import Combine
import Foundation

/// Main-actor presentation cache. Mutations execute against current SQLite state off the main thread.
@MainActor
class DiaryStore: ObservableObject {
    @Published private(set) var document = DiaryDocument()
    @Published private(set) var lastSaveError: String?
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published private(set) var hasLoadedSnapshot = false
    @Published private(set) var currentStreak = StreakSummary.empty
    private(set) var repository: DiaryRepository?
    private var engine = DiaryEngine(document: DiaryDocument())
    private let fileURL: URL
    private let calendar: Calendar
    private let catalog: CatalogStore?
    private let healthKit: HealthKitStore?
    private let usesWindow: Bool
    private var initialDocument: DiaryDocument?
    private var openingTask: Task<DiaryRepository, Error>?
    private var selectedDay: Date?
    private var healthTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var pendingActions = 0
    private var refreshGeneration = 0

    init(
        fileURL: URL? = nil, calendar: Calendar = .current, catalog: CatalogStore? = nil,
        healthKit: HealthKitStore? = nil, referenceDate: Date = Date(), usesWindow: Bool = true
    ) {
        self.fileURL = fileURL ?? SharedDiaryStorage.defaultFileURL()
        self.calendar = calendar
        self.catalog = catalog
        self.healthKit = healthKit
        self.usesWindow = usesWindow
    }

    convenience init(
        document: DiaryDocument, fileURL: URL? = nil, calendar: Calendar = .current,
        catalog: CatalogStore? = nil, healthKit: HealthKitStore? = nil,
        referenceDate: Date = Date(), usesWindow: Bool = true
    ) {
        self.init(
            fileURL: fileURL, calendar: calendar, catalog: catalog, healthKit: healthKit,
            referenceDate: referenceDate, usesWindow: usesWindow)
        initialDocument = document
    }

    private func scope(at date: Date) -> DiaryScope {
        usesWindow ? .window(reference: date, selectedDay: selectedDay) : .all
    }

    private func open() async throws -> DiaryRepository {
        if let repository { return repository }
        if let openingTask { return try await openingTask.value }
        let url = fileURL
        let calendar = calendar
        let initial = initialDocument
        let catalog = catalog
        let task = Task.detached {
            if initial == nil, url == SharedDiaryStorage.defaultFileURL(), !SharedDiaryStorage.usesSimulatorFixture {
                guard SharedDiaryStorage.hasSharedContainer else {
                    throw DiaryDatabaseError.unavailable("The shared App Group container is unavailable.")
                }
                try DiaryJSONMigration.convertIfNeeded(
                    destination: url, sources: SharedDiaryStorage.legacyDiaryURLs,
                    backupDirectory: SharedDiaryStorage.migrationBackupDirectory, calendar: calendar)
            }
            let repository = try DiaryRepository(fileURL: url, calendar: calendar, catalog: catalog)
            if let initial { try repository.importDocument(initial) }
            return repository
        }
        openingTask = task
        defer { openingTask = nil }
        let opened = try await task.value
        repository = opened
        initialDocument = nil
        return opened
    }

    func reloadFromDisk(referenceDate: Date = Date()) async {
        do {
            let repository = try await open()
            try await repository.prepare(referenceDate: referenceDate)
            try await refresh(repository, referenceDate: referenceDate)
            lastSaveError = nil
            startHealthSync()
        } catch {
            lastSaveError = error.localizedDescription
        }
        isLoading = false
    }

    func selectDay(_ date: Date) async {
        selectedDay = date
        do { try await refresh(try await open(), referenceDate: Date()) } catch {
            lastSaveError = error.localizedDescription
        }
    }

    private func refresh(_ repository: DiaryRepository, referenceDate: Date) async throws {
        refreshGeneration += 1
        let generation = refreshGeneration
        let snapshot = try await repository.snapshot(scope: scope(at: referenceDate))
        guard generation == refreshGeneration else { return }
        publish(snapshot.document)
        let streak = try await repository.streak(referenceDate: referenceDate)
        guard generation == refreshGeneration else { return }
        currentStreak = streak
        isLoading = false
    }

    private func publish(_ document: DiaryDocument) {
        self.document = document
        engine = DiaryEngine(document: document, calendar: calendar, catalog: catalog)
        hasLoadedSnapshot = true
    }

    /// UI actions await commit before dismissal or success analytics. Errors stay visible at the root.
    func run(_ action: @escaping @MainActor () async throws -> Void) {
        let previous = actionTask
        pendingActions += 1
        isSaving = true
        actionTask = Task {
            await previous?.value
            defer {
                pendingActions -= 1
                isSaving = pendingActions > 0
            }
            do {
                try await action()
                lastSaveError = nil
            } catch {
                lastSaveError = error.localizedDescription
            }
        }
    }

