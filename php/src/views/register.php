<?php
/** @var string $redirectTo */

use App\Http\Csrf;
use App\View;

$title = 'Create account';
?>

<div style="max-width:26rem;margin:0 auto">
  <div style="text-align:center;margin-bottom:1.5rem">
    <h1>Create account</h1>
    <p class="muted">Every registration uses this project's single "customer" role — full document CRUD.</p>
  </div>

  <form method="post" action="/register">
    <?= Csrf::field() ?>
    <input type="hidden" name="redirectTo" value="<?= View::escape($redirectTo) ?>">
    <div style="display:flex;gap:0.75rem">
      <div class="field" style="flex:1">
        <label for="firstName">First name</label>
        <input type="text" id="firstName" name="firstName" autocomplete="given-name" required>
      </div>
      <div class="field" style="flex:1">
        <label for="lastName">Last name</label>
        <input type="text" id="lastName" name="lastName" autocomplete="family-name" required>
      </div>
    </div>
    <div class="field">
      <label for="email">Email</label>
      <input type="email" id="email" name="email" autocomplete="email" required>
    </div>
    <div class="field">
      <label for="password">Password</label>
      <input type="password" id="password" name="password" autocomplete="new-password" minlength="8" required>
      <p class="field-hint">At least 8 characters.</p>
    </div>
    <div class="field" style="display:flex;align-items:flex-start;gap:0.5rem">
      <input type="checkbox" id="agreedToTerms" name="agreedToTerms" style="margin-top:0.3rem" required>
      <label for="agreedToTerms" style="margin:0">I agree to the Terms of Service and Privacy Policy.</label>
    </div>
    <button type="submit" class="btn btn--block">Create account</button>
  </form>

  <p class="muted" style="text-align:center;margin-top:1rem">
    Already have an account? <a href="/login">Sign in</a>.
  </p>
</div>
