const MUDBASE_BASE_URL = "https://cloud.mudbase.dev"

/**
 * This project ships Mudbase's single default starter application role - slug "customer",
 * signupEndpoint "customer" (same verified-live convention documented in the sibling
 * mudbase-showcase-social app: signup against "user" 404s with "Role not found", signup against
 * "customer" succeeds). There is only one role in this app, so it is hardcoded here rather than
 * exposed as a caller-supplied parameter.
 */
const APP_ROLE = "customer"

export interface MudbaseConfig {
  baseUrl?: string
  projectId: string
}

export interface RegisterParams {
  email: string
  password: string
  firstName: string
  lastName: string
  /** Required by Mudbase's registration validator - a direct API call without it is rejected. */
  agreedToTerms: boolean
}

export interface LoginParams {
  email: string
  password: string
}

export interface AuthResponse {
  message: string
  token?: string
  refreshToken?: string
  expiresIn?: number
  user: UserObject
  /**
   * True when the project requires email verification before login. Callers must not treat a
   * successful register() as a signed-in session when this is true.
   */
  requireVerification?: boolean
}

export interface UserObject {
  id: string
  email: string
  firstName: string
  lastName: string
  role?: string
  customRole?: string | null
  emailVerified: boolean
  isAnonymous?: boolean
}

export interface SessionResponse {
  user: UserObject
  token: string
}

export interface Document {
  _id: string
  createdAt: string
  updatedAt: string
  [key: string]: unknown
}

export interface PaginationMeta {
  page: number
  limit: number
  total: number
  totalPages: number
  hasMore: boolean
}

export interface ListResponse<T> {
  data: T[]
  pagination: PaginationMeta
}

export type MongoFilter = Record<string, unknown>

export interface QueryParams {
  filter?: MongoFilter
  sort?: string
  page?: number
  limit?: number
  fields?: string[]
}

export class MudbaseError extends Error {
  constructor(
    message: string,
    public statusCode: number,
    public details?: unknown,
  ) {
    super(message)
    this.name = "MudbaseError"
  }
}

/** Narrows MudbaseError.details to read a server-provided error `code` (e.g. EMAIL_VERIFICATION_REQUIRED). */
export function errorCode(err: unknown): string | undefined {
  if (!(err instanceof MudbaseError)) return undefined
  const details = err.details as { code?: string } | undefined
  return details?.code
}

export class MudbaseClient {
  private baseUrl: string
  private projectId: string
  private token: string | null = null
  private refreshToken: string | null = null
  // Refresh tokens rotate on every use (single-use, platform-enforced) - if two requests both
  // hit a 401 at once, only the first refresh call may succeed since the second would present
  // an already-rotated-away token. This promise lets concurrent callers await the same in-flight
  // refresh instead of racing each other into failure.
  private refreshInFlight: Promise<string> | null = null

  constructor(config: MudbaseConfig) {
    this.baseUrl = config.baseUrl ?? MUDBASE_BASE_URL
    this.projectId = config.projectId
    if (typeof window !== "undefined") {
      this.token = localStorage.getItem("mudbase_token")
      this.refreshToken = localStorage.getItem("mudbase_refresh_token")
    }
  }

  getProjectId(): string {
    return this.projectId
  }

  setToken(token: string, refreshToken?: string): void {
    this.token = token
    if (typeof window !== "undefined") {
      localStorage.setItem("mudbase_token", token)
    }
    if (refreshToken) {
      this.refreshToken = refreshToken
      if (typeof window !== "undefined") {
        localStorage.setItem("mudbase_refresh_token", refreshToken)
      }
    }
  }

  clearToken(): void {
    this.token = null
    this.refreshToken = null
    if (typeof window !== "undefined") {
      localStorage.removeItem("mudbase_token")
      localStorage.removeItem("mudbase_refresh_token")
    }
  }

  getToken(): string | null {
    return this.token
  }

