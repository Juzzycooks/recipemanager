"""Households (shared shopping list), collection soft delete, cook history with photos, meal plan .ics."""
import io, os, re, sys, tempfile, unittest
from datetime import date, datetime, timedelta, timezone

os.environ["DATA_DIR"] = tempfile.mkdtemp()
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app import create_app
from models import db, User, Recipe, Collection, CookLog, Household, MealPlan, ShoppingListItem

app = create_app()
app.testing = True
app.config["WTF_CSRF_ENABLED"] = False  # the web forms; the token API is CSRF-exempt by itself
PW = "Sup3r-secret-pass!"
V1 = "/api/v1"
UPLOADS = os.path.join(os.environ["DATA_DIR"], "uploads")
CODE_RE = re.compile(r"^[A-HJKMNP-Z2-9]{4}-[A-HJKMNP-Z2-9]{4}$")

_n = [0]


def tiny_jpeg(colour=(200, 120, 40)):
    from PIL import Image
    buf = io.BytesIO()
    Image.new("RGB", (8, 8), colour).save(buf, "JPEG")
    buf.seek(0)
    return buf


class Base(unittest.TestCase):
    """Fresh users per test, so tests don't share a household or a list."""

    def setUp(self):
        self.c = app.test_client()

    def user(self, tag):
        _n[0] += 1
        name = f"{tag}{_n[0]}"
        with app.app_context():
            u = User(username=name, email=f"{name}@example.com")
            u.set_password(PW)
            db.session.add(u)
            db.session.commit()
            uid = u.id
        tok = self.c.post(f"{V1}/auth/login", json={"username": name, "password": PW}).get_json()["token"]
        return {"id": uid, "name": name, "token": tok}

    def api(self, method, path, who, **kw):
        return getattr(self.c, method)(V1 + path, headers={"Authorization": f"Bearer {who['token']}"}, **kw)

    def web(self, who):
        client = app.test_client()
        r = client.post("/login", data={"username": who["name"], "password": PW})
        self.assertEqual(r.status_code, 302)
        return client

    def recipe(self, who, title="Soup"):
        r = self.api("post", "/recipes", who, json={"title": title, "ingredients": "2 cups stock\n1 onion",
                                                     "instructions": "Boil."})
        self.assertEqual(r.status_code, 201, r.get_json())
        return r.get_json()["id"]


# ── Households ──

