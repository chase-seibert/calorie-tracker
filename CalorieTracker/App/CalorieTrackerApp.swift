import SwiftUI
import Foundation

@main
struct CalorieTrackerApp: App {
    @UIApplicationDelegateAdaptor(VitaChaseAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var diary: DiaryStore
    @StateObject private var healthKit: HealthKitStore
    @State private var hasPreparedLaunch = false
    @State private var didScheduleInteractionReadyEvent = false
    @State private var pendingOpenURL: URL?
    private let catalog: CatalogStore

    init() {
        _ = AppStartupMetrics.startedAtUptimeNanoseconds
        VitaChaseAppShortcuts.updateAppShortcutParameters()
        let healthKit = HealthKitStore()
        let catalog = CatalogStore()
        let diary = LaunchConfiguration.makeDiaryStore(
            healthKit: healthKit,
            catalog: catalog
        )
        self.catalog = catalog
        _healthKit = StateObject(wrappedValue: healthKit)
        _diary = StateObject(wrappedValue: diary)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasPreparedLaunch {
                    readyContent
                        .onAppear(perform: scheduleInteractionReadyEvent)
                } else {
                    ProgressView(diary.loadingPhase.message)
                }
            }
                .environmentObject(diary)
                .environmentObject(healthKit)
                .tint(AppTheme.coral)
                // Capture cold-launch imports/deep links while the diary is still opening.
                .onOpenURL { pendingOpenURL = $0 }
                .task {
                    defer { hasPreparedLaunch = true }
                    await diary.reloadFromDisk()
                    guard diary.lastSaveError == nil else { return }
                    hasPreparedLaunch = true
                    await Task.yield()
                    // Share the existing app preference with widget/Siri on the first SQLite launch.
                    LoggingPreferences.lastWeightUnit = LoggingPreferences.lastWeightUnit
                    FirstTimeOnboarding.prepareForLaunch(document: diary.document)
                    WeeklyReportBackground.diaryStore = diary
                    WeeklyReportBackground.scheduleIfEnabled()
                    HomeScreenQuickActions.update(document: diary.document)
                    Task {
                        await WeeklyReportBackground.runForegroundCatchUp()
                    }
                    Task {
                        let analytics = AnalyticsService.shared
                        await analytics.start()
                        await analytics.recordAppLaunch()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        WeeklyReportBackground.diaryStore = diary
                        WeeklyReportBackground.scheduleIfEnabled()
                        guard !diary.isLoading else { return }
                        Task {
                            await diary.reloadFromDisk()
                            VitaChaseAppShortcuts.updateAppShortcutParameters()
                            await AnalyticsService.shared.appBecameActive()
                        }
                    case .inactive, .background:
                        HomeScreenQuickActions.update(document: diary.document)
                    @unknown default:
                        break
                    }
                }
        }
    }

    @ViewBuilder
    private var readyContent: some View {
#if DEBUG && targetEnvironment(simulator)
        if let route = ProcessInfo.processInfo.environment["CALORIE_TRACKER_CUSTOMIZATION_EVIDENCE"] {
            CustomizationEvidenceView(route: route, catalog: catalog)
        } else {
            RootView(catalog: catalog, pendingOpenURL: $pendingOpenURL)
        }
#else
        RootView(catalog: catalog, pendingOpenURL: $pendingOpenURL)
#endif
    }

    private func scheduleInteractionReadyEvent() {
        guard !didScheduleInteractionReadyEvent else { return }
        didScheduleInteractionReadyEvent = true
        Task { @MainActor in
            // Let SwiftUI replace the loading view before stopping the startup timer.
            await Task.yield()
            let elapsedMilliseconds = AppStartupMetrics.elapsedMilliseconds
            await AnalyticsService.shared.recordInteractionReady(
                startupDurationMilliseconds: elapsedMilliseconds
            )
        }
    }
}

private enum AppStartupMetrics {
    static let startedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds

    static var elapsedMilliseconds: Double {
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAtUptimeNanoseconds
        return Double(elapsed) / 1_000_000
    }
}

enum FirstTimeOnboarding {
    static let completedKey = "onboarding.focus.v1.completed"
    static let resetNotification = Notification.Name("FirstTimeOnboarding.didReset")

    static func prepareForLaunch(
        document: DiaryDocument,
        defaults: UserDefaults = .standard
    ) {
        guard defaults.object(forKey: completedKey) == nil else { return }
        guard hasExistingUserData(document) else { return }
        defaults.set(true, forKey: completedKey)
    }

    private static func hasExistingUserData(_ document: DiaryDocument) -> Bool {
        document.trackingStartDate != nil
            || document.dailyCalorieGoal != nil
            || !document.entries.isEmpty
            || !document.alcoholEntries.isEmpty
            || !document.favorites.isEmpty
            || !document.customFoods.isEmpty
            || !document.meals.isEmpty
            || !document.dayStatuses.isEmpty
            || !document.rememberedQuantities.isEmpty
    }
}

private enum LaunchConfiguration {
    @MainActor
    static func makeDiaryStore(healthKit: HealthKitStore, catalog: CatalogStore) -> DiaryStore {
#if DEBUG && targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        if environment["CALORIE_TRACKER_UNIFIED_FIXTURE"] == "1" {
            let fixtureURL = SharedDiaryStorage.selectFixture("customization", reset: environment["CALORIE_TRACKER_FIXTURE_RESET"] == "1")
            if FileManager.default.fileExists(atPath: fixtureURL.path) {
                return DiaryStore(fileURL: fixtureURL, catalog: catalog, healthKit: healthKit)
            }
            return DiaryStore(document: CustomizationEvidenceView.document(catalog: catalog), fileURL: fixtureURL, catalog: catalog, healthKit: healthKit)
        }
        if environment["CALORIE_TRACKER_UI_TEST_FIXTURE"] == "reorder" {
            let fixtureURL = SharedDiaryStorage.selectFixture("reorder", reset: environment["CALORIE_TRACKER_UI_TEST_RESET"] == "1")
            if FileManager.default.fileExists(atPath: fixtureURL.path) {
                return DiaryStore(fileURL: fixtureURL, catalog: catalog, healthKit: healthKit)
            }
            return DiaryStore(document: reorderFixture(), fileURL: fixtureURL, catalog: catalog, healthKit: healthKit)
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
        _ = SharedDiaryStorage.selectFixture(nil)
#endif
        return DiaryStore(catalog: catalog, healthKit: healthKit)
    }

#if DEBUG
    @MainActor
    private static func reorderFixture() -> DiaryDocument {
        let store = DiaryEngine(document: DiaryDocument())
        let foods = [
            fixtureFood(id: "reorder-delta", name: "Reorder Delta", calories: 40),
            fixtureFood(id: "reorder-gamma", name: "Reorder Gamma", calories: 30),
            fixtureFood(id: "reorder-beta", name: "Reorder Beta", calories: 20),
            fixtureFood(id: "reorder-alpha", name: "Reorder Alpha", calories: 10)
        ]
        for food in foods {
            store.log(food, amount: 1, unit: .serving, portionID: "fixture-serving", on: Date())
        }
        return store.document
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
