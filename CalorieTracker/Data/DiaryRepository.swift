import CryptoKit
import Darwin
import Foundation
import SQLite3

enum DiaryDatabaseError: LocalizedError {
    case unavailable(String)
    case unsupportedVersion(Int)
    case conversionRequired
    case alreadyInitialized
    case invalidData(String)
    case savedButRefreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail):
            "The diary could not be opened or saved. Your existing data was not replaced. \(detail)"
        case .unsupportedVersion(let version):
            "This diary uses database version \(version). Open it with a compatible app version."
        case .conversionRequired: "Your JSON diary needs the one-time SQLite conversion. It has not been changed."
        case .alreadyInitialized: "The destination already contains a diary. Choose a new destination."
        case .invalidData(let detail): "The diary data is invalid: \(detail)"
        case .savedButRefreshFailed(let detail): "Your change was saved, but the display could not refresh. Retry opening the diary; do not log the item again. \(detail)"
        }
    }
}

enum DiaryScope: Sendable {
    case all
    case library
    case day(Date)
    case range(Date, Date)
    case search(String)
    case entries(Set<UUID>)
    case food(String)
    case meal(UUID)
    case window(reference: Date, selectedDay: Date?)
}

/// One-time owner cutover. Only the foreground app calls this, before opening its repository.
/// The JSON is never modified; a closed, verified database is published without replacement.
enum DiaryJSONMigration {
    static func canonicalData(_ document: DiaryDocument) throws -> Data {
        var sorted = document
        sorted.entries.sort { $0.id.uuidString < $1.id.uuidString }
        sorted.dayStatuses.sort { $0.date < $1.date }
        sorted.alcoholEntries.sort { $0.date < $1.date }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(sorted)
    }

    static func exists(_ url: URL) throws -> Bool {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return true
        } catch CocoaError.fileReadNoSuchFile {
            return false
        }
    }

    /// Ordered sources are authoritative: never use an older fallback if the first is unreadable.
    @discardableResult
    static func convertIfNeeded(
        destination: URL, sources: [URL], backupDirectory: URL, calendar: Calendar = .current
    ) throws -> URL? {
        if try exists(destination) { return nil }
        var source: URL?
        for candidate in sources where try exists(candidate) {
            source = candidate
            break
        }
        guard let source else { return nil }
        for suffix in ["-wal", "-shm", "-journal"] {
            if try exists(URL(fileURLWithPath: destination.path + suffix)) {
                throw DiaryDatabaseError.invalidData("SQLite sidecar files already exist; conversion was stopped.")
            }
        }

        let manager = FileManager.default
        let bytes = try Data(contentsOf: source)
        let backup = backupDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try makePrivateDirectory(backup, intermediates: true)
        let jsonBackup = backup.appendingPathComponent("Diary.json")
        try writePrivate(bytes, to: jsonBackup)
        guard try Data(contentsOf: jsonBackup) == bytes else {
            throw DiaryDatabaseError.invalidData("The JSON backup could not be verified.")
        }

        let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        guard let version = root?["schemaVersion"] as? Int, (1...8).contains(version),
            root?["entries"] is [Any], root?["fixtureVersion"] == nil
        else { throw DiaryDatabaseError.invalidData("Unrecognized or unsupported JSON diary. Original and backup retained.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(DiaryDocument.self, from: bytes)
        try DiaryRepository.validateDocument(document)
        let expected = try canonicalData(document)

        // Stage on the destination volume so the final no-replace publication is atomic.
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent("JSONMigration-" + UUID().uuidString, isDirectory: true)
        try makePrivateDirectory(staging, intermediates: true)
        defer { try? manager.removeItem(at: staging) }
        let candidate = staging.appendingPathComponent("Verified.sqlite")
        try buildSnapshot(document, expected: expected, staging: staging, candidate: candidate, calendar: calendar)
        try verifySnapshot(candidate, expected: expected, calendar: calendar)
        // DELETE journaling and explicit close make the main file standalone. Apple's SQLite
        // can retain an unused SHM index; it contains no authoritative data and stays in staging.
        for suffix in ["-wal", "-journal"] {
            let sidecar = URL(fileURLWithPath: candidate.path + suffix)
            guard !(try exists(sidecar)) else {
                let attributes = try manager.attributesOfItem(atPath: sidecar.path)
                throw DiaryDatabaseError.invalidData("The converted snapshot still has a \(suffix) file (\(attributes[.size] ?? "unknown") bytes).")
            }
        }
        let databaseBytes = try Data(contentsOf: candidate)
        let manifest: [String: Any] = [
            "sourcePath": source.path, "sourceSHA256": sha256(bytes),
            "databaseSHA256": sha256(databaseBytes), "databaseSchemaVersion": DiaryRepository.schemaVersion,
            "entryCount": document.entries.count,
            "entryIngredientCount": document.entries.reduce(0) { $0 + ($1.mealItems?.count ?? 0) },
            "mealCount": document.meals.count, "customFoodCount": document.customFoods.count,
            "favoriteFoodCount": document.favorites.count, "favoriteMealCount": document.favoriteMealIDs.count,
            "dayStatusCount": document.dayStatuses.count, "alcoholDayCount": document.alcoholEntries.count,
            "roundTripVerified": true,
        ]
        try writePrivate(
            JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]),
            to: backup.appendingPathComponent("VerifiedConversion.json"))
        guard try Data(contentsOf: source) == bytes else {
            throw DiaryDatabaseError.invalidData("The JSON changed during conversion. Close other writers and retry.")
        }
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: candidate.path)
        let handle = try FileHandle(forWritingTo: candidate)
        defer { try? handle.close() }
        try handle.synchronize()
        // link() fails with EEXIST rather than overwriting a concurrently published database.
        guard link(candidate.path, destination.path) == 0 else {
            if errno == EEXIST { return nil }
            throw DiaryDatabaseError.unavailable("Could not publish the converted diary. Original and backup retained.")
        }
        return jsonBackup
    }

    private static func buildSnapshot(
        _ document: DiaryDocument, expected: Data, staging: URL, candidate: URL, calendar: Calendar
    ) throws {
        let repository = try DiaryRepository(fileURL: staging.appendingPathComponent("Working.sqlite"), calendar: calendar)
        try repository.importDocument(document)
        try repository.validate()
        guard try canonicalData(repository.snapshotSync().document) == expected else {
            throw DiaryDatabaseError.invalidData("Converted records did not match the JSON backup.")
        }
        try repository.backup(to: candidate)
    }

    private static func verifySnapshot(_ url: URL, expected: Data, calendar: Calendar) throws {
        let repository = try DiaryRepository(fileURL: url, calendar: calendar)
        try repository.validate()
        guard try canonicalData(repository.snapshotSync().document) == expected else {
            throw DiaryDatabaseError.invalidData("Published snapshot verification failed.")
        }
        try repository.closeStagingSnapshot()
    }

    private static func makePrivateDirectory(_ url: URL, intermediates: Bool) throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: intermediates, attributes: attributes)
    }

    private static func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct DiarySnapshot: Sendable {
    let document: DiaryDocument
    let revision: Int64
}

