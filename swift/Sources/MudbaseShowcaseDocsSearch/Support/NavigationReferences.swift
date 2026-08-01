import SwiftUI

/// `navigationDestination(for:)` registers one destination builder per *type* within a given
/// `NavigationStack`. A document can be reached both by tapping a card in the Library tab and by
/// tapping a citation in the Ask AI tab — each tab owns its own `NavigationStack`, so both register
/// this same destination type independently. Same pattern as the sibling
/// `mudbase-showcase-social`/`mudbase-showcase-ecommerce` Swift ports'
/// `Support/NavigationReferences.swift`.
struct DocumentReference: Hashable {
    let documentId: String
}

extension View {
    func docsSearchNavigationDestinations(config: AppConfig) -> some View {
        self.navigationDestination(for: DocumentReference.self) { reference in
            DocumentDetailView(config: config, documentId: reference.documentId)
        }
    }
}
