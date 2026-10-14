import SwiftUI
import UIKit

struct FoodPickerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case magic = "Magic"
        case recent = "Recent"
        case frequent = "Frequent"
        case favorites = "Favorites"
        case meals = "Meals"

        var id: String { rawValue }

        var analyticsValue: String { rawValue.lowercased() }
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
    @State private var customizingFood: Food?
    @State private var customizingConfiguration: SavedFoodConfiguration?
    @State private var selectedMeal: SavedMeal?
    @State private var query = ProcessInfo.processInfo.arguments.contains("--show-food-search") ? "banana" : ""
    @State private var results: [FoodPickerItem] = []
    @State private var isSearching = false
    @State private var showingCustomFoodEditor = false
    @State private var showingFoodSuggestionEditor = false
    @State private var showingMealAnalysis = false
    @State private var searchAttempt = FoodSearchAttemptTracker()
    @FocusState private var searchIsFocused: Bool
    @AppStorage("foodSource.enabled.usda") private var usdaEnabled = true
    @AppStorage("foodSource.enabled.off") private var offEnabled = true
    @AppStorage("foodSource.enabled.chaseFood") private var chaseFoodEnabled = false

    private let analytics = AnalyticsService.shared

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
                    FoodPickerModeStrip(
                        selection: $mode,
                        onAnalyzeMeal: {
                            searchIsFocused = false
                            showingMealAnalysis = true
                            AppAnalytics.capture("food_picker.analyze_meal_selected")
                        }
                    ) { selectedMode in
                            searchIsFocused = false
                            refreshItems(for: selectedMode)
                            AppAnalytics.capture(
                                "food_picker.mode_selected",
                                properties: ["mode": selectedMode.analyticsValue]
                            )
                        }
                }
                Divider()
                Group {
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SearchResultsList(
                            query: query,
                            results: results,
                            isSearching: isSearching,
                            onQuickLogFood: quickLog,
                            onEditFood: { editFood($0) },
                            onQuickLogConfiguration: quickLogConfiguration,
                            onQuickLogMeal: logMeal,
                            onEditMeal: { selectedMeal = $0 },
                            onSearchResultSelected: captureSearchResultSelection,
                            onAddCustomFood: {
                                finishSearchAttempt(recordNothingSelected: false)
                                showingCustomFoodEditor = true
                            },
                            onSuggestCanonical: { showingFoodSuggestionEditor = true }
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
                                    onDeleteMeal: deleteMeal
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
                                    onDeleteMeal: deleteMeal
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
                                    onDeleteMeal: deleteMeal
                                )
                            case .meals:
                                MealsList(
                                    onQuickLog: logMeal,
                                    onEdit: { selectedMeal = $0 }
                                )
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
                    Button("Done") {
                        finishSearchAttempt()
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedFood) { food in
                QuantityEditor(food: food, date: date) { preference, defaultPreference in
                    markCurrentSearchLogged()
                    captureFoodLog(
                        food: food,
                        method: "quantity_editor",
                        unit: preference.unit,
                        portionID: preference.portionID,
                        defaultUnit: defaultPreference?.unit,
                        defaultPortionID: defaultPreference?.portionID
                    )
                }
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedMeal) { meal in
                QuantityEditor(meal: meal, date: date) { preference, _ in
                    markCurrentSearchLogged()
                    captureMealLog(meal: meal, method: "quantity_editor", unit: preference.unit)
                }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingFoodSuggestionEditor) {
                FoodSuggestionEditor(query: query)
                    .environmentObject(diary)
            }
            .sheet(isPresented: $showingCustomFoodEditor, onDismiss: refreshSearchResults) {
                CustomFoodEditorView(
                    food: nil,
                    initialName: query.trimmingCharacters(in: .whitespacesAndNewlines),
                    analyticsOrigin: "search_miss",
                    onSaved: { food in
                        diary.run {
                            markCurrentSearchLogged()
                            let previousEntryCount = diary.entries(on: date).count
                            try await diary.log(
                                food,
                                amount: 1,
                                unit: .serving,
                                portionID: "custom-serving",
                                on: date,
                                allowCheatDay: true
                            )
                            if diary.entries(on: date).count > previousEntryCount {
                                captureFoodLog(
                                    food: food,
                                    method: "custom_food_creation",
                                    unit: .serving,
                                    portionID: "custom-serving",
                                    foodKind: "custom"
                                )
                            }
                            dismiss()

                        }
                    }
                )
            }
            .fullScreenCover(item: $customizingFood, onDismiss: { customizingConfiguration = nil }) { food in
                ChaseFoodCustomizeView(food: food, catalog: catalog, date: date, initialConfiguration: customizingConfiguration)
                    .environmentObject(diary)
            }
            .sheet(isPresented: $showingMealAnalysis) {
                MealAnalysisView(targetDate: date) {
                    finishSearchAttempt()
                    dismiss()
                }
                .environmentObject(diary)
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
                AppAnalytics.capture("food_picker.opened", properties: [
                    "initial_mode": mode?.analyticsValue ?? "search"
                ])
            }
            .task(id: "\(query)|\(usdaEnabled)|\(offEnabled)|\(chaseFoodEnabled)") {
                let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedQuery.isEmpty else {
                    results = []
                    isSearching = false
                    return
                }
                isSearching = true
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                var enabledSources = Set<FoodSource>()
                if usdaEnabled { enabledSources.insert(.usda) }
                if offEnabled { enabledSources.insert(.openFoodFacts) }
                if chaseFoodEnabled { enabledSources.insert(.chaseFood) }
                let bundledResults = catalog.searchAll(normalizedQuery, enabledSources: enabledSources)
                let matches = await diary.searchItemsIncludingHistory(normalizedQuery, catalogFoods: bundledResults)
                guard !Task.isCancelled else { return }
                results = matches
                isSearching = false
                searchAttempt.completed(query: normalizedQuery, resultCount: results.count)
            }
            .onDisappear { finishSearchAttempt() }
        }
        .analyticsScreen(
            "food_picker",
            properties: [
                "initial_mode": mode?.analyticsValue ?? "search"
            ])
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
                Button("Clear", systemImage: "xmark.circle.fill") {
                    finishSearchAttempt()
                    query = ""
                }
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
            onQuickLog: logMagicSuggestion
        )
    }

    private func quickLog(_ food: Food) {
        diary.run {
            markCurrentSearchLogged()
            let preference = diary.preference(for: food)
            let previousEntryCount = diary.entries(on: date).count
            try await diary.quickLog(food, on: date, allowCheatDay: true)
            guard diary.entries(on: date).count > previousEntryCount else { return }
            captureFoodLog(
                food: food,
                method: "quick_add",
                unit: preference.unit,
                portionID: preference.portionID
            )

        }
    }

    private func editFood(_ food: Food) {
        if food.source == .chaseFood {
            customizingConfiguration = nil
            customizingFood = food
        } else {
            selectedFood = food
        }
    }

    private func quickLogConfiguration(_ food: Food, _ configuration: SavedFoodConfiguration) {
        markCurrentSearchLogged()
        let options = catalog.chaseFoodOptions(for: food.sourceID)
        let selected = Set(configuration.selectedOptionIDs)
        var nutrients = food.nutrients(for: 1, unit: .serving, portionID: configuration.portionID)
        let variant = options.first {
            $0.relationship.caseInsensitiveCompare("variant") == .orderedSame && selected.contains($0.id)
        }
        if let variant {
            let grams = food.portion(id: configuration.portionID)?.grams ?? food.baseAmountGrams
            nutrients = variant.food.nutrients(for: grams, unit: .grams)
        }
        for option in options {
            guard option.relationship.caseInsensitiveCompare("style") != .orderedSame,
                  option.relationship.caseInsensitiveCompare("variant") != .orderedSame else { continue }
            if variant != nil && option.includedByDefault { continue }
            let included = selected.contains(option.id)
            guard (option.includedByDefault && !included) || (!option.includedByDefault && included) else { continue }
            let value = option.food.nutrients(for: option.amountGrams, unit: .grams)
            if included { nutrients = nutrients + value }
            else {
                nutrients = MacroNutrients(calories: max(0, nutrients.calories - value.calories),
                                           carbs: max(0, nutrients.carbs - value.carbs),
                                           fat: max(0, nutrients.fat - value.fat),
                                           protein: max(0, nutrients.protein - value.protein),
                                           fiber: nutrients.fiber.map { max(0, $0 - (value.fiber ?? 0)) })
            }
        }
        for component in configuration.components {
            nutrients = nutrients + component.food.nutrients(for: component.amount, unit: component.unit, portionID: component.portionID)
        }
        let additions = options.filter {
            selected.contains($0.id) && $0.relationship.caseInsensitiveCompare("style") != .orderedSame
        }.map {
            MealItem(id: UUID(), food: $0.food, amount: $0.amountGrams, unit: .grams)
        } + configuration.components
        let refreshedConfiguration = SavedFoodConfiguration(baseFoodID: food.id, label: configuration.label,
                                                            selectedOptionIDs: configuration.selectedOptionIDs,
                                                            components: configuration.components, portionID: configuration.portionID)
        diary.run(operation: "chase_food_saved_variation_log") {
            let previousCount = diary.entries(on: date).count
            try await diary.logConfiguredFood(food, nutrients: nutrients, selectedOptionIDs: configuration.selectedOptionIDs,
                                              components: additions, suggestedChanges: nil, portionID: configuration.portionID,
                                              configuration: refreshedConfiguration, suggestion: nil, on: date, allowCheatDay: true)
            guard diary.entries(on: date).count > previousCount else { return }
            captureFoodLog(food: food, method: "saved_configuration", unit: .serving, portionID: configuration.portionID)
        }
    }

    private func logMeal(_ meal: SavedMeal) {
        diary.run {
            markCurrentSearchLogged()
            let previousEntryCount = diary.entries(on: date).count
            try await diary.logMeal(meal, on: date, allowCheatDay: true)
            guard diary.entries(on: date).count > previousEntryCount else { return }
            captureMealLog(meal: meal, method: "quick_add", unit: .serving)

        }
    }

    private func deleteMeal(_ meal: SavedMeal) {
        diary.run {
            try await diary.deleteMeal(meal)
            AppAnalytics.capture("meal.deleted", properties: ["origin": "food_picker"])

        }
    }

    private func logMagicSuggestion(_ suggestion: MagicFoodSuggestion) {
        diary.run {
            let loggedItems = try await diary.logMagicSuggestion(suggestion, on: date)
            guard !loggedItems.isEmpty else { return }
            let groupID = UUID().uuidString
            for item in loggedItems {
                switch item {
                case .food(let food):
                    captureFoodLog(
                        food: food,
                        method: "magic_suggestion",
                        unit: diary.preference(for: food).unit,
                        portionID: diary.preference(for: food).portionID,
                        mode: "magic",
                        groupID: groupID
                    )
                case .meal(let meal):
                    captureMealLog(
                        meal: meal,
                        method: "magic_suggestion",
                        unit: .serving,
                        mode: "magic",
                        groupID: groupID
                    )
                }
            }

        }
    }

    private func captureFoodLog(
        food: Food,
        method: String,
        unit: LogUnit,
        portionID: String? = nil,
        defaultUnit: LogUnit? = nil,
        defaultPortionID: String? = nil,
        foodKind: String? = nil,
        mode: String? = nil,
        groupID: String? = nil
    ) {
        let resolvedMode = mode ?? activeAnalyticsMode
        AppAnalytics.capture(
            "food_log.completed",
            properties: FoodLogAnalytics.foodProperties(
                food: food,
                method: method,
                mode: resolvedMode,
                unit: unit,
                isFavorite: diary.isFavorite(food),
                catalogVersion: catalog.catalogVersion,
                foodKind: foodKind,
                portionID: portionID,
                defaultUnit: defaultUnit,
                defaultPortionID: defaultPortionID,
                selectionRank: resolvedMode == "search" ? selectionRank(for: .food(food)) : nil,
                query: resolvedMode == "search" ? successfulSearchQuery : nil,
                groupID: groupID
            )
        )
    }

    private func captureMealLog(
        meal: SavedMeal,
        method: String,
        unit: LogUnit,
        mode: String? = nil,
        groupID: String? = nil
    ) {
        let resolvedMode = mode ?? activeAnalyticsMode
        AppAnalytics.capture(
            "food_log.completed",
            properties: FoodLogAnalytics.mealProperties(
                meal: meal,
                method: method,
                mode: resolvedMode,
                unit: unit,
                isFavorite: diary.isFavorite(meal),
                selectionRank: resolvedMode == "search" ? selectionRank(for: .meal(meal)) : nil,
                query: resolvedMode == "search" ? successfulSearchQuery : nil,
                groupID: groupID
            )
        )
    }

    private var activeAnalyticsMode: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (mode?.analyticsValue ?? "magic")
            : "search"
    }

    private var successfulSearchQuery: String? {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : String(normalized.prefix(200))
    }

    private func selectionRank(for item: FoodPickerItem) -> Int? {
        results.firstIndex(where: { $0.id == item.id }).map { $0 + 1 }
    }

    private func captureSearchResultSelection(_ item: FoodPickerItem) {
        guard let properties = FoodSearchSelectionAnalytics.properties(
            query: query,
            selectedItemID: analyticsSearchItemID(item),
            rankedItemIDs: results.map(analyticsSearchItemID)
        ) else { return }
        AppAnalytics.capture(
            "food_search.result_selected",
            properties: properties
        )
    }

    private func analyticsSearchItemID(_ item: FoodPickerItem) -> String {
        switch item {
        case let .food(food):
            let namespace = food.source == .custom ? "local" : food.source.rawValue
            return "food:\(namespace):\(food.sourceID)"
        case let .meal(meal):
            return "meal:local:\(meal.id.uuidString)"
        }
    }

    private func markCurrentSearchLogged() {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return }
        searchAttempt.logged(query: normalizedQuery)
    }

    private func finishSearchAttempt(recordNothingSelected: Bool = true) {
        guard let outcome = searchAttempt.finish(
            query: query,
            isSearching: isSearching,
            recordNothingSelected: recordNothingSelected
        ) else { return }
        Task {
            await analytics.capture(type: outcome.eventType, properties: [
                "query": String(outcome.query.prefix(200)),
                "result_count": String(outcome.resultCount)
            ])
        }
    }

    private func refreshSearchResults() {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            results = []
            isSearching = false
            return
        }
        Task {
            let matches = await diary.searchItemsIncludingHistory(
                normalizedQuery, catalogFoods: catalog.searchAll(normalizedQuery)
            )
            guard normalizedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            results = matches
            isSearching = false
        }
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

