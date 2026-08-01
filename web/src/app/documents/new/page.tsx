"use client"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { useAuth } from "@/hooks/useAuth"
import { useCreateDocument } from "@/hooks/useCollection"
import { DOCUMENTS_COLLECTION_ID } from "@/lib/config"
import { DocumentForm, type DocumentFormValues } from "@/components/documents/DocumentForm"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { MudbaseError } from "@/lib/mudbase"
import type { DocumentRecord } from "@/types/document"

export default function NewDocumentPage(): React.JSX.Element {
  const router = useRouter()
  const { user, isAuthenticated, loading: authLoading } = useAuth()
  const createDocument = useCreateDocument<DocumentRecord>(DOCUMENTS_COLLECTION_ID)
  const [submitError, setSubmitError] = useState<string | null>(null)

  const onSubmit = async (values: DocumentFormValues): Promise<void> => {
    if (!user) return
    setSubmitError(null)
    try {
      const created = await createDocument.mutateAsync({
        title: values.title,
        content: values.content,
        tags: values.tags ?? "",
        authorId: user.id,
        authorName: `${user.firstName} ${user.lastName}`.trim(),
      })
      router.push(`/documents/${created._id}`)
    } catch (err) {
      setSubmitError(err instanceof MudbaseError ? err.message : "Failed to create document")
    }
  }

  if (authLoading) {
    return <p className="container py-16 text-center text-sm text-muted-foreground">Loading…</p>
  }

  if (!isAuthenticated) {
    return (
      <div className="container max-w-md py-16 text-center">
        <p className="text-sm text-muted-foreground">Sign in to add a document to the library.</p>
      </div>
    )
  }

  return (
    <div className="container max-w-2xl py-8">
      <Card>
        <CardHeader>
          <CardTitle>New document</CardTitle>
        </CardHeader>
        <CardContent>
          <DocumentForm
            submitLabel="Publish document"
            submittingLabel="Publishing…"
            isSubmitting={createDocument.isPending}
            error={submitError}
            onSubmit={onSubmit}
          />
        </CardContent>
      </Card>
    </div>
  )
}
