import CryptoKit
import Foundation
import SwiftUI

enum AnalyticsAudience: String, Codable, Sendable {
    case debug
    case test
    case beta
    case production
}

struct AnalyticsConfiguration: Sendable {
    let baseURL: URL
    let appName: String
    let appVersion: String
    let appPlatform: String
    let audience: AnalyticsAudience
    let keyID: String
    let secret: String
    let namespace: String

    var fingerprint: String {
        let material = [
            baseURL.absoluteString,
            appName,
            appPlatform,
            audience.rawValue,
            keyID,
            secret
        ].joined(separator: "\n")
        return AnalyticsRequestSigner.payloadSHA256(Data(material.utf8))
    }

    static func load(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> AnalyticsConfiguration? {
        guard processInfo.environment["XCTestConfigurationFilePath"] == nil,
              processInfo.environment["CALORIE_TRACKER_UI_TEST_FIXTURE"] == nil else {
            return nil
        }

        var candidateURLs: [URL] = []
#if DEBUG
        if let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            candidateURLs.append(applicationSupport.appendingPathComponent("AnalyticsConfig.plist"))
        }
#endif
        if let bundledURL = bundle.url(forResource: "AnalyticsConfig", withExtension: "plist") {
            candidateURLs.append(bundledURL)
        }

        for url in candidateURLs {
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let values = plist as? [String: Any],
                  values["analyticsEnabled"] as? Bool != false,
                  let rawBaseURL = values["analyticsBaseUrl"] as? String,
                  let baseURL = URL(string: rawBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
                  baseURL.scheme == "https",
                  baseURL.host != nil,
                  let appName = values["appName"] as? String,
                  let keyID = values["analyticsKeyId"] as? String,
                  let secret = values["analyticsSecret"] as? String,
                  !secret.isEmpty,
                  (values["signatureVersion"] as? String) == "hmac-sha256-v1" else {
                continue
            }

            let namespace = baseURL.lastPathComponent
            guard namespace.range(of: "^[a-z0-9][a-z0-9-]{0,62}$", options: .regularExpression) != nil,
                  appName.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil,
                  keyID == namespace else {
                continue
            }

            let audience: AnalyticsAudience
            if let configuredAudience = values["audience"] as? String {
                guard let parsedAudience = AnalyticsAudience(rawValue: configuredAudience) else { continue }
                audience = parsedAudience
            } else {
#if DEBUG
                audience = .debug
#else
                audience = .production
#endif
            }

            return AnalyticsConfiguration(
                baseURL: baseURL,
                appName: appName,
                appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                appPlatform: values["appPlatform"] as? String ?? "iOS",
                audience: audience,
                keyID: keyID,
                secret: secret,
                namespace: namespace
            )
        }
        return nil
    }
}

struct AnalyticsDiagnosticsSnapshot: Sendable {
    let enabled: Bool
    let appName: String?
    let appVersion: String?
    let platform: String?
    let audience: String?
    let namespace: String?
    let keyID: String?
    let status: String
    let queuedEventCount: Int
    let preparedBatchCount: Int
    let oldestUnsentAge: TimeInterval?
    let latestBatchID: String?
    let retryAttempt: Int
    let nextRetryAt: Date?
    let redirectHost: String?
    let stopLogging: Bool
    let recentEvents: [AnalyticsDiagnosticEvent]

    var redactedSummary: String {
        [
            "Analytics: \(enabled ? "enabled" : "disabled")",
            "App: \(appName ?? "—") \(appVersion ?? "—") on \(platform ?? "—")",
            "Audience: \(audience ?? "—")",
            "Namespace: \(namespace ?? "—")",
            "Key ID: \(keyID ?? "—")",
            "Status: \(status)",
            "Queued events: \(queuedEventCount)",
            "Prepared batches: \(preparedBatchCount)",
            "Latest batch ID: \(latestBatchID ?? "—")",
            "Retry attempt: \(retryAttempt)",
            "Next retry: \(nextRetryAt?.formatted(.iso8601) ?? "—")",
            "Redirect host: \(redirectHost ?? "—")",
            "Stop logging: \(stopLogging)"
        ].joined(separator: "\n")
    }
}

struct AnalyticsDiagnosticEvent: Identifiable, Codable, Sendable {
    let id: String
    let type: String
    let occurredAt: Date
    var state: String
    var payload: AnalyticsDiagnosticPayload?

