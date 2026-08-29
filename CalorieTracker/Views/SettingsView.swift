import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var diary: DiaryStore
    @EnvironmentObject private var healthKit: HealthKitStore
    @AppStorage("trends.focus.alcohol") private var tracksAlcohol = true
    @AppStorage("trends.focus.fiber") private var tracksFiber = true
    @AppStorage("trends.focus.processedMeat") private var tracksProcessedMeat = true
    @AppStorage("trends.focus.redMeat") private var tracksRedMeat = true
    let catalog: CatalogStore

    var body: some View {
        Form {
            Section("Goals & Logging") {
                NavigationLink {
                    CalorieGoalSettingsView()
                } label: {
                    SettingsValueLabel(
                        title: "Daily Calorie Goal",
                        systemImage: "target",
                        value: calorieGoalDescription
                    )
                }
            }

            Section {
                Toggle("Alcohol", isOn: $tracksAlcohol)
                Toggle("Fiber", isOn: $tracksFiber)
                Toggle("Processed Meat", isOn: $tracksProcessedMeat)
                Toggle("Red Meat", isOn: $tracksRedMeat)
            } header: {
                Text("Focus Areas")
            } footer: {
                Text("Choose which focused health metrics appear in the app. These preferences only change the display; your logged data stays on your phone.")
            }

            Section("Food & Meals") {
                NavigationLink {
                    PersonalCatalogView()
                } label: {
                    SettingsValueLabel(
                        title: "Personal Library",
                        systemImage: "books.vertical",
                        value: personalLibraryDescription
                    )
                }

                NavigationLink {
                    CustomImportGuideView()
                } label: {
                    Label("AI Food & Meal Import", systemImage: "square.and.arrow.down")
                }
            }

            Section("Connections") {
                NavigationLink {
                    AppleHealthSettingsView()
                } label: {
                    SettingsValueLabel(
                        title: "Apple Health",
                        systemImage: "heart.fill",
                        value: appleHealthStatus
                    )
                }
            }

            Section("Data & Privacy") {
                NavigationLink {
                    FoodDataSourcesView(catalog: catalog)
                } label: {
                    SettingsValueLabel(
                        title: "Food Data Sources",
                        systemImage: "cylinder.split.1x2",
                        value: "USDA · Open Food Facts"
                    )
                }

                NavigationLink {
                    PrivacyAnalyticsView()
                } label: {
                    Label("Privacy & Analytics", systemImage: "hand.raised.fill")
                }
            }

#if DEBUG
            Section("Developer") {
                NavigationLink {
                    DeveloperDiagnosticsView()
                } label: {
                    Label("Developer Diagnostics", systemImage: "wrench.and.screwdriver.fill")
                }
            }
#endif

        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Settings")
        .analyticsScreen("settings")
    }

    private var calorieGoalDescription: String {
        diary.dailyCalorieGoal.map { "\($0.formatted()) cal" } ?? "Not Set"
    }

    private var personalLibraryDescription: String {
        let foodCount = diary.document.customFoods.count
        let mealCount = diary.document.meals.count
        return "\(foodCount) \(foodCount == 1 ? "food" : "foods") · \(mealCount) \(mealCount == 1 ? "meal" : "meals")"
    }

    private var appleHealthStatus: String {
        switch healthKit.authorizationState {
        case .authorized: "Connected"
        case .notDetermined: "Not Connected"
        case .denied: "Access Off"
        case .unavailable: "Unavailable"
        }
    }
}

