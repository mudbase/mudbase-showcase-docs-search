<?php
/**
 * Rendered once per document from home.php, in the same variable scope (plain `require`, no
 * template engine — see src/View.php).
 *
 * @var array<string, mixed> $document
 */

use App\Support\DocumentText;
use App\Support\TimeFormat;
use App\View;

$documentId = (string) ($document['_id'] ?? '');
$docTitle = (string) ($document['title'] ?? '');
$content = is_string($document['content'] ?? null) ? $document['content'] : '';
$tags = DocumentText::parseTags(is_string($document['tags'] ?? null) ? $document['tags'] : null);
$authorName = is_string($document['authorName'] ?? null) ? $document['authorName'] : 'Someone';
$createdAt = is_string($document['createdAt'] ?? null) ? $document['createdAt'] : null;
?>
<a href="/documents/<?= urlencode($documentId) ?>" class="document-card">
  <p class="document-card__title"><?= View::escape($docTitle) ?></p>
  <?php if ($tags !== []): ?>
    <div class="tag-row">
      <?php foreach ($tags as $tag): ?>
        <span class="tag-chip"><?= View::escape($tag) ?></span>
      <?php endforeach; ?>
    </div>
  <?php endif; ?>
  <p class="document-card__snippet"><?= View::escape(DocumentText::snippet($content)) ?></p>
  <p class="document-card__meta"><?= View::escape($authorName) ?> · <?= View::escape(TimeFormat::relative($createdAt)) ?></p>
</a>
