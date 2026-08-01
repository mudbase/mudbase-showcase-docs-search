import { Text, View } from "react-native";
import { History } from "lucide-react-native";
import { useRecentSearches } from "@/hooks/useSearchLog";
import { formatRelativeTime } from "@/lib/format";

export function RecentSearches(): React.JSX.Element | null {
  const { data, isLoading } = useRecentSearches();

  const entries = data?.data ?? [];
  if (isLoading || entries.length === 0) return null;

  return (
    <View className="gap-2">
      <View className="flex-row items-center gap-1.5">
        <History size={14} color="#606876" />
        <Text className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Recent searches</Text>
      </View>
      <View className="gap-1.5">
        {entries.map((entry) => (
          <View key={entry._id} className="flex-row items-center justify-between gap-3">
            <Text className="flex-1 text-sm text-foreground" numberOfLines={1}>
              {entry.queryText}
            </Text>
            <Text className="shrink-0 text-xs text-muted-foreground">
              {entry.resultCount} {entry.resultCount === 1 ? "source" : "sources"} · {formatRelativeTime(entry.createdAt)}
            </Text>
          </View>
        ))}
      </View>
    </View>
  );
}