    var stateTitle: String {
        state.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct AnalyticsDiagnosticPayload: Codable, Sendable {
    let eventId: String
    let type: String
    let occurredAt: Date
    let audience: AnalyticsAudience
    let sessionId: String
    let properties: [String: String]

    var formattedJSON: String {
        let encoder = JSONEncoder.analytics
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "Payload unavailable"
        }
        return json
    }
}

actor AnalyticsService {
    static let shared = AnalyticsService()

    private static let retentionInterval: TimeInterval = 90 * 24 * 60 * 60
    private static let maximumEventsPerBatch = 500
    private static let maximumCompressedBytes = 1_048_576
    private static let maximumUncompressedBytes = 5_242_880
    private static let maximumRecentEvents = 100

    private let configuration: AnalyticsConfiguration?
    private let stateURL: URL?
    private let sessionID = UUID().uuidString
    private var state: AnalyticsStoredState
    private var isStarted = false
    private var isUploading = false
    private var didRecordAppLaunch = false
    private var retryTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    init(
        configuration: AnalyticsConfiguration? = AnalyticsConfiguration.load(),
        stateURL: URL? = AnalyticsService.defaultStateURL()
    ) {
        self.configuration = configuration
        self.stateURL = stateURL
        if let stateURL,
           let data = try? Data(contentsOf: stateURL),
           let storedState = try? JSONDecoder.analytics.decode(AnalyticsStoredState.self, from: data) {
            state = storedState
        } else {
            state = AnalyticsStoredState()
        }
        if let configuration {
            if let previousFingerprint = state.configurationFingerprint,
               previousFingerprint != configuration.fingerprint {
                state.preparedBatch = nil
                state.retryAttempt = 0
                state.nextRetryAt = nil
                state.redirectBaseURL = nil
                state.stopLogging = false
            }
            state.configurationFingerprint = configuration.fingerprint
        }
#if !DEBUG
        for index in state.recentEvents.indices {
            state.recentEvents[index].payload = nil
        }
#endif
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        pruneExpiredEvents()
        persistState()
        scheduleOrFlush(immediately: true)
    }

    func appBecameActive() {
        guard isStarted else {
            start()
            return
        }
        scheduleOrFlush(immediately: true)
    }

    func recordAppLaunch() {
        guard !didRecordAppLaunch else { return }
        didRecordAppLaunch = true
        capture(type: "app.launched")
    }

    func capture(type: String, properties: [String: String] = [:]) {
        guard let configuration, !state.stopLogging else { return }
        let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedType.isEmpty else { return }

        let event = AnalyticsEvent(
            eventId: UUID().uuidString,
            type: normalizedType,
            occurredAt: Date(),
            audience: configuration.audience,
            sessionId: sessionID,
            properties: properties.mapValues { String($0.prefix(256)) }
        )
#if DEBUG
        let diagnosticPayload = AnalyticsDiagnosticPayload(
            eventId: event.eventId,
            type: event.type,
            occurredAt: event.occurredAt,
            audience: event.audience,
            sessionId: event.sessionId,
            properties: event.properties
        )
#else
        let diagnosticPayload: AnalyticsDiagnosticPayload? = nil
#endif
        state.queuedEvents.append(event)
        state.recentEvents.append(AnalyticsDiagnosticEvent(
            id: event.eventId,
            type: event.type,
            occurredAt: event.occurredAt,
            state: "queued",
            payload: diagnosticPayload
        ))
        trimRecentEvents()
        pruneExpiredEvents()
        persistState()
        scheduleOrFlush()
    }

    func uploadNow() async {
        guard configuration != nil, !state.stopLogging else { return }
        retryTask?.cancel()
        retryTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        state.nextRetryAt = nil
        persistState()
        await flushIfNeeded(force: true)
    }

    func diagnosticsSnapshot() -> AnalyticsDiagnosticsSnapshot {
        let oldestAge = state.queuedEvents.map(\.occurredAt).min().map {
            max(0, Date().timeIntervalSince($0))
        }
        return AnalyticsDiagnosticsSnapshot(
            enabled: configuration != nil,
            appName: configuration?.appName,
            appVersion: configuration?.appVersion,
            platform: configuration?.appPlatform,
            audience: configuration?.audience.rawValue,
            namespace: configuration?.namespace,
            keyID: configuration?.keyID,
            status: statusDescription,
            queuedEventCount: state.queuedEvents.count,
            preparedBatchCount: state.preparedBatch == nil ? 0 : 1,
            oldestUnsentAge: oldestAge,
            latestBatchID: state.preparedBatch?.batchId,
            retryAttempt: state.retryAttempt,
            nextRetryAt: state.nextRetryAt,
            redirectHost: state.redirectBaseURL.flatMap(URL.init(string:))?.host,
            stopLogging: state.stopLogging,
            recentEvents: Array(state.recentEvents.suffix(50).reversed())
        )
    }

#if DEBUG
    func clearQueue() {
        retryTask?.cancel()
        retryTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        state.queuedEvents = []
        state.preparedBatch = nil
        state.retryAttempt = 0
        state.nextRetryAt = nil
        persistState()
    }
#endif

    private var statusDescription: String {
        if configuration == nil { return "disabled" }
        if state.stopLogging { return "stopped" }
        if isUploading { return "uploading" }
        if state.nextRetryAt != nil { return "retry scheduled" }
        if state.preparedBatch != nil { return "prepared" }
        if !state.queuedEvents.isEmpty { return "queued" }
        return "idle"
    }

    private func scheduleOrFlush(immediately: Bool = false) {
        guard configuration != nil, !state.stopLogging, !state.queuedEvents.isEmpty else { return }
        if let nextRetryAt = state.nextRetryAt, nextRetryAt > Date() {
            scheduleRetry(at: nextRetryAt)
        } else if immediately {
            Task { await flushIfNeeded(force: false) }
        } else {
            debounceTask?.cancel()
            debounceTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await self?.flushIfNeeded(force: false)
            }
        }
    }

