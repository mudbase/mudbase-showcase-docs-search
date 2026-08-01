import SwiftUI

struct InlineErrorView: View {
    let message: String
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let onRetry {
                Button("Try again", action: onRetry)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}
