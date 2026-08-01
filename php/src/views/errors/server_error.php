<?php
/** @var string $message */

use App\View;

$title = 'Something went wrong';
?>
<div class="empty-state">
  <h1>Something went wrong</h1>
  <p class="flash flash--error"><?= View::escape($message) ?></p>
  <p class="muted"><a href="/">Back to the library</a>.</p>
</div>
