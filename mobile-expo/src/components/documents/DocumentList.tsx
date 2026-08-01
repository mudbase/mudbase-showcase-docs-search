import { FlatList, Text, View } from "react-native";
import { FileQuestion } from "lucide-react-native";
import { DocumentCard } from "@/components/documents/DocumentCard";
import type { DocumentRecord } from "@/api/schemas";

export function DocumentList({ documents }: { documents: DocumentRecord[] }): React.JSX.Element {
  if (documents.length === 0) {
    return (
      <View className="items-center justify-center gap-2 rounded-lg border border-dashed border-border px-6 py-16">
        <FileQuestion size={28} color="#606876" />
        <Text className="text-sm font-medium text-foreground">No documents match your search</Text>
        <Text className="text-center text-xs text-muted-foreground">
          Try a different keyword, or add the first document.
        </Text>
      </View>
    );
  }

  return (
    <FlatList
      data={documents}
      keyExtractor={(document) => document._id}
      renderItem={({ item }) => <DocumentCard document={item} />}
      contentContainerClassName="gap-3 pb-8"
      scrollEnabled={false}
    />
  );
}
