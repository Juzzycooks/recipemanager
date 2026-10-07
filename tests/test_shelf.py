import json
import os
import shutil
import sys
import tempfile
import time
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class ShelfTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        os.environ["DATA_DIR"] = self.tmp
        from app import create_app
        from models import db, User
        self.app = create_app()
        self.app.config["WTF_CSRF_ENABLED"] = False
        self.db = db
        with self.app.app_context():
            for name, admin in (("alice", True), ("bob", False), ("carol", False)):
                u = User(username=name, is_admin=admin)
                u.set_password("pw12345678")
                db.session.add(u)
            db.session.commit()
            self.uid = {u.username: u.id for u in User.query.all()}
        self.client = self.app.test_client()
        self.login(self.client, "bob")

    def tearDown(self):
        with self.app.app_context():
            self.db.session.remove()
            self.db.engine.dispose()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def login(self, client, name):
        r = client.post("/login", data={"username": name, "password": "pw12345678"})
        self.assertIn(r.status_code, (302, 200))

    def make(self, title, ingredients="1 egg", cats=(), user="bob", image=""):
        from models import Recipe, Category
        with self.app.app_context():
            r = Recipe(title=title, ingredients=ingredients, instructions="Cook.", user_id=self.uid[user], image_url=image)
            for c in cats:
                cat = Category.query.filter_by(name=c).first() or Category(name=c)
                r.categories.append(cat)
            self.db.session.add(r)
            self.db.session.commit()
            return r.id


class FirstRunTests(ShelfTestCase):
    def test_welcome_and_tour(self):
        html = self.client.get("/").get_data(as_text=True)
        self.assertIn("Welcome to your recipe shelf", html)
        self.assertIn("Quick tour", html)
        self.assertNotIn('style="', html)

    def test_compact_tour_with_few_recipes(self):
        self.make("One")
        html = self.client.get("/").get_data(as_text=True)
        self.assertNotIn("Welcome to your recipe shelf", html)
        self.assertIn("tour-compact", html)


class FavoriteTests(ShelfTestCase):
    def test_fetch_gets_json(self):
        rid = self.make("Soup")
        r = self.client.post(f"/recipe/{rid}/favorite", headers={"X-Requested-With": "fetch"})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.get_json(), {"favorited": True})
        r = self.client.post(f"/recipe/{rid}/favorite", headers={"Accept": "application/json"})
        self.assertEqual(r.get_json(), {"favorited": False})

    def test_plain_post_redirects(self):
        rid = self.make("Soup")
        r = self.client.post(f"/recipe/{rid}/favorite")
        self.assertEqual(r.status_code, 302)

    def test_card_renders_heart_form(self):
        rid = self.make("Soup")
        html = self.client.get("/").get_data(as_text=True)
        self.assertIn(f"/recipe/{rid}/favorite", html)
        self.assertIn('aria-label="Add Soup to favorites"', html)


class FilterTests(ShelfTestCase):
    def test_multi_category_all_semantics_and_legacy(self):
        from models import Category
        self.make("OnlyA", cats=["A"])
        self.make("AandB", cats=["A", "B"])
        self.make("OnlyB", cats=["B"])
        with self.app.app_context():
            a = Category.query.filter_by(name="A").first().id
            b = Category.query.filter_by(name="B").first().id
        both = self.client.get(f"/?cat={a}&cat={b}").get_data(as_text=True)
        self.assertIn("AandB", both)
        self.assertNotIn("OnlyA", both)
        self.assertNotIn("OnlyB", both)
        legacy = self.client.get(f"/?cat={a}").get_data(as_text=True)
        self.assertIn("OnlyA", legacy)
        self.assertIn("AandB", legacy)
        self.assertNotIn("OnlyB", legacy)

    def test_zero_results_offers_recovery(self):
        from models import Category
        self.make("Pie", cats=["A"])
        self.make("Stew", cats=["B"])
        with self.app.app_context():
            b = Category.query.filter_by(name="B").first().id
        html = self.client.get(f"/?q=Pie&cat={b}").get_data(as_text=True)
        self.assertIn("Search all recipes for", html)
        self.assertIn("Clear filters", html)


