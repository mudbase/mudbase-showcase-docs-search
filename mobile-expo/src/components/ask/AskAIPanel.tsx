import { useState } from "react";
import { Pressable, Text, View } from "react-native";
import { router } from "expo-router";
import { Sparkles, ExternalLink } from "lucide-react-native";
import { useDocumentsList } from "@/hooks/useDocuments";
import { useAskAI } from "@/hooks/useAskAI";
import { useLogSearch } from "@/hooks/useSearchLog";
import { scoreDocuments, topCandidates } from "@/lib/retrieval";
import { ASK_PROXY_URL } from "@/config/env";
import { Card } from "@/components/ui/Card";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { TextField } from "@/components/ui/TextField";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import type { AskCitation } from "@/lib/ask-schema";

/**
 * See plan/build-plan.md "Ask AI architecture" and hooks/useAskAI.ts for the full reasoning on why
 * this feature depends on an optionally-configured proxy. When EXPO_PUBLIC_ASK_PROXY_URL is unset,
 * this panel still runs the real client-side keyword retrieval (the same scoreDocuments() the
 * proxy's own Mudbase Function re-ranks server-side) so a developer can see the pipeline is wired
 * up to the exact point the missing server-side surface would take over — it never fabricates an
 * answer.
 */
export function AskAIPanel(): React.JSX.Element {
  const [question, setQuestion] = useState("");
  const [answer, setAnswer] = useState<string | null>(null);
  const [citations, setCitations] = useState<AskCitation[]>([]);
  const [noMatch, setNoMatch] = useState(false);
  const [localTitles, setLocalTitles] = useState<string[] | null>(null);

  const documentsQuery = useDocumentsList();
  const askAI = useAskAI();
  const logSearch = useLogSearch();

  const handleAsk = async (): Promise<void> => {
    const trimmed = question.trim();
    if (!trimmed) return;

    setAnswer(null);
    setCitations([]);
    setNoMatch(false);
    setLocalTitles(null);

    const documents = documentsQuery.data?.data ?? [];
    const scored = scoreDocuments(documents, trimmed);

    if (scored.length === 0) {
      setNoMatch(true);
      await logSearch.mutateAsync({ queryText: trimmed, resultCount: 0 });
      return;
    }

    if (!ASK_PROXY_URL) {
      // Documented architectural gap (see file header) — show what retrieval alone found instead
      // of pretending the LLM step ran.
      setLocalTitles(scored.slice(0, 5).map((entry) => entry.document.title));
      await logSearch.mutateAsync({ queryText: trimmed, resultCount: scored.length });
      return;
    }

    const candidates = topCandidates(scored, 5);
    const result = await askAI.mutateAsync({ question: trimmed, candidates });
    setAnswer(result.answer);
    setCitations(result.citations);

    await logSearch.mutateAsync({ queryText: trimmed, resultCount: result.citations.length });
  };

  return (
    <View className="gap-4">
      <Card className="gap-3">
        <View className="flex-row items-center gap-2">
          <Sparkles size={16} color="#4a43db" />
          <Text className="text-base font-semibold text-foreground">Ask a question</Text>
        </View>
        <TextField
          value={question}
          onChangeText={setQuestion}
          placeholder="e.g. How do I reset my password?"
          accessibilityLabel="Question for Ask AI"
          multiline
          numberOfLines={3}
          className="min-h-20"
          textAlignVertical="top"
          editable={!askAI.isPending}
        />
        <Button
          onPress={() => void handleAsk()}
          disabled={askAI.isPending || documentsQuery.isLoading || !question.trim()}
          isLoading={askAI.isPending}
        >
          {askAI.isPending ? "Thinking…" : documentsQuery.isLoading ? "Loading library…" : "Ask AI"}
        </Button>
        {askAI.isError && <ErrorNotice message={askAI.error.message} />}
      </Card>

      {!ASK_PROXY_URL && (
        <Card className="gap-1.5 border-warning/40 bg-warning/5">
          <Text className="text-xs font-semibold uppercase tracking-wide text-warning">Known limitation</Text>
          <Text className="text-xs text-muted-foreground">
            No Ask AI proxy is configured (EXPO_PUBLIC_ASK_PROXY_URL is unset) — this mobile app has no
            server of its own, and the LLM completion call cannot happen on-device or inside the
            Mudbase Function (see plan/build-plan.md). Retrieval below still runs for real against
            the documents you have loaded.
          </Text>
        </Card>
      )}

      {noMatch && (
        <Text className="text-sm text-muted-foreground">
          No documents in the library matched that question closely enough to answer from. Try
          rephrasing, or add a document that covers it.
        </Text>
      )}

      {localTitles && localTitles.length > 0 && (
        <Card className="gap-2">
          <Text className="text-sm font-semibold text-foreground">Closest matches (retrieval only)</Text>
          <View className="flex-row flex-wrap gap-1.5">
            {localTitles.map((title) => (
              <Badge key={title} variant="outline">
                {title}
              </Badge>
            ))}
          </View>
        </Card>
      )}

      {answer && (
        <Card className="gap-3">
          <Text className="text-base font-semibold text-foreground">Answer</Text>
          <Text className="text-sm leading-relaxed text-foreground">{answer}</Text>
          {citations.length > 0 && (
            <View className="gap-2">
              <Text className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Sources</Text>
              <View className="flex-row flex-wrap gap-2">
                {citations.map((citation) => (
                  <Pressable key={citation.documentId} onPress={() => router.push(`/documents/${citation.documentId}`)}>
                    <View className="flex-row items-center gap-1 rounded-full border border-border px-2.5 py-1">
                      <Text className="text-xs text-foreground">{citation.title}</Text>
                      <ExternalLink size={12} color="#606876" />
                    </View>
                  </Pressable>
                ))}
              </View>
            </View>
          )}
        </Card>
      )}
    </View>
  );
}