private struct SettingsValueLabel: View {
    let title: String
    let systemImage: String
    let value: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

private struct CalorieGoalSettingsView: View {
    @EnvironmentObject private var diary: DiaryStore
    @FocusState private var calorieGoalIsFocused: Bool

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Calories per day")
                    Spacer()
                    TextField("Not set", text: calorieGoalText)
                        .focused($calorieGoalIsFocused)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 90)
                    if diary.dailyCalorieGoal != nil {
                        Text("cal")
                            .foregroundStyle(.secondary)
                    }
                }

                if diary.dailyCalorieGoal != nil {
                    Button("Remove Goal", role: .destructive) {
                        diary.setDailyCalorieGoal(nil)
                    }
                }
            } header: {
                Text("Daily Goal")
            } footer: {
                Text("Optional. When set, the diary shows calories consumed against this daily goal.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Calorie Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Save") {
                    calorieGoalIsFocused = false
                }
            }
        }
        .analyticsScreen("settings_calorie_goal")
    }

    private var calorieGoalText: Binding<String> {
        Binding(
            get: { diary.dailyCalorieGoal.map(String.init) ?? "" },
            set: { value in
                let digits = value.filter(\.isNumber)
                diary.setDailyCalorieGoal(Int(digits))
            }
        )
    }
}

private struct AppleHealthSettingsView: View {
    @EnvironmentObject private var diary: DiaryStore
    @EnvironmentObject private var healthKit: HealthKitStore

    @State private var syncingNutrition = false

    private let minimumSyncSpinnerDuration: TimeInterval = 0.35