class TestHouseholds(Base):
    def make_pair(self):
        a, b = self.user("hha"), self.user("hhb")
        hh = self.api("post", "/household", a, json={"name": "Home"}).get_json()["household"]
        r = self.api("post", "/household/join", b, json={"code": hh["invite_code"]})
        self.assertEqual(r.status_code, 200, r.get_json())
        return a, b, hh

    def test_create_shape_and_code(self):
        a = self.user("hh")
        self.assertEqual(self.api("get", "/household", a).get_json(), {"household": None})
        r = self.api("post", "/household", a, json={"name": "  Flat 4  "})
        self.assertEqual(r.status_code, 201)
        hh = r.get_json()["household"]
        self.assertEqual(set(hh), {"id", "name", "invite_code", "is_owner", "members"})
        self.assertEqual(hh["name"], "Flat 4")
        self.assertTrue(hh["is_owner"])
        self.assertRegex(hh["invite_code"], CODE_RE)
        self.assertEqual(hh["members"], [{"id": a["id"], "username": a["name"]}])
        self.assertEqual(self.api("get", "/household", a).get_json()["household"], hh)
        self.assertEqual(self.api("post", "/household", a, json={"name": "Again"}).status_code, 409)
        self.assertEqual(self.api("post", "/household", self.user("hh"), json={"name": "  "}).status_code, 422)

    def test_join_accepts_any_form_and_rejects_bad(self):
        a, b, c = self.user("hha"), self.user("hhb"), self.user("hhc")
        code = self.api("post", "/household", a, json={"name": "Home"}).get_json()["household"]["invite_code"]
        self.assertEqual(self.api("post", "/household/join", c, json={"code": "ZZZZ-ZZZZ"}).status_code, 404)
        loose = " " + code.replace("-", " ").lower() + " "
        r = self.api("post", "/household/join", b, json={"code": loose})
        self.assertEqual(r.status_code, 200)
        hh = r.get_json()["household"]
        self.assertFalse(hh["is_owner"])
        self.assertEqual([m["id"] for m in hh["members"]], [a["id"], b["id"]])
        self.assertEqual(self.api("post", "/household/join", b, json={"code": code}).status_code, 409)
        self.assertEqual(self.api("post", "/household/join", c, json={"code": code.replace("-", "")}).status_code, 200)

    def test_shared_list_scoping_and_permissions(self):
        a, b = self.user("hha"), self.user("hhb")
        outsider = self.user("hhx")
        self.api("post", "/shopping/items", b, json={"name": "Milk"})  # before joining: comes along
        self.api("post", "/shopping/items", outsider, json={"name": "Caviar"})
        code = self.api("post", "/household", a, json={"name": "Home"}).get_json()["household"]["invite_code"]
        self.api("post", "/household/join", b, json={"code": code})
        self.api("post", "/shopping/items", a, json={"name": "Bread"})

        items = {i["name"]: i for i in self.api("get", "/shopping", a).get_json()["items"]}
        self.assertEqual(set(items), {"Milk", "Bread"})
        milk = items["Milk"]
        self.assertEqual(milk["added_by"], {"id": b["id"], "username": b["name"]})
        self.assertFalse(milk["mine"])
        self.assertTrue(items["Bread"]["mine"])

        # Any member may tick, rename and delete anyone's item; an outsider may not
        r = self.api("patch", f"/shopping/items/{milk['id']}", a, json={"checked": True, "name": "Oat milk"})
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.get_json()["checked"])
        self.assertEqual(self.api("patch", f"/shopping/items/{milk['id']}", outsider, json={"checked": False}).status_code, 403)
        self.assertEqual(self.api("delete", f"/shopping/items/{milk['id']}", outsider).status_code, 403)
        self.assertNotIn("Oat milk", [i["name"] for i in self.api("get", "/shopping", outsider).get_json()["items"]])

        # Clear ticked acts on the household list (the ticked item was b's)
        self.assertEqual(self.api("delete", "/shopping/items?checked=1", a).status_code, 204)
        self.assertEqual([i["name"] for i in self.api("get", "/shopping", b).get_json()["items"]], ["Bread"])
        # Clear all too, but never touches the outsider
        self.assertEqual(self.api("delete", "/shopping/items", b).status_code, 204)
        self.assertEqual(self.api("get", "/shopping", a).get_json()["items"], [])
        self.assertEqual(len(self.api("get", "/shopping", outsider).get_json()["items"]), 1)

    def test_merge_across_household(self):
        a, b, _ = self.make_pair()
        self.api("post", "/shopping/items", a, json={"name": "2 eggs"})
        r = self.api("post", "/shopping/items", b, json={"name": "3 eggs"}).get_json()
        self.assertEqual(r, {"added": 0, "merged": 1})
        items = self.api("get", "/shopping", b).get_json()["items"]
        self.assertEqual([i["name"] for i in items], ["5 eggs"])
        # A recipe sent to the list merges into the shared list as well
        rid = self.recipe(b, "Omelette")
        with app.app_context():
            db.session.get(Recipe, rid).ingredients = "4 eggs\n1 knob butter"
            db.session.commit()
        self.api("post", f"/shopping/recipe/{rid}", b)
        names = sorted(i["name"] for i in self.api("get", "/shopping", a).get_json()["items"])
        self.assertIn("9 eggs", names)

    def test_version_changes_on_every_kind_of_change(self):
        a, b, _ = self.make_pair()
        v = lambda: self.api("get", "/shopping/version", a).get_json()["version"]
        v0 = v()
        self.assertEqual(self.api("get", "/shopping", a).get_json()["version"], v0)
        self.api("post", "/shopping/items", b, json={"name": "Apples"})
        v1 = v(); self.assertNotEqual(v1, v0)
        item = self.api("get", "/shopping", b).get_json()["items"][0]
        self.api("patch", f"/shopping/items/{item['id']}", b, json={"checked": True})
        v2 = v(); self.assertNotEqual(v2, v1)
        self.api("patch", f"/shopping/items/{item['id']}", b, json={"name": "Green apples"})
        v3 = v(); self.assertNotEqual(v3, v2)
        self.api("post", "/shopping/items", a, json={"name": "Pears"})
        v4 = v()
        self.assertEqual(self.api("delete", f"/shopping/items/{item['id']}", b).status_code, 204)  # a member's delete
        self.assertNotEqual(v(), v4)
        self.assertEqual(v(), self.api("get", "/shopping/version", b).get_json()["version"])  # same list, same version

    def test_leave_owner_handover_and_cleanup(self):
        a, b, hh = self.make_pair()
        c = self.user("hhc")
        self.api("post", "/household/join", c, json={"code": hh["invite_code"]})
        self.api("post", "/shopping/items", a, json={"name": "Owner's tea"})
        self.api("post", "/shopping/items", b, json={"name": "Rice"})

        r = self.api("post", "/household/leave", a)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.get_json(), {"household": None})
        # The leaver's items leave with them
        self.assertEqual([i["name"] for i in self.api("get", "/shopping", a).get_json()["items"]], ["Owner's tea"])
        self.assertEqual([i["name"] for i in self.api("get", "/shopping", b).get_json()["items"]], ["Rice"])
        # Owner passes to the lowest-id remaining member
        hb = self.api("get", "/household", b).get_json()["household"]
        self.assertTrue(hb["is_owner"])
        self.assertFalse(self.api("get", "/household", c).get_json()["household"]["is_owner"])
        self.assertEqual([m["id"] for m in hb["members"]], [b["id"], c["id"]])

        self.api("post", "/household/leave", c)
        self.api("post", "/household/leave", b)
        with app.app_context():
            self.assertIsNone(db.session.get(Household, hh["id"]))  # empty: deleted
        self.assertEqual(self.api("post", "/household/leave", b).get_json(), {"household": None})

    def test_regenerate_code_owner_only(self):
        a, b, hh = self.make_pair()
        self.assertEqual(self.api("post", "/household/code", b).status_code, 403)
        r = self.api("post", "/household/code", a)
        self.assertEqual(r.status_code, 200)
        new = r.get_json()["household"]["invite_code"]
        self.assertRegex(new, CODE_RE)
        self.assertNotEqual(new, hh["invite_code"])
        c = self.user("hhc")
        self.assertEqual(self.api("post", "/household/join", c, json={"code": hh["invite_code"]}).status_code, 404)
        self.assertEqual(self.api("post", "/household/join", c, json={"code": new}).status_code, 200)
        self.assertEqual(self.api("post", "/household/code", self.user("hhd")).status_code, 404)

    def test_deleting_a_member_account_hands_over(self):
        a, b, hh = self.make_pair()
        self.assertEqual(self.api("delete", "/me", a, json={"password": PW}).status_code, 204)
        hb = self.api("get", "/household", b).get_json()["household"]
        self.assertTrue(hb["is_owner"])
        self.assertEqual([m["id"] for m in hb["members"]], [b["id"]])

    def test_web_shopping_and_profile(self):
        a, b = self.user("hwa"), self.user("hwb")
        wa, wb = self.web(a), self.web(b)
        # Create and join from the profile page
        r = wa.post("/profile", data={"action": "household_create", "name": "Our place"}, follow_redirects=True)
        self.assertIn(b"Our place", r.data)
        code = self.api("get", "/household", a).get_json()["household"]["invite_code"]
        self.assertIn(code.encode(), r.data)
        self.assertIn(b"New invite code", r.data)  # owner only
        r = wb.post("/profile", data={"action": "household_join", "code": code.lower()}, follow_redirects=True)
        self.assertIn(b"joined the household", r.data)
        self.assertNotIn(b"New invite code", r.data)
        r = wb.post("/profile", data={"action": "household_create", "name": "Second"}, follow_redirects=True)
        self.assertIn(b"already in a household", r.data)

        wa.post("/shopping/add", data={"name": "Coffee"})
        page = wb.get("/shopping/").data.decode()
        self.assertIn("Coffee", page)
        self.assertIn(f"Added by {a['name']}", page)
        self.assertIn("data-shop-version", page)
        self.assertIn("shoplist.js", page)
        v0 = wb.get("/shopping/version").get_json()["version"]
        item = self.api("get", "/shopping", b).get_json()["items"][0]
        self.assertEqual(wb.post(f"/shopping/toggle/{item['id']}").status_code, 302)
        self.assertTrue(self.api("get", "/shopping", a).get_json()["items"][0]["checked"])
        self.assertNotEqual(wb.get("/shopping/version").get_json()["version"], v0)
        wb.post("/shopping/clear-checked")
        self.assertEqual(self.api("get", "/shopping", a).get_json()["items"], [])

        r = wb.post("/profile", data={"action": "household_leave"}, follow_redirects=True)
        self.assertIn(b"left the household", r.data)
        self.assertIsNone(self.api("get", "/household", b).get_json()["household"])
        self.assertNotIn(b"shoplist.js", wb.get("/shopping/").data)