struct FoodSearchAttemptTracker {
    private(set) var completedQuery = ""
    private(set) var completedResultCount = 0
    private var loggedQueries: Set<String> = []
    private var finishedQueries: Set<String> = []

    mutating func completed(query: String, resultCount: Int) {
        completedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        completedResultCount = max(0, resultCount)
    }

    mutating func logged(query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return }
        loggedQueries.insert(normalizedQuery)
    }

    mutating func finish(
        query: String,
        isSearching: Bool,
        recordNothingSelected: Bool = true
    ) -> FoodSearchOutcome? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty,
              normalizedQuery == completedQuery,
              !isSearching,
              !finishedQueries.contains(normalizedQuery) else { return nil }

        let eventType: String
        if completedResultCount == 0 {
            eventType = "food_search.no_match"
        } else {
            guard recordNothingSelected, !loggedQueries.contains(normalizedQuery) else { return nil }
            eventType = "food_search.nothing_selected"
        }
        finishedQueries.insert(normalizedQuery)
        return FoodSearchOutcome(
            eventType: eventType,
            query: normalizedQuery,
            resultCount: completedResultCount
        )
    }
}

struct FoodSearchOutcome: Equatable {
    let eventType: String
    let query: String
    let resultCount: Int
}

struct FoodSearchSelectionAnalytics {
    static func properties(
        query: String,
        selectedItemID: String,
        rankedItemIDs: [String]
    ) -> [String: String]? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty,
              let index = rankedItemIDs.firstIndex(of: selectedItemID)
        else { return nil }

