import os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from shopping_utils import aisle_for


class Aisles(unittest.TestCase):
    def test_packaged_versions_go_to_pantry(self):
        for name in ("tinned tomatoes", "1 can chopped tomatoes", "chicken stock", "coconut milk", "black pepper", "tomato paste", "dried oregano", "soy sauce"):
            self.assertEqual(aisle_for(name), "Pantry", name)

    def test_fresh_and_frozen(self):
        self.assertEqual(aisle_for("tomatoes"), "Produce")
        self.assertEqual(aisle_for("chicken thighs"), "Meat & Seafood")
        self.assertEqual(aisle_for("milk"), "Dairy & Eggs")
        self.assertEqual(aisle_for("frozen peas"), "Frozen")
        self.assertEqual(aisle_for("frozen chicken nuggets"), "Frozen")


if __name__ == "__main__":
    unittest.main()
