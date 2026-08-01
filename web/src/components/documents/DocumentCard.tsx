import Link from "next/link"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { snippet, parseTags, formatRelativeTime } from "@/lib/utils"
import type { DocumentRecord } from "@/types/document"

export function DocumentCard({ document }: { document: DocumentRecord }): React.JSX.Element {
  const tags = parseTags(document.tags)

  return (
    <Link href={`/documents/${document._id}`}>
      <Card className="h-full transition-colors hover:border-primary/50 hover:bg-secondary/40">
        <CardHeader className="space-y-2">
          <CardTitle className="line-clamp-2 text-base">{document.title}</CardTitle>
          {tags.length > 0 && (
            <div className="flex flex-wrap gap-1.5">
              {tags.map((tag) => (
                <Badge key={tag} variant="secondary">
                  {tag}
                </Badge>
              ))}
            </div>
          )}
        </CardHeader>
        <CardContent className="space-y-3">
          <p className="text-sm text-muted-foreground">{snippet(document.content)}</p>
          <p className="text-xs text-muted-foreground">
            {document.authorName} · {formatRelativeTime(document.createdAt)}
          </p>
        </CardContent>
      </Card>
    </Link>
  )
}
