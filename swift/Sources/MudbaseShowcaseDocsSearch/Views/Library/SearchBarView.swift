import SwiftUI

/// Mirrors `../web/src/components/documents/SearchBar.tsx`.
struct SearchBarView: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search documents by title, content, or tag…", text: $text)
                .autocorrectionDisabled()
                .accessibilityLabel("Search documents")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}
