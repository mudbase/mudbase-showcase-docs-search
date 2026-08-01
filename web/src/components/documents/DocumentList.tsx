import { FileQuestion } from "lucide-react"
import { DocumentCard } from "@/components/documents/DocumentCard"
import type { DocumentRecord } from "@/types/document"

export function DocumentList({ documents }: { documents: DocumentRecord[] }): React.JSX.Element {
  if (documents.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center gap-2 rounded-lg border border-dashed border-border py-16 text-center">
        <FileQuestion className="h-8 w-8 text-muted-foreground" />
        <p className="text-sm font-medium">No documents match your search</p>
        <p className="text-xs text-muted-foreground">Try a different keyword, or add the first document.</p>
      </div>
    )
  }

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {documents.map((document) => (
        <DocumentCard key={document._id} document={document} />
      ))}
    </div>
  )
}