    func dismissSaveError() { lastSaveError = nil }

    private func perform<T: Sendable>(scope: DiaryScope, _ action: @escaping @Sendable (DiaryEngine) throws -> T)
        async throws -> T
    {
        let repository = try await open()
        let result = try await repository.perform(scope: scope, action)
        SharedDiaryStorage.reloadWidget()
        startHealthSync()
        do { try await refresh(repository, referenceDate: Date()) }
        catch { throw DiaryDatabaseError.savedButRefreshFailed(error.localizedDescription) }
        return result
    }

    func syncAllHealthData() async {
        do {
            try await (try await open()).requestHealthReconciliation()
            startHealthSync()
            await healthTask?.value
        } catch { lastSaveError = error.localizedDescription }
    }

    func startHealthSync() {
        guard healthTask == nil, let repository, let healthKit,
            healthKit.authorizationState == .authorized
        else { return }
        healthTask = Task {
            defer { healthTask = nil }
            do {
                while !Task.isCancelled, let work = try await repository.nextHealthWork() {
                    guard await healthKit.apply(work) else { return }
                    try await repository.acknowledgeHealthWork(work)
                }
            } catch { lastSaveError = error.localizedDescription }
        }
    }

    #if DEBUG
        // Synchronous adapters are only for existing small unit-test fixtures, never called by the app.
        func loadTestFixture(referenceDate: Date) throws {
            let repository = try DiaryRepository(fileURL: fileURL, calendar: calendar, catalog: catalog)
            if let initialDocument {
                let enriched = DiaryEngine.backfilledFoodMetadata(in: initialDocument, catalog: catalog)
                try repository.importDocument(enriched)
                self.initialDocument = nil
            }
            self.repository = repository
            try repository.prepareSync(referenceDate: referenceDate)
            publish(try repository.snapshotSync().document)
            currentStreak = engine.streak(referenceDate: referenceDate)
            isLoading = false
        }

        func performTestMutation<T: Sendable>(scope: DiaryScope, _ action: (DiaryEngine) throws -> T) throws -> T {
            guard let repository else { throw DiaryDatabaseError.unavailable("Test store is not initialized.") }
            let result = try repository.performSync(scope: scope, action)
            publish(try repository.snapshotSync().document)
            return result
        }

    #endif

    func entries(on date: Date) -> [DiaryEntry] {
        engine.entries(on: date)
    }

    func totals(on date: Date) -> MacroNutrients {
        engine.totals(on: date)
    }

    func caloriesExcludingAlcohol(on date: Date) -> Double {
        engine.caloriesExcludingAlcohol(on: date)
    }

    func meatPresence(on date: Date) -> MeatClassification {
        engine.meatPresence(on: date)
    }

    func weeklyMeatDays(
        numberOfDays: Int = 30,
        referenceDate: Date = Date()
    ) -> [WeeklyMeatDays] {
        engine.weeklyMeatDays(numberOfDays: numberOfDays, referenceDate: referenceDate)
    }

    func weeklyMeatServings(
        numberOfDays: Int = 30,
        referenceDate: Date = Date()
    ) -> [WeeklyMeatServings] {
        engine.weeklyMeatServings(numberOfDays: numberOfDays, referenceDate: referenceDate)
    }

    func meatDayFoods(
        numberOfDays: Int = 30,
        referenceDate: Date = Date()
    ) -> [MeatDayFoods] {
        engine.meatDayFoods(numberOfDays: numberOfDays, referenceDate: referenceDate)
    }

    func alcoholEntry(on date: Date) -> AlcoholEntry? {
        engine.alcoholEntry(on: date)
    }

    func alcoholDrinkCount(on date: Date) -> Int {
        engine.alcoholDrinkCount(on: date)
    }

    func setAlcohol(drinks: Int, type: AlcoholType?, on date: Date) async throws {
        try await perform(scope: .day(date)) { $0.setAlcohol(drinks: drinks, type: type, on: date) }
    }

    func foodWeightReport(referenceDate: Date = Date()) -> FoodWeightReport {
        engine.foodWeightReport(referenceDate: referenceDate)
    }

    func status(on date: Date) -> DayStatus? {
        engine.status(on: date)
    }

    func canLogFood(on date: Date) -> Bool {
        engine.canLogFood(on: date)
    }

    func calorieAdjustment(on date: Date) -> Int? {
        engine.calorieAdjustment(on: date)
    }

