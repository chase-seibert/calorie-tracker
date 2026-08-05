@preconcurrency import HealthKit
import Combine
import Foundation

enum HealthKitAuthorizationState: Equatable {
    case unavailable
    case notDetermined
    case denied
    case authorized
}

@MainActor
final class HealthKitStore: ObservableObject {
    @Published private(set) var authorizationState: HealthKitAuthorizationState = .unavailable
    @Published private(set) var lastError: String?

    private let healthStore = HKHealthStore()
    private var pendingOperation: Task<Void, Never>?

    init() {
        refreshAuthorizationState()
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func refreshAuthorizationState() {
        guard isAvailable else {
            authorizationState = .unavailable
            return
        }

        let statuses = quantityTypes.map { healthStore.authorizationStatus(for: $0) }
        if statuses.allSatisfy({ $0 == .sharingAuthorized }) {
            authorizationState = .authorized
        } else if statuses.allSatisfy({ $0 == .sharingDenied }) {
            authorizationState = .denied
        } else {
            authorizationState = .notDetermined
        }
    }

    func requestAuthorizationAndSync(entries: [DiaryEntry]) async {
        guard isAvailable else { return }

        let granted = await requestAuthorization()
        guard granted else { return }

        sync(entries: entries)
    }

    @discardableResult
    func sync(entries: [DiaryEntry]) -> Task<Void, Never> {
        enqueue { [weak self] in
            guard let self else { return }
            for entry in entries {
                await replaceSamples(for: entry)
            }
        }
    }

    func delete(entries: [DiaryEntry]) {
        enqueue { [weak self] in
            guard let self else { return }
            for entry in entries {
                await deleteSamples(for: entry)
            }
        }
    }

    private var quantityTypes: [HKQuantityType] {
        [
            .dietaryEnergyConsumed,
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .dietaryProtein
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }
    }

    private var writableQuantityTypes: [HKQuantityType] {
        quantityTypes.filter { healthStore.authorizationStatus(for: $0) == .sharingAuthorized }
    }

    private func requestAuthorization() async -> Bool {
        let shareTypes: Set<HKSampleType> = Set(quantityTypes.map { $0 as HKSampleType })
        let success = await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: shareTypes, read: []) { success, error in
                Task { @MainActor [weak self] in
                    if let error {
                        self?.lastError = error.localizedDescription
                    }
                    self?.refreshAuthorizationState()
                    continuation.resume(returning: success)
                }
            }
        }
        return success && authorizationState != .denied
    }

    @discardableResult
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = pendingOperation
        let task = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            await operation()
        }
        pendingOperation = task
        return task
    }

    private func replaceSamples(for entry: DiaryEntry) async {
        let types = writableQuantityTypes
        guard !types.isEmpty else { return }

        for type in types {
            await deleteSample(of: type, syncIdentifier: syncIdentifier(for: entry, type: type))
        }

        let samples = samples(for: entry, types: types)
        guard !samples.isEmpty else { return }
        await save(samples)
    }

    private func deleteSamples(for entry: DiaryEntry) async {
        for type in writableQuantityTypes {
            await deleteSample(of: type, syncIdentifier: syncIdentifier(for: entry, type: type))
        }
    }

    private func samples(for entry: DiaryEntry, types: [HKQuantityType]) -> [HKQuantitySample] {
        let values: [(HKQuantityTypeIdentifier, Double, HKUnit)] = [
            (.dietaryEnergyConsumed, entry.nutrients.calories, .kilocalorie()),
            (.dietaryCarbohydrates, entry.nutrients.carbs, .gram()),
            (.dietaryFatTotal, entry.nutrients.fat, .gram()),
            (.dietaryProtein, entry.nutrients.protein, .gram())
        ]

        return values.compactMap { identifier, value, unit in
            guard let type = types.first(where: { $0.identifier == identifier.rawValue }) else { return nil }
            let quantity = HKQuantity(unit: unit, doubleValue: max(value, 0))
            let syncID = syncIdentifier(for: entry, type: type)
            let metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: syncID,
                HKMetadataKeySyncVersion: 1,
                HKMetadataKeyWasUserEntered: true
            ]
            return HKQuantitySample(
                type: type,
                quantity: quantity,
                start: entry.date,
                end: entry.date,
                metadata: metadata
            )
        }
    }

    private func syncIdentifier(for entry: DiaryEntry, type: HKQuantityType) -> String {
        "com.cseibert.CalorieTracker.\(entry.id.uuidString).\(type.identifier)"
    }

    private func deleteSample(of type: HKQuantityType, syncIdentifier: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeySyncIdentifier,
                operatorType: .equalTo,
                value: syncIdentifier
            )
            healthStore.deleteObjects(of: type, predicate: predicate) { success, _, error in
                if let error, !success {
                    Task { @MainActor [weak self] in
                        self?.lastError = error.localizedDescription
                    }
                }
                continuation.resume()
            }
        }
    }

    private func save(_ samples: [HKQuantitySample]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            healthStore.save(samples) { success, error in
                if let error, !success {
                    Task { @MainActor [weak self] in
                        self?.lastError = error.localizedDescription
                    }
                }
                continuation.resume()
            }
        }
    }
}
