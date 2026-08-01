import { View } from "react-native";
import { cn } from "@/lib/cn";

export function Separator({ className }: { className?: string }): React.JSX.Element {
  return <View className={cn("h-px w-full bg-border", className)} />;
}
