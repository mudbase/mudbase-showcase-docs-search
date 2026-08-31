import { ScrollView, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { AppHeader } from "@/components/layout/AppHeader";
import { AskAIPanel } from "@/components/ask/AskAIPanel";
import { RecentSearches } from "@/components/ask/RecentSearches";

export default function AskScreen(): React.JSX.Element {
  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      <AppHeader title="Ask AI" />
      <ScrollView contentContainerClassName="gap-6 px-4 pb-8" keyboardShouldPersistTaps="handled">
        <Text className="text-sm text-muted-foreground">
          Ask a question in plain language. The app finds the most relevant documents in the
          library, then asks an LLM to answer strictly from their content - with citations back to
          the source documents.
        </Text>
        <AskAIPanel />
        <View>
          <RecentSearches />
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}
