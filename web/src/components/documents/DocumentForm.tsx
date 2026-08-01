"use client"

import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { z } from "zod"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"

export const documentFormSchema = z.object({
  title: z.string().min(1, "Title is required").max(200, "Title is too long"),
  content: z.string().min(1, "Content is required").max(50000, "Content is too long"),
  tags: z.string().max(500, "Tags are too long").optional(),
})

export type DocumentFormValues = z.infer<typeof documentFormSchema>

interface DocumentFormProps {
  defaultValues?: Partial<DocumentFormValues>
  submitLabel: string
  submittingLabel: string
  isSubmitting: boolean
  error?: string | null
  onSubmit: (values: DocumentFormValues) => void | Promise<void>
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
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<DocumentFormValues>({
    resolver: zodResolver(documentFormSchema),
    defaultValues: { title: "", content: "", tags: "", ...defaultValues },
  })

  return (
    <form onSubmit={handleSubmit((values) => void onSubmit(values))} className="space-y-4" noValidate>
      {error && (
        <p role="alert" className="text-sm text-destructive">
          {error}
        </p>
      )}
      <div className="space-y-1.5">
        <Label htmlFor="title">Title</Label>
        <Input id="title" {...register("title")} />
        {errors.title && <p className="text-xs text-destructive">{errors.title.message}</p>}
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="content">Content</Label>
        <Textarea id="content" rows={14} {...register("content")} />
        {errors.content && <p className="text-xs text-destructive">{errors.content.message}</p>}
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="tags">Tags</Label>
        <Input id="tags" placeholder="billing, invoices, refunds" {...register("tags")} />
        <p className="text-xs text-muted-foreground">Comma-separated. Used for search and Ask AI ranking.</p>
        {errors.tags && <p className="text-xs text-destructive">{errors.tags.message}</p>}
      </div>
      <Button type="submit" disabled={isSubmitting}>
        {isSubmitting ? submittingLabel : submitLabel}
      </Button>
    </form>
  )
}