# ── Collections: soft delete and restore ──

class TestCollectionSoftDelete(Base):
    def setUp(self):
        super().setUp()
        self.me = self.user("coll")
        self.rid = self.recipe(self.me, "Lasagne")
        r = self.api("post", "/collections", self.me, json={"name": "Sunday", "slug": f"sunday-{_n[0]}"})
        self.coll = r.get_json()
        self.cid = self.coll["id"]
        self.api("post", f"/collections/{self.cid}/recipes", self.me, json={"recipe_id": self.rid})
        self.token = self.api("post", f"/collections/{self.cid}/share", self.me).get_json()["share_url"].rstrip("/").split("/")[-1]
        with app.app_context():
            self.share_token = db.session.get(Collection, self.cid).share_token
            self.slug = db.session.get(Collection, self.cid).slug

    def visible(self):
        return [c["id"] for c in self.api("get", "/collections", self.me).get_json()["items"]]

    def test_api_delete_hides_everywhere_and_restore(self):
        r = self.api("delete", f"/collections/{self.cid}", self.me)
        self.assertEqual(r.status_code, 200)
        body = r.get_json()
        self.assertEqual(set(body), {"ok", "restorable_until"})
        self.assertTrue(body["ok"])
        until = datetime.fromisoformat(body["restorable_until"].replace("Z", "+00:00"))
        self.assertAlmostEqual((until - datetime.now(timezone.utc)).total_seconds(), 30 * 86400, delta=120)

        self.assertNotIn(self.cid, self.visible())
        self.assertEqual(self.api("get", f"/collections/{self.cid}", self.me).status_code, 404)
        self.assertEqual(self.api("delete", f"/collections/{self.cid}", self.me).status_code, 404)
        self.assertEqual(self.c.get(f"{V1}/shared/collections/{self.share_token}").status_code, 404)
        self.assertEqual(self.c.get(f"{V1}/shared/collections/{self.share_token}/recipes/{self.rid}").status_code, 404)
        detail = self.api("get", f"/recipes/{self.rid}", self.me).get_json()
        self.assertNotIn(self.cid, [c["id"] for c in detail.get("collections", [])])
        web = self.web(self.me)
        self.assertEqual(web.get(f"/collections/{self.cid}").status_code, 404)
        self.assertEqual(web.get(f"/collections/shared/{self.share_token}").status_code, 404)
        self.assertEqual(web.get(f"/collections/shared/{self.slug}").status_code, 404)
        self.assertNotIn(b"Sunday", web.get("/collections/").data)
        self.assertNotIn(f"collection={self.cid}".encode(), web.get("/").data)

        other = self.user("collx")
        self.assertEqual(self.api("post", f"/collections/{self.cid}/restore", other).status_code, 404)
        r = self.api("post", f"/collections/{self.cid}/restore", self.me)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.get_json()["id"], self.cid)
        self.assertEqual([x["id"] for x in r.get_json()["recipes"]], [self.rid])
        self.assertIn(self.cid, self.visible())
        self.assertEqual(self.c.get(f"{V1}/shared/collections/{self.share_token}").status_code, 200)
        self.assertEqual(self.api("post", f"/collections/{self.cid}/restore", self.me).status_code, 404)  # not deleted

    def test_past_window_cannot_restore_and_is_purged(self):
        self.api("delete", f"/collections/{self.cid}", self.me)
        with app.app_context():
            db.session.get(Collection, self.cid).deleted_at = datetime.now(timezone.utc) - timedelta(days=31)
            db.session.commit()
        self.assertEqual(self.api("post", f"/collections/{self.cid}/restore", self.me).status_code, 404)
        self.visible()  # list calls purge
        with app.app_context():
            self.assertIsNone(db.session.get(Collection, self.cid))
            self.assertIsNotNone(db.session.get(Recipe, self.rid))  # the recipes stay

    def test_web_delete_flash_and_undo(self):
        web = self.web(self.me)
        r = web.post(f"/collections/{self.cid}/delete", follow_redirects=True)
        page = r.data.decode()
        self.assertIn("Collection deleted", page)
        self.assertIn(f"/collections/{self.cid}/restore", page)
        self.assertIn("Undo", page)
        self.assertNotIn(self.cid, self.visible())
        r = web.post(f"/collections/{self.cid}/restore", follow_redirects=True)
        self.assertEqual(r.status_code, 200)
        self.assertIn(self.cid, self.visible())
        self.assertEqual(web.get(f"/collections/{self.cid}").status_code, 200)

    def test_deleted_slug_can_be_reused(self):
        self.api("delete", f"/collections/{self.cid}", self.me)
        r = self.api("post", "/collections", self.me, json={"name": "New", "slug": self.slug})
        self.assertEqual(r.status_code, 201, r.get_json())


