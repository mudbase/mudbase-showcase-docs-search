import type { Document } from "@/lib/mudbase"

export interface DocumentRecord extends Document {
  title: string
  content: string
  /** Comma-separated tags, e.g. "billing,invoices". Optional field on the collection schema. */
  tags?: string
  authorId: string
  authorName: string
}

export interface SearchLogRecord extends Document {
  queryText: string
  userId?: string
  userName?: string
  resultCount: number
}