struct HealthSyncWork: Sendable {
    let day: Date
    let revision: Int64
    let knownEntries: [DiaryEntry]
    let desiredEntries: [DiaryEntry]
    let zeroNutrition: Bool
}

private struct DiarySettings: Codable, Equatable {
    var schemaVersion: Int
    var dailyCalorieGoal: Int?
    var trackingStartDate: Date?
    var favoriteItemOrder: [String]

    init(_ document: DiaryDocument) {
        schemaVersion = document.schemaVersion
        dailyCalorieGoal = document.dailyCalorieGoal
        trackingStartDate = document.trackingStartDate
        favoriteItemOrder = document.favoriteItemOrder
    }
}

/// Each process has its own connection and serial executor. SQLite coordinates processes.
/// No caller-owned document is ever written wholesale over another process's changes.
final class DiaryRepository: @unchecked Sendable {
    static let schemaVersion = 1
    let fileURL: URL
    private let calendar: Calendar
    private let queue = DispatchQueue(label: "com.cseibert.CalorieTracker.diary", qos: .userInitiated)
    private var db: OpaquePointer?

    init(fileURL: URL, calendar: Calendar = .current) throws {
        self.fileURL = fileURL
        self.calendar = calendar
        do { try queue.sync { try open() } } catch {
            if let db {
                sqlite3_close_v2(db)
                self.db = nil
            }
            throw error
        }
    }

    deinit { if let db { sqlite3_close_v2(db) } }

    private func open() throws {
        let manager = FileManager.default
        let existed = try DiaryJSONMigration.exists(fileURL)
        if fileURL == SharedDiaryStorage.defaultFileURL(), !SharedDiaryStorage.usesSimulatorFixture {
            guard SharedDiaryStorage.hasSharedContainer else {
                throw DiaryDatabaseError.unavailable("The shared App Group container is unavailable.")
            }
            #if WIDGET_EXTENSION
            guard existed else {
                throw DiaryDatabaseError.unavailable("Open VitaChase to prepare the diary first.")
            }
            #endif
            if !existed, try SharedDiaryStorage.legacyDiaryURLs.contains(where: { try DiaryJSONMigration.exists($0) }) {
                throw DiaryDatabaseError.conversionRequired
            }
        }
        if existed {
            let file = try FileHandle(forReadingFrom: fileURL)
            defer { try? file.close() }
            guard try file.read(upToCount: 16) == Data("SQLite format 3\0".utf8) else {
                throw DiaryDatabaseError.invalidData("The existing file is not a SQLite database.")
            }
        } else {
            try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        guard
            sqlite3_open_v2(fileURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
                == SQLITE_OK
        else {
            throw databaseError()
        }
        sqlite3_busy_timeout(db, 2_000)
        try execute("PRAGMA foreign_keys = ON")
        try transaction {
            let version = Int(try scalar("PRAGMA user_version"))
            if version == 0, !existed {
                try execute(Self.schema)
                try execute("PRAGMA user_version = 1")
                try execute("INSERT INTO store_state(id, revision, initialized) VALUES(1, 0, 0)")
                try putSettings(DiaryDocument())
            } else if version != Self.schemaVersion {
                throw DiaryDatabaseError.unsupportedVersion(version)
            }
        }
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = FULL")
        try execute("PRAGMA wal_autocheckpoint = 1000")
        try protectFiles()
    }

    private func protectFiles() throws {
        #if os(iOS)
            let manager = FileManager.default
            try manager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.deletingLastPathComponent().path)
            for path in [fileURL.path, fileURL.path + "-wal", fileURL.path + "-shm"]
            where manager.fileExists(atPath: path) {
                try manager.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path)
            }
        #endif
    }

    func snapshotSync(scope: DiaryScope = .all) throws -> DiarySnapshot {
        try queue.sync { try transaction(write: false) { try readSnapshot(scope: scope) } }
    }

    func snapshot(scope: DiaryScope = .all) async throws -> DiarySnapshot {
        try await enqueue { try self.transaction(write: false) { try self.readSnapshot(scope: scope) } }
    }

    func performSync<T: Sendable>(scope: DiaryScope, _ action: (DiaryEngine) throws -> T) throws -> T {
        try queue.sync { try mutate(scope: scope, action) }
    }