class MatchLineTests(ShelfTestCase):
    def test_ingredient_match_line_escaped(self):
        self.make("Bread", ingredients="# Dough\n2 cups plain <b>flour</b>\n1 tsp salt")
        html = self.client.get("/?q=flour").get_data(as_text=True)
        self.assertIn("Contains:", html)
        self.assertIn("<mark>flour</mark>", html)
        self.assertIn("2 cups plain &lt;b&gt;", html)
        self.assertNotIn("<b>flour</b>", html)

    def test_no_line_when_title_matches_and_headings_skipped(self):
        self.make("Flour cake", ingredients="1 cup flour")
        html = self.client.get("/?q=flour").get_data(as_text=True)
        self.assertNotIn("Contains:", html)
        self.make("Cake2", ingredients="# Flour mix\n1 egg")
        html = self.client.get("/?q=nothingmatches").get_data(as_text=True)
        self.assertNotIn("Contains:", html)

    def test_legacy_ingredient_param(self):
        self.make("Loaf", ingredients="3 cups rye")
        html = self.client.get("/?ingredient=rye").get_data(as_text=True)
        self.assertIn("<mark>rye</mark>", html)


class RecentlyCookedTests(ShelfTestCase):
    def test_order_and_distinct(self):
        from models import CookLog
        ids = [self.make(f"R{i}") for i in range(8)]
        now = datetime.now(timezone.utc)
        with self.app.app_context():
            for n, rid in enumerate(ids):
                self.db.session.add(CookLog(user_id=self.uid["bob"], recipe_id=rid, cooked_at=now - timedelta(days=10 - n)))
            # ids[0] cooked again most recently
            self.db.session.add(CookLog(user_id=self.uid["bob"], recipe_id=ids[0], cooked_at=now))
            self.db.session.add(CookLog(user_id=self.uid["carol"], recipe_id=ids[1], cooked_at=now))
            self.db.session.commit()
        from routes.recipes import _recently_cooked
        with self.app.app_context():
            got = _recently_cooked(self.uid["bob"])
        titles = [r.title for r, _ in got]
        self.assertEqual(titles, ["R0", "R7", "R6", "R5", "R4", "R3"])
        self.assertEqual(got[0][1], "today")
        html = self.client.get("/").get_data(as_text=True)
        self.assertIn("Recently cooked", html)

    def test_hidden_when_empty(self):
        self.make("R")
        self.assertNotIn("Recently cooked", self.client.get("/").get_data(as_text=True))


