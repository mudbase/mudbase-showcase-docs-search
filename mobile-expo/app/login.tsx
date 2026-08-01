import { ScrollView, Text, View } from "react-native";
import { router } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { LoginForm } from "@/components/auth/LoginForm";

export default function LoginScreen(): React.JSX.Element {
  return (
    <SafeAreaView className="flex-1 bg-background" edges={["bottom"]}>
      <ScrollView contentContainerClassName="flex-grow justify-center px-6 py-10" keyboardShouldPersistTaps="handled">
        <View className="mb-8 gap-1">
          <Text className="text-3xl font-semibold text-foreground">Docs Search</Text>
          <Text className="text-muted-foreground">Sign in to publish, edit, or delete documents.</Text>
        </View>
        {/* router.back() — /login is reached by an explicit "Sign in" tap from a guest session
            that already has a valid anonymous session underneath it, unlike the kanban port
            where /login is the only reachable screen for an unauthenticated user. */}
        <LoginForm onSuccess={() => (router.canGoBack() ? router.back() : router.replace("/"))} />
      </ScrollView>
    </SafeAreaView>
  );
}
