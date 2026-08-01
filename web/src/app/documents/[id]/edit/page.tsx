"use client"

import { useParams, useRouter } from "next/navigation"
import { useState } from "react"
import { useAuth } from "@/hooks/useAuth"
import { useDocument, useUpdateDocument } from "@/hooks/useCollection"
import { DOCUMENTS_COLLECTION_ID } from "@/lib/config"
import { DocumentForm, type DocumentFormValues } from "@/components/documents/DocumentForm"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { MudbaseError } from "@/lib/mudbase"
import type { DocumentRecord } from "@/types/document"

export default function EditDocumentPage(): React.JSX.Element {
  const params = useParams<{ id: string }>()
  const documentId = params.id
  const router = useRouter()
  const { user, loading: authLoading } = useAuth()
  const documentQuery = useDocument<DocumentRecord>(DOCUMENTS_COLLECTION_ID, documentId)
  const updateDocument = useUpdateDocument<DocumentRecord>(DOCUMENTS_COLLECTION_ID)
  const [submitError, setSubmitError] = useState<string | null>(null)

  if (authLoading || documentQuery.isLoading) {
    return <p className="container max-w-2xl py-16 text-center text-sm text-muted-foreground">Loading…</p>
  }

  if (documentQuery.isError || !documentQuery.data) {
    return (
      <p className="container max-w-2xl py-16 text-center text-sm text-destructive">
        This document isn&apos;t available.
      </p>
    )
  }

  const document = documentQuery.data
  const isOwner = !!user && user.id === document.authorId

  if (!isOwner) {
    return (
      <div className="container max-w-2xl py-16 text-center">
        <p className="text-sm text-muted-foreground">You can only edit documents you authored.</p>
      </div>
    )
  }

  const onSubmit = async (values: DocumentFormValues): Promise<void> => {
    setSubmitError(null)
    try {
      await updateDocument.mutateAsync({
        documentId: document._id,
        data: { title: values.title, content: values.content, tags: values.tags ?? "" },
      })
      router.push(`/documents/${document._id}`)
    } catch (err) {
      setSubmitError(err instanceof MudbaseError ? err.message : "Failed to update document")
    }
  }

  return (
    <div className="container max-w-2xl py-8">
      <Card>
        <CardHeader>
          <CardTitle>Edit document</CardTitle>
        </CardHeader>
        <CardContent>
          <DocumentForm
            defaultValues={{ title: document.title, content: document.content, tags: document.tags ?? "" }}
            submitLabel="Save changes"
            submittingLabel="Saving…"
            isSubmitting={updateDocument.isPending}
            error={submitError}
            onSubmit={onSubmit}
          />
        </CardContent>
      </Card>
    </div>
  )
}
