import * as SecureStore from "expo-secure-store";
import { Platform } from "react-native";

/**
 * Auth tokens live here, never in AsyncStorage/MMKV — a hard security rule for this project (see
 * builder CLAUDE.md "Mobile" security non-negotiables). SecureStore wraps iOS Keychain / Android
 * Keystore. On web, `expo-secure-store`'s own `ExpoSecureStore.web.ts` module has every method
 * undefined (not a localStorage shim), so calling it there throws before anything reaches storage
 * — the same gap the sibling `mudbase-showcase-kanban/mobile-expo` port documents; `IS_WEB`
 * routes storage straight to `window.localStorage` instead, purely as a local-smoke-test / QA
 * fallback, never a production path.
 */
const IS_WEB = Platform.OS === "web";

if (IS_WEB) {
  // eslint-disable-next-line no-console
  console.warn("[secureStorage] Running on web — falling back to localStorage, not secure for production.");
}

const SECURE_STORE_OPTIONS: SecureStore.SecureStoreOptions = {
  keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY,
};

export const STORAGE_KEYS = {
  ACCESS_TOKEN: "mudbase.accessToken",
  REFRESH_TOKEN: "mudbase.refreshToken",
} as const;

export const secureStorage = {
  async set(key: string, value: string): Promise<void> {
    if (IS_WEB) {
      try {
        window.localStorage.setItem(key, value);
      } catch (error: unknown) {
        const message = error instanceof Error ? error.message : String(error);
        throw new Error(`localStorage write failed for key "${key}": ${message}`);
      }
      return;
    }
    try {
      await SecureStore.setItemAsync(key, value, SECURE_STORE_OPTIONS);
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : String(error);
      throw new Error(`SecureStore write failed for key "${key}": ${message}`);
    }
  },

  async get(key: string): Promise<string | null> {
    if (IS_WEB) {
      try {
        return window.localStorage.getItem(key);
      } catch (error: unknown) {
        const message = error instanceof Error ? error.message : String(error);
        // eslint-disable-next-line no-console
        console.warn(`[secureStorage] Failed to read key "${key}": ${message}`);
        return null;
      }
    }
    try {
      return await SecureStore.getItemAsync(key, SECURE_STORE_OPTIONS);
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : String(error);
      // eslint-disable-next-line no-console
      console.warn(`[secureStorage] Failed to read key "${key}": ${message}`);
      return null;
    }
  },

  async delete(key: string): Promise<void> {
    if (IS_WEB) {
      try {
        window.localStorage.removeItem(key);
      } catch {
        // Key may already be absent — not an error condition worth surfacing.
      }
      return;
    }
    try {
      await SecureStore.deleteItemAsync(key, SECURE_STORE_OPTIONS);
    } catch {
      // Key may already be absent — not an error condition worth surfacing.
    }
  },
};