# ── Cook history ──

class TestCookLog(Base):
    def setUp(self):
        super().setUp()
        self.me = self.user("cook")
        self.rid = self.recipe(self.me, "Risotto")

    def photo_path(self, entry):
        self.assertTrue(entry["photo_url"].startswith("/admin/uploads/"), entry["photo_url"])
        return os.path.join(UPLOADS, entry["photo_url"].rsplit("/", 1)[1].replace("thumb_", ""))

    def test_made_bodies_and_entry_shape(self):
        r = self.api("post", f"/recipes/{self.rid}/made", self.me)
        self.assertEqual(r.status_code, 201)
        e = r.get_json()
        self.assertEqual(e["made_count"], 1)
        self.assertEqual(e["note"], "")
        self.assertIsNone(e["photo_url"])
        self.assertEqual(e["recipe"]["id"], self.rid)
        self.assertEqual(e["recipe"]["title"], "Risotto")
        self.assertIn("image_url", e["recipe"])
        self.assertTrue({"id", "cooked_at", "note", "photo_url", "recipe"} <= set(e))

        e = self.api("post", f"/recipes/{self.rid}/made", self.me, json={"note": "More parmesan"}).get_json()
        self.assertEqual((e["note"], e["made_count"]), ("More parmesan", 2))

        r = self.api("post", f"/recipes/{self.rid}/made", self.me,
                     data={"note": "With a photo", "photo": (tiny_jpeg(), "dinner.jpg")}, content_type="multipart/form-data")
        self.assertEqual(r.status_code, 201, r.get_json())
        e = r.get_json()
        self.assertEqual(e["made_count"], 3)
        self.assertTrue(os.path.exists(self.photo_path(e)))

        bad = self.api("post", f"/recipes/{self.rid}/made", self.me,
                       data={"photo": (io.BytesIO(b"not an image"), "x.jpg")}, content_type="multipart/form-data")
        self.assertEqual(bad.status_code, 422)

        hist = self.api("get", f"/recipes/{self.rid}/cook-history", self.me).get_json()["items"]
        self.assertEqual([h["note"] for h in hist], ["With a photo", "More parmesan", ""])

    def test_timeline_paging_and_crud(self):
        ids = [self.api("post", f"/recipes/{self.rid}/made", self.me, json={"note": f"#{i}"}).get_json()["id"] for i in range(3)]
        page = self.api("get", "/cook-log?limit=2", self.me).get_json()
        self.assertEqual(set(page), {"entries", "next_before"})
        self.assertEqual([e["id"] for e in page["entries"]], ids[::-1][:2])
        rest = self.api("get", f"/cook-log?limit=2&before={page['next_before']}", self.me).get_json()
        self.assertEqual([e["id"] for e in rest["entries"]], [ids[0]])
        self.assertIsNone(rest["next_before"])

        lid = ids[0]
        other = self.user("cookx")
        self.assertEqual(self.api("patch", f"/cook-log/{lid}", other, json={"note": "x"}).status_code, 404)
        self.assertEqual(self.api("delete", f"/cook-log/{lid}", other).status_code, 404)
        self.assertEqual(self.api("get", "/cook-log", other).get_json(), {"entries": [], "next_before": None})

        r = self.api("patch", f"/cook-log/{lid}", self.me, json={"note": "Edited"})
        self.assertEqual(r.get_json()["note"], "Edited")

        r = self.api("post", f"/cook-log/{lid}/photo", self.me, data={"photo": (tiny_jpeg(), "a.jpg")},
                     content_type="multipart/form-data")
        self.assertEqual(r.status_code, 200)
        first = self.photo_path(r.get_json())
        self.assertTrue(os.path.exists(first))
        r = self.api("post", f"/cook-log/{lid}/photo", self.me, data={"photo": (tiny_jpeg((10, 90, 200)), "b.jpg")},
                     content_type="multipart/form-data")
        second = self.photo_path(r.get_json())
        self.assertFalse(os.path.exists(first))  # replaced: the old file goes
        self.assertTrue(os.path.exists(second))
        self.assertEqual(self.api("post", f"/cook-log/{lid}/photo", self.me, json={}).status_code, 422)

        r = self.api("delete", f"/cook-log/{lid}/photo", self.me)
        self.assertIsNone(r.get_json()["photo_url"])
        self.assertFalse(os.path.exists(second))

        r = self.api("post", f"/cook-log/{lid}/photo", self.me, data={"photo": (tiny_jpeg(), "c.jpg")},
                     content_type="multipart/form-data")
        third = self.photo_path(r.get_json())
        self.assertEqual(self.api("delete", f"/cook-log/{lid}", self.me).status_code, 204)
        self.assertFalse(os.path.exists(third))
        self.assertEqual(self.api("patch", f"/cook-log/{lid}", self.me, json={"note": "x"}).status_code, 404)

    def test_deleting_the_recipe_removes_cook_photos(self):
        e = self.api("post", f"/recipes/{self.rid}/made", self.me, data={"photo": (tiny_jpeg(), "p.jpg")},
                     content_type="multipart/form-data").get_json()
        path = self.photo_path(e)
        self.assertTrue(os.path.exists(path))
        self.assertEqual(self.api("delete", f"/recipes/{self.rid}", self.me).status_code, 200)
        self.assertFalse(os.path.exists(path))
        with app.app_context():
            self.assertEqual(CookLog.query.filter_by(recipe_id=self.rid).count(), 0)

    def test_web_made_timeline_edit_delete(self):
        web = self.web(self.me)
        r = web.post(f"/recipe/{self.rid}/made-it", data={"note": "Crispy edges", "photo": (tiny_jpeg(), "w.jpg")},
                     content_type="multipart/form-data", follow_redirects=True)
        self.assertIn(b"made this 1 time", r.data)
        self.assertIn(b"Your cooks", r.data)  # the recipe page shows past cook photos
        r = web.post(f"/recipe/{self.rid}/made-it", data={"note": "From cook mode"},
                     headers={"X-Requested-With": "fetch"})
        self.assertEqual(r.get_json()["made_count"], 2)

        page = web.get("/cook-history").data.decode()
        self.assertIn("Crispy edges", page)
        self.assertIn("From cook mode", page)
        self.assertIn("Risotto", page)
        self.assertIn("Crispy edges", web.get(f"/recipe/{self.rid}/cook-history").data.decode())

        with app.app_context():
            log = CookLog.query.filter_by(user_id=self.me["id"], note="Crispy edges").one()
            lid, photo = log.id, log.photo
        self.assertTrue(os.path.exists(os.path.join(UPLOADS, photo)))
        web.post(f"/cook-history/{lid}/edit", data={"note": "Crispier next time", "remove_photo": "1"})
        with app.app_context():
            log = db.session.get(CookLog, lid)
            self.assertEqual((log.note, log.photo), ("Crispier next time", ""))
        self.assertFalse(os.path.exists(os.path.join(UPLOADS, photo)))

        other = self.web(self.user("cookweb"))
        self.assertEqual(other.post(f"/cook-history/{lid}/delete").status_code, 404)
        r = web.post(f"/cook-history/{lid}/delete", data={"next": "https://example.com/"})
        self.assertEqual(r.headers["Location"].split("?")[0].rstrip("/").rsplit("/", 1)[-1], "cook-history")
        with app.app_context():
            self.assertIsNone(db.session.get(CookLog, lid))


