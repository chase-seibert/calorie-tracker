import Foundation

enum DiaryFixtureLoader {
    private static let fixtureName = "DeviceDiaryFixture"
    private static let fixtureDirectoryName = "CalorieTrackerFixtures"

    @MainActor
    static func makeDeviceStore(
        healthKit: HealthKitStore,
        calendar: Calendar = .current,
        reset: Bool
    ) -> DiaryStore {
        guard
            let fixtureURL = Bundle.main.url(
                forResource: fixtureName,
                withExtension: "json"
            ),
            let data = try? Data(contentsOf: fixtureURL),
            let fixture = decode(data: data)
        else {
            return DiaryStore(healthKit: healthKit)
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fixtureDirectoryName, isDirectory: true)
            .appendingPathComponent("DeviceDiary.json")

        if !reset, FileManager.default.fileExists(atPath: fileURL.path) {
            return DiaryStore(
                fileURL: fileURL,
                calendar: calendar,
                healthKit: healthKit,
                defaultWeightUnit: fixture.defaultWeightUnit
            )
        }

        try? FileManager.default.removeItem(at: fileURL)
        let document = rebasedDocument(
            fixture.document,
            from: fixture.capturedReferenceDate,
            to: Date(),
            calendar: calendar
        )
        return DiaryStore(
            document: document,
            fileURL: fileURL,
            calendar: calendar,
            healthKit: healthKit,
            defaultWeightUnit: fixture.defaultWeightUnit
        )
    }

    private static func decode(data: Data) -> DiaryFixture? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DiaryFixture.self, from: data)
    }

    private static func rebasedDocument(
        _ source: DiaryDocument,
        from sourceDate: Date,
        to destinationDate: Date,
        calendar: Calendar
    ) -> DiaryDocument {
        let sourceDay = calendar.startOfDay(for: sourceDate)
        let destinationDay = calendar.startOfDay(for: destinationDate)
        let dayOffset = calendar.dateComponents([.day], from: sourceDay, to: destinationDay).day ?? 0

        var document = source
        document.entries = source.entries.map { entry in
            var rebased = entry
            rebased.date = calendar.date(byAdding: .day, value: dayOffset, to: entry.date) ?? entry.date
            rebased.loggedAt = calendar.date(byAdding: .day, value: dayOffset, to: entry.loggedAt) ?? entry.loggedAt
            return rebased
        }
        return document
    }
}
