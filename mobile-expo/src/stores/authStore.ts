import { create } from "zustand";
import { mudbaseClient, MudbaseApiError } from "@/api/client";
import type { MudbaseUser } from "@/api/schemas";

interface AuthState {
  user: MudbaseUser | null;
  /** True only while the boot-time restoreTokens()+getSession()(+bootstrap anonymous) sequence is running. */
  isInitializing: boolean;
  isSubmitting: boolean;
  error: string | null;
  initialize: () => Promise<void>;
  login: (email: string, password: string) => Promise<boolean>;
  logout: () => Promise<void>;
  clearError: () => void;
}

function messageFrom(err: unknown, fallback: string): string {
  return err instanceof MudbaseApiError ? err.message : fallback;
}

/**
 * A plain in-memory zustand store, not persisted via MMKV/AsyncStorage — the only durable state is
 * the token pair in SecureStore (mudbaseClient owns that). Mirrors
 * web/src/lib/mudbase-provider.tsx's bootstrap: every cold start (and every logout) ends with
 * *some* session established — a real signed-in author if valid tokens were restored, otherwise a
 * fresh anonymous session so the library's public-read permission resolves without forcing a
 * login screen. `isRealUser()` (lib/rbac.ts) is what distinguishes the two for UI gating.
 */
export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  isInitializing: true,
  isSubmitting: false,
  error: null,

  initialize: async (): Promise<void> => {
    set({ isInitializing: true });
    const hasTokens = await mudbaseClient.restoreTokens();
    if (hasTokens) {
      const user = await mudbaseClient.getSession();
      if (user) {
        set({ user, isInitializing: false });
        return;
      }
      // Restored tokens were invalid/expired past refresh — fall through to a fresh anonymous
      // session below, same as a first-ever launch.
    }
    try {
      const user = await mudbaseClient.createAnonymousSession();
      set({ user, isInitializing: false });
    } catch (err) {
      set({ user: null, error: messageFrom(err, "Could not connect to Mudbase."), isInitializing: false });
    }
  },

  login: async (email, password): Promise<boolean> => {
    set({ isSubmitting: true, error: null });
    try {
      const user = await mudbaseClient.login(email, password);
      set({ user, isSubmitting: false });
      return true;
    } catch (err) {
      set({ error: messageFrom(err, "Login failed. Check your email and password."), isSubmitting: false });
      return false;
    }
  },

  logout: async (): Promise<void> => {
    set({ isSubmitting: true });
    await mudbaseClient.logout();
    try {
      const user = await mudbaseClient.createAnonymousSession();
      set({ user, isSubmitting: false });
    } catch {
      set({ user: null, isSubmitting: false });
    }
  },

  clearError: (): void => set({ error: null }),
}));
