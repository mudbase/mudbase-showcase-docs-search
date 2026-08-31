import { isAxiosError, type AxiosResponse } from "axios";
import { AuthenticationApi, Configuration, DataApi } from "mudbase-sdk";
import { z } from "zod";
import { MUDBASE_PROJECT_ID, MUDBASE_URL } from "@/config/env";
import { secureStorage, STORAGE_KEYS } from "./secureStorage";
import { authResultSchema, mudbaseUserSchema, type AuthResult, type MudbaseUser } from "./schemas";

/**
 * Thin, typed wrapper around the real generated `mudbase-sdk` - same mechanism the sibling
 * `mudbase-showcase-kanban/mobile-expo` and `mudbase-showcase-social/mobile-expo` ports use: real
 * generated `*Api` class instances (`AuthenticationApi`/`DataApi`), not a unified client the SDK
 * doesn't ship. Every generated method takes a single `requestParameters` object (e.g.
 * `loginLocalUser({ loginLocalUserRequest: {...} })`), NOT positional arguments - calling
 * positionally throws a client-side `RequiredError` before any request reaches the network.
 *
 * This file adds on top of the generated SDK: token storage (SecureStore, never AsyncStorage), a
 * single-retry-on-401 refresh with in-flight dedupe (ported from web/src/lib/mudbase.ts's
 * `refreshInFlight` pattern - refresh tokens rotate on every use and a reused one revokes the
 * whole session, so concurrent 401s must share one refresh call, never race), and zod-validated
 * narrowing of the generated response types where they under-describe the real payload (see
 * schemas.ts).
 *
 * Unlike the kanban port (which has no anonymous session at all), this app's auth model matches
 * the web reference and the sibling social port: every collection read requires *some* JWT
 * (verified live against this exact project - every read 401s with zero auth, even with the
 * project's own `pk_` publishable key), so a bootstrap anonymous session lets guests browse and
 * search without a login screen. Creating/editing/deleting documents and using Ask AI still
 * require a real, signed-in `customer` account.
 */

export class MudbaseApiError extends Error {
  constructor(
    message: string,
    public readonly statusCode: number,
    public readonly code?: string,
  ) {
    super(message);
    this.name = "MudbaseApiError";
  }
}

export interface PaginationMeta {
  page: number;
  limit: number;
  total: number;
  totalPages: number;
  hasMore: boolean;
}

interface ListDocumentsOptions {
  filter?: Record<string, unknown>;
  sort?: string;
  page?: number;
  limit?: number;
}

function toApiError(err: unknown): MudbaseApiError {
  if (isAxiosError(err)) {
    const status = err.response?.status ?? 0;
    const body = err.response?.data as { error?: string; message?: string; code?: string } | undefined;
    return new MudbaseApiError(body?.error ?? body?.message ?? err.message, status, body?.code);
  }
  if (err instanceof Error) return new MudbaseApiError(err.message, 0);
  return new MudbaseApiError("Unknown error", 0);
}

class MudbaseClient {
  private token: string | null = null;
  private refreshTokenValue: string | null = null;
  private refreshing: Promise<void> | null = null;

  private readonly configuration = new Configuration({
    basePath: MUDBASE_URL,
    accessToken: async (): Promise<string> => this.token ?? "",
  });

  private readonly authApi = new AuthenticationApi(this.configuration);
  private readonly dataApi = new DataApi(this.configuration);

  /** True for both a real signed-in author and the bootstrap guest - see isRealUser() in lib/rbac.ts for the distinction the UI cares about. */
  isAuthenticated(): boolean {
    return this.token !== null;
  }

  /** Loads any persisted tokens from SecureStore at app boot. Call once, before getSession(). */
  async restoreTokens(): Promise<boolean> {
    const [token, refreshTokenValue] = await Promise.all([
      secureStorage.get(STORAGE_KEYS.ACCESS_TOKEN),
      secureStorage.get(STORAGE_KEYS.REFRESH_TOKEN),
    ]);
    if (!token || !refreshTokenValue) return false;
    this.token = token;
    this.refreshTokenValue = refreshTokenValue;
    return true;
  }

  getToken(): string | null {
    return this.token;
  }

  private async persistTokens(token: string, refreshTokenValue: string): Promise<void> {
    this.token = token;
    this.refreshTokenValue = refreshTokenValue;
    await Promise.all([
      secureStorage.set(STORAGE_KEYS.ACCESS_TOKEN, token),
      secureStorage.set(STORAGE_KEYS.REFRESH_TOKEN, refreshTokenValue),
    ]);
  }

  private async clearTokens(): Promise<void> {
    this.token = null;
    this.refreshTokenValue = null;
    await Promise.all([
      secureStorage.delete(STORAGE_KEYS.ACCESS_TOKEN),
      secureStorage.delete(STORAGE_KEYS.REFRESH_TOKEN),
    ]);
  }

  /**
   * Refresh tokens rotate on every use and a reused one revokes the session (platform
   * reuse-detection) - this in-flight promise is shared across concurrent 401s to guarantee at
   * most one refresh call per expiry, never a stampede that would trip reuse-detection itself.
   * Faithful port of web/src/lib/mudbase.ts's `refreshAccessToken()` / `refreshInFlight`.
   */
  private async refreshSession(): Promise<void> {
    if (!this.refreshTokenValue) {
      throw new MudbaseApiError("No refresh token available - sign in again.", 401);
    }
    if (!this.refreshing) {
      this.refreshing = (async (): Promise<void> => {
        const res = await this.authApi.refreshToken({
          refreshTokenRequest: { refreshToken: this.refreshTokenValue as string },
        });
        const { token, refreshToken: nextRefreshToken } = res.data;
        if (!token || !nextRefreshToken) {
          throw new MudbaseApiError("Refresh response was missing new tokens.", 500);
        }
        await this.persistTokens(token, nextRefreshToken);
      })().finally(() => {
        this.refreshing = null;
      });
    }
    return this.refreshing;
  }