  private async refreshAccessToken(): Promise<string> {
    if (this.refreshInFlight) return this.refreshInFlight

    this.refreshInFlight = (async () => {
      if (!this.refreshToken) throw new MudbaseError("No refresh token available", 401)
      const res = await fetch(`${this.baseUrl}/api/auth/refresh`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ refreshToken: this.refreshToken }),
      })
      if (!res.ok) {
        this.clearToken()
        throw new MudbaseError("Session expired - please log in again", 401)
      }
      const body = (await res.json()) as { token: string; refreshToken: string }
      this.setToken(body.token, body.refreshToken)
      return body.token
    })()

    try {
      return await this.refreshInFlight
    } finally {
      this.refreshInFlight = null
    }
  }

  private async request<T>(
    method: string,
    path: string,
    body?: unknown,
    options: { auth?: boolean; retriedAfterRefresh?: boolean } = {},
  ): Promise<T> {
    const headers: Record<string, string> = { "Content-Type": "application/json" }
    if (options.auth !== false && this.token) {
      headers["Authorization"] = `Bearer ${this.token}`
    }

    const res = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    })

    if (res.status === 401 && options.auth !== false && this.refreshToken && !options.retriedAfterRefresh) {
      await this.refreshAccessToken()
      return this.request<T>(method, path, body, { ...options, retriedAfterRefresh: true })
    }

    if (!res.ok) {
      const error = (await res.json().catch(() => ({ error: res.statusText }))) as { error?: string; message?: string }
      throw new MudbaseError(error.error ?? error.message ?? "Request failed", res.status, error)
    }

    const text = await res.text()
    return text ? (JSON.parse(text) as T) : ({} as T)
  }

  // ─── Auth ──────────────────────────────────────────────────────────────────

  async register(params: RegisterParams): Promise<AuthResponse> {
    // The signup validator explicitly rejects `role`/`customRole` in the request body
    // (`.unknown(false)`, a deliberate anti-role-injection control) - the role is taken only
    // from the URL path segment below, so it must not be spread into the body too.
    const res = await this.request<AuthResponse>(
      "POST",
      `/api/auth/local/signup/${APP_ROLE}`,
      { ...params, projectId: this.projectId },
      { auth: false },
    )
    if (res.token) this.setToken(res.token)
    return res
  }

  async login(params: LoginParams): Promise<AuthResponse> {
    const res = await this.request<AuthResponse>(
      "POST",
      "/api/auth/local/login",
      { ...params, projectId: this.projectId },
      { auth: false },
    )
    if (res.token) this.setToken(res.token)
    return res
  }

  async logout(): Promise<void> {
    try {
      await this.request<void>("POST", "/api/auth/logout", { projectId: this.projectId })
    } finally {
      this.clearToken()
    }
  }

  async getSession(): Promise<SessionResponse> {
    return this.request<SessionResponse>("GET", `/api/auth/session?projectId=${this.projectId}`)
  }

  /** Public endpoint (no auth) - completes the link sent in the verification email. */
  async verifyEmail(token: string): Promise<{ message: string }> {
    return this.request<{ message: string }>("POST", "/api/users/verify-email", { token }, { auth: false })
  }

  /**
   * Verified live against this project: every collection read 401s with absolutely no auth at
   * all, even with the project's own publishable key sent as X-API-Key. An anonymous session
   * lets guests browse the document library without requiring a real signup - see
   * plan/build-plan.md "Known limitations".
   */
  async loginAnonymous(): Promise<AuthResponse> {
    const res = await this.request<AuthResponse>(
      "POST",
      "/api/auth/anonymous",
      { projectId: this.projectId },
      { auth: false },
    )
    if (res.token) this.setToken(res.token)
    return res
  }

  // ─── Collections ─────────────────────────────────────────────────────────────

  private dataPath(collectionId: string, documentId?: string): string {
    const base = `/api/data/projects/${this.projectId}/collections/${collectionId}/data`
    return documentId ? `${base}/${documentId}` : base
  }

  async getDocuments<T = Document>(collectionId: string, query?: QueryParams): Promise<ListResponse<T>> {
    const params = new URLSearchParams()
    if (query?.filter && Object.keys(query.filter).length > 0) {
      params.set("filter", JSON.stringify(query.filter))
    }
    if (query?.sort) params.set("sort", query.sort)
    if (query?.page !== undefined) params.set("page", String(query.page))
    if (query?.limit !== undefined) params.set("limit", String(query.limit))
    if (query?.fields?.length) params.set("fields", query.fields.join(","))

    const qs = params.toString()
    return this.request<ListResponse<T>>("GET", qs ? `${this.dataPath(collectionId)}?${qs}` : this.dataPath(collectionId))
  }

  async getDocument<T = Document>(collectionId: string, documentId: string): Promise<T> {
    const res = await this.request<{ data: T }>("GET", this.dataPath(collectionId, documentId))
    return res.data
  }

  async createDocument<T = Document>(collectionId: string, data: Record<string, unknown>): Promise<T> {
    const res = await this.request<{ message: string; data: T }>("POST", this.dataPath(collectionId), data)
    return res.data
  }

  async updateDocument<T = Document>(
    collectionId: string,
    documentId: string,
    data: Record<string, unknown>,
  ): Promise<T> {
    const res = await this.request<{ message: string; data: T }>("PATCH", this.dataPath(collectionId, documentId), data)
    return res.data
  }

  async deleteDocument(collectionId: string, documentId: string): Promise<void> {
    await this.request<{ message: string }>("DELETE", this.dataPath(collectionId, documentId))
  }
}

let _client: MudbaseClient | null = null

export function getMudbaseClient(): MudbaseClient {
  if (!_client) throw new Error("Mudbase client not initialized. Call initMudbase() first.")
  return _client
}

export function initMudbase(config: MudbaseConfig): MudbaseClient {
  _client = new MudbaseClient(config)
  return _client
}
