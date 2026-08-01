import SwiftUI

/// Mirrors `../web/src/components/documents/DocumentForm.tsx` — handles both "New document" and
/// "Edit document".
struct DocumentFormView: View {
    @StateObject private var viewModel: DocumentFormViewModel
    @Environment(\.dismiss) private var dismiss

    init(config: AppConfig, author: AppUser, existingDocument: DocumentRecord?) {
        _viewModel = StateObject(wrappedValue: DocumentFormViewModel(config: config, author: author, existingDocument: existingDocument))
    }

    var body: some View {
        Form {
            if let errorMessage = viewModel.errorMessage {
                Section { InlineBanner(message: errorMessage) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Title") {
                TextField("Title", text: $viewModel.title)
            }

            Section("Content") {
                TextEditor(text: $viewModel.content)
                    .frame(minHeight: 220)
            }

            Section("Tags") {
                TextField("billing, invoices, refunds", text: $viewModel.tags)
                    .autocorrectionDisabled()
                Text("Comma-separated. Used for search and Ask AI ranking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task {
                        await viewModel.save()
                        if viewModel.savedDocument != nil { dismiss() }
                    }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Text(viewModel.isEditing ? "Save changes" : "Publish document")
                    }
                }
                .disabled(viewModel.isSubmitting)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(viewModel.isEditing ? "Edit document" : "New document")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
