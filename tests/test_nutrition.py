"""The calorie estimate (nutrition.py), servings parsing, source nutrition and precedence.

Reference totals below are worked by hand: USDA FoodData Central per-100 g values (SR Legacy /
Foundation) times weights from USDA household measures and the cup table in
static/unit-ingredients.json. The tolerance is 8%: the parser should land on the same weights,
so a bigger miss means a line was misread, not that a food value drifted.
"""
import json, os, sys, types, unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import nutrition as n

TOL = 0.08


def line(text):
    return n.estimate_line(text)


class LineMatching(unittest.TestCase):
    def test_pepper_is_not_capsicum(self):
        r = line("1 tsp black pepper")
        self.assertEqual(r["food"], "black pepper")
        self.assertEqual(r["status"], "negligible")
        self.assertEqual(line("1 red pepper, sliced")["food"], "capsicum")
        self.assertEqual(line("2 green peppers")["food"], "capsicum")
        self.assertEqual(line("2 peppers, sliced")["food"], "capsicum")  # a count of peppers is capsicum
        self.assertEqual(line("1/2 tsp cayenne pepper")["status"], "negligible")

    def test_whole_words_only(self):
        self.assertEqual(line("2 tbsp cornflour")["food"], "cornflour")
        self.assertEqual(line("1 cup sour cream")["food"], "sour cream")
        self.assertEqual(line("2 cups vanilla ice cream")["food"], "ice cream")
        self.assertEqual(line("1 cup cream cheese")["food"], "cream cheese")
        self.assertIsNone(line("1 price tag")["food"])  # not rice
        self.assertEqual(line("2 tbsp coconut oil")["food"], "coconut oil")
        self.assertEqual(line("1 tbsp unsalted butter")["food"], "butter")  # not salt

    def test_cup_of_flour_uses_the_cup_table(self):
        # USDA: 1 cup all-purpose flour 125 g = 455 kcal; the shared cup table says 120 g.
        r = line("1 cup flour")
        self.assertAlmostEqual(r["grams"], 120, delta=1)
        self.assertAlmostEqual(r["kcal"], 455, delta=455 * 0.05)
        # A cup of sugar is not a cup of flour (the old estimate used 240 g for both).
        self.assertAlmostEqual(line("1 cup sugar")["grams"], 200, delta=1)
        self.assertAlmostEqual(line("1 cup brown sugar, packed")["grams"], 213, delta=1)
        self.assertAlmostEqual(line("1 cup milk")["grams"], 243.7, delta=1)  # 236.6 ml x 1.03

    def test_tins_and_brackets(self):
        r = line("2 x 400g tins chopped tomatoes")
        self.assertEqual(r["food"], "canned tomatoes")
        self.assertAlmostEqual(r["grams"], 800)
        r = line("1 tin (400g) chickpeas, drained")
        self.assertEqual(r["food"], "chickpeas")
        self.assertAlmostEqual(r["grams"], 240)  # 60% left after draining
        self.assertAlmostEqual(line("1 (14 oz) can black beans")["grams"], 396.9 * 0.6, delta=1)
        self.assertAlmostEqual(line("2 cans (400g each) cannellini beans")["grams"], 480)
        self.assertAlmostEqual(line("½ cup (115g) butter, melted")["grams"], 115)
        self.assertAlmostEqual(line("2 chicken breasts (about 500g)")["grams"], 500)  # total, not each
        self.assertAlmostEqual(line("2 chicken breasts (250g each)")["grams"], 500)

    def test_slash_and_trailing_weights(self):
        self.assertAlmostEqual(line("400g/14oz spaghetti")["grams"], 400)
        self.assertAlmostEqual(line("Plain flour 200g")["grams"], 200)
        self.assertAlmostEqual(line("1 lb ground beef")["grams"], 453.6, delta=0.1)

    def test_ranges_average(self):
        self.assertAlmostEqual(line("1-2 cloves garlic")["grams"], 6)
        self.assertAlmostEqual(line("2 to 3 carrots")["grams"], 200)
        self.assertAlmostEqual(line("1½ cups milk")["grams"], 1.5 * 243.7, delta=1)

    def test_sizes_and_items(self):
        self.assertAlmostEqual(line("2 large eggs")["grams"], 100)
        self.assertAlmostEqual(line("1 small onion")["grams"], 90)
        self.assertAlmostEqual(line("1 large onion")["grams"], 220)
        self.assertAlmostEqual(line("3 garlic cloves, crushed")["grams"], 12)
        self.assertAlmostEqual(line("3 rashers bacon")["grams"], 90)

    def test_cooked_and_dry(self):
        self.assertEqual(line("1 cup cooked rice")["food"], "cooked rice")
        self.assertAlmostEqual(line("1 cup cooked rice")["grams"], 160)
        self.assertEqual(line("1 cup basmati rice")["food"], "rice")
        self.assertEqual(line("400g canned lentils")["food"], "cooked lentils")
        self.assertEqual(line("200g dried chickpeas")["food"], "dried chickpeas")

    def test_negligible_and_serving_lines(self):
        for text in ("Salt and pepper, to taste", "1 tsp ground cumin", "2 bay leaves", "1 tsp baking powder",
                     "1 cup water", "1 chicken stock cube", "2 tsp vanilla extract", "Fresh coriander, to serve"):
            self.assertEqual(line(text)["status"], "negligible", text)
        self.assertEqual(line("1/2 cup walnuts (optional)")["status"], "negligible")
        self.assertIsNone(line("1/2 cup walnuts (optional)")["kcal"])
        self.assertEqual(line("Oil, for deep frying")["status"], "negligible")
        self.assertEqual(line("2 tbsp olive oil")["status"], "matched")

    def test_juice_of(self):
        r = line("Juice of 1 lemon")
        self.assertEqual(r["food"], "lemon juice")
        self.assertAlmostEqual(r["grams"], 45)

    def test_unknown_line(self):
        r = line("1 packet mystery seasoning blend thing")
        self.assertIn(r["status"], ("negligible", "unmatched"))
        self.assertEqual(line("3 widgets")["status"], "unmatched")