    private func scheduleRetry(at date: Date) {
        retryTask?.cancel()
        let delay = max(0, date.timeIntervalSinceNow)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.flushIfNeeded(force: false)
        }
    }

    private func flushIfNeeded(force: Bool) async {
        guard let configuration,
              !state.stopLogging,
              !isUploading,
              !state.queuedEvents.isEmpty else { return }
        if !force, let nextRetryAt = state.nextRetryAt, nextRetryAt > Date() {
            scheduleRetry(at: nextRetryAt)
            return
        }

        isUploading = true
        defer { isUploading = false }

        if state.preparedBatch == nil {
            state.preparedBatch = prepareBatch(configuration: configuration)
            guard state.preparedBatch != nil else {
                persistState()
                return
            }
            if let eventIDs = state.preparedBatch?.eventIds {
                updateHistory(ids: Set(eventIDs), state: "prepared")
            }
            persistState()
        }
        guard let preparedBatch = state.preparedBatch else { return }
        updateHistory(ids: Set(preparedBatch.eventIds), state: "uploading")
        persistState()

        do {
            let result = try await upload(preparedBatch, configuration: configuration)
            applyServerRouting(from: result.envelope)

            if state.stopLogging {
                if result.isSuccess {
                    complete(preparedBatch)
                } else {
                    updateHistory(ids: Set(preparedBatch.eventIds), state: "stopped")
                }
                persistState()
            } else if result.isRetryable {
                scheduleRetry(serverDelay: result.retryAfter)
            } else if result.isSuccess {
                complete(preparedBatch)
                persistState()
                if !state.queuedEvents.isEmpty, !state.stopLogging {
                    Task { await flushIfNeeded(force: true) }
                }
            } else {
                drop(preparedBatch, reason: "rejected")
                persistState()
                if !state.queuedEvents.isEmpty, !state.stopLogging {
                    Task { await flushIfNeeded(force: true) }
                }
            }
        } catch {
            scheduleRetry(serverDelay: nil)
        }
    }

