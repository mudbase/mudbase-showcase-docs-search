import SwiftUI

/// Shown instead of crashing when `Config.plist` is missing or malformed — see
/// `AppConfig.load(bundle:environment:)`'s doc comment for why this is a runtime check rather than
/// a build-time one.
struct ConfigurationRequiredView: View {
    let error: ConfigurationError

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Configuration required")
                .font(.title2.bold())
            Text(error.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
