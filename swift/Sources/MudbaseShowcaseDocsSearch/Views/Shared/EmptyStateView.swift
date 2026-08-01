import SwiftUI

struct EmptyStateView: View {
    let message: String

    var body: some View {
        VStack {
            Spacer(minLength: 48)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer(minLength: 48)
        }
        .frame(maxWidth: .infinity)
    }
}
