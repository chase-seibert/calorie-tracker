import AppIntents
import CryptoKit
import Foundation

private enum SiriQuickLogDiagnostics {
    private static let maximumLogBytes = 256 * 1024
    private static let fileName = "siri-quick-log.jsonl"

    static func record(_ event: String, properties: [String: String] = [:]) {
        let root = SharedDiaryStorage.defaultFileURL().deletingLastPathComponent()
            .appendingPathComponent("Diagnostics", isDirectory: true)
        let file = root.appendingPathComponent(fileName)
        let entry: [String: Any] = [
            "event": event,
            "occurred_at": ISO8601DateFormatter().string(from: Date()),
            "properties": properties.mapValues { String($0.prefix(256)) }
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
        handle.write(data + Data([0x0A]))
            try? manager.setAttributes(
                [.posixPermissions: 0o600, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: file.path
            )
        } catch {
            // Diagnostics must never interrupt Siri logging.
        }
    }

    static func selectionHash(_ selectionID: String) -> String {
        SHA256.hash(data: Data(selectionID.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

private enum SiriQuickLogInstrumentation {
    static func record(_ event: String, properties: [String: String] = [:]) {
        SiriQuickLogDiagnostics.record(event, properties: properties)
#if !WIDGET_EXTENSION
        Task {
            await AnalyticsService.shared.capture(
                type: "siri.quick_log.\(event)",
                properties: properties
            )
        }
#endif
    }
}

struct QuickLogSelectionEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Recent Food or Meal",
        numericFormat: "^\(placeholder: .int) recent foods or meals"
    )
    static let defaultQuery = RecentQuickLogSelectionQuery()

    let id: String
    let name: String
    let detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: LocalizedStringResource(stringLiteral: detail)
        )
    }

    init(selection: QuickLogSelection) {
        id = selection.id
        name = selection.title
        detail = selection.subtitle
    }
}

struct RecentQuickLogSelectionQuery: EntityStringQuery {
    func entities(for identifiers: [QuickLogSelectionEntity.ID]) async throws -> [QuickLogSelectionEntity] {
        let snapshot = try QuickLogRepository().snapshot()
        return identifiers.compactMap { identifier in
            snapshot.selection(id: identifier).map(QuickLogSelectionEntity.init)
        }
    }

    func suggestedEntities() async throws -> [QuickLogSelectionEntity] {
        try QuickLogRepository().snapshot()
            .recentSelections()
            .map(QuickLogSelectionEntity.init)
    }

    func entities(matching string: String) async throws -> [QuickLogSelectionEntity] {
        let results = try QuickLogRepository().snapshot()
            .recentSelections(matching: string)
            .map(QuickLogSelectionEntity.init)
        SiriQuickLogInstrumentation.record(
            "resolution_attempted",
            properties: [
                "query": String(string.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)),
                "result_count": String(results.count)
            ]
        )
        return results
    }
}

struct LogRecentItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Recent Food or Meal"
    static let description = IntentDescription(
        "Logs a food or saved meal from your Yum Chase recent items using its remembered quantity."
    )

    @Parameter(
        title: "Food or Meal",
        requestValueDialog: "What would you like to log?"
    )
    var item: QuickLogSelectionEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$item)")
    }

    init() {}

    init(item: QuickLogSelectionEntity) {
        self.item = item
    }

    func perform() async -> some IntentResult & ProvidesDialog {
        let selectionHash = SiriQuickLogDiagnostics.selectionHash(item.id)
        SiriQuickLogInstrumentation.record(
            "started",
            properties: ["selection_hash": selectionHash]
        )
        do {
            let result = try QuickLogRepository().log(selectionID: item.id)
            SiriQuickLogInstrumentation.record(
                "completed",
                properties: [
                    "selection_hash": selectionHash,
                    "logged_item_count": String(result.loggedItemCount)
                ]
            )
            return .result(dialog: IntentDialog("Logged \(result.title)."))
        } catch QuickLogError.unknownItem {
            SiriQuickLogInstrumentation.record(
                "failed",
                properties: ["selection_hash": selectionHash, "failure": "unknown_item"]
            )
            return .result(dialog: "That item is no longer in your Yum Chase recents.")
        } catch QuickLogError.loggingDisabled {
            SiriQuickLogInstrumentation.record(
                "failed",
                properties: ["selection_hash": selectionHash, "failure": "logging_disabled"]
            )
            return .result(dialog: "Food logging is disabled because today is a cheat day.")
        } catch {
            SiriQuickLogInstrumentation.record(
                "failed",
                properties: ["selection_hash": selectionHash, "failure": "database_or_unavailable"]
            )
            return .result(dialog: "I couldn’t update your Yum Chase diary. Open the app once and try again.")
        }
    }
}

struct CaloriesRemainingIntent: AppIntent {
    static let title: LocalizedStringResource = "Calories Left Today"
    static let description = IntentDescription(
        "Reports how many calories remain against your Yum Chase daily goal."
    )

    func perform() async -> some IntentResult & ProvidesDialog {
        do {
            let remaining = try QuickLogRepository().caloriesRemaining()
            if remaining >= 0 {
                return .result(
                    dialog: IntentDialog("You have \(remaining) calories left today.")
                )
            }
            return .result(
                dialog: IntentDialog("You’re \(-remaining) calories over your goal today.")
            )
        } catch QuickLogError.calorieGoalNotSet {
            return .result(dialog: "Set a daily calorie goal in Yum Chase first.")
        } catch {
            return .result(dialog: "I couldn’t read your Yum Chase diary. Open the app once and try again.")
        }
    }
}

#if !WIDGET_EXTENSION
struct VitaChaseAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogRecentItemIntent(),
            phrases: [
                "Log \(\.$item) in \(.applicationName)",
                "Add \(\.$item) to \(.applicationName)",
                "Log \(\.$item) with \(.applicationName)",
                "Use \(.applicationName) to log \(\.$item)"
            ],
            shortTitle: "Log Recent Item",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: CaloriesRemainingIntent(),
            phrases: [
                "How many calories do I have left in \(.applicationName)",
                "How many calories are left in \(.applicationName)",
                "Calories left in \(.applicationName)",
                "Ask \(.applicationName) how many calories I have left"
            ],
            shortTitle: "Calories Left",
            systemImageName: "gauge.with.dots.needle.67percent"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .orange }
}
#endif
