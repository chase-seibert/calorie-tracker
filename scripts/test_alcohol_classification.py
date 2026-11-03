"""Focused regressions for stable-ID alcoholic beverage classification."""
import hashlib
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from build_food_catalog import (
    CatalogFood,
    apply_alcohol_classifications,
    create_database,
    load_alcohol_classifications,
)
from export_alcohol_review_manifest import export_manifest

ROOT = Path(__file__).resolve().parents[1]


class AlcoholClassificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.classifications = load_alcohol_classifications(ROOT / "data/food-catalog/alcohol-classifications.json")

    def test_full_manifest_serializes_every_stable_identity_once(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "manifest.jsonl"
            count = export_manifest(ROOT / "CalorieTracker/Resources/FoodCatalog.sqlite3", output)
            records = [json.loads(line) for line in output.read_text(encoding="utf-8").splitlines()]
            manifest_hash = hashlib.sha256(output.read_bytes()).hexdigest()
        with sqlite3.connect(ROOT / "CalorieTracker/Resources/FoodCatalog.sqlite3") as database:
            expected_count = database.execute("SELECT count(*) FROM foods").fetchone()[0]
        identities = [(record["source"], record["source_id"]) for record in records]
        self.assertEqual(count, expected_count)
        self.assertEqual(len(identities), len(set(identities)))
        curated = json.loads((ROOT / "data/food-catalog/alcohol-classifications.json").read_text(encoding="utf-8"))
        self.assertEqual(curated["manifest_sha256"], manifest_hash)
        chase = next(record for record in records if record["source"] == "chaseFood" and record["source_id"] == "food_cocktail")
        self.assertEqual(chase["source_category"], "Beverages")
        self.assertIn("alcoholic", chase["source_context"])

    def test_review_marks_drinks_and_preserves_non_alcoholic_boundaries(self):
        expected_true = {
            ("usda", "2710616"),  # Beer
            ("usda", "2710621"),  # Hard cider
            ("usda", "2710642"),  # Mimosa
            ("usda", "174837"),   # Alcoholic white wine
            ("chaseFood", "food_beer"),
            ("chaseFood", "food_cocktail"),
            ("chaseFood", "food_wine"),
        }
        expected_false = {
            ("usda", "2710610"),  # Nonalcoholic beer
            ("usda", "2710609"),  # Nonalcoholic wine
            ("usda", "169070"),   # Cooking wine
            ("usda", "2710575"),  # Nonalcoholic margarita mix
            ("chaseFood", "food_ginger_beer"),
            ("chaseFood", "food_root_beer"),
            ("chaseFood", "food_cranberry_juice_cocktail"),
            ("chaseFood", "food_shrimp_cocktail"),
        }
        self.assertTrue(all(self.classifications[key]["contains_alcohol"] for key in expected_true))
        self.assertTrue(all(not self.classifications[key]["contains_alcohol"] for key in expected_false))
        self.assertFalse(self.classifications[("usda", "2710698")]["contains_alcohol"])  # ambiguous Glug stays untagged

    def test_application_is_keyed_by_source_and_id_and_sqlite_round_trips(self):
        matching = [
            CatalogFood("same", "usda", "Beer", None, None, 100, 0, 0, 0),
            CatalogFood("same", "off", "Beer", None, None, 100, 0, 0, 0),
            CatalogFood("food_beer", "chaseFood", "Beer", None, None, 100, 0, 0, 0),
        ]
        classifications = {
            ("usda", "same"): {"contains_alcohol": True},
            ("off", "same"): {"contains_alcohol": False},
            ("chaseFood", "food_beer"): {"contains_alcohol": True},
        }
        updated = apply_alcohol_classifications(matching, classifications)
        self.assertEqual([food.contains_alcohol for food in updated], [True, False, True])
        self.assertEqual([food.calories for food in updated], [100, 100, 100])
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "catalog.sqlite3"
            create_database(output, updated)
            with sqlite3.connect(output) as database:
                values = database.execute(
                    "SELECT source, source_id, contains_alcohol FROM foods ORDER BY source"
                ).fetchall()
        self.assertEqual(values, [("chaseFood", "food_beer", 1), ("off", "same", 0), ("usda", "same", 1)])

    def test_loader_rejects_duplicate_identity_and_unknown_catalog_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.json"
            record = {"source": "usda", "source_id": "1", "contains_alcohol": False, "basis": "Reviewed"}
            path.write_text(json.dumps({"format": "calorie-tracker-alcohol-classifications-v1", "foods": [record, record]}))
            with self.assertRaisesRegex(ValueError, "Duplicate"):
                load_alcohol_classifications(path)
        with self.assertRaisesRegex(ValueError, "Unknown catalog identities"):
            apply_alcohol_classifications(
                [CatalogFood("1", "usda", "Food", None, None, 1, 0, 0, 0)],
                {("usda", "2"): {"contains_alcohol": True}},
            )


if __name__ == "__main__":
    unittest.main()
