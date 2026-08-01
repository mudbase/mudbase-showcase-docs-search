# frozen_string_literal: true

require "time"

# ERB helpers shared by every view. Ported from the reference web app's `src/lib/utils.ts`.
module ViewHelpers
  def h(text)
    Rack::Utils.escape_html(text.to_s)
  end

  def format_datetime(iso_string)
    return "" if iso_string.nil? || iso_string.empty?

    Time.parse(iso_string).strftime("%b %-d, %Y %-I:%M %p")
  rescue ArgumentError
    iso_string.to_s
  end

  # Compact "3m", "2h", "5d" style relative time - falls back to an absolute date once it's more
  # than a week old, matching the reference web app's `formatRelativeTime`.
  def format_relative(iso_string)
    return "" if iso_string.nil? || iso_string.empty?

    then_time = Time.parse(iso_string)
    seconds = (Time.now - then_time).to_i
    return "just now" if seconds < 5
    return "#{seconds}s ago" if seconds < 60
    return "#{seconds / 60}m ago" if seconds < 3600
    return "#{seconds / 3600}h ago" if seconds < 86_400
    return "#{seconds / 86_400}d ago" if seconds < 604_800

    then_time.strftime("%b %-d, %Y")
  rescue ArgumentError
    iso_string.to_s
  end

  def initials(name)
    parts = name.to_s.strip.split(/\s+/)
    return "?" if parts.empty?
    return parts.first[0].upcase if parts.length == 1

    "#{parts.first[0]}#{parts.last[0]}".upcase
  end

  # Short plain-text snippet from document content, for library-card previews - matches the
  # reference web app's `snippet()`.
  def snippet(text, max_length = 160)
    trimmed = text.to_s.strip.gsub(/\s+/, " ")
    return trimmed if trimmed.length <= max_length

    "#{trimmed[0, max_length].rstrip}…"
  end

  # Parses the `documents.tags` field (comma-separated string) into a clean array - matches the
  # reference web app's `parseTags()`.
  def parse_tags(tags)
    return [] if tags.nil? || tags.to_s.empty?

    tags.to_s.split(",").map(&:strip).reject(&:empty?)
  end
end
