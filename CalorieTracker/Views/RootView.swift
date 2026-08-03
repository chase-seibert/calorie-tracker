import SwiftUI

struct RootView: View {
    let catalog: CatalogStore

    var body: some View {
        TabView {
            DiaryView(catalog: catalog)
                .tabItem { Label("Diary", systemImage: "fork.knife") }

            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }

            SettingsView(catalog: catalog)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

