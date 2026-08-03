import SwiftUI

@main
struct CalorieTrackerApp: App {
    @StateObject private var diary = DiaryStore()
    private let catalog = CatalogStore()

    var body: some Scene {
        WindowGroup {
            RootView(catalog: catalog)
                .environmentObject(diary)
                .tint(AppTheme.coral)
        }
    }
}

enum AppTheme {
    static let background = Color(red: 0.975, green: 0.965, blue: 0.94)
    static let card = Color.white.opacity(0.86)
    static let ink = Color(red: 0.12, green: 0.14, blue: 0.18)
    static let muted = Color(red: 0.42, green: 0.43, blue: 0.45)
    static let coral = Color(red: 0.94, green: 0.35, blue: 0.28)
    static let carbs = Color(red: 0.22, green: 0.52, blue: 0.88)
    static let fat = Color(red: 0.54, green: 0.37, blue: 0.84)
    static let protein = Color(red: 0.20, green: 0.62, blue: 0.43)
}

