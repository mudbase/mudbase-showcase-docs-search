import { useState } from "react";
import { ScrollView } from "react-native";
import { router } from "expo-router";
import { useCreateDocument } from "@/hooks/useDocuments";
import { DocumentForm, type DocumentFormValues } from "@/components/documents/DocumentForm";
import { MudbaseApiError } from "@/api/client";

export default function NewDocumentScreen(): React.JSX.Element {
  const createDocument = useCreateDocument();
  const [submitError, setSubmitError] = useState<string | null>(null);

  const onSubmit = async (values: DocumentFormValues): Promise<void> => {
    setSubmitError(null);
    try {
      const created = await createDocument.mutateAsync({
        title: values.title,
        content: values.content,
        tags: values.tags ?? "",
      });
      router.replace(`/documents/${created._id}`);
    } catch (err) {
      setSubmitError(err instanceof MudbaseApiError ? err.message : "Failed to create document");
    }
  };

  return (
    <ScrollView className="flex-1 bg-background" contentContainerClassName="gap-4 p-4" keyboardShouldPersistTaps="handled">
      <DocumentForm
        submitLabel="Publish document"
        submittingLabel="Publishing…"
        isSubmitting={createDocument.isPending}
        error={submitError}
        onSubmit={onSubmit}
      />
    </ScrollView>
  );
}
