<?php
/** @var string $redirectTo */

use App\Http\Csrf;
use App\View;

$title = 'Sign in';

/**
 * One-click demo account form — same zero-JS pattern as the sibling kanban PHP port's login
 * page: a real `<form>` with the credentials already baked into hidden inputs, submitting
 * straight to the same /login handler a manually typed form would.
 */
$demoEmail = 'docs.member.demo@gmail.com';
$demoPassword = 'DemoTest123!';
?>

<div style="max-width:26rem;margin:0 auto">
  <div style="text-align:center;margin-bottom:1.5rem">
    <h1>Sign in</h1>
    <p class="muted">Browsing and search work as a guest — sign in to add or edit documents and have Ask AI remember your searches.</p>
  </div>

  <form method="post" action="/login">
    <?= Csrf::field() ?>
    <input type="hidden" name="email" value="<?= View::escape($demoEmail) ?>">
    <input type="hidden" name="password" value="<?= View::escape($demoPassword) ?>">
    <input type="hidden" name="redirectTo" value="<?= View::escape($redirectTo) ?>">
    <button type="submit" class="btn btn--outline btn--block">Sign in as demo member</button>
  </form>

  <div class="divider-row">or sign in manually</div>

  <form method="post" action="/login">
    <?= Csrf::field() ?>
    <input type="hidden" name="redirectTo" value="<?= View::escape($redirectTo) ?>">
    <div class="field">
      <label for="email">Email</label>
      <input type="email" id="email" name="email" autocomplete="email" required>
    </div>
    <div class="field">
      <label for="password">Password</label>
      <input type="password" id="password" name="password" autocomplete="current-password" required>
    </div>
    <button type="submit" class="btn btn--block">Sign in</button>
  </form>

  <p class="muted" style="text-align:center;margin-top:1rem">
    No account? <a href="/register">Create one</a>.
  </p>
</div>