        return [
            "query": String(normalizedQuery.prefix(200)),
            "selected_item_id": selectedItemID,
            "selected_rank": String(index + 1),
            "result_ids_above": String(rankedItemIDs.prefix(index).joined(separator: ",").prefix(240))
        ]
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
    let onAnalyzeMeal: () -> Void
    var isEnabled = true
    var onDisabledTap: (() -> Void)? = nil
    let onSelect: (FoodPickerView.Mode) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(FoodPickerView.Mode.allCases) { item in
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

            Button(action: onAnalyzeMeal) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(AppTheme.ink)
                    .background(AppTheme.controlFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Analyze a meal with AI")
            .accessibilityHint("Describe your meal and optionally add a photo")
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
        case .food(let food):
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
        case .meal(let meal):
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
            case .food(let food): food.name
            case .meal(let meal): meal.name
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
                        case .food(let food):
                            FoodResultRow(
                                food: food,
                                preference: diary.preference(for: food),
                                actionTitle: "Add",
                                action: { onQuickLogFood(food) }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onEditFood(food) }
                        case .meal(let meal):
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
    var openAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            SourceBadge(source: food.source)
            Group {
                if let openAction {
                    Button(action: openAction) {
                        foodDescription
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Customize \(food.name)")
                } else {
                    foodDescription
                }
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

    private var foodDescription: some View {
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
        .contentShape(Rectangle())
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
    let results: [FoodPickerItem]
    let isSearching: Bool
    let onQuickLogFood: (Food) -> Void
    let onEditFood: (Food) -> Void
    let onQuickLogConfiguration: (Food, SavedFoodConfiguration) -> Void
    let onQuickLogMeal: (SavedMeal) -> Void
    let onEditMeal: (SavedMeal) -> Void
    let onSearchResultSelected: (FoodPickerItem) -> Void
    let onAddCustomFood: () -> Void
    let onSuggestCanonical: () -> Void

    var body: some View {
        if isSearching {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            VStack(spacing: 0) {
                ContentUnavailableView.search(text: query)
                Button("Add custom food", systemImage: "plus", action: onAddCustomFood)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                Button("Suggest a canonical food", systemImage: "lightbulb", action: onSuggestCanonical)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(results) { item in
                        switch item {
                        case .food(let food):
                            VStack(alignment: .leading, spacing: 3) {
                                FoodResultRow(
                                    food: food,
                                    preference: diary.preference(for: food),
                                    actionTitle: "Quick add",
                                    action: {
                                        onSearchResultSelected(.food(food))
                                        onQuickLogFood(food)
                                    },
                                    openAction: food.source == .chaseFood ? {
                                        onSearchResultSelected(.food(food))
                                        onEditFood(food)
                                    } : nil
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard food.source != .chaseFood else { return }
                                    onSearchResultSelected(.food(food))
                                    onEditFood(food)
                                }
                                let variations = diary.document.savedFoodConfigurations
                                    .filter { $0.baseFoodID == food.id }
                                    .sorted { $0.lastUsedAt > $1.lastUsedAt }
                                    .prefix(2)
                                ForEach(Array(variations)) { configuration in
                                    HStack(spacing: 8) {
                                        Button {
                                            onSearchResultSelected(.food(food))
                                            onQuickLogConfiguration(food, configuration)
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: "arrow.turn.down.right")
                                                    .foregroundStyle(AppTheme.muted)
                                                Text(displayLabel(configuration, for: food))
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                                Spacer(minLength: 0)
                                            }
                                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Select saved variation: \(displayLabel(configuration, for: food))")
                                        AddConfirmationButton(
                                            actionTitle: "Quick add",
                                            itemName: displayLabel(configuration, for: food),
                                            action: {
                                                onSearchResultSelected(.food(food))
                                                onQuickLogConfiguration(food, configuration)
                                            }
                                        )
                                        .frame(minWidth: 44, minHeight: 44)
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .padding(.leading, 60)
                                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                }
                            }
                        case .meal(let meal):
                            MealListActionRow(
                                meal: meal,
                                onQuickLog: {
                                    onSearchResultSelected(.meal(meal))
                                    onQuickLogMeal(meal)
                                },
                                onEdit: {
                                    onSearchResultSelected(.meal(meal))
                                    onEditMeal(meal)
                                }
                            )
                        }
                    }
                } footer: {
                    Text("Tap + to log the displayed quantity. Tap the row to change it.")
                }
                Section {
                    Button("Suggest a canonical food or search change", systemImage: "lightbulb", action: onSuggestCanonical)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func displayLabel(_ configuration: SavedFoodConfiguration, for food: Food) -> String {
        var label = configuration.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let foodName = food.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let redundantPrefixes = [" · ", " • ", ", "]
            .map { foodName + $0 }
        if let prefix = redundantPrefixes.first(where: {
            label.range(of: $0, options: .caseInsensitive).map { $0.lowerBound == label.startIndex } ?? false
        }) {
            label = String(label.dropFirst(prefix.count))
        }
        return label
            .replacingOccurrences(of: " · ", with: ", ")
            .replacingOccurrences(of: " • ", with: ", ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ", "))
    }
}

private struct FoodSuggestionEditor: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let query: String
    @State private var suggestedName: String
    @State private var suggestedChanges = ""

    init(query: String) {
        self.query = query
        _suggestedName = State(initialValue: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New canonical food") {
                    TextField("Food name", text: $suggestedName)
                        .textInputAutocapitalization(.words)
                    Text("Search: \(query)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Suggested changes") {
                    TextEditor(text: $suggestedChanges)
                        .frame(minHeight: 150)
                    Text("Describe what food should be available or how the search result should change.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Suggest a food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { submit() }
                        .disabled(suggestedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || suggestedChanges.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func submit() {
        let suggestion = FoodSuggestion(
            kind: .newCanonicalFood,
            suggestedName: suggestedName,
            suggestedChanges: suggestedChanges,
            searchQuery: query
        )
        diary.run(operation: "food_suggestion_submit") {
            try await diary.saveFoodSuggestion(suggestion)
            AppAnalytics.capture("food.suggestion_submitted", properties: [
                "kind": suggestion.kind.rawValue,
                "suggested_name": suggestion.suggestedName,
                "suggested_changes": suggestion.suggestedChanges,
                "search_query": query
            ])
            dismiss()
        }
    }
}

private struct ChaseFoodOptionGroup: Identifiable {
    let name: String
    let selectionMode: String
    let options: [ChaseFoodOption]

    var id: String { name }
}

private struct ChaseFoodCustomizeView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let food: Food
    let catalog: CatalogStore
    let date: Date
    let initialConfiguration: SavedFoodConfiguration?
    @State private var selectedOptionIDs: Set<String>
    @State private var selectedExtraFoodIDs: Set<String>
    @State private var portionID: String
    @State private var amount = 1.0
    @State private var unitChoice: QuantityUnitChoice
    @State private var ingredientQuery = ""
    @State private var suggestedChanges = ""
    @State private var showingIngredientSearch = false
    @FocusState private var amountIsFocused: Bool

    init(food: Food, catalog: CatalogStore, date: Date, initialConfiguration: SavedFoodConfiguration?) {
        self.food = food
        self.catalog = catalog
        self.date = date
        self.initialConfiguration = initialConfiguration
        let options = catalog.chaseFoodOptions(for: food.sourceID)
        _selectedOptionIDs = State(initialValue: Set(initialConfiguration?.selectedOptionIDs
            ?? options.filter(\.includedByDefault).map(\.id)))
        _selectedExtraFoodIDs = State(initialValue: Set(initialConfiguration?.components.map(\.food.id) ?? []))
        let initialPortionID = initialConfiguration?.portionID ?? food.availablePortions.first?.id ?? ""
        _portionID = State(initialValue: initialPortionID)
        _unitChoice = State(initialValue: initialPortionID.isEmpty ? .ounces : .portion(initialPortionID))
    }

    private var options: [ChaseFoodOption] { catalog.chaseFoodOptions(for: food.sourceID) }
    private var recentConfigurations: [SavedFoodConfiguration] {
        diary.document.savedFoodConfigurations
            .filter { $0.baseFoodID == food.id }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
            .prefix(5)
            .map { $0 }
    }
    private var optionGroups: [ChaseFoodOptionGroup] {
        var grouped: [String: [ChaseFoodOption]] = [:]
        for option in options {
            if let name = option.optionGroup {
                grouped[name, default: []].append(option)
            }
        }
        return grouped.map { key, values in
            ChaseFoodOptionGroup(
                name: key,
                selectionMode: values.first?.selectionMode ?? "multiple",
                options: values.sorted { $0.displayOrder < $1.displayOrder }
            )
        }
        .sorted { ($0.options.first?.displayOrder ?? 0) < ($1.options.first?.displayOrder ?? 0) }
    }
    private var includedOptions: [ChaseFoodOption] { options.filter { $0.optionGroup == nil && $0.includedByDefault } }
    private var additionOptions: [ChaseFoodOption] { options.filter { $0.optionGroup == nil && !$0.includedByDefault } }
    private var extraFoods: [Food] {
        selectedExtraFoodIDs.compactMap { id in
            if let saved = diary.document.savedFoodConfigurations
                .lazy.flatMap(\.components).first(where: { $0.food.id == id }) { return saved.food }
            let pieces = id.components(separatedBy: ":")
            guard pieces.count >= 2, let source = FoodSource(rawValue: pieces[0]) else { return nil }
            return catalog.food(sourceID: pieces.dropFirst().joined(separator: ":"), source: source)
        }
    }
    private var ingredientSearchResults: [Food] {
        let query = ingredientQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        return catalog.searchAll(query, limit: 8).filter { $0.id != food.id }
    }
    private var selectedPortionID: String? { portionID.isEmpty ? nil : portionID }
    private var selectedPortionGrams: Double {
        food.portion(id: selectedPortionID)?.grams ?? food.baseAmountGrams
    }
    private var quantityInSelectedPortions: Double {
        switch unitChoice {
        case .portion:
            max(amount, 0)
        case .grams:
            max(amount, 0) / max(selectedPortionGrams, 0.001)
        case .ounces:
            max(amount, 0) * 28.349_523_125 / max(selectedPortionGrams, 0.001)
        }
    }
    private var selectedUnit: LogUnit {
        switch unitChoice {
        case .portion: .serving
        case .grams: .grams
        case .ounces: .ounces
        }
    }
    private var totalNutrients: MacroNutrients {
        configuredPortionNutrients.scaled(by: quantityInSelectedPortions)
    }
    private var configuredPortionNutrients: MacroNutrients {
        var total = food.nutrients(for: 1, unit: .serving, portionID: selectedPortionID)
        // A variant replaces the canonical base at the selected portion size.
        // It must not be added on top of a second copy of the same food.
        let selectedVariant = options.first(where: {
            $0.relationship.caseInsensitiveCompare("variant") == .orderedSame
                && selectedOptionIDs.contains($0.id)
        })
        if let selectedVariant {
            let grams = food.portion(id: selectedPortionID)?.grams ?? food.baseAmountGrams
            total = selectedVariant.food.nutrients(for: grams, unit: .grams)
        }
        for option in options {
            guard option.relationship.caseInsensitiveCompare("style") != .orderedSame,
                  option.relationship.caseInsensitiveCompare("variant") != .orderedSame else { continue }
            if selectedVariant != nil && option.includedByDefault { continue }
            let selected = selectedOptionIDs.contains(option.id)
            guard (option.includedByDefault && !selected) || (!option.includedByDefault && selected) else { continue }
            let nutrients = option.food.nutrients(for: option.amountGrams, unit: .grams)
            total = selected ? total + nutrients : MacroNutrients(
                calories: max(0, total.calories - nutrients.calories),
                carbs: max(0, total.carbs - nutrients.carbs),
                fat: max(0, total.fat - nutrients.fat),
                protein: max(0, total.protein - nutrients.protein),
                fiber: total.fiber.map { max(0, $0 - (nutrients.fiber ?? 0)) }
            )
        }
        for extra in extraFoods {
            total = total + extra.nutrients(for: 1, unit: .serving)
        }
        return total
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stickyFoodSummary
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        if !includedOptions.isEmpty || !additionOptions.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionLabel("Add to this food or meal")
                                Text("Tap any option; totals update instantly.")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.muted)
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                    ForEach(includedOptions) { option in
                                        optionPill(option, defaultSelected: true)
                                    }
                                    ForEach(additionOptions) { option in
                                        optionPill(option, defaultSelected: false)
                                    }
                                }
                            }
                        }

                        ForEach(optionGroups) { group in
                            optionSection(group.name, options: group.options)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            sectionLabel("Add another ingredient")
                            Button {
                                ingredientQuery = ""
                                showingIngredientSearch = true
                            } label: {
                                Label("Add another food", systemImage: "plus")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppTheme.coral)
                                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.controlFill, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("custom-food-add-ingredient")
                            if !extraFoods.isEmpty {
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                    ForEach(extraFoods) { ingredient in
                                        selectionPill(
                                            title: ingredient.name,
                                            detail: "Added · tap to remove",
                                            isSelected: true
                                        ) { toggleExtraFood(ingredient) }
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink {
                                SuggestedChangesEditor(text: $suggestedChanges)
                            } label: {
                                Text("Suggest a change")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.coral)
                                    .underline()
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("custom-food-show-suggestions")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 160)
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { nutritionAndLogFooter }
            .sheet(isPresented: $showingIngredientSearch) { ingredientSearchSheet }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var ingredientSearchSheet: some View {
        NavigationStack {
            List {
                if ingredientQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    Text("Search for a food to add it to this meal.")
                        .foregroundStyle(AppTheme.muted)
                } else if ingredientSearchResults.isEmpty {
                    ContentUnavailableView.search(text: ingredientQuery)
                } else {
                    ForEach(ingredientSearchResults) { ingredient in
                        Button {
                            if !selectedExtraFoodIDs.contains(ingredient.id) {
                                toggleExtraFood(ingredient)
                            }
                            showingIngredientSearch = false
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ingredient.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(AppTheme.ink)
                                    Text("\(Int(ingredient.nutrients(for: 1, unit: .serving).calories.rounded())) kcal · 1 serving")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.muted)
                                }
                                Spacer()
                                Image(systemName: selectedExtraFoodIDs.contains(ingredient.id) ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundStyle(AppTheme.coral)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $ingredientQuery, prompt: "Search foods")
            .navigationTitle("Add ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingIngredientSearch = false }
                }
            }
        }
    }

    private struct SuggestedChangesEditor: View {
        @Environment(\.dismiss) private var dismiss
        @Binding var text: String

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $text)
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("custom-food-suggested-changes")
                Text("This feedback is saved with your diary data and sent to your analytics server.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Suggested changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var stickyFoodSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.coral)
                        .frame(width: 36, height: 36, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("custom-food-back")
                Text(food.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .accessibilityIdentifier("custom-food-sticky-title")
                Spacer(minLength: 0)
                Menu {
                    if recentConfigurations.isEmpty {
                        Text("No saved variations yet")
                    } else {
                        Section("Recent variations") {
                            ForEach(recentConfigurations) { configuration in
                                Button(displayLabel(configuration)) {
                                    apply(configuration)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.muted)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Recent variations")
                .accessibilityIdentifier("custom-food-recent-variations")
            }
            HStack(spacing: 12) {
                calorieValue
                macroValue("Carbs", value: totalNutrients.carbs, color: AppTheme.carbs)
                Spacer(minLength: 0)
                macroValue("Fat", value: totalNutrients.fat, color: AppTheme.fat)
                Spacer(minLength: 0)
                macroValue("Protein", value: totalNutrients.protein, color: AppTheme.protein)
            }
            macroBar
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.background)
        .overlay(alignment: .bottom) { AppTheme.controlFill.frame(height: 1) }
    }

    private var nutritionAndLogFooter: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                Text("PORTION & QUANTITY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                quantityControls
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.controlFill, lineWidth: 1))

            Button(action: logConfiguration) {
                Text("Log Food")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(AppTheme.coral, in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .disabled(amount <= 0)
            .opacity(amount <= 0 ? 0.5 : 1)
            .shadow(color: AppTheme.coral.opacity(0.24), radius: 10, y: 5)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(AppTheme.background.opacity(0.72))
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var calorieValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(Int(totalNutrients.calories.rounded()))")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
                .contentTransition(.numericText())
            Text("kcal")
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.muted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories \(Int(totalNutrients.calories.rounded())) kcal")
        .accessibilityIdentifier("custom-food-estimate-calories")
    }

    private var quantityControls: some View {
        HStack(spacing: 5) {
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
            Menu {
                Picker("Unit", selection: unitSelection) {
                    ForEach(availableChoices, id: \.self) { choice in
                        Text(label(for: choice)).tag(choice)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(label(for: unitChoice))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.coral)
                .padding(.horizontal, 9)
                .frame(minWidth: 76, minHeight: 40, maxHeight: 40)
                .background(AppTheme.coral.opacity(0.10), in: Capsule())
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .accessibilityLabel("Portion or unit")
            .accessibilityValue(label(for: unitChoice))
            .accessibilityIdentifier("custom-food-unit-picker")
        }
    }

    private var availableChoices: [QuantityUnitChoice] {
        food.availablePortions.map { .portion($0.id) } + [.ounces, .grams]
    }

    private var unitSelection: Binding<QuantityUnitChoice> {
        Binding(
            get: { unitChoice },
            set: { choice in
                switch choice {
                case .portion(let id):
                    if case .portion = unitChoice {
                        portionID = id
                    } else {
                        portionID = id
                        amount = 1
                    }
                case .grams, .ounces:
                    let grams = currentQuantityInGrams
                    unitChoice = choice
                    amount = choice == .grams ? grams : grams / 28.349_523_125
                }
                unitChoice = choice
                amountIsFocused = false
            }
        )
    }

    private var currentQuantityInGrams: Double {
        switch unitChoice {
        case .portion: amount * selectedPortionGrams
        case .grams: amount
        case .ounces: amount * 28.349_523_125
        }
    }

    private var amountField: some View {
        TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...2)))
            .keyboardType(.decimalPad)
            .focused($amountIsFocused)
            .font(.subheadline.weight(.bold).monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: 48)
            .padding(.horizontal, 4)
            .padding(.vertical, 9)
            .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("Quantity")
            .accessibilityIdentifier("custom-food-quantity-value")
    }

    private func quantityAdjusterButton(
        title: String,
        accessibilityLabel: String,
        amountDelta: Double,
        isDisabled: Bool
    ) -> some View {
        Button {
            let adjustedAmount = amount + amountDelta
            guard adjustedAmount > 0 else { return }
            amount = adjustedAmount
            amountIsFocused = false
        } label: {
            Text(title)
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(width: 30, height: 36)
                .background(AppTheme.controlFill, in: Circle())
                .overlay(Circle().stroke(AppTheme.coral, lineWidth: 1.25))
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.coral)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(amountDelta < 0 ? "custom-food-quantity-minus" : "custom-food-quantity-plus")
    }

    private func label(for choice: QuantityUnitChoice) -> String {
        return switch choice {
        case .ounces: "ounces"
        case .grams: "grams"
        case .portion(let id):
            if let portion = food.portion(id: id) { portionDisplayLabel(portion) }
            else { "serving" }
        }
    }

    private func portionDisplayLabel(_ portion: FoodPortion) -> String {
        var label = portion.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = food.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if suffix.caseInsensitiveCompare("Taco") == .orderedSame,
           let qualifier = label.range(of: " (", options: .backwards) {
            label = String(label[..<qualifier.lowerBound])
        }
        guard !suffix.isEmpty,
              label.lowercased().hasSuffix(" " + suffix.lowercased()) else { return label }
        return String(label.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var macroBar: some View {
        let carbs = max(totalNutrients.carbs, 0)
        let fat = max(totalNutrients.fat, 0)
        let protein = max(totalNutrients.protein, 0)
        let total = carbs + fat + protein
        return GeometryReader { geometry in
            HStack(spacing: 0) {
                if total > 0 {
                    Rectangle().fill(AppTheme.carbs).frame(width: geometry.size.width * CGFloat(carbs / total))
                    Rectangle().fill(AppTheme.fat).frame(width: geometry.size.width * CGFloat(fat / total))
                    Rectangle().fill(AppTheme.protein).frame(width: geometry.size.width * CGFloat(protein / total))
                } else {
                    Rectangle().fill(AppTheme.controlFill)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carbs \(carbs.cleanAmount) grams, fat \(fat.cleanAmount) grams, protein \(protein.cleanAmount) grams")
        .accessibilityIdentifier("custom-food-macro-bar")
    }

    private func macroValue(_ title: String, value: Double, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(title).foregroundStyle(AppTheme.muted)
            Text("\(value.cleanAmount) g").foregroundStyle(color)
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.muted)
    }

    private func optionSection(_ title: String, options: [ChaseFoodOption]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(title)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(options) { option in optionPill(option, defaultSelected: option.includedByDefault) }
            }
        }
    }

    private func optionPill(_ option: ChaseFoodOption, defaultSelected: Bool) -> some View {
        let selected = selectedOptionIDs.contains(option.id)
        let calories = Int(option.food.nutrients(for: option.amountGrams, unit: .grams).calories.rounded())
        return selectionPill(
            title: option.displayName,
            detail: defaultSelected ? "\(calories) kcal" : "+\(calories) kcal",
            isSelected: selected
        ) { setOption(option, selected: !selected) }
    }

    private func selectionPill(title: String, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Circle()
                    .fill(isSelected ? AppTheme.coral : AppTheme.muted.opacity(0.45))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(isSelected ? AppTheme.coral : AppTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.coral)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(isSelected ? AppTheme.coral.opacity(0.13) : AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? AppTheme.coral : AppTheme.controlFill, lineWidth: 1.25))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.ink)
        .accessibilityLabel(title)
        .accessibilityValue("\(isSelected ? "Selected" : "Not selected"), \(detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func setOption(_ option: ChaseFoodOption, selected: Bool) {
        guard let group = option.optionGroup,
              let definition = optionGroups.first(where: { $0.name == group }),
              definition.selectionMode == "exclusive" else {
            if selected { selectedOptionIDs.insert(option.id) } else { selectedOptionIDs.remove(option.id) }
            return
        }
        for candidate in definition.options { selectedOptionIDs.remove(candidate.id) }
        if selected { selectedOptionIDs.insert(option.id) }
    }

    private func toggleExtraFood(_ ingredient: Food) {
        if selectedExtraFoodIDs.contains(ingredient.id) {
            selectedExtraFoodIDs.remove(ingredient.id)
        } else {
            selectedExtraFoodIDs.insert(ingredient.id)
        }
    }

    private func exclusiveSelection(for group: ChaseFoodOptionGroup) -> Binding<String> {
        Binding(
            get: { group.options.first(where: { selectedOptionIDs.contains($0.id) })?.id ?? "" },
            set: { selection in
                for option in group.options { selectedOptionIDs.remove(option.id) }
                if !selection.isEmpty { selectedOptionIDs.insert(selection) }
            }
        )
    }

    private var configuredComponents: [MealItem] {
        let hasVariant = options.contains {
            $0.relationship.caseInsensitiveCompare("variant") == .orderedSame
                && selectedOptionIDs.contains($0.id)
        }
        var selected = options.filter {
            selectedOptionIDs.contains($0.id) && $0.food.id != food.id
                && $0.relationship.caseInsensitiveCompare("style") != .orderedSame
                && (!hasVariant || !$0.includedByDefault || $0.relationship.caseInsensitiveCompare("variant") == .orderedSame)
        }.map { option in
            let amount = option.relationship.caseInsensitiveCompare("variant") == .orderedSame
                ? (food.portion(id: selectedPortionID)?.grams ?? food.baseAmountGrams)
                : option.amountGrams
            return MealItem(id: UUID(), food: option.food, amount: amount, unit: .grams)
        }
        selected += extraFoods.map { MealItem(id: UUID(), food: $0, amount: 1, unit: .serving) }
        return selected
    }

    private var variationLabel: String {
        let hasVariant = options.contains {
            $0.relationship.caseInsensitiveCompare("variant") == .orderedSame
                && selectedOptionIDs.contains($0.id)
        }
        let details = options.filter {
            selectedOptionIDs.contains($0.id) && $0.food.id != food.id
                && $0.relationship.caseInsensitiveCompare("style") != .orderedSame
        }.map(\.displayName)
            + extraFoods.map(\.name)
            + (hasVariant ? [] : includedOptions.filter { !selectedOptionIDs.contains($0.id) }.map { "no \($0.food.name.lowercased())" })
        let style = options.first {
            $0.optionGroup == "Style" && selectedOptionIDs.contains($0.id) && !$0.includedByDefault
        }?.displayName
        let namedDetails = details + (style.map { [$0] } ?? [])
        let portion = food.portion(id: selectedPortionID).map(portionDisplayLabel) ?? "serving"
        let normalizedPortion = portion.replacingOccurrences(of: " · ", with: ", ")
        return ([normalizedPortion] + namedDetails).joined(separator: ", ")
    }

    private func displayLabel(_ configuration: SavedFoodConfiguration) -> String {
        var label = configuration.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let foodName = food.name.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" · ", " • ", ", "] {
            let prefix = foodName + separator
            if label.range(of: prefix, options: .caseInsensitive).map({ $0.lowerBound == label.startIndex }) == true {
                label = String(label.dropFirst(prefix.count))
                break
            }
        }
        return label.replacingOccurrences(of: " · ", with: ", ")
            .replacingOccurrences(of: " • ", with: ", ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ", "))
    }

    private func apply(_ configuration: SavedFoodConfiguration) {
        selectedOptionIDs = Set(configuration.selectedOptionIDs)
        selectedExtraFoodIDs = Set(configuration.components.map(\.food.id))
        if let portionID = configuration.portionID, food.portion(id: portionID) != nil {
            self.portionID = portionID
            unitChoice = .portion(portionID)
            amount = 1
        }
        amountIsFocused = false
    }

    private func logConfiguration() {
        let note = suggestedChanges.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestion = note.isEmpty ? nil : FoodSuggestion(
            kind: .changeToFood, suggestedName: food.name, suggestedChanges: note, foodID: food.id)
        let configuration = SavedFoodConfiguration(
            baseFoodID: food.id,
            label: variationLabel,
            selectedOptionIDs: Array(selectedOptionIDs).sorted(),
            components: extraFoods.map { MealItem(id: UUID(), food: $0, amount: 1, unit: .serving) },
            portionID: selectedPortionID
        )
        diary.run(operation: "chase_food_configured_log") {
            let previousCount = diary.entries(on: date).count
            try await diary.logConfiguredFood(
                food, nutrients: totalNutrients, selectedOptionIDs: Array(selectedOptionIDs).sorted(),
                components: configuredComponents, suggestedChanges: note.isEmpty ? nil : note,
                portionID: selectedPortionID, amount: amount, unit: selectedUnit,
                configuration: configuration, suggestion: suggestion, on: date,
                allowCheatDay: true
            )
            if diary.entries(on: date).count > previousCount {
                AppAnalytics.capture("food.logged", properties: ["source": FoodSource.chaseFood.rawValue, "method": "customize"])
                if let suggestion {
                    AppAnalytics.capture("food.suggestion_submitted", properties: [
                        "kind": suggestion.kind.rawValue,
                        "suggested_name": suggestion.suggestedName,
                        "suggested_changes": suggestion.suggestedChanges,
                        "food_id": food.id
                    ])
                }
                dismiss()
            }
        }
    }
}

private enum QuantityUnitChoice: Hashable {
    case ounces
    case grams
    case portion(String)
}

struct CorpusFoodMeatTagEditor: View {
    @EnvironmentObject private var diary: DiaryStore
    let food: Food
    var onSaved: (() -> Void)? = nil

    @State private var processed: Bool?
    @State private var red: Bool?
    @State private var savedOverrides = FoodMeatOverrides(processed: nil, red: nil)
    @State private var automaticFood: Food?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var currentOverrides: FoodMeatOverrides {
        FoodMeatOverrides(processed: processed, red: red)
    }

    var body: some View {
        GroupBox("Meat classification") {
            VStack(alignment: .leading, spacing: 12) {
                tagPicker("Processed meat", choice: $processed, automatic: automaticFood?.containsProcessedMeat)
                tagPicker("Red meat", choice: $red, automatic: automaticFood?.containsRedMeat)
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                Button {
                    save()
                } label: {
                    if isSaving { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Save meat tags").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.bordered)
                .disabled(isSaving || currentOverrides == savedOverrides)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: food.id) {
            let current = diary.corpusFoodMeatOverrides(for: food)
            savedOverrides = current
            processed = current.processed
            red = current.red
            automaticFood = await diary.suggestedMeatClassification(for: food)
        }
    }

    private func tagPicker(_ title: String, choice: Binding<Bool?>, automatic: Bool?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker(title, selection: choice) {
                    Text("Automatic").tag(nil as Bool?)
                    Text("Yes").tag(true as Bool?)
                    Text("No").tag(false as Bool?)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel(title)
            }
            if let automatic {
                Text("Catalog default: \(automatic ? "Yes" : "No")")
                    .font(.caption).foregroundStyle(.secondary)
            } else if choice.wrappedValue == nil {
                Text("Catalog default: Unknown")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        diary.run(operation: "corpus_meat_tags.update") {
            do {
                try await diary.updateCorpusFoodMeatTags(originalFood: food, overrides: currentOverrides)
                savedOverrides = currentOverrides
                onSaved?()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
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
    private let onLogged: (QuantityPreference, QuantityPreference?) -> Void

    @State private var amount: Double
    @State private var unitChoice: QuantityUnitChoice
    @State private var initialUnitChoice: QuantityUnitChoice
    @State private var mealItems: [MealItem]
    @State private var mealItemsWereEdited = false
    @State private var processedMeatOverride: Bool?
    @State private var redMeatOverride: Bool?
    @State private var showingNameEditor = false
    @State private var showingMeatClassification = false
    @FocusState private var amountIsFocused: Bool

    init(
        food: Food,
        date: Date,
        onLogged: @escaping (QuantityPreference, QuantityPreference?) -> Void = { _, _ in }
    ) {
        _food = State(initialValue: food)
        self.date = date
        entryID = nil
        mealID = nil
        savedMeal = nil
        isMealEditor = false
        self.onLogged = onLogged
        _amount = State(initialValue: 1)
        _unitChoice = State(initialValue: .ounces)
        _initialUnitChoice = State(initialValue: .ounces)
        _mealItems = State(initialValue: [])
        _processedMeatOverride = State(initialValue: nil)
        _redMeatOverride = State(initialValue: nil)
    }

    init(
        meal: SavedMeal,
        date: Date,
        onLogged: @escaping (QuantityPreference, QuantityPreference?) -> Void = { _, _ in }
    ) {
        _food = State(initialValue: Self.mealFood(for: meal))
        self.date = date
        entryID = nil
        mealID = meal.id
        savedMeal = meal
        isMealEditor = true
        self.onLogged = onLogged
        _amount = State(initialValue: 1)
        _unitChoice = State(initialValue: .portion("saved-meal"))
        _initialUnitChoice = State(initialValue: .portion("saved-meal"))
        _mealItems = State(initialValue: meal.items)
        _processedMeatOverride = State(initialValue: nil)
        _redMeatOverride = State(initialValue: nil)
    }

    init(entry: DiaryEntry) {
        _food = State(initialValue: entry.food)
        date = entry.date
        entryID = entry.id
        mealID = entry.savedMealID
        savedMeal = nil
        isMealEditor = entry.isMeal
        onLogged = { _, _ in }
        _amount = State(initialValue: entry.amount)
        _mealItems = State(initialValue: entry.mealItems ?? [])
        _processedMeatOverride = State(initialValue: entry.processedMeatOverride)
        _redMeatOverride = State(initialValue: entry.redMeatOverride)
        if entry.isMeal {
            _unitChoice = State(initialValue: .portion(entry.portionID ?? "saved-meal"))
            _initialUnitChoice = State(initialValue: .portion(entry.portionID ?? "saved-meal"))
            return
        }
        switch entry.unit {
        case .ounces:
            _unitChoice = State(initialValue: .ounces)
            _initialUnitChoice = State(initialValue: .ounces)
        case .grams:
            _unitChoice = State(initialValue: .grams)
            _initialUnitChoice = State(initialValue: .grams)
        case .serving:
            if let portion = entry.food.portion(id: entry.portionID) {
                _unitChoice = State(initialValue: .portion(portion.id))
                _initialUnitChoice = State(initialValue: .portion(portion.id))
            } else {
                _unitChoice = State(initialValue: .ounces)
                _initialUnitChoice = State(initialValue: .ounces)
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
        guard case .portion(let id) = unitChoice else { return nil }
        return id
    }

    private var preview: MacroNutrients {
        food.nutrients(for: amount, unit: selectedUnit, portionID: selectedPortionID)
    }

    private var currentPreference: QuantityPreference {
        QuantityPreference(amount: amount, unit: selectedUnit, portionID: selectedPortionID)
    }

    private var initialPreference: QuantityPreference? {
        guard !isMealEditor else { return nil }
        switch initialUnitChoice {
        case .ounces:
            return QuantityPreference(amount: 1, unit: .ounces)
        case .grams:
            return QuantityPreference(amount: 100, unit: .grams)
        case .portion(let id):
            return QuantityPreference(amount: 1, unit: .serving, portionID: id)
        }
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
                            Picker("Unit", selection: unitSelection) {
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
                        if let fiber = preview.fiber {
                            nutrient("Fiber", fiber, suffix: "g")
                        }
                    }

                    Button(action: save) {
                        Text(saveTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(amount <= 0)

                    if entryID != nil {
                        GroupBox(isMealEditor ? "Meal-level meat tags" : "Meat classification") {
                            VStack(alignment: .leading, spacing: 12) {
                                meatTagPicker("Processed meat", choice: $processedMeatOverride,
                                              automatic: food.containsProcessedMeat)
                                meatTagPicker("Red meat", choice: $redMeatOverride,
                                              automatic: food.containsRedMeat)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if !isMealEditor, FoodCatalogIdentity(food: food) != nil {
                        DisclosureGroup(isExpanded: $showingMeatClassification) {
                            CorpusFoodMeatTagEditor(food: food)
                        } label: {
                            Text("Edit food meat tags")
                                .font(.subheadline.weight(.medium))
                        }
                        .accessibilityHint("Changes meat tags for this food in future logs")
                    }

                    if isMealEditor, !mealItems.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(entryID == nil ? "Contains" : "Meal ingredients")
                                .font(.headline)
                            if entryID != nil {
                                Text("Changes here apply to this logged meal only.")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.muted)
                                ForEach($mealItems) { item in
                                    MealItemEditorRow(item: item, showsMeatClassification: true) {
                                        mealItemsWereEdited = true
                                    }
                                }
                            } else {
                                ForEach(mealItems) { item in
                                    MealItemRow(item: item)
                                }
                            }
                        }
                        .padding(16)
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
                    let meal = diary.document.meals.first(where: { $0.id == mealID })
                {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(
                            diary.isFavorite(meal) ? "Unfavorite" : "Favorite",
                            systemImage: diary.isFavorite(meal) ? "star.fill" : "star"
                        ) {
                            diary.run {
                                let wasFavorite = diary.isFavorite(meal)
                                try await diary.toggleFavorite(meal)
                                AppAnalytics.capture(
                                    wasFavorite ? "favorite.removed" : "favorite.added",
                                    properties: ["item_type": "meal"]
                                )

                            }
                        }
                        .labelStyle(.iconOnly)
                    }
                } else if !isMealEditor {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(
                            diary.isFavorite(food) ? "Unfavorite" : "Favorite",
                            systemImage: diary.isFavorite(food) ? "star.fill" : "star"
                        ) {
                            diary.run {
                                let wasFavorite = diary.isFavorite(food)
                                try await diary.toggleFavorite(food, preference: currentPreference)
                                AppAnalytics.capture(
                                    wasFavorite ? "favorite.removed" : "favorite.added",
                                    properties: [
                                        "item_type": "food",
                                        "source": food.source.rawValue,
                                    ]
                                )

                            }
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
                            diary.run {
                                guard let mealID, try await diary.renameMeal(mealID: mealID, name: name) else { return }
                                food.name = diary.document.meals.first { $0.id == mealID }?.name ?? name

                            }
                        }
                    } else {
                        NameEditor(
                            title: "Rename food",
                            fieldTitle: "Food name",
                            footer:
                                "This name is saved when you leave this editor and will be used in the diary, favorites, and future searches.",
                            name: food.name
                        ) { name in
                            diary.run {
                                guard try await diary.renameFood(foodID: food.id, name: name) else { return }
                                food = diary.displayedFood(food)

                            }
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
                initialUnitChoice = unitChoice
            }
            .onChange(of: amount) { oldAmount, newAmount in
                guard entryID != nil, oldAmount > 0, newAmount > 0, oldAmount != newAmount else { return }
                let scale = newAmount / oldAmount
                mealItems = mealItems.map { item in
                    var scaledItem = item
                    scaledItem.amount *= scale
                    return scaledItem
                }
                // One-off meals have no saved template to recalculate from, so
                // persist the scaled snapshot alongside the new serving count.
                if mealID == nil {
                    mealItemsWereEdited = true
                }
            }
            .onDisappear {
                diary.run {
                    if entryID == nil, !isMealEditor, diary.isFavorite(food) {
                        try await diary.rememberPreference(currentPreference, for: food)
                    }

                }
            }
            .analyticsScreen(
                "quantity_editor",
                properties: [
                    "item_type": isMealEditor ? "meal" : "food",
                    "operation": entryID == nil ? "create" : "edit",
                ])
        }
    }

    private var unitSelection: Binding<QuantityUnitChoice> {
        Binding(
            get: { unitChoice },
            set: { choice in
                let previousChoice = unitChoice
                unitChoice = choice
                let unit: LogUnit = switch choice {
                case .ounces: .ounces
                case .grams: .grams
                case .portion: .serving
                }
                diary.rememberLastWeightUnit(unit)
                let previousUnit = self.unit(for: previousChoice)
                let previousPortionID = self.portionID(for: previousChoice)
                AppAnalytics.capture(
                    "food_log.unit_selected",
                    properties: FoodLogAnalytics.unitSelectionProperties(
                        food: food,
                        operation: entryID == nil ? "create" : "edit",
                        fromUnit: previousUnit,
                        fromPortionID: previousPortionID,
                        selectedUnit: unit,
                        selectedPortionID: self.portionID(for: choice),
                        defaultUnit: self.unit(for: initialUnitChoice),
                        defaultPortionID: self.portionID(for: initialUnitChoice)
                    )
                )
            }
        )
    }

    private func unit(for choice: QuantityUnitChoice) -> LogUnit {
        switch choice {
        case .ounces: .ounces
        case .grams: .grams
        case .portion: .serving
        }
    }

    private func portionID(for choice: QuantityUnitChoice) -> String? {
        guard case .portion(let id) = choice else { return nil }
        return id
    }

    private func label(for choice: QuantityUnitChoice) -> String {
        switch choice {
        case .ounces: "ounces"
        case .grams: "grams"
        case .portion(let id):
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
        diary.run {
            guard amount > 0 else { return }
            if let entryID {
                let previousEntry = diary.document.entries.first { $0.id == entryID }
                if isMealEditor {
                    if mealItemsWereEdited {
                        try await diary.updateMealEntry(
                            entryID: entryID,
                            amount: amount,
                            items: mealItems,
                            allowCheatDay: true
                        )
                    } else {
                        try await diary.updateMealEntry(
                            entryID: entryID,
                            amount: amount,
                            allowCheatDay: true
                        )
                    }
                } else {
                    try await diary.updateEntry(
                        entryID: entryID,
                        amount: amount,
                        unit: selectedUnit,
                        portionID: selectedPortionID,
                        allowCheatDay: true
                    )
                }
                if diary.document.entries.first(where: { $0.id == entryID }) != previousEntry {
                    AppAnalytics.capture(
                        "diary_entry.updated",
                        properties: [
                            "item_type": isMealEditor ? "meal" : "food",
                            "unit": selectedUnit.analyticsValue,
                        ])
                }
                if let currentEntry = diary.document.entries.first(where: { $0.id == entryID }),
                    currentEntry.processedMeatOverride != processedMeatOverride
                        || currentEntry.redMeatOverride != redMeatOverride
                {
                    try await diary.updateEntryMeatClassification(
                        entryID: entryID,
                        processed: processedMeatOverride,
                        red: redMeatOverride
                    )
                }
            } else if let savedMeal {
                let previousEntryCount = diary.entries(on: date).count
                let currentMeal = diary.document.meals.first { $0.id == savedMeal.id } ?? savedMeal
                try await diary.logMeal(
                    currentMeal,
                    amount: amount,
                    on: date,
                    allowCheatDay: true
                )
                if diary.entries(on: date).count > previousEntryCount {
                    onLogged(currentPreference, initialPreference)
                }
            } else {
                let previousEntryCount = diary.entries(on: date).count
                try await diary.log(
                    food,
                    amount: amount,
                    unit: selectedUnit,
                    portionID: selectedPortionID,
                    on: date,
                    allowCheatDay: true
                )
                if diary.entries(on: date).count > previousEntryCount {
                    onLogged(currentPreference, initialPreference)
                }
            }
            dismiss()

        }
    }

    private func breakApartMeal() {
        diary.run {
            guard let entryID else { return }
            let previousEntryCount = diary.entries(on: date).count
            try await diary.breakApartMeal(entryID: entryID)
            if diary.entries(on: date).count > previousEntryCount {
                AppAnalytics.capture("meal.broken_apart")
            }
            dismiss()

        }
    }

    private func meatTagPicker(_ title: String, choice: Binding<Bool?>, automatic: Bool?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Picker(title, selection: choice) {
                    Text("Automatic").tag(nil as Bool?)
                    Text("Yes").tag(true as Bool?)
                    Text("No").tag(false as Bool?)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 245)
            }
            Text(automatic.map { "Automatic: \($0 ? "Yes" : "No")" } ?? "Automatic: unknown")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
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
            portions: [FoodPortion(id: "saved-meal", label: "meal", grams: 1)],
            containsProcessedMeat: meal.resolvedContainsProcessedMeat,
            containsRedMeat: meal.resolvedContainsRedMeat
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

struct MealItemEditorRow: View {
    @Binding var item: MealItem
    var showsMeatClassification = false
    var onAmountChanged: () -> Void = {}
    @FocusState private var amountIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.food.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text(calorieDescription)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    TextField("Amount", value: amountBinding, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 68)
                        .textFieldStyle(.roundedBorder)
                        .focused($amountIsFocused)
                        .onChange(of: amountIsFocused) { _, isFocused in
                            if isFocused { selectAllAmount() }
                        }
                        .accessibilityLabel("Editable amount for " + item.food.name)
                        .accessibilityHint("Enter the quantity in " + unitLabel)
                    Text(unitLabel)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 110, alignment: .leading)
                }
            }
            if showsMeatClassification {
                VStack(alignment: .leading, spacing: 5) {
                    ingredientTagPicker("Processed meat", keyPath: \.processedMeatOverride,
                                        automatic: item.food.containsProcessedMeat)
                    ingredientTagPicker("Red meat", keyPath: \.redMeatOverride,
                                        automatic: item.food.containsRedMeat)
                }
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quantity for " + item.food.name)
    }

    private var amountBinding: Binding<Double> {
        Binding(
            get: { item.amount },
            set: {
                let clamped = min(max($0, 0.01), 100)
                guard clamped != item.amount else { return }
                item.amount = clamped
                onAmountChanged()
            }
        )
    }

    private func ingredientTagPicker(
        _ title: String,
        keyPath: WritableKeyPath<MealItem, Bool?>,
        automatic: Bool?
    ) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker(title, selection: Binding(
                get: { item[keyPath: keyPath] },
                set: { value in
                    guard value != item[keyPath: keyPath] else { return }
                    item[keyPath: keyPath] = value
                    onAmountChanged()
                }
            )) {
                Text("Automatic").tag(nil as Bool?)
                Text("Yes").tag(true as Bool?)
                Text("No").tag(false as Bool?)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 245)
        }
        .overlay(alignment: .bottomLeading) {
            Text(automatic.map { "Automatic: \($0 ? "Yes" : "No")" } ?? "Automatic: unknown")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.muted)
                .offset(y: 13)
        }
        .padding(.bottom, 12)
    }

    private var unitLabel: String {
        switch item.unit {
        case .grams, .ounces:
            item.unit.title
        case .serving:
            item.food.portion(id: item.portionID)?.label ?? item.unit.title
        }
    }

    private var calorieDescription: String {
        Int(nutrients.calories.rounded()).formatted() + " calories"
    }

    private var nutrients: MacroNutrients {
        item.food.nutrients(for: item.amount, unit: item.unit, portionID: item.portionID)
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
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
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
                if !diary.customMeals.isEmpty {
                    Section("Hand-created meals") {
                        ForEach(diary.customMeals) { meal in
                            mealRow(for: meal)
                        }
                    }
                }
                if !diary.importedMeals.isEmpty {
                    Section("Imported meals") {
                        ForEach(diary.importedMeals) { meal in
                            mealRow(for: meal)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func mealRow(for meal: SavedMeal) -> some View {
        MealListActionRow(
            meal: meal,
            onQuickLog: { onQuickLog(meal) },
            onEdit: { onEdit(meal) }
        )
        .swipeActions {
            Button("Delete", role: .destructive) {
                diary.run {
                    try await diary.deleteMeal(meal)
                    AppAnalytics.capture("meal.deleted", properties: ["origin": "food_picker"])

                }
            }
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

struct FlowLayout: Layout {
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
    private let analytics = AnalyticsService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                BarcodeScanner { code in
                    barcode = code
                    lookup(inputSource: "camera")
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 22))

                Text("Point the camera at a UPC or EAN barcode.")
                    .font(.subheadline).foregroundStyle(.secondary)

                HStack {
                    TextField("Enter barcode", text: $barcode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Look up") { lookup(inputSource: "manual") }
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

    private func lookup(inputSource: String) {
        let normalizedBarcode = barcode.filter(\.isNumber)
        guard !normalizedBarcode.isEmpty else {
            notFound = true
            return
        }
        if let food = catalog.food(barcode: normalizedBarcode) {
            notFound = false
            onSelect(food)
        } else {
            notFound = true
            Task {
                await analytics.capture(type: "barcode_search.no_match", properties: [
                    "barcode": String(normalizedBarcode.prefix(32)),
                    "input_source": inputSource
                ])
            }
        }
    }
}
