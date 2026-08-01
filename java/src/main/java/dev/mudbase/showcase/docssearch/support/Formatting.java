package dev.mudbase.showcase.docssearch.support;

import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/** Formatting helpers shared by domain objects and templates - mirrors ../web/src/lib/utils.ts. */
public final class Formatting {

  private static final DateTimeFormatter DISPLAY_DATE_TIME =
      DateTimeFormatter.ofPattern("MMM d, yyyy 'at' h:mm a", Locale.US);
  private static final DateTimeFormatter DISPLAY_DATE = DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.US);
  private static final int DEFAULT_SNIPPET_LENGTH = 160;

  private Formatting() {}

  /** Full "MMM d, yyyy at h:mm a" timestamp - mirrors {@code formatDateTime} in utils.ts. */
  public static String formatDateTime(String iso) {
    return format(iso, DISPLAY_DATE_TIME);
  }

  /**
   * A short relative timestamp ("3m ago", "5h ago", "2d ago"), falling back to an absolute date
   * once something is more than a week old - mirrors {@code formatRelativeTime} in utils.ts.
   */
  public static String formatRelativeTime(String iso) {
    if (iso == null || iso.isBlank()) {
      return "";
    }
    try {
      OffsetDateTime parsed = OffsetDateTime.parse(iso);
      Duration elapsed = Duration.between(parsed.toInstant(), Instant.now());
      long seconds = elapsed.toSeconds();
      if (seconds < 5) {
        return "just now";
      }
      if (seconds < 60) {
        return seconds + "s ago";
      }
      long minutes = Math.round(seconds / 60.0);
      if (minutes < 60) {
        return minutes + "m ago";
      }
      long hours = Math.round(minutes / 60.0);
      if (hours < 24) {
        return hours + "h ago";
      }
      long days = Math.round(hours / 24.0);
      if (days < 7) {
        return days + "d ago";
      }
      return parsed.format(DISPLAY_DATE);
    } catch (DateTimeParseException e) {
      return iso;
    }
  }

  private static String format(String iso, DateTimeFormatter formatter) {
    if (iso == null || iso.isBlank()) {
      return "";
    }
    try {
      return OffsetDateTime.parse(iso).format(formatter);
    } catch (DateTimeParseException e) {
      return iso;
    }
  }

  /** Builds a short plain-text snippet from document content - mirrors {@code snippet} in utils.ts. */
  public static String snippet(String text, int maxLength) {
    if (text == null) {
      return "";
    }
    String trimmed = text.trim().replaceAll("\\s+", " ");
    if (trimmed.length() <= maxLength) {
      return trimmed;
    }
    String cut = trimmed.substring(0, maxLength);
    // Trim trailing whitespace introduced by cutting mid-word, then append an ellipsis.
    int end = cut.length();
    while (end > 0 && Character.isWhitespace(cut.charAt(end - 1))) {
      end--;
    }
    return cut.substring(0, end) + "…";
  }

  public static String snippet(String text) {
    return snippet(text, DEFAULT_SNIPPET_LENGTH);
  }

  /** Parses the documents.tags field (comma-separated string) into a clean list - mirrors {@code parseTags}. */
  public static List<String> parseTags(String tags) {
    List<String> result = new ArrayList<>();
    if (tags == null || tags.isBlank()) {
      return result;
    }
    for (String part : tags.split(",")) {
      String trimmed = part.trim();
      if (!trimmed.isEmpty()) {
        result.add(trimmed);
      }
    }
    return result;
  }
}
