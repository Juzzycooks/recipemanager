import json, os, sys, types, unittest
from unittest import mock
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import scraper


def page(ld, body=""):
    return f'<html><head><script type="application/ld+json">{json.dumps(ld)}</script></head><body>{body}</body></html>'


def fake(html):
    return mock.patch.object(scraper, "safe_get", return_value=types.SimpleNamespace(text=html))


class JsonLd(unittest.TestCase):
    def test_entities_and_tags_are_cleaned(self):
        ld = {"@type": "Recipe", "name": "Mac &amp; Cheese", "description": "Rich &#8211; and <b>creamy</b>",
              "recipeIngredient": ["1&nbsp;cup macaroni", "2 tbsp butter &amp; more"],
              "recipeInstructions": [{"@type": "HowToStep", "text": "Boil &amp; drain."}], "recipeYield": ["4", "4 servings"]}
        with fake(page(ld)):
            r = scraper.scrape_recipe("https://example.com/r")
        self.assertEqual(r["title"], "Mac & Cheese")
        self.assertEqual(r["ingredients"].split("\n"), ["1 cup macaroni", "2 tbsp butter & more"])
        self.assertEqual(r["instructions"], "Boil & drain.")
        self.assertIn("creamy", r["description"]); self.assertNotIn("<b>", r["description"])

    def test_howto_sections_become_headings(self):
        ld = {"@type": "Recipe", "name": "Cake", "recipeIngredient": ["flour"],
              "recipeInstructions": [{"@type": "HowToSection", "name": "Cake", "itemListElement": [{"@type": "HowToStep", "text": "Bake."}]},
                                     {"@type": "HowToSection", "name": "Icing", "itemListElement": [{"@type": "HowToStep", "text": "Whip."}]}]}
        with fake(page(ld)):
            r = scraper.scrape_recipe("https://example.com/r")
        self.assertEqual(r["instructions"].split("\n"), ["# Cake", "Bake.", "# Icing", "Whip."])

    def test_tasty_recipes_groups_and_notes(self):
        body = ('<div class="tasty-recipes-ingredients"><h4>Ingredients</h4>'
                '<h4>For the cake</h4><ul><li>2 cups flour</li><li>1 egg</li></ul>'
                '<h4>For the icing</h4><ul><li>1 cup sugar</li></ul></div>'
                '<div class="tasty-recipes-notes"><ul><li>Keeps 3 days.</li><li>Freezes well.</li></ul></div>')
        ld = {"@type": "Recipe", "name": "Cake", "recipeIngredient": ["2 cups flour", "1 egg", "1 cup sugar"], "recipeInstructions": "Bake."}
        with fake(page(ld, body)):
            r = scraper.scrape_recipe("https://example.com/r")
        self.assertEqual(r["ingredients"].split("\n"), ["# For the cake", "2 cups flour", "1 egg", "# For the icing", "1 cup sugar"])
        self.assertEqual(r["notes"].split("\n"), ["Keeps 3 days.", "Freezes well."])

    def test_mediavine_create_groups_and_notes(self):
        body = ('<div class="mv-create-ingredients"><h3>Ingredients</h3><h4>Dough</h4><ul><li>500 g flour</li></ul>'
                '<h4>Filling</h4><ul><li>200 g cheese</li></ul></div>'
                '<div class="mv-create-notes"><div class="mv-create-notes-content"><p>Use strong flour.</p></div></div>')
        ld = {"@type": "Recipe", "name": "Pie", "recipeIngredient": ["500 g flour", "200 g cheese"], "recipeInstructions": "Bake."}
        with fake(page(ld, body)):
            r = scraper.scrape_recipe("https://example.com/r")
        self.assertIn("# Dough", r["ingredients"]); self.assertIn("# Filling", r["ingredients"])
        self.assertEqual(r["notes"], "Use strong flour.")


class Instagram(unittest.TestCase):
    def test_embed_caption_is_used_and_parsed(self):
        embed = ('<html><body><div class="Caption"><a class="CaptionUsername">chef</a>'
                 'Garlic Butter Prawns 🍤<br/><br/>Serves 2<br/>INGREDIENTS<br/>300 g prawns<br/>3 cloves garlic<br/>'
                 'METHOD<br/>1. Melt the butter.<br/>2. Fry the prawns.<br/>Tip: serve with lemon.'
                 '<div class="CaptionComments">12 comments</div></div><img class="EmbeddedMediaImage" src="https://cdn/x.jpg"></body></html>')
        def get(url, **kw):
            return types.SimpleNamespace(text=embed if "/embed/" in url else "<html><title>Instagram</title></html>")
        with mock.patch.object(scraper, "safe_get", side_effect=get):
            r = scraper.scrape_recipe("https://www.instagram.com/reel/ABC123/?igsh=xyz")
        self.assertEqual(r["title"], "Garlic Butter Prawns 🍤")
        self.assertEqual(r["ingredients"].split("\n"), ["300 g prawns", "3 cloves garlic"])
        self.assertEqual(r["instructions"].split("\n"), ["Melt the butter.", "Fry the prawns."])
        self.assertEqual(r["servings"], "2")
        self.assertEqual(r["image_url"], "https://cdn/x.jpg")
        self.assertTrue(r["caption_found"])

    def test_login_shell_reports_no_caption(self):
        with mock.patch.object(scraper, "safe_get", return_value=types.SimpleNamespace(text="<html><title>Instagram</title></html>")):
            r = scraper.scrape_recipe("https://www.instagram.com/p/XYZ/")
        self.assertFalse(r["caption_found"]); self.assertEqual(r["ingredients"], "")


if __name__ == "__main__":
    unittest.main()
