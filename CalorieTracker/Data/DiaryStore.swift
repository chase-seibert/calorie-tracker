import Combine
import Foundation

#if DEBUG
struct DiaryDatabaseBackup: Identifiable, Sendable {
    let url: URL
    let createdAt: Date
    let byteCount: Int64

    var id: String { url.path }
}
#endif

enum DiaryPerformanceDiagnostics {
    private static let maximumLogBytes = 512 * 1024
    private static let fileName = "diary-performance.jsonl"

    static func newOperationID() -> String {
        UUID().uuidString
    }

    static func monotonicTimestamp() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func elapsedMilliseconds(since timestamp: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - timestamp) / 1_000_000
    }

    static func record(
        _ event: String,
        operationID: String? = nil,
        properties: [String: String] = [:]
    ) {
        SharedDiaryStorage.migrateLegacyDiagnostics()
        let root = SharedDiaryStorage.diagnosticsDirectoryURL()
        let file = root.appendingPathComponent(fileName)
        var boundedProperties = properties.mapValues { String($0.prefix(256)) }
        if let operationID {
            boundedProperties["operation_id"] = String(operationID.prefix(128))
        }
        let entry: [String: Any] = [
            "event": event,
            "occurred_at": ISO8601DateFormatter().string(from: Date()),
            "properties": boundedProperties
        ]
        guard JSONSerialization.isValidJSONObject(entry),
              let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }

        let manager = FileManager.default
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            if let attributes = try? manager.attributesOfItem(atPath: file.path),
               let size = attributes[.size] as? NSNumber, size.intValue >= maximumLogBytes {
                let rotated = root.appendingPathComponent(fileName + ".1")
                try? manager.removeItem(at: rotated)
                try manager.moveItem(at: file, to: rotated)
            }
            if !manager.fileExists(atPath: file.path) {
                try Data().write(to: file, options: .atomic)
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data + Data([0x0A]))
            try? manager.setAttributes(
                [.posixPermissions: 0o600, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: file.path
            )
        } catch {
            // Diagnostics must never interrupt diary actions.
        }
    }
}

private struct TimedDiaryOperation: Sendable {
    let name: String
    let id: String
    let startedAt: UInt64

    init(name: String, id: String? = nil) {
        self.name = name
        self.id = id ?? DiaryPerformanceDiagnostics.newOperationID()
        startedAt = DispatchTime.now().uptimeNanoseconds
    }

    func record(_ event: String, properties: [String: String] = [:]) {
        var properties = properties
        properties["operation"] = name
        properties["elapsed_ms"] = String(format: "%.1f", elapsedMilliseconds)
        DiaryPerformanceDiagnostics.record(event, operationID: id, properties: properties)
    }

    var elapsedMilliseconds: Double {
        Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
    }
}

enum DiaryLoadingPhase: Equatable, Sendable {
    case checkingStorage
    case migratingLegacyDiary
    case openingDatabase
    case importingDiary
    case preparingDiary
    case loadingEntries
    case calculatingStreak
    case preparingWeeklyReports
    case ready
    case failed

    var message: String {
        switch self {
        case .checkingStorage: "Checking diary storage…"
        case .migratingLegacyDiary: "Converting your existing diary…"
        case .openingDatabase: "Opening the diary database…"
        case .importingDiary: "Importing diary data…"
        case .preparingDiary: "Preparing diary days…"
        case .loadingEntries: "Loading diary entries…"
        case .calculatingStreak: "Calculating your streak…"
        case .preparingWeeklyReports: "Preparing weekly reports…"
        case .ready: "Diary ready"
        case .failed: "Diary unavailable"
        }
    }
}

