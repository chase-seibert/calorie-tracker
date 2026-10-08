import CryptoKit
import Foundation
import SQLite3

struct SearchEvaluationFixture: Decodable {
    let schemaVersion: Int
    let datasetVersion: String
    let catalogFingerprint: String
    let rankingRuleVersion: String
    let queries: [SearchEvaluationQuery]
}

struct SearchEvaluationQuery: Decodable {
    let query: String
    let rationale: String
    let expectedTargets: [SearchEvaluationTarget]
    let matchingSavedMealNames: [String]?
}

struct SearchEvaluationTarget: Decodable {
    let itemID: String
    let label: String
    let relevance: Int
    let desiredMaxRank: Int
}

/// Uses the exact storage implementation linked into the app and extensions.
@main
struct DiaryTool {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(message: message) }
    }

    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            switch args.first {
            case "convert":
                guard args.count == 3 else { throw Failure(message: usage) }
                try convert(source: URL(fileURLWithPath: args[1]), destination: URL(fileURLWithPath: args[2]))
            case "validate":
                guard args.count == 2, FileManager.default.fileExists(atPath: args[1]) else {
                    throw Failure(message: usage)
                }
                let repository = try DiaryRepository(fileURL: URL(fileURLWithPath: args[1]))
                try repository.validate()
                let document = try repository.snapshotSync().document
                try DiaryRepository.validateDocument(document)
                print(
                    "Valid: \(document.entries.count) entries, \(document.meals.count) meals, \(document.customFoods.count) personal foods."
                )
            case "self-test":
                try await selfTest()
            case "benchmark":
                try await benchmark()
            case "search-eval":
                guard args.count <= 2 else { throw Failure(message: usage) }
                try searchEvaluation(fixtureURL: URL(fileURLWithPath: args.count == 2
                    ? args[1]
                    : "data/search-eval/relevance-v1.json"))
            default: throw Failure(message: usage)
            }
        } catch {
            FileHandle.standardError.write(Data(("Diary tool: \(error.localizedDescription)\n").utf8))
            exit(1)
        }
    }

    static let usage =
        "Usage: diary-tool convert INPUT.json OUTPUT.sqlite | validate INPUT.sqlite | self-test | benchmark | search-eval [FIXTURE.json]"

    static func searchEvaluation(fixtureURL: URL) throws {
        let fixture = try JSONDecoder().decode(SearchEvaluationFixture.self, from: Data(contentsOf: fixtureURL))
        try require(fixture.schemaVersion == 1, "Unsupported search evaluation fixture schema.")
        try require(!fixture.queries.isEmpty, "Search evaluation fixture contains no queries.")

        let catalogURL = URL(fileURLWithPath: "CalorieTracker/Resources/FoodCatalog.sqlite3")
        let catalog = CatalogStore(url: catalogURL)
        try require(catalog.isAvailable, "Bundled food catalog is unavailable.")
        let actualFingerprint = catalog.catalogVersion ?? "unknown"
        let cases = fixture.queries.map { query in
            var document = DiaryDocument()
            document.meals = (query.matchingSavedMealNames ?? []).enumerated().map { index, name in
                SavedMeal(
                    id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                    name: name,
                    items: []
                )
            }
            let results = DiaryEngine(document: document, catalog: catalog).searchItems(
                query.query,
                catalogFoods: catalog.searchAll(query.query, limit: 50),
                limit: 50
            )
            let targetRanks = query.expectedTargets.map { target in
                let rank = results.firstIndex { item in
                    if case let .food(food) = item { return food.id == target.itemID }
                    return false
                }.map { $0 + 1 }
                return [
                    "itemID": target.itemID,
                    "label": target.label,
                    "relevance": target.relevance,
                    "desiredMaxRank": target.desiredMaxRank,
                    "actualRank": rank as Any? ?? NSNull(),
                    "reciprocalRank": rank.map { 1.0 / Double($0) } as Any? ?? NSNull(),
                    "withinDesiredRank": rank.map { $0 <= target.desiredMaxRank } as Any? ?? NSNull(),
                ] as [String: Any]
            }
            let foundRanks = targetRanks.compactMap { $0["actualRank"] as? Int }
            let bestRank = foundRanks.min()
            return (
                query: query.query,
                rationale: query.rationale,
                targets: targetRanks,
                bestRank: bestRank,
                hitAtFive: bestRank.map { $0 <= 5 } ?? false,
                targetMet: query.expectedTargets.contains { target in
                    results.firstIndex { item in
                        if case let .food(food) = item { return food.id == target.itemID }
                        return false
                    }.map { $0 + 1 <= target.desiredMaxRank } ?? false
                },
                results: results.prefix(10).enumerated().map { index, food in
                    switch food {
                    case let .food(value):
                        return ["rank": index + 1, "itemID": value.id, "name": value.name, "source": value.source.rawValue] as [String: Any]
                    case let .meal(value):
                        return ["rank": index + 1, "itemID": "meal:\(value.id.uuidString)", "name": value.name, "source": "synthetic_saved_meal"] as [String: Any]
                    }
                }
            )
        }
        let reciprocalRanks = cases.compactMap { $0.bestRank.map { 1.0 / Double($0) } }
        let report: [String: Any] = [
            "schemaVersion": fixture.schemaVersion,
            "datasetVersion": fixture.datasetVersion,
            "rankingRuleVersion": catalog.activeRankingVersion.rawValue,
            "fixtureRankingRuleVersion": fixture.rankingRuleVersion,
            "fixtureCatalogFingerprint": fixture.catalogFingerprint,
            "actualCatalogFingerprint": actualFingerprint,
            "catalogFingerprintMatches": fixture.catalogFingerprint == actualFingerprint,
            "scope": "bundled catalog plus only explicit synthetic saved meals in the fixture; no diary, favorites, or analytics",
            "queryCount": cases.count,
            "meanReciprocalRank": reciprocalRanks.isEmpty ? NSNull() : reciprocalRanks.reduce(0, +) / Double(reciprocalRanks.count),
            "hitRateAtFive": Double(cases.filter(\.hitAtFive).count) / Double(cases.count),
            "targetRate": Double(cases.filter(\.targetMet).count) / Double(cases.count),
            "queries": cases.map { [
                "query": $0.query,
                "rationale": $0.rationale,
                "targets": $0.targets,
                "bestRelevantRank": $0.bestRank as Any? ?? NSNull(),
                "reciprocalRank": $0.bestRank.map { 1.0 / Double($0) } as Any? ?? NSNull(),
                "hitAtFive": $0.hitAtFive,
                "targetMet": $0.targetMet,
                "topResults": $0.results,
            ] as [String: Any] }
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func encode(_ document: DiaryDocument) throws -> Data {
        try DiaryJSONMigration.canonicalData(document)
    }

    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DiaryTool-" + UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        return directory
    }

    static func convert(source: URL, destination: URL) throws {
        let manager = FileManager.default
        let manifest = destination.appendingPathExtension("manifest.json")
        try require(
            !manager.fileExists(atPath: destination.path) && !manager.fileExists(atPath: manifest.path),
            "Destination or manifest already exists; no files were replaced.")
        let data = try Data(contentsOf: source)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document: DiaryDocument
        if root?["fixtureVersion"] != nil {
            document = try decoder.decode(DiaryFixture.self, from: data).document
        } else {
            try require(
                root?["entries"] != nil && root?["schemaVersion"] != nil, "Not a recognized diary JSON document.")
            document = try decoder.decode(DiaryDocument.self, from: data)
        }
        try require((1...8).contains(document.schemaVersion), "Unsupported JSON schema version.")
        try DiaryRepository.validateDocument(document)
        let directory = try temporaryDirectory()
        defer { try? manager.removeItem(at: directory) }
        let repository = try DiaryRepository(fileURL: directory.appendingPathComponent("staging.sqlite"))
        try repository.importDocument(document)
        try repository.validate()
        try require(
            encode(document) == encode(repository.snapshotSync().document),
            "Round-trip verification failed. No converted database was published.")
        // Do not call prepare: conversion must not change historical records or add day statuses.
        try repository.backup(to: destination)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        let report: [String: Any] = [
            "sourceSHA256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            "databaseSHA256": SHA256.hash(data: try Data(contentsOf: destination)).map { String(format: "%02x", $0) }
                .joined(),
            "databaseSchemaVersion": DiaryRepository.schemaVersion,
            "entryCount": document.entries.count,
            "entryIngredientCount": document.entries.reduce(0) { $0 + ($1.mealItems?.count ?? 0) },
            "mealCount": document.meals.count,
            "customFoodCount": document.customFoods.count,
            "favoriteFoodCount": document.favorites.count,
            "favoriteMealCount": document.favoriteMealIDs.count,
            "alcoholDayCount": document.alcoholEntries.count,
            "dayStatusCount": document.dayStatuses.count,
            "roundTripVerified": true,
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: manifest, options: [.withoutOverwriting])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifest.path)
        print("Converted and verified \(document.entries.count) entries and \(document.meals.count) meals.")
        print("Source JSON unchanged. Database: \(destination.path)")
        print("Checksum/count manifest: \(manifest.path)")
    }

    static func food(_ name: String = "Test food") -> Food {
        Food(
            sourceID: name, source: .custom, name: name, brand: nil, barcode: nil,
            nutrients: MacroNutrients(calories: 100, carbs: 10, fat: 3, protein: 5),
            baseAmountGrams: 100, servingGrams: 100, servingDescription: "serving",
            containsProcessedMeat: name == "Bacon", containsRedMeat: false)
    }

    static func entry(_ food: Food, on day: Date, index: Int = 0) -> DiaryEntry {
        DiaryEntry(
            id: UUID(), date: day, food: food, amount: 1, unit: .serving,
            nutrients: food.nutrients, loggedAt: day.addingTimeInterval(Double(index + 1)), displayOrder: index)
    }

    static func rawSQL(_ sql: String, at url: URL) throws {
        var db: OpaquePointer?
        try require(sqlite3_open(url.path, &db) == SQLITE_OK, "Could not open test connection.")
        defer { sqlite3_close(db) }
        try require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "Test SQL failed.")
    }

    static func selfTest() async throws {
        try migrationSelfTest()
        try foodResolutionSelfTest()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let today = Calendar.current.startOfDay(for: Date())
        let bacon = food("Bacon")
        let item = MealItem(id: UUID(), food: bacon, amount: 0.5, unit: .serving)
        let meal = SavedMeal(id: UUID(), name: "Soup", items: [item], origin: .imported)
        var initial = DiaryDocument()
        initial.dailyCalorieGoal = 2000
        initial.customFoods = [bacon, food()]
        initial.favorites = [food(), bacon]
        initial.meals = [meal]
        initial.favoriteMealIDs = [meal.id]
        initial.favoriteItemOrder = ["meal:" + meal.id.uuidString, "food:" + bacon.id, "food:" + food().id]
        initial.customFoodNames[bacon.id] = "My bacon"
        initial.rememberedQuantities[bacon.id] = QuantityPreference(amount: 20, unit: .grams)
        let url = directory.appendingPathComponent("test.sqlite")
        let repository = try DiaryRepository(fileURL: url)
        try repository.importDocument(initial)
        try require(encode(initial) == encode(repository.snapshotSync().document), "Library/order round trip.")
        try repository.performSync(scope: .day(today)) { engine in
            engine.logOneOffMeal(meal, on: today)
        }
        let detached = try repository.snapshotSync().document.entries[0]
        var expectedItem = item
        expectedItem.food.name = "My bacon"
        try require(detached.savedMealID == nil && detached.mealItems == [expectedItem], "Detached snapshot lost.")
        try require(detached.nutrients.fiber == nil, "Unknown fiber became zero.")
        let engine = DiaryEngine(document: try repository.snapshotSync().document)
        try require(engine.meatPresence(on: today).containsProcessedMeat, "Ingredient bacon classification lost.")
        try repository.performSync(scope: .library) {
            $0.deleteMeal(meal)
            $0.deleteCustomFood(bacon)
        }
        try require(repository.snapshotSync().document.entries[0] == detached, "Deleting a template changed history.")
        print("PASS: library, IDs, order, snapshots, nullable fiber, ingredient classification, template deletion")

        let second = try DiaryRepository(fileURL: url)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                let connection = index.isMultiple(of: 2) ? repository : second
                group.addTask {
                    try await connection.perform(scope: .day(today)) {
                        $0.log(food(), amount: 1, unit: .serving, on: today)
                    }
                }
            }
            try await group.waitForAll()
        }
        try require(repository.snapshotSync().document.entries.count == 51, "Concurrent writers lost entries.")
        let before = try encode(repository.snapshotSync().document)
        do {
            try repository.performSync(scope: .day(today)) { engine in
                engine.document.entries.append(entry(food("valid"), on: today))
                var invalid = entry(food("invalid"), on: today)
                invalid.amount = -1
                engine.document.entries.append(invalid)
            }
            throw Failure(message: "Invalid write succeeded.")
        } catch is DiaryDatabaseError {}
        try require(before == encode(repository.snapshotSync().document), "Failed transaction changed the diary.")
        print("PASS: two-connection concurrent writes and transaction rollback")

        guard let oldWork = try await repository.nextHealthWork() else { throw Failure(message: "Missing health job.") }
        try repository.performSync(scope: .entries([detached.id])) { $0.delete(entryID: detached.id) }
        try await repository.acknowledgeHealthWork(oldWork)
        guard let newWork = try await repository.nextHealthWork() else {
            throw Failure(message: "Stale health acknowledgement removed new work.")
        }
        try require(newWork.revision > oldWork.revision, "Health revision did not advance.")
        try require(newWork.knownEntries.contains { $0.id == detached.id }, "Deleted Health sample identity lost.")
        try require(!newWork.desiredEntries.contains { $0.id == detached.id }, "Deleted entry still projected.")
        try await repository.acknowledgeHealthWork(newWork)
        let pending = try await repository.nextHealthWork()
        try require(pending == nil, "Acknowledged health work still pending.")
        print("PASS: durable deletion tombstones and revision-checked HealthKit acknowledgement")

        let backup = directory.appendingPathComponent("backup.sqlite")
        try repository.backup(to: backup)
        let restored = try DiaryRepository(fileURL: backup)
        try restored.validate()
        try require(
            encode(restored.snapshotSync().document) == encode(repository.snapshotSync().document),
            "WAL backup missing committed changes.")
        let corrupt = directory.appendingPathComponent("corrupt.sqlite")
        let bytes = Data("not a database".utf8)
        try bytes.write(to: corrupt)
        do {
            _ = try DiaryRepository(fileURL: corrupt)
            throw Failure(message: "Corrupt store opened.")
        } catch is DiaryDatabaseError {}
        try require(Data(contentsOf: corrupt) == bytes, "Corrupt source was overwritten.")
        let future = directory.appendingPathComponent("future.sqlite")
        try repository.backup(to: future)
        try rawSQL("PRAGMA user_version = 999", at: future)
        do {
            _ = try DiaryRepository(fileURL: future)
            throw Failure(message: "Future schema opened.")
        } catch DiaryDatabaseError.unsupportedVersion(999) {}
        print("PASS: SQLite WAL backup, corrupt-store protection, future-schema refusal")

        let quick = try repository.performSync(scope: .window(reference: today, selectedDay: nil)) {
            $0.logQuickSelection("food:" + food().id, on: today)
        }
        try require(
            quick != nil && repository.receiptSync()?.selectionID == "food:" + food().id,
            "Atomic quick-log receipt missing.")
        let oldDay = Calendar.current.date(byAdding: .year, value: -3, to: today)!
        try repository.performSync(scope: .day(oldDay)) {
            $0.log(food("Historic unique pear"), amount: 1, unit: .serving, on: oldDay)
        }
        let search = try await repository.snapshot(scope: .search("Historic unique"))
        try require(search.document.entries.count == 1, "Search lost older history.")
        print("PASS: quick-log receipt and historical search")
        try repository.validate()
        print("All storage self-tests passed.")
    }

    static func foodResolutionSelfTest() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = Calendar.current.startOfDay(for: Date())
        let url = directory.appendingPathComponent("resolution.sqlite")
        let catalog = CatalogStore(url: URL(fileURLWithPath: "CalorieTracker/Resources/FoodCatalog.sqlite3"))
        let repository = try DiaryRepository(fileURL: url, catalog: catalog)
        var bacon = food("Bacon")
        bacon.containsProcessedMeat = nil
        bacon.containsRedMeat = nil
        let item = MealItem(id: UUID(), food: bacon, amount: 1, unit: .serving)
        let meal = SavedMeal(id: UUID(), name: "Soup with bacon", items: [item], origin: .imported)
        let saved = try repository.performSync(scope: .day(day)) { try $0.logImportedMeal(meal, on: day) }
        let snapshot = try repository.snapshotSync().document
        try require(snapshot.entries[0].mealItems?[0].food.containsProcessedMeat == true, "Omitted bacon flag not resolved.")
        try require(saved.items[0].food.nutrients == bacon.nutrients, "Resolution changed nutrition.")
        // Assert persisted SQL columns, not just the decoded snapshot or presentation engine.
        try rawSQL("""
            CREATE TEMP TABLE verify_flags(value INTEGER CHECK(value = 1));
            INSERT INTO verify_flags SELECT processed_meat FROM diary_entries;
            INSERT INTO verify_flags SELECT json_extract(payload, '$.food.containsProcessedMeat') FROM entry_ingredients;
            """, at: url)
        let reopened = try DiaryRepository(fileURL: url, catalog: catalog)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        _ = try reopened.performSync(scope: .window(reference: nextDay, selectedDay: nil)) {
            $0.logQuickSelection("meal:" + saved.id.uuidString, on: nextDay)
        }
        try require(repository.snapshotSync().document.entries.count == 2, "Quick log failed after reopening SQLite.")
        let before = try encode(repository.snapshotSync().document)
        do {
            try repository.performSync(scope: .day(day)) { engine in
                _ = try engine.logImportedMeal(meal, on: day)
                throw Failure(message: "Simulated failed import")
            }
        } catch is Failure {}
        try require(before == encode(repository.snapshotSync().document), "Failed import left library or entry rows behind.")
        let id = snapshot.entries[0].id
        try repository.performSync(scope: .entries([id])) { engine in
            engine.updateMealEntry(entryID: id, amount: 1, items: [MealItem(
                id: UUID(), food: food("Beans"), amount: 1, unit: .serving)])
        }
        try rawSQL("""
            CREATE TEMP TABLE verify_edit(value INTEGER CHECK(value = 0));
            INSERT INTO verify_edit SELECT processed_meat FROM diary_entries WHERE id = '\(id.uuidString)';
            """, at: url)
        try repository.validate()
        print("PASS: food resolution, SQL chart/ingredient parity, quick logging, atomic import rollback, ingredient edits")

        let batchURL = directory.appendingPathComponent("batch.sqlite")
        let batchRepository = try DiaryRepository(fileURL: batchURL, catalog: catalog)
        var legacyBacon = food("Bacon")
        legacyBacon.containsProcessedMeat = false
        legacyBacon.containsRedMeat = false
        var legacyBeef = food("Beef")
        legacyBeef.containsProcessedMeat = false
        legacyBeef.containsRedMeat = false
        let legacyMeal = SavedMeal(id: UUID(), name: "Legacy mixed meal", items: [legacyBacon, legacyBeef].map {
            MealItem(id: UUID(), food: $0, amount: 1, unit: .serving)
        })
        let legacy = DiaryEngine(document: DiaryDocument())
        legacy.logOneOffMeal(legacyMeal, on: day)
        try batchRepository.importDocument(legacy.document)
        let reviews = DiaryEngine(document: legacy.document, catalog: catalog).foodResolutionReview()
        try require(reviews.count == 2, "Expected both batch classification suggestions.")
        try batchRepository.performSync(scope: .foods(Set(reviews.map { $0.food.id }))) {
            try $0.applyFoodResolutionReviews(reviews)
        }
        try rawSQL("""
            CREATE TEMP TABLE verify_batch(value INTEGER NOT NULL CHECK(value = 1));
            INSERT INTO verify_batch SELECT processed_meat FROM diary_entries;
            INSERT INTO verify_batch SELECT red_meat FROM diary_entries;
            INSERT INTO verify_batch SELECT json_extract(payload, '$.food.containsProcessedMeat')
              FROM entry_ingredients WHERE json_extract(payload, '$.food.name') = 'Bacon';
            INSERT INTO verify_batch SELECT json_extract(payload, '$.food.containsRedMeat')
              FROM entry_ingredients WHERE json_extract(payload, '$.food.name') = 'Beef';
            """, at: batchURL)
        try batchRepository.validate()
        print("PASS: Approve All keeps both SQL chart flags and ingredient classifications consistent")
    }

    static func migrationSelfTest() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = FileManager.default
        let source = directory.appendingPathComponent("Shared.json")
        let fallback = directory.appendingPathComponent("Legacy.json")
        let destination = directory.appendingPathComponent("Shared/Diary.sqlite")
        let backups = directory.appendingPathComponent("Backups")
        let today = Calendar.current.startOfDay(for: Date())
        let bacon = food("Bacon")
        let item = MealItem(id: UUID(), food: bacon, amount: 0.5, unit: .serving)
        let meal = SavedMeal(id: UUID(), name: "Soup", items: [item], origin: .imported)
        let engine = DiaryEngine(document: DiaryDocument())
        engine.logOneOffMeal(meal, on: today)
        var document = engine.document
        document.meals = [meal]
        document.favorites = [bacon]
        document.customFoods = [bacon]
        document.favoriteMealIDs = [meal.id]
        document.favoriteItemOrder = ["meal:" + meal.id.uuidString, "food:" + bacon.id]
        document.customFoodNames[bacon.id] = "My bacon"
        document.rememberedQuantities[bacon.id] = QuantityPreference(amount: 20, unit: .grams)
        document.dailyCalorieGoal = 2100
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(document)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Legacy JSON dates have second precision; compare the exact source records.
        let expected = try decoder.decode(DiaryDocument.self, from: bytes)
        try bytes.write(to: source)
        try encoder.encode(DiaryDocument()).write(to: fallback)
        let backup = try DiaryJSONMigration.convertIfNeeded(
            destination: destination, sources: [source, fallback], backupDirectory: backups)
        try require(backup != nil, "Migration did not run.")
        try require(Data(contentsOf: source) == bytes && Data(contentsOf: backup!) == bytes, "JSON or backup changed.")
        let converted = try DiaryRepository(fileURL: destination).snapshotSync().document
        try require(encode(converted) == encode(expected), "On-device migration lost data or used stale fallback.")
        let manifestURL = backup!.deletingLastPathComponent().appendingPathComponent("VerifiedConversion.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        try require(manifest["roundTripVerified"] as? Bool == true, "Migration verification manifest missing.")
        try require(manifest["entryIngredientCount"] as? Int == 1, "Ingredient count not preserved.")
        let sourceHash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try require(manifest["sourceSHA256"] as? String == sourceHash, "Migration source checksum mismatch.")
        let retry = try DiaryJSONMigration.convertIfNeeded(destination: destination, sources: [source], backupDirectory: backups)
        try require(retry == nil, "Relaunch reimported the diary.")
        try require(manager.contentsOfDirectory(atPath: backups.path).count == 1, "Relaunch made another backup.")

        let bad = directory.appendingPathComponent("Bad.json")
        let failedDestination = directory.appendingPathComponent("Failed.sqlite")
        for badBytes in [Data("not JSON".utf8), Data("{\"schemaVersion\":999,\"entries\":[]}".utf8)] {
            try badBytes.write(to: bad)
            var failed = false
            do {
                try DiaryJSONMigration.convertIfNeeded(
                    destination: failedDestination, sources: [bad, fallback], backupDirectory: backups)
            } catch { failed = true }
            try require(failed && !manager.fileExists(atPath: failedDestination.path), "Bad JSON published an empty diary.")
            try require(Data(contentsOf: bad) == badBytes, "Failed migration changed source JSON.")
        }
        var invalid = document
        invalid.entries.append(invalid.entries[0])
        try encoder.encode(invalid).write(to: bad)
        var rejectedDuplicate = false
        do {
            try DiaryJSONMigration.convertIfNeeded(destination: failedDestination, sources: [bad], backupDirectory: backups)
        } catch { rejectedDuplicate = true }
        try require(rejectedDuplicate && !manager.fileExists(atPath: failedDestination.path), "Duplicate IDs accepted.")
        // A leftover staging directory from process death is never mistaken for the live diary.
        try manager.createDirectory(at: directory.appendingPathComponent("JSONMigration-interrupted"), withIntermediateDirectories: true)
        try bytes.write(to: bad)
        try DiaryJSONMigration.convertIfNeeded(destination: failedDestination, sources: [bad], backupDirectory: backups)
        try require(encode(DiaryRepository(fileURL: failedDestination).snapshotSync().document) == encode(expected), "Retry failed.")
        let blockedBackup = directory.appendingPathComponent("NotADirectory")
        try Data("block backup".utf8).write(to: blockedBackup)
        let blockedDestination = directory.appendingPathComponent("Blocked.sqlite")
        var failedBackup = false
        do {
            try DiaryJSONMigration.convertIfNeeded(destination: blockedDestination, sources: [source], backupDirectory: blockedBackup)
        } catch { failedBackup = true }
        try require(failedBackup && !manager.fileExists(atPath: blockedDestination.path), "Backup failure published a database.")
        let missing = try DiaryJSONMigration.convertIfNeeded(
            destination: blockedDestination, sources: [directory.appendingPathComponent("Absent.json")], backupDirectory: backups)
        try require(missing == nil && !manager.fileExists(atPath: blockedDestination.path), "No-source migration wrote a database.")
        print("PASS: on-device migration, byte-identical backup, source priority, round trip, manifest, idempotency, failure/retry safety")
    }

    static func benchmark() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for years in [1, 3, 10] {
            var document = DiaryDocument()
            let foods = (0..<15).map { food("Food \($0)") }
            document.dailyCalorieGoal = 2000
            for offset in 0..<(365 * years) {
                let day = calendar.date(byAdding: .day, value: -offset, to: today)!
                document.entries += foods.enumerated().map { entry($0.element, on: day, index: $0.offset) }
            }
            let repository = try DiaryRepository(fileURL: directory.appendingPathComponent("\(years)y.sqlite"))
            var start = Date()
            try repository.importDocument(document)
            let importMS = Date().timeIntervalSince(start) * 1000
            try repository.prepareSync(referenceDate: today)
            start = Date()
            let snapshot = try await repository.snapshot(scope: .window(reference: today, selectedDay: nil))
            let readMS = Date().timeIntervalSince(start) * 1000
            start = Date()
            try await repository.perform(scope: .day(today)) { $0.log(foods[0], amount: 1, unit: .serving, on: today) }
            let writeMS = Date().timeIntervalSince(start) * 1000
            start = Date()
            let streak = try await repository.streak(referenceDate: today)
            let streakMS = Date().timeIntervalSince(start) * 1000
            try require(snapshot.document.entries.count <= 90 * 15 + 30, "Read window grows with full history.")
            try require(streak.dates.count == years * 365, "All-history streak lost.")
            print(
                String(
                    format: "%2dy  %5d entries  import %.0f ms  window %.1f ms (%d rows)  log %.1f ms  streak %.1f ms",
                    years, document.entries.count, importMS, readMS, snapshot.document.entries.count, writeMS, streakMS)
            )
        }
        print("Mac timings, not an iPhone performance guarantee. Window includes 90 days plus latest distinct items.")
    }
}
