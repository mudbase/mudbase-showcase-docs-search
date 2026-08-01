import { z } from "zod";

/**
 * Contract for the Ask AI proxy request (see hooks/useAskAI.ts and plan/build-plan.md "Ask AI
 * architecture"). Byte-for-byte port of web/src/lib/ask-schema.ts — this app's client sends the
 * exact same shape the web reference app's own `POST /api/ask` Route Handler already validates,
 * since that route (or a deployment of it) is what this app's proxy points at.
 */
export const AskRequestCandidateSchema = z.object({
  documentId: z.string().regex(/^[0-9a-f]{24}$/i, "documentId must be a 24-character hex ObjectId"),
  title: z.string().min(1).max(300),
  content: z.string().min(1).max(20000),
  tags: z.string().max(500).optional(),
});

export const AskRequestSchema = z.object({
  question: z.string().min(1, "Question is required").max(2000, "Question is too long"),
  candidates: z.array(AskRequestCandidateSchema).min(1, "At least one candidate document is required").max(8),
});

export type AskRequestCandidate = z.infer<typeof AskRequestCandidateSchema>;
export type AskRequest = z.infer<typeof AskRequestSchema>;

export const AskCitationSchema = z.object({
  documentId: z.string(),
  title: z.string(),
});

export const AskResponseSchema = z.object({
  answer: z.string(),
  citations: z.array(AskCitationSchema),
  usedCount: z.number().int().nonnegative(),
});

export type AskCitation = z.infer<typeof AskCitationSchema>;
export type AskResponse = z.infer<typeof AskResponseSchema>;

export const AskErrorResponseSchema = z.object({
  error: z.string(),
});
