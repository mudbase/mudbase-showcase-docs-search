<?php
/**
 * @var "create"|"edit" $mode
 * @var string $formAction
 * @var string $title
 * @var string $content
 * @var string $tags
 * @var string|null $error
 */

use App\Http\Csrf;
use App\View;

// Reuses the outer $title variable name for the layout's <title> tag would collide with the
// document's own title field - rename before the layout reads it.
$documentTitleValue = $title;
$title = $mode === 'create' ? 'New document' : 'Edit document';
?>

<div style="max-width:42rem;margin:0 auto">
  <h1><?= $mode === 'create' ? 'New document' : 'Edit document' ?></h1>

  <?php if ($error !== null): ?>
    <p class="flash flash--error" role="alert"><?= View::escape($error) ?></p>
  <?php endif; ?>

  <form method="post" action="<?= View::escape($formAction) ?>">
    <?= Csrf::field() ?>
    <div class="field">
      <label for="doc-title">Title</label>
      <input type="text" id="doc-title" name="title" maxlength="200" value="<?= View::escape($documentTitleValue) ?>" required>
    </div>
    <div class="field">
      <label for="doc-content">Content</label>
      <textarea id="doc-content" name="content" rows="14" maxlength="50000" required><?= View::escape($content) ?></textarea>
    </div>
    <div class="field">
      <label for="doc-tags">Tags</label>
      <input type="text" id="doc-tags" name="tags" maxlength="500" placeholder="billing, invoices, refunds" value="<?= View::escape($tags) ?>">
      <p class="field-hint">Comma-separated. Used for search and Ask AI ranking.</p>
    </div>
    <button type="submit" class="btn"><?= $mode === 'create' ? 'Publish document' : 'Save changes' ?></button>
  </form>
</div>
