import type { Metadata } from "next"
import { AskAIPanel } from "@/components/ask/AskAIPanel"
import { RecentSearches } from "@/components/ask/RecentSearches"

export const metadata: Metadata = { title: "Ask AI" }

export default function AskPage(): React.JSX.Element {
  return (
    <div className="container max-w-2xl space-y-8 py-8">
      <div className="space-y-1.5">
        <h1 className="font-display text-2xl font-semibold tracking-tight">Ask AI</h1>
        <p className="text-sm text-muted-foreground">
          Ask a question in plain language. The app finds the most relevant documents in the library, then asks an
          LLM to answer strictly from their content - with citations back to the source documents.
        </p>
      </div>

      <AskAIPanel />
      <RecentSearches />
    </div>
  )
}
