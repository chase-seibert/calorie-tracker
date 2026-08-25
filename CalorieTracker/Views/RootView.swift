import SwiftUI

struct RootView: View {
    let catalog: CatalogStore
    @State private var importRequest: ImportRequest?
    @State private var importError: String?

    var body: some View {
        DiaryView(catalog: catalog)
            .onOpenURL(perform: openImportFile)
            .sheet(item: $importRequest) { request in
                switch request.file {
                case let .food(file):
                    CustomFoodImportView(file: file)
                case let .meal(file):
                    CustomMealImportView(file: file)
                }
            }
            .alert("Couldn’t Import File", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "Unknown error")
            }
    }

    private func openImportFile(_ url: URL) {
        do {
            importRequest = ImportRequest(file: try CustomImportFile.load(from: url))
            importError = nil
        } catch {
            importRequest = nil
            importError = error.localizedDescription
        }
    }
}

private struct ImportRequest: Identifiable {
    let id = UUID()
    let file: CustomImportFile
}
