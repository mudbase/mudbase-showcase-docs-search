<?php
/**
 * @var array<string, mixed> $document
 * @var bool $isOwner
 */

use App\Http\Csrf;
use App\Support\DocumentText;
use App\Support\TimeFormat;
use App\View;

$docTitle = (string) ($document['title'] ?? '');
$documentId = (string) ($document['_id'] ?? '');
$content = is_string($document['content'] ?? null) ? $document['content'] : '';
$tags = DocumentText::parseTags(is_string($document['tags'] ?? null) ? $document['tags'] : null);
$authorName = is_string($document['authorName'] ?? null) ? $document['authorName'] : 'Someone';
$createdAt = is_string($document['createdAt'] ?? null) ? $document['createdAt'] : null;

$title = $docTitle;
?>

<div class="document-detail">
  <div class="document-detail__header">
    <h1 style="margin:0"><?= View::escape($docTitle) ?></h1>
    <?php if ($isOwner): ?>
      <div style="display:flex;gap:0.5rem;flex-shrink:0">
        <a class="btn btn--outline btn--sm" href="/documents/<?= urlencode($documentId) ?>/edit">Edit</a>
        <form method="post" action="/documents/<?= urlencode($documentId) ?>/delete">
          <?= Csrf::field() ?>
          <button type="submit" class="btn btn--destructive btn--sm">Delete</button>
        </form>
      </div>
    <?php endif; ?>
  </div>

  <?php if ($tags !== []): ?>
    <div class="tag-row">
      <?php foreach ($tags as $tag): ?>
        <span class="tag-chip"><?= View::escape($tag) ?></span>
      <?php endforeach; ?>
    </div>
  <?php endif; ?>

  <p class="muted"><?= View::escape($authorName) ?> · <?= View::escape(TimeFormat::dateTime($createdAt)) ?></p>

  <hr class="hr">

  <article class="document-detail__body"><?= View::escape($content) ?></article>
</div>