# ── Meal plan calendar export ──

class TestIcs(Base):
    def setUp(self):
        super().setUp()
        self.me = self.user("ics")
        self.rid = self.recipe(self.me, "Salt, pepper; lime " + "and a very long title " * 4)
        self.today = date.today()
        with app.app_context():
            p = MealPlan(user_id=self.me["id"], recipe_id=self.rid, date=self.today, meal_type="lunch")
            db.session.add(p)
            db.session.commit()
            self.pid = p.id

    def check(self, resp):
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.headers["Content-Type"].startswith("text/calendar"))
        self.assertIn("attachment", resp.headers.get("Content-Disposition", ""))
        raw = resp.get_data()
        self.assertTrue(raw.startswith(b"BEGIN:VCALENDAR\r\n"))
        self.assertTrue(raw.endswith(b"END:VCALENDAR\r\n"))
        self.assertNotIn(b"\n", raw.replace(b"\r\n", b""))  # CRLF only
        for line in raw.split(b"\r\n"):
            self.assertLessEqual(len(line), 75)
        text = raw.decode().replace("\r\n ", "")  # unfold
        self.assertIn("VERSION:2.0", text)
        self.assertEqual(text.count("BEGIN:VEVENT"), 1)
        self.assertIn(f"UID:mealplan-{self.pid}@spoonmate", text)
        self.assertIn(f"DTSTART;VALUE=DATE:{self.today.strftime('%Y%m%d')}", text)
        self.assertIn(f"DTEND;VALUE=DATE:{(self.today + timedelta(days=1)).strftime('%Y%m%d')}", text)
        self.assertIn("SUMMARY:Lunch: Salt\\, pepper\\; lime and a very long title", text)
        self.assertRegex(text, rf"DESCRIPTION:.*http://localhost/recipe/{self.rid}")
        return text

    def test_web_export(self):
        web = self.web(self.me)
        self.check(web.get("/mealplan/export.ics"))
        self.assertNotIn(b"BEGIN:VEVENT", web.get("/mealplan/export.ics?week=2").data)
        self.assertIn(b"Download for Calendar", web.get("/mealplan/").data)

    def test_api_export(self):
        self.check(self.api("get", "/mealplan/export.ics", self.me))
        d = self.today.isoformat()
        self.check(self.api("get", f"/mealplan/export.ics?from={d}&to={d}", self.me))
        self.assertEqual(self.c.get(f"{V1}/mealplan/export.ics").status_code, 401)
        other = self.user("icsx")
        self.assertNotIn(b"BEGIN:VEVENT", self.api("get", "/mealplan/export.ics", other).get_data())


if __name__ == "__main__":
    unittest.main()