    func setDailyCalorieGoal(_ goal: Int?) async throws {
        try await perform(scope: .all) { $0.setDailyCalorieGoal(goal) }
    }

    func markCheatDay(on date: Date, adjustmentCalories: Int? = nil) async throws {
        try await perform(scope: .day(date)) { $0.markCheatDay(on: date, adjustmentCalories: adjustmentCalories) }
    }

    func setCalorieAdjustment(_ calories: Int?, on date: Date) async throws {
        try await perform(scope: .day(date)) { $0.setCalorieAdjustment(calories, on: date) }
    }

    func undoCheatDay(on date: Date, preservingCalorieAdjustment: Bool = false) async throws {
        try await perform(scope: .day(date)) {
            $0.undoCheatDay(on: date, preservingCalorieAdjustment: preservingCalorieAdjustment)
        }
    }

    func finalizePastDays(referenceDate: Date = Date()) async throws {
        try await perform(scope: .all) { $0.finalizePastDays(referenceDate: referenceDate) }
    }

    func streak(referenceDate: Date) -> StreakSummary {
        engine.streak(referenceDate: referenceDate)
    }

    #if DEBUG
        func seedSpecialDaysForScreenshots(referenceDate: Date = Date()) async throws {
            try await perform(scope: .window(reference: referenceDate, selectedDay: nil)) {
                $0.seedSpecialDaysForScreenshots(referenceDate: referenceDate)
            }
        }

    #endif
    func log(_ food: Food, amount: Double, unit: LogUnit, portionID: String? = nil, on date: Date) async throws {
        try await perform(scope: .day(date)) {
            $0.log(food, amount: amount, unit: unit, portionID: portionID, on: date)
        }
    }

    func delete(entryID: UUID) async throws {
        try await perform(scope: .entries([entryID])) { $0.delete(entryID: entryID) }
    }

    func deleteEntries(entryIDs: Set<UUID>) async throws {
        try await perform(scope: .entries(entryIDs)) { $0.deleteEntries(entryIDs: entryIDs) }
    }

    func updateEntry(
        entryID: UUID,
        amount: Double,
        unit: LogUnit,
        portionID: String? = nil
    ) async throws {
        try await perform(scope: .entries([entryID])) {
            $0.updateEntry(entryID: entryID, amount: amount, unit: unit, portionID: portionID)
        }
    }

    func moveEntry(
        _ entryID: UUID,
        relativeTo targetEntryID: UUID,
        placeAfterTarget: Bool,
        on date: Date
    ) async throws {
        try await perform(scope: .day(date)) {
            $0.moveEntry(entryID, relativeTo: targetEntryID, placeAfterTarget: placeAfterTarget, on: date)
        }
    }

    func moveEntry(_ entryID: UUID, toIndex destinationIndex: Int, on date: Date) async throws {
        try await perform(scope: .day(date)) { $0.moveEntry(entryID, toIndex: destinationIndex, on: date) }
    }

    func preference(for food: Food) -> QuantityPreference {
        engine.preference(for: food)
    }

    func rememberLastWeightUnit(_ unit: LogUnit) {
        engine.rememberLastWeightUnit(unit)
    }

    func rememberPreference(_ preference: QuantityPreference, for food: Food) async throws {
        try await perform(scope: .library) { $0.rememberPreference(preference, for: food) }
    }

    func quickLog(_ food: Food, on date: Date) async throws {
        try await perform(scope: .day(date)) { $0.quickLog(food, on: date) }
    }

    @discardableResult
    func logMagicSuggestion(_ suggestion: MagicFoodSuggestion, on date: Date) async throws -> [FoodPickerItem] {
        try await perform(scope: .window(reference: date, selectedDay: date)) {
            $0.logMagicSuggestion(suggestion, on: date)
        }
    }

    @discardableResult
    func logQuickSelection(_ selectionID: String, on date: Date = Date()) async throws -> QuickLogResult? {
        try await perform(scope: .window(reference: date, selectedDay: date)) {
            $0.logQuickSelection(selectionID, on: date)
        }
    }

    func isFavorite(_ food: Food) -> Bool {
        engine.isFavorite(food)
    }

    func toggleFavorite(_ food: Food, preference: QuantityPreference? = nil) async throws {
        try await perform(scope: .library) { $0.toggleFavorite(food, preference: preference) }
    }

    func isFavorite(_ meal: SavedMeal) -> Bool {
        engine.isFavorite(meal)
    }

    func toggleFavorite(_ meal: SavedMeal) async throws {
        try await perform(scope: .library) { $0.toggleFavorite(meal) }
    }

