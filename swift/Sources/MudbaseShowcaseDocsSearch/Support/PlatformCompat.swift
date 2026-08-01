import SwiftUI

/// `.keyboardType` and `.textInputAutocapitalization` only exist on iOS/tvOS/watchOS — this
/// target also builds for macOS (see Package.swift). These no-op on macOS instead of failing to
/// compile. Ported verbatim from the sibling `mudbase-showcase-ecommerce`/`mudbase-showcase-social`
/// Swift ports' `Support/PlatformCompat.swift`.
extension View {
    @ViewBuilder
    func emailKeyboard() -> some View {
        #if os(iOS) || os(tvOS) || os(watchOS)
        self.keyboardType(.emailAddress).textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    /// `.navigationBarTitleDisplayMode` is unavailable on macOS entirely (there is no navigation
    /// bar to compress) — this project's real target is iOS/iPadOS, where it applies normally.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS) || os(tvOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
