import { Tabs } from "expo-router";
import { BookOpen, Sparkles } from "lucide-react-native";
import type { ColorValue } from "react-native";

const FALLBACK_ICON_COLOR = "#181c25";

/**
 * `Tabs.Screen`'s `tabBarIcon` hands back React Navigation's broader `ColorValue`, while
 * lucide-react-native icons only accept a plain `string`. Every tint color configured below is
 * always a literal hex string, so this narrows safely without a cast.
 */
function toIconColor(color: ColorValue): string {
  return typeof color === "string" ? color : FALLBACK_ICON_COLOR;
}

/**
 * Unlike the sibling kanban port, this app has a real anonymous-session guest experience (see
 * plan/build-plan.md "Auth model") - both tabs are reachable without signing in. Only publish/
 * edit/delete actions (gated inline, not at the router level) require a real account.
 */
export default function TabsLayout(): React.JSX.Element {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: "#4a43db",
        tabBarInactiveTintColor: "#606876",
      }}
    >
      <Tabs.Screen
        name="index"
        options={{ title: "Library", tabBarIcon: ({ color, size }) => <BookOpen color={toIconColor(color)} size={size} /> }}
      />
      <Tabs.Screen
        name="ask"
        options={{ title: "Ask AI", tabBarIcon: ({ color, size }) => <Sparkles color={toIconColor(color)} size={size} /> }}
      />
    </Tabs>
  );
}
