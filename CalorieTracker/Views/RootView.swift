import SwiftUI

struct RootView: View {
    let catalog: CatalogStore
    @EnvironmentObject private var diary: DiaryStore
    @ObservedObject private var quickActionRouter = HomeScreenQuickActionRouter.shared
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
            .onReceive(quickActionRouter.$request.compactMap { $0 }) { request in
                handleQuickAction(request)
            }
    }

    private func openImportFile(_ url: URL) {
        do {
            let importedFile = try CustomImportFile.load(from: url)
            importRequest = ImportRequest(file: importedFile)
            importError = nil
            let itemType: String = switch importedFile {
            case .food: "food"
            case .meal: "meal"
            }
            AppAnalytics.capture("import.opened", properties: ["item_type": itemType])
        } catch {
            importRequest = nil
            importError = error.localizedDescription
            AppAnalytics.capture("import.failed")
        }
    }

    private func handleQuickAction(_ request: HomeScreenQuickActionRequest) {
        defer { quickActionRouter.consume(request) }
        guard let result = diary.logQuickSelection(request.selectionID) else { return }
        AppAnalytics.capture("diary.quick_action_logged", properties: [
            "item_count": String(result.loggedItemCount)
        ])
    }
}

private struct ImportRequest: Identifiable {
    let id = UUID()
    let file: CustomImportFile
}