    private func prepareBatch(configuration: AnalyticsConfiguration) -> AnalyticsPreparedBatch? {
        guard let audience = state.queuedEvents.first?.audience else { return nil }
        var events = Array(
            state.queuedEvents.lazy
                .filter { $0.audience == audience }
                .prefix(Self.maximumEventsPerBatch)
        )
        while !events.isEmpty {
            let batchID = UUID().uuidString
            let payload = AnalyticsPayload(
                schemaVersion: 1,
                batchId: batchID,
                sentAt: Date(),
                app: AnalyticsApp(
                    name: configuration.appName,
                    version: configuration.appVersion,
                    platform: configuration.appPlatform
                ),
                events: events
            )
            guard let json = try? JSONEncoder.analytics.encode(payload) else { return nil }
            let gzipped = GzipEncoder.encode(json)
            if json.count <= Self.maximumUncompressedBytes,
               gzipped.count <= Self.maximumCompressedBytes {
                let payloadSHA = AnalyticsRequestSigner.payloadSHA256(gzipped)
                let signature = AnalyticsRequestSigner.signature(
                    namespace: configuration.namespace,
                    apiVersion: "v1",
                    batchID: batchID,
                    payloadSHA256: payloadSHA,
                    secret: configuration.secret
                )
                return AnalyticsPreparedBatch(
                    batchId: batchID,
                    eventIds: events.map(\.eventId),
                    gzippedPayload: gzipped,
                    payloadSHA256: payloadSHA,
                    signature: signature
                )
            }
            events.removeLast(max(1, events.count / 4))
        }
        return nil
    }

    private func upload(
        _ batch: AnalyticsPreparedBatch,
        configuration: AnalyticsConfiguration
    ) async throws -> AnalyticsUploadResult {
        let baseURL = state.redirectBaseURL.flatMap(URL.init(string:)) ?? configuration.baseURL
        let endpoint = baseURL.appendingPathComponent("v1").appendingPathComponent("events")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = batch.gzippedPayload
        request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(batch.batchId, forHTTPHeaderField: "X-App-Analytics-Batch-ID")
        request.setValue(batch.payloadSHA256, forHTTPHeaderField: "X-App-Analytics-Payload-SHA256")
        request.setValue(configuration.keyID, forHTTPHeaderField: "X-App-Analytics-Key-ID")
        request.setValue(batch.signature, forHTTPHeaderField: "X-App-Analytics-Signature")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let envelope = try? JSONDecoder.analytics.decode(AnalyticsResponseEnvelope.self, from: data)
        let retryAfter = max(
            envelope?.retryAfterSeconds ?? 0,
            Self.retryAfterSeconds(from: httpResponse.value(forHTTPHeaderField: "Retry-After")) ?? 0
        )
        let isSuccess = httpResponse.statusCode == 202 ||
            (httpResponse.statusCode == 200 && envelope?.duplicate == true)
        let isRetryable = httpResponse.statusCode == 429 ||
            (500...599).contains(httpResponse.statusCode) ||
            envelope?.action == "pause_uploads" ||
            envelope?.error?.code == "INGEST_PAUSED"
        return AnalyticsUploadResult(
            isSuccess: isSuccess,
            isRetryable: isRetryable,
            retryAfter: retryAfter > 0 ? retryAfter : nil,
            envelope: envelope
        )
    }

    private func applyServerRouting(from envelope: AnalyticsResponseEnvelope?) {
        guard let envelope else { return }
        if envelope.action == "stop_logging" {
            state.stopLogging = true
            retryTask?.cancel()
            retryTask = nil
            debounceTask?.cancel()
            debounceTask = nil
        } else if envelope.action == "redirect",
                  let redirect = envelope.redirectBaseUrl,
                  let url = URL(string: redirect),
                  url.scheme == "https",
                  url.host != nil {
            state.redirectBaseURL = url.absoluteString
        }
    }

    private func complete(_ batch: AnalyticsPreparedBatch) {
        let uploadedIDs = Set(batch.eventIds)
        state.queuedEvents.removeAll { uploadedIDs.contains($0.eventId) }
        updateHistory(ids: uploadedIDs, state: "uploaded")
        state.preparedBatch = nil
        state.retryAttempt = 0
        state.nextRetryAt = nil
        retryTask?.cancel()
        retryTask = nil
    }

