"use client"

import { useState } from "react"
import Link from "next/link"
import { Sparkles, ExternalLink } from "lucide-react"
import { useDocuments, useCreateDocument } from "@/hooks/useCollection"
import { useAskAI } from "@/hooks/useAskAI"
import { useAuth } from "@/hooks/useAuth"
import { DOCUMENTS_COLLECTION_ID, SEARCH_LOG_COLLECTION_ID } from "@/lib/config"
import { scoreDocuments, topCandidates } from "@/lib/retrieval"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import type { DocumentRecord, SearchLogRecord } from "@/types/document"
import type { AskCitation } from "@/lib/ask-schema"

export function AskAIPanel(): React.JSX.Element {
  const [question, setQuestion] = useState("")
  const [answer, setAnswer] = useState<string | null>(null)
  const [citations, setCitations] = useState<AskCitation[]>([])
  const [noMatch, setNoMatch] = useState(false)

  const { user } = useAuth()
  const documentsQuery = useDocuments<DocumentRecord>(DOCUMENTS_COLLECTION_ID, { limit: 200 })
  const askAI = useAskAI()
  const logSearch = useCreateDocument<SearchLogRecord>(SEARCH_LOG_COLLECTION_ID)

  const handleAsk = async (): Promise<void> => {
    const trimmed = question.trim()
    if (!trimmed) return

    setAnswer(null)
    setCitations([])
    setNoMatch(false)

    const documents = documentsQuery.data?.data ?? []
    const scored = scoreDocuments(documents, trimmed)

    if (scored.length === 0) {
      setNoMatch(true)
      await logSearch.mutateAsync({
        queryText: trimmed,
        resultCount: 0,
        // userId must be a real ObjectId or omitted entirely - never a placeholder string.
        ...(user?.id ? { userId: user.id } : {}),
        ...(user ? { userName: `${user.firstName} ${user.lastName}`.trim() } : {}),
      })
      return
    }

    const candidates = topCandidates(scored, 5)
    const result = await askAI.mutateAsync({ question: trimmed, candidates })
    setAnswer(result.answer)
    setCitations(result.citations)

    await logSearch.mutateAsync({
      queryText: trimmed,
      resultCount: result.citations.length,
      ...(user?.id ? { userId: user.id } : {}),
      ...(user ? { userName: `${user.firstName} ${user.lastName}`.trim() } : {}),
    })
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <Sparkles className="h-4 w-4 text-primary" />
            Ask a question
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <Textarea
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            placeholder="e.g. How do I reset my password?"
            aria-label="Question for Ask AI"
            rows={3}
            disabled={askAI.isPending}
          />
          <Button
            onClick={() => void handleAsk()}
            disabled={askAI.isPending || documentsQuery.isLoading || !question.trim()}
          >
            {askAI.isPending ? "Thinking…" : documentsQuery.isLoading ? "Loading library…" : "Ask AI"}
          </Button>
          {askAI.isError && (
            <p role="alert" className="text-sm text-destructive">
              {askAI.error.message}
            </p>
          )}
        </CardContent>
      </Card>

      {noMatch && (
        <p className="text-sm text-muted-foreground">
          No documents in the library matched that question closely enough to answer from. Try rephrasing, or add a
          document that covers it.
        </p>
      )}

      {answer && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Answer</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <p className="whitespace-pre-wrap text-sm leading-relaxed">{answer}</p>
            {citations.length > 0 && (
              <div className="space-y-2">
                <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Sources</p>
                <div className="flex flex-wrap gap-2">
                  {citations.map((citation) => (
                    <Link key={citation.documentId} href={`/documents/${citation.documentId}`}>
                      <Badge variant="outline" className="gap-1">
                        {citation.title}
                        <ExternalLink className="h-3 w-3" />
                      </Badge>
                    </Link>
                  ))}
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  )
}
