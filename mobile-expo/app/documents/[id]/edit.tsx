import { useState } from "react";
import { ActivityIndicator, ScrollView, Text, View } from "react-native";
import { router, useLocalSearchParams } from "expo-router";
import { useAuth } from "@/hooks/useAuth";
import { useDocument, useUpdateDocument } from "@/hooks/useDocuments";
import { isDocumentOwner } from "@/lib/rbac";
import { DocumentForm, type DocumentFormValues } from "@/components/documents/DocumentForm";
import { MudbaseApiError } from "@/api/client";

export default function EditDocumentScreen(): React.JSX.Element {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { user } = useAuth();
  const documentQuery = useDocument(id);
  const updateDocument = useUpdateDocument();
  const [submitError, setSubmitError] = useState<string | null>(null);

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

  if (!isDocumentOwner(user, document)) {
    return (
      <View className="flex-1 items-center justify-center bg-background px-6 py-16">
        <Text className="text-center text-sm text-muted-foreground">You can only edit documents you authored.</Text>
      </View>
    );
  }

  const onSubmit = async (values: DocumentFormValues): Promise<void> => {
    setSubmitError(null);
    try {
      await updateDocument.mutateAsync({
        documentId: document._id,
        title: values.title,
        content: values.content,
        tags: values.tags ?? "",
      });
      router.replace(`/documents/${document._id}`);
    } catch (err) {
      setSubmitError(err instanceof MudbaseApiError ? err.message : "Failed to update document");
    }
  };

  return (
    <ScrollView className="flex-1 bg-background" contentContainerClassName="gap-4 p-4" keyboardShouldPersistTaps="handled">
      <DocumentForm
        defaultValues={{ title: document.title, content: document.content, tags: document.tags ?? "" }}
        submitLabel="Save changes"
        submittingLabel="Saving…"
        isSubmitting={updateDocument.isPending}
        error={submitError}
        onSubmit={onSubmit}
      />
    </ScrollView>
  );
}
