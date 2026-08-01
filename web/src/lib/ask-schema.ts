import { z } from "zod"

/**
 * Contract for POST /api/ask. Shared between the client (building the request) and the route
 * handler (validating it) so the two never drift.
 *
 * Why the client sends full candidate documents instead of the server fetching them itself:
 * the Mudbase Function that ranks/assembles context (see plan/build-plan.md "Ask AI
 * architecture") runs inside an isolated-vm sandbox with zero network access - it cannot call
 * back into Mudbase's own data API to look documents up by ID. The client already holds the
 * full document list (it rendered the library page from it), so it does the initial keyword
 * shortlist and passes the shortlisted documents' content along in the payload.
 */
export const AskRequestCandidateSchema = z.object({
  documentId: z.string().regex(/^[0-9a-f]{24}$/i, "documentId must be a 24-character hex ObjectId"),
  title: z.string().min(1).max(300),
  content: z.string().min(1).max(20000),
  tags: z.string().max(500).optional(),
})

export const AskRequestSchema = z.object({
  question: z.string().min(1, "Question is required").max(2000, "Question is too long"),
  candidates: z.array(AskRequestCandidateSchema).min(1, "At least one candidate document is required").max(8),
})

export type AskRequestCandidate = z.infer<typeof AskRequestCandidateSchema>
export type AskRequest = z.infer<typeof AskRequestSchema>

export const AskCitationSchema = z.object({
  documentId: z.string(),
  title: z.string(),
})

export const AskResponseSchema = z.object({
  answer: z.string(),
  citations: z.array(AskCitationSchema),
  usedCount: z.number().int().nonnegative(),
})

export type AskCitation = z.infer<typeof AskCitationSchema>
export type AskResponse = z.infer<typeof AskResponseSchema>

export const AskErrorResponseSchema = z.object({
  error: z.string(),
})
