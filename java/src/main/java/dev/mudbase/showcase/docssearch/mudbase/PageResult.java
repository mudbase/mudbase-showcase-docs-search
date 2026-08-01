package dev.mudbase.showcase.docssearch.mudbase;

import java.util.List;

/** One page of a Mudbase collection list call, carrying the pagination metadata. */
public record PageResult<T>(List<T> items, int page, int limit, long total, boolean hasMore) {

  public static <T> PageResult<T> empty(int page, int limit) {
    return new PageResult<>(List.of(), page, limit, 0, false);
  }
}
