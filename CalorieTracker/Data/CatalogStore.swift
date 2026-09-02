import CryptoKit
import Foundation
import SQLite3

final class CatalogStore: @unchecked Sendable {
    private var database: OpaquePointer?
    private let lock = NSLock()
    let catalogVersion: String?

    init(url: URL? = Bundle.main.url(forResource: "FoodCatalog", withExtension: "sqlite3")) {
        catalogVersion = url.flatMap { Self.contentFingerprint(at: $0) }
        guard let url else { return }
        if sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            sqlite3_close(database)
            database = nil
        }
    }

    deinit {
        sqlite3_close(database)
    }

    var isAvailable: Bool { database != nil }

    private static func contentFingerprint(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data)
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func search(_ query: String, source: FoodSource, limit: Int = 50) -> [Food] {
        let terms = query
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(8)
            .map { "\($0)*" }
            .joined(separator: " ")
        guard !terms.isEmpty else { return popular(source: source, limit: limit) }

        let sql = """
            SELECT f.source_id, f.source, f.name, f.brand, f.barcode,
                   f.calories, f.carbs, f.fat, f.protein, f.fiber, f.base_grams,
                   f.serving_grams, f.serving_description, f.portions_json,
                   f.contains_processed_meat, f.contains_red_meat
            FROM foods_fts
            JOIN foods f ON f.rowid = foods_fts.rowid
            WHERE foods_fts MATCH ? AND f.source = ?
            ORDER BY
                CASE
                    WHEN lower(f.name) = lower(?) THEN 0
                    WHEN lower(f.name) LIKE lower(?) || ',%' THEN 1
                    WHEN lower(f.name) LIKE lower(?) || '%' THEN 2
                    ELSE 3
                END,
                bm25(foods_fts, 8.0, 3.0),
                length(f.name),
                f.rank DESC
            LIMIT ?
            """
        return queryFoods(sql: sql) { statement in
            bind(terms, at: 1, to: statement)
            bind(source.rawValue, at: 2, to: statement)
            bind(query, at: 3, to: statement)
            bind(query, at: 4, to: statement)
            bind(query, at: 5, to: statement)
            sqlite3_bind_int(statement, 6, Int32(limit))
        }
    }

    func searchAll(_ query: String, limit: Int = 50) -> [Food] {
        let terms = query
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(8)
            .map { "\($0)*" }
            .joined(separator: " ")
        guard !terms.isEmpty else { return [] }

        let sql = """
            SELECT f.source_id, f.source, f.name, f.brand, f.barcode,
                   f.calories, f.carbs, f.fat, f.protein, f.fiber, f.base_grams,
                   f.serving_grams, f.serving_description, f.portions_json,
                   f.contains_processed_meat, f.contains_red_meat
            FROM foods_fts
            JOIN foods f ON f.rowid = foods_fts.rowid
            WHERE foods_fts MATCH ?
            ORDER BY
                CASE
                    WHEN lower(f.name) = lower(?) THEN 0
                    WHEN lower(f.name) LIKE lower(?) || ',%' THEN 1
                    WHEN lower(f.name) LIKE lower(?) || '%' THEN 2
                    ELSE 3
                END,
                bm25(foods_fts, 8.0, 3.0),
                length(f.name),
                f.rank DESC
            LIMIT ?
            """
        return queryFoods(sql: sql) { statement in
            bind(terms, at: 1, to: statement)
            bind(query, at: 2, to: statement)
            bind(query, at: 3, to: statement)
            bind(query, at: 4, to: statement)
            sqlite3_bind_int(statement, 5, Int32(limit))
        }
    }

    func popular(source: FoodSource, limit: Int = 50) -> [Food] {
        let sql = """
            SELECT source_id, source, name, brand, barcode, calories, carbs,
                   fat, protein, fiber, base_grams, serving_grams, serving_description, portions_json,
                   contains_processed_meat, contains_red_meat
            FROM foods WHERE source = ? ORDER BY rank DESC, name LIMIT ?
            """
        return queryFoods(sql: sql) { statement in
            bind(source.rawValue, at: 1, to: statement)
            sqlite3_bind_int(statement, 2, Int32(limit))
        }
    }

    func food(barcode: String) -> Food? {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        let sql = """
            SELECT source_id, source, name, brand, barcode, calories, carbs,
                   fat, protein, fiber, base_grams, serving_grams, serving_description, portions_json,
                   contains_processed_meat, contains_red_meat
            FROM foods WHERE barcode = ? ORDER BY CASE source WHEN 'off' THEN 0 ELSE 1 END, rank DESC LIMIT 1
            """
        return queryFoods(sql: sql) { statement in
            bind(digits, at: 1, to: statement)
        }.first
    }

    func food(sourceID: String, source: FoodSource) -> Food? {
        queryFoods(sql: """
            SELECT source_id, source, name, brand, barcode, calories, carbs, fat, protein, fiber,
                   base_grams, serving_grams, serving_description, portions_json,
                   contains_processed_meat, contains_red_meat
            FROM foods WHERE source_id = ? AND source = ? LIMIT 1
            """) {
            bind(sourceID, at: 1, to: $0)
            bind(source.rawValue, at: 2, to: $0)
        }.first
    }

    func count(source: FoodSource) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let database else { return 0 }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT count(*) FROM foods WHERE source = ?", -1, &statement, nil) == SQLITE_OK,
              let statement else { return 0 }
        bind(source.rawValue, at: 1, to: statement)
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
    }

    func meatClassification(sourceID: String, source: FoodSource) -> MeatClassification? {
        lock.lock()
        defer { lock.unlock() }
        guard let database else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = """
            SELECT contains_processed_meat, contains_red_meat
            FROM foods WHERE source = ? AND source_id = ? LIMIT 1
            """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        bind(source.rawValue, at: 1, to: statement)
        bind(sourceID, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return MeatClassification(
            containsProcessedMeat: sqlite3_column_int(statement, 0) != 0,
            containsRedMeat: sqlite3_column_int(statement, 1) != 0
        )
    }

    func fiber(sourceID: String, source: FoodSource) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let database else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT fiber FROM foods WHERE source = ? AND source_id = ? LIMIT 1"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        bind(source.rawValue, at: 1, to: statement)
        bind(sourceID, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, 0)
    }

    private func queryFoods(sql: String, bindValues: (OpaquePointer) -> Void) -> [Food] {
        lock.lock()
        defer { lock.unlock() }
        guard let database else { return [] }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        bindValues(statement)
        var result: [Food] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let sourceID = text(statement, 0),
                  let sourceRaw = text(statement, 1),
                  let source = FoodSource(rawValue: sourceRaw),
                  let name = text(statement, 2) else { continue }
            result.append(Food(
                sourceID: sourceID,
                source: source,
                name: name,
                brand: text(statement, 3),
                barcode: text(statement, 4),
                nutrients: MacroNutrients(
                    calories: sqlite3_column_double(statement, 5),
                    carbs: sqlite3_column_double(statement, 6),
                    fat: sqlite3_column_double(statement, 7),
                    protein: sqlite3_column_double(statement, 8),
                    fiber: sqlite3_column_type(statement, 9) == SQLITE_NULL
                        ? nil
                        : sqlite3_column_double(statement, 9)
                ),
                baseAmountGrams: sqlite3_column_double(statement, 10),
                servingGrams: sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 11),
                servingDescription: text(statement, 12),
                portions: decodePortions(text(statement, 13)),
                containsProcessedMeat: sqlite3_column_int(statement, 14) != 0,
                containsRedMeat: sqlite3_column_int(statement, 15) != 0
            ))
        }
        return result
    }
}

private func decodePortions(_ json: String?) -> [FoodPortion]? {
    guard let json, let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode([FoodPortion].self, from: data)
}

private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    sqlite3_bind_text(statement, index, value, -1, transient)
}

private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
    guard let pointer = sqlite3_column_text(statement, index) else { return nil }
    let value = String(cString: pointer)
    return value.isEmpty ? nil : value
}