    private func drop(_ batch: AnalyticsPreparedBatch, reason: String) {
        let droppedIDs = Set(batch.eventIds)
        state.queuedEvents.removeAll { droppedIDs.contains($0.eventId) }
        updateHistory(ids: droppedIDs, state: reason)
        state.preparedBatch = nil
        state.retryAttempt = 0
        state.nextRetryAt = nil
    }

    private func scheduleRetry(serverDelay: TimeInterval?) {
        if let eventIDs = state.preparedBatch?.eventIds {
            updateHistory(ids: Set(eventIDs), state: "retry_scheduled")
        }
        state.retryAttempt += 1
        let exponent = min(state.retryAttempt - 1, 20)
        let cappedDelay = min(86_400, 60 * pow(2, Double(exponent)))
        let jitteredDelay = max(60, Double.random(in: (cappedDelay * 0.5)...cappedDelay))
        let delay = max(jitteredDelay, serverDelay ?? 0)
        let retryDate = Date().addingTimeInterval(delay)
        state.nextRetryAt = retryDate
        persistState()
        scheduleRetry(at: retryDate)
    }

    private func pruneExpiredEvents() {
        let cutoff = Date().addingTimeInterval(-Self.retentionInterval)
        let expiredIDs = Set(state.queuedEvents.filter { $0.occurredAt < cutoff }.map(\.eventId))
        guard !expiredIDs.isEmpty else { return }
        state.queuedEvents.removeAll { expiredIDs.contains($0.eventId) }
        updateHistory(ids: expiredIDs, state: "expired")
        if let prepared = state.preparedBatch,
           !expiredIDs.isDisjoint(with: prepared.eventIds) {
            state.preparedBatch = nil
            state.retryAttempt = 0
            state.nextRetryAt = nil
        }
    }

    private func updateHistory(ids: Set<String>, state newState: String) {
        for index in state.recentEvents.indices where ids.contains(state.recentEvents[index].id) {
            state.recentEvents[index].state = newState
        }
        trimRecentEvents()
    }

    private func trimRecentEvents() {
        if state.recentEvents.count > Self.maximumRecentEvents {
            state.recentEvents.removeFirst(state.recentEvents.count - Self.maximumRecentEvents)
        }
    }

    private func persistState() {
        guard let stateURL,
              let data = try? JSONEncoder.analytics.encode(state) else { return }
        let directory = stateURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectory = directory
            try? mutableDirectory.setResourceValues(values)
            try data.write(to: stateURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: stateURL.path
            )
            var mutableStateURL = stateURL
            try? mutableStateURL.setResourceValues(values)
        } catch {
            // Analytics failures must never interrupt the app's primary workflows.
        }
    }

    private static func defaultStateURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CalorieTracker", isDirectory: true)
            .appendingPathComponent("Analytics", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    private static func retryAfterSeconds(from value: String?) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value) { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSinceNow) }
    }
}

enum AppAnalytics {
    static func capture(_ type: String, properties: [String: String] = [:]) {
        Task {
            await AnalyticsService.shared.capture(type: type, properties: properties)
        }
    }
}

