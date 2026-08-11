import SwiftUI
import UniformTypeIdentifiers
import UIKit

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

    @State private var editingFood: Food?
    @State private var showingFoodEditor = false
    @State private var editingMeal: SavedMeal?
    @State private var showingMealEditor = false

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
                                }
                            }
                    }
                }
            }

            Section("Saved meals") {
                Button("Add", systemImage: "plus") {
                    editingMeal = nil
                    showingMealEditor = true
                }
                if diary.document.meals.isEmpty {
                    Label("No saved meals yet", systemImage: "square.stack.3d.up")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(diary.alphabetizedMeals) { meal in
                        PersonalMealRow(meal: meal)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingMeal = meal
                                showingMealEditor = true
                            }
                            .swipeActions {
                                Button("Edit", systemImage: "pencil") {
                                    editingMeal = meal
                                    showingMealEditor = true
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    diary.deleteMeal(meal)
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle("Custom")
        .sheet(isPresented: $showingFoodEditor) {
            CustomFoodEditorView(food: editingFood)
        }
        .sheet(isPresented: $showingMealEditor) {
            SavedMealEditorView(meal: editingMeal)
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
    @State private var name: String
    @State private var brand: String
    @State private var calories: Double
    @State private var carbs: Double
    @State private var fat: Double
    @State private var protein: Double
    @State private var servingGrams: Double
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case brand
        case calories
        case carbs
        case fat
        case protein
        case servingGrams

        var selectsAllOnFocus: Bool {
            switch self {
            case .calories, .carbs, .fat, .protein, .servingGrams:
                return true
            case .name, .brand:
                return false
            }
        }
    }

    init(
        food: Food?,
        initialName: String? = nil,
        onSaved: ((Food) -> Void)? = nil
    ) {
        self.food = food
        self.onSaved = onSaved
        _name = State(initialValue: food?.name ?? initialName ?? "")
        _brand = State(initialValue: food?.brand ?? "")
        _calories = State(initialValue: food?.nutrients.calories ?? 0)
        _carbs = State(initialValue: food?.nutrients.carbs ?? 0)
        _fat = State(initialValue: food?.nutrients.fat ?? 0)
        _protein = State(initialValue: food?.nutrients.protein ?? 0)
        _servingGrams = State(initialValue: food?.servingGrams ?? food?.baseAmountGrams ?? 100)
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
                    decimalFieldRow("Serving size (g)", value: $servingGrams, field: .servingGrams)
                }
            }
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
                servingGrams: servingGrams
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
                servingGrams: servingGrams
            )
        }
        if let savedFood {
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
    @State private var showingFoodPicker = false

    init(meal: SavedMeal?) {
        self.meal = meal
        _name = State(initialValue: meal?.name ?? "")
        _items = State(initialValue: meal?.items ?? [])
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
            }
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
                }
            }
        }
    }

    private var availableFoods: [Food] {
        var seen = Set<String>()
        let candidates = diary.document.customFoods
            + diary.document.favorites
            + diary.document.importedFoods
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
            _ = diary.updateSavedMeal(mealID: meal.id, name: name, items: items)
        } else {
            _ = diary.saveMeal(name: name, items: items)
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
