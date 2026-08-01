import { useCallback } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { mudbaseClient } from "@/api/client";
import { searchLogRecordSchema } from "@/api/schemas";
import { SEARCH_LOG_COLLECTION_ID } from "@/config/env";
import { useAuth } from "@/hooks/useAuth";

/** Most recent 10 Ask AI queries, newest first — mirrors web/src/components/ask/RecentSearches.tsx. */
export function useRecentSearches() {
  return useQuery({
    queryKey: ["collection", SEARCH_LOG_COLLECTION_ID, "list"],
    queryFn: () =>
      mudbaseClient.listDocuments(searchLogRecordSchema, SEARCH_LOG_COLLECTION_ID, {
        sort: "-createdAt",
        limit: 10,
      }),
  });
}

export interface LogSearchInput {
  queryText: string;
  resultCount: number;
}

/** Writes one search_log row per Ask AI query, for both guests and signed-in users — mirrors
 * web/src/components/ask/AskAIPanel.tsx's handleAsk(). userId/userName are only included for a
 * real signed-in author; never a placeholder string for a guest. */
export function useLogSearch() {
  const { user, isAuthenticated } = useAuth();
  const queryClient = useQueryClient();

  const mutate = useCallback(
    async (input: LogSearchInput): Promise<void> => {
      await mudbaseClient.createDocument(searchLogRecordSchema, SEARCH_LOG_COLLECTION_ID, {
        queryText: input.queryText,
        resultCount: input.resultCount,
        ...(isAuthenticated && user ? { userId: user.id, userName: `${user.firstName} ${user.lastName}`.trim() } : {}),
      });
    },
    [user, isAuthenticated],
  );

  return useMutation({
    mutationFn: mutate,
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["collection", SEARCH_LOG_COLLECTION_ID] }),
  });
}