class Coverage(unittest.TestCase):
    def test_spices_do_not_count_against_coverage(self):
        text = "500g beef mince\n1 onion\n1 tsp cumin\n1 tsp paprika\n1 tsp oregano\nSalt\nPepper"
        d = n.estimate_detail(text)
        self.assertEqual(d["counted_lines"], 2)
        self.assertEqual(d["matched"], 2)
        self.assertEqual(d["confidence"], "high")
        legacy = n.estimate_recipe(text, "4")
        self.assertEqual(legacy["matched"], 7)
        self.assertEqual(legacy["total_lines"], 7)

    def test_no_estimate_under_half(self):
        self.assertIsNone(n.estimate_detail("3 widgets\n2 gizmos\n1 onion"))
        self.assertIsNone(n.estimate_recipe("3 widgets\n2 gizmos\n1 onion", "2"))
        self.assertIsNone(n.estimate_detail("Salt\nPepper"))  # nothing countable

    def test_confidence_drops_without_quantities(self):
        d = n.estimate_detail("2 chicken thigh fillets\n1 tbsp butter\n2 cups rice\nonion")
        self.assertEqual(d["confidence"], "medium")  # 3 with a quantity of 4 counted -> 75%
        d = n.estimate_detail("butter\nmilk\n2 cups rice")
        self.assertEqual(d["confidence"], "low")

    def test_headings_are_skipped(self):
        d = n.estimate_detail("# Base\n1 onion\nFor the sauce:\n1 cup milk")
        self.assertEqual(d["total_lines"], 2)


class Servings(unittest.TestCase):
    def test_parse(self):
        self.assertEqual(n.parse_servings("Serves 4-6"), (4, "serving"))
        self.assertEqual(n.parse_servings("Makes 12 cookies"), (12, "cookies"))
        self.assertEqual(n.parse_servings("4 servings"), (4, "serving"))
        self.assertEqual(n.parse_servings("1"), (1, "serving"))
        self.assertEqual(n.parse_servings("Makes 1 loaf"), (1, "loaf"))
        self.assertEqual(n.parse_servings("Makes about 24 small biscuits"), (24, "biscuits"))
        self.assertEqual(n.parse_servings("4 (as a main)"), (4, "serving"))
        self.assertEqual(n.parse_servings("6 people"), (6, "serving"))
        self.assertEqual(n.parse_servings("serves four"), (4, "serving"))
        self.assertEqual(n.parse_servings(""), (None, "serving"))
        self.assertEqual(n.parse_servings("a few"), (None, "serving"))

    def test_singular(self):
        self.assertEqual(n.yield_singular("cookies"), "cookie")
        self.assertEqual(n.yield_singular("loaves"), "loaf")
        self.assertEqual(n.yield_singular("muffins"), "muffin")
        self.assertEqual(n.yield_singular("brownies"), "brownie")
        self.assertEqual(n.yield_singular("patties"), "patty")
        self.assertEqual(n.yield_singular("serving"), "serving")

    def test_one_serving_still_gets_per_serving(self):
        r = n.estimate_recipe("2 eggs\n1 tbsp butter", "1")
        self.assertIsNotNone(r["per_serving"])
        self.assertEqual(r["per_serving"]["kcal"], r["kcal"])


