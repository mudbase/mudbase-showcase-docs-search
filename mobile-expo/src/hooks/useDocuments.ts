import { useCallback } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { mudbaseClient } from "@/api/client";
import { documentRecordSchema, type DocumentRecord } from "@/api/schemas";
import { DOCUMENTS_COLLECTION_ID } from "@/config/env";
import { useAuth } from "@/hooks/useAuth";

/** The full document library, newest first - mirrors web/src/app/page.tsx's useDocuments call.
 * Search is client-side (see lib/retrieval.ts), so this always fetches the whole (bounded) set. */
export function useDocumentsList() {
  return useQuery({
    queryKey: ["collection", DOCUMENTS_COLLECTION_ID, "list"],
    queryFn: () =>
      mudbaseClient.listDocuments(documentRecordSchema, DOCUMENTS_COLLECTION_ID, {
        sort: "-createdAt",
        limit: 100,
      }),
  });
}

export function useDocument(documentId: string | undefined) {
  return useQuery({
    queryKey: ["collection", DOCUMENTS_COLLECTION_ID, "doc", documentId],
    queryFn: () => {
      if (!documentId) throw new Error("useDocument called without a documentId");
      return mudbaseClient.getDocument(documentRecordSchema, DOCUMENTS_COLLECTION_ID, documentId);
    },
    enabled: !!documentId,
  });
}

export interface CreateDocumentInput {
  title: string;
  content: string;
  tags?: string;
}

/** Signed-in authors: publishes a new document, denormalizing the author's name onto the row
 * (this collection has no join to a users table - see plan/build-plan.md). */
export function useCreateDocument() {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  const mutate = useCallback(
    async (input: CreateDocumentInput): Promise<DocumentRecord> => {
      if (!user) throw new Error("Must be signed in to publish a document");
      return mudbaseClient.createDocument(documentRecordSchema, DOCUMENTS_COLLECTION_ID, {
        title: input.title,
        content: input.content,
        tags: input.tags ?? "",
        authorId: user.id,
        authorName: `${user.firstName} ${user.lastName}`.trim(),
      });
    },
    [user],
  );

  return useMutation({
    mutationFn: mutate,
    onSuccess: (created) => {
      void queryClient.invalidateQueries({ queryKey: ["collection", DOCUMENTS_COLLECTION_ID, "list"] });
      queryClient.setQueryData(["collection", DOCUMENTS_COLLECTION_ID, "doc", created._id], created);
    },
  });
}

export interface UpdateDocumentInput {
  documentId: string;
  title: string;
  content: string;
  tags?: string;
}

/** Author-only: edits a document's title/content/tags in place. Ownership is enforced both by
 * Mudbase's own collection permissions and by the UI gate in lib/rbac.ts's isDocumentOwner(). */
export function useUpdateDocument() {
  const queryClient = useQueryClient();

  const mutate = useCallback(async (input: UpdateDocumentInput): Promise<DocumentRecord> => {
    return mudbaseClient.updateDocument(documentRecordSchema, DOCUMENTS_COLLECTION_ID, input.documentId, {
      title: input.title,
      content: input.content,
      tags: input.tags ?? "",
    });
  }, []);

  return useMutation({
    mutationFn: mutate,
    onSuccess: (updated) => {
      queryClient.setQueryData(["collection", DOCUMENTS_COLLECTION_ID, "doc", updated._id], updated);
      void queryClient.invalidateQueries({ queryKey: ["collection", DOCUMENTS_COLLECTION_ID, "list"] });
    },
  });
}

/** Author-only: deletes a document. */
export function useDeleteDocument() {
  const queryClient = useQueryClient();

  const mutate = useCallback(async (documentId: string): Promise<void> => {
    await mudbaseClient.deleteDocument(DOCUMENTS_COLLECTION_ID, documentId);
  }, []);

  return useMutation({
    mutationFn: mutate,
    onSuccess: (_data, documentId) => {
      queryClient.removeQueries({ queryKey: ["collection", DOCUMENTS_COLLECTION_ID, "doc", documentId] });
      void queryClient.invalidateQueries({ queryKey: ["collection", DOCUMENTS_COLLECTION_ID, "list"] });
    },
  });
}
