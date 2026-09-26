@preconcurrency import EventKit
import Combine
import Foundation

struct SnackReminderList: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let account: String
}

struct ExistingSnackReminder: Sendable {
    let title: String
    let url: URL?
}

enum SnackRemindersError: LocalizedError, Sendable {
    case accessDenied, listUnavailable, fetchFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied: "Allow Reminders access for Yum Chase in iPhone Settings, then try again."
        case .listUnavailable: "That Reminders list is no longer available or writable. Choose another list; nothing was added."
        case .fetchFailed: "Couldn't check this list for existing reminders. Nothing was added. Try again."
        }
    }
}

@MainActor
protocol SnackRemindersClient {
    var hasAccess: Bool { get }
    func requestAccess() async throws
    func writableLists() -> [SnackReminderList]
    func incompleteReminders(in listID: String) async throws -> [ExistingSnackReminder]
    func save(_ snacks: [SnackSuggestion], to listID: String) throws
}

@MainActor
final class EventKitSnackRemindersClient: SnackRemindersClient {
    private let store = EKEventStore()

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    func requestAccess() async throws {
        if hasAccess { return }
        guard EKEventStore.authorizationStatus(for: .reminder) == .notDetermined,
              try await store.requestFullAccessToReminders() else {
            throw SnackRemindersError.accessDenied
        }
    }

    func writableLists() -> [SnackReminderList] {
        guard hasAccess else { return [] }
        return store.calendars(for: .reminder).filter(\.allowsContentModifications).map {
            SnackReminderList(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title)
        }.sorted { ($0.title, $0.account, $0.id) < ($1.title, $1.account, $1.id) }
    }

    func incompleteReminders(in listID: String) async throws -> [ExistingSnackReminder] {
        let calendar = try writableCalendar(id: listID)
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: [calendar]
        )
        return try await withCheckedThrowingContinuation { continuation in
            Self.fetchRemindersNonisolated(store: store, predicate: predicate) { result in
                Task { @MainActor in
                    continuation.resume(with: result)
                }
            }
        }
    }

    /// EventKit invokes this callback on its own search queue. Keep the
    /// callback nonisolated, then hop back before resuming the caller.
    nonisolated private static func fetchRemindersNonisolated(
        store: EKEventStore,
        predicate: NSPredicate,
        completion: @escaping @Sendable (Result<[ExistingSnackReminder], SnackRemindersError>) -> Void
    ) {
        store.fetchReminders(matching: predicate) { reminders in
            guard let reminders else {
                completion(.failure(.fetchFailed))
                return
            }
            completion(.success(reminders.map {
                ExistingSnackReminder(title: $0.title ?? "", url: $0.url)
            }))
        }
    }

    func save(_ snacks: [SnackSuggestion], to listID: String) throws {
        let calendar = try writableCalendar(id: listID)
        do {
            for snack in snacks {
                let reminder = EKReminder(eventStore: store)
                reminder.calendar = calendar
                reminder.title = snack.name
                reminder.url = snack.reminderURL
                // No alarms, dates, diary data, or private focus-area preferences are exported.
                try store.save(reminder, commit: false)
            }
            try store.commit()
        } catch {
            // Discard unsaved changes so a retry cannot commit an earlier partial batch.
            store.reset()
            throw error
        }
    }

    private func writableCalendar(id: String) throws -> EKCalendar {
        guard hasAccess else { throw SnackRemindersError.accessDenied }
        guard let calendar = store.calendar(withIdentifier: id),
              calendar.allowedEntityTypes.contains(.reminder), calendar.allowsContentModifications else {
            throw SnackRemindersError.listUnavailable
        }
        return calendar
    }
}

@MainActor
final class SnackRemindersStore: ObservableObject {
    @Published private(set) var selectedList: SnackReminderList?
    @Published private(set) var lists: [SnackReminderList] = []
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?

    private static let listPreferenceKey = "snacks.reminders.list"
    private let client: any SnackRemindersClient
    private let defaults: UserDefaults

    init(client: any SnackRemindersClient = EventKitSnackRemindersClient(), defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.listPreferenceKey) {
            selectedList = try? JSONDecoder().decode(SnackReminderList.self, from: data)
        }
    }

    /// Called only after an explicit Choose/Change List tap. Never writes reminders.
    func prepareListChoice() async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        errorMessage = nil
        statusMessage = nil
        defer { isBusy = false }
        do {
            try await client.requestAccess()
            loadLists()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func choose(_ list: SnackReminderList) {
        guard !isBusy, lists.contains(where: { $0.id == list.id }) else { return }
        persist(list)
        statusMessage = nil
    }

    /// Refreshes a remembered list's name and permissions, without requesting access.
    func refreshLists() {
        guard !isBusy else { return }
        loadLists()
    }

    private func loadLists() {
        lists = client.writableLists()
        if let selectedList, let current = lists.first(where: { $0.id == selectedList.id }) {
            persist(current)
        }
        // Keep an unavailable choice so we can explain it, never silently switch destinations.
    }

    func clearError() { errorMessage = nil }

    /// Returns true only after the batch commits, or all requested snacks already exist.
    func add(_ snacks: [SnackSuggestion]) async -> Bool {
        guard !isBusy, !snacks.isEmpty else { return false }
        isBusy = true
        errorMessage = nil
        statusMessage = nil
        defer { isBusy = false }
        do {
            try await client.requestAccess()
            loadLists()
            guard let selectedList, lists.contains(where: { $0.id == selectedList.id }) else {
                throw SnackRemindersError.listUnavailable
            }
            let existing = try await client.incompleteReminders(in: selectedList.id)
            var titles = Set(existing.map { Self.normalizedTitle($0.title) })
            var urls = Set(existing.compactMap(\.url))
            let additions = snacks.filter { snack in
                let title = Self.normalizedTitle(snack.name)
                guard !titles.contains(title), !urls.contains(snack.reminderURL) else { return false }
                titles.insert(title)
                urls.insert(snack.reminderURL)
                return true
            }
            if !additions.isEmpty { try client.save(additions, to: selectedList.id) }
            let skipped = Set(snacks.map(\.id)).count - additions.count
            let result = additions.isEmpty
                ? "These snacks are already on \(selectedList.title)."
                : "Added \(additions.count) to \(selectedList.title)."
            statusMessage = result + (skipped > 0 && !additions.isEmpty ? " \(skipped) already on the list." : "")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func persist(_ list: SnackReminderList) {
        selectedList = list
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: Self.listPreferenceKey)
        }
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