class TrashTests(ShelfTestCase):
    def upload(self, name):
        d = os.path.join(self.tmp, "uploads")
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, name)
        with open(path, "wb") as f:
            f.write(b"x")
        return path

    def trash_files(self):
        d = os.path.join(self.tmp, "trash")
        return [f for f in os.listdir(d)] if os.path.isdir(d) else []

    def delete(self, rid):
        r = self.client.post(f"/recipe/{rid}/delete", follow_redirects=False)
        self.assertEqual(r.status_code, 302)
        with self.client.session_transaction() as s:
            flashes = s.get("_flashes", [])
        self.assertEqual(flashes[-1][0], "undo")
        msg, token = flashes[-1][1].rsplit("|", 1)
        return msg, token

    def test_delete_keeps_image_and_writes_trash(self):
        img = self.upload("recipe_abc.jpg")
        rid = self.make("Tart", cats=["Dessert"], image="recipe_abc.jpg")
        msg, token = self.delete(rid)
        self.assertIn("Tart", msg)
        self.assertTrue(os.path.exists(img))
        self.assertEqual(self.trash_files(), [token + ".json"])
        from models import Recipe
        with self.app.app_context():
            self.assertIsNone(self.db.session.get(Recipe, rid))

    def test_restore_recreates_with_categories(self):
        rid = self.make("Tart", cats=["Dessert", "Baking"])
        _, token = self.delete(rid)
        r = self.client.post(f"/recipe/restore/{token}")
        self.assertEqual(r.status_code, 302)
        from models import Recipe
        with self.app.app_context():
            rec = Recipe.query.filter_by(title="Tart").one()
            self.assertEqual(sorted(c.name for c in rec.categories), ["Baking", "Dessert"])
            self.assertEqual(rec.user_id, self.uid["bob"])
        self.assertEqual(self.trash_files(), [])

    def test_restore_denied_for_other_user_allowed_for_admin(self):
        rid = self.make("Tart")
        _, token = self.delete(rid)
        other = self.app.test_client()
        self.login(other, "carol")
        other.post(f"/recipe/restore/{token}")
        self.assertEqual(self.trash_files(), [token + ".json"])
        admin = self.app.test_client()
        self.login(admin, "alice")
        admin.post(f"/recipe/restore/{token}")
        self.assertEqual(self.trash_files(), [])

    def test_bad_and_expired_tokens(self):
        for bad in ("short", "..%2F..%2Fetc", "a" * 40, "abc$defgh"):
            r = self.client.post(f"/recipe/restore/{bad}")
            self.assertIn(r.status_code, (302, 404))
        r = self.client.post("/recipe/restore/abcdefgh12345678")
        self.assertEqual(r.status_code, 302)
        # expired entry
        d = os.path.join(self.tmp, "trash")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "oldoldold1234.json"), "w") as f:
            json.dump({"deleted_by": self.uid["bob"], "deleted_at": time.time() - 90000,
                       "recipe": {"title": "Old", "ingredients": "x", "instructions": "y", "user_id": self.uid["bob"]}}, f)
        self.client.post("/recipe/restore/oldoldold1234")
        from models import Recipe
        with self.app.app_context():
            self.assertEqual(Recipe.query.filter_by(title="Old").count(), 0)

    def test_purge_removes_old_entries_and_images(self):
        img = self.upload("recipe_old.jpg")
        d = os.path.join(self.tmp, "trash")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "oldoldold1234.json"), "w") as f:
            json.dump({"deleted_by": self.uid["bob"], "deleted_at": time.time() - 90000,
                       "recipe": {"title": "Old", "image_url": "recipe_old.jpg"}}, f)
        rid = self.make("Other")
        self.delete(rid)
        self.assertFalse(os.path.exists(img))
        self.assertNotIn("oldoldold1234.json", self.trash_files())


if __name__ == "__main__":
    unittest.main()


class EditImageTests(ShelfTestCase):
    def edit(self, rid, **extra):
        data = {"title": "Soup", "ingredients": "1 egg", "instructions": "Cook.", "image_url": "", **extra}
        return self.client.post(f"/recipe/{rid}/edit", data=data)

    def image(self, rid):
        from models import Recipe
        with self.app.app_context():
            return self.db.session.get(Recipe, rid).image_url

    def test_edit_keeps_uploaded_picture(self):
        rid = self.make("Soup", image="recipe_abc.jpg")
        self.assertEqual(self.edit(rid).status_code, 302)
        self.assertEqual(self.image(rid), "recipe_abc.jpg")

    def test_edit_keeps_linked_picture_and_can_replace_it(self):
        rid = self.make("Soup", image="https://example.com/a.jpg")
        self.edit(rid, image_url="https://example.com/a.jpg")
        self.assertEqual(self.image(rid), "https://example.com/a.jpg")
        self.edit(rid, image_url="https://example.com/b.jpg")
        self.assertEqual(self.image(rid), "https://example.com/b.jpg")

    def test_remove_picture(self):
        rid = self.make("Soup", image="recipe_abc.jpg")
        self.edit(rid, remove_image="1")
        self.assertEqual(self.image(rid), "")
