<?php
/**
 * @var list<array<string, mixed>> $documents
 * @var string $query
 * @var string|null $error
 */

use App\View;

$title = null;
?>

<div class="library-header">
  <h1 style="margin:0">Document library</h1>
  <p class="muted">
    Browse the knowledge base, or head to <a href="/ask">Ask AI</a> for a grounded answer synthesized from these documents.
  </p>
</div>

<form method="get" action="/" class="search-form" role="search">
  <input
    type="search"
    name="q"
    value="<?= View::escape($query) ?>"
    placeholder="Search documents by title, content, or tag…"
    aria-label="Search documents"
  >
  <button type="submit" class="btn btn--sm">Search</button>
  <?php if ($query !== ''): ?>
    <a href="/" class="btn btn--ghost btn--sm">Clear</a>
  <?php endif; ?>
</form>

<?php if ($error !== null): ?>
  <p class="flash flash--error"><?= View::escape($error) ?></p>
<?php elseif ($documents === []): ?>
  <div class="empty-state">
    <p><?= $query !== '' ? 'No documents match your search.' : 'No documents in the library yet.' ?></p>
    <?php if ($query !== ''): ?>
      <p class="muted">Try a different keyword, or add the first document.</p>
    <?php endif; ?>
  </div>
<?php else: ?>
  <div class="document-grid">
    <?php foreach ($documents as $document): ?>
      <?php require __DIR__ . '/partials/document_card.php'; ?>
    <?php endforeach; ?>
  </div>
<?php endif; ?>