enum FoodLogAnalytics {
    static func foodProperties(
        food: Food,
        method: String,
        mode: String,
        unit: LogUnit,
        isFavorite: Bool,
        catalogVersion: String? = nil,
        foodKind: String? = nil,
        portionID: String? = nil,
        defaultUnit: LogUnit? = nil,
        defaultPortionID: String? = nil,
        selectionRank: Int? = nil,
        query: String? = nil,
        groupID: String? = nil,
        savedForReuse: Bool? = nil
    ) -> [String: String] {
        let resolvedKind = foodKind ?? (food.source == .custom ? "custom" : "catalog")
        var properties = commonProperties(
            itemType: "food",
            foodKind: resolvedKind,
            method: method,
            mode: mode,
            unit: unit,
            isFavorite: isFavorite,
            selectionRank: selectionRank,
            query: query,
            groupID: groupID
        )
        properties["source"] = food.source.rawValue
        properties["has_brand"] = String(food.displayBrand != nil)
        properties["has_barcode"] = String(!(food.barcode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
        properties["has_portions"] = String(!food.availablePortions.isEmpty)
        if let portionID, !portionID.isEmpty {
            properties["portion_id"] = portionID
        }
        if let defaultUnit {
            properties["default_unit"] = defaultUnit.analyticsValue
            properties["unit_changed_from_default"] = String(
                defaultUnit != unit || defaultPortionID != portionID
            )
        }
        if let defaultPortionID, !defaultPortionID.isEmpty {
            properties["default_portion_id"] = defaultPortionID
        }

        if food.source == .custom {
            properties["local_item_id"] = food.sourceID
        } else {
            properties["source_id"] = food.sourceID
            if let catalogVersion, !catalogVersion.isEmpty {
                properties["catalog_version"] = catalogVersion
            }
        }
        if let savedForReuse {
            properties["saved_for_reuse"] = String(savedForReuse)
        }
        return properties
    }

    static func unitSelectionProperties(
        food: Food,
        operation: String,
        fromUnit: LogUnit,
        fromPortionID: String?,
        selectedUnit: LogUnit,
        selectedPortionID: String?,
        defaultUnit: LogUnit,
        defaultPortionID: String?
    ) -> [String: String] {
        var properties = [
            "item_type": "food",
            "food_kind": food.source == .custom ? "custom" : "catalog",
            "operation": operation,
            "from_unit": fromUnit.analyticsValue,
            "selected_unit": selectedUnit.analyticsValue,
            "default_unit": defaultUnit.analyticsValue,
            "selection_changed": String(
                fromUnit != selectedUnit || fromPortionID != selectedPortionID
            ),
            "changed_from_default": String(
                defaultUnit != selectedUnit || defaultPortionID != selectedPortionID
            )
        ]
        properties["source"] = food.source.rawValue
        if food.source == .custom {
            properties["local_item_id"] = food.sourceID
        } else {
            properties["source_id"] = food.sourceID
        }
        if let fromPortionID, !fromPortionID.isEmpty {
            properties["from_portion_id"] = fromPortionID
        }
        if let selectedPortionID, !selectedPortionID.isEmpty {
            properties["selected_portion_id"] = selectedPortionID
        }
        if let defaultPortionID, !defaultPortionID.isEmpty {
            properties["default_portion_id"] = defaultPortionID
        }
        return properties
    }

    static func mealProperties(
        meal: SavedMeal,
        method: String,
        mode: String,
        unit: LogUnit = .serving,
        isFavorite: Bool,
        foodKind: String = "saved_meal",
        includeLocalID: Bool = true,
        selectionRank: Int? = nil,
        query: String? = nil,
        groupID: String? = nil,
        savedForReuse: Bool? = nil
    ) -> [String: String] {
        var properties = commonProperties(
            itemType: "meal",
            foodKind: foodKind,
            method: method,
            mode: mode,
            unit: unit,
            isFavorite: isFavorite,
            selectionRank: selectionRank,
            query: query,
            groupID: groupID
        )
        properties["item_count"] = String(meal.items.count)
        if includeLocalID {
            properties["local_item_id"] = meal.id.uuidString
        }
        if let savedForReuse {
            properties["saved_for_reuse"] = String(savedForReuse)
        }
        return properties
    }

    private static func commonProperties(
        itemType: String,
        foodKind: String,
        method: String,
        mode: String,
        unit: LogUnit,
        isFavorite: Bool,
        selectionRank: Int?,
        query: String?,
        groupID: String?
    ) -> [String: String] {
        var properties = [
            "item_type": itemType,
            "food_kind": foodKind,
            "method": method,
            "mode": mode,
            "unit": unit.analyticsValue,
            "is_favorite": String(isFavorite)
        ]
        if let selectionRank, selectionRank > 0 {
            properties["selection_rank"] = String(selectionRank)
        }
        if let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines),
           !normalizedQuery.isEmpty {
            properties["query"] = String(normalizedQuery.prefix(200))
        }
        if let groupID, !groupID.isEmpty {
            properties["group_id"] = groupID
        }
        return properties
    }
}

private struct AnalyticsScreenModifier: ViewModifier {
    let screen: String
    let properties: [String: String]

