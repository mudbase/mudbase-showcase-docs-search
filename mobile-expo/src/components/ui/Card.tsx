import { View, type ViewProps } from "react-native";
import { cn } from "@/lib/cn";

export function Card({ className, ...props }: ViewProps & { className?: string }): React.JSX.Element {
  return <View className={cn("rounded-lg border border-border bg-card p-4", className)} {...props} />;
}
