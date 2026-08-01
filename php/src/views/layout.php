<?php
/**
 * @var \App\Http\AppContext $context
 * @var array{type: string, message: string}|null $flash
 * @var string $content
 * @var string|null $title
 */

use App\Http\Csrf;
use App\View;

$pageTitle = isset($title) && $title !== '' ? "{$title} — Mudbase Docs Search" : 'Mudbase Docs Search';
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><?= View::escape($pageTitle) ?></title>
  <link rel="stylesheet" href="/assets/style.css">
</head>
<body>
  <header class="site-header">
    <div class="container site-header__row">
      <a href="/" class="site-header__brand">📚 Docs Search</a>
      <nav class="site-header__nav">
        <a class="btn btn--ghost btn--sm" href="/ask">✨ Ask AI</a>
        <?php if ($context->isSignedIn()): ?>
          <a class="btn btn--ghost btn--sm" href="/documents/new">+ New document</a>
          <span class="muted" style="font-size:0.8rem"><?= View::escape($context->displayName() ?? 'Signed in') ?></span>
          <form method="post" action="/logout" style="display:inline">
            <?= Csrf::field() ?>
            <button type="submit" class="btn btn--outline btn--sm">Sign out</button>
          </form>
        <?php else: ?>
          <a class="btn btn--ghost btn--sm" href="/login">Sign in</a>
          <a class="btn btn--sm" href="/register">Sign up</a>
        <?php endif; ?>
      </nav>
    </div>
  </header>

  <main class="container">
    <?php if ($flash !== null): ?>
      <div class="flash flash--<?= View::escape($flash['type']) ?>" role="alert">
        <?= View::escape($flash['message']) ?>
      </div>
    <?php endif; ?>

    <?= $content ?>
  </main>

  <footer class="site-footer">
    <div class="container">
      Every document, search log entry, and Ask AI retrieval ranking here is served by a real
      Mudbase project — auth, database, and a deployed serverless Function — with only one small
      unavoidable server-side surface: the Anthropic Claude completion call the Function's own
      network-isolated sandbox cannot make itself. See <code>plan/build-plan.md</code> "Ask AI
      architecture" for the full platform-constraint rationale.
    </div>
  </footer>
</body>
</html>