    func body(content: Content) -> some View {
        content.onAppear {
            AppAnalytics.capture(
                "screen.viewed",
                properties: properties.merging(["screen": screen]) { current, _ in current }
            )
        }
    }
}

extension View {
    func analyticsScreen(_ screen: String, properties: [String: String] = [:]) -> some View {
        modifier(AnalyticsScreenModifier(screen: screen, properties: properties))
    }
}

extension LogUnit {
    var analyticsValue: String {
        switch self {
        case .grams: "grams"
        case .ounces: "ounces"
        case .serving: "serving"
        }
    }
}

extension HealthKitAuthorizationState {
    var analyticsValue: String {
        switch self {
        case .unavailable: "unavailable"
        case .notDetermined: "not_determined"
        case .denied: "denied"
        case .authorized: "authorized"
        }
    }
}

private struct AnalyticsStoredState: Codable, Sendable {
    var queuedEvents: [AnalyticsEvent] = []
    var preparedBatch: AnalyticsPreparedBatch?
    var retryAttempt = 0
    var nextRetryAt: Date?
    var redirectBaseURL: String?
    var stopLogging = false
    var recentEvents: [AnalyticsDiagnosticEvent] = []
    var configurationFingerprint: String?
}

private struct AnalyticsEvent: Codable, Sendable {
    let eventId: String
    let type: String
    let occurredAt: Date
    let audience: AnalyticsAudience
    let sessionId: String
    let properties: [String: String]
}

private struct AnalyticsPayload: Codable, Sendable {
    let schemaVersion: Int
    let batchId: String
    let sentAt: Date
    let app: AnalyticsApp
    let events: [AnalyticsEvent]
}

private struct AnalyticsApp: Codable, Sendable {
    let name: String
    let version: String
    let platform: String
}

private struct AnalyticsPreparedBatch: Codable, Sendable {
    let batchId: String
    let eventIds: [String]
    let gzippedPayload: Data
    let payloadSHA256: String
    let signature: String
}

private struct AnalyticsUploadResult: Sendable {
    let isSuccess: Bool
    let isRetryable: Bool
    let retryAfter: TimeInterval?
    let envelope: AnalyticsResponseEnvelope?
}

private struct AnalyticsResponseEnvelope: Codable, Sendable {
    let accepted: Bool?
    let duplicate: Bool?
    let action: String?
    let redirectBaseUrl: String?
    let retryAfterSeconds: TimeInterval?
    let error: AnalyticsResponseError?
}

private struct AnalyticsResponseError: Codable, Sendable {
    let code: String?
}

enum AnalyticsRequestSigner {
    static func payloadSHA256(_ payload: Data) -> String {
        hexString(SHA256.hash(data: payload))
    }

    static func signature(
        namespace: String,
        apiVersion: String,
        batchID: String,
        payloadSHA256: String,
        secret: String
    ) -> String {
        let signingText = [namespace, apiVersion, batchID, payloadSHA256].joined(separator: "\n")
        return hexString(HMAC<SHA256>.authenticationCode(
            for: Data(signingText.utf8),
            using: SymmetricKey(data: Data(secret.utf8))
        ))
    }
}

enum GzipEncoder {
    static func encode(_ data: Data) -> Data {
        var output = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff])
        let bytes = [UInt8](data)
        if bytes.isEmpty {
            output.append(contentsOf: [0x01, 0x00, 0x00, 0xff, 0xff])
        } else {
            var offset = 0
            while offset < bytes.count {
                let count = min(65_535, bytes.count - offset)
                let isFinal = offset + count == bytes.count
                let length = UInt16(count)
                let inverseLength = ~length
                output.append(isFinal ? 0x01 : 0x00)
                output.append(UInt8(length & 0xff))
                output.append(UInt8(length >> 8))
                output.append(UInt8(inverseLength & 0xff))
                output.append(UInt8(inverseLength >> 8))
                output.append(contentsOf: bytes[offset..<(offset + count)])
                offset += count
            }
        }
        appendLittleEndian(crc32(bytes), to: &output)
        appendLittleEndian(UInt32(truncatingIfNeeded: bytes.count), to: &output)
        return output
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (0xedb8_8320 & (0 &- (crc & 1)))
            }
        }
        return ~crc
    }

    private static func appendLittleEndian(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }
}

private extension JSONEncoder {
    static var analytics: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var analytics: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private func hexString<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
    bytes.map { String(format: "%02x", $0) }.joined()
}
