import SwiftUI

struct RootView: View {
    let catalog: CatalogStore

    var body: some View {
        DiaryView(catalog: catalog)
    }
}
