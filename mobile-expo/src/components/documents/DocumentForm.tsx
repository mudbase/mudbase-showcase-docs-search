import { Controller, useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { View } from "react-native";
import { z } from "zod";
import { Button } from "@/components/ui/Button";
import { TextField } from "@/components/ui/TextField";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

export const documentFormSchema = z.object({
  title: z.string().min(1, "Title is required").max(200, "Title is too long"),
  content: z.string().min(1, "Content is required").max(50000, "Content is too long"),
  tags: z.string().max(500, "Tags are too long").optional(),
});

export type DocumentFormValues = z.infer<typeof documentFormSchema>;

interface DocumentFormProps {
  defaultValues?: Partial<DocumentFormValues>;
  submitLabel: string;
  submittingLabel: string;
  isSubmitting: boolean;
  error?: string | null;
  onSubmit: (values: DocumentFormValues) => void | Promise<void>;
}

export function DocumentForm({
  defaultValues,
  submitLabel,
  submittingLabel,
  isSubmitting,
  error,
  onSubmit,
}: DocumentFormProps): React.JSX.Element {
  const {
    control,
    handleSubmit,
    formState: { errors },
  } = useForm<DocumentFormValues>({
    resolver: zodResolver(documentFormSchema),
    defaultValues: { title: "", content: "", tags: "", ...defaultValues },
  });

  return (
    <View className="gap-4">
      {error && <ErrorNotice message={error} />}
      <Controller
        control={control}
        name="title"
        render={({ field: { onChange, onBlur, value } }) => (
          <TextField label="Title" value={value} onChangeText={onChange} onBlur={onBlur} error={errors.title?.message} />
        )}
      />
      <Controller
        control={control}
        name="content"
        render={({ field: { onChange, onBlur, value } }) => (
          <TextField
            label="Content"
            value={value}
            onChangeText={onChange}
            onBlur={onBlur}
            multiline
            numberOfLines={12}
            className="min-h-48"
            textAlignVertical="top"
            error={errors.content?.message}
          />
        )}
      />
      <Controller
        control={control}
        name="tags"
        render={({ field: { onChange, onBlur, value } }) => (
          <TextField
            label="Tags (optional)"
            value={value}
            onChangeText={onChange}
            onBlur={onBlur}
            placeholder="billing, invoices, refunds"
            error={errors.tags?.message}
          />
        )}
      />
      <Button onPress={handleSubmit((values) => void onSubmit(values))} isLoading={isSubmitting}>
        {isSubmitting ? submittingLabel : submitLabel}
      </Button>
    </View>
  );
}
