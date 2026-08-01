import SwiftUI

/// A dismiss-free, non-blocking inline banner for form-level error/info text — the SwiftUI
/// equivalent of the web app's `role="alert"` paragraphs above each form.
struct InlineBanner: View {
    enum Style { case error, info }

    let message: String
    var style: Style = .error

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(style == .error ? .red : .secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((style == .error ? Color.red : Color.blue).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
