# frozen_string_literal: true

# Client-side (in the Next.js reference app) / server-side (here, since this app has no
# client-side JavaScript at all) keyword retrieval: scores each document by counting
# query-term occurrences across title (weight 3), tags (weight 2), and content (weight 1). No
# vector DB, no external search service - simple substring matching, ported line-for-line from
# the reference web app's `src/lib/retrieval.rb` (`scoreDocuments`/`matchesSearchTerm`/
# `topCandidates`) and `src/lib/utils.ts` (`countOccurrences`/`tokenizeQuery`).
module Retrieval
  MAX_CANDIDATE_CONTENT_CHARS = 4000

  # Case-insensitive substring count of `term` inside `text`.
  def self.count_occurrences(text, term)
    return 0 if term.to_s.empty?

    haystack = text.to_s.downcase
    needle = term.downcase
    count = 0
    index = haystack.index(needle)
    while index
      count += 1
      index = haystack.index(needle, index + needle.length)
    end
    count
  end

  # Splits free text into lowercase alphanumeric tokens of length > 2, deduplicated.
  def self.tokenize_query(text)
    text.to_s.downcase.split(/[^a-z0-9]+/).select { |t| t.length > 2 }.uniq
  end

  # @return [Array<Hash>] `{ document:, score: }` for every document with score > 0, sorted
  #   descending by score.
  def self.score_documents(documents, query)
    terms = tokenize_query(query)
    return [] if terms.empty?

    documents
      .map do |document|
        score = terms.sum do |term|
          count_occurrences(document[:title], term) * 3 +
            count_occurrences(document[:tags], term) * 2 +
            count_occurrences(document[:content], term)
        end
        { document: document, score: score }
      end
      .select { |entry| entry[:score].positive? }
      .sort_by { |entry| -entry[:score] }
  end

  # Matches the library page's plain-text search box: substring match across title+content+tags.
  def self.matches_search_term?(document, term)
    return true if term.to_s.strip.empty?

    needle = term.strip.downcase
    document[:title].to_s.downcase.include?(needle) ||
      document[:content].to_s.downcase.include?(needle) ||
      document[:tags].to_s.downcase.include?(needle)
  end

  # Top-N candidates for the Ask AI Function payload, with content truncated to bound payload
  # size - matches the reference web app's `topCandidates` exactly (5 candidates, 4000 chars).
  def self.top_candidates(scored, limit: 5)
    scored.first(limit).map do |entry|
      document = entry[:document]
      candidate = {
        documentId: document[:_id],
        title: document[:title],
        content: document[:content].to_s[0, MAX_CANDIDATE_CONTENT_CHARS],
      }
      tags = document[:tags]
      candidate[:tags] = tags if tags && !tags.to_s.empty?
      candidate
    end
  end
end
