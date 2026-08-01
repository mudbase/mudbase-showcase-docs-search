import { useState } from "react";
import { ActivityIndicator, Alert, ScrollView, Text, View } from "react-native";
import { router, useLocalSearchParams } from "expo-router";
import { Pencil, Trash2 } from "lucide-react-native";
import { useAuth } from "@/hooks/useAuth";
import { useDeleteDocument, useDocument } from "@/hooks/useDocuments";
import { isDocumentOwner } from "@/lib/rbac";
import { parseTags, formatDateTime } from "@/lib/format";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Separator } from "@/components/ui/Separator";

export default function DocumentDetailScreen(): React.JSX.Element {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { user } = useAuth();
  const documentQuery = useDocument(id);
  const deleteDocument = useDeleteDocument();
  const [deleting, setDeleting] = useState(false);

  if (documentQuery.isLoading) {
    return (
      <View className="flex-1 items-center justify-center bg-background py-16">
        <ActivityIndicator size="large" color="#4a43db" />
      </View>
    );
  }

  if (documentQuery.isError || !documentQuery.data) {
    return (
      <View className="flex-1 items-center justify-center bg-background px-6 py-16">
        <Text className="text-center text-sm text-destructive">This document isn&apos;t available.</Text>
      </View>
    );
  }

  const document = documentQuery.data;
  const tags = parseTags(document.tags);
  const isOwner = isDocumentOwner(user, document);

  const handleDelete = (): void => {
    Alert.alert("Delete this document?", "This cannot be undone.", [
      { text: "Cancel", style: "cancel" },
      {
        text: "Delete",
        style: "destructive",
        onPress: () => {
          setDeleting(true);
          deleteDocument.mutate(document._id, {
            onSuccess: () => router.replace("/"),
            onSettled: () => setDeleting(false),
          });
        },
      },
    ]);
  };

  return (
    <ScrollView className="flex-1 bg-background" contentContainerClassName="gap-4 p-4">
      <View className="gap-3">
        <View className="flex-row items-start justify-between gap-4">
          <Text className="flex-1 text-2xl font-semibold text-foreground">{document.title}</Text>
        </View>
        {isOwner && (
          <View className="flex-row gap-2">
            <Button
              variant="outline"
              size="sm"
              className="flex-1"
              icon={<Pencil size={14} color="#181c25" />}
              onPress={() => router.push(`/documents/${document._id}/edit`)}
            >
              Edit
            </Button>
            <Button
              variant="destructive"
              size="sm"
              className="flex-1"
              icon={<Trash2 size={14} color="#f9f9fb" />}
              isLoading={deleting}
              onPress={handleDelete}
            >
              {deleting ? "Deleting…" : "Delete"}
            </Button>
          </View>
        )}
        {tags.length > 0 && (
          <View className="flex-row flex-wrap gap-1.5">
            {tags.map((tag) => (
              <Badge key={tag} variant="secondary">
                {tag}
              </Badge>
            ))}
          </View>
        )}
        <Text className="text-sm text-muted-foreground">
          {document.authorName} · {formatDateTime(document.createdAt)}
        </Text>
      </View>

      <Separator />

      <Text className="text-sm leading-relaxed text-foreground">{document.content}</Text>
    </ScrollView>
  );
}
