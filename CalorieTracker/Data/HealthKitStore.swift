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
#if targetEnvironment(simulator)
        authorizationState = .unavailable
#endif
    }

    var isAvailable: Bool {
#if targetEnvironment(simulator)
        false
#else
        HKHealthStore.isHealthDataAvailable()
#endif
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

    func clearLastError() {
        lastError = nil
    }

    func waitForPendingOperations() async {
        await pendingOperation?.value
    }

    /// Only acknowledge the durable job after every HealthKit operation has completed successfully.
    func apply(_ work: HealthSyncWork) async -> Bool {
        guard authorizationState == .authorized else { return false }
        let operation = enqueue { [weak self] in
            guard let self else { return }
            lastError = nil
            for entry in work.knownEntries { await deleteSamples(for: entry) }
            for type in writableQuantityTypes {
                await deleteSample(of: type, syncIdentifier: dayOverrideIdentifier(for: work.day, type: type))
            }
            guard lastError == nil else { return }
            if work.zeroNutrition {
                await save(zeroSamples(on: work.day, types: writableQuantityTypes))
            } else {
                for entry in work.desiredEntries { await replaceSamples(for: entry) }
            }
        }
        await operation.value
        return lastError == nil && authorizationState == .authorized
    }

    @discardableResult
    func sync(entries: [DiaryEntry]) -> Task<Void, Never> {
        guard isAvailable else { return Task {} }
        return enqueue { [weak self] in
            guard let self else { return }
            for entry in entries {
                await replaceSamples(for: entry)
            }
        }
    }

    func delete(entries: [DiaryEntry]) {
        guard isAvailable else { return }
        enqueue { [weak self] in
            guard let self else { return }
            for entry in entries {
                await deleteSamples(for: entry)
            }
        }
    }

    @discardableResult
    func syncZeroNutrition(on date: Date) -> Task<Void, Never> {
        guard isAvailable else { return Task {} }
        return enqueue { [weak self] in
            guard let self else { return }
            let types = writableQuantityTypes
            guard !types.isEmpty else { return }
            for type in types {
                await deleteSample(of: type, syncIdentifier: dayOverrideIdentifier(for: date, type: type))
            }
            await save(zeroSamples(on: date, types: types))
        }
    }

    func deleteZeroNutrition(on date: Date) {
        guard isAvailable else { return }
        enqueue { [weak self] in
            guard let self else { return }
            for type in writableQuantityTypes {
                await deleteSample(of: type, syncIdentifier: dayOverrideIdentifier(for: date, type: type))
            }
        }
    }

    private var quantityTypes: [HKQuantityType] {
        [
            .dietaryEnergyConsumed,
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .dietaryProtein,
            .dietaryFiber
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
        let values: [(HKQuantityTypeIdentifier, Double?, HKUnit)] = [
            (.dietaryEnergyConsumed, entry.nutrients.calories, .kilocalorie()),
            (.dietaryCarbohydrates, entry.nutrients.carbs, .gram()),
            (.dietaryFatTotal, entry.nutrients.fat, .gram()),
            (.dietaryProtein, entry.nutrients.protein, .gram()),
            (.dietaryFiber, entry.nutrients.fiber, .gram())
        ]

        return values.compactMap { identifier, value, unit in
            guard let value,
                  let type = types.first(where: { $0.identifier == identifier.rawValue }) else { return nil }
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

    private func zeroSamples(on date: Date, types: [HKQuantityType]) -> [HKQuantitySample] {
        let units: [(HKQuantityTypeIdentifier, HKUnit)] = [
            (.dietaryEnergyConsumed, .kilocalorie()),
            (.dietaryCarbohydrates, .gram()),
            (.dietaryFatTotal, .gram()),
            (.dietaryProtein, .gram()),
            (.dietaryFiber, .gram())
        ]

        return units.compactMap { identifier, unit in
            guard let type = types.first(where: { $0.identifier == identifier.rawValue }) else { return nil }
            let metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: dayOverrideIdentifier(for: date, type: type),
                HKMetadataKeySyncVersion: 1,
                HKMetadataKeyWasUserEntered: true
            ]
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: 0),
                start: date,
                end: date,
                metadata: metadata
            )
        }
    }

    private func syncIdentifier(for entry: DiaryEntry, type: HKQuantityType) -> String {
        "com.cseibert.CalorieTracker.\(entry.id.uuidString).\(type.identifier)"
    }

    private func dayOverrideIdentifier(for date: Date, type: HKQuantityType) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let day = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return "com.cseibert.CalorieTracker.day-override.\(day).\(type.identifier)"
    }

    private func deleteSample(of type: HKQuantityType, syncIdentifier: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeySyncIdentifier,
                operatorType: .equalTo,
                value: syncIdentifier
            )
            healthStore.deleteObjects(of: type, predicate: predicate) { success, _, error in
                Task { @MainActor [weak self] in
                    if !success { self?.lastError = error?.localizedDescription ?? "Apple Health could not delete nutrition samples." }
                    continuation.resume()
                }
            }
        }
    }

    private func save(_ samples: [HKQuantitySample]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            healthStore.save(samples) { success, error in
                Task { @MainActor [weak self] in
                    if !success { self?.lastError = error?.localizedDescription ?? "Apple Health could not save nutrition samples." }
                    continuation.resume()
                }
            }
        }
    }
}
