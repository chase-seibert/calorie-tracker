"""Focused catalog-builder regressions; no downloads or database writes."""
import unittest

from build_food_catalog import classify_meat_text


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


if __name__ == "__main__":
    unittest.main()
