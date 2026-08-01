import { View } from "react-native";
import { Search } from "lucide-react-native";
import { TextField } from "@/components/ui/TextField";

interface SearchBarProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
}

export function SearchBar({ value, onChange, placeholder }: SearchBarProps): React.JSX.Element {
  return (
    <View className="flex-row items-center gap-2 rounded-md border border-border bg-card px-3">
      <Search size={16} color="#606876" />
      <TextField
        value={value}
        onChangeText={onChange}
        placeholder={placeholder ?? "Search documents by title, content, or tag…"}
        containerClassName="flex-1"
        className="border-0 bg-transparent px-0"
        accessibilityLabel="Search documents"
      />
    </View>
  );
}
