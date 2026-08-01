import SwiftUI

/// Mirrors `../web/src/components/documents/DocumentCard.tsx`.
struct DocumentCardView: View {
    let document: DocumentRecord

    private var tags: [String] { Formatting.parseTags(document.tags) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(document.title)
                .font(.headline)
                .lineLimit(2)

            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }

            Text(Formatting.snippet(document.content))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Text("\(document.authorName) · \(Formatting.relativeTime(from: document.createdAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}
