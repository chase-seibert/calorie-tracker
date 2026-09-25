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
        #if DEBUG && targetEnvironment(simulator)
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

        let fileURL = SharedDiaryStorage.selectFixture("device", reset: reset)

        if !reset, FileManager.default.fileExists(atPath: fileURL.path) {
            return DiaryStore(
                fileURL: fileURL,
                calendar: calendar,
                catalog: catalog,
                healthKit: healthKit
            )
        }

        let document = makeRichDemoDocument(
            rebasedDocument(
            fixture.document,
            from: fixture.capturedReferenceDate,
            to: Date(),
            calendar: calendar
            ),
            referenceDate: Date(),
            calendar: calendar
        )
        return DiaryStore(
            document: document,
            fileURL: fileURL,
            calendar: calendar,
            catalog: catalog,
            healthKit: healthKit
        )
        #else
        return DiaryStore(catalog: catalog, healthKit: healthKit)
        #endif
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

    /// Adds a realistic, relative demo history to the small captured fixture.
    ///
    /// This is intentionally applied only by `makeDeviceStore`. The smaller
    /// `rebasedDocument` fixture remains unchanged because it is also used by
    /// migration and magic-suggestion tests.
    static func makeRichDemoDocument(
        _ document: DiaryDocument,
        referenceDate: Date,
        calendar: Calendar
    ) -> DiaryDocument {
        var document = document
        let today = calendar.startOfDay(for: referenceDate)
        document.trackingStartDate = calendar.date(byAdding: .day, value: -29, to: today)
        document.dayStatuses.removeAll { $0.kind == .gap }

        let foods = makeDemoFoods()
        document.customFoods.append(contentsOf: foods.customFoods)

        let meals = makeDemoMeals(foods: foods)
        document.meals.append(contentsOf: meals.all)

        let customMeals = meals.custom
        let importedMeals = meals.imported
        let dailyPlans = [
            DemoDayPlan(
                breakfast: [foods.oats, foods.eggs, foods.berries],
                lunch: customMeals[0],
                snack: [foods.apple, foods.yogurt],
                dinner: importedMeals[0]
            ),
            DemoDayPlan(
                breakfast: [foods.oats, foods.toast, foods.avocado],
                lunch: importedMeals[1],
                snack: [foods.apple, foods.yogurt],
                dinner: customMeals[1]
            ),
            DemoDayPlan(
                breakfast: [foods.oats, foods.eggs, foods.berries],
                lunch: importedMeals[2],
                snack: [foods.apple, foods.yogurt],
                dinner: customMeals[0]
            )
        ]

        for offset in (-29 ... 0) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let plan = dailyPlans[(offset + 29) % dailyPlans.count]
            appendDemoDayIfNeeded(
                to: &document,
                day: day,
                plan: plan,
                foods: foods,
                calendar: calendar
            )

            // Keep the meat charts varied without making every day a meat day.
            if offset == -27 || offset == -18 || offset == -9 || offset == 0 {
                appendDemoFood(&document, foods.bacon, on: day, hour: 8, order: 30, calendar: calendar)
            }
            if offset == -25 || offset == -15 || offset == -5 {
                appendDemoFood(&document, foods.steak, on: day, hour: 19, order: 31, calendar: calendar)
            }
        }

        let alcoholDays: [(offset: Int, drinks: Int, type: AlcoholType)] = [
            (-28, 1, .beer), (-24, 2, .wine), (-20, 1, .cocktail),
            (-16, 2, .beer), (-13, 1, .wine), (-9, 2, .spirits),
            (-6, 1, .cocktail), (-2, 2, .wine), (0, 1, .beer)
        ]
        document.alcoholEntries.removeAll { entry in
            (-29 ... 0).contains(calendar.dateComponents([.day], from: today, to: entry.date).day ?? 1)
        }
        document.alcoholEntries.append(contentsOf: alcoholDays.compactMap { item in
            guard let day = calendar.date(byAdding: .day, value: item.offset, to: today) else { return nil }
            return AlcoholEntry(
                id: stableUUID("demo-alcohol-\(item.offset)"),
                date: day,
                drinks: item.drinks,
                type: item.type,
                loggedAt: calendar.date(bySettingHour: 20, minute: 15, second: 0, of: day) ?? day
            )
        })
        document.alcoholEntries.sort { $0.date < $1.date }
        return document
    }

    private struct DemoFoods {
        let oats: Food
        let eggs: Food
        let berries: Food
        let toast: Food
        let avocado: Food
        let chicken: Food
        let rice: Food
        let greens: Food
        let salmon: Food
        let lentils: Food
        let steak: Food
        let bacon: Food
        let potato: Food
        let yogurt: Food
        let apple: Food

        var customFoods: [Food] {
            [oats, eggs, berries, toast, avocado, chicken, rice, greens, salmon, lentils, steak, bacon, potato, yogurt, apple]
        }
    }

    private struct DemoDayPlan {
        let breakfast: [Food]
        let lunch: SavedMeal
        let snack: [Food]
        let dinner: SavedMeal
    }

    private static func makeDemoFoods() -> DemoFoods {
        func food(
            _ key: String,
            _ name: String,
            calories: Double,
            carbs: Double,
            fat: Double,
            protein: Double,
            fiber: Double,
            processed: Bool = false,
            red: Bool = false
        ) -> Food {
            Food(
                sourceID: "fixture-\(key)",
                source: .custom,
                name: name,
                brand: "Demo kitchen",
                barcode: nil,
                nutrients: MacroNutrients(
                    calories: calories,
                    carbs: carbs,
                    fat: fat,
                    protein: protein,
                    fiber: fiber
                ),
                baseAmountGrams: 100,
                servingGrams: 100,
                servingDescription: "1 serving",
                portions: [FoodPortion(id: "fixture-serving", label: "serving", grams: 100)],
                containsProcessedMeat: processed,
                containsRedMeat: red
            )
        }

        return DemoFoods(
            oats: food("oats", "Chase's overnight oats", calories: 320, carbs: 48, fat: 9, protein: 14, fiber: 8),
            eggs: food("eggs", "Eggs with spinach", calories: 140, carbs: 3, fat: 9, protein: 13, fiber: 1),
            berries: food("berries", "Mixed berries", calories: 80, carbs: 19, fat: 0.5, protein: 1, fiber: 5),
            toast: food("toast", "Whole-grain toast", calories: 120, carbs: 22, fat: 2, protein: 5, fiber: 4),
            avocado: food("avocado", "Avocado", calories: 160, carbs: 9, fat: 15, protein: 2, fiber: 7),
            chicken: food("chicken", "Roasted chicken breast", calories: 280, carbs: 0, fat: 7, protein: 52, fiber: 0),
            rice: food("rice", "Brown rice", calories: 220, carbs: 46, fat: 2, protein: 5, fiber: 4),
            greens: food("greens", "Roasted vegetables and greens", calories: 120, carbs: 18, fat: 4, protein: 5, fiber: 6),
            salmon: food("salmon", "Baked salmon", calories: 360, carbs: 0, fat: 22, protein: 38, fiber: 0),
            lentils: food("lentils", "Lentil curry", calories: 280, carbs: 42, fat: 7, protein: 15, fiber: 12),
            steak: food("steak", "Grilled steak", calories: 430, carbs: 0, fat: 27, protein: 45, fiber: 0, red: true),
            bacon: food("bacon", "Bacon", calories: 180, carbs: 1, fat: 14, protein: 12, fiber: 0, processed: true),
            potato: food("potato", "Roasted potato", calories: 220, carbs: 40, fat: 6, protein: 5, fiber: 5),
            yogurt: food("yogurt", "Greek yogurt", calories: 150, carbs: 10, fat: 3, protein: 20, fiber: 0),
            apple: food("apple", "Apple", calories: 95, carbs: 25, fat: 0, protein: 0.5, fiber: 4)
        )
    }

    private static func makeDemoMeals(foods: DemoFoods) -> (
        all: [SavedMeal], custom: [SavedMeal], imported: [SavedMeal]
    ) {
        func item(_ food: Food) -> MealItem {
            MealItem(id: stableUUID("demo-item-\(food.sourceID)"), food: food, amount: 1, unit: .serving)
        }
        func meal(_ key: String, _ name: String, _ items: [Food], origin: SavedMealOrigin) -> SavedMeal {
            let mealItems = items.map(item)
            return SavedMeal(
                id: stableUUID("demo-meal-\(key)"),
                name: name,
                items: mealItems,
                containsProcessedMeat: items.contains { $0.containsProcessedMeat == true },
                containsRedMeat: items.contains { $0.containsRedMeat == true },
                origin: origin
            )
        }

        let custom = [
            meal("chicken-bowl", "Weeknight chicken bowl", [foods.chicken, foods.rice, foods.greens, foods.avocado], origin: .custom),
            meal("steak-plate", "Sunday steak plate", [foods.steak, foods.potato, foods.greens], origin: .custom)
        ]
        let imported = [
            meal("salmon-poke", "AI Import — Salmon poke bowl", [foods.salmon, foods.rice, foods.greens, foods.avocado], origin: .imported),
            meal("shawarma", "AI Import — Chicken shawarma plate", [foods.chicken, foods.toast, foods.greens, foods.yogurt], origin: .imported),
            meal("lentil-curry", "AI Import — Lentil curry bowl", [foods.lentils, foods.rice, foods.greens], origin: .imported)
        ]
        return (custom + imported, custom, imported)
    }

    private static func appendDemoDayIfNeeded(
        to document: inout DiaryDocument,
        day: Date,
        plan: DemoDayPlan,
        foods: DemoFoods,
        calendar: Calendar
    ) {
        let existingCalories = document.entries
            .filter { calendar.isDate($0.date, inSameDayAs: day) && !$0.isCheatDayAdjustment }
            .reduce(0) { $0 + $1.nutrients.calories }
        var calories = existingCalories
        var order = 10

        for food in plan.breakfast + plan.snack where calories < 2_100 {
            appendDemoFood(&document, food, on: day, hour: order == 10 ? 7 : 15, order: order, calendar: calendar)
            calories += food.nutrients.calories
            order += 1
        }
        if calories < 2_100 {
            appendDemoMeal(&document, plan.lunch, on: day, hour: 12, order: order, calendar: calendar)
            calories += plan.lunch.nutrients.calories
            order += 1
        }
        if calories < 2_100 {
            appendDemoMeal(&document, plan.dinner, on: day, hour: 19, order: order, calendar: calendar)
        }

        // Existing captured days have little or no fiber. Add a produce side so
        // every day remains represented on the fiber chart as well.
        let hasFiber = document.entries
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .contains { ($0.nutrients.fiber ?? 0) > 0 }
        if !hasFiber {
            appendDemoFood(&document, foods.greens, on: day, hour: 18, order: 40, calendar: calendar)
        }
    }

    private static func appendDemoFood(
        _ document: inout DiaryDocument,
        _ food: Food,
        on day: Date,
        hour: Int,
        order: Int,
        calendar: Calendar
    ) {
        let loggedAt = calendar.date(bySettingHour: hour, minute: 15, second: 0, of: day) ?? day
        document.entries.append(DiaryEntry(
            id: stableUUID("demo-entry-\(food.id)-\(day.timeIntervalSince1970)-\(order)"),
            date: day,
            food: food,
            amount: 1,
            unit: .serving,
            nutrients: food.nutrients,
            loggedAt: loggedAt,
            portionID: "fixture-serving",
            displayOrder: order
        ))
    }

    private static func appendDemoMeal(
        _ document: inout DiaryDocument,
        _ meal: SavedMeal,
        on day: Date,
        hour: Int,
        order: Int,
        calendar: Calendar
    ) {
        let loggedAt = calendar.date(bySettingHour: hour, minute: 30, second: 0, of: day) ?? day
        let mealFood = Food(
            sourceID: "saved-meal-\(meal.id.uuidString)",
            source: .custom,
            name: meal.name,
            brand: nil,
            barcode: nil,
            nutrients: meal.nutrients,
            baseAmountGrams: 1,
            servingGrams: 1,
            servingDescription: "1 meal",
            portions: [FoodPortion(id: "saved-meal", label: "meal", grams: 1)],
            containsProcessedMeat: meal.resolvedContainsProcessedMeat,
            containsRedMeat: meal.resolvedContainsRedMeat
        )
        document.entries.append(DiaryEntry(
            id: stableUUID("demo-meal-entry-\(meal.id.uuidString)-\(day.timeIntervalSince1970)-\(order)"),
            date: day,
            food: mealFood,
            amount: 1,
            unit: .serving,
            nutrients: meal.nutrients,
            loggedAt: loggedAt,
            portionID: "saved-meal",
            displayOrder: order,
            savedMealID: meal.id,
            mealItems: meal.items,
            processedMeatOverride: meal.containsProcessedMeat,
            redMeatOverride: meal.containsRedMeat
        ))
    }

    private static func stableUUID(_ key: String) -> UUID {
        let bytes = Array(key.utf8)
        var hash = UInt64(14695981039346656037)
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        let hex = String(format: "%016llx", hash)
        return UUID(uuidString: "\(hex.prefix(8))-0000-4000-8000-\(hex.suffix(12))") ?? UUID()
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
