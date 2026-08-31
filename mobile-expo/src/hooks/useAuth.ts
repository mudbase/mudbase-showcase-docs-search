import { useAuthStore } from "@/stores/authStore";
import { isRealUser } from "@/lib/rbac";
import type { MudbaseUser } from "@/api/schemas";

interface UseAuthReturn {
  user: MudbaseUser | null;
  /** A real, signed-in author - distinct from the always-present anonymous guest session. */
  isAuthenticated: boolean;
  isInitializing: boolean;
  isSubmitting: boolean;
  error: string | null;
  login: (email: string, password: string) => Promise<boolean>;
  logout: () => Promise<void>;
  clearError: () => void;
}

/** Thin selector hook over the auth store - screens read/act through this, never the store directly. */
export function useAuth(): UseAuthReturn {
  const user = useAuthStore((s) => s.user);
  const isInitializing = useAuthStore((s) => s.isInitializing);
  const isSubmitting = useAuthStore((s) => s.isSubmitting);
  const error = useAuthStore((s) => s.error);
  const login = useAuthStore((s) => s.login);
  const logout = useAuthStore((s) => s.logout);
  const clearError = useAuthStore((s) => s.clearError);

  return {
    user,
    isAuthenticated: isRealUser(user),
    isInitializing,
    isSubmitting,
    error,
    login,
    logout,
    clearError,
  };
}
