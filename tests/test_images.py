import io, os, sys, tempfile, types, unittest
from unittest import mock
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("DATA_DIR", tempfile.mkdtemp())
from PIL import Image
from app import create_app
from models import db, User, Recipe


def png_bytes():
    b = io.BytesIO(); Image.new("RGB", (40, 30), (200, 80, 20)).save(b, "PNG"); return b.getvalue()


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(); os.environ["DATA_DIR"] = cls.dir
        cls.app = create_app(); cls.app.config["WTF_CSRF_ENABLED"] = False; cls.app.testing = True
        with cls.app.app_context():
            for name, admin in (("imgowner", False), ("imgother", False), ("imgadmin", True)):
                u = User(username=name, email=name + "@x.com", is_admin=admin); u.set_password("Sup3r-secret-pass!"); db.session.add(u)
            db.session.commit()

    def login(self, name):
        c = self.app.test_client(); c.post("/login", data={"username": name, "password": "Sup3r-secret-pass!"}); return c

    def make(self, url):
        with self.app.app_context():
            owner = User.query.filter_by(username="imgowner").first()
            r = Recipe(title="R", ingredients="x", instructions="y", image_url=url, user_id=owner.id)
            db.session.add(r); db.session.commit(); return r.id

    def fake_get(self, ok=True):
        def get(url, **kw):
            if not ok: raise RuntimeError("blocked")
            self.seen = kw.get("headers", {})
            return types.SimpleNamespace(content=png_bytes(), text="", headers={})
        return mock.patch("routes.recipes.safe_get", side_effect=get)


class LocaliseImage(Base):
    def test_repairs_remote_image_and_sends_site_referer(self):
        rid = self.make("https://blocked.example.com/pics/a.webp")
        with self.fake_get():
            r = self.login("imgowner").post(f"/recipe/{rid}/localise-image")
        self.assertEqual(r.status_code, 200)
        url = r.get_json()["url"]; self.assertTrue(url.startswith("/admin/uploads/recipe_"))
        self.assertTrue(r.get_json()["thumb"].startswith("/admin/uploads/thumb_recipe_"))  # cards get the small version
        self.assertEqual(self.seen.get("Referer"), "https://blocked.example.com/")
        with self.app.app_context():
            self.assertEqual(db.session.get(Recipe, rid).image_url, url.split("/")[-1])

    def test_unavailable_image_returns_502_and_keeps_link(self):
        rid = self.make("https://gone.example.com/a.jpg")
        with self.fake_get(ok=False):
            r = self.login("imgowner").post(f"/recipe/{rid}/localise-image")
        self.assertEqual(r.status_code, 502)
        with self.app.app_context():
            self.assertEqual(db.session.get(Recipe, rid).image_url, "https://gone.example.com/a.jpg")

    def test_other_users_cannot_touch_it(self):
        rid = self.make("https://x.example.com/a.jpg")
        with self.fake_get():
            self.assertEqual(self.login("imgother").post(f"/recipe/{rid}/localise-image").status_code, 403)


class AdminBulk(Base):
    def test_bulk_saves_locally_and_blanks_dead_links(self):
        with self.app.app_context():
            Recipe.query.delete(); db.session.commit()
        good = self.make("https://ok.example.com/1.jpg"); mealie = self.make("https://mealie.local/api/media/recipes/x/original.webp")
        with self.fake_get():
            r = self.login("imgadmin").post("/admin/localise-images", follow_redirects=True)
        self.assertIn(b"Saved 1 picture", r.data)
        with self.app.app_context():
            self.assertTrue(db.session.get(Recipe, good).image_url.startswith("recipe_"))
            self.assertTrue(db.session.get(Recipe, mealie).image_url.startswith("https://mealie.local"))  # unusable links are left alone
        bad = self.make("https://dead.example.com/2.jpg")
        with self.fake_get(ok=False):
            r = self.login("imgadmin").post("/admin/localise-images", follow_redirects=True)
        self.assertIn(b"couldn", r.data)
        with self.app.app_context():
            self.assertEqual(db.session.get(Recipe, bad).image_url, "")

    def test_non_admin_forbidden(self):
        r = self.login("imgowner").post("/admin/localise-images", follow_redirects=False)
        self.assertIn(r.status_code, (302, 403))


if __name__ == "__main__":
    unittest.main()
