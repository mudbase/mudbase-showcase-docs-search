import { Text, View } from "react-native";
import { router } from "expo-router";
import { LogIn, LogOut } from "lucide-react-native";
import { useAuth } from "@/hooks/useAuth";
import { IconButton } from "@/components/ui/IconButton";

/**
 * A small per-screen header (title, current-user name, sign-in/out button) shown at the top of
 * every tab screen's content. Mirrors the content of web/src/components/layout/Header.tsx — Expo
 * Router's native stack header does not carry auth state naturally and there is no meaningful
 * mobile equivalent of the web reference's persistent app shell across a bottom-tab layout, so
 * this renders inline instead.
 */
export function AppHeader({ title }: { title: string }): React.JSX.Element {
  const { user, isAuthenticated, logout } = useAuth();

  return (
    <View className="flex-row items-center justify-between px-4 pb-3 pt-2">
      <View className="gap-0.5">
        <Text className="text-2xl font-bold text-foreground">{title}</Text>
        {isAuthenticated && user && (
          <Text className="text-xs text-muted-foreground">
            {user.firstName} {user.lastName}
          </Text>
        )}
        {!isAuthenticated && <Text className="text-xs text-muted-foreground">Browsing as guest</Text>}
      </View>
      {isAuthenticated ? (
        <IconButton accessibilityLabel="Sign out" onPress={() => void logout()}>
          <LogOut size={18} color="#606876" />
        </IconButton>
      ) : (
        <IconButton accessibilityLabel="Sign in" onPress={() => router.push("/login")}>
          <LogIn size={18} color="#4a43db" />
        </IconButton>
      )}
    </View>
  );
}