class SourceNutrition(unittest.TestCase):
    def test_calorie_strings(self):
        p = n.parse_source_nutrition
        self.assertEqual(p({"calories": "350 kcal"})["kcal"], 350)
        self.assertEqual(p({"calories": "350 calories"})["kcal"], 350)
        self.assertEqual(p({"calories": "350"})["kcal"], 350)
        self.assertEqual(p({"calories": 350})["kcal"], 350)
        self.assertEqual(p({"calories": "1,250 Calories"})["kcal"], 1250)
        self.assertEqual(p({"calories": "1464 kJ"})["kcal"], 350)
        self.assertEqual(p({"calories": "1464 kJ (350 kcal)"})["kcal"], 350)

    def test_macros_and_size(self):
        r = n.parse_source_nutrition({"@type": "NutritionInformation", "calories": "420 kcal",
                                      "proteinContent": "25 g", "fatContent": "12.5g",
                                      "carbohydrateContent": "48 grams", "servingSize": "1 bowl"})
        self.assertEqual(r, {"kcal": 420, "protein": 25.0, "fat": 12.5, "carbs": 48.0, "serving_size": "1 bowl"})
        self.assertEqual(n.parse_source_nutrition([{"calories": "100"}])["kcal"], 100)
        self.assertEqual(n.parse_source_nutrition('{"kcal": 90, "protein": 3}')["protein"], 3.0)

    def test_rejects_nonsense(self):
        self.assertIsNone(n.parse_source_nutrition(None))
        self.assertIsNone(n.parse_source_nutrition({}))
        self.assertIsNone(n.parse_source_nutrition({"calories": "lots"}))
        self.assertIsNone(n.parse_source_nutrition("not json"))
        self.assertIsNone(n.parse_source_nutrition({"calories": "99999 kcal"}))

    def test_scraper_reads_json_ld_nutrition(self):
        import scraper
        ld = {"@type": "Recipe", "name": "Soup", "recipeIngredient": ["1 onion"], "recipeInstructions": "Cook.",
              "recipeYield": "4", "nutrition": {"@type": "NutritionInformation", "calories": "350 calories",
                                                "proteinContent": "12 g"}}
        html = f'<html><head><script type="application/ld+json">{json.dumps(ld)}</script></head></html>'
        with mock.patch.object(scraper, "safe_get", return_value=types.SimpleNamespace(text=html)):
            r = scraper.scrape_recipe("https://example.com/soup")
        self.assertEqual(r["source_nutrition"]["kcal"], 350)
        self.assertEqual(r["source_nutrition"]["protein"], 12.0)

    def test_scraper_reads_microdata_nutrition(self):
        import scraper
        html = ('<html><body><div itemscope itemtype="https://schema.org/Recipe"><h1 itemprop="name">Cake</h1>'
                '<span itemprop="recipeIngredient">1 cup flour</span>'
                '<div itemprop="nutrition" itemscope itemtype="https://schema.org/NutritionInformation">'
                '<span itemprop="calories">240 kcal</span><span itemprop="fatContent">9 g</span></div>'
                '</div></body></html>')
        with mock.patch.object(scraper, "safe_get", return_value=types.SimpleNamespace(text=html)):
            r = scraper.scrape_recipe("https://example.com/cake")
        self.assertEqual(r["source_nutrition"]["kcal"], 240)
        self.assertEqual(r["source_nutrition"]["fat"], 9.0)

    def test_parse_calories_input(self):
        self.assertEqual(n.parse_calories(""), (True, None))
        self.assertEqual(n.parse_calories(None), (True, None))
        self.assertEqual(n.parse_calories("450"), (True, 450))
        self.assertEqual(n.parse_calories("450 kcal"), (True, 450))
        self.assertEqual(n.parse_calories(450.4), (True, 450))
        self.assertEqual(n.parse_calories("-5"), (False, None))
        self.assertEqual(n.parse_calories("lots"), (False, None))
        self.assertEqual(n.parse_calories(True), (False, None))


