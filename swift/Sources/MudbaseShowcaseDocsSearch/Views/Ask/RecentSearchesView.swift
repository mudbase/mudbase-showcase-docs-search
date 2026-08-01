import SwiftUI

/// Mirrors `../web/src/components/ask/RecentSearches.tsx`.
struct RecentSearchesView: View {
    @StateObject private var viewModel: RecentSearchesViewModel

    init(config: AppConfig) {
        _viewModel = StateObject(wrappedValue: RecentSearchesViewModel(config: config))
    }

    var body: some View {
        Group {
            if !viewModel.isLoading && !viewModel.entries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Recent searches", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ForEach(viewModel.entries) { entry in
                        HStack {
                            Text(entry.queryText)
                                .lineLimit(1)
                            Spacer()
                            Text("\(entry.resultCount) \(entry.resultCount == 1 ? "source" : "sources") · \(Formatting.relativeTime(from: entry.createdAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .task { await viewModel.load() }
    }
}