    func perform<T: Sendable>(scope: DiaryScope, _ action: @escaping @Sendable (DiaryEngine) throws -> T) async throws
        -> T
    {
        try await enqueue { try self.mutate(scope: scope, action) }
    }

    private func mutate<T>(scope: DiaryScope, _ action: (DiaryEngine) throws -> T) throws -> T {
        try transaction {
            let before = try readSnapshot(scope: scope).document
            let engine = DiaryEngine(document: before, calendar: calendar)
            let result = try action(engine)
            try applyChanges(from: before, to: engine.document)
            if engine.clearsPersonalData {
                try execute("DELETE FROM quick_log_receipt")
                try execute("UPDATE store_state SET finalized_through = NULL WHERE id = 1")
            }
            if let receipt = result as? QuickLogResult {
                try execute(
                    "INSERT OR REPLACE INTO quick_log_receipt(id, title, selection_id, logged_at) VALUES(1, ?, ?, ?)",
                    [
                        .text(receipt.title), .text(receipt.selectionID ?? ""), .real(Date().timeIntervalSince1970),
                    ])
            }
            return result
        }
    }

    /// Imports only into a new, uninitialized store; migration calls this on a staging database.
    func importDocument(_ document: DiaryDocument) throws {
        try Self.validateDocument(document)
        try queue.sync {
            try transaction {
                guard try scalar("SELECT initialized FROM store_state WHERE id = 1") == 0 else {
                    throw DiaryDatabaseError.alreadyInitialized
                }
                try applyChanges(from: DiaryDocument(), to: document)
                try execute("UPDATE store_state SET initialized = 1 WHERE id = 1")
            }
        }
    }

    /// Finalize only newly elapsed days. A global goal edit intentionally uses an all-history scope.
    func prepareSync(referenceDate: Date) throws {
        try queue.sync { try prepare(referenceDate: referenceDate) }
    }

    func prepare(referenceDate: Date) async throws {
        try await enqueue { try self.prepare(referenceDate: referenceDate) }
    }