    func magicSuggestions(
        at referenceDate: Date = Date(),
        lookbackDays: Int = 10,
        limit: Int = 4
    ) -> [MagicFoodSuggestion] {
        engine.magicSuggestions(at: referenceDate, lookbackDays: lookbackDays, limit: limit)
    }

    func magicSuggestionResult(
        at referenceDate: Date = Date(),
        lookbackDays: Int = 10,
        limit: Int = 4
    ) -> MagicFoodSuggestionResult {
        engine.magicSuggestionResult(at: referenceDate, lookbackDays: lookbackDays, limit: limit)
    }

    @discardableResult
    func addCustomFood(
        name: String,
        brand: String,
        calories: Double,
        carbs: Double,
        fat: Double,
        protein: Double,
        fiber: Double? = nil,
        servingGrams: Double,
        servingDescription: String = "1 serving",
        containsProcessedMeat: Bool? = nil,
        containsRedMeat: Bool? = nil
    ) async throws -> Food {
        try await perform(scope: .library) {
            $0.addCustomFood(
                name: name, brand: brand, calories: calories, carbs: carbs, fat: fat, protein: protein, fiber: fiber,
                servingGrams: servingGrams, servingDescription: servingDescription,
                containsProcessedMeat: containsProcessedMeat, containsRedMeat: containsRedMeat)
        }
    }

    @discardableResult
    func updateCustomFood(
        foodID: String,
        name: String,
        brand: String,
        calories: Double,
        carbs: Double,
        fat: Double,
        protein: Double,
        fiber: Double? = nil,
        servingGrams: Double,
        containsProcessedMeat: Bool? = nil,
        containsRedMeat: Bool? = nil,
        meatOverrides: FoodMeatOverrides? = nil
    ) async throws -> Bool {
        try await perform(scope: .food(foodID)) {
            $0.updateCustomFood(
                foodID: foodID, name: name, brand: brand, calories: calories, carbs: carbs, fat: fat, protein: protein,
                fiber: fiber, servingGrams: servingGrams, containsProcessedMeat: containsProcessedMeat,
                containsRedMeat: containsRedMeat, meatOverrides: meatOverrides)
        }
    }

    @discardableResult
    func saveMeal(
        name: String,
        items: [MealItem],
        containsProcessedMeat: Bool? = nil,
        containsRedMeat: Bool? = nil,
        origin: SavedMealOrigin = .custom
    ) async throws -> SavedMeal? {
        try await perform(scope: .library) {
            $0.saveMeal(
                name: name, items: items, containsProcessedMeat: containsProcessedMeat,
                containsRedMeat: containsRedMeat, origin: origin)
        }
    }

    @discardableResult
    func updateSavedMeal(
        mealID: UUID,
        name: String,
        items: [MealItem],
        containsProcessedMeat: Bool? = nil,
        containsRedMeat: Bool? = nil,
        meatOverrides: FoodMeatOverrides? = nil
    ) async throws -> Bool {
        try await perform(scope: .meal(mealID)) {
            $0.updateSavedMeal(
                mealID: mealID, name: name, items: items, containsProcessedMeat: containsProcessedMeat,
                containsRedMeat: containsRedMeat, meatOverrides: meatOverrides)
        }
    }

    func saveMeal(name: String, replacing entryIDs: Set<UUID>, on date: Date) async throws {
        try await perform(scope: .day(date)) { $0.saveMeal(name: name, replacing: entryIDs, on: date) }
    }

    func breakApartMeal(entryID: UUID) async throws {
        try await perform(scope: .entries([entryID])) { $0.breakApartMeal(entryID: entryID) }
    }

    func deleteCustomFood(_ food: Food) async throws {
        try await perform(scope: .library) { $0.deleteCustomFood(food) }
    }

    func deleteMeal(_ meal: SavedMeal) async throws {
        try await perform(scope: .library) { $0.deleteMeal(meal) }
    }

    func logMeal(_ meal: SavedMeal, amount: Double = 1, on date: Date) async throws {
        try await perform(scope: .day(date)) { $0.logMeal(meal, amount: amount, on: date) }
    }

    func logImportedFood(_ food: Food, saveForReuse: Bool, on date: Date) async throws -> Food {
        try await perform(scope: .day(date)) { try $0.logImportedFood(food, saveForReuse: saveForReuse, on: date) }
    }

    func logImportedMeal(_ meal: SavedMeal, on date: Date) async throws -> SavedMeal {
        try await perform(scope: .day(date)) { try $0.logImportedMeal(meal, on: date) }
    }

