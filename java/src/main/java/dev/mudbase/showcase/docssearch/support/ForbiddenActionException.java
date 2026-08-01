package dev.mudbase.showcase.docssearch.support;

/**
 * Thrown by {@code DocumentService} when the acting user is not the author of the document they
 * are trying to edit or delete. This is this Java app's own independent server-side enforcement
 * of the "edit/delete gated to user.id === document.authorId" rule in plan/build-plan.md: it runs
 * before any mutating call to Mudbase is attempted, so a raw POST to one of this app's own routes
 * that bypasses the Thymeleaf UI's hidden buttons is rejected here - not merely by Mudbase's own
 * collection permissions one layer further down (which grant the signed-in `customer` role
 * unconditional CRUD on this collection - see plan/build-plan.md "Data model" - so Mudbase itself
 * would happily let one customer edit another's document; this check is the actual security
 * boundary for that specific rule). Handled by {@code
 * dev.mudbase.showcase.docssearch.web.GlobalExceptionHandler}, which renders a 403 error page.
 */
public class ForbiddenActionException extends RuntimeException {

  private static final long serialVersionUID = 1L;

  public ForbiddenActionException(String message) {
    super(message);
  }
}