class Precedence(unittest.TestCase):
    ING = "500g beef mince\n1 onion\n400g spaghetti"

    def test_estimate(self):
        f = n.nutrition_facts(self.ING, "Serves 4")
        self.assertEqual(f["source"], "estimate")
        self.assertEqual(f["total"]["kcal"], f["estimate"]["kcal"])
        self.assertEqual(f["per_serving"]["kcal"], round(f["estimate"]["kcal"] / 4))
        f = n.nutrition_facts(self.ING, "")
        self.assertIsNone(f["servings"])
        self.assertIsNone(f["per_serving"])
        self.assertIsNotNone(f["total"])

    def test_recipe_source_beats_estimate(self):
        src = json.dumps({"kcal": 600, "protein": 30, "fat": None, "carbs": 70, "serving_size": None})
        f = n.nutrition_facts(self.ING, "4", source_nutrition=src)
        self.assertEqual(f["source"], "recipe")
        self.assertEqual(f["per_serving"], {"kcal": 600, "protein": 30.0, "fat": None, "carbs": 70.0})
        self.assertEqual(f["total"], {"kcal": 2400, "protein": 120.0, "fat": None, "carbs": 280.0})
        self.assertIsNotNone(f["estimate"])
        self.assertIsNone(n.nutrition_facts(self.ING, "", source_nutrition=src)["total"])

    def test_manual_beats_everything(self):
        src = {"kcal": 600, "protein": 30, "fat": 20, "carbs": 70}
        f = n.nutrition_facts(self.ING, "Makes 12 cookies", calories_per_serving=150, source_nutrition=src)
        self.assertEqual(f["source"], "manual")
        self.assertEqual(f["yield_unit"], "cookies")
        self.assertEqual(f["per_serving"], {"kcal": 150, "protein": 30.0, "fat": 20.0, "carbs": 70.0})
        self.assertEqual(f["total"]["kcal"], 1800)
        # No source: macros from the estimate per serving.
        f = n.nutrition_facts(self.ING, "4", calories_per_serving=500)
        self.assertEqual(f["per_serving"]["protein"], round(f["estimate"]["protein"] / 4, 1))
        # Nothing to estimate from: macros stay null.
        f = n.nutrition_facts("3 widgets", "", calories_per_serving=500)
        self.assertEqual(f["per_serving"], {"kcal": 500, "protein": None, "fat": None, "carbs": None})
        self.assertIsNone(f["total"])
        self.assertIsNone(f["estimate"])
        self.assertEqual(n.nutrition_facts("3 widgets", "", calories_per_serving=0)["per_serving"]["kcal"], 0)

    def test_nothing(self):
        self.assertIsNone(n.nutrition_facts("3 widgets\n2 gizmos", "4"))
        self.assertIsNone(n.nutrition_facts("", ""))


