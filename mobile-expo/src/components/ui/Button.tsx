import { forwardRef } from "react";
import { ActivityIndicator, Pressable, Text, View, type PressableProps } from "react-native";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/cn";

const buttonVariants = cva("flex-row items-center justify-center rounded-md gap-2", {
  variants: {
    variant: {
      primary: "bg-primary active:opacity-80",
      outline: "border border-border active:bg-secondary",
      ghost: "active:bg-secondary",
      destructive: "bg-destructive active:opacity-80",
    },
    size: {
      sm: "px-3 py-2",
      md: "px-4 py-3",
      lg: "px-5 py-4",
      icon: "h-9 w-9 p-0",
    },
  },
  defaultVariants: { variant: "primary", size: "md" },
});

const textVariants = cva("font-semibold", {
  variants: {
    variant: {
      primary: "text-primary-foreground",
      outline: "text-foreground",
      ghost: "text-foreground",
      destructive: "text-destructive-foreground",
    },
    size: {
      sm: "text-sm",
      md: "text-base",
      lg: "text-lg",
      icon: "text-base",
    },
  },
  defaultVariants: { variant: "primary", size: "md" },
});

export interface ButtonProps extends Omit<PressableProps, "children">, VariantProps<typeof buttonVariants> {
  children?: string;
  isLoading?: boolean;
  className?: string;
  icon?: React.ReactNode;
}

export const Button = forwardRef<View, ButtonProps>(
  ({ children, variant, size, isLoading = false, disabled, className, icon, ...props }, ref) => {
    const isDisabled = disabled === true || isLoading;
    return (
      <Pressable
        ref={ref}
        disabled={isDisabled}
        accessibilityRole="button"
        accessibilityState={{ disabled: isDisabled, busy: isLoading }}
        className={cn(buttonVariants({ variant, size }), isDisabled && "opacity-50", className)}
        {...props}
      >
        {isLoading && (
          <ActivityIndicator size="small" color={variant === "outline" || variant === "ghost" ? "#4a43db" : "#f9f9fb"} />
        )}
        {!isLoading && icon}
        {children && <Text className={cn(textVariants({ variant, size }))}>{children}</Text>}
      </Pressable>
    );
  },
);

Button.displayName = "Button";
