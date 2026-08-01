<?php
/**
 * @var string $question
 * @var string|null $answer
 * @var list<array{documentId: string, title: string, score?: int}> $citations
 * @var bool $noMatch
 * @var string|null $askError
 * @var list<array<string, mixed>> $recentSearches
 */

use App\Http\Csrf;
use App\Support\TimeFormat;
use App\View;

$title = 'Ask AI';
?>

<h1>Ask AI</h1>
<p class="muted" style="max-width:40rem">
  Ask a question in plain language. The app finds the most relevant documents in the library via a
  real, deployed Mudbase Function, then asks Claude to answer strictly from their content — with
  citations back to the source documents.
</p>

<form method="post" action="/ask" class="ask-form">
  <?= Csrf::field() ?>
  <div class="field">
    <label class="sr-only" for="ask-question">Question for Ask AI</label>
    <textarea id="ask-question" name="question" rows="3" maxlength="2000" placeholder="e.g. How do I reset my password?" required><?= View::escape($question) ?></textarea>
  </div>
  <button type="submit" class="btn">Ask AI</button>
</form>

<?php if ($askError !== null): ?>
  <p class="flash flash--error" role="alert"><?= View::escape($askError) ?></p>
<?php endif; ?>

<?php if ($noMatch): ?>
  <p class="muted" style="max-width:40rem">
    I couldn't find anything in the knowledge base closely related to that question. Try
    rephrasing, or add a document that covers it.
  </p>
<?php endif; ?>

<?php if ($answer !== null): ?>
  <div class="card ask-answer">
    <h2>Answer</h2>
    <p style="white-space:pre-wrap"><?= View::escape($answer) ?></p>
    <?php if ($citations !== []): ?>
      <p class="muted" style="font-size:0.78rem;text-transform:uppercase;letter-spacing:0.03em;margin-bottom:0.4rem">Sources</p>
      <div class="tag-row">
        <?php foreach ($citations as $citation): ?>
          <a class="tag-chip tag-chip--link" href="/documents/<?= urlencode((string) $citation['documentId']) ?>">
            <?= View::escape((string) $citation['title']) ?>
          </a>
        <?php endforeach; ?>
      </div>
    <?php endif; ?>
  </div>
<?php endif; ?>

<?php if ($recentSearches !== []): ?>
  <div class="recent-searches">
    <p class="muted" style="font-size:0.78rem;text-transform:uppercase;letter-spacing:0.03em">Recent searches</p>
    <ul class="recent-searches__list">
      <?php foreach ($recentSearches as $entry): ?>
        <?php
          $queryText = is_string($entry['queryText'] ?? null) ? $entry['queryText'] : '';
          $resultCount = (int) ($entry['resultCount'] ?? 0);
          $createdAt = is_string($entry['createdAt'] ?? null) ? $entry['createdAt'] : null;
        ?>
        <li>
          <span><?= View::escape($queryText) ?></span>
          <span class="muted"><?= $resultCount ?> <?= $resultCount === 1 ? 'source' : 'sources' ?> · <?= View::escape(TimeFormat::relative($createdAt)) ?></span>
        </li>
      <?php endforeach; ?>
    </ul>
  </div>
<?php endif; ?>