/// Main-actor presentation cache. Mutations execute against current SQLite state off the main thread.
@MainActor
class DiaryStore: ObservableObject {
    @Published private(set) var document = DiaryDocument()
    @Published private(set) var lastSaveError: String?
    @Published private(set) var isLoading = true
    @Published private(set) var loadingPhase: DiaryLoadingPhase = .checkingStorage
    @Published private(set) var isSaving = false
    @Published private(set) var hasLoadedSnapshot = false
    @Published private(set) var currentStreak = StreakSummary.empty
    @Published private(set) var isCalculatingStreak = false
    private(set) var repository: DiaryRepository?
    private var engine = DiaryEngine(document: DiaryDocument())
    private let fileURL: URL
    private let calendar: Calendar
    var foodCatalog: CatalogStore { catalog ?? CatalogStore() }
    private let catalog: CatalogStore?
    private let healthKit: HealthKitStore?
    private let usesWindow: Bool
    private var initialDocument: DiaryDocument?
    private var openingTask: Task<DiaryRepository, Error>?
    private var selectedDay: Date?
    private var healthTask: Task<Void, Never>?
    private var finalizationTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var pendingActions = 0
    private var refreshGeneration = 0

    init(
        fileURL: URL? = nil, calendar: Calendar = .current, catalog: CatalogStore? = nil,
        healthKit: HealthKitStore? = nil, referenceDate: Date = Date(), usesWindow: Bool = true
    ) {
        SharedDiaryStorage.migrateLegacyDiagnostics()
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
        let updateLoadingPhase: @MainActor @Sendable (DiaryLoadingPhase) -> Void = { [weak self] phase in
            self?.loadingPhase = phase
        }
        let task = Task.detached {
            await updateLoadingPhase(.checkingStorage)
            if initial == nil, url == SharedDiaryStorage.defaultFileURL(), !SharedDiaryStorage.usesSimulatorFixture {
                guard SharedDiaryStorage.hasSharedContainer else {
                    throw DiaryDatabaseError.unavailable("The shared App Group container is unavailable.")
                }
            }
            await updateLoadingPhase(.openingDatabase)
            let repository = try DiaryRepository(fileURL: url, calendar: calendar, catalog: catalog)
            if let initial {
                await updateLoadingPhase(.importingDiary)
                try repository.importDocument(initial)
            }
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
        if !hasLoadedSnapshot { isLoading = true }
        loadingPhase = .checkingStorage
        do {
            let repository = try await open()
            try await refresh(repository, referenceDate: referenceDate)
            lastSaveError = nil
            loadingPhase = .ready
            scheduleFinalization(repository, referenceDate: referenceDate)
            scheduleHealthSyncAfterReadiness()
        } catch {
            lastSaveError = error.localizedDescription
            loadingPhase = .failed
        }
        isLoading = false
    }

    func showLoadingPhase(_ phase: DiaryLoadingPhase) {
        loadingPhase = phase
    }

    func selectDay(_ date: Date) async {
        selectedDay = date
        do { try await refresh(try await open(), referenceDate: Date()) } catch {
            lastSaveError = error.localizedDescription
        }
    }

    private func refresh(
        _ repository: DiaryRepository,
        referenceDate: Date,
        operation: TimedDiaryOperation? = nil
    ) async throws {
        operation?.record("refresh_started")
        refreshGeneration += 1
        let generation = refreshGeneration
        if isLoading { loadingPhase = .loadingEntries }
        operation?.record("snapshot_started")
        let snapshot = try await repository.snapshot(scope: scope(at: referenceDate))
        operation?.record("snapshot_finished", properties: [
            "entry_count": String(snapshot.document.entries.count),
            "meal_count": String(snapshot.document.meals.count)
        ])
        guard generation == refreshGeneration else {
            operation?.record("refresh_discarded_as_stale")
            return
        }
        publish(snapshot.document)
        operation?.record("snapshot_published")
        scheduleStreak(repository, referenceDate: referenceDate, snapshotGeneration: generation, operation: operation)
        isLoading = false
        operation?.record("refresh_finished")
    }

    private func scheduleStreak(
        _ repository: DiaryRepository,
        referenceDate: Date,
        snapshotGeneration: Int,
        operation: TimedDiaryOperation? = nil
    ) {
        if !hasLoadedSnapshot { loadingPhase = .calculatingStreak }
        isCalculatingStreak = true
        operation?.record("streak_started")
        Task { [weak self] in
            do {
                let streak = try await repository.streak(referenceDate: referenceDate)
                operation?.record("streak_finished")
                guard let self, self.repository === repository,
                      self.refreshGeneration == snapshotGeneration else {
                    operation?.record("streak_discarded_as_stale")
                    return
                }
                self.currentStreak = streak
                self.isCalculatingStreak = false
            } catch {
                operation?.record("streak_failed", properties: ["error_type": String(describing: type(of: error))])
                guard let self, self.repository === repository,
                      self.refreshGeneration == snapshotGeneration else { return }
                self.isCalculatingStreak = false
            }
        }
    }

    private func scheduleFinalization(_ repository: DiaryRepository, referenceDate: Date) {
        guard finalizationTask == nil else { return }
        let operation = TimedDiaryOperation(name: "startup_finalization")
        operation.record("finalization_started")
        finalizationTask = Task { [weak self] in
            defer { self?.finalizationTask = nil }
            do {
                try await repository.prepare(referenceDate: referenceDate)
                operation.record("finalization_finished")
                guard let self, self.repository === repository else { return }
                try await self.refresh(repository, referenceDate: Date(), operation: operation)
            } catch {
                operation.record("finalization_failed", properties: ["error_type": String(describing: type(of: error))])
                self?.lastSaveError = error.localizedDescription
            }
        }
    }

    private func scheduleHealthSyncAfterReadiness() {
        guard let healthKit else { return }
        Task { [weak self] in
            healthKit.refreshAuthorizationState()
            self?.startHealthSync()
        }
    }

    private func publish(_ document: DiaryDocument) {
        self.document = document
        engine = DiaryEngine(document: document, calendar: calendar, catalog: catalog)
        hasLoadedSnapshot = true
    }

    /// UI actions await commit before dismissal or success analytics. Errors stay visible at the root.
    func run(
        operation: String? = nil,
        operationID: String? = nil,
        _ action: @escaping @MainActor () async throws -> Void
    ) {
        let previous = actionTask
        pendingActions += 1
        isSaving = true
        let queuedAt = DispatchTime.now().uptimeNanoseconds
        if let operation {
            DiaryPerformanceDiagnostics.record(
                "action_queued",
                operationID: operationID,
                properties: [
                    "operation": operation,
                    "pending_actions": String(pendingActions),
                    "queued_behind_previous": String(previous != nil)
                ]
            )
        }
        actionTask = Task {
            await previous?.value
            if let operation {
                DiaryPerformanceDiagnostics.record(
                    "action_started",
                    operationID: operationID,
                    properties: [
                        "operation": operation,
                        "queue_wait_ms": String(format: "%.1f", Double(DispatchTime.now().uptimeNanoseconds - queuedAt) / 1_000_000)
                    ]
                )
            }
            defer {
                pendingActions -= 1
                isSaving = pendingActions > 0
            }
            do {
                try await action()
                if let operation {
                    DiaryPerformanceDiagnostics.record(
                        "action_completed",
                        operationID: operationID,
                        properties: [
                            "operation": operation,
                            "total_action_ms": String(format: "%.1f", Double(DispatchTime.now().uptimeNanoseconds - queuedAt) / 1_000_000)
                        ]
                    )
                }
                lastSaveError = nil
            } catch {
                if let operation {
                    DiaryPerformanceDiagnostics.record(
                        "action_failed",
                        operationID: operationID,
                        properties: [
                            "operation": operation,
                            "total_action_ms": String(format: "%.1f", Double(DispatchTime.now().uptimeNanoseconds - queuedAt) / 1_000_000),
                            "error_type": String(describing: type(of: error))
                        ]
                    )
                }
                lastSaveError = error.localizedDescription
            }
        }
    }

    func dismissSaveError() { lastSaveError = nil }

    private func perform<T: Sendable>(
        scope: DiaryScope,
        operation: TimedDiaryOperation? = nil,
        syncHealth: Bool = true,
        _ action: @escaping @Sendable (DiaryEngine) throws -> T
    ) async throws -> T {
        do {
            operation?.record("store_open_started")
            let repository = try await open()
            operation?.record("store_open_finished")
            operation?.record("database_mutation_started")
            let result = try await repository.perform(scope: scope, action)
            operation?.record("database_mutation_finished")
            SharedDiaryStorage.reloadWidget()
            operation?.record("widget_reload_requested")
            if syncHealth { startHealthSync(operation: operation) }
            do {
                try await refresh(repository, referenceDate: Date(), operation: operation)
            } catch {
                operation?.record("refresh_failed", properties: ["error_type": String(describing: type(of: error))])
                throw DiaryDatabaseError.savedButRefreshFailed(error.localizedDescription)
            }
            operation?.record("store_action_completed")
            return result
        } catch {
            operation?.record("store_action_failed", properties: ["error_type": String(describing: type(of: error))])
            throw error
        }
    }

    func syncAllHealthData() async {
        do {
            try await (try await open()).requestHealthReconciliation()
            startHealthSync()
            await healthTask?.value
        } catch { lastSaveError = error.localizedDescription }
    }

    private func startHealthSync(operation: TimedDiaryOperation? = nil) {
        guard healthTask == nil else {
            operation?.record("health_sync_already_running")
            return
        }
        guard let repository else {
            operation?.record("health_sync_skipped", properties: ["reason": "repository_unavailable"])
            return
        }
        guard let healthKit else {
            operation?.record("health_sync_skipped", properties: ["reason": "healthkit_unavailable"])
            return
        }
        guard healthKit.authorizationState == .authorized else {
            operation?.record("health_sync_skipped", properties: ["reason": "not_authorized"])
            return
        }
        operation?.record("health_sync_scheduled")
        healthTask = Task {
            operation?.record("health_sync_started")
            var workIndex = 0
            defer {
                healthTask = nil
                operation?.record("health_sync_finished", properties: ["work_count": String(workIndex)])
            }
            do {
                while !Task.isCancelled, let work = try await repository.nextHealthWork() {
                    workIndex += 1
                    operation?.record("health_sync_work_started", properties: ["work_index": String(workIndex)])
                    guard await healthKit.apply(work) else { return }
                    try await repository.acknowledgeHealthWork(work)
                    operation?.record("health_sync_work_finished", properties: ["work_index": String(workIndex)])
                }
            } catch {
                operation?.record("health_sync_failed", properties: ["error_type": String(describing: type(of: error))])
                lastSaveError = error.localizedDescription
            }
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
            isCalculatingStreak = false
            isLoading = false
        }

        func performTestMutation<T: Sendable>(scope: DiaryScope, _ action: (DiaryEngine) throws -> T) throws -> T {
            guard let repository else { throw DiaryDatabaseError.unavailable("Test store is not initialized.") }
            let result = try repository.performSync(scope: scope, action)
            publish(try repository.snapshotSync().document)
            return result
        }

    #endif

    #if DEBUG
        private static let databaseBackupLimit = 8
        private static let databaseBackupRetention: TimeInterval = 30 * 24 * 60 * 60

        func databaseBackups() -> [DiaryDatabaseBackup] {
            let root = fileURL.deletingLastPathComponent()
                .appendingPathComponent("SQLiteTransfers", isDirectory: true)
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return urls.compactMap { url in
                guard url.lastPathComponent.hasPrefix("BeforeImport-"), url.pathExtension == "sqlite",
                    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                    let createdAt = values.contentModificationDate
                else { return nil }
                return DiaryDatabaseBackup(url: url, createdAt: createdAt, byteCount: Int64(values.fileSize ?? 0))
            }
            .sorted { $0.createdAt > $1.createdAt }
        }

        private func pruneDatabaseBackups() throws {
            let backups = databaseBackups()
            let cutoff = Date().addingTimeInterval(-Self.databaseBackupRetention)
            for backup in backups.enumerated() where backup.offset >= Self.databaseBackupLimit || backup.element.createdAt < cutoff {
                try FileManager.default.removeItem(at: backup.element.url)
            }
        }

        func exportDatabase() async throws -> Data {
            let repository = try await open()
            let calendar = calendar
            let directory = fileURL.deletingLastPathComponent()
                .appendingPathComponent("SQLiteTransfers", isDirectory: true)
                .appendingPathComponent("Exports", isDirectory: true)
            let destination = directory.appendingPathComponent(UUID().uuidString + ".sqlite")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let data = try await Task.detached {
                try repository.backup(to: destination)
                let validation = try DiaryRepository(fileURL: destination, calendar: calendar, catalog: nil)
                try validation.validate()
                try validation.closeStagingSnapshot()
                return try Data(contentsOf: destination)
            }.value
            return data
        }

        func importDatabase(from sourceURL: URL) async throws -> URL {
            guard !isSaving else {
                throw DiaryDatabaseError.unavailable("Finish the current save before importing a database.")
            }
            let repository = try await open()
            let calendar = calendar
            let manager = FileManager.default
            let transferRoot = fileURL.deletingLastPathComponent()
                .appendingPathComponent("SQLiteTransfers", isDirectory: true)
            let importDirectory = transferRoot.appendingPathComponent("Import-" + UUID().uuidString, isDirectory: true)
            let candidate = importDirectory.appendingPathComponent("Incoming.sqlite")
            let backup = transferRoot.appendingPathComponent("BeforeImport-" + UUID().uuidString + ".sqlite")
            try manager.createDirectory(at: importDirectory, withIntermediateDirectories: true)
            try manager.createDirectory(at: transferRoot, withIntermediateDirectories: true)
            defer { try? manager.removeItem(at: importDirectory) }

            let isManagedBackup = sourceURL.deletingLastPathComponent().standardizedFileURL == transferRoot.standardizedFileURL
                && sourceURL.lastPathComponent.hasPrefix("BeforeImport-")
                && sourceURL.pathExtension == "sqlite"
            let accessing = !isManagedBackup && sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
            for suffix in ["-wal", "-shm", "-journal"] where !isManagedBackup && manager.fileExists(atPath: sourceURL.path + suffix) {
                throw DiaryDatabaseError.invalidData("Choose a standalone SQLite export, not a live database with sidecar files.")
            }
            try manager.copyItem(at: sourceURL, to: candidate)

            try await Task.detached {
                let incoming = try DiaryRepository(fileURL: candidate, calendar: calendar, catalog: nil)
                try incoming.validate()
                try incoming.closeStagingSnapshot()
            }.value

            healthTask?.cancel()
            await healthTask?.value
            healthTask = nil

            try await Task.detached {
                try repository.backup(to: backup)
                let validation = try DiaryRepository(fileURL: backup, calendar: calendar, catalog: nil)
                try validation.validate()
                try validation.closeStagingSnapshot()
            }.value

            refreshGeneration += 1
            try repository.close()
            self.repository = nil
            try replaceLiveDatabase(with: candidate)
            initialDocument = nil
            document = DiaryDocument()
            engine = DiaryEngine(document: document, calendar: calendar, catalog: catalog)
            currentStreak = .empty
            hasLoadedSnapshot = false
            isLoading = true
            lastSaveError = nil
            await reloadFromDisk(referenceDate: Date())
            guard hasLoadedSnapshot else {
                throw DiaryDatabaseError.unavailable(lastSaveError ?? "The imported database could not be opened.")
            }
            try? pruneDatabaseBackups()
            return backup
        }

        private func replaceLiveDatabase(with candidate: URL) throws {
            let manager = FileManager.default
            let liveURL = fileURL
            let sidecarArchive = liveURL.deletingLastPathComponent()
                .appendingPathComponent("SQLiteTransfers", isDirectory: true)
                .appendingPathComponent("ArchivedSidecars-" + UUID().uuidString, isDirectory: true)
            try manager.createDirectory(at: sidecarArchive, withIntermediateDirectories: true)
            for suffix in ["-wal", "-shm", "-journal"] {
                let sidecar = URL(fileURLWithPath: liveURL.path + suffix)
                if manager.fileExists(atPath: sidecar.path) {
                    try manager.moveItem(at: sidecar, to: sidecarArchive.appendingPathComponent(sidecar.lastPathComponent))
                }
            }
            if manager.fileExists(atPath: liveURL.path) {
                _ = try manager.replaceItemAt(liveURL, withItemAt: candidate, backupItemName: nil, options: [])
            } else {
                try manager.moveItem(at: candidate, to: liveURL)
            }
        }
    #endif

    func entries(on date: Date) -> [DiaryEntry] {
        engine.entries(on: date)
    }

    func saveFoodSuggestion(_ suggestion: FoodSuggestion) async throws {
        try await perform(scope: .library) { engine in
            engine.saveFoodSuggestion(suggestion)
        }
    }

    func deleteSavedFoodConfiguration(id: UUID) async throws {
        try await perform(scope: .library) { engine in
            engine.deleteSavedFoodConfiguration(id: id)
        }
    }

    func logConfiguredFood(
        _ food: Food,
        nutrients: MacroNutrients,
        selectedOptionIDs: [String],
        components: [MealItem],
        suggestedChanges: String?,
        portionID: String?,
        amount: Double = 1,
        unit: LogUnit = .serving,
        snapshot: FoodConfigurationSnapshot? = nil,
        companions: [Food] = [],
        configuration: SavedFoodConfiguration,
        suggestion: FoodSuggestion?,
        on date: Date,
        allowCheatDay: Bool = false
    ) async throws {
        try await perform(scope: .day(date)) { engine in
            engine.logConfiguredFood(food, nutrients: nutrients, selectedOptionIDs: selectedOptionIDs,
                                     components: components, suggestedChanges: suggestedChanges,
                                     portionID: portionID, amount: amount, unit: unit, snapshot: snapshot,
                                     companions: companions,
                                     on: date, allowCheatDay: allowCheatDay)
            engine.saveFoodConfiguration(configuration)
            if let suggestion { engine.saveFoodSuggestion(suggestion) }
        }
    }

    func logFoodWithCompanions(
        _ food: Food,
        amount: Double,
        unit: LogUnit,
        portionID: String?,
        companions: [Food],
        on date: Date
    ) async throws {
        try await perform(scope: .day(date)) { engine in
            engine.log(food, amount: amount, unit: unit, portionID: portionID, on: date, allowCheatDay: true)
            for companion in companions {
                engine.quickLog(companion, on: date, allowCheatDay: true)
            }
        }
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

    func updateMeatServingsOverride(contributions: [MeatDayFoodContribution], servings: Double?) async throws {
        let entryIDs = Set(contributions.map(\.entryID))
        guard !entryIDs.isEmpty else { return }
        try await perform(scope: .entries(entryIDs)) {
            $0.updateMeatServingsOverride(contributions: contributions, servings: servings)
        }
    }

    func corpusFoodMeatOverrides(for food: Food) -> FoodMeatOverrides {
        engine.corpusFoodMeatOverrides(for: food)
    }

    func alcoholEntry(on date: Date) -> AlcoholEntry? {
        engine.alcoholEntry(on: date)
    }

    func alcoholDrinkCount(on date: Date) -> Int {
        engine.alcoholDrinkCount(on: date)
    }

    func setAlcohol(
        drinks: Int,
        type: AlcoholType?,
        on date: Date,
        allowCheatDay: Bool = false
    ) async throws {
        try await perform(scope: .day(date)) {
            $0.setAlcohol(drinks: drinks, type: type, on: date, allowCheatDay: allowCheatDay)
        }
    }

    func foodWeightReport(referenceDate: Date = Date()) -> FoodWeightReport {
        engine.foodWeightReport(referenceDate: referenceDate)
    }

    func status(on date: Date) -> DayStatus? {
        engine.status(on: date)
    }

    func dailyNote(on date: Date) -> String? {
        engine.dailyNote(on: date)
    }

    func saveDailyNote(_ text: String?, on date: Date) async throws {
        try await perform(scope: .day(date), syncHealth: false) { $0.setDailyNote(text, on: date) }
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

    func markCheatDay(
        on date: Date,
        adjustmentCalories: Int? = nil,
        diagnosticsID: String? = nil
    ) async throws {
        try await perform(
            scope: .day(date),
            operation: TimedDiaryOperation(name: "cheat_day_mark", id: diagnosticsID)
        ) { $0.markCheatDay(on: date, adjustmentCalories: adjustmentCalories) }
    }

    func setCalorieAdjustment(_ calories: Int?, on date: Date) async throws {
        try await perform(scope: .day(date)) { $0.setCalorieAdjustment(calories, on: date) }
    }

    func undoCheatDay(
        on date: Date,
        preservingCalorieAdjustment: Bool = false,
        diagnosticsID: String? = nil
    ) async throws {
        try await perform(
            scope: .day(date),
            operation: TimedDiaryOperation(name: "cheat_day_clear", id: diagnosticsID)
        ) {
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
    func log(
        _ food: Food,
        amount: Double,
        unit: LogUnit,
        portionID: String? = nil,
        on date: Date,
        allowCheatDay: Bool = false
    ) async throws {
        try await perform(scope: .day(date)) {
            $0.log(
                food,
                amount: amount,
                unit: unit,
                portionID: portionID,
                on: date,
                allowCheatDay: allowCheatDay
            )
        }
    }

    func delete(entryID: UUID) async throws {
        try await perform(scope: .entries([entryID])) { $0.delete(entryID: entryID) }
    }

    func duplicateEntry(entryID: UUID, on date: Date) async throws {
        try await perform(scope: .entryAndDay(entryID, date)) { try $0.duplicateEntry(entryID: entryID, on: date) }
    }

    func duplicateEntries(entryIDs: Set<UUID>, on date: Date) async throws {
        try await perform(scope: .entriesAndDay(entryIDs, date)) { try $0.duplicateEntries(entryIDs: entryIDs, on: date) }
    }

    func deleteEntries(entryIDs: Set<UUID>) async throws {
        try await perform(scope: .entries(entryIDs)) { $0.deleteEntries(entryIDs: entryIDs) }
    }

    func updateEntry(
        entryID: UUID,
        amount: Double,
        unit: LogUnit,
        portionID: String? = nil,
        allowCheatDay: Bool = false
    ) async throws {
        try await perform(scope: .entries([entryID])) {
            $0.updateEntry(
                entryID: entryID,
                amount: amount,
                unit: unit,
                portionID: portionID,
                allowCheatDay: allowCheatDay
            )
        }
    }

    func updateFoodDraft(draft: MealItem, original: DiaryEntry) async throws {
        try await perform(scope: .entries([original.id])) { try $0.updateFoodDraft(entryID: original.id, draft: draft, original: original) }
    }

    func updateMealDraft(original: DiaryEntry, name: String, amount: Double, items: [MealItem], processed: Bool?, red: Bool?) async throws {
        try await perform(scope: .entries([original.id])) {
            try $0.updateMealDraft(original: original, name: name, amount: amount, items: items, processed: processed, red: red)
        }
    }

    func updateEntryMeatClassification(entryID: UUID, processed: Bool?, red: Bool?) async throws {
        try await perform(scope: .entries([entryID])) {
            $0.updateEntryMeatClassification(entryID: entryID, processed: processed, red: red)
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

    func quickLog(_ food: Food, on date: Date, allowCheatDay: Bool = false) async throws {
        try await perform(scope: .day(date)) { $0.quickLog(food, on: date, allowCheatDay: allowCheatDay) }
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
    func saveLoggedMeal(entryID: UUID, favorite: Bool = false) async throws -> SavedMeal {
        try await perform(scope: .entries([entryID])) {
            try $0.saveLoggedMeal(entryID: entryID, favorite: favorite)
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

    func hideFood(_ food: Food) async throws {
        try await perform(scope: .library) { $0.hideFood(food) }
    }

    func restoreHiddenFood(id: String) async throws {
        try await perform(scope: .library) { $0.restoreHiddenFood(id: id) }
    }

    func deleteMeal(_ meal: SavedMeal) async throws {
        try await perform(scope: .library) { $0.deleteMeal(meal) }
    }

    func logMeal(
        _ meal: SavedMeal,
        amount: Double = 1,
        on date: Date,
        allowCheatDay: Bool = false
    ) async throws {
        try await perform(scope: .day(date)) {
            $0.logMeal(meal, amount: amount, on: date, allowCheatDay: allowCheatDay)
        }
    }

    func logImportedFood(
        _ food: Food,
        saveForReuse: Bool,
        on date: Date,
        allowCheatDay: Bool = false
    ) async throws -> Food {
        try await perform(scope: .day(date)) {
            try $0.logImportedFood(
                food,
                saveForReuse: saveForReuse,
                on: date,
                allowCheatDay: allowCheatDay
            )
        }
    }

    func logImportedMeal(_ meal: SavedMeal, saveForReuse: Bool = true, amount: Double = 1, on date: Date, allowCheatDay: Bool = false) async throws -> SavedMeal {
        try await perform(scope: .day(date)) {
            try $0.logImportedMeal(meal, saveForReuse: saveForReuse, amount: amount, on: date, allowCheatDay: allowCheatDay)
        }
    }

    func suggestedMeatClassification(name: String) async -> Food {
        let catalog = catalog
        return await Task.detached {
            FoodResolver(catalog: catalog).resolve(Food(
                sourceID: "preview", source: .custom, name: name, brand: nil, barcode: nil,
                nutrients: .zero, baseAmountGrams: 1, servingGrams: nil, servingDescription: nil))
        }.value
    }

    func suggestedMeatClassification(for food: Food) async -> Food {
        let catalog = catalog
        return await Task.detached {
            FoodResolver(catalog: catalog).suggestion(for: food)
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
        _ = try await createClassificationBackup(for: repository)
        try await perform(scope: .foods(Set(reviews.map { $0.food.id }))) {
            try $0.applyFoodResolutionReviews(reviews)
        }
    }

    func updateCorpusFoodMeatTags(originalFood: Food, overrides: FoodMeatOverrides) async throws {
        guard FoodCatalogIdentity(food: originalFood) != nil else {
            throw DiaryDatabaseError.invalidData("Only USDA and Open Food Facts foods can be corrected here.")
        }
        let repository = try await open()
        _ = try await createClassificationBackup(for: repository)
        try await perform(scope: .foods([originalFood.id])) {
            try $0.updateCorpusFoodMeatTags(originalFood: originalFood, overrides: overrides)
        }
    }

    private func createClassificationBackup(for repository: DiaryRepository) async throws -> URL {
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
        return backup
    }

    func logOneOffMeal(_ meal: SavedMeal, amount: Double = 1, on date: Date) async throws {
        try await perform(scope: .day(date)) { $0.logOneOffMeal(meal, amount: amount, on: date) }
    }

    func updateMealEntry(entryID: UUID, amount: Double, allowCheatDay: Bool = false) async throws {
        try await perform(scope: .entries([entryID])) {
            $0.updateMealEntry(entryID: entryID, amount: amount, allowCheatDay: allowCheatDay)
        }
    }

    func updateMealEntry(
        entryID: UUID,
        amount: Double,
        items: [MealItem],
        allowCheatDay: Bool = false
    ) async throws {
        try await perform(scope: .entries([entryID])) {
            $0.updateMealEntry(
                entryID: entryID,
                amount: amount,
                items: items,
                allowCheatDay: allowCheatDay
            )
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

    func weeklyReportDocument(referenceDate: Date = Date()) async throws -> DiaryDocument {
        let calendar = self.calendar
        let today = calendar.startOfDay(for: referenceDate)
        guard let end = calendar.date(byAdding: .day, value: 0, to: today),
              let start = calendar.date(byAdding: .day, value: -7, to: today) else {
            throw DiaryDatabaseError.invalidData("Could not calculate the local report week.")
        }
        return try await (try await open()).snapshot(scope: .range(start, end)).document
    }
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
