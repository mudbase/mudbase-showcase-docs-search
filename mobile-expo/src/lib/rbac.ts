import type { DocumentRecord, MudbaseUser } from "@/api/schemas";

/**
 * This project ships Mudbase's single default starter application role ("customer") with full
 * CRUD on both collections — there is no multi-role RBAC matrix here the way the sibling kanban
 * port has. The only two things the UI needs to gate are:
 *
 * 1. Is this a real, signed-in author (not the always-present anonymous guest)?
 * 2. Does the signed-in user own this specific document (authorId === user.id)?
 *
 * Mudbase's own collection permissions are the real enforcement boundary — this is purely a UI
 * convenience so a viewer never sees an edit/delete control they'd get a 403 for pressing. Byte-
 * for-byte port of the gating logic in web/src/hooks/useAuth.ts and web/src/app/documents/[id]/page.tsx.
 */
export function isRealUser(user: MudbaseUser | null): boolean {
  return !!user && user.isAnonymous !== true;
}

export function isDocumentOwner(user: MudbaseUser | null, document: DocumentRecord): boolean {
  return isRealUser(user) && user?.id === document.authorId;
}
