import { Text, View } from "react-native";
import { cn } from "@/lib/cn";

export type BadgeVariant = "default" | "secondary" | "outline";

const variantClasses: Record<BadgeVariant, string> = {
  default: "bg-primary",
  secondary: "bg-secondary",
  outline: "border border-border bg-transparent",
};

const textVariantClasses: Record<BadgeVariant, string> = {
  default: "text-primary-foreground",
  secondary: "text-secondary-foreground",
  outline: "text-foreground",
};

export interface BadgeProps {
  children: string;
  variant?: BadgeVariant;
  className?: string;
}

export function Badge({ children, variant = "default", className }: BadgeProps): React.JSX.Element {
  return (
    <View className={cn("rounded-full px-2.5 py-1", variantClasses[variant], className)}>
      <Text className={cn("text-xs font-semibold", textVariantClasses[variant])}>{children}</Text>
    </View>
  );
}
