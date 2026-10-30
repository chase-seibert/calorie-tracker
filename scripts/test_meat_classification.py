"""Focused catalog-builder regressions; no downloads or database writes."""
import unittest
from pathlib import Path

from build_food_catalog import (
    CatalogFood,
    apply_meat_classifications,
    classify_meat_text,
    classify_off_meat,
    classify_usda_meat,
    load_meat_classifications,
)
from prepare_chase_food_data import load_chase_food_meat_classifications

ROOT = Path(__file__).resolve().parents[1]


class MeatClassificationTests(unittest.TestCase):
    def test_meat_sandwiches_are_not_treated_as_bakery_products(self):
        for name in (
            "SUBWAY, B.L.T. sub on white bread with bacon, lettuce and tomato",
            "Fast foods, submarine sandwich, bacon, lettuce, and tomato on white bread",
            "SUBWAY, cold cut sub on white bread with lettuce and tomato",
            "SUBWAY, black forest ham sub on white bread with lettuce and tomato",
        ):
            with self.subTest(name=name):
                self.assertEqual(classify_meat_text(name), (True, False))

    def test_bakery_and_meatless_exceptions_remain(self):
        for name in ("Hot dog buns", "Bacon bits, meatless", "Bacon, meatless", "Vegan bacon"):
            with self.subTest(name=name):
                self.assertEqual(classify_meat_text(name), (False, False))

    def test_unprocessed_red_meat_and_preserved_poultry_are_independent(self):
        self.assertEqual(classify_meat_text("Ground beef, cooked"), (False, True))
        self.assertEqual(classify_meat_text("Turkey bacon"), (True, False))
        self.assertEqual(classify_off_meat({}, "Original Beef Stick"), (True, False))

    def test_mixed_usda_dish_can_carry_both_flags_from_separate_ingredients(self):
        raw = {
            "description": "Beef and bacon sandwich",
            "inputFoods": [
                {"ingredientDescription": "Beef, cooked"},
                {"ingredientDescription": "Bacon, cured"},
            ],
        }
        self.assertEqual(classify_usda_meat(raw), (True, True))

    def test_fat_only_products_are_not_meat_even_when_source_lists_meat_ingredients(self):
        self.assertEqual(classify_meat_text("Animal fat, bacon grease"), (False, False))
        raw = {
            "description": "Animal fat or drippings",
            "inputFoods": [{"ingredientDescription": "Beef, cooked"}],
        }
        self.assertEqual(classify_usda_meat(raw), (False, False))
        self.assertEqual(classify_off_meat({"ingredients_tags": ["en:bacon"]}, "Bacon grease"), (False, False))
        self.assertEqual(classify_meat_text("Beef, separable lean and fat"), (False, True))

    def test_frozen_meatballs_are_not_processed_by_the_broad_sausage_category(self):
        self.assertEqual(
            classify_meat_text("Meatballs, frozen, Italian style", "Sausages and luncheon meats"),
            (False, False),
        )

    def test_curated_chase_food_classifications_are_keyed_and_applied(self):
        path = ROOT / "data/food-catalog/meat-classifications.json"
        all_classifications = load_meat_classifications(path)
        chase_ids = {source_id for source, source_id in all_classifications if source == "chaseFood"}
        curated = load_chase_food_meat_classifications(path, chase_ids)
        self.assertEqual(curated["food_bacon"]["contains_processed_meat"], True)
        self.assertEqual(curated["food_bacon"]["contains_red_meat"], False)
        self.assertEqual(curated["food_burger"]["contains_red_meat"], True)

        foods = [
            CatalogFood("food_bacon", "chaseFood", "Bacon", None, None, 53.82, 0.2, 4.04, 3.9),
            CatalogFood("food_plain", "chaseFood", "Plain food", None, None, 100, 0, 0, 0),
        ]
        updated = apply_meat_classifications(foods, all_classifications)
        self.assertEqual((updated[0].contains_processed_meat, updated[0].contains_red_meat), (True, False))
        self.assertEqual((updated[1].contains_processed_meat, updated[1].contains_red_meat), (False, False))
        self.assertEqual((updated[0].calories, updated[0].source_id), (53.82, "food_bacon"))


if __name__ == "__main__":
    unittest.main()
