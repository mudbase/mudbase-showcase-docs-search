import Foundation

/// Backs `RecentSearchesView`. Mirrors `../web/src/components/ask/RecentSearches.tsx`: reads the
/// 10 most recent `search_log` entries, independent of whatever the `AskAIViewModel` on the same
/// screen is currently doing (same "each screen fetches its own slice" convention the sibling
/// `mudbase-showcase-social` Swift port's `FeedViewModel`/`ProfileViewModel` use).
@MainActor
final class RecentSearchesViewModel: ObservableObject {
    @Published private(set) var entries: [SearchLogRecord] = []
    @Published private(set) var isLoading = true

    private let searchLogService: SearchLogService

    init(config: AppConfig) {
        searchLogService = SearchLogService(config: config)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        entries = (try? await searchLogService.recent()) ?? []
    }
}
