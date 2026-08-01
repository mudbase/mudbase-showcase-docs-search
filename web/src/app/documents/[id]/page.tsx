"use client"

import { useParams, useRouter } from "next/navigation"
import Link from "next/link"
import { useState } from "react"
import { Trash2, Pencil } from "lucide-react"
import { useAuth } from "@/hooks/useAuth"
import { useDocument, useDeleteDocument } from "@/hooks/useCollection"
import { DOCUMENTS_COLLECTION_ID } from "@/lib/config"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import { parseTags, formatDateTime } from "@/lib/utils"
import type { DocumentRecord } from "@/types/document"

export default function DocumentDetailPage(): React.JSX.Element {
  const params = useParams<{ id: string }>()
  const documentId = params.id
  const router = useRouter()
  const { user } = useAuth()
  const documentQuery = useDocument<DocumentRecord>(DOCUMENTS_COLLECTION_ID, documentId)
  const deleteDocument = useDeleteDocument(DOCUMENTS_COLLECTION_ID)
  const [deleting, setDeleting] = useState(false)

  if (documentQuery.isLoading) {
    return <p className="container max-w-3xl py-16 text-center text-sm text-muted-foreground">Loading document…</p>
  }

  if (documentQuery.isError || !documentQuery.data) {
    return (
      <p className="container max-w-3xl py-16 text-center text-sm text-destructive">
        This document isn&apos;t available.
      </p>
    )
  }

  const document = documentQuery.data
  const tags = parseTags(document.tags)
  const isOwner = !!user && user.id === document.authorId

  const handleDelete = async (): Promise<void> => {
    if (!window.confirm("Delete this document? This cannot be undone.")) return
    setDeleting(true)
    try {
      await deleteDocument.mutateAsync(document._id)
      router.push("/")
    } finally {
      setDeleting(false)
    }
  }

  return (
    <div className="container max-w-3xl space-y-6 py-8">
      <div className="space-y-3">
        <div className="flex items-start justify-between gap-4">
          <h1 className="font-display text-2xl font-semibold tracking-tight">{document.title}</h1>
          {isOwner && (
            <div className="flex shrink-0 gap-2">
              <Button asChild variant="outline" size="sm">
                <Link href={`/documents/${document._id}/edit`}>
                  <Pencil className="mr-2 h-4 w-4" />
                  Edit
                </Link>
              </Button>
              <Button variant="destructive" size="sm" onClick={() => void handleDelete()} disabled={deleting}>
                <Trash2 className="mr-2 h-4 w-4" />
                {deleting ? "Deleting…" : "Delete"}
              </Button>
            </div>
          )}
        </div>
        {tags.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {tags.map((tag) => (
              <Badge key={tag} variant="secondary">
                {tag}
              </Badge>
            ))}
          </div>
        )}
        <p className="text-sm text-muted-foreground">
          {document.authorName} · {formatDateTime(document.createdAt)}
        </p>
      </div>

      <Separator />

      <article className="whitespace-pre-wrap text-sm leading-relaxed text-foreground">{document.content}</article>
    </div>
  )
}
