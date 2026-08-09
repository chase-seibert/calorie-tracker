import SwiftUI
import UIKit

struct FoodPickerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case magic = "Magic"
        case recent = "Recent"
        case frequent = "Frequent"
        case favorites = "Favorites"
        case meals = "Meals"
        case scan = "Scan"

        var id: String { rawValue }
    }

    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let catalog: CatalogStore

    @State private var mode: Mode?
    @State private var recentItemsSnapshot: [FoodPickerItem] = []
    @State private var frequentItemsSnapshot: [FoodPickerItem] = []
    @State private var magicSuggestionsSnapshot: [MagicFoodSuggestion] = []
    @State private var magicHasExcludedMatchesSnapshot = false
    @State private var magicTimeRange = MagicFoodTimeRange(date: Date(), calendar: .current)
    @State private var didLoadInitialSnapshot = false
    @State private var selectedFood: Food?
    @State private var selectedMeal: SavedMeal?
    @State private var query = ProcessInfo.processInfo.arguments.contains("--show-food-search") ? "banana" : ""
    @State private var results: [Food] = []
    @State private var isSearching = false
    @FocusState private var searchIsFocused: Bool

    init(date: Date, catalog: CatalogStore, initialMode: Mode? = nil) {
        self.date = date
        self.catalog = catalog
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchControls
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    FoodPickerModeStrip(selection: $mode) { selectedMode in
                        searchIsFocused = false
                        refreshItems(for: selectedMode)
                    }
                }
                Divider()
                Group {
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SearchResultsList(
                            query: query,
                            results: results,
                            isSearching: isSearching,
                            onQuickLog: quickLog,
                            onEdit: { selectedFood = $0 }
                        )
                    } else {
                        if let mode {
                            switch mode {
                            case .magic:
                                magicSuggestionsContent
                            case .recent:
                                FoodPickerList(
                                    title: "Logged recently",
                                    emptyTitle: "No suggestions yet",
                                    emptyMessage: "Foods or meals you log will appear here.",
                                    items: recentItemsSnapshot,
                                    onQuickLogFood: quickLog,
                                    onEditFood: { selectedFood = $0 },
                                    onQuickLogMeal: logMeal,
                                    onEditMeal: { selectedMeal = $0 },
                                    onDeleteMeal: diary.deleteMeal
                                )
                            case .frequent:
                                FoodPickerList(
                                    title: "Most used · 30 days",
                                    emptyTitle: "No suggestions yet",
                                    emptyMessage: "Your most-used foods and meals will appear here.",
                                    items: frequentItemsSnapshot,
                                    onQuickLogFood: quickLog,
                                    onEditFood: { selectedFood = $0 },
                                    onQuickLogMeal: logMeal,
                                    onEditMeal: { selectedMeal = $0 },
                                    onDeleteMeal: diary.deleteMeal
                                )
                            case .favorites:
                                FoodPickerList(
                                    title: nil,
                                    emptyTitle: "No favorites",
                                    emptyMessage: "Star any food or meal to keep it here.",
                                    items: diary.favoriteItems,
                                    onQuickLogFood: quickLog,
                                    onEditFood: { selectedFood = $0 },
                                    onQuickLogMeal: logMeal,
                                    onEditMeal: { selectedMeal = $0 },
                                    onDeleteMeal: diary.deleteMeal
                                )
                            case .meals:
                                MealsList(
                                    onQuickLog: { meal in
                                        diary.logMeal(meal, on: date)
                                    },
                                    onEdit: { selectedMeal = $0 }
                                )
                            case .scan:
                                BarcodeLookup(catalog: catalog, onSelect: { selectedFood = diary.displayedFood($0) })
                            }
                        } else {
                            magicSuggestionsContent
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    FoodPickerCalorieSummary(date: date)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedFood) { food in
                QuantityEditor(food: food, date: date)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedMeal) { meal in
                QuantityEditor(meal: meal, date: date)
                    .presentationDetents([.medium, .large])
            }
            .task {
                guard mode == nil else { return }
                try? await Task.sleep(for: .milliseconds(180))
                searchIsFocused = true
            }
            .onAppear {
                guard !didLoadInitialSnapshot else { return }
                didLoadInitialSnapshot = true
                refreshItems(for: mode ?? .magic)
            }
            .task(id: query) {
                let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedQuery.isEmpty else {
                    results = []
                    isSearching = false
                    return
                }
                isSearching = true
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                let personalResults = diary.searchPersonalFoods(normalizedQuery)
                let bundledResults = catalog.searchAll(normalizedQuery)
                var seen = Set<String>()
                results = (Array(personalResults.prefix(10)) + bundledResults + Array(personalResults.dropFirst(10)))
                    .filter { seen.insert($0.id).inserted }
                    .prefix(50)
                    .map(diary.displayedFood)
                isSearching = false
            }
        }
    }

    private var searchControls: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search foods", text: $query)
                .focused($searchIsFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var magicSuggestionsContent: some View {
        MagicFoodSuggestionsList(
            timeRange: magicTimeRange,
            suggestions: magicSuggestionsSnapshot,
            hasExcludedMatches: magicHasExcludedMatchesSnapshot,
            onQuickLog: { diary.logMagicSuggestion($0, on: date) }
        )
    }

    private func quickLog(_ food: Food) {
        diary.quickLog(food, on: date)
    }

    private func logMeal(_ meal: SavedMeal) {
        diary.logMeal(meal, on: date)
    }

    private func refreshItems(for mode: Mode) {
        switch mode {
        case .magic:
            let now = Date()
            magicTimeRange = MagicFoodTimeRange(date: now, calendar: .current)
            let result = diary.magicSuggestionResult(at: now)
            magicSuggestionsSnapshot = result.suggestions
            magicHasExcludedMatchesSnapshot = result.hasExcludedMatches
        case .recent:
            recentItemsSnapshot = diary.recentItems
        case .frequent:
            frequentItemsSnapshot = diary.frequentItems
        default:
            break
        }
    }
}