class WholeRecipes(unittest.TestCase):
    """Realistic recipes against hand-worked USDA totals."""

    def check(self, text, servings, expected):
        r = n.estimate_recipe(text, servings)
        self.assertIsNotNone(r)
        self.assertAlmostEqual(r["kcal"], expected, delta=expected * TOL, msg=f"{r['kcal']} vs {expected}")
        return r

    def test_banana_bread(self):
        # bananas 3 x 118 g x 89 = 315; butter 1/3 cup 75.7 g x 717 = 543; brown sugar 3/4 cup 160 g x 380 = 608;
        # egg 50 g x 143 = 72; plain flour 1 1/2 cups 180 g x 364 = 655; vanilla ~12; soda, salt ~0  => ~2205
        r = self.check("3 ripe bananas, mashed\n1/3 cup melted butter\n3/4 cup brown sugar\n1 egg, beaten\n"
                       "1 tsp vanilla extract\n1 tsp bicarbonate of soda\nPinch of salt\n1 1/2 cups plain flour",
                       "Makes 1 loaf", 2205)
        self.assertEqual(r["servings"], 1)

    def test_bolognese(self):
        # olive oil 27 g x 884 = 239; onion 150 g x 40 = 60; garlic 8 g = 12; carrot 80 g = 33; celery 40 g = 6;
        # beef mince 85% lean 500 g x 215 = 1075; canned tomatoes 800 g x 24 = 192; tomato paste 33 g = 27;
        # stock 240 g = 14; spaghetti dry 400 g x 371 = 1484  => ~3142 (old estimate: 3640)
        r = self.check("2 tbsp olive oil\n1 brown onion, finely chopped\n2 garlic cloves, crushed\n1 carrot, grated\n"
                       "1 celery stick, finely chopped\n500g beef mince\n2 x 400g cans diced tomatoes\n"
                       "2 tbsp tomato paste\n1 cup beef stock\n1 tsp dried oregano\nSalt and pepper, to taste\n"
                       "400g spaghetti\nGrated parmesan, to serve", "Serves 4", 3142)
        self.assertEqual(r["per_serving"]["kcal"], round(r["kcal"] / 4))

    def test_thai_curry(self):
        # oil 13.6 g = 120; onion 60; garlic 12 g = 18; ginger 6 g = 5; red curry paste 48 g x 130 = 62;
        # chicken thigh 600 g x 121 = 726; coconut milk 400 ml x 0.98 = 392 g x 197 = 772; fish sauce 6;
        # brown sugar 13.3 g = 51; capsicum 150 g = 42; baby spinach 60 g = 14; jasmine rice dry 285 g x 365 = 1040
        # => ~2916 (old estimate: 3208)
        self.check("1 tbsp vegetable oil\n1 onion, diced\n3 cloves garlic, minced\n1 tbsp grated ginger\n"
                   "3 tbsp red curry paste\n600g chicken thigh fillets, cut into pieces\n1 x 400ml can coconut milk\n"
                   "1 tbsp fish sauce\n1 tbsp brown sugar\n1 red capsicum, sliced\n2 cups baby spinach\n"
                   "1 1/2 cups jasmine rice, to serve\nCoriander leaves, to garnish", "Serves 4", 2916)

    def test_choc_chip_cookies(self):
        # flour 2 1/4 cups 270 g x 364 = 983; butter 1 cup 227 g x 717 = 1628; sugar 150 g x 387 = 581;
        # brown sugar 160 g x 380 = 608; eggs 2 x 50 g = 143; chocolate chips 2 cups 340 g x 546 = 1856;
        # vanilla 12; walnuts optional, left out  => ~5811, 121 a cookie (old estimate: 9415)
        r = self.check("2 1/4 cups all-purpose flour\n1 tsp baking soda\n1 tsp salt\n1 cup (2 sticks) butter, softened\n"
                       "3/4 cup granulated sugar\n3/4 cup packed brown sugar\n1 tsp vanilla extract\n2 large eggs\n"
                       "2 cups chocolate chips\n1 cup chopped walnuts (optional)", "Makes 48 cookies", 5811)
        self.assertAlmostEqual(r["per_serving"]["kcal"], 121, delta=10)
        f = n.nutrition_facts("2 1/4 cups all-purpose flour\n1 cup butter", "Makes 48 cookies")
        self.assertEqual(f["yield_unit"], "cookies")

    def test_lentil_soup(self):
        # oil 120; onion 60; carrots 2 x 80 g = 66; celery 80 g = 11; garlic 12; cumin 7;
        # red lentils dry 1 cup 192-200 g x 352 = 676-704; tomatoes 400 g = 96; stock 1 L = 60; lemon juice 22 g = 5
        # => ~1130 (old estimate: 640, it read the lentils as cooked)
        self.check("1 tbsp olive oil\n1 onion, chopped\n2 carrots, diced\n2 celery stalks, diced\n"
                   "2 cloves garlic, crushed\n1 tsp ground cumin\n1 cup dried red lentils\n"
                   "1 x 400g tin chopped tomatoes\n1 litre vegetable stock\nJuice of 1/2 lemon\n"
                   "Handful of parsley, chopped", "Serves 4", 1130)


class Data(unittest.TestCase):
    def test_food_table(self):
        with open(n._FOODS_PATH, encoding="utf-8") as f:
            doc = json.load(f)
        self.assertIn("USDA", doc["about"])
        self.assertGreaterEqual(len(doc["foods"]), 250)
        names = {food["name"] for food in doc["foods"]}
        for food in doc["foods"]:
            for key in ("kcal", "protein", "fat", "carbs"):
                self.assertIsInstance(food[key], (int, float), food["name"])
            # Energy should roughly agree with the macros (4/9/4). Alcohol and very high fibre
            # (cocoa, dried spices) are the known exceptions.
            atwater = 4 * food["protein"] + 9 * food["fat"] + 4 * food["carbs"]
            if food["kcal"] > 50 and not food.get("negligible") and food["name"] not in (
                    "spirits", "fortified wine", "wine", "beer", "mirin", "cocoa powder"):
                self.assertLess(abs(atwater - food["kcal"]) / food["kcal"], 0.3, food["name"])
            for key in ("cooked", "canned", "dried", "skin_on", "count_as"):
                if key in food:
                    self.assertIn(food[key], names, f"{food['name']}.{key}")


if __name__ == "__main__":
    unittest.main()
