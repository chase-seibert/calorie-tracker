import XCTest
@testable import CalorieTracker

final class CalorieTrackerTests: XCTestCase {
    @MainActor
    func testLoggingScalesNutrientsAndRemembersQuantity() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
        let food = Food(
            sourceID: "banana",
            source: .usda,
            name: "Banana",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 89, carbs: 22.8, fat: 0.3, protein: 1.1),
            baseAmountGrams: 100,
            servingGrams: 118,
            servingDescription: "1 medium"
        )

        store.log(food, amount: 50, unit: .grams, on: Date())

        let entry = try XCTUnwrap(store.entries(on: Date()).first)
        XCTAssertEqual(entry.nutrients.calories, 44.5, accuracy: 0.001)
        XCTAssertEqual(store.preference(for: food), QuantityPreference(amount: 50, unit: .grams))
    }

    @MainActor
    func testFavoritePersistsSelectedNaturalPortionWithoutLogging() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = folder.appendingPathComponent("diary.json")
        let egg = Food(
            sourceID: "scrambled-egg",
            source: .usda,
            name: "Egg, whole, cooked, scrambled",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 149, carbs: 1.6, fat: 10, protein: 10),
            baseAmountGrams: 100,
            servingGrams: 61,
            servingDescription: "1 large egg",
            portions: [FoodPortion(id: "large-egg", label: "large egg", grams: 61)]
        )
        let preference = QuantityPreference(amount: 1, unit: .serving, portionID: "large-egg")
        let store = DiaryStore(fileURL: fileURL)

        store.toggleFavorite(egg, preference: preference)

        let reloaded = DiaryStore(fileURL: fileURL)
        XCTAssertTrue(reloaded.isFavorite(egg))
        XCTAssertEqual(reloaded.preference(for: egg), preference)
    }

    @MainActor
    func testCustomFoodsAndMealsRemainSeparatePersonalCatalogItems() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
        let americano = store.addCustomFood(
            name: "Americano",
            brand: "",
            calories: 5,
            carbs: 1,
            fat: 0,
            protein: 0,
            servingGrams: 355
        )
        store.saveMeal(
            name: "Coffee",
            items: [MealItem(id: UUID(), food: americano, amount: 1, unit: .serving, portionID: "custom-serving")]
        )

        XCTAssertEqual(store.document.customFoods.count, 1)
        XCTAssertEqual(store.document.meals.count, 1)

        store.deleteCustomFood(americano)
        XCTAssertTrue(store.document.customFoods.isEmpty)
        XCTAssertEqual(store.document.meals.count, 1)
    }

    func testMyFitnessPalCSVImport() throws {
        let csv = "Date,Food Name,Calories,Carbs,Fat,Protein\n2026-08-01,Banana,105,27,0.4,1.3\n"
        let result = try MyFitnessPalImporter.parse(data: Data(csv.utf8), calendar: .current)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.foods.count, 1)
        XCTAssertEqual(result.entries[0].food.source, .myFitnessPal)
        XCTAssertEqual(result.entries[0].nutrients.calories, 105)
    }

    func testCatalogHasBothBundledSources() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalog = CatalogStore(url: projectRoot.appendingPathComponent("CalorieTracker/Resources/FoodCatalog.sqlite3"))
        XCTAssertGreaterThan(catalog.count(source: .usda), 0)
        XCTAssertGreaterThan(catalog.count(source: .openFoodFacts), 0)
        XCTAssertFalse(catalog.search("banana", source: .usda).isEmpty)
        XCTAssertFalse(catalog.search("milk", source: .openFoodFacts).isEmpty)
    }

    func testCatalogPreservesNaturalPortions() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalog = CatalogStore(url: projectRoot.appendingPathComponent("CalorieTracker/Resources/FoodCatalog.sqlite3"))

        let scrambledEgg = try XCTUnwrap(
            catalog.search("egg whole cooked scrambled", source: .usda)
                .first { $0.name == "Egg, whole, cooked, scrambled" }
        )
        XCTAssertTrue(scrambledEgg.availablePortions.contains { $0.label == "large egg" && $0.grams == 61 })

        let butter = try XCTUnwrap(
            catalog.search("butter salted", source: .usda)
                .first { $0.availablePortions.contains { $0.label.localizedCaseInsensitiveContains("tablespoon") || $0.label == "tbsp" } }
        )
        XCTAssertNotNil(butter.availablePortions.first { $0.label.localizedCaseInsensitiveContains("table") || $0.label == "tbsp" })
    }

    @MainActor
    func testNewFoodsDefaultToOunces() {
        let previous = UserDefaults.standard.object(forKey: "defaultWeightUnit")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "defaultWeightUnit")
            } else {
                UserDefaults.standard.removeObject(forKey: "defaultWeightUnit")
            }
        }
        UserDefaults.standard.removeObject(forKey: "defaultWeightUnit")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DiaryStore(fileURL: folder.appendingPathComponent("diary.json"))
        let food = Food(
            sourceID: "cheddar",
            source: .usda,
            name: "Cheddar cheese",
            brand: nil,
            barcode: nil,
            nutrients: MacroNutrients(calories: 403, carbs: 1.3, fat: 33.1, protein: 24.9),
            baseAmountGrams: 100,
            servingGrams: nil,
            servingDescription: nil
        )

        XCTAssertEqual(store.preference(for: food), QuantityPreference(amount: 1, unit: .ounces))
    }
}
