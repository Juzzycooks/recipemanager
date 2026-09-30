import os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from recipe_text import parse_recipe_text


class ParseRecipeText(unittest.TestCase):
    def test_emoji_headers_sections_and_notes(self):
        text = """Creamy Tuscan Chicken 🍗
Ready in 30 minutes and everyone loves it!
Serves 4
Prep time: 10 mins
🧂 INGREDIENTS
For the chicken:
- 4 chicken breasts
- 2 tbsp olive oil
For the sauce:
- 1 cup cream
- 3 cloves garlic
👩‍🍳 METHOD
1. Season the chicken and sear until golden.
2. Add the garlic and cream and simmer
until thickened.
Notes:
Keeps 3 days in the fridge.
#dinner #chicken @someone
"""
        r = parse_recipe_text(text)
        self.assertEqual(r["title"], "Creamy Tuscan Chicken 🍗")
        self.assertEqual(r["servings"], "4")
        self.assertEqual(r["prep_time"], "10 mins")
        self.assertIn("# For the chicken", r["ingredients"])
        self.assertIn("# For the sauce", r["ingredients"])
        self.assertIn("4 chicken breasts", r["ingredients"].split("\n"))
        steps = r["instructions"].split("\n")
        self.assertEqual(steps[0], "Season the chicken and sear until golden.")
        self.assertEqual(steps[1], "Add the garlic and cream and simmer until thickened.")  # wrapped line joined
        self.assertEqual(r["notes"], "Keeps 3 days in the fridge.")
        self.assertNotIn("#dinner", r["description"])
        self.assertIn("Ready in 30 minutes", r["description"])

    def test_inline_marker_content_and_ocr_bullets(self):
        text = "Pancakes\nIngredients\ne 2 cups flour\ne 1 tsp salt\n© 3 eggs\nDirections\nMix everything.\nCook on a hot pan."
        r = parse_recipe_text(text)
        self.assertEqual(r["ingredients"].split("\n"), ["2 cups flour", "1 tsp salt", "3 eggs"])
        self.assertEqual(r["instructions"].split("\n"), ["Mix everything.", "Cook on a hot pan."])

    def test_no_headings_falls_back_to_shape(self):
        text = "Quick Salsa\n2 tomatoes\n1/2 cup onion, diced\n1 tsp salt\nStir all of the ingredients together in a bowl and let it rest for ten minutes before serving."
        r = parse_recipe_text(text)
        self.assertEqual(r["title"], "Quick Salsa")
        self.assertIn("1/2 cup onion, diced", r["ingredients"])
        self.assertTrue(r["instructions"].startswith("Stir all"))

    def test_glued_ingredients_are_split(self):
        text = "Toast\nIngredients:\n2 slices bread 1 tbsp butter 1 tsp jam 1 pinch salt\nMethod:\nToast the bread."
        r = parse_recipe_text(text)
        self.assertGreaterEqual(len(r["ingredients"].split("\n")), 3)

    def test_step_numbers_and_long_paragraph_split(self):
        long = "Preheat the oven to 200C and line a tray with baking paper. " * 3 + "Roast the vegetables for 25 minutes until charred at the edges. Serve warm."
        r = parse_recipe_text("Roast Veg\nIngredients\n1 kg veg\nMethod\nStep 1: Chop.\n" + long)
        self.assertEqual(r["instructions"].split("\n")[0], "Chop.")
        self.assertGreater(len(r["instructions"].split("\n")), 2)

    def test_quantity_line_is_not_a_subheading(self):
        r = parse_recipe_text("X\nIngredients\n2 cups flour:\n1 egg\nMethod\nMix.")
        self.assertNotIn("# 2 cups flour", r["ingredients"])

    def test_several_meta_fields_on_one_line(self):
        r = parse_recipe_text("Prawns\nServes 2   Prep time: 10 mins | Cook time: 8 mins\nIngredients\n300 g prawns\nMethod\nCook.")
        self.assertEqual((r["servings"], r["prep_time"], r["cook_time"]), ("2", "10 mins", "8 mins"))

    def test_empty_and_junk_never_raise(self):
        for junk in ("", "   ", "\n\n", "#tag #tag2", "..."):
            self.assertIsInstance(parse_recipe_text(junk), dict)


class UnlabelledPost(unittest.TestCase):
    """A real-world Instagram shape: no Ingredients/Method headings, dash bullets, numbered steps,
    a second recipe part introduced by a short line, and a PS at the end."""
    CAPTION = """Skirt Steak 🥩🔥

Skirt steak is another one of those cuts that is insanely underrated here. Perfect to eat by itself or in a sandwich 🔥

Here’s exactly how I prep & cook my skirt steak ⬇️

- 1 skirt steak
- 125ml soy sauce
- Juice of 1 lime
- BBQ rub

1. Make the marinate & marinate the meat for 3-4 hrs
2. Set your grill up for 2 zone cooking
2. Grill the skirt steaks hot & fast, flipping every 30 seconds
3. Slice against the grain to serve

For the smoked chimichurri 🪴

- 125 ml olive oil
- Handful parsley
- 4-5 Garlic cloves

1. Finely chop the parsley, garlic
2. Add the olive oil & mix well

PS: mad shoutout to @paddocktotable for the steaks 🫶"""

    def test_structure(self):
        r = parse_recipe_text(self.CAPTION)
        self.assertEqual(r["title"], "Skirt Steak 🥩🔥")
        ing = r["ingredients"].split("\n")
        self.assertEqual(ing[:4], ["1 skirt steak", "125ml soy sauce", "Juice of 1 lime", "BBQ rub"])
        self.assertEqual(ing[4], "# For the smoked chimichurri")
        self.assertEqual(ing[5:], ["125 ml olive oil", "Handful parsley", "4-5 Garlic cloves"])
        steps = r["instructions"].split("\n")
        self.assertEqual(steps[0], "Make the marinate & marinate the meat for 3-4 hrs")
        self.assertIn("# For the smoked chimichurri", steps)
        self.assertEqual(steps[-1], "Add the olive oil & mix well")
        self.assertTrue(r["notes"].startswith("mad shoutout"))
        self.assertIn("insanely underrated", r["description"])
        self.assertNotIn("skirt steak\n", r["ingredients"].replace("1 skirt steak", ""))


if __name__ == "__main__":
    unittest.main()