    func suggestedMeatClassification(name: String) async -> Food {
        let catalog = catalog
        return await Task.detached {
            FoodResolver(catalog: catalog).resolve(Food(
                sourceID: "preview", source: .custom, name: name, brand: nil, barcode: nil,
                nutrients: .zero, baseAmountGrams: 1, servingGrams: nil, servingDescription: nil))
        }.value
    }

    func unknownMeatEntryCount(processed: Bool, red: Bool) -> Int {
        engine.unknownMeatEntryCount(processed: processed, red: red)
    }

    func foodResolutionReview() async throws -> [FoodResolutionReview] {
        let repository = try await open()
        let catalog = catalog
        let document = try await repository.snapshot(scope: .all).document
        return await Task.detached { DiaryEngine(document: document, catalog: catalog).foodResolutionReview() }.value
    }

    func applyFoodResolutionReview(_ review: FoodResolutionReview) async throws {
        try await applyFoodResolutionReviews([review])
    }

    func applyFoodResolutionReviews(_ reviews: [FoodResolutionReview]) async throws {
        guard !reviews.isEmpty else { return }
        let repository = try await open()
        let backup = repository.fileURL.deletingLastPathComponent()
            .appendingPathComponent("ClassificationBackups", isDirectory: true)
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        try await Task.detached {
            try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try repository.backup(to: backup)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            try DiaryRepository(fileURL: backup, catalog: nil).validate()
        }.value
        try await perform(scope: .foods(Set(reviews.map { $0.food.id }))) {
            try $0.applyFoodResolutionReviews(reviews)
        }
    }

    func logOneOffMeal(_ meal: SavedMeal, amount: Double = 1, on date: Date) async throws {
        try await perform(scope: .day(date)) { $0.logOneOffMeal(meal, amount: amount, on: date) }
    }

    func updateMealEntry(entryID: UUID, amount: Double) async throws {
        try await perform(scope: .entries([entryID])) { $0.updateMealEntry(entryID: entryID, amount: amount) }
    }

    func updateMealEntry(entryID: UUID, amount: Double, items: [MealItem]) async throws {
        try await perform(scope: .entries([entryID])) {
            $0.updateMealEntry(entryID: entryID, amount: amount, items: items)
        }
    }

    @discardableResult
    func renameMeal(mealID: UUID, name: String) async throws -> Bool {
        try await perform(scope: .meal(mealID)) { $0.renameMeal(mealID: mealID, name: name) }
    }

    func searchPersonalFoods(_ query: String) -> [Food] {
        engine.searchPersonalFoods(query)
    }

    func searchItems(_ query: String, catalogFoods: [Food], limit: Int = 50) -> [FoodPickerItem] {
        engine.searchItems(query, catalogFoods: catalogFoods, limit: limit)
    }

    func searchItemsIncludingHistory(_ query: String, catalogFoods: [Food]) async -> [FoodPickerItem] {
        do {
            let repository = try await open()
            let snapshot = try await repository.snapshot(scope: .search(query))
            return DiaryEngine(document: snapshot.document, calendar: calendar, catalog: catalog)
                .searchItems(query, catalogFoods: catalogFoods)
        } catch {
            lastSaveError = error.localizedDescription
            return []
        }
    }

    func displayedFood(_ food: Food) -> Food {
        engine.displayedFood(food)
    }

    @discardableResult
    func renameFood(foodID: String, name: String) async throws -> Bool {
        try await perform(scope: .food(foodID)) { $0.renameFood(foodID: foodID, name: name) }
    }

    func clearPersonalData() async throws {
        try await perform(scope: .all) { $0.clearPersonalData() }
    }

    func totalsByDay(numberOfDays: Int = 30) -> [(date: Date, nutrients: MacroNutrients)] {
        engine.totalsByDay(numberOfDays: numberOfDays)
    }

    var dailyCalorieGoal: Int? { engine.dailyCalorieGoal }
    var favoriteMeals: [SavedMeal] { engine.favoriteMeals }
    var favoriteItems: [FoodPickerItem] { engine.favoriteItems }
    var alphabetizedMeals: [SavedMeal] { engine.alphabetizedMeals }
    var customMeals: [SavedMeal] { engine.customMeals }
    var importedMeals: [SavedMeal] { engine.importedMeals }
    var recentFoods: [Food] { engine.recentFoods }
    var recentItems: [FoodPickerItem] { engine.recentItems }
    var frequentFoods: [Food] { engine.frequentFoods }
    var frequentItems: [FoodPickerItem] { engine.frequentItems }
}
