import SwiftUI

@main
struct CalorieTrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var diary: DiaryStore
    @StateObject private var healthKit: HealthKitStore
    private let catalog: CatalogStore
    private let analytics = AnalyticsService.shared

    init() {
        let healthKit = HealthKitStore()
        let catalog = CatalogStore()
        self.catalog = catalog
        _healthKit = StateObject(wrappedValue: healthKit)
        _diary = StateObject(wrappedValue: LaunchConfiguration.makeDiaryStore(
            healthKit: healthKit,
            catalog: catalog
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(catalog: catalog)
                .environmentObject(diary)
                .environmentObject(healthKit)
                .tint(AppTheme.coral)
                .task {
                    await analytics.start()
                    await analytics.recordAppLaunch()
                    guard healthKit.authorizationState == .authorized else { return }
                    await analytics.capture(type: "health.sync_requested", properties: ["source": "app_launch"])
                    healthKit.clearLastError()
                    diary.syncAllHealthData()
                    await healthKit.waitForPendingOperations()
                    await analytics.capture(type: "health.sync_completed", properties: [
                        "source": "app_launch",
                        "result": healthKit.lastError == nil ? "success" : "failure"
                    ])
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await analytics.appBecameActive() }
                }
        }
    }
}

private enum LaunchConfiguration {
    @MainActor
    static func makeDiaryStore(healthKit: HealthKitStore, catalog: CatalogStore) -> DiaryStore {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["CALORIE_TRACKER_UI_TEST_FIXTURE"] == "reorder" {
            let fixtureURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CalorieTrackerUITests", isDirectory: true)
                .appendingPathComponent("ReorderDiary.json")
            if environment["CALORIE_TRACKER_UI_TEST_RESET"] == "1" {
                try? FileManager.default.removeItem(at: fixtureURL)
            }

            let store = DiaryStore(fileURL: fixtureURL, catalog: catalog, healthKit: healthKit)
            if store.entries(on: Date()).isEmpty {
                seedReorderFixture(in: store)
            }
            return store
        }

        #if targetEnvironment(simulator)
        let usesDefaultSimulatorFixture = environment["CALORIE_TRACKER_DISABLE_SIMULATOR_FIXTURE"] != "1"
        #else
        let usesDefaultSimulatorFixture = false
        #endif

        if environment["CALORIE_TRACKER_FIXTURE"] == "device" || usesDefaultSimulatorFixture {
            return DiaryFixtureLoader.makeDeviceStore(
                healthKit: healthKit,
                catalog: catalog,
                reset: environment["CALORIE_TRACKER_FIXTURE_RESET"] == "1" || usesDefaultSimulatorFixture
            )
        }
#endif
        return DiaryStore(catalog: catalog, healthKit: healthKit)
    }

#if DEBUG
    @MainActor
    private static func seedReorderFixture(in store: DiaryStore) {
        let foods = [
            fixtureFood(id: "reorder-delta", name: "Reorder Delta", calories: 40),
            fixtureFood(id: "reorder-gamma", name: "Reorder Gamma", calories: 30),
            fixtureFood(id: "reorder-beta", name: "Reorder Beta", calories: 20),
            fixtureFood(id: "reorder-alpha", name: "Reorder Alpha", calories: 10)
        ]
        for food in foods {
            store.log(food, amount: 1, unit: .serving, portionID: "fixture-serving", on: Date())
        }
    }

    private static func fixtureFood(id: String, name: String, calories: Double) -> Food {
        Food(
            sourceID: id,
            source: .custom,
            name: name,
            brand: "UI Test",
            barcode: nil,
            nutrients: MacroNutrients(calories: calories, carbs: 1, fat: 1, protein: 1),
            baseAmountGrams: 1,
            servingGrams: 1,
            servingDescription: "1 item",
            portions: [FoodPortion(id: "fixture-serving", label: "item", grams: 1)]
        )
    }
#endif
}

enum AppTheme {
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemGroupedBackground
            : UIColor(red: 0.975, green: 0.965, blue: 0.94, alpha: 1)
    })
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let controlFill = Color(uiColor: .tertiarySystemFill)
    static let ink = Color.primary
    static let muted = Color.secondary
    static let selectedText = Color(uiColor: .systemBackground)
    static let coral = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.39, blue: 0.33, alpha: 1)
            : UIColor(red: 0.94, green: 0.35, blue: 0.28, alpha: 1)
    })
    static let carbs = Color(uiColor: .systemBlue)
    static let fat = Color(uiColor: .systemPurple)
    static let protein = Color(uiColor: .systemGreen)
    static let fiber = Color(uiColor: .systemBrown)
    static let gapDay = Color(uiColor: .systemGray)
    static let cheatDay = Color(uiColor: .systemOrange)
    static let processedMeat = Color(uiColor: .systemTeal)
    static let redMeat = Color(uiColor: .systemRed)
}
