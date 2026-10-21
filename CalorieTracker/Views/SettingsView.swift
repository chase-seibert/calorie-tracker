import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
                Text("Choose which focused health metrics appear in the app and tailor your snack suggestions. Changing these preferences doesn't change your logged data.")
            }

            Section("Food & Meals") {
                NavigationLink {
                    SnackSuggestionsView()
                } label: {
                    Label("Snack Suggestions", systemImage: "carrot")
                }
                NavigationLink {
                    ReviewClassificationsView()
                } label: {
                    Label("Review Classifications", systemImage: "checklist")
                }
                NavigationLink {
                    PersonalCatalogView(catalog: catalog)
                } label: {
                    SettingsValueLabel(
                        title: "Personal Library",
                        systemImage: "books.vertical",
                        value: personalLibraryDescription
                    )
                }
                NavigationLink {
                    HiddenFoodsView()
                } label: {
                    Label("Hidden Foods", systemImage: "eye.slash")
                }

                NavigationLink {
                    CustomImportGuideView()
                } label: {
                    Label("AI Food & Meal Import", systemImage: "square.and.arrow.down")
                }

                NavigationLink {
                    FoodDataSourcesView(catalog: catalog)
                } label: {
                    SettingsValueLabel(
                        title: "Food Data Sources",
                        systemImage: "cylinder.split.1x2",
                        value: "USDA · Open Food Facts"
                    )
                }
            }

            Section("Connections") {
                NavigationLink {
                    OpenAISettingsView()
                } label: {
                    SettingsValueLabel(
                        title: "OpenAI API",
                        systemImage: "sparkles",
                        value: openAIStatus
                    )
                }
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

            Section("Reports") {
                NavigationLink {
                    WeeklyFoodReportView()
                } label: {
                    Label("Weekly Food Report", systemImage: "chart.bar.doc.horizontal")
                }
                NavigationLink {
                    WeeklyFoodReportSettingsView()
                } label: {
                    Label("Weekly Report Settings", systemImage: "slider.horizontal.3")
                }
            }

            Section("Data & Privacy") {
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
        let mealCount = diary.customMeals.count
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

    private var openAIStatus: String {
        do { return try OpenAICredentialStore.shared.load() == nil ? "Not configured" : "Configured" }
        catch { return "Unavailable" }
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
    @State private var goalDraft = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Calories per day")
                    Spacer()
                    TextField("Not set", text: $goalDraft)
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
                        goalDraft = ""
                        diary.run {
                            try await diary.setDailyCalorieGoal(nil)

                        }
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
                    saveGoal()
                }
            }
        }
        .analyticsScreen("settings_calorie_goal")
        .onAppear { goalDraft = diary.dailyCalorieGoal.map(String.init) ?? "" }
        .onDisappear { saveGoal() }
    }

    private func saveGoal() {
        let value = Int(goalDraft.filter(\.isNumber))
        guard value != diary.dailyCalorieGoal else { return }
        diary.run { try await diary.setDailyCalorieGoal(value) }
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
                Text("Yum Chase writes calories, carbohydrates, fat, protein, and available fiber for logged foods, meals, and alcohol estimates.")
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
        await diary.syncAllHealthData()
        await healthKit.waitForPendingOperations()
        AppAnalytics.capture(
            "health.sync_completed",
            properties: [
                "source": "manual",
                "result": healthKit.lastError == nil ? "success" : "failure",
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
        AppAnalytics.capture(
            "health.authorization_completed",
            properties: [
                "result": healthKit.authorizationState.analyticsValue
            ])
        guard healthKit.authorizationState == .authorized else { return }

        AppAnalytics.capture("health.sync_requested", properties: ["source": "authorization"])
        healthKit.clearLastError()
        await diary.syncAllHealthData()
        await healthKit.waitForPendingOperations()
        AppAnalytics.capture(
            "health.sync_completed",
            properties: [
                "source": "authorization",
                "result": healthKit.lastError == nil ? "success" : "failure",
            ])
    }
}

private struct HiddenFoodsView: View {
    @EnvironmentObject private var diary: DiaryStore

    var body: some View {
        List {
            if diary.document.hiddenFoods.isEmpty {
                ContentUnavailableView(
                    "No Hidden Foods",
                    systemImage: "eye",
                    description: Text("Foods you hide from search will appear here.")
                )
            } else {
                Section {
                    ForEach(diary.document.hiddenFoods) { record in
                        HStack(spacing: 12) {
                            SourceBadge(source: record.food.source)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.food.name)
                                    .lineLimit(2)
                                if let brand = record.food.displayBrand {
                                    Text(brand)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(record.food.source.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button("Restore", systemImage: "arrow.uturn.backward") {
                                diary.run {
                                    try await diary.restoreHiddenFood(id: record.id)
                                }
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Restore \(record.food.name) to search")
                        }
                    }
                } footer: {
                    Text("Restoring a food makes it searchable again. Hiding foods does not change diary history.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Hidden Foods")
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen("settings_hidden_foods")
    }
}

private struct FoodDataSourcesView: View {
    let catalog: CatalogStore
    @AppStorage("foodSource.enabled.usda") private var usdaEnabled = true
    @AppStorage("foodSource.enabled.off") private var offEnabled = true
    @AppStorage("foodSource.enabled.chaseFood") private var chaseFoodEnabled = false

    var body: some View {
        List {
            Section("Local Catalogs") {
                sourceRow(.usda, count: catalog.count(source: .usda), isEnabled: $usdaEnabled)
                sourceRow(.openFoodFacts, count: catalog.count(source: .openFoodFacts), isEnabled: $offEnabled)
                sourceRow(.chaseFood, count: catalog.count(source: .chaseFood), isEnabled: $chaseFoodEnabled)
            }

            Section("Source Links") {
                Link("USDA FoodData Central", destination: URL(string: "https://fdc.nal.usda.gov/")!)
                Link("Open Food Facts", destination: URL(string: "https://world.openfoodfacts.org/")!)
            }

            Section("Attribution") {
                Text("USDA records are U.S. government public-domain data. Open Food Facts database records are reused under ODbL with source attribution and remain identifiable in this derived local database.")
                    .foregroundStyle(.secondary)
                Text("Chase Food is a personal canonical catalog. Its initial nutrient values are matched from existing local catalog records and have varying review confidence.")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Food Data Sources")
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen("settings_food_data_sources")
    }

    private func sourceRow(_ source: FoodSource, count: Int, isEnabled: Binding<Bool>) -> some View {
        HStack {
            SourceBadge(source: source)
            Text(source.title)
            Spacer()
            Text(count.formatted())
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Toggle("Show \(source.title) in search", isOn: isEnabled)
                .labelsHidden()
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

            Section("Optional Reminders Export") {
                Text("Snack suggestions are generated from an on-device library. If you connect Apple Reminders, only the snacks you select and their serving tips are added when you tap Add. The chosen list may sync through its account or be shared with others. Your diary and focus settings aren't exported.")
                    .foregroundStyle(.secondary)
            }

            Section("Analytics") {
                Text("When analytics is enabled, the app sends feature-usage events, catalog or local item identifiers, successful and failed food search terms, searches dismissed without logging, and unmatched barcodes to its private analytics service. If you submit food feedback, the text you enter is also sent with that event.")
                    .foregroundStyle(.secondary)
                Label("Analytics do not include diary food names, meal contents, quantities, calorie totals, or Health data. If you generate an AI weekly report, its settings explain the limited diary summary and repeated food names sent for that request. Food feedback text is sent only when you submit it.", systemImage: "checkmark.shield.fill")
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
    @EnvironmentObject private var diary: DiaryStore
    @AppStorage(FirstTimeOnboarding.completedKey) private var completedFocusOnboarding = false
    @AppStorage("trends.focus.alcohol") private var tracksAlcohol = true
    @AppStorage("trends.focus.fiber") private var tracksFiber = true
    @AppStorage("trends.focus.processedMeat") private var tracksProcessedMeat = true
    @AppStorage("trends.focus.redMeat") private var tracksRedMeat = true
    @State private var showingOnboardingResetConfirmation = false
    @State private var showingDatabaseExporter = false
    @State private var showingDatabaseImporter = false
    @State private var showingDatabaseImportConfirmation = false
    @State private var showingDatabaseRollbackConfirmation = false
    @State private var databaseDocument: DiaryDatabaseFileDocument?
    @State private var pendingDatabaseImportURL: URL?
    @State private var pendingDatabaseRollback: DiaryDatabaseBackup?
    @State private var databaseBackups = [DiaryDatabaseBackup]()
    @State private var databaseTransferMessage: String?
    @State private var databaseTransferError: String?
    @State private var isTransferringDatabase = false
    @StateObject private var weeklyReport = WeeklyReportCoordinator.shared
    @State private var showingWeeklyReport = false

    var body: some View {
        List {
            Section("Weekly Report") {
                Button {
                    Task {
                        do {
                            let document = try await diary.weeklyReportDocument()
                            await weeklyReport.generate(document: document, force: true)
                            if weeklyReport.report != nil, weeklyReport.errorMessage == nil {
                                showingWeeklyReport = true
                            }
                        } catch {
                            weeklyReport.errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Label(weeklyReport.isGenerating ? "Generating Weekly Report…" : "Generate Weekly Report Now", systemImage: "sparkles")
                }
                .disabled(weeklyReport.isGenerating)
                if let message = weeklyReport.statusMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
                if let message = weeklyReport.errorMessage { Text(message).font(.footnote).foregroundStyle(.red) }
            }

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

            Section("First-Time Experience") {
                Button("Reset First-Time Onboarding", systemImage: "arrow.counterclockwise") {
                    showingOnboardingResetConfirmation = true
                }
            }

            databaseTransferSection
            databaseBackupSection
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Developer Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen("developer_diagnostics")
        .navigationDestination(isPresented: $showingWeeklyReport) {
            WeeklyFoodReportView()
        }
        .alert("Reset first-time onboarding?", isPresented: $showingOnboardingResetConfirmation) {
            Button("Reset", role: .destructive) {
                tracksAlcohol = true
                tracksFiber = true
                tracksProcessedMeat = true
                tracksRedMeat = true
                NotificationCenter.default.post(name: FirstTimeOnboarding.resetNotification, object: nil)
                completedFocusOnboarding = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores the default focus selections, returns to Home, and presents onboarding again. Your logged foods, custom foods, and saved meals are not deleted.")
        }
        .fileExporter(
            isPresented: $showingDatabaseExporter,
            document: databaseDocument,
            contentType: .yumChaseSQLiteDatabase,
            defaultFilename: "YumChase-Database"
        ) { result in
            switch result {
            case .success:
                databaseTransferMessage = "SQLite database exported successfully."
            case let .failure(error):
                databaseTransferError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showingDatabaseImporter,
            allowedContentTypes: [.yumChaseSQLiteDatabase],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                pendingDatabaseImportURL = urls.first
                showingDatabaseImportConfirmation = pendingDatabaseImportURL != nil
            case let .failure(error):
                databaseTransferError = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Import this SQLite database?",
            isPresented: $showingDatabaseImportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Import", role: .destructive) {
                guard let url = pendingDatabaseImportURL else { return }
                importDatabase(from: url)
            }
            Button("Cancel", role: .cancel) {
                pendingDatabaseImportURL = nil
            }
        } message: {
            Text("This replaces the current diary with the selected standalone SQLite export. A verified backup of the current diary is created first.")
        }
        .confirmationDialog(
            "Restore this SQLite backup?",
            isPresented: $showingDatabaseRollbackConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                guard let backup = pendingDatabaseRollback else { return }
                pendingDatabaseRollback = nil
                importDatabase(from: backup.url, successMessage: "SQLite database restored")
            }
            Button("Cancel", role: .cancel) {
                pendingDatabaseRollback = nil
            }
        } message: {
            Text("This switches the diary back to the selected snapshot. A verified backup of the current diary is created first.")
        }
        .alert("Database transfer failed", isPresented: Binding(
            get: { databaseTransferError != nil },
            set: { if !$0 { databaseTransferError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(databaseTransferError ?? "Unknown database transfer error.")
        }
        .task {
            refreshDatabaseBackups()
        }
    }

    private var databaseTransferSection: some View {
        Section {
            Button {
                exportDatabase()
            } label: {
                Label("Export SQLite Database", systemImage: "square.and.arrow.up")
            }
            .disabled(diary.isSaving || isTransferringDatabase)

            Button {
                showingDatabaseImporter = true
            } label: {
                Label("Import SQLite Database", systemImage: "square.and.arrow.down")
            }
            .disabled(diary.isSaving || isTransferringDatabase)

            if isTransferringDatabase {
                ProgressView("Transferring database…")
            }
            if let message = databaseTransferMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("SQLite Database")
        } footer: {
            Text("Exports use SQLite's online backup API and include committed WAL content. Import replaces the current diary after creating a verified backup.")
        }
    }

    private var databaseBackupSection: some View {
        Section {
            if databaseBackups.isEmpty {
                Text("No recent database backups.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(databaseBackups) { backup in
                    Button {
                        pendingDatabaseRollback = backup
                        showingDatabaseRollbackConfirmation = true
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                            Text(backup.url.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(diary.isSaving || isTransferringDatabase)
                }
            }
        } header: {
            Text("Previous Backups")
        } footer: {
            Text("The app keeps up to eight import backups for 30 days. Tap a backup to restore it; the current database is backed up first.")
        }
    }

    private func exportDatabase() {
        databaseTransferMessage = nil
        databaseTransferError = nil
        isTransferringDatabase = true
        Task {
            defer { isTransferringDatabase = false }
            do {
                databaseDocument = DiaryDatabaseFileDocument(data: try await diary.exportDatabase())
                showingDatabaseExporter = true
            } catch {
                databaseTransferError = error.localizedDescription
            }
        }
    }

    private func refreshDatabaseBackups() {
        databaseBackups = diary.databaseBackups()
    }

    private func importDatabase(from url: URL, successMessage: String = "SQLite database imported") {
        pendingDatabaseImportURL = nil
        databaseTransferMessage = nil
        databaseTransferError = nil
        isTransferringDatabase = true
        Task {
            defer { isTransferringDatabase = false }
            do {
                let backup = try await diary.importDatabase(from: url)
                databaseTransferMessage = "\(successMessage). Current data was backed up as \(backup.lastPathComponent)."
                refreshDatabaseBackups()
            } catch {
                databaseTransferError = error.localizedDescription
            }
        }
    }
}

private extension UTType {
    static var yumChaseSQLiteDatabase: UTType {
        UTType(filenameExtension: "sqlite") ?? .data
    }
}

private struct DiaryDatabaseFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.yumChaseSQLiteDatabase] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw DiaryDatabaseError.invalidData("The selected file is not a regular SQLite export.")
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct ExperimentalFeaturesView: View {
    @AppStorage("experimental.alwaysShowQuickCalories") private var alwaysShowQuickCalories = false
    @AppStorage(FoodSearchRankingVersion.preferenceKey)
    private var searchRankingVersion = FoodSearchRankingVersion.latest.rawValue

    private var selectedSearchRankingVersion: FoodSearchRankingVersion {
        FoodSearchRankingVersion(rawValue: searchRankingVersion) ?? .latest
    }

    var body: some View {
        Form {
            Section {
                Toggle("Always show quick calories", isOn: $alwaysShowQuickCalories)
            } footer: {
                Text("Shows the +500, +1,000, +1,500, and +2,000 calorie shortcuts on every day. When disabled, they appear only on cheat days or when that day already has an adjustment.")
            }

            Section {
                LabeledContent("Current version", value: selectedSearchRankingVersion.currentStatus)
                Picker("Food search ranking", selection: $searchRankingVersion) {
                    ForEach(FoodSearchRankingVersion.orderedByVersion) { version in
                        Text(version.title).tag(version.rawValue)
                    }
                }
            } footer: {
                Text("Versions are listed oldest to newest. The latest version is marked in the list and shown above; the selected version takes effect on the next search.")
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
    let catalog: CatalogStore

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
            case .edit(let meal):
                return meal.id.uuidString
            }
        }

        var meal: SavedMeal? {
            switch self {
            case .add:
                return nil
            case .edit(let meal):
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
                                    diary.run {
                                        try await diary.deleteCustomFood(food)
                                        AppAnalytics.capture(
                                            "custom_food.deleted",
                                            properties: ["origin": "custom_catalog"]
                                        )

                                    }
                                }
                            }
                    }
                }
            }

            Section("Saved meals") {
                Button("Add", systemImage: "plus") {
                    mealEditorPresentation = .add
                }
                if diary.customMeals.isEmpty {
                    Label("No saved meals yet", systemImage: "square.stack.3d.up")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(diary.customMeals) { meal in
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
                                    diary.run {
                                        try await diary.deleteMeal(meal)
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
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Personal Library")
        .analyticsScreen("custom_catalog")
        .sheet(isPresented: $showingFoodEditor) {
            CustomFoodEditorView(food: editingFood)
        }
        .sheet(item: $mealEditorPresentation) { presentation in
            SavedMealEditorView(meal: presentation.meal, catalog: catalog)
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
    private let savesToLibrary: Bool
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
    @State private var containsProcessedMeat: Bool?
    @State private var containsRedMeat: Bool?
    @State private var meatChoicesChanged = false
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
        savesToLibrary: Bool = true,
        onSaved: ((Food) -> Void)? = nil
    ) {
        self.food = food
        self.savesToLibrary = savesToLibrary
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
        _containsProcessedMeat = State(initialValue: food?.meatResolution?.processed.isAutomatic == true ? nil : food?.containsProcessedMeat)
        _containsRedMeat = State(initialValue: food?.meatResolution?.red.isAutomatic == true ? nil : food?.containsRedMeat)
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
                    FoodMeatFields(name: name,
                        processed: Binding(get: { containsProcessedMeat }, set: { containsProcessedMeat = $0; meatChoicesChanged = true }),
                        red: Binding(get: { containsRedMeat }, set: { containsRedMeat = $0; meatChoicesChanged = true }))
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
        if !savesToLibrary {
            let definition = CustomFoodDefinition(name: name, servingDescription: "serving", servingGrams: servingGrams,
                nutrition: .init(calories: calories, carbohydratesGrams: carbs, fatGrams: fat, proteinGrams: protein, fiberGrams: fiber),
                notes: nil, containsProcessedMeat: containsProcessedMeat, containsRedMeat: containsRedMeat)
            var draft = definition.makeFood()
            draft.brand = brand.isEmpty ? nil : brand
            onSaved?(draft)
            dismiss()
            return
        }
        diary.run {
            guard canSave else { return }
            let savedFood: Food?
            if let food {
                guard
                    try await diary.updateCustomFood(
                        foodID: food.id,
                        name: name,
                        brand: brand,
                        calories: calories,
                        carbs: carbs,
                        fat: fat,
                        protein: protein,
                        fiber: fiber,
                        servingGrams: servingGrams,
                        meatOverrides: meatChoicesChanged ? FoodMeatOverrides(processed: containsProcessedMeat, red: containsRedMeat) : nil
                    )
                else { return }
                savedFood = diary.document.customFoods.first { $0.id == food.id }
            } else {
                savedFood = try await diary.addCustomFood(
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
                AppAnalytics.capture(
                    food == nil ? "custom_food.created" : "custom_food.updated",
                    properties: [
                        "origin": analyticsOrigin
                    ])
                onSaved?(savedFood)
            }
            dismiss()

        }
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
    let meal: SavedMeal?
    let catalog: CatalogStore
    var body: some View { MealDetailView(context: .template(meal), catalog: catalog) }
}