    private func prepare(referenceDate: Date) throws {
        try transaction {
            var base = try readSnapshot(scope: .library).document
            let today = calendar.startOfDay(for: referenceDate)
            if base.trackingStartDate == nil {
                let earliest = try rows(
                    "SELECT min(day) AS day FROM (SELECT day FROM diary_entries UNION ALL SELECT day FROM alcohol_entries UNION ALL SELECT day FROM day_statuses)"
                ).first?["day"]?.double
                base.trackingStartDate = earliest.map(Date.init(timeIntervalSince1970:)) ?? today
                try putSettings(base)
            }
            let last = try rows("SELECT finalized_through FROM store_state WHERE id = 1").first?["finalized_through"]?
                .double.map(Date.init(timeIntervalSince1970:))
            var cursor =
                last.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
                ?? base.trackingStartDate.map { calendar.startOfDay(for: $0) } ?? today
            guard cursor < today else { return }
            let before = try readSnapshot(scope: .range(cursor, today)).document
            let engine = DiaryEngine(document: before, calendar: calendar)
            while cursor < today {
                engine.finalizeDay(cursor)
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            try applyChanges(from: before, to: engine.document)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            try execute(
                "UPDATE store_state SET finalized_through = ? WHERE id = 1", [.real(yesterday.timeIntervalSince1970)])
        }
    }

    private func readSnapshot(scope: DiaryScope) throws -> DiarySnapshot {
        var document = DiaryDocument()
        guard let row = try rows("SELECT payload FROM diary_settings WHERE id = 1").first,
            try scalar("SELECT count(*) FROM store_state WHERE id=1") == 1
        else {
            throw DiaryDatabaseError.invalidData("Required diary settings are missing.")
        }
        do {
            let settings: DiarySettings = try decode(row)
            document.schemaVersion = settings.schemaVersion
            document.dailyCalorieGoal = settings.dailyCalorieGoal
            document.trackingStartDate = settings.trackingStartDate
            document.favoriteItemOrder = settings.favoriteItemOrder
        }
        document.customFoods = try objects("SELECT payload FROM personal_foods ORDER BY position")
        document.meals = try objects("SELECT payload FROM meals ORDER BY position")
        let mealItems = try rows("SELECT meal_id, payload FROM meal_ingredients ORDER BY meal_id, position")
        let groupedMeals = Dictionary(grouping: mealItems) { $0["meal_id"]?.string ?? "" }
        for index in document.meals.indices {
            document.meals[index].items = try (groupedMeals[document.meals[index].id.uuidString] ?? []).map {
                try decode($0)
            }
        }
        for row in try rows("SELECT kind, item_id, payload FROM favorites ORDER BY position") {
            let id = row["item_id"]?.string ?? ""
            if row["kind"]?.string == "food" {
                document.favorites.append(try decode(row))
            } else if let uuid = UUID(uuidString: id) {
                document.favoriteMealIDs.append(uuid)
            }
        }
        for row in try rows("SELECT food_id, payload FROM food_preferences") {
            document.rememberedQuantities[row["food_id"]!.string!] = try decode(row)
        }
        for row in try rows("SELECT food_id, name FROM food_names") {
            document.customFoodNames[row["food_id"]!.string!] = row["name"]!.string!
        }
        document.dayStatuses = try objects("SELECT payload FROM day_statuses ORDER BY day")
        document.alcoholEntries = try objects("SELECT payload FROM alcohol_entries ORDER BY day")

        let (predicate, bindings) = predicate(for: scope)
        document.entries = try objects("SELECT payload FROM diary_entries WHERE \(predicate) ORDER BY rowid", bindings)
        let ingredientRows = try rows(
            "SELECT entry_id, payload FROM entry_ingredients WHERE entry_id IN (SELECT id FROM diary_entries WHERE \(predicate)) ORDER BY entry_id, position",
            bindings)
        let grouped = Dictionary(grouping: ingredientRows) { $0["entry_id"]?.string ?? "" }
        for index in document.entries.indices {
            if let ingredients = grouped[document.entries[index].id.uuidString] {
                document.entries[index].mealItems = try ingredients.map { try decode($0) }
            }
        }
        return DiarySnapshot(document: document, revision: try scalar("SELECT revision FROM store_state WHERE id = 1"))
    }

    private func predicate(for scope: DiaryScope) -> (String, [Value]) {
        switch scope {
        case .all: return ("1", [])
        case .library: return ("0", [])
        case .search(let query):
            let escaped = query.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let match = Value.text("%" + escaped + "%")
            return (
                """
                id IN (SELECT id FROM diary_entries WHERE kind IS NULL
                  AND json_extract(payload, '$.mealItems') IS NULL
                  AND (json_extract(payload, '$.food.name') LIKE ? ESCAPE '\\'
                    OR json_extract(payload, '$.food.brand') LIKE ? ESCAPE '\\'
                    OR food_id IN (SELECT food_id FROM food_names WHERE name LIKE ? ESCAPE '\\'))
                  GROUP BY food_id HAVING logged_at = max(logged_at)
                  ORDER BY max(logged_at) DESC LIMIT 50)
                """, [match, match, match]
            )
        case .day(let day):
            let start = calendar.startOfDay(for: day)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return ("day >= ? AND day < ?", [.real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)])
        case .range(let start, let end):
            return ("day >= ? AND day < ?", [.real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)])
        case .entries(let ids):
            guard !ids.isEmpty else { return ("0", []) }
            // Include the whole affected day for ordering, break-apart and day-level rules.
            return (
                "day IN (SELECT day FROM diary_entries WHERE id IN (\(ids.map { _ in "?" }.joined(separator: ","))))",
                ids.sorted { $0.uuidString < $1.uuidString }.map { .text($0.uuidString) }
            )
        case .food(let id):
            return (
                "food_id = ? OR id IN (SELECT entry_id FROM entry_ingredients WHERE food_id = ?) OR meal_id IN (SELECT meal_id FROM meal_ingredients WHERE food_id = ?)",
                [.text(id), .text(id), .text(id)]
            )
        case .meal(let id): return ("meal_id = ?", [.text(id.uuidString)])
        case .window(let reference, let selected):
            let start = calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: reference))!
            let end = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: reference))!
            var predicate =
                "(day >= ? AND day < ?) OR id IN (SELECT id FROM diary_entries WHERE kind IS NULL GROUP BY item_key HAVING logged_at = max(logged_at) ORDER BY max(logged_at) DESC LIMIT 30)"
            var values: [Value] = [.real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)]
            if let selected {
                let (dayPredicate, dayValues) = self.predicate(for: .day(selected))
                predicate += " OR (\(dayPredicate))"
                values += dayValues
            }
            return (predicate, values)
        }
    }

    private func applyChanges(from old: DiaryDocument, to new: DiaryDocument) throws {
        let oldEntries = Dictionary(uniqueKeysWithValues: old.entries.map { ($0.id, $0) })
        let newEntries = Dictionary(uniqueKeysWithValues: new.entries.map { ($0.id, $0) })
        var dirtyDays = Set<Date>()
        let orderedIDs = old.entries.map(\.id) + new.entries.filter { oldEntries[$0.id] == nil }.map(\.id)
        for id in orderedIDs where oldEntries[id] != newEntries[id] {
            for entry in [oldEntries[id], newEntries[id]].compactMap({ $0 }) {
                try rememberHealthEntry(entry)
                dirtyDays.insert(calendar.startOfDay(for: entry.date))
            }
            if let entry = newEntries[id] {
                try putEntry(entry)
            } else {
                try execute("DELETE FROM diary_entries WHERE id = ?", [.text(id.uuidString)])
            }
        }
        try syncCollection(table: "personal_foods", old: old.customFoods, new: new.customFoods, key: { $0.id }) {
            food, index in
            try execute(
                "INSERT OR REPLACE INTO personal_foods(id, name, position, payload) VALUES(?, ?, ?, ?)",
                [.text(food.id), .text(food.name), .integer(Int64(index)), try encoded(food)])
        }
        try syncCollection(table: "meals", old: old.meals, new: new.meals, key: { $0.id.uuidString }) { meal, index in
            var header = meal
            header.items = []
            try execute(
                "INSERT INTO meals(id, name, position, payload) VALUES(?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name=excluded.name, position=excluded.position, payload=excluded.payload",
                [.text(meal.id.uuidString), .text(meal.name), .integer(Int64(index)), try encoded(header)])
            try execute("DELETE FROM meal_ingredients WHERE meal_id = ?", [.text(meal.id.uuidString)])
            for (position, item) in meal.items.enumerated() {
                try execute(
                    "INSERT INTO meal_ingredients(meal_id, position, food_id, payload) VALUES(?, ?, ?, ?)",
                    [.text(meal.id.uuidString), .integer(Int64(position)), .text(item.food.id), try encoded(item)])
            }
        }
        if old.favorites != new.favorites || old.favoriteMealIDs != new.favoriteMealIDs
            || old.favoriteItemOrder != new.favoriteItemOrder
        {
            try execute("DELETE FROM favorites")
            for (index, food) in new.favorites.enumerated() {
                try execute(
                    "INSERT INTO favorites(kind, item_id, position, payload) VALUES('food', ?, ?, ?)",
                    [.text(food.id), .integer(Int64(index)), try encoded(food)])
            }
            for (index, id) in new.favoriteMealIDs.enumerated() {
                try execute(
                    "INSERT INTO favorites(kind, item_id, position) VALUES('meal', ?, ?)",
                    [.text(id.uuidString), .integer(Int64(index))])
            }
        }
        for key in Set(old.rememberedQuantities.keys).union(new.rememberedQuantities.keys)
        where old.rememberedQuantities[key] != new.rememberedQuantities[key] {
            if let value = new.rememberedQuantities[key] {
                try execute(
                    "INSERT OR REPLACE INTO food_preferences(food_id, payload) VALUES(?, ?)",
                    [.text(key), try encoded(value)])
            } else {
                try execute("DELETE FROM food_preferences WHERE food_id = ?", [.text(key)])
            }
        }
        for key in Set(old.customFoodNames.keys).union(new.customFoodNames.keys)
        where old.customFoodNames[key] != new.customFoodNames[key] {
            if let name = new.customFoodNames[key] {
                try execute("INSERT OR REPLACE INTO food_names(food_id, name) VALUES(?, ?)", [.text(key), .text(name)])
            } else {
                try execute("DELETE FROM food_names WHERE food_id = ?", [.text(key)])
            }
        }
        for day in Set(old.dayStatuses.map(\.date)).union(new.dayStatuses.map(\.date)) {
            let before = old.dayStatuses.first { $0.date == day }
            let after = new.dayStatuses.first { $0.date == day }
            guard before != after else { continue }
            dirtyDays.insert(calendar.startOfDay(for: day))
            if let after {
                try execute(
                    "INSERT OR REPLACE INTO day_statuses(day, payload) VALUES(?, ?)",
                    [.real(day.timeIntervalSince1970), try encoded(after)])
            } else {
                try execute("DELETE FROM day_statuses WHERE day = ?", [.real(day.timeIntervalSince1970)])
            }
        }
        for day in Set(old.alcoholEntries.map(\.date)).union(new.alcoholEntries.map(\.date)) {
            let before = old.alcoholEntries.first { $0.date == day }
            let after = new.alcoholEntries.first { $0.date == day }
            guard before != after else { continue }
            dirtyDays.insert(calendar.startOfDay(for: day))
            for document in [old, new] {
                let engine = DiaryEngine(document: document, calendar: calendar)
                for entry in engine.healthEntries(on: day) { try rememberHealthEntry(entry) }
            }
            if let after {
                try execute(
                    "INSERT OR REPLACE INTO alcohol_entries(day, id, payload) VALUES(?, ?, ?)",
                    [.real(day.timeIntervalSince1970), .text(after.id.uuidString), try encoded(after)])
            } else {
                try execute("DELETE FROM alcohol_entries WHERE day = ?", [.real(day.timeIntervalSince1970)])
            }
        }
        if DiarySettings(old) != DiarySettings(new) { try putSettings(new) }
        try execute("UPDATE store_state SET revision = revision + 1, initialized = 1 WHERE id = 1")
        let revision = try scalar("SELECT revision FROM store_state WHERE id = 1")
        for day in dirtyDays {
            try execute(
                "INSERT OR REPLACE INTO health_sync_jobs(day, revision) VALUES(?, ?)",
                [.real(day.timeIntervalSince1970), .integer(revision)])
        }
    }

    private func putEntry(_ entry: DiaryEntry) throws {
        guard entry.amount.isFinite, entry.amount > 0,
            [entry.nutrients.calories, entry.nutrients.carbs, entry.nutrients.fat, entry.nutrients.protein].allSatisfy({
                $0.isFinite && $0 >= 0
            }),
            entry.nutrients.fiber.map({ $0.isFinite && $0 >= 0 }) ?? true
        else {
            throw DiaryDatabaseError.invalidData("An entry has an invalid quantity or nutrient value.")
        }
        var header = entry
        header.mealItems = entry.mealItems == nil ? nil : []
        let engine = DiaryEngine(
            document: {
                var d = DiaryDocument()
                d.entries = [entry]
                return d
            }(), calendar: calendar)
        let classification = engine.meatPresence(on: entry.date)
        try execute(
            """
            INSERT INTO diary_entries(id, day, logged_at, food_id, meal_id, item_key, display_order, kind,
              calories, carbs, fat, protein, fiber, processed_meat, red_meat, payload)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET day=excluded.day, logged_at=excluded.logged_at,
              food_id=excluded.food_id, meal_id=excluded.meal_id, item_key=excluded.item_key,
              display_order=excluded.display_order, kind=excluded.kind, calories=excluded.calories,
              carbs=excluded.carbs, fat=excluded.fat, protein=excluded.protein, fiber=excluded.fiber,
              processed_meat=excluded.processed_meat, red_meat=excluded.red_meat, payload=excluded.payload
            """,
            [
                .text(entry.id.uuidString), .real(calendar.startOfDay(for: entry.date).timeIntervalSince1970),
                .real(entry.loggedAt.timeIntervalSince1970),
                .text(entry.food.id), entry.savedMealID.map { .text($0.uuidString) } ?? .null,
                .text(entry.savedMealID.map { "meal:" + $0.uuidString } ?? "food:" + entry.food.id),
                entry.displayOrder.map { .integer(Int64($0)) } ?? .null, entry.kind.map { .text($0.rawValue) } ?? .null,
                .real(entry.nutrients.calories), .real(entry.nutrients.carbs), .real(entry.nutrients.fat),
                .real(entry.nutrients.protein),
                entry.nutrients.fiber.map(Value.real) ?? .null, .integer(classification.containsProcessedMeat ? 1 : 0),
                .integer(classification.containsRedMeat ? 1 : 0), try encoded(header),
            ])
        try execute("DELETE FROM entry_ingredients WHERE entry_id = ?", [.text(entry.id.uuidString)])
        for (index, item) in (entry.mealItems ?? []).enumerated() {
            guard item.amount.isFinite, item.amount > 0 else {
                throw DiaryDatabaseError.invalidData("An ingredient has an invalid amount.")
            }
            let grams = item.unit.grams(for: item.amount, food: item.food, portionID: item.portionID)
            try execute(
                "INSERT INTO entry_ingredients(entry_id, position, food_id, grams, payload) VALUES(?, ?, ?, ?, ?)",
                [
                    .text(entry.id.uuidString), .integer(Int64(index)), .text(item.food.id), .real(grams),
                    try encoded(item),
                ])
        }
    }

    private func putSettings(_ document: DiaryDocument) throws {
        try execute(
            "INSERT OR REPLACE INTO diary_settings(id, payload) VALUES(1, ?)", [try encoded(DiarySettings(document))])
    }

    private func rememberHealthEntry(_ entry: DiaryEntry) throws {
        try execute(
            "INSERT OR REPLACE INTO health_sample_entries(entry_id, day, payload) VALUES(?, ?, ?)",
            [
                .text(entry.id.uuidString), .real(calendar.startOfDay(for: entry.date).timeIntervalSince1970),
                try encoded(entry),
            ])
    }

    func nextHealthWork() async throws -> HealthSyncWork? {
        try await enqueue {
            try self.transaction(write: false) {
                guard let row = try self.rows("SELECT day, revision FROM health_sync_jobs ORDER BY day LIMIT 1").first,
                    let day = row["day"]?.double, let revision = row["revision"]?.int
                else { return nil }
                let date = Date(timeIntervalSince1970: day)
                let engine = DiaryEngine(
                    document: try self.readSnapshot(scope: .day(date)).document, calendar: self.calendar)
                let known: [DiaryEntry] = try self.objects(
                    "SELECT payload FROM health_sample_entries WHERE day = ?", [.real(day)])
                return HealthSyncWork(
                    day: date, revision: revision, knownEntries: known,
                    desiredEntries: engine.healthEntries(on: date),
                    zeroNutrition: engine.suppressesHealthNutrition(on: date))
            }
        }
    }

    func acknowledgeHealthWork(_ work: HealthSyncWork) async throws {
        try await enqueue {
            try self.transaction {
                let day = Value.real(work.day.timeIntervalSince1970)
                guard try self.scalar("SELECT revision FROM health_sync_jobs WHERE day = ?", [day]) == work.revision
                else { return }
                try self.execute("DELETE FROM health_sample_entries WHERE day = ?", [day])
                for entry in work.desiredEntries { try self.rememberHealthEntry(entry) }
                try self.execute(
                    "DELETE FROM health_sync_jobs WHERE day = ? AND revision = ?", [day, .integer(work.revision)])
            }
        }
    }

    func requestHealthReconciliation() async throws {
        try await enqueue {
            try self.transaction {
                try self.execute("UPDATE store_state SET revision = revision + 1 WHERE id = 1")
                try self.execute(
                    "INSERT OR REPLACE INTO health_sync_jobs(day, revision) SELECT day, (SELECT revision FROM store_state WHERE id=1) FROM (SELECT day FROM diary_entries UNION SELECT day FROM alcohol_entries UNION SELECT day FROM day_statuses UNION SELECT day FROM health_sample_entries)"
                )
            }
        }
    }

    func streak(referenceDate: Date) async throws -> StreakSummary {
        try await enqueue {
            try self.transaction(write: false) {
                let today = self.calendar.startOfDay(for: referenceDate)
                let tomorrow = self.calendar.date(byAdding: .day, value: 1, to: today)!
                let rows = try self.rows(
                    """
                    SELECT day, sum(calories) AS calories, sum(carbs) AS carbs, sum(fat) AS fat,
                      sum(protein) AS protein, sum(CASE WHEN kind IS NULL THEN 1 ELSE 0 END) AS food_count,
                      sum(coalesce(fiber, (SELECT sum(json_extract(i.payload, '$.food.nutrients.fiber')
                        * i.grams / max(json_extract(i.payload, '$.food.baseAmountGrams'), 0.01))
                        FROM entry_ingredients i WHERE i.entry_id = diary_entries.id), 0)) AS known_fiber
                    FROM diary_entries WHERE day < ? GROUP BY day
                    """,
                    [.real(tomorrow.timeIntervalSince1970)])
                // A stored midnight may be a different absolute time after travel. Match the
                // domain's current-calendar day semantics without decoding historical entries.
                var byDay: [Date: (nutrients: MacroNutrients, foodCount: Int64)] = [:]
                for row in rows {
                    let day = self.calendar.startOfDay(for: Date(timeIntervalSince1970: row["day"]!.double!))
                    let nutrients = MacroNutrients(calories: row["calories"]?.double ?? 0,
                        carbs: row["carbs"]?.double ?? 0, fat: row["fat"]?.double ?? 0, protein: row["protein"]?.double ?? 0,
                        fiber: row["known_fiber"]?.double ?? 0)
                    let previous = byDay[day] ?? (.zero, 0)
                    byDay[day] = (previous.nutrients + nutrients, previous.foodCount + (row["food_count"]?.int ?? 0))
                }
                let library = try self.readSnapshot(scope: .library).document
                let lowerBound = library.trackingStartDate.map { self.calendar.startOfDay(for: $0) } ?? today
                var cursor = today
                if (byDay[cursor]?.foodCount ?? 0) == 0 {
                    cursor = self.calendar.date(byAdding: .day, value: -1, to: cursor)!
                }
                var dates: [Date] = []
                var values: [MacroNutrients] = []
                while cursor >= lowerBound, let row = byDay[cursor], row.foodCount > 0 {
                    dates.append(cursor)
                    let alcohol =
                        library.alcoholEntries.first { self.calendar.isDate($0.date, inSameDayAs: cursor) }?.calories
                        ?? 0
                    values.append(
                        MacroNutrients(
                            calories: row.nutrients.calories + Double(alcohol),
                            carbs: row.nutrients.carbs, fat: row.nutrients.fat,
                            protein: row.nutrients.protein, fiber: row.nutrients.fiber))
                    cursor = self.calendar.date(byAdding: .day, value: -1, to: cursor)!
                }
                guard let first = dates.last, let last = dates.first else { return .empty }
                let end = self.calendar.date(byAdding: .day, value: 1, to: last)!
                let frequent = try self.rows(
                    "SELECT json_extract(payload, '$.food.name') AS name, count(*) AS count FROM diary_entries WHERE day >= ? AND day < ? AND kind IS NULL GROUP BY name ORDER BY count DESC, name COLLATE NOCASE LIMIT 5",
                    [.real(first.timeIntervalSince1970), .real(end.timeIntervalSince1970)]
                ).map {
                    FrequentFood(name: $0["name"]?.string ?? "", count: Int($0["count"]?.int ?? 0))
                }
                let total = values.reduce(.zero, +)
                return StreakSummary(
                    dates: dates, averageNutrients: total.scaled(by: 1 / Double(dates.count)),
                    minimumNutrients: MacroNutrients(
                        calories: values.map(\.calories).min()!, carbs: values.map(\.carbs).min()!,
                        fat: values.map(\.fat).min()!, protein: values.map(\.protein).min()!),
                    maximumNutrients: MacroNutrients(
                        calories: values.map(\.calories).max()!, carbs: values.map(\.carbs).max()!,
                        fat: values.map(\.fat).max()!, protein: values.map(\.protein).max()!), frequentFoods: frequent)
            }
        }
    }

    func receiptSync() throws -> QuickLogReceipt? {
        try queue.sync {
            guard let row = try rows("SELECT * FROM quick_log_receipt WHERE id=1").first,
                let stamp = row["logged_at"]?.double, Date().timeIntervalSince1970 - stamp < 600
            else { return nil }
            return QuickLogReceipt(
                selectionID: row["selection_id"]?.string ?? "", title: row["title"]?.string ?? "",
                loggedAt: Date(timeIntervalSince1970: stamp))
        }
    }

    /// SQLite's backup API includes committed WAL content and produces a standalone snapshot.
    func backup(to destination: URL) throws {
        try queue.sync {
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw DiaryDatabaseError.alreadyInitialized
            }
            var output: OpaquePointer?
            guard
                sqlite3_open_v2(destination.path, &output, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK
            else {
                if let output { sqlite3_close(output) }
                throw DiaryDatabaseError.unavailable("Could not create the backup.")
            }
            defer { sqlite3_close(output) }
            guard let backup = sqlite3_backup_init(output, "main", db, "main") else { throw databaseError() }
            let result = sqlite3_backup_step(backup, -1)
            let finish = sqlite3_backup_finish(backup)
            guard result == SQLITE_DONE, finish == SQLITE_OK else {
                throw DiaryDatabaseError.unavailable("Backup did not complete.")
            }
        }
    }

    func validate() throws {
        try queue.sync {
            guard try rows("PRAGMA integrity_check").first?.values.first?.string == "ok",
                try rows("PRAGMA foreign_key_check").isEmpty
            else {
                throw DiaryDatabaseError.invalidData("Database integrity check failed.")
            }
        }
    }

    /// Only for the migrator's private candidate, never for an active/shared repository.
    fileprivate func closeStagingSnapshot() throws {
        try queue.sync {
            guard try rows("PRAGMA journal_mode = DELETE").first?.values.first?.string == "delete" else {
                throw DiaryDatabaseError.invalidData("Could not seal the standalone conversion snapshot.")
            }
            guard sqlite3_close(db) == SQLITE_OK else { throw databaseError() }
            db = nil
        }
    }

    static func validateDocument(_ document: DiaryDocument) throws {
        func unique<T: Hashable>(_ keys: [T], _ label: String) throws {
            guard Set(keys).count == keys.count else { throw DiaryDatabaseError.invalidData("Duplicate \(label).") }
        }
        try unique(document.entries.map(\.id), "entry IDs")
        try unique(document.meals.map(\.id), "meal IDs")
        try unique(document.customFoods.map(\.id), "custom food IDs")
        try unique(document.favorites.map(\.id), "favorite food IDs")
        try unique(document.favoriteMealIDs, "favorite meal IDs")
        try unique(document.dayStatuses.map(\.date), "day statuses")
        try unique(document.alcoholEntries.map(\.date), "alcohol days")
        try unique(document.alcoholEntries.map(\.id), "alcohol IDs")
        for entry in document.entries {
            guard entry.date.timeIntervalSince1970.isFinite, entry.loggedAt.timeIntervalSince1970.isFinite else {
                throw DiaryDatabaseError.invalidData("Invalid entry date.")
            }
        }
    }

    private func syncCollection<T: Equatable>(
        table: String, old: [T], new: [T], key: (T) -> String, put: (T, Int) throws -> Void
    ) throws {
        let oldByID = Dictionary(
            uniqueKeysWithValues: old.enumerated().map { (key($0.element), ($0.offset, $0.element)) })
        let newIDs = Set(new.map(key))
        for id in oldByID.keys where !newIDs.contains(id) {
            try execute("DELETE FROM \(table) WHERE id = ?", [.text(id)])
        }
        for (index, value) in new.enumerated() {
            if let previous = oldByID[key(value)], previous.0 == index, previous.1 == value { continue }
            try put(value, index)
        }
    }

    private func enqueue<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try body() }) }
        }
    }

    private func transaction<T>(write: Bool = true, _ body: () throws -> T) throws -> T {
        try execute(write ? "BEGIN IMMEDIATE" : "BEGIN")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private enum Value {
        case text(String)
        case real(Double)
        case integer(Int64)
        case null
        var string: String? { if case .text(let value) = self { value } else { nil } }
        var double: Double? {
            switch self {
            case .real(let value): value
            case .integer(let value): Double(value)
            default: nil
            }
        }
        var int: Int64? { if case .integer(let value) = self { value } else { nil } }
    }
    private typealias Row = [String: Value]

    private func encoded<T: Encodable>(_ value: T) throws -> Value {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return .text(String(decoding: try encoder.encode(value), as: UTF8.self))
    }

    private func decode<T: Decodable>(_ row: Row) throws -> T {
        guard let text = row["payload"]?.string else { throw DiaryDatabaseError.invalidData("Missing record payload.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(T.self, from: Data(text.utf8))
    }

    private func objects<T: Decodable>(_ sql: String, _ bindings: [Value] = []) throws -> [T] {
        try rows(sql, bindings).map { try decode($0) }
    }

    private func scalar(_ sql: String, _ bindings: [Value] = []) throws -> Int64 {
        try rows(sql, bindings).first?.values.first?.int ?? 0
    }

    private func execute(_ sql: String, _ bindings: [Value] = []) throws {
        if bindings.isEmpty {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw databaseError() }
        } else {
            _ = try rows(sql, bindings)
        }
    }

    private func rows(_ sql: String, _ bindings: [Value] = []) throws -> [Row] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let text):
                result = sqlite3_bind_text(
                    statement, index, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .real(let number): result = sqlite3_bind_double(statement, index, number)
            case .integer(let number): result = sqlite3_bind_int64(statement, index, number)
            case .null: result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw databaseError() }
        }
        var output: [Row] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return output }
            guard result == SQLITE_ROW else { throw databaseError() }
            var row: Row = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: row[name] = .integer(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT: row[name] = .real(sqlite3_column_double(statement, index))
                case SQLITE_TEXT: row[name] = .text(String(cString: sqlite3_column_text(statement, index)))
                default: row[name] = .null
                }
            }
            output.append(row)
        }
    }

    private func databaseError() -> DiaryDatabaseError {
        .unavailable(db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite connection unavailable.")
    }

    private static let schema = """
        CREATE TABLE store_state(id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER NOT NULL, initialized INTEGER NOT NULL, finalized_through REAL);
        CREATE TABLE diary_settings(id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL);
        CREATE TABLE personal_foods(id TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL, payload TEXT NOT NULL);
        CREATE TABLE meals(id TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL, payload TEXT NOT NULL);
        CREATE TABLE meal_ingredients(meal_id TEXT NOT NULL REFERENCES meals(id) ON DELETE CASCADE, position INTEGER NOT NULL, food_id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(meal_id, position));
        CREATE INDEX meal_ingredient_food ON meal_ingredients(food_id);
        CREATE TABLE diary_entries(id TEXT PRIMARY KEY, day REAL NOT NULL, logged_at REAL NOT NULL, food_id TEXT NOT NULL, meal_id TEXT, item_key TEXT NOT NULL, display_order INTEGER, kind TEXT, calories REAL NOT NULL, carbs REAL NOT NULL, fat REAL NOT NULL, protein REAL NOT NULL, fiber REAL, processed_meat INTEGER NOT NULL, red_meat INTEGER NOT NULL, payload TEXT NOT NULL);
        CREATE INDEX diary_day ON diary_entries(day, display_order, logged_at DESC);
        CREATE INDEX diary_recent ON diary_entries(logged_at DESC);
        CREATE INDEX diary_item ON diary_entries(item_key, logged_at DESC);
        CREATE INDEX diary_food ON diary_entries(food_id);
        CREATE INDEX diary_meal ON diary_entries(meal_id);
        CREATE TABLE entry_ingredients(entry_id TEXT NOT NULL REFERENCES diary_entries(id) ON DELETE CASCADE, position INTEGER NOT NULL, food_id TEXT NOT NULL, grams REAL NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(entry_id, position));
        CREATE INDEX entry_ingredient_food ON entry_ingredients(food_id);
        CREATE TABLE favorites(kind TEXT NOT NULL CHECK(kind IN ('food','meal')), item_id TEXT NOT NULL, position INTEGER NOT NULL, payload TEXT, PRIMARY KEY(kind,item_id));
        CREATE TABLE food_preferences(food_id TEXT PRIMARY KEY, payload TEXT NOT NULL);
        CREATE TABLE food_names(food_id TEXT PRIMARY KEY, name TEXT NOT NULL);
        CREATE TABLE day_statuses(day REAL PRIMARY KEY, payload TEXT NOT NULL);
        CREATE TABLE alcohol_entries(day REAL PRIMARY KEY, id TEXT NOT NULL UNIQUE, payload TEXT NOT NULL);
        CREATE TABLE quick_log_receipt(id INTEGER PRIMARY KEY CHECK(id=1), title TEXT NOT NULL, selection_id TEXT NOT NULL, logged_at REAL NOT NULL);
        CREATE TABLE health_sync_jobs(day REAL PRIMARY KEY, revision INTEGER NOT NULL);
        CREATE TABLE health_sample_entries(entry_id TEXT NOT NULL, day REAL NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(entry_id, day));
        CREATE INDEX health_entry_day ON health_sample_entries(day);
        """
}
