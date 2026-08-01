import { Pressable, Text, View } from "react-native";
import { router } from "expo-router";
import { Card } from "@/components/ui/Card";
import { Badge } from "@/components/ui/Badge";
import { snippet, parseTags, formatRelativeTime } from "@/lib/format";
import type { DocumentRecord } from "@/api/schemas";

export function DocumentCard({ document }: { document: DocumentRecord }): React.JSX.Element {
  const tags = parseTags(document.tags);

  return (
    <Pressable onPress={() => router.push(`/documents/${document._id}`)}>
      <Card className="gap-3 active:border-primary/50 active:bg-secondary/40">
        <View className="gap-2">
          <Text className="text-base font-semibold text-foreground" numberOfLines={2}>
            {document.title}
          </Text>
          {tags.length > 0 && (
            <View className="flex-row flex-wrap gap-1.5">
              {tags.map((tag) => (
                <Badge key={tag} variant="secondary">
                  {tag}
                </Badge>
              ))}
            </View>
          )}
        </View>
        <Text className="text-sm text-muted-foreground">{snippet(document.content)}</Text>
        <Text className="text-xs text-muted-foreground">
          {document.authorName} · {formatRelativeTime(document.createdAt)}
        </Text>
      </Card>
    </Pressable>
  );
}