private struct FoodPickerCalorieSummary: View {
    @EnvironmentObject private var diary: DiaryStore
    let date: Date

    var body: some View {
        let calorieProgress = DailyCalorieProgress(
            calories: diary.totals(on: date).calories,
            goal: diary.dailyCalorieGoal
        )

        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .foregroundStyle(AppTheme.coral)
            Text(calorieProgress.consumed.formatted())
                .font(.headline.monospacedDigit())
            if let goal = calorieProgress.goal {
                Text("/ \(goal.formatted())")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.muted)
            }
            Text("cal")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(calorieProgress.accessibilityLabel)
    }
}

struct FoodPickerModeStrip: View {
    @Binding var selection: FoodPickerView.Mode?
    var isEnabled = true
    var showsScan = true
    var onDisabledTap: (() -> Void)? = nil
    let onSelect: (FoodPickerView.Mode) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(FoodPickerView.Mode.allCases.filter { showsScan || $0 != .scan }) { item in
                Button {
                    guard isEnabled else {
                        onDisabledTap?()
                        return
                    }
                    withAnimation(.snappy) {
                        selection = item
                        onSelect(item)
                    }
                } label: {
                    Group {
                        if item == .magic {
                            Image(systemName: "wand.and.sparkles")
                        } else if item == .scan {
                            Image(systemName: "barcode.viewfinder")
                        } else {
                            Text(item.rawValue)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .frame(height: 16)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .foregroundStyle(selection == item ? AppTheme.selectedText : AppTheme.ink)
                    .background(selection == item ? AppTheme.ink : AppTheme.controlFill, in: Capsule())
                    .opacity(isEnabled ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.rawValue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct MagicFoodSuggestionsList: View {
    let timeRange: MagicFoodTimeRange
    let suggestions: [MagicFoodSuggestion]
    let hasExcludedMatches: Bool
    let onQuickLog: (MagicFoodSuggestion) -> Void

    var body: some View {
        List {
            if suggestions.isEmpty {
                Section {
                    ContentUnavailableView(
                        hasExcludedMatches
                            ? "You’ve already logged the matching foods"
                            : "No \(timeRange.title.lowercased()) pattern yet",
                        systemImage: "wand.and.sparkles",
                        description: Text(
                            hasExcludedMatches
                                ? "Magic found foods that match your usual \(timeRange.title.lowercased()), but they’re hidden because you’ve already logged them today."
                                : "Keep logging and Magic will learn the foods you repeat during \(timeRange.hoursDescription)."
                        )
                    )
                }
            } else {
                Section("\(timeRange.title) · \(timeRange.hoursDescription)") {
                    ForEach(suggestions) { suggestion in
                        MagicFoodSuggestionRow(
                            suggestion: suggestion,
                            onQuickLog: { onQuickLog(suggestion) }
                        )
                    }
                }
            }

            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "wand.and.sparkles")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.coral)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your recent routine, ready in one tap")
                            .font(.subheadline.weight(.semibold))
                        Text("Magic looks at your last 10 days during breakfast (5–11 AM), lunch (11 AM–3 PM), or dinner (after 3 PM). A set adds each item separately to your log.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct MagicFoodSuggestionRow: View {
    @EnvironmentObject private var diary: DiaryStore
    let suggestion: MagicFoodSuggestion
    let onQuickLog: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(suggestion.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                    }
                    itemLabel(item)
                }
            }
            Spacer(minLength: 8)
            AddConfirmationButton(
                actionTitle: "Add",
                itemName: accessibilityName,
                action: onQuickLog
            )
        }
        .padding(.vertical, isSet ? 10 : 4)
        .overlay {
            if isSet {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.coral.opacity(0.55), lineWidth: 1)
                    .padding(.horizontal, -12)
            }
        }
        .padding(.bottom, isSet ? 10 : 0)
        .listRowSeparator(isSet ? .hidden : .visible)
        .accessibilityElement(children: .contain)
    }

    private var isSet: Bool {
        suggestion.items.count > 1
    }

    @ViewBuilder
    private func itemLabel(_ item: FoodPickerItem) -> some View {
        switch item {
        case let .food(food):
            HStack(spacing: 9) {
                SourceBadge(source: food.source)
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text(foodDescription(food))
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
            }
        case let .meal(meal):
            HStack(spacing: 9) {
                MealBadge()
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text("\(Int(meal.nutrients.calories.rounded())) cal · saved meal")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
    }

    private func foodDescription(_ food: Food) -> String {
        let preference = diary.preference(for: food)
        let nutrients = food.nutrients(
            for: preference.amount,
            unit: preference.unit,
            portionID: preference.portionID
        )
        let quantity: String
        switch preference.unit {
        case .grams, .ounces:
            quantity = "\(preference.amount.cleanAmount) \(preference.unit.rawValue)"
        case .serving:
            let label = food.portion(id: preference.portionID)?.label ?? "serving"
            quantity = "\(preference.amount.cleanAmount) \(label)"
        }
        return "\(Int(nutrients.calories.rounded())) cal · \(quantity)"
    }

    private var accessibilityName: String {
        suggestion.items.map {
            switch $0 {
            case let .food(food): food.name
            case let .meal(meal): meal.name
            }
        }.joined(separator: " and ")
    }
}

private struct FoodPickerList: View {
    @EnvironmentObject private var diary: DiaryStore
    let title: String?
    let emptyTitle: String
    let emptyMessage: String
    let items: [FoodPickerItem]
    let onQuickLogFood: (Food) -> Void
    let onEditFood: (Food) -> Void
    let onQuickLogMeal: (SavedMeal) -> Void
    let onEditMeal: (SavedMeal) -> Void
    let onDeleteMeal: (SavedMeal) -> Void

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: "fork.knife.circle", description: Text(emptyMessage))
        } else {
            List {
                Section {
                    ForEach(items) { item in
                        switch item {
                        case let .food(food):
                            FoodResultRow(
                                food: food,
                                preference: diary.preference(for: food),
                                actionTitle: "Add",
                                action: { onQuickLogFood(food) }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onEditFood(food) }
                        case let .meal(meal):
                            MealListActionRow(
                                meal: meal,
                                onQuickLog: { onQuickLogMeal(meal) },
                                onEdit: { onEditMeal(meal) }
                            )
                            .swipeActions {
                                Button("Delete", role: .destructive) { onDeleteMeal(meal) }
                            }
                        }
                    }
                } header: {
                    if let title { Text(title) }
                } footer: {
                    Text("Tap + to reuse your last quantity. Tap the row to change it.")
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

struct FoodResultRow: View {
    let food: Food
    var preference: QuantityPreference? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            SourceBadge(source: food.source)
            VStack(alignment: .leading, spacing: 3) {
                Text(food.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let brand = food.displayBrand { Text(brand + " ·") }
                    Text(nutritionDescription)
                }
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
            }
            Spacer()
            if let actionTitle, let action {
                AddConfirmationButton(
                    actionTitle: actionTitle,
                    itemName: food.name,
                    action: action
                )
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var nutritionDescription: String {
        guard let preference else {
            return "\(Int(food.nutrients.calories.rounded())) cal / \(food.baseAmountGrams.cleanAmount)g"
        }
        let nutrients = food.nutrients(
            for: preference.amount,
            unit: preference.unit,
            portionID: preference.portionID
        )
        return "\(Int(nutrients.calories.rounded())) cal / \(quantityDescription(preference))"
    }

    private func quantityDescription(_ preference: QuantityPreference) -> String {
        switch preference.unit {
        case .grams, .ounces:
            "\(preference.amount.cleanAmount) \(preference.unit.rawValue)"
        case .serving:
            "\(preference.amount.cleanAmount) \(food.portion(id: preference.portionID)?.label ?? "serving")"
        }
    }
}

private struct AddConfirmationButton: View {
    let actionTitle: String
    let itemName: String
    let action: () -> Void

    @State private var isAdded = false
    @State private var feedbackID = UUID()

    var body: some View {
        Button {
            action()
            let currentFeedbackID = UUID()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                feedbackID = currentFeedbackID
                isAdded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                guard feedbackID == currentFeedbackID else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    isAdded = false
                }
            }
        } label: {
            Image(systemName: isAdded ? "checkmark" : "plus")
                .font(.headline.weight(.bold))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: feedbackID)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(isAdded ? AppTheme.protein : AppTheme.coral)
        .accessibilityLabel(isAdded ? "Added \(itemName)" : "\(actionTitle) \(itemName)")
        .accessibilityHint(isAdded ? "Ready to add again" : "Adds the displayed quantity")
    }
}

private struct SearchResultsList: View {
    @EnvironmentObject private var diary: DiaryStore
    let query: String
    let results: [Food]
    let isSearching: Bool
    let onQuickLog: (Food) -> Void
    let onEdit: (Food) -> Void

    var body: some View {
        if isSearching {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                Section {
                    ForEach(results) { food in
                        FoodResultRow(
                            food: food,
                            preference: diary.preference(for: food),
                            actionTitle: "Quick add",
                            action: { onQuickLog(food) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onEdit(food) }
                    }
                } footer: {
                    Text("Tap + to log the displayed quantity. Tap the row to change it.")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private enum QuantityUnitChoice: Hashable {
    case ounces
    case grams
    case portion(String)
}

struct QuantityEditor: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var food: Food
    let date: Date
    private let entryID: UUID?
    private let mealID: UUID?
    private let savedMeal: SavedMeal?
    private let isMealEditor: Bool

    @State private var amount: Double
    @State private var unitChoice: QuantityUnitChoice
    @State private var mealItems: [MealItem]
    @State private var showingNameEditor = false
    @FocusState private var amountIsFocused: Bool

    init(food: Food, date: Date) {
        _food = State(initialValue: food)
        self.date = date
        entryID = nil
        mealID = nil
        savedMeal = nil
        isMealEditor = false
        _amount = State(initialValue: 1)
        _unitChoice = State(initialValue: .ounces)
        _mealItems = State(initialValue: [])
    }

    init(meal: SavedMeal, date: Date) {
        _food = State(initialValue: Self.mealFood(for: meal))
        self.date = date
        entryID = nil
        mealID = meal.id
        savedMeal = meal
        isMealEditor = true
        _amount = State(initialValue: 1)
        _unitChoice = State(initialValue: .portion("saved-meal"))
        _mealItems = State(initialValue: meal.items)
    }

    init(entry: DiaryEntry) {
        _food = State(initialValue: entry.food)
        date = entry.date
        entryID = entry.id
        mealID = entry.savedMealID
        savedMeal = nil
        isMealEditor = entry.isMeal
        _amount = State(initialValue: entry.amount)
        _mealItems = State(initialValue: entry.mealItems ?? [])
        if entry.isMeal {
            _unitChoice = State(initialValue: .portion(entry.portionID ?? "saved-meal"))
            return
        }
        switch entry.unit {
        case .ounces:
            _unitChoice = State(initialValue: .ounces)
        case .grams:
            _unitChoice = State(initialValue: .grams)
        case .serving:
            if let portion = entry.food.portion(id: entry.portionID) {
                _unitChoice = State(initialValue: .portion(portion.id))
            } else {
                _unitChoice = State(initialValue: .ounces)
            }
        }
    }

    private var availableChoices: [QuantityUnitChoice] {
        if isMealEditor { return [.portion(selectedPortionID ?? "saved-meal")] }
        return [.ounces, .grams] + food.availablePortions.map { .portion($0.id) }
    }

    private var selectedUnit: LogUnit {
        if isMealEditor { return .serving }
        return switch unitChoice {
        case .ounces: .ounces
        case .grams: .grams
        case .portion: .serving
        }
    }

    private var selectedPortionID: String? {
        guard case let .portion(id) = unitChoice else { return nil }
        return id
    }

    private var preview: MacroNutrients {
        food.nutrients(for: amount, unit: selectedUnit, portionID: selectedPortionID)
    }

    private var currentPreference: QuantityPreference {
        QuantityPreference(amount: amount, unit: selectedUnit, portionID: selectedPortionID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isMealEditor {
                        HStack(spacing: 8) {
                            MealEditorHeader(name: food.name, itemCount: mealItems.count)
                            if mealID != nil {
                                Button("Rename meal", systemImage: "pencil") {
                                    showingNameEditor = true
                                }
                                .labelStyle(.iconOnly)
                                .font(.headline)
                                .foregroundStyle(AppTheme.coral)
                                .frame(width: 44, height: 44)
                                .accessibilityHint("Choose the name used throughout the app")
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            FoodResultRow(food: food)
                            Button("Rename food", systemImage: "pencil") {
                                showingNameEditor = true
                            }
                            .labelStyle(.iconOnly)
                            .font(.headline)
                            .foregroundStyle(AppTheme.coral)
                            .frame(width: 44, height: 44)
                            .accessibilityHint("Choose the name used throughout the app")
                        }
                    }

                    HStack(spacing: 10) {
                        quantityAdjusterButton(
                            title: "−1",
                            accessibilityLabel: "Decrease quantity by one",
                            amountDelta: -1,
                            isDisabled: amount <= 1
                        )
                        amountField
                        quantityAdjusterButton(
                            title: "+1",
                            accessibilityLabel: "Increase quantity by one",
                            amountDelta: 1,
                            isDisabled: false
                        )
                        if isMealEditor {
                            Text("meal")
                                .font(.headline)
                                .foregroundStyle(AppTheme.muted)
                                .frame(minWidth: 52, alignment: .leading)
                        } else {
                            Picker("Unit", selection: $unitChoice) {
                                ForEach(availableChoices, id: \.self) { choice in
                                    Text(label(for: choice)).tag(choice)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    HStack {
                        nutrient("Calories", preview.calories, suffix: "")
                        nutrient("Carbs", preview.carbs, suffix: "g")
                        nutrient("Fat", preview.fat, suffix: "g")
                        nutrient("Protein", preview.protein, suffix: "g")
                    }

                    Button(action: save) {
                        Text(saveTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(amount <= 0)

                    if isMealEditor, !mealItems.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Contains")
                                .font(.headline)
                            ForEach(mealItems) { item in
                                MealItemRow(item: item)
                            }
                        }
                        .padding(14)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
                    }

                    if isMealEditor, entryID != nil {
                        Button("Break apart meal", systemImage: "rectangle.split.3x1", action: breakApartMeal)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .buttonStyle(.bordered)
                    }
                }
                .padding(18)
            }
            .background(AppTheme.background)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isMealEditor,
                   let mealID,
                   let meal = diary.document.meals.first(where: { $0.id == mealID }) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(
                            diary.isFavorite(meal) ? "Unfavorite" : "Favorite",
                            systemImage: diary.isFavorite(meal) ? "star.fill" : "star"
                        ) {
                            diary.toggleFavorite(meal)
                        }
                        .labelStyle(.iconOnly)
                    }
                } else if !isMealEditor {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(diary.isFavorite(food) ? "Unfavorite" : "Favorite", systemImage: diary.isFavorite(food) ? "star.fill" : "star") {
                            diary.toggleFavorite(food, preference: currentPreference)
                        }
                        .labelStyle(.iconOnly)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Save", action: save)
                        .disabled(amount <= 0)
                }
            }
            .sheet(isPresented: $showingNameEditor) {
                Group {
                    if isMealEditor {
                        NameEditor(
                            title: "Rename meal",
                            fieldTitle: "Meal name",
                            footer: "This name is saved with the meal and used by logged meal entries.",
                            name: food.name
                        ) { name in
                            guard let mealID, diary.renameMeal(mealID: mealID, name: name) else { return }
                            food.name = diary.document.meals.first { $0.id == mealID }?.name ?? name
                        }
                    } else {
                        NameEditor(
                            title: "Rename food",
                            fieldTitle: "Food name",
                            footer: "This name is saved when you leave this editor and will be used in the diary, favorites, and future searches.",
                            name: food.name
                        ) { name in
                            guard diary.renameFood(foodID: food.id, name: name) else { return }
                            food = diary.displayedFood(food)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .onAppear {
                guard entryID == nil, !isMealEditor else { return }
                let preference = diary.preference(for: food)
                amount = preference.amount
                switch preference.unit {
                case .ounces:
                    unitChoice = .ounces
                case .grams:
                    unitChoice = .grams
                case .serving:
                    if let portion = food.portion(id: preference.portionID) {
                        unitChoice = .portion(portion.id)
                    } else {
                        unitChoice = .ounces
                    }
                }
            }
            .onDisappear {
                if entryID == nil, !isMealEditor, diary.isFavorite(food) {
                    diary.rememberPreference(currentPreference, for: food)
                }
            }
        }
    }

    private func label(for choice: QuantityUnitChoice) -> String {
        switch choice {
        case .ounces: "ounces"
        case .grams: "grams"
        case let .portion(id):
            food.portion(id: id)?.label ?? "serving"
        }
    }

    private var amountField: some View {
        TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...2)))
            .keyboardType(.decimalPad)
            .submitLabel(.done)
            .focused($amountIsFocused)
            .font(.title2.weight(.bold).monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: 78)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))
            .onSubmit(save)
            .onChange(of: amountIsFocused) { _, isFocused in
                if isFocused { selectAllAmount() }
            }
    }

    private func quantityAdjusterButton(
        title: String,
        accessibilityLabel: String,
        amountDelta: Double,
        isDisabled: Bool
    ) -> some View {
        Button {
            adjustAmount(by: amountDelta)
        } label: {
            Text(title)
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(width: 36, height: 36)
                .background(AppTheme.controlFill, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.orange, lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.orange)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(amountDelta < 0 ? "quantity-minus-one" : "quantity-plus-one")
    }

    private func adjustAmount(by delta: Double) {
        let adjustedAmount = amount + delta
        guard adjustedAmount > 0 else { return }
        let roundingRule: FloatingPointRoundingRule = delta > 0 ? .up : .down
        amount = max(1, adjustedAmount.rounded(roundingRule))
        amountIsFocused = false
    }

    private var navigationTitle: String {
        if isMealEditor { return entryID == nil ? "Meal quantity" : "Edit meal" }
        return entryID == nil ? "Quantity" : "Edit food"
    }

    private var saveTitle: String {
        if entryID == nil {
            return "Add \(Int(preview.calories.rounded())) calories"
        }
        return "Save quantity"
    }

    private func save() {
        guard amount > 0 else { return }
        if let entryID {
            if isMealEditor {
                diary.updateMealEntry(entryID: entryID, amount: amount)
            } else {
                diary.updateEntry(
                    entryID: entryID,
                    amount: amount,
                    unit: selectedUnit,
                    portionID: selectedPortionID
                )
            }
        } else if let savedMeal {
            let currentMeal = diary.document.meals.first { $0.id == savedMeal.id } ?? savedMeal
            diary.logMeal(currentMeal, amount: amount, on: date)
        } else {
            diary.log(
                food,
                amount: amount,
                unit: selectedUnit,
                portionID: selectedPortionID,
                on: date
            )
        }
        dismiss()
    }

    private func breakApartMeal() {
        guard let entryID else { return }
        diary.breakApartMeal(entryID: entryID)
        dismiss()
    }

    private static func mealFood(for meal: SavedMeal) -> Food {
        Food(
            sourceID: "saved-meal-\(meal.id.uuidString)",
            source: .custom,
            name: meal.name,
            brand: nil,
            barcode: nil,
            nutrients: meal.nutrients,
            baseAmountGrams: 1,
            servingGrams: 1,
            servingDescription: "1 meal",
            portions: [FoodPortion(id: "saved-meal", label: "meal", grams: 1)]
        )
    }

    @MainActor
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

    private func nutrient(_ title: String, _ value: Double, suffix: String) -> some View {
        VStack(spacing: 3) {
            Text(value.cleanAmount + suffix).font(.subheadline.weight(.bold).monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MealEditorHeader: View {
    let name: String
    let itemCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("Meal")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.coral)
                .frame(width: 44, height: 44)
                .background(AppTheme.coral.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text("Saved meal · \(itemCount) item\(itemCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct MealItemRow: View {
    let item: MealItem

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.food.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(quantityDescription)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer(minLength: 8)
            Text("\(Int(nutrients.calories.rounded())) cal")
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.muted)
        }
    }

    private var nutrients: MacroNutrients {
        item.food.nutrients(for: item.amount, unit: item.unit, portionID: item.portionID)
    }

    private var quantityDescription: String {
        switch item.unit {
        case .grams, .ounces:
            "\(item.amount.cleanAmount) \(item.unit.rawValue)"
        case .serving:
            "\(item.amount.cleanAmount) \(item.food.portion(id: item.portionID)?.label ?? "serving")"
        }
    }
}

private struct NameEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let fieldTitle: String
    let footer: String
    let onApply: (String) -> Void

    @State private var editedName: String
    @State private var hasFinished = false

    init(
        title: String,
        fieldTitle: String,
        footer: String,
        name: String,
        onApply: @escaping (String) -> Void
    ) {
        self.title = title
        self.fieldTitle = fieldTitle
        self.footer = footer
        self.onApply = onApply
        _editedName = State(initialValue: name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(fieldTitle, text: $editedName)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        hasFinished = true
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: applyAndDismiss)
                    .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onDisappear {
                guard !hasFinished else { return }
                hasFinished = true
                onApply(editedName)
            }
        }
    }

    private func applyAndDismiss() {
        guard !editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        hasFinished = true
        onApply(editedName)
        dismiss()
    }
}

private struct MealListActionRow: View {
    let meal: SavedMeal
    let onQuickLog: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MealListRow(meal: meal)
                .contentShape(Rectangle())
                .onTapGesture(perform: onEdit)
            AddConfirmationButton(
                actionTitle: "Add",
                itemName: meal.name,
                action: onQuickLog
            )
                .frame(width: 44, height: 44)
        }
    }
}

private struct MealsList: View {
    @EnvironmentObject private var diary: DiaryStore
    let onQuickLog: (SavedMeal) -> Void
    let onEdit: (SavedMeal) -> Void

    var body: some View {
        if diary.document.meals.isEmpty {
            ContentUnavailableView(
                "No saved meals",
                systemImage: "square.stack.3d.up",
                description: Text("From the diary, log a combination and choose Save meal.")
            )
        } else {
            List {
                ForEach(diary.alphabetizedMeals) { meal in
                    MealListActionRow(
                        meal: meal,
                        onQuickLog: { onQuickLog(meal) },
                        onEdit: { onEdit(meal) }
                    )
                    .swipeActions {
                        Button("Delete", role: .destructive) { diary.deleteMeal(meal) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct MealListRow: View {
    let meal: SavedMeal

    var body: some View {
        HStack(spacing: 12) {
            MealBadge()

            VStack(alignment: .leading, spacing: 3) {
                Text(meal.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text("\(meal.items.count) item\(meal.items.count == 1 ? "" : "s") · \(macroDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var macroDescription: String {
        "\(Int(meal.nutrients.calories.rounded())) cal · C \(meal.nutrients.carbs.cleanAmount)g · F \(meal.nutrients.fat.cleanAmount)g · P \(meal.nutrients.protein.cleanAmount)g"
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? .infinity
        let result = rows(for: subviews, width: width)
        return CGSize(width: width, height: result.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> (height: CGFloat, rows: Int) {
        var x: CGFloat = 0
        var height: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowCount = subviews.isEmpty ? 0 : 1

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
                rowCount += 1
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (height + rowHeight, rowCount)
    }
}

private struct BarcodeLookup: View {
    let catalog: CatalogStore
    let onSelect: (Food) -> Void

    @State private var barcode = ""
    @State private var notFound = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                BarcodeScanner { code in
                    barcode = code
                    lookup()
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 22))

                Text("Point the camera at a UPC or EAN barcode.")
                    .font(.subheadline).foregroundStyle(.secondary)

                HStack {
                    TextField("Enter barcode", text: $barcode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Look up") { lookup() }
                        .buttonStyle(.borderedProminent)
                }
                if notFound {
                    Label("No local match. Add it as a custom food.", systemImage: "exclamationmark.magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
    }

    private func lookup() {
        if let food = catalog.food(barcode: barcode) {
            notFound = false
            onSelect(food)
        } else {
            notFound = true
        }
    }
}