    var body: some View {
        Form {
            Section("Status") {
                switch healthKit.authorizationState {
                case .authorized:
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.protein)
                    Button {
                        Task {
                            await syncLoggedNutrition()
                        }
                    } label: {
                        if syncingNutrition {
                            HStack {
                                ProgressView()
                                Text("Syncing logged nutrition…")
                            }
                        } else {
                            Label("Sync Logged Nutrition", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(syncingNutrition)
                case .notDetermined:
                    Button("Connect Apple Health", systemImage: "heart.fill") {
                        Task {
                            await connectAppleHealth()
                        }
                    }
                case .denied:
                    Label("Access is turned off", systemImage: "exclamationmark.triangle")
                    Text("Allow nutrition data in the Health app's Apps settings to reconnect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .unavailable:
                    Label("Apple Health is unavailable", systemImage: "heart.slash")
                    Text("Health data can only be written on a device that supports Apple Health.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = healthKit.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Nutrition Data") {
                Text("Calorie Tracker writes calories, carbohydrates, fat, protein, and available fiber for logged foods, meals, and alcohol estimates.")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen("settings_apple_health")
    }

    private func syncLoggedNutrition() async {
        syncingNutrition = true
        let startedAt = Date()

        AppAnalytics.capture("health.sync_requested", properties: ["source": "manual"])
        healthKit.clearLastError()
        diary.syncAllHealthData()
        await healthKit.waitForPendingOperations()
        AppAnalytics.capture("health.sync_completed", properties: [
            "source": "manual",
            "result": healthKit.lastError == nil ? "success" : "failure"
        ])

        let remainingDuration = minimumSyncSpinnerDuration - Date().timeIntervalSince(startedAt)
        if remainingDuration > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remainingDuration * 1_000_000_000))
        }

        syncingNutrition = false
    }

    private func connectAppleHealth() async {
        AppAnalytics.capture("health.authorization_requested")
        healthKit.clearLastError()
        await healthKit.requestAuthorizationAndSync(entries: [])
        AppAnalytics.capture("health.authorization_completed", properties: [
            "result": healthKit.authorizationState.analyticsValue
        ])
        guard healthKit.authorizationState == .authorized else { return }

        AppAnalytics.capture("health.sync_requested", properties: ["source": "authorization"])
        healthKit.clearLastError()
        diary.syncAllHealthData()
        await healthKit.waitForPendingOperations()
        AppAnalytics.capture("health.sync_completed", properties: [
            "source": "authorization",
            "result": healthKit.lastError == nil ? "success" : "failure"
        ])
    }
}

private struct FoodDataSourcesView: View {
    let catalog: CatalogStore

    var body: some View {
        List {
            Section("Local Catalogs") {
                sourceRow(.usda, count: catalog.count(source: .usda))
                sourceRow(.openFoodFacts, count: catalog.count(source: .openFoodFacts))
            }

            Section("Source Links") {
                Link("USDA FoodData Central", destination: URL(string: "https://fdc.nal.usda.gov/")!)
                Link("Open Food Facts", destination: URL(string: "https://world.openfoodfacts.org/")!)
            }

            Section("Attribution") {
                Text("USDA records are U.S. government public-domain data. Open Food Facts database records are reused under ODbL with source attribution and remain identifiable in this derived local database.")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Food Data Sources")
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen("settings_food_data_sources")
    }

    private func sourceRow(_ source: FoodSource, count: Int) -> some View {
        HStack {
            SourceBadge(source: source)
            Text(source.title)
            Spacer()
            Text(count.formatted())
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct PrivacyAnalyticsView: View {
    var body: some View {
        List {
            Section("On Your Device") {
                Text("Your diary, personal foods, saved meals, and remembered quantities are stored on your device. The food catalog and search index are bundled with the app, so routine logging does not depend on a network connection.")
                    .foregroundStyle(.secondary)
            }

            Section("Analytics") {
                Text("When analytics is enabled, the app sends feature-usage events, catalog or local item identifiers, successful and failed food search terms, searches dismissed without logging, and unmatched barcodes to its private analytics service.")
                    .foregroundStyle(.secondary)
                Label("Food names, meal contents, quantities, calorie totals, and Health data are not sent.", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(AppTheme.protein)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Privacy & Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen("settings_privacy_analytics")
    }
}

#if DEBUG
private struct DeveloperDiagnosticsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    ExperimentalFeaturesView()
                } label: {
                    Label("Experimental Features", systemImage: "flask.fill")
                }

                NavigationLink {
                    AnalyticsDiagnosticsView()
                } label: {
                    Label("Analytics Events", systemImage: "chart.line.uptrend.xyaxis")
                }
            } footer: {
                Text("Inspect the local event queue, upload state, retries, and recent delivery outcomes.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Developer Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen("developer_diagnostics")
    }
}

private struct ExperimentalFeaturesView: View {
    @AppStorage("experimental.alwaysShowQuickCalories") private var alwaysShowQuickCalories = false

    var body: some View {
        Form {
            Section {
                Toggle("Always show quick calories", isOn: $alwaysShowQuickCalories)
            } footer: {
                Text("Shows the +500, +1,000, +1,500, and +2,000 calorie shortcuts on every day. When disabled, they appear only on cheat days or when that day already has an adjustment.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Experimental Features")
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen("developer_experimental_features")
    }
}

private struct AnalyticsDiagnosticsView: View {
    @State private var snapshot: AnalyticsDiagnosticsSnapshot?
    @State private var isUploading = false
    @State private var showingClearConfirmation = false

    private let analytics = AnalyticsService.shared

    var body: some View {
        List {
            if let currentSnapshot = snapshot {
                Section {
                    if currentSnapshot.recentEvents.isEmpty {
                        Text("No recent events")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(currentSnapshot.recentEvents) { event in
                            NavigationLink {
                                AnalyticsEventPayloadView(event: event)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: eventStateIcon(event.state))
                                        .foregroundStyle(eventStateColor(event.state))
                                        .frame(width: 24)
                                        .accessibilityLabel(event.stateTitle)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(event.type)
                                            .font(.body.monospaced())
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                        Text(event.occurredAt.formatted(date: .abbreviated, time: .standard))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Events")
                } footer: {
                    Text("Select an event to inspect its payload. Request headers, signatures, and configuration secrets are never shown here.")
                }

                Section("Queue") {
                    diagnosticRow("Status", currentSnapshot.status)
                    diagnosticRow("Queued events", currentSnapshot.queuedEventCount.formatted())
                    diagnosticRow("Prepared batches", currentSnapshot.preparedBatchCount.formatted())
                    diagnosticRow("Oldest unsent", oldestAgeDescription(currentSnapshot.oldestUnsentAge))
                    diagnosticRow("Batch ID", currentSnapshot.latestBatchID ?? "—")
                    diagnosticRow("Retry attempt", currentSnapshot.retryAttempt.formatted())
                    diagnosticRow("Next retry", currentSnapshot.nextRetryAt?.formatted(date: .abbreviated, time: .standard) ?? "—")
                    diagnosticRow("Redirect host", currentSnapshot.redirectHost ?? "—")
                    diagnosticRow("Stop logging", currentSnapshot.stopLogging ? "Yes" : "No")
                }

                Section("Actions") {
                    Button {
                        refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button {
                        Task {
                            isUploading = true
                            await analytics.uploadNow()
                            snapshot = await analytics.diagnosticsSnapshot()
                            isUploading = false
                        }
                    } label: {
                        if isUploading {
                            HStack {
                                ProgressView()
                                Text("Uploading…")
                            }
                        } else {
                            Label("Upload now", systemImage: "arrow.up.circle")
                        }
                    }
                    .disabled(isUploading || currentSnapshot.queuedEventCount == 0)
                    Button("Copy diagnostics summary", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = currentSnapshot.redactedSummary
                    }
                    Button("Clear analytics queue", systemImage: "trash", role: .destructive) {
                        showingClearConfirmation = true
                    }
                }

                Section("Configuration") {
                    diagnosticRow("Enabled", currentSnapshot.enabled ? "Yes" : "No")
                    diagnosticRow("App", currentSnapshot.appName ?? "—")
                    diagnosticRow("Version", currentSnapshot.appVersion ?? "—")
                    diagnosticRow("Platform", currentSnapshot.platform ?? "—")
                    diagnosticRow("Audience", currentSnapshot.audience ?? "—")
                    diagnosticRow("Namespace", currentSnapshot.namespace ?? "—")
                    diagnosticRow("Key ID", currentSnapshot.keyID ?? "—")
                }
            } else {
                ProgressView()
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Analytics")
        .analyticsScreen("analytics_diagnostics")
        .task { refresh() }
        .refreshable { snapshot = await analytics.diagnosticsSnapshot() }
        .confirmationDialog(
            "Clear all queued analytics events?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear queue", role: .destructive) {
                Task {
                    await analytics.clearQueue()
                    snapshot = await analytics.diagnosticsSnapshot()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func refresh() {
        Task { snapshot = await analytics.diagnosticsSnapshot() }
    }

    private func oldestAgeDescription(_ age: TimeInterval?) -> String {
        guard let age else { return "—" }
        return Duration.seconds(age).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated))
    }

    private func eventStateIcon(_ state: String) -> String {
        switch state {
        case "uploaded": "checkmark.circle.fill"
        case "rejected", "expired", "stopped": "xmark.octagon.fill"
        case "retry_scheduled": "exclamationmark.triangle.fill"
        case "uploading", "prepared": "arrow.up.circle.fill"
        default: "circle.dashed"
        }
    }

    private func eventStateColor(_ state: String) -> Color {
        switch state {
        case "uploaded": AppTheme.protein
        case "rejected", "expired", "stopped": .red
        case "retry_scheduled": .orange
        case "uploading", "prepared": .blue
        default: AppTheme.muted
        }
    }
}

private struct AnalyticsEventPayloadView: View {
    let event: AnalyticsDiagnosticEvent

    var body: some View {
        List {
            Section("Delivery") {
                HStack {
                    Text("State")
                    Spacer()
                    Label(event.stateTitle, systemImage: eventStateIcon)
                        .foregroundStyle(eventStateColor)
                }
            }

            Section("Payload") {
                Text(event.payload?.formattedJSON ?? "Payload unavailable for events recorded before payload diagnostics were enabled.")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle(event.type)
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen("analytics_event_payload")
    }

    private var eventStateIcon: String {
        switch event.state {
        case "uploaded": "checkmark.circle.fill"
        case "rejected", "expired", "stopped": "xmark.octagon.fill"
        case "retry_scheduled": "exclamationmark.triangle.fill"
        case "uploading", "prepared": "arrow.up.circle.fill"
        default: "circle.dashed"
        }
    }

    private var eventStateColor: Color {
        switch event.state {
        case "uploaded": AppTheme.protein
        case "rejected", "expired", "stopped": .red
        case "retry_scheduled": .orange
        case "uploading", "prepared": .blue
        default: AppTheme.muted
        }
    }
}
#endif

struct FoodWeightReportView: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var shareURL: URL?
    @State private var shareRequest: FoodWeightReportShareRequest?
    @State private var sharePreparationError: String?

    private var report: FoodWeightReport {
        diary.foodWeightReport()
    }

    var body: some View {
        List {
            Section {
                Text("Diary coverage: \(report.coverageDescription)")
                    .foregroundStyle(.secondary)
            }

            Section("Foods") {
                if report.items.isEmpty {
                    ContentUnavailableView(
                        "No logged foods",
                        systemImage: "fork.knife",
                        description: Text("Log food to include it in the last-90-days report.")
                    )
                } else {
                    ForEach(report.items) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.name)
                            Spacer(minLength: 16)
                            Text("\(item.wholeOunces.formatted()) oz")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Food Weight Report")
        .analyticsScreen("food_weight_report")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let shareURL {
                        shareRequest = FoodWeightReportShareRequest(fileURL: shareURL)
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(shareURL == nil)
            }
        }
        .task(id: report.markdown) {
            prepareShareFile()
        }
        .alert("Couldn’t prepare report", isPresented: Binding(
            get: { sharePreparationError != nil },
            set: { if !$0 { sharePreparationError = nil } }
        )) {
            Button("Try again") {
                prepareShareFile()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(sharePreparationError ?? "Unknown error")
        }
        .sheet(item: $shareRequest) { request in
            FoodWeightReportShareSheet(fileURL: request.fileURL)
        }
    }

    private func prepareShareFile() {
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("CalorieTrackerReports", isDirectory: true)
            shareURL = try report.writeShareFile(in: directory)
            sharePreparationError = nil
        } catch {
            shareURL = nil
            sharePreparationError = error.localizedDescription
        }
    }
}

private struct FoodWeightReportShareRequest: Identifiable {
    let id = UUID()
    let fileURL: URL
}

private struct FoodWeightReportShareSheet: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct PersonalCatalogView: View {
    @EnvironmentObject private var diary: DiaryStore

    @State private var editingFood: Food?
    @State private var showingFoodEditor = false
    @State private var mealEditorPresentation: MealEditorPresentation?

    private enum MealEditorPresentation: Identifiable {
        case add
        case edit(SavedMeal)

        var id: String {
            switch self {
            case .add:
                return "add"
            case let .edit(meal):
                return meal.id.uuidString
            }
        }

        var meal: SavedMeal? {
            switch self {
            case .add:
                return nil
            case let .edit(meal):
                return meal
            }
        }
    }

    var body: some View {
        List {
            Section("Custom foods") {
                Button("Add", systemImage: "plus") {
                    editingFood = nil
                    showingFoodEditor = true
                }
                if diary.document.customFoods.isEmpty {
                    Label("No custom foods yet", systemImage: "fork.knife")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(diary.document.customFoods) { food in
                        FoodResultRow(food: food, preference: diary.preference(for: food))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingFood = food
                                showingFoodEditor = true
                            }
                            .swipeActions {
                                Button("Edit", systemImage: "pencil") {
                                    editingFood = food
                                    showingFoodEditor = true
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    diary.deleteCustomFood(food)
                                    AppAnalytics.capture(
                                        "custom_food.deleted",
                                        properties: ["origin": "custom_catalog"]
                                    )
                                }
                            }
                    }
                }
            }

            Section("Saved meals") {
                Button("Add", systemImage: "plus") {
                    mealEditorPresentation = .add
                }
                if diary.document.meals.isEmpty {
                    Label("No saved meals yet", systemImage: "square.stack.3d.up")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(diary.alphabetizedMeals) { meal in
                        PersonalMealRow(meal: meal)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                mealEditorPresentation = .edit(meal)
                            }
                            .swipeActions {
                                Button("Edit", systemImage: "pencil") {
                                    mealEditorPresentation = .edit(meal)
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    diary.deleteMeal(meal)
                                    AppAnalytics.capture(
                                        "meal.deleted",
                                        properties: ["origin": "custom_catalog"]
                                    )
                                }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Personal Library")
        .analyticsScreen("custom_catalog")
        .sheet(isPresented: $showingFoodEditor) {
            CustomFoodEditorView(food: editingFood)
        }
        .sheet(item: $mealEditorPresentation) { presentation in
            SavedMealEditorView(meal: presentation.meal)
        }
    }
}

private struct PersonalMealRow: View {
    let meal: SavedMeal

    var body: some View {
        HStack(spacing: 12) {
            MealBadge()
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name)
                    .font(.body.weight(.semibold))
                Text("\(meal.items.count) item\(meal.items.count == 1 ? "" : "s") · \(Int(meal.nutrients.calories.rounded())) cal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct CustomFoodEditorView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss

    private let food: Food?
    private let onSaved: ((Food) -> Void)?
    private let analyticsOrigin: String
    @State private var name: String
    @State private var brand: String
    @State private var calories: Double
    @State private var carbs: Double
    @State private var fat: Double
    @State private var protein: Double
    @State private var fiber: Double?
    @State private var servingGrams: Double
    @State private var containsProcessedMeat: Bool
    @State private var containsRedMeat: Bool
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case brand
        case calories
        case carbs
        case fat
        case protein
        case fiber
        case servingGrams

        var selectsAllOnFocus: Bool {
            switch self {
            case .calories, .carbs, .fat, .protein, .fiber, .servingGrams:
                return true
            case .name, .brand:
                return false
            }
        }
    }

    init(
        food: Food?,
        initialName: String? = nil,
        analyticsOrigin: String = "custom_catalog",
        onSaved: ((Food) -> Void)? = nil
    ) {
        self.food = food
        self.onSaved = onSaved
        self.analyticsOrigin = analyticsOrigin
        _name = State(initialValue: food?.name ?? initialName ?? "")
        _brand = State(initialValue: food?.brand ?? "")
        _calories = State(initialValue: food?.nutrients.calories ?? 0)
        _carbs = State(initialValue: food?.nutrients.carbs ?? 0)
        _fat = State(initialValue: food?.nutrients.fat ?? 0)
        _protein = State(initialValue: food?.nutrients.protein ?? 0)
        _fiber = State(initialValue: food?.nutrients.fiber)
        _servingGrams = State(initialValue: food?.servingGrams ?? food?.baseAmountGrams ?? 100)
        _containsProcessedMeat = State(initialValue: food?.containsProcessedMeat ?? false)
        _containsRedMeat = State(initialValue: food?.containsRedMeat ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    textFieldRow("Name", text: $name, field: .name)
                    textFieldRow("Brand (optional)", text: $brand, field: .brand)
                }

                Section("Nutrition per serving") {
                    decimalFieldRow("Calories", value: $calories, field: .calories)
                    decimalFieldRow("Carbohydrates (g)", value: $carbs, field: .carbs)
                    decimalFieldRow("Fat (g)", value: $fat, field: .fat)
                    decimalFieldRow("Protein (g)", value: $protein, field: .protein)
                    optionalDecimalFieldRow("Fiber (g, optional)", value: $fiber, field: .fiber)
                    decimalFieldRow("Serving size (g)", value: $servingGrams, field: .servingGrams)
                }

                Section {
                    Toggle("Contains processed meat", isOn: $containsProcessedMeat)
                    Toggle("Contains red meat", isOn: $containsRedMeat)
                } header: {
                    Text("Meat tracking")
                } footer: {
                    Text("Red meat tracks unprocessed mammalian meat. Set both when a mixed food contains both kinds.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle(food == nil ? "Add Custom Food" : "Edit Custom Food")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: focusedField) { _, field in
                guard field?.selectsAllOnFocus == true else { return }
                selectAllFocusedText()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .analyticsScreen("custom_food_editor", properties: [
                "operation": food == nil ? "create" : "edit",
                "origin": analyticsOrigin
            ])
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            servingGrams > 0
    }

    private func textFieldRow(_ label: String, text: Binding<String>, field: Field) -> some View {
        LabeledContent {
            TextField("", text: text)
                .focused($focusedField, equals: field)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        } label: {
            Text(label)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { focus(field) }
    }

    private func decimalFieldRow(_ label: String, value: Binding<Double>, field: Field) -> some View {
        LabeledContent {
            TextField("", value: value, format: .number)
                .focused($focusedField, equals: field)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
                .foregroundStyle(.primary)
        } label: {
            Text(label)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { focus(field) })
    }

    private func optionalDecimalFieldRow(
        _ label: String,
        value: Binding<Double?>,
        field: Field
    ) -> some View {
        LabeledContent {
            TextField("", value: value, format: .number)
                .focused($focusedField, equals: field)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
                .foregroundStyle(.primary)
        } label: {
            Text(label)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { focus(field) })
    }

    private func save() {
        guard canSave else { return }
        let savedFood: Food?
        if let food {
            guard diary.updateCustomFood(
                foodID: food.id,
                name: name,
                brand: brand,
                calories: calories,
                carbs: carbs,
                fat: fat,
                protein: protein,
                fiber: fiber,
                servingGrams: servingGrams,
                containsProcessedMeat: containsProcessedMeat,
                containsRedMeat: containsRedMeat
            ) else { return }
            savedFood = diary.document.customFoods.first { $0.id == food.id }
        } else {
            savedFood = diary.addCustomFood(
                name: name,
                brand: brand,
                calories: calories,
                carbs: carbs,
                fat: fat,
                protein: protein,
                fiber: fiber,
                servingGrams: servingGrams,
                containsProcessedMeat: containsProcessedMeat,
                containsRedMeat: containsRedMeat
            )
        }
        if let savedFood {
            AppAnalytics.capture(food == nil ? "custom_food.created" : "custom_food.updated", properties: [
                "origin": analyticsOrigin
            ])
            onSaved?(savedFood)
        }
        dismiss()
    }

    private func focus(_ field: Field) {
        focusedField = field
        if field.selectsAllOnFocus {
            selectAllFocusedText()
        }
    }

    private func selectAllFocusedText() {
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(
                #selector(UIResponder.selectAll(_:)),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}

private struct SavedMealEditorView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss

    private let meal: SavedMeal?
    @State private var name: String
    @State private var items: [MealItem]
    @State private var containsProcessedMeat: Bool
    @State private var containsRedMeat: Bool
    @State private var showingFoodPicker = false

    init(meal: SavedMeal?) {
        self.meal = meal
        _name = State(initialValue: meal?.name ?? "")
        _items = State(initialValue: meal?.items ?? [])
        _containsProcessedMeat = State(initialValue: meal?.resolvedContainsProcessedMeat ?? false)
        _containsRedMeat = State(initialValue: meal?.resolvedContainsRedMeat ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("Name", text: $name)
                }

                Section("Foods") {
                    if items.isEmpty {
                        Text("Add at least one food to save this meal.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach($items) { item in
                        SavedMealItemEditorRow(item: item) {
                            let itemID = item.wrappedValue.id
                            items.removeAll { $0.id == itemID }
                        }
                    }
                    Button("Add food", systemImage: "plus") {
                        showingFoodPicker = true
                    }
                }

                Section {
                    Toggle("Contains processed meat", isOn: $containsProcessedMeat)
                    Toggle("Contains red meat", isOn: $containsRedMeat)
                } header: {
                    Text("Meat tracking")
                } footer: {
                    Text("These meal-level flags control how every logged serving of this meal appears in Trends.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle(meal == nil ? "Add Saved Meal" : "Edit Saved Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || items.isEmpty)
                }
            }
            .sheet(isPresented: $showingFoodPicker) {
                MealFoodPickerView(foods: availableFoods) { food in
                    let preference = diary.preference(for: food)
                    items.append(MealItem(
                        id: UUID(),
                        food: food,
                        amount: preference.amount,
                        unit: preference.unit,
                        portionID: preference.portionID
                    ))
                    containsProcessedMeat = containsProcessedMeat || food.containsProcessedMeat == true
                    containsRedMeat = containsRedMeat || food.containsRedMeat == true
                }
            }
            .analyticsScreen("saved_meal_editor", properties: [
                "operation": meal == nil ? "create" : "edit",
                "origin": "custom_catalog"
            ])
        }
    }

    private var availableFoods: [Food] {
        var seen = Set<String>()
        let candidates = diary.document.customFoods
            + diary.document.favorites
            + diary.document.entries
                .filter { !$0.isMeal && !$0.isCheatDayAdjustment }
                .map(\.food)
            + diary.document.meals.flatMap { $0.items.map(\.food) }
        return candidates.compactMap { food in
            guard seen.insert(food.id).inserted else { return nil }
            return diary.displayedFood(food)
        }
        .sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !items.isEmpty else { return }
        if let meal {
            guard diary.updateSavedMeal(
                mealID: meal.id,
                name: name,
                items: items,
                containsProcessedMeat: containsProcessedMeat,
                containsRedMeat: containsRedMeat
            ) else { return }
            AppAnalytics.capture("meal.updated", properties: [
                "origin": "custom_catalog",
                "item_count": String(items.count)
            ])
        } else {
            guard diary.saveMeal(
                name: name,
                items: items,
                containsProcessedMeat: containsProcessedMeat,
                containsRedMeat: containsRedMeat
            ) != nil else { return }
            AppAnalytics.capture("meal.created", properties: [
                "origin": "custom_catalog",
                "item_count": String(items.count)
            ])
        }
        dismiss()
    }
}

private struct SavedMealItemEditorRow: View {
    @Binding var item: MealItem
    let onDelete: () -> Void
    @FocusState private var amountIsFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.food.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(quantityDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Amount", value: amountBinding, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 80)
                .focused($amountIsFocused)
                .onChange(of: amountIsFocused) { _, isFocused in
                    if isFocused {
                        selectAllAmount()
                    }
                }
            .accessibilityLabel("Quantity for \(item.food.name)")
        }
        .swipeActions {
            Button("Remove", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var amountBinding: Binding<Double> {
        Binding(
            get: { item.amount },
            set: { item.amount = min(max($0, 0.01), 100) }
        )
    }

    private func selectAllAmount() {
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(
                #selector(UIResponder.selectAll(_:)),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }

    private var quantityDescription: String {
        switch item.unit {
        case .grams, .ounces:
            return "\(item.amount.cleanAmount) \(item.unit.rawValue)"
        case .serving:
            return "\(item.amount.cleanAmount) \(item.food.portion(id: item.portionID)?.label ?? "serving")"
        }
    }
}

private struct MealFoodPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let foods: [Food]
    let onSelect: (Food) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                Group {
                    if foods.isEmpty {
                        ContentUnavailableView(
                            "No foods available",
                            systemImage: "fork.knife.circle",
                            description: Text("Add a custom food or log a food before creating a saved meal.")
                        )
                    } else {
                        List(foods) { food in
                            Button {
                                onSelect(food)
                                dismiss()
                            } label: {
                                FoodResultRow(food: food)
                            }
                            .buttonStyle(.plain)
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
