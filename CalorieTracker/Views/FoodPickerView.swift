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
    var componentSelection: ComponentSelectionContext? = nil

    @State private var mode: Mode?
    @State private var recentItemsSnapshot: [FoodPickerItem] = []
    @State private var frequentItemsSnapshot: [FoodPickerItem] = []
    @State private var magicSuggestionsSnapshot: [MagicFoodSuggestion] = []
    @State private var magicHasExcludedMatchesSnapshot = false
    @State private var magicTimeRange = MagicFoodTimeRange(date: Date(), calendar: .current)
    @State private var didLoadInitialSnapshot = false
    @State private var selectedFood: Food?
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

    init(date: Date, catalog: CatalogStore, initialMode: Mode? = nil, componentSelection: ComponentSelectionContext? = nil) {
        self.date = date
        self.catalog = catalog
        self.componentSelection = componentSelection
        _mode = State(initialValue: initialMode ?? (componentSelection == nil ? nil : .recent))
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
                        },
                        showsLoggingTools: componentSelection == nil
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
                            onEditConfiguration: editConfiguration,
                            onQuickLogMeal: logMeal,
                            onEditMeal: editMeal,
                            onSearchResultSelected: captureSearchResultSelection,
                            onAddCustomFood: {
                                finishSearchAttempt(recordNothingSelected: false)
                                showingCustomFoodEditor = true
                            },
                            onSuggestCanonical: { showingFoodSuggestionEditor = true },
                            componentMode: componentSelection != nil
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
                                    items: eligible(recentItemsSnapshot),
                                    onQuickLogFood: quickLog,
                                    onEditFood: { editFood($0) },
                                    onQuickLogMeal: logMeal,
                                    onEditMeal: editMeal,
                                    onDeleteMeal: deleteMeal, actionTitle: componentSelection == nil ? "Quick add" : "Add", allowsDelete: componentSelection == nil
                                )
                            case .frequent:
                                FoodPickerList(
                                    title: "Most used · 30 days",
                                    emptyTitle: "No suggestions yet",
                                    emptyMessage: "Your most-used foods and meals will appear here.",
                                    items: eligible(frequentItemsSnapshot),
                                    onQuickLogFood: quickLog,
                                    onEditFood: { editFood($0) },
                                    onQuickLogMeal: logMeal,
                                    onEditMeal: editMeal,
                                    onDeleteMeal: deleteMeal, actionTitle: componentSelection == nil ? "Quick add" : "Add", allowsDelete: componentSelection == nil
                                )
                            case .favorites:
                                FoodPickerList(
                                    title: nil,
                                    emptyTitle: "No favorites",
                                    emptyMessage: "Star any food or meal to keep it here.",
                                    items: eligible(diary.favoriteItems),
                                    onQuickLogFood: quickLog,
                                    onEditFood: { editFood($0) },
                                    onQuickLogMeal: logMeal,
                                    onEditMeal: editMeal,
                                    onDeleteMeal: deleteMeal, actionTitle: componentSelection == nil ? "Quick add" : "Add", allowsDelete: componentSelection == nil
                                )
                            case .meals:
                                FoodPickerList(title: "Meals", emptyTitle: "No meals", emptyMessage: "Save a meal to find it here.",
                                    items: eligible(diary.document.meals.map { .meal($0) }), onQuickLogFood: quickLog,
                                    onEditFood: editFood, onQuickLogMeal: logMeal, onEditMeal: editMeal, onDeleteMeal: deleteMeal, actionTitle: componentSelection == nil ? "Quick add" : "Add", allowsDelete: componentSelection == nil)
                            }
                        } else {
                            magicSuggestionsContent
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle(componentSelection == nil ? "Log food" : "Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if componentSelection == nil { FoodPickerCalorieSummary(date: date) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        finishSearchAttempt()
                        dismiss()
                    }
                }
            }
            .fullScreenCover(item: $selectedFood, onDismiss: { customizingConfiguration = nil }) { food in
                if let componentSelection {
                    FoodDetailView(item: MealItem(id: UUID(), food: food, amount: 1, unit: .serving,
                        portionID: food.availablePortions.first?.id), catalog: catalog, date: date,
                        initialConfiguration: customizingConfiguration, isNewSelection: true) { item in
                        componentSelection.onSelect([item])
                        selectedFood = nil
                        dismiss()
                    }
                } else {
                    FoodDetailView(food: food, catalog: catalog, date: date, initialConfiguration: customizingConfiguration) { preference, defaultPreference in
                        markCurrentSearchLogged()
                        captureFoodLog(food: food, method: "quantity_editor", unit: preference.unit, portionID: preference.portionID,
                            defaultUnit: defaultPreference?.unit, defaultPortionID: defaultPreference?.portionID)
                    }
                }
            }
            .fullScreenCover(item: $selectedMeal) { meal in
                if let componentSelection {
                    MealDetailView(context: .component(meal, { items in
                        componentSelection.onSelect(items)
                        selectedMeal = nil
                        dismiss()
                    }), catalog: catalog)
                } else {
                    MealDetailView(context: .log(meal, date, { preference, _ in
                        markCurrentSearchLogged()
                        captureMealLog(meal: meal, method: "quantity_editor", unit: preference.unit)
                    }), catalog: catalog)
                }
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
                    savesToLibrary: componentSelection == nil,
                    onSaved: { food in
                        if let componentSelection {
                            componentSelection.onSelect([MealItem(id: UUID(), food: food, amount: 1, unit: .serving, portionID: "custom-serving")])
                            dismiss()
                            return
                        }
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
                results = eligible(matches)
                isSearching = false
                searchAttempt.completed(query: normalizedQuery, resultCount: results.count)
            }
            .onDisappear {
                // Opening detail is still part of this search attempt.
                if selectedFood == nil && selectedMeal == nil && !showingCustomFoodEditor && !showingMealAnalysis {
                    finishSearchAttempt()
                }
            }
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
            onQuickLog: logMagicSuggestion,
            onOpenFood: editFood,
            onOpenMeal: editMeal
        )
    }

    private func quickLog(_ food: Food) {
        if let componentSelection {
            componentSelection.onSelect([MealItem(id: UUID(), food: food, amount: 1, unit: .serving,
                                                  portionID: food.availablePortions.first?.id)])
            dismiss()
            return
        }
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
        searchIsFocused = false
        customizingConfiguration = nil
        selectedFood = food
    }

    private func editMeal(_ meal: SavedMeal) {
        searchIsFocused = false
        selectedMeal = meal
    }

    private func eligible(_ items: [FoodPickerItem]) -> [FoodPickerItem] {
        guard let componentSelection else { return items }
        return items.filter {
            switch $0 {
            case .food(let food): !componentSelection.excludedFoodIDs.contains(food.id)
            case .meal(let meal): !componentSelection.excludedMealIDs.contains(meal.id)
                && !meal.items.contains { componentSelection.excludedFoodIDs.contains($0.food.id) }
            }
        }
    }

    private func editConfiguration(_ food: Food, _ configuration: SavedFoodConfiguration) {
        searchIsFocused = false
        customizingConfiguration = configuration
        selectedFood = food
    }

    private func quickLogConfiguration(_ food: Food, _ configuration: SavedFoodConfiguration) {
        markCurrentSearchLogged()
        let base = configuration.snapshot?.baseFood ?? food
        let options = configuration.snapshot?.options ?? (base.source == .chaseFood ? catalog.chaseFoodOptions(for: base.sourceID) : [])
        let selected = Set(configuration.selectedOptionIDs)
        let nutrients = FoodConfigurationCalculator.nutrients(food: base, options: options, selected: selected,
            extras: configuration.components, portionID: configuration.portionID)
        let additions = options.filter {
            selected.contains($0.id) && $0.relationship.lowercased() != "style"
                && $0.food.id != base.id
                && (!options.contains { $0.relationship.lowercased() == "variant" && selected.contains($0.id) }
                    || !$0.includedByDefault || $0.relationship.lowercased() == "variant")
        }.map {
            MealItem(id: UUID(), food: $0.food,
                amount: $0.relationship.lowercased() == "variant" ? (base.portion(id: configuration.portionID)?.grams ?? base.baseAmountGrams) : $0.amountGrams,
                unit: .grams, configurationOptionID: $0.id)
        } + configuration.components
        var refreshedConfiguration = SavedFoodConfiguration(baseFoodID: food.id, label: configuration.label,
                                                            selectedOptionIDs: configuration.selectedOptionIDs,
                                                            components: configuration.components, portionID: configuration.portionID)
        let snapshot = configuration.snapshot ?? FoodConfigurationSnapshot(selectedOptionIDs: configuration.selectedOptionIDs,
            components: additions, suggestedChanges: nil, catalogVersion: catalog.catalogVersion,
            baseFood: base, options: options, extraComponents: configuration.components, portionID: configuration.portionID)
        if let componentSelection {
            let configuredFood = FoodConfigurationCalculator.configuredFood(base: base, portionNutrients: nutrients,
                                                                            portionID: configuration.portionID)
            componentSelection.onSelect([MealItem(id: UUID(), food: configuredFood, amount: 1, unit: .serving,
                                                  portionID: configuration.portionID, foodConfigurationSnapshot: snapshot)])
            dismiss()
            return
        }
        refreshedConfiguration.snapshot = snapshot
        let savedVariation = refreshedConfiguration
        diary.run(operation: "chase_food_saved_variation_log") {
            let previousCount = diary.entries(on: date).count
            try await diary.logConfiguredFood(base, nutrients: nutrients, selectedOptionIDs: configuration.selectedOptionIDs,
                                              components: additions, suggestedChanges: nil, portionID: configuration.portionID,
                                              snapshot: snapshot, configuration: savedVariation, suggestion: nil, on: date, allowCheatDay: true)
            guard diary.entries(on: date).count > previousCount else { return }
            captureFoodLog(food: food, method: "saved_configuration", unit: .serving, portionID: configuration.portionID)
        }
    }

    private func logMeal(_ meal: SavedMeal) {
        if componentSelection != nil { editMeal(meal); return }
        diary.run {
            markCurrentSearchLogged()
            let previousEntryCount = diary.entries(on: date).count
            try await diary.logMeal(meal, on: date, allowCheatDay: true)
            guard diary.entries(on: date).count > previousEntryCount else { return }
            captureMealLog(meal: meal, method: "quick_add", unit: .serving)

        }
    }

    private func deleteMeal(_ meal: SavedMeal) {
        guard componentSelection == nil else { return }
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
        guard componentSelection == nil else { return }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return }
        searchAttempt.logged(query: normalizedQuery)
    }

    private func finishSearchAttempt(recordNothingSelected: Bool = true) {
        guard componentSelection == nil else { return }
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

    private var enabledSources: Set<FoodSource> {
        var sources = Set<FoodSource>()
        if usdaEnabled { sources.insert(.usda) }
        if offEnabled { sources.insert(.openFoodFacts) }
        if chaseFoodEnabled { sources.insert(.chaseFood) }
        return sources
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
                normalizedQuery, catalogFoods: catalog.searchAll(normalizedQuery, enabledSources: enabledSources)
            )
            guard normalizedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            results = eligible(matches)
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
    var showsLoggingTools = true
    var isEnabled = true
    var onDisabledTap: (() -> Void)? = nil
    let onSelect: (FoodPickerView.Mode) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(FoodPickerView.Mode.allCases.filter { showsLoggingTools || $0 != .magic }) { item in
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

            if showsLoggingTools {
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
    let onOpenFood: (Food) -> Void
    let onOpenMeal: (SavedMeal) -> Void

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
                            onQuickLog: { onQuickLog(suggestion) },
                            onOpenFood: onOpenFood,
                            onOpenMeal: onOpenMeal
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
    let onOpenFood: (Food) -> Void
    let onOpenMeal: (SavedMeal) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(suggestion.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                    }
                    itemButton(item)
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
    private func itemButton(_ item: FoodPickerItem) -> some View {
        switch item {
        case .food(let food):
            Button { onOpenFood(food) } label: {
                HStack(spacing: 9) {
                    SourceBadge(source: food.source)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name).font(.body.weight(.semibold)).lineLimit(2)
                        Text(foodDescription(food)).font(.caption).foregroundStyle(AppTheme.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize \(food.name)")
        case .meal(let meal):
            Button { onOpenMeal(meal) } label: {
                HStack(spacing: 9) {
                    MealBadge()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meal.name).font(.body.weight(.semibold)).lineLimit(2)
                        Text("\(Int(meal.nutrients.calories.rounded())) cal · saved meal")
                            .font(.caption).foregroundStyle(AppTheme.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize \(meal.name)")
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
    var actionTitle = "Quick add"
    var allowsDelete = true

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
                                actionTitle: actionTitle,
                                action: { onQuickLogFood(food) }, openAction: { onEditFood(food) }
                            )

                        case .meal(let meal):
                            MealListActionRow(
                                meal: meal,
                                onQuickLog: { onQuickLogMeal(meal) },
                                onEdit: { onEditMeal(meal) }, actionTitle: actionTitle
                            )
                            .swipeActions {
                                if allowsDelete { Button("Delete", role: .destructive) { onDeleteMeal(meal) } }
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
        SearchItemRow(itemName: food.name, identifier: "customize-food-" + food.id,
            actionTitle: actionTitle, action: action, openAction: openAction) {
            SourceBadge(source: food.source)
            foodDescription
        }
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
            guard actionTitle != "Customize" else { return }
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
        .accessibilityHint(isAdded ? "Ready to add again" : actionTitle == "Add" ? "Adds this food to the parent draft" : "Adds the displayed quantity")
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
    let onEditConfiguration: (Food, SavedFoodConfiguration) -> Void
    let onQuickLogMeal: (SavedMeal) -> Void
    let onEditMeal: (SavedMeal) -> Void
    let onSearchResultSelected: (FoodPickerItem) -> Void
    let onAddCustomFood: () -> Void
    let onSuggestCanonical: () -> Void
    var componentMode = false

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
                if !componentMode { Button("Suggest a canonical food", systemImage: "lightbulb", action: onSuggestCanonical)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10) }
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
                                    actionTitle: componentMode ? "Add" : "Quick add",
                                    action: {
                                        onSearchResultSelected(.food(food))
                                        onQuickLogFood(food)
                                    },
                                    openAction: {
                                        onSearchResultSelected(.food(food))
                                        onEditFood(food)
                                    }
                                )
                                let variations = diary.document.savedFoodConfigurations
                                    .filter { $0.baseFoodID == food.id }
                                    .sorted { $0.lastUsedAt > $1.lastUsedAt }
                                    .prefix(2)
                                ForEach(Array(variations)) { configuration in
                                    HStack(spacing: 8) {
                                        Button {
                                            onSearchResultSelected(.food(food))
                                            onEditConfiguration(food, configuration)
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
                                            actionTitle: componentMode ? "Add" : "Quick add",
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
                                }, actionTitle: componentMode ? "Customize" : "Quick add"
                            )
                        }
                    }
                } footer: {
                    Text(componentMode ? "Customize a food, then add it to your draft." : "Tap + to log the displayed quantity. Tap the row to change it.")
                }
                if !componentMode { Section {
                    Button("Suggest a canonical food or search change", systemImage: "lightbulb", action: onSuggestCanonical)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } }
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

struct MealItemRow: View {
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
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
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
                guard $0.isFinite else { return }
                let maximum = item.unit == .grams ? 10_000.0 : item.unit == .ounces ? 1_000.0 : 100.0
                let clamped = min(max($0, 0.01), maximum)
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
        VStack(alignment: .leading, spacing: 5) {
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
            .frame(maxWidth: .infinity)
            Text(automatic.map { "Automatic: \($0 ? "Yes" : "No")" } ?? "Automatic: unknown")
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
        }
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

struct NameEditor: View {
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
    var actionTitle = "Quick add"

    var body: some View {
        SearchItemRow(itemName: meal.name, identifier: "customize-meal-" + meal.id.uuidString,
            actionTitle: actionTitle, action: onQuickLog, openAction: onEdit) { MealListRow(meal: meal) }
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

/// An explicit detail target and an independent contextual shortcut for every source/list.
private struct SearchItemRow<Content: View>: View {
    let itemName: String
    let identifier: String
    var actionTitle: String?
    var action: (() -> Void)?
    var openAction: (() -> Void)?
    @ViewBuilder var content: () -> Content
    private var primaryLabel: some View {
        HStack(spacing: 12) { content(); Spacer(minLength: 0) }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }
    var body: some View {
        HStack(spacing: 12) {
            if let openAction {
                Button(action: openAction) { primaryLabel }.buttonStyle(.plain)
                    .accessibilityLabel("Customize " + itemName).accessibilityIdentifier(identifier)
            } else { primaryLabel }
            if let actionTitle, let action {
                AddConfirmationButton(actionTitle: actionTitle, itemName: itemName, action: action)
                    .frame(minWidth: 44, minHeight: 44)
            } else { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary) }
        }.padding(.vertical, 4)
    }
}
