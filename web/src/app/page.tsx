"use client"

import { useMemo, useState } from "react"
import Link from "next/link"
import { useDocuments } from "@/hooks/useCollection"
import { DOCUMENTS_COLLECTION_ID } from "@/lib/config"
import { SearchBar } from "@/components/documents/SearchBar"
import { DocumentList } from "@/components/documents/DocumentList"
import { matchesSearchTerm } from "@/lib/retrieval"
import type { DocumentRecord } from "@/types/document"

export default function HomePage(): React.JSX.Element {
  const [searchTerm, setSearchTerm] = useState("")
  const { data, isLoading, error } = useDocuments<DocumentRecord>(DOCUMENTS_COLLECTION_ID, {
    sort: "-createdAt",
    limit: 100,
  })

  const filtered = useMemo(
    () => (data?.data ?? []).filter((document) => matchesSearchTerm(document, searchTerm)),
    [data, searchTerm],
  )

  return (
    <div className="container max-w-5xl space-y-6 py-8">
      <div className="space-y-1.5">
        <h1 className="font-display text-2xl font-semibold tracking-tight">Document library</h1>
        <p className="text-sm text-muted-foreground">
          Browse the knowledge base, or head to{" "}
          <Link href="/ask" className="text-primary underline underline-offset-4">
            Ask AI
          </Link>{" "}
          for a grounded answer synthesized from these documents.
        </p>
      </div>

      <SearchBar value={searchTerm} onChange={setSearchTerm} />

      {isLoading ? (
        <p className="py-12 text-center text-sm text-muted-foreground">Loading documents…</p>
      ) : error ? (
        <p className="py-12 text-center text-sm text-destructive">Failed to load documents. Please try again.</p>
      ) : (
        <DocumentList documents={filtered} />
      )}
    </div>
  )
}
