import os, sys, tempfile, unittest
from datetime import date

os.environ["DATA_DIR"] = tempfile.mkdtemp()
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app import create_app
from models import db, User, Recipe, ShoppingListItem, SiteSetting, MealPlan, Collection

app = create_app()
app.config["WTF_CSRF_ENABLED"] = False
app.testing = True
PW = "Sup3r-secret-pass!"


def setting(key, value):
    with app.app_context():
        _setting(key, value)


def _setting(key, value):
    row = SiteSetting.query.filter_by(key=key).first()
    if row:
        row.value = value
    else:
        db.session.add(SiteSetting(key=key, value=value))
    db.session.commit()


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with app.app_context():
            existing = Recipe.query.filter_by(title="Soup").first()
            if existing:
                cls.uid = existing.user_id
                cls.rid = existing.id
                cls.hid = Recipe.query.filter_by(title="Secret Stew").first().id
                return
            db.session.query(SiteSetting).delete()
            for name, admin in (("sharecook", True), ("shareother", False)):
                if not User.query.filter_by(username=name).first():
                    u = User(username=name, email=f"{name}@example.com", is_admin=admin)
                    u.set_password(PW)
                    db.session.add(u)
            db.session.commit()
            cook = User.query.filter_by(username="sharecook").first()
            cls.uid = cook.id
            r = Recipe(title="Soup", ingredients="# Base\n2 cups flour\n1 onion\n# Extras\n1 tsp salt",
                       instructions="Stir.", user_id=cook.id, share_token="soup-token")
            hidden = Recipe(title="Secret Stew", ingredients="1 carrot", instructions="Stir.", user_id=cook.id)
            db.session.add_all([r, hidden])
            db.session.commit()
            cls.rid, cls.hid = r.id, hidden.id

    def setUp(self):
        with app.app_context():
            ShoppingListItem.query.delete()
            MealPlan.query.delete()
            SiteSetting.query.delete()
            db.session.commit()
        self.c = app.test_client()
        self.c.post("/login", data={"username": "sharecook", "password": PW})


class AddSelected(Base):
    def test_merges_skips_headings_and_flashes(self):
        with app.app_context():
            db.session.add(ShoppingListItem(name="1 cup flour", user_id=self.uid))
            db.session.commit()
        r = self.c.post("/shopping/add-selected", data={
            "recipe_id": self.rid, "items": ["# Base", "2 cup flour", "  ", "1 onion"]})
        self.assertEqual(r.status_code, 302)
        self.assertTrue(r.headers["Location"].endswith("/shopping/"))
        with app.app_context():
            names = sorted(i.name for i in ShoppingListItem.query.all())
        self.assertEqual(names, ["1 onion", "3 cup flour"])
        page = self.c.get("/shopping/").get_data(as_text=True)
        self.assertIn("Added 1 ingredients from", page)
        self.assertIn("Soup", page)

    def test_limits(self):
        r = self.c.post("/shopping/add-selected", data={
            "recipe_id": self.rid, "items": [f"item {i}" for i in range(201)]})
        self.assertIn("/recipe/", r.headers["Location"])
        with app.app_context():
            self.assertEqual(ShoppingListItem.query.count(), 0)
        long = "x" * 500
        self.c.post("/shopping/add-selected", data={"recipe_id": self.rid, "items": [long]})
        with app.app_context():
            self.assertLessEqual(len(ShoppingListItem.query.first().name), 300)

    def test_nothing_selected_adds_nothing(self):
        self.c.post("/shopping/add-selected", data={"recipe_id": self.rid, "items": ["# Only heading", " "]})
        with app.app_context():
            self.assertEqual(ShoppingListItem.query.count(), 0)

    def test_old_route_still_adds_all(self):
        self.c.post(f"/shopping/recipe/{self.rid}")
        with app.app_context():
            self.assertEqual(ShoppingListItem.query.count(), 3)

    def test_recipe_page_has_picker(self):
        page = self.c.get(f"/recipe/{self.rid}").get_data(as_text=True)
        self.assertIn('id="pick-dialog"', page)
        self.assertIn("data-pick-trigger", page)


