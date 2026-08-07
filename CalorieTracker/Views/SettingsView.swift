import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var diary: DiaryStore
    @EnvironmentObject private var healthKit: HealthKitStore
    let catalog: CatalogStore

    @State private var importing = false
    @State private var importMessage: String?
    @State private var importError: String?
    @State private var syncingNutrition = false
    @AppStorage("defaultWeightUnit") private var defaultWeightUnit = LogUnit.ounces.rawValue

    private let minimumSyncSpinnerDuration: TimeInterval = 0.35

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    TrendsView()
                } label: {
                    Label("Trends", systemImage: "chart.xyaxis.line")
                }
            }

            Section {
                HStack {
                    Label("Goal", systemImage: "target")
                    Spacer()
                    TextField("Not set", text: calorieGoalText)
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
                    Button("Remove goal", role: .destructive) {
                        diary.setDailyCalorieGoal(nil)
                    }
                }
            } header: {
                Text("Daily calorie goal")
            } footer: {
                Text("Optional. When set, the diary shows calories consumed against this daily goal.")
            }

            Section("Entry defaults") {
                Picker("Weight unit", selection: $defaultWeightUnit) {
                    Text("Ounces").tag(LogUnit.ounces.rawValue)
                    Text("Grams").tag(LogUnit.grams.rawValue)
                }
                .pickerStyle(.segmented)
                Text("Used for foods you have not logged before. Your last amount and unit are remembered per food.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apple Health") {
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
                            Label("Sync logged nutrition", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(syncingNutrition)
                case .notDetermined:
                    Button("Connect Apple Health", systemImage: "heart.fill") {
                        Task {
                            await healthKit.requestAuthorizationAndSync(entries: [])
                            diary.syncAllHealthData()
                        }
                    }
                    Text("Writes calories, carbohydrates, fat, and protein for your logged foods and meals.")
                        .font(.caption)
                case .denied:
                    Label("Access is turned off", systemImage: "exclamationmark.triangle")
                    Text("Allow nutrition data in the Health app's Apps settings to reconnect.")
                        .font(.caption)
                case .unavailable:
                    Label("Apple Health is unavailable", systemImage: "heart.slash")
                    Text("Health data can only be written on a device that supports Apple Health.")
                        .font(.caption)
                }
                if let error = healthKit.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Local catalogs") {
                sourceRow(.usda, count: catalog.count(source: .usda))
                sourceRow(.openFoodFacts, count: catalog.count(source: .openFoodFacts))
                sourceRow(.myFitnessPal, count: diary.document.importedFoods.count)
                NavigationLink {
                    PersonalCatalogView()
                } label: {
                    HStack {
                        SourceBadge(source: .custom)
                        Text("Custom")
                        Spacer()
                        Text("\(diary.document.customFoods.count) foods · \(diary.document.meals.count) meals")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Section("MyFitnessPal") {
                Button("Import CSV export", systemImage: "square.and.arrow.down") {
                    importing = true
                }
                if let importMessage {
                    Label(importMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.protein)
                }
                Text("The importer is ready for history data. Its header mapping may be adjusted once your actual export arrives.")
                    .font(.caption)
            }

            Section("Data & attribution") {
                Link("USDA FoodData Central", destination: URL(string: "https://fdc.nal.usda.gov/")!)
                Link("Open Food Facts", destination: URL(string: "https://world.openfoodfacts.org/")!)
                Text("USDA records are U.S. government public-domain data. Open Food Facts database records are reused under ODbL with source attribution and remain identifiable in this derived local database.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Settings")
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false,
            onCompletion: importFile
        )
        .alert("Import failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    private func syncLoggedNutrition() async {
        syncingNutrition = true
        let startedAt = Date()

        diary.syncAllHealthData()

        let remainingDuration = minimumSyncSpinnerDuration - Date().timeIntervalSince(startedAt)
        if remainingDuration > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remainingDuration * 1_000_000_000))
        }

        syncingNutrition = false
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

    private var calorieGoalText: Binding<String> {
        Binding(
            get: { diary.dailyCalorieGoal.map(String.init) ?? "" },
            set: { value in
                let digits = value.filter(\.isNumber)
                diary.setDailyCalorieGoal(Int(digits))
            }
        )
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let summary = try diary.importMyFitnessPal(data: Data(contentsOf: url))
            importMessage = "Imported \(summary.entries) entries and \(summary.foods) foods"
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct PersonalCatalogView: View {
    @EnvironmentObject private var diary: DiaryStore

    var body: some View {
        List {
            Section("Custom foods") {
                if diary.document.customFoods.isEmpty {
                    Label("No custom foods yet", systemImage: "fork.knife")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(diary.document.customFoods) { food in
                        FoodResultRow(food: food, preference: diary.preference(for: food))
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    diary.deleteCustomFood(food)
                                }
                            }
                    }
                }
            }

            Section("Saved meals") {
                if diary.document.meals.isEmpty {
                    Label("No saved meals yet", systemImage: "square.stack.3d.up")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(diary.document.meals) { meal in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(meal.name)
                                .font(.body.weight(.semibold))
                            Text("\(meal.items.count) item\(meal.items.count == 1 ? "" : "s") · \(mealCalories(meal)) cal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                diary.deleteMeal(meal)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Custom")
    }

    private func mealCalories(_ meal: SavedMeal) -> Int {
        Int(meal.items.reduce(0) { total, item in
            total + item.food.nutrients(
                for: item.amount,
                unit: item.unit,
                portionID: item.portionID
            ).calories
        }.rounded())
    }
}
