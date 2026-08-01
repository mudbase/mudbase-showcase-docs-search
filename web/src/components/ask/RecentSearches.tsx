"use client"

import { History } from "lucide-react"
import { useDocuments } from "@/hooks/useCollection"
import { SEARCH_LOG_COLLECTION_ID } from "@/lib/config"
import { formatRelativeTime } from "@/lib/utils"
import type { SearchLogRecord } from "@/types/document"

export function RecentSearches(): React.JSX.Element | null {
  const { data, isLoading } = useDocuments<SearchLogRecord>(SEARCH_LOG_COLLECTION_ID, {
    sort: "-createdAt",
    limit: 10,
  })

  const entries = data?.data ?? []
  if (isLoading || entries.length === 0) return null

  return (
    <div className="space-y-2">
      <p className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-muted-foreground">
        <History className="h-3.5 w-3.5" />
        Recent searches
      </p>
      <ul className="space-y-1.5">
        {entries.map((entry) => (
          <li key={entry._id} className="flex items-center justify-between gap-3 text-sm">
            <span className="truncate text-foreground">{entry.queryText}</span>
            <span className="shrink-0 text-xs text-muted-foreground">
              {entry.resultCount} {entry.resultCount === 1 ? "source" : "sources"} · {formatRelativeTime(entry.createdAt)}
            </span>
          </li>
        ))}
      </ul>
    </div>
  )
}
