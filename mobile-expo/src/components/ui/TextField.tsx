import { Text, TextInput, View, type TextInputProps } from "react-native";
import { cn } from "@/lib/cn";

export interface TextFieldProps extends TextInputProps {
  label?: string;
  error?: string;
  containerClassName?: string;
}

/**
 * React Hook Form's `register()` binds directly to DOM `<input>` refs and does not work with React
 * Native's `TextInput` - RN integration requires `Controller`, so every form in this app wraps
 * this component in a `<Controller render={({ field }) => <TextField {...field} .../>} />` rather
 * than calling `register()` the way the web reference app does.
 */
export function TextField({
  label,
  error,
  containerClassName,
  className,
  ...props
}: TextFieldProps): React.JSX.Element {
  return (
    <View className={cn("gap-1.5", containerClassName)}>
      {label && <Text className="text-sm font-medium text-foreground">{label}</Text>}
      <TextInput
        className={cn(
          "rounded-md border border-border bg-card px-3 py-2.5 text-base text-foreground",
          error && "border-destructive",
          className,
        )}
        placeholderTextColor="#606876"
        accessibilityLabel={label}
        {...props}
      />
      {error && <Text className="text-xs text-destructive">{error}</Text>}
    </View>
  );
}