  private async withAuthRetry<T>(fn: () => Promise<AxiosResponse<T>>): Promise<T> {
    try {
      const res = await fn();
      return res.data;
    } catch (err) {
      if (isAxiosError(err) && err.response?.status === 401 && this.refreshTokenValue) {
        await this.refreshSession();
        const retried = await fn();
        return retried.data;
      }
      throw toApiError(err);
    }
  }

  // ─── Auth ─────────────────────────────────────────────────────────────────

  /**
   * Every collection read requires *some* JWT - verified live against this exact project (see
   * ../plan/build-plan.md): an anonymous session satisfies that without forcing a login screen on
   * first launch, exactly like the web reference app's guest-browsing bootstrap. Publishing,
   * editing, deleting, and Ask AI still require a real, signed-in customer account - enforced both
   * by Mudbase's own collection permissions and by this app's isRealUser() UI gate.
   */
  async createAnonymousSession(): Promise<MudbaseUser> {
    try {
      const res = await this.authApi.createAnonymousSession({
        createAnonymousSessionRequest: { projectId: MUDBASE_PROJECT_ID },
      });
      const parsed: AuthResult = authResultSchema.parse(res.data);
      if (!parsed.token || !parsed.refreshToken || !parsed.user) {
        throw new MudbaseApiError("Anonymous session response was missing tokens or user.", 500);
      }
      await this.persistTokens(parsed.token, parsed.refreshToken);
      return parsed.user;
    } catch (err) {
      throw toApiError(err);
    }
  }

  async login(email: string, password: string): Promise<MudbaseUser> {
    try {
      const res = await this.authApi.loginLocalUser({
        loginLocalUserRequest: { email, password, projectId: MUDBASE_PROJECT_ID },
      });
      const { token, refreshToken: refreshTokenValue } = res.data;
      if (!token || !refreshTokenValue) {
        throw new MudbaseApiError("Login response was missing tokens.", 500);
      }
      const user = mudbaseUserSchema.parse(res.data.user);
      await this.persistTokens(token, refreshTokenValue);
      return user;
    } catch (err) {
      if (err instanceof MudbaseApiError) throw err;
      if (isAxiosError(err) && err.response?.status === 403) {
        const body = err.response.data as { code?: string; error?: string } | undefined;
        if (body?.code === "EMAIL_VERIFICATION_REQUIRED") {
          throw new MudbaseApiError("Please verify your email before signing in.", 403, body.code);
        }
      }
      throw toApiError(err);
    }
  }

  async logout(): Promise<void> {
    try {
      await this.authApi.logoutLocalUser();
    } catch {
      // Best-effort server-side revoke - always clear local tokens regardless.
    } finally {
      await this.clearTokens();
    }
  }

  async getSession(): Promise<MudbaseUser | null> {
    if (!this.token) return null;
    try {
      const body = await this.withAuthRetry(() => this.authApi.getLocalSession({ projectId: MUDBASE_PROJECT_ID }));
      const parsed: AuthResult = authResultSchema.parse(body);
      return parsed.user ? mudbaseUserSchema.parse(parsed.user) : null;
    } catch {
      await this.clearTokens();
      return null;
    }
  }

  // ─── Collections (Data API) ────────────────────────────────────────────────

  async listDocuments<T>(
    schema: z.ZodType<T>,
    collectionId: string,
    options: ListDocumentsOptions = {},
  ): Promise<{ data: T[]; pagination: PaginationMeta }> {
    const filterStr =
      options.filter && Object.keys(options.filter).length > 0 ? JSON.stringify(options.filter) : undefined;
    const body = await this.withAuthRetry(() =>
      this.dataApi.listData({
        projectId: MUDBASE_PROJECT_ID,
        collectionId,
        page: options.page,
        limit: options.limit,
        sort: options.sort,
        filter: filterStr,
      }),
    );
    const list = z.array(schema).parse(body.data ?? []);
    const page = body.pagination?.page ?? 1;
    const totalPages = body.pagination?.totalPages ?? 1;
    return {
      data: list,
      pagination: {
        page,
        limit: body.pagination?.limit ?? list.length,
        total: body.pagination?.total ?? list.length,
        totalPages,
        hasMore: page < totalPages,
      },
    };
  }

  async getDocument<T>(schema: z.ZodType<T>, collectionId: string, documentId: string): Promise<T> {
    const body = await this.withAuthRetry(() =>
      this.dataApi.getData({ projectId: MUDBASE_PROJECT_ID, collectionId, documentId }),
    );
    return schema.parse(body.data);
  }

  async createDocument<T>(schema: z.ZodType<T>, collectionId: string, data: Record<string, unknown>): Promise<T> {
    const body = await this.withAuthRetry(() =>
      this.dataApi.createData({ projectId: MUDBASE_PROJECT_ID, collectionId, body: data }),
    );
    return schema.parse(body.data);
  }

  async updateDocument<T>(
    schema: z.ZodType<T>,
    collectionId: string,
    documentId: string,
    data: Record<string, unknown>,
  ): Promise<T> {
    const body = await this.withAuthRetry(() =>
      this.dataApi.updateData({ projectId: MUDBASE_PROJECT_ID, collectionId, documentId, body: data }),
    );
    return schema.parse(body.data);
  }

  async deleteDocument(collectionId: string, documentId: string): Promise<void> {
    await this.withAuthRetry(() =>
      this.dataApi.deleteData({ projectId: MUDBASE_PROJECT_ID, collectionId, documentId }),
    );
  }
}

export const mudbaseClient = new MudbaseClient();
