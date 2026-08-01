import { useMemo, useState } from "react";
import { ActivityIndicator, ScrollView, Text, View } from "react-native";
import { router } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { PlusCircle } from "lucide-react-native";
import { useAuth } from "@/hooks/useAuth";
import { useDocumentsList } from "@/hooks/useDocuments";
import { matchesSearchTerm } from "@/lib/retrieval";
import { AppHeader } from "@/components/layout/AppHeader";
import { SearchBar } from "@/components/documents/SearchBar";
import { DocumentList } from "@/components/documents/DocumentList";
import { Button } from "@/components/ui/Button";

export default function LibraryScreen(): React.JSX.Element {
  const { isAuthenticated } = useAuth();
  const [searchTerm, setSearchTerm] = useState("");
  const documentsQuery = useDocumentsList();

  const filtered = useMemo(
    () => (documentsQuery.data?.data ?? []).filter((document) => matchesSearchTerm(document, searchTerm)),
    [documentsQuery.data, searchTerm],
  );

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      <AppHeader title="Document library" />
      <ScrollView contentContainerClassName="gap-4 px-4 pb-8" keyboardShouldPersistTaps="handled">
        <SearchBar value={searchTerm} onChange={setSearchTerm} />

        {isAuthenticated && (
          <Button variant="outline" icon={<PlusCircle size={16} color="#4a43db" />} onPress={() => router.push("/documents/new")}>
            New document
          </Button>
        )}

        {documentsQuery.isLoading ? (
          <View className="items-center py-12">
            <ActivityIndicator size="large" color="#4a43db" />
          </View>
        ) : documentsQuery.isError ? (
          <Text className="py-12 text-center text-sm text-destructive">
            Failed to load documents. Pull to refresh or restart the app.
          </Text>
        ) : (
          <DocumentList documents={filtered} />
        )}
      </ScrollView>
    </SafeAreaView>
  );
}
