import { z } from "zod";

/**
 * Runtime validation for every Mudbase response shape this app touches.
 *
 * The generated `mudbase-sdk`'s auth response models omit `customRole`/`isAnonymous` even though
 * the live API includes them on every project-scoped session response (this app's entire "is this
 * a real signed-in user, or the bootstrap guest" gate depends on them) — the same gap the sibling
 * `mudbase-showcase-kanban/mobile-expo` and `mudbase-showcase-social/mobile-expo` ports' own
 * `schemas.ts` document against the same generated SDK. Likewise `DataResponse`/`DataListResponse`
 * type their `data` field as bare `object`. Rather than casting past the generated types with
 * `as`, every SDK response is widened to `unknown` (always assignable, no cast needed) and parsed
 * through one of these schemas instead.
 */

// ─── Auth / User ────────────────────────────────────────────────────────────

export const mudbaseUserSchema = z.object({
  id: z.string(),
  email: z.string(),
  firstName: z.string(),
  lastName: z.string(),
  customRole: z.string().nullable().optional(),
  emailVerified: z.boolean().optional(),
  /** True for the bootstrap guest session created on first launch — see stores/authStore.ts. */
  isAnonymous: z.boolean().optional(),
});
export type MudbaseUser = z.infer<typeof mudbaseUserSchema>;

export const authResultSchema = z.object({
  message: z.string().optional(),
  token: z.string().optional(),
  refreshToken: z.string().optional(),
  expiresIn: z.number().optional(),
  requireVerification: z.boolean().optional(),
  user: mudbaseUserSchema.optional(),
});
export type AuthResult = z.infer<typeof authResultSchema>;

// ─── Documents (Collections) ───────────────────────────────────────────────

export const documentBaseSchema = z.object({
  _id: z.string(),
  createdAt: z.string(),
  updatedAt: z.string(),
});

export const documentRecordSchema = documentBaseSchema.extend({
  title: z.string(),
  content: z.string(),
  /** Comma-separated tags, e.g. "billing,invoices". Optional field on the collection schema. */
  tags: z.string().optional(),
  authorId: z.string(),
  authorName: z.string(),
});
export type DocumentRecord = z.infer<typeof documentRecordSchema>;

export const searchLogRecordSchema = documentBaseSchema.extend({
  queryText: z.string(),
  userId: z.string().optional(),
  userName: z.string().optional(),
  resultCount: z.number(),
});
export type SearchLogRecord = z.infer<typeof searchLogRecordSchema>;
