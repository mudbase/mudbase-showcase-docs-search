import { Pressable, type PressableProps } from "react-native";
import { cn } from "@/lib/cn";

export interface IconButtonProps extends PressableProps {
  accessibilityLabel: string;
  className?: string;
}

/** A small square icon-only pressable. Every usage requires accessibilityLabel since there is no
 * visible text for a screen reader to read. */
export function IconButton({
  accessibilityLabel,
  disabled,
  className,
  children,
  ...props
}: IconButtonProps): React.JSX.Element {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityState={{ disabled: !!disabled }}
      disabled={disabled}
      hitSlop={6}
      className={cn(
        "h-8 w-8 items-center justify-center rounded-md active:bg-secondary",
        disabled && "opacity-40",
        className,
      )}
      {...props}
    >
      {children}
    </Pressable>
  );
}
