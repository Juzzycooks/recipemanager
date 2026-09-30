import os, sys, tempfile, unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ["DATA_DIR"] = tempfile.mkdtemp()

from app import create_app
from models import db, User, Recipe

PARSED = {
    "title": "Lemon Pasta", "description": "Bright and quick.",
    "ingredients": "# Pasta\n200g spaghetti\n1 lemon\n# Sauce\n2 tbsp butter",
    "instructions": "Boil the pasta.\nToss with butter and lemon.",
    "notes": "Keeps 2 days.", "servings": "2", "prep_time": "5 min", "cook_time": "10 min",
    "image_url": "", "source_type": "web",
}


class ImportFlow(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config["WTF_CSRF_ENABLED"] = False
        cls.app.testing = True
        with cls.app.app_context():
            u = User(username="cook", email="c@example.com")
            u.set_password("Sup3r-secret-pass!")
            db.session.add(u)
            db.session.commit()

    def setUp(self):
        self.c = self.app.test_client()
        r = self.c.post("/login", data={"username": "cook", "password": "Sup3r-secret-pass!"})
        self.assertIn(r.status_code, (200, 302))
        with self.app.app_context():
            Recipe.query.delete()
            db.session.commit()

    def count(self):
        with self.app.app_context():
            return Recipe.query.count()

    def test_single_url_renders_preview_without_saving(self):
        with mock.patch("routes.recipes.scrape_recipe", return_value=dict(PARSED)):
            r = self.c.post("/recipe/import", data={"urls": "https://example.com/pasta"})
        self.assertEqual(r.status_code, 200)
        body = r.get_data(as_text=True)
        self.assertIn("Check what we found", body)
        self.assertIn("Lemon Pasta", body)
        self.assertIn("200g spaghetti", body)
        self.assertIn("https://example.com/pasta", body)
        self.assertEqual(self.count(), 0)

    def test_thin_parse_shows_warning(self):
        thin = dict(PARSED, ingredients="")
        with mock.patch("routes.recipes.scrape_recipe", return_value=thin):
            r = self.c.post("/recipe/import", data={"urls": "https://example.com/x"})
        self.assertIn("We found the method but no ingredients", r.get_data(as_text=True))

    def test_caption_preview_has_original_text(self):
        cap = "Toast\nIngredients:\n2 slices bread\n1 tbsp butter\nMethod:\nToast the bread and butter it."
        r = self.c.post("/recipe/import-caption", data={"caption": cap})
        body = r.get_data(as_text=True)
        self.assertEqual(r.status_code, 200)
        self.assertIn("Show the original text", body)
        self.assertEqual(self.count(), 0)

    def test_photo_preview(self):
        import io
        text = "Toast\nIngredients:\n2 slices bread\n1 tbsp butter\nMethod:\nToast the bread and butter it."
        with mock.patch("routes.recipes.images_to_text", return_value=text):
            r = self.c.post("/recipe/import-photo", data={"photos": (io.BytesIO(b"x"), "a.png")},
                            content_type="multipart/form-data")
        self.assertEqual(r.status_code, 200)
        self.assertIn("2 slices bread", r.get_data(as_text=True))
        self.assertEqual(self.count(), 0)

    def test_save_creates_recipe_with_all_fields(self):
        data = {k: PARSED[k] for k in ("title", "description", "ingredients", "instructions", "notes",
                                        "servings", "prep_time", "cook_time")}
        data.update(source_url="https://example.com/pasta", image_name="", kind="url")
        r = self.c.post("/recipe/import-save", data=data)
        self.assertEqual(r.status_code, 302)
        with self.app.app_context():
            rec = Recipe.query.one()
            self.assertEqual(rec.notes, "Keeps 2 days.")
            self.assertEqual(rec.servings, "2")
            self.assertIn("# Pasta", rec.ingredients)
            self.assertIn("# Sauce", rec.ingredients)
            self.assertEqual(rec.source_url, "https://example.com/pasta")

    def test_save_without_title_rerenders_and_preserves_text(self):
        r = self.c.post("/recipe/import-save", data={
            "title": "  ", "ingredients": "1 egg\n2 cups flour", "instructions": "Whisk.", "notes": "My note"})
        body = r.get_data(as_text=True)
        self.assertGreaterEqual(r.status_code, 400)
        self.assertIn("Give the recipe a title", body)
        self.assertIn("2 cups flour", body)
        self.assertIn("My note", body)
        self.assertEqual(self.count(), 0)

    def test_bulk_urls_still_save_immediately(self):
        with mock.patch("routes.recipes.scrape_recipe", return_value=dict(PARSED)):
            r = self.c.post("/recipe/import", data={"urls": "https://a.example/1\nhttps://b.example/2"})
        self.assertEqual(r.status_code, 302)
        self.assertEqual(self.count(), 2)


if __name__ == "__main__":
    unittest.main()
