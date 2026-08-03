import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var diary: DiaryStore
    let catalog: CatalogStore

    @State private var importing = false
    @State private var importMessage: String?
    @State private var importError: String?
    @State private var confirmingClear = false
    @AppStorage("defaultWeightUnit") private var defaultWeightUnit = LogUnit.ounces.rawValue

    var body: some View {
        NavigationStack {
            Form {
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

                Section {
                    Button("Clear diary and personal data", systemImage: "trash", role: .destructive) {
                        confirmingClear = true
                    }
                } footer: {
                    Text("Removes entries, favorites, saved meals, custom foods, remembered quantities, and imported history. Bundled catalogs are unchanged.")
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
            .confirmationDialog(
                "Clear all personal data?",
                isPresented: $confirmingClear,
                titleVisibility: .visible
            ) {
                Button("Clear personal data", role: .destructive) { diary.clearPersonalData() }
                Button("Cancel", role: .cancel) {}
            }
        }
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
