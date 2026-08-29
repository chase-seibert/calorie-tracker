import Foundation

enum DiaryFixtureLoader {
    private static let fixtureName = "DeviceDiaryFixture"

    @MainActor
    static func makeDeviceStore(
        healthKit: HealthKitStore,
        catalog: CatalogStore? = nil,
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
            return DiaryStore(catalog: catalog, healthKit: healthKit)
        }

        let fileURL = SharedDiaryStorage.defaultFileURL()

        if !reset, FileManager.default.fileExists(atPath: fileURL.path) {
            return DiaryStore(
                fileURL: fileURL,
                calendar: calendar,
                catalog: catalog,
                healthKit: healthKit
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
            catalog: catalog,
            healthKit: healthKit
        )
    }

    private static func decode(data: Data) -> DiaryFixture? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DiaryFixture.self, from: data)
    }

    static func rebasedDocument(
        _ source: DiaryDocument,
        from sourceDate: Date,
        to destinationDate: Date,
        calendar: Calendar
    ) -> DiaryDocument {
        let sourceDay = calendar.startOfDay(for: sourceDate)
        let destinationDay = calendar.startOfDay(for: destinationDate)
        let dayOffset = calendar.dateComponents([.day], from: sourceDay, to: destinationDay).day ?? 0

        var document = source
        document.trackingStartDate = source.trackingStartDate.flatMap {
            calendar.date(byAdding: .day, value: dayOffset, to: $0)
        }
        document.dayStatuses = source.dayStatuses.map { status in
            var rebased = status
            rebased.date = calendar.date(byAdding: .day, value: dayOffset, to: status.date) ?? status.date
            return rebased
        }
        document.entries = source.entries.map { entry in
            var rebased = entry
            rebased.date = calendar.date(byAdding: .day, value: dayOffset, to: entry.date) ?? entry.date
            rebased.loggedAt = calendar.date(byAdding: .day, value: dayOffset, to: entry.loggedAt) ?? entry.loggedAt
            return rebased
        }
        document.alcoholEntries = source.alcoholEntries.map { entry in
            var rebased = entry
            rebased.date = calendar.date(byAdding: .day, value: dayOffset, to: entry.date) ?? entry.date
            rebased.loggedAt = calendar.date(byAdding: .day, value: dayOffset, to: entry.loggedAt) ?? entry.loggedAt
            return rebased
        }
        addMagicDemoHistory(to: &document, referenceDate: destinationDate, calendar: calendar)
        return document
    }

    private static func addMagicDemoHistory(
        to document: inout DiaryDocument,
        referenceDate: Date,
        calendar: Calendar
    ) {
        let templateNames = [
            "Cappuccino",
            "Protein shake",
            "Turkey sandwich",
            "Tea with honey",
            "Chili, no rice",
            "Rice, white, cooked, glutinous"
        ]
        let templates = templateNames.compactMap { name in
            document.entries.first { $0.food.name == name }
        }
        guard templates.count == templateNames.count else { return }

        let templateKeys = Set(templates.map(itemKey(for:)))
        let magicFoodIDs = Set(templates.flatMap(representedFoodIDs(for:)))
        let unrelatedTemplates = document.entries.filter {
            !$0.isCheatDayAdjustment
                && !$0.isMeal
                && !magicFoodIDs.contains($0.food.id)
        }
        guard let unrelatedTemplate = unrelatedTemplates.first(where: { $0.food.name == "Plum, raw" })
            ?? unrelatedTemplates.first
        else { return }
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let magicHistoryDays = (-2 ... -1).compactMap {
            calendar.date(byAdding: .day, value: $0, to: referenceDay)
        }
        let visibleDays = (0...1).compactMap {
            calendar.date(byAdding: .day, value: $0, to: referenceDay)
        }
        document.entries.removeAll { entry in
            visibleDays.contains { calendar.isDate(entry.date, inSameDayAs: $0) }
                || (magicHistoryDays.contains { calendar.isDate(entry.date, inSameDayAs: $0) }
                    && templateKeys.contains(itemKey(for: entry)))
        }

        let times = [(6, 30), (6, 31), (12, 0), (12, 1), (18, 0), (18, 1)]
        for day in magicHistoryDays {
            for (index, template) in templates.enumerated() {
                let loggedAt = calendar.date(
                    bySettingHour: times[index].0,
                    minute: times[index].1,
                    second: 0,
                    of: day
                ) ?? day
                document.entries.append(DiaryEntry(
                    id: UUID(),
                    date: day,
                    food: template.food,
                    amount: template.amount,
                    unit: template.unit,
                    nutrients: template.nutrients,
                    loggedAt: loggedAt,
                    portionID: template.portionID,
                    displayOrder: index,
                    savedMealID: template.savedMealID,
                    mealItems: template.mealItems,
                    kind: template.kind
                ))
            }
        }

        for day in visibleDays {
            let loggedAt = calendar.date(
                bySettingHour: 0,
                minute: 30,
                second: 0,
                of: day
            ) ?? day
            document.entries.append(DiaryEntry(
                id: UUID(),
                date: day,
                food: unrelatedTemplate.food,
                amount: unrelatedTemplate.amount,
                unit: unrelatedTemplate.unit,
                nutrients: unrelatedTemplate.nutrients,
                loggedAt: loggedAt,
                portionID: unrelatedTemplate.portionID,
                displayOrder: 0
            ))
        }
    }

    private static func itemKey(for entry: DiaryEntry) -> String {
        if let savedMealID = entry.savedMealID {
            return "meal:\(savedMealID.uuidString)"
        }
        return "food:\(entry.food.id)"
    }

    private static func representedFoodIDs(for entry: DiaryEntry) -> [String] {
        guard entry.isMeal else { return [entry.food.id] }
        return entry.mealItems?.map { $0.food.id } ?? []
    }
}
