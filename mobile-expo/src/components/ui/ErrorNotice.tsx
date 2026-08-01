import { Text, View } from "react-native";

export function ErrorNotice({ message }: { message: string }): React.JSX.Element {
  return (
    <View accessibilityRole="alert" className="rounded-md bg-destructive/10 p-3">
      <Text className="text-sm text-destructive">{message}</Text>
    </View>
  );
}
