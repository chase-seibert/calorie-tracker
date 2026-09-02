import AppIntents
import Foundation

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
        try QuickLogRepository().snapshot()
            .recentSelections(matching: string)
            .map(QuickLogSelectionEntity.init)
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
        do {
            let result = try QuickLogRepository().log(selectionID: item.id)
            return .result(dialog: IntentDialog("Logged \(result.title)."))
        } catch QuickLogError.unknownItem {
            return .result(dialog: "That item is no longer in your Yum Chase recents.")
        } catch QuickLogError.loggingDisabled {
            return .result(dialog: "Food logging is disabled because today is a cheat day.")
        } catch {
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