class StoreLink(Base):
    def _item(self):
        with app.app_context():
            db.session.add(ShoppingListItem(name="2 red apples & pears", user_id=self.uid))
            db.session.commit()

    def test_default_link(self):
        self._item()
        page = self.c.get("/shopping/").get_data(as_text=True)
        self.assertIn("Find at Woolworths", page)
        self.assertIn("searchTerm=2+red+apples+%26+pears", page)

    def test_custom_and_encoded(self):
        self._item()
        self.c.post("/admin/settings", data={"store_name": "Corner Shop",
                                             "store_search_url": "https://shop.example/s?q={q}"})
        page = self.c.get("/shopping/").get_data(as_text=True)
        self.assertIn("Find at Corner Shop", page)
        self.assertIn("https://shop.example/s?q=2+red+apples+%26+pears", page)

    def test_empty_hides_link(self):
        self._item()
        self.c.post("/admin/settings", data={"store_name": "", "store_search_url": ""})
        page = self.c.get("/shopping/").get_data(as_text=True)
        self.assertNotIn("Find at", page)
        self.assertIn("red apples", page)

    def test_bad_values_rejected_keep_old(self):
        self.c.post("/admin/settings", data={"store_name": "Corner Shop",
                                             "store_search_url": "https://shop.example/s?q={q}"})
        for bad in ("ftp://shop.example/{q}", "https://shop.example/no-placeholder", "javascript:alert({q})"):
            r = self.c.post("/admin/settings", data={"store_name": "Evil", "store_search_url": bad},
                            follow_redirects=True)
            self.assertIn("include {q}", r.get_data(as_text=True))
            with app.app_context():
                self.assertEqual(SiteSetting.query.filter_by(key="store_search_url").first().value,
                                 "https://shop.example/s?q={q}")
                self.assertEqual(SiteSetting.query.filter_by(key="store_name").first().value, "Corner Shop")


class Author(Base):
    def test_toggle(self):
        off = self.c.get("/shared/soup-token").get_data(as_text=True)
        self.assertNotIn("By sharecook", off)
        setting("public_show_author", "1")
        anon = app.test_client()
        on = anon.get("/shared/soup-token").get_data(as_text=True)
        self.assertIn("By sharecook", on)

    def test_admin_checkbox_saves(self):
        self.c.post("/admin/settings", data={"site_name": "X", "public_show_author": "1"})
        with app.app_context():
            self.assertEqual(SiteSetting.query.filter_by(key="public_show_author").first().value, "1")
        self.c.post("/admin/settings", data={"site_name": "X"})
        with app.app_context():
            self.assertEqual(SiteSetting.query.filter_by(key="public_show_author").first().value, "0")

    def test_collection_byline(self):
        with app.app_context():
            Collection.query.delete()
            db.session.add(Collection(name="Weeknights", user_id=self.uid, share_token="coltok", slug="wk"))
            db.session.commit()
        anon = app.test_client()
        self.assertNotIn("A collection by", anon.get("/collections/shared/coltok").get_data(as_text=True))
        setting("public_show_author", "1")
        self.assertIn("A collection by sharecook", anon.get("/collections/shared/coltok").get_data(as_text=True))


class MealPlanShare(Base):
    def _plan(self):
        with app.app_context():
            for rid in (self.rid, self.hid):
                db.session.add(MealPlan(user_id=self.uid, recipe_id=rid, date=date.today(), meal_type="dinner"))
            db.session.commit()

    def _token(self):
        with app.app_context():
            return SiteSetting.query.filter_by(key=f"mealplan_share_{self.uid}").first().value

    def test_create_public_unshare(self):
        self._plan()
        anon = app.test_client()
        self.assertEqual(anon.get("/mealplan/shared/nope").status_code, 404)
        self.c.post("/mealplan/share")
        tok = self._token()
        self.c.post("/mealplan/share")
        self.assertEqual(self._token(), tok)  # idempotent
        self.assertIn(tok, self.c.get("/mealplan/").get_data(as_text=True))
        r = anon.get(f"/mealplan/shared/{tok}")
        self.assertEqual(r.status_code, 200)
        page = r.get_data(as_text=True)
        self.assertIn('name="robots" content="noindex', page)
        self.assertIn('href="/shared/soup-token"', page)
        self.assertIn("Secret Stew", page)
        self.assertNotIn("/recipe/%d" % self.hid, page)
        self.assertNotIn("recipes/shared/None", page)
        self.assertEqual(anon.get(f"/mealplan/shared/{tok}?week=1").status_code, 200)
        self.c.post("/mealplan/unshare")
        self.assertEqual(anon.get(f"/mealplan/shared/{tok}").status_code, 404)

    def test_share_requires_login(self):
        r = app.test_client().post("/mealplan/share")
        self.assertEqual(r.status_code, 302)
        self.assertIn("login", r.headers["Location"])


if __name__ == "__main__":
    unittest.main()
