import io, os, sys, tempfile, unittest
from datetime import date, timedelta

os.environ["DATA_DIR"] = tempfile.mkdtemp()
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app import create_app
from models import db, User, Recipe, Category, ApiToken, LoginAttempt

app = create_app()
app.testing = True  # CSRF stays ON: the API must be exempt by itself
PW = "Sup3r-secret-pass!"
V1 = "/api/v1"


_ADMIN = {}


class Api(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = app.test_client()
        if "token" not in _ADMIN:
            r = cls.c.post(f"{V1}/auth/setup", json={"username": "admin", "password": PW})
            _ADMIN["token"] = r.get_json()["token"]
        cls.admin = _ADMIN["token"]

    @classmethod
    def signup(cls, name):
        """A token for a plain user, creating the account the first time."""
        with app.app_context():
            if not User.query.filter_by(username=name).first():
                u = User(username=name, is_admin=False)
                u.set_password(PW)
                db.session.add(u)
                db.session.commit()
        return cls.c.post(f"{V1}/auth/login", json={"username": name, "password": PW}).get_json()["token"]

    def call(self, method, path, token=None, **kw):
        token = self.admin if token is None else token
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        return getattr(self.c, method)(V1 + path, headers=headers, **kw)

    def get(self, p, **kw): return self.call("get", p, **kw)
    def post(self, p, **kw): return self.call("post", p, **kw)
    def put(self, p, **kw): return self.call("put", p, **kw)
    def patch(self, p, **kw): return self.call("patch", p, **kw)
    def delete(self, p, **kw): return self.call("delete", p, **kw)

    def new_recipe(self, title="Soup", **extra):
        body = {"title": title, "ingredients": "# Base\n2 cups stock\n1 onion", "instructions": "Boil.", **extra}
        r = self.post("/recipes", json=body)
        self.assertEqual(r.status_code, 201, r.get_json())
        return r.get_json()


class TestAuth(Api):
    def test_requires_token(self):
        r = self.get("/recipes", token="")
        self.assertEqual(r.status_code, 401)
        self.assertEqual(r.get_json()["error"]["code"], "unauthorized")
        self.assertEqual(r.headers["WWW-Authenticate"], "Bearer")

    def test_bad_token_and_cookie_session_ignored(self):
        self.assertEqual(self.get("/recipes", token="nope").status_code, 401)
        web = app.test_client()
        app.config["WTF_CSRF_ENABLED"] = False
        try:
            web.post("/login", data={"username": "admin", "password": PW})
        finally:
            app.config["WTF_CSRF_ENABLED"] = True
        self.assertEqual(web.get(f"{V1}/recipes").status_code, 401)  # cookie alone is not enough

    def test_login_logout_and_rate_limit(self):
        r = self.c.post(f"{V1}/auth/login", json={"username": "admin", "password": PW, "device_name": "Phone"})
        self.assertEqual(r.status_code, 200)
        tok = r.get_json()["token"]
        self.assertTrue(tok.startswith("rm_"))
        with app.app_context():  # only a hash is stored
            self.assertIsNone(ApiToken.query.filter_by(token_hash=tok).first())
        self.assertEqual(self.get("/me", token=tok).get_json()["username"], "admin")
        names = [t["name"] for t in self.get("/auth/tokens", token=tok).get_json()["items"]]
        self.assertIn("Phone", names)
        self.assertEqual(self.post("/auth/logout", token=tok).status_code, 204)
        self.assertEqual(self.get("/me", token=tok).status_code, 401)
        for _ in range(6):
            bad = self.c.post(f"{V1}/auth/login", json={"username": "ratey", "password": "x"})
        self.assertEqual(bad.status_code, 429)
        with app.app_context():  # don't lock every later test out of this IP
            LoginAttempt.query.delete()
            db.session.commit()

    def test_site_is_public(self):
        r = self.c.get(f"{V1}/site")
        self.assertEqual(r.status_code, 200)
        self.assertFalse(r.get_json()["setup_required"])

    def test_setup_closed_after_first_user(self):
        self.assertEqual(self.c.post(f"{V1}/auth/setup", json={"username": "x", "password": PW}).status_code, 409)

    def test_change_password_revokes_other_tokens(self):
        tok_a = self.signup("pwuser")
        tok_b = self.c.post(f"{V1}/auth/login", json={"username": "pwuser", "password": PW}).get_json()["token"]
        r = self.post("/me/password", token=tok_a, json={"current_password": PW, "new_password": "An0ther-pass-9"})
        self.assertEqual(r.status_code, 204)
        self.assertEqual(self.get("/me", token=tok_a).status_code, 200)
        self.assertEqual(self.get("/me", token=tok_b).status_code, 401)
        self.assertEqual(self.post("/me/password", token=tok_a,
                                   json={"current_password": "wrong", "new_password": "An0ther-pass-9"}).status_code, 403)

    def test_delete_own_account(self):
        tok = self.signup("leaver")
        rid = self.post("/recipes", token=tok, json={"title": "Leaver's dish"}).get_json()["id"]
        self.assertEqual(self.delete("/me", token=tok, json={"password": "wrong"}).status_code, 403)
        self.assertEqual(self.delete("/me", token=tok, json={}).status_code, 403)
        self.assertEqual(self.get("/me", token=tok).status_code, 200)            # still there
        self.assertEqual(self.delete("/me", token=tok, json={"password": PW}).status_code, 204)
        self.assertEqual(self.get("/me", token=tok).status_code, 401)             # token died with the account
        self.assertEqual(self.get(f"/recipes/{rid}").status_code, 404)            # their recipes went too
        login = self.c.post(f"{V1}/auth/login", json={"username": "leaver", "password": PW})
        self.assertEqual(login.status_code, 401)

    def test_last_admin_cannot_delete_themselves(self):
        r = self.delete("/me", json={"password": PW})
        self.assertEqual(r.status_code, 422)
        self.assertIn("only admin", r.get_json()["error"]["message"])
        self.assertEqual(self.get("/me").status_code, 200)

    def test_update_me_email(self):
        self.assertEqual(self.patch("/me", json={"email": "bad"}).status_code, 422)
        self.assertEqual(self.patch("/me", json={"email": "a@b.co"}).get_json()["email"], "a@b.co")

    def test_unknown_route_is_json(self):
        r = self.get("/nothing-here")
        self.assertEqual(r.status_code, 404)
        self.assertEqual(r.get_json()["error"]["code"], "not_found")


class TestRecipes(Api):
    def test_crud_and_sections(self):
        r = self.new_recipe("Pasta", servings="4", prep_time="10 min")
        rid = r["id"]
        self.assertEqual(r["ingredient_sections"], [{"heading": "Base", "lines": ["2 cups stock", "1 onion"]}])
        self.assertTrue(r["can_edit"])
        r = self.patch(f"/recipes/{rid}", json={"title": "Better Pasta", "notes": "more salt"}).get_json()
        self.assertEqual((r["title"], r["notes"], r["servings"]), ("Better Pasta", "more salt", "4"))
        self.assertEqual(self.patch(f"/recipes/{rid}", json={"title": ""}).status_code, 422)
        self.assertEqual(self.get(f"/recipes/{rid}").get_json()["title"], "Better Pasta")

    def test_create_requires_title_and_valid_image_url(self):
        self.assertEqual(self.post("/recipes", json={"ingredients": "x"}).status_code, 422)
        r = self.post("/recipes", json={"title": "T", "image_url": "/etc/passwd"})
        self.assertEqual(r.status_code, 422)

    def test_categories_on_recipe(self):
        cat = self.post("/categories", json={"name": "Dinner"}).get_json()
        r = self.new_recipe("Cat recipe", category_ids=[cat["id"]])
        self.assertEqual(r["categories"], [{"id": cat["id"], "name": "Dinner"}])
        self.assertEqual(self.post("/recipes", json={"title": "x", "category_ids": [9999]}).status_code, 422)
        listed = self.get(f"/recipes?cat={cat['id']}").get_json()
        self.assertEqual([i["title"] for i in listed["items"]], ["Cat recipe"])
        self.assertEqual(self.post("/categories", json={"name": "Dinner"}).status_code, 409)

    def test_list_search_sort_pagination(self):
        for t in ("Zeta", "Alpha"):
            self.new_recipe(t, ingredients="1 unicorn horn")
        r = self.get("/recipes?q=unicorn&sort=title_az&per_page=1&page=2").get_json()
        self.assertEqual((r["total"], r["pages"], r["page"]), (2, 2, 2))
        self.assertEqual(r["items"][0]["title"], "Zeta")
        self.assertEqual(self.get("/recipes?ingredient=unicorn").get_json()["total"], 2)

    def test_favorite_rating_comment_made(self):
        rid = self.new_recipe("Social")["id"]
        self.assertTrue(self.put(f"/recipes/{rid}/favorite").get_json()["favorited"])
        self.assertTrue(self.put(f"/recipes/{rid}/favorite").get_json()["favorited"])  # idempotent
        self.assertEqual(self.get("/recipes?favorites=1").get_json()["total"] >= 1, True)
        self.assertFalse(self.delete(f"/recipes/{rid}/favorite").get_json()["favorited"])
        self.assertEqual(self.put(f"/recipes/{rid}/rating", json={"score": 9}).status_code, 422)
        rated = self.put(f"/recipes/{rid}/rating", json={"score": 4}).get_json()
        self.assertEqual((rated["my_rating"], rated["avg_rating"], rated["rating_count"]), (4, 4, 1))
        self.assertIsNone(self.delete(f"/recipes/{rid}/rating").get_json()["my_rating"])
        cid = self.post(f"/recipes/{rid}/comments", json={"text": "Yum"}).get_json()["id"]
        self.assertEqual(self.post(f"/recipes/{rid}/comments", json={"text": " "}).status_code, 422)
        self.assertEqual(len(self.get(f"/recipes/{rid}/comments").get_json()["items"]), 1)
        other = self.signup("commenter")
        self.assertEqual(self.delete(f"/comments/{cid}", token=other).status_code, 403)
        self.assertEqual(self.delete(f"/comments/{cid}").status_code, 204)
        self.assertEqual(self.post(f"/recipes/{rid}/made").get_json()["made_count"], 1)
        self.assertEqual(len(self.get(f"/recipes/{rid}/cook-history").get_json()["items"]), 1)
        detail = self.get(f"/recipes/{rid}").get_json()
        self.assertEqual(detail["made_count"], 1)
        self.assertEqual(self.get("/recipes/recent").get_json()["items"][0]["id"], rid)

    def test_permissions(self):
        other = self.signup("intruder")
        rid = self.new_recipe("Mine")["id"]
        self.assertEqual(self.get(f"/recipes/{rid}", token=other).status_code, 200)  # one shared library
        self.assertFalse(self.get(f"/recipes/{rid}", token=other).get_json()["can_edit"])
        for call, path, kw in ((self.patch, f"/recipes/{rid}", {"json": {"title": "x"}}),
                               (self.delete, f"/recipes/{rid}", {}),
                               (self.put, f"/recipes/{rid}/notes", {"json": {"notes": "x"}}),
                               (self.post, f"/recipes/{rid}/share", {})):
            self.assertEqual(call(path, token=other, **kw).status_code, 403, path)

    def test_delete_and_restore(self):
        rid = self.new_recipe("Doomed")["id"]
        d = self.delete(f"/recipes/{rid}").get_json()
        self.assertEqual(self.get(f"/recipes/{rid}").status_code, 404)
        other = self.signup("restorer")
        self.assertEqual(self.post(f"/recipes/restore/{d['restore_token']}", token=other).status_code, 403)
        back = self.post(f"/recipes/restore/{d['restore_token']}")
        self.assertEqual(back.status_code, 201)
        self.assertEqual(back.get_json()["title"], "Doomed")
        self.assertEqual(self.post(f"/recipes/restore/{d['restore_token']}").status_code, 404)
        self.assertEqual(self.post("/recipes/restore/../../x").status_code, 404)

    def test_duplicate_share_and_public_view(self):
        self.patch("/admin/settings", json={"public_show_author": False})
        rid = self.new_recipe("Sharable", notes="private note")["id"]
        self.assertEqual(self.post(f"/recipes/{rid}/duplicate").get_json()["title"], "Sharable (Copy)")
        url = self.post(f"/recipes/{rid}/share").get_json()["share_url"]
        token = url.rsplit("/", 1)[1]
        pub = self.c.get(f"{V1}/shared/recipes/{token}")  # no auth header
        self.assertEqual(pub.status_code, 200)
        body = pub.get_json()
        self.assertNotIn("notes", body)
        self.assertNotIn("comments", body)
        self.assertIsNone(body["author"])
        self.assertEqual(self.delete(f"/recipes/{rid}/share").status_code, 204)
        self.assertEqual(self.c.get(f"{V1}/shared/recipes/{token}").status_code, 404)

    def test_image_upload(self):
        from PIL import Image
        buf = io.BytesIO()
        Image.new("RGB", (40, 30), "red").save(buf, "PNG")
        buf.seek(0)
        rid = self.new_recipe("Pic")["id"]
        r = self.put(f"/recipes/{rid}/image", data={"image_file": (buf, "p.png")}, content_type="multipart/form-data")
        self.assertEqual(r.status_code, 200, r.get_json())
        url = r.get_json()["image_url"]
        self.assertTrue(url.startswith("/admin/uploads/"))
        self.assertEqual(self.c.get(url).status_code, 200)  # images load without a token
        bad = self.put(f"/recipes/{rid}/image", data={"image_file": (io.BytesIO(b"nope"), "p.png")},
                       content_type="multipart/form-data")
        self.assertEqual(bad.status_code, 422)
        self.assertEqual(self.delete(f"/recipes/{rid}/image").status_code, 204)
        self.assertEqual(self.get(f"/recipes/{rid}").get_json()["image_url"], "")

    def test_multipart_create(self):
        r = self.post("/recipes", data={"title": "Form made", "ingredients": "1 egg"},
                      content_type="multipart/form-data")
        self.assertEqual(r.status_code, 201)

    def test_random_and_not_json_body(self):
        self.new_recipe("Anything")
        self.assertEqual(self.get("/recipes/random").status_code, 200)
        r = self.post("/recipes", data="[1,2]", content_type="application/json")
        self.assertEqual(r.status_code, 400)


class TestImport(Api):
    def test_caption_preview_then_save(self):
        r = self.post("/import/caption", json={
            "caption": "Garlic Bread\nIngredients\n1 loaf bread\n3 cloves garlic\nMethod\nMix and bake for 10 minutes."})
        self.assertEqual(r.status_code, 200)
        body = r.get_json()
        self.assertEqual(body["kind"], "caption")
        self.assertIn("garlic", body["draft"]["ingredients"].lower())
        saved = self.post("/import/save", json={**body["draft"], "source_url": "https://x.test/a"})
        self.assertEqual(saved.status_code, 201)
        self.assertEqual(saved.get_json()["source_url"], "https://x.test/a")
        self.assertEqual(self.post("/import/save", json={"title": ""}).status_code, 422)
        self.assertEqual(self.post("/import/caption", json={"caption": ""}).status_code, 422)

    def test_url_validation_and_failure_is_json(self):
        self.assertEqual(self.post("/import/url", json={"url": "ftp://x"}).status_code, 422)
        r = self.post("/import/url", json={"url": "http://127.0.0.1/recipe"})  # SSRF guard
        self.assertEqual(r.status_code, 422)
        self.assertEqual(r.get_json()["error"]["code"], "import_failed")

    def test_bulk_urls_reports_failures(self):
        r = self.post("/import/urls", json={"urls": ["http://127.0.0.1/x", "nope"]})
        body = r.get_json()
        self.assertEqual(r.status_code, 422)
        self.assertEqual(len(body["failed"]), 2)
        self.assertEqual(self.post("/import/urls", json={"urls": []}).status_code, 422)

    def test_photo_and_pdf_need_files(self):
        self.assertEqual(self.post("/import/photo").status_code, 422)
        self.assertEqual(self.post("/import/pdf").status_code, 422)


class TestCollections(Api):
    def test_lifecycle(self):
        a, b = self.new_recipe("A")["id"], self.new_recipe("B")["id"]
        coll = self.post("/collections", json={"name": "Weeknights", "slug": "Week Nights"}).get_json()
        cid = coll["id"]
        self.assertEqual(coll["slug"], "week-nights")
        self.assertEqual(self.post("/collections", json={"name": "Dup", "slug": "week-nights"}).status_code, 409)
        self.assertEqual(self.post("/collections", json={"name": ""}).status_code, 422)
        self.post(f"/collections/{cid}/recipes", json={"recipe_id": a})
        c = self.post(f"/collections/{cid}/recipes", json={"recipe_id": b}).get_json()
        self.assertEqual([r["title"] for r in c["recipes"]], ["A", "B"])
        c = self.put(f"/collections/{cid}/order", json={"order": [b]}).get_json()
        self.assertEqual([r["id"] for r in c["recipes"]], [b, a])  # omitted recipe kept, not dropped
        self.assertEqual(self.get(f"/recipes?collection={cid}").get_json()["total"], 2)
        url = self.post(f"/collections/{cid}/share").get_json()["share_url"]
        token = url.rsplit("/", 1)[1]
        self.assertEqual(token, "week-nights")
        pub = self.c.get(f"{V1}/shared/collections/{token}").get_json()
        self.assertEqual(len(pub["recipes"]), 2)
        self.assertEqual(self.c.get(f"{V1}/shared/collections/{token}/recipes/{a}").status_code, 200)
        self.assertEqual(self.delete(f"/collections/{cid}/share").status_code, 204)
        self.assertEqual(self.c.get(f"{V1}/shared/collections/{token}").status_code, 404)
        self.assertEqual(self.delete(f"/collections/{cid}/recipes/{a}").status_code, 204)
        self.assertEqual(self.patch(f"/collections/{cid}", json={"name": "Renamed"}).get_json()["name"], "Renamed")
        self.assertEqual(self.delete(f"/collections/{cid}").status_code, 204)
        self.assertEqual(self.get(f"/collections/{cid}").status_code, 404)

    def test_category_linked_recipes_and_ownership(self):
        cat = self.post("/categories", json={"name": "Linked"}).get_json()
        rid = self.new_recipe("Linked one", category_ids=[cat["id"]])["id"]
        c = self.post("/collections", json={"name": "By category", "category_id": cat["id"]}).get_json()
        detail = self.get(f"/collections/{c['id']}").get_json()
        self.assertEqual([r["id"] for r in detail["recipes"]], [rid])
        self.assertEqual(detail["manual_recipe_ids"], [])
        other = self.signup("collother")
        self.assertEqual(self.get(f"/collections/{c['id']}", token=other).status_code, 403)
        self.assertEqual(self.get("/collections", token=other).get_json()["items"], [])


class TestMealPlan(Api):
    def test_plan_flow(self):
        tok = self.signup("planner")
        rid = self.new_recipe("Planned")["id"]
        day = date.today().isoformat()
        e = self.post("/mealplan", json={"recipe_id": rid, "date": day, "meal_type": "lunch"}, token=tok)
        self.assertEqual(e.status_code, 201)
        pid = e.get_json()["id"]
        self.assertEqual(self.post("/mealplan", json={"recipe_id": rid, "date": day, "meal_type": "brunch"}, token=tok).status_code, 422)
        self.assertEqual(self.post("/mealplan", json={"recipe_id": rid, "date": "soon"}, token=tok).status_code, 422)
        week = self.get("/mealplan", token=tok).get_json()
        self.assertIn(pid, [x["id"] for x in week["entries"]])
        self.assertEqual(date.fromisoformat(week["from"]).weekday(), 0)
        tomorrow = (date.today() + timedelta(days=1)).isoformat()
        moved = self.patch(f"/mealplan/{pid}", json={"date": tomorrow, "meal_type": "dinner"}, token=tok).get_json()
        self.assertEqual((moved["date"], moved["meal_type"]), (tomorrow, "dinner"))
        rng = self.get(f"/mealplan?from={tomorrow}&to={tomorrow}", token=tok).get_json()
        self.assertEqual(len(rng["entries"]), 1)
        self.assertEqual(self.get("/mealplan?from=2026-01-01&to=2027-01-01", token=tok).status_code, 422)
        other = self.signup("planother")
        self.assertEqual(self.delete(f"/mealplan/{pid}", token=other).status_code, 403)
        # shopping from the plan
        self.assertEqual(self.post("/mealplan/shopping", json={"from": tomorrow, "to": tomorrow}, token=tok).get_json()["added"], 2)
        # sharing
        url = self.post("/mealplan/share", token=tok).get_json()["share_url"]
        token = url.rsplit("/", 1)[1]
        pub = self.c.get(f"{V1}/shared/mealplan/{token}?from={tomorrow}&to={tomorrow}")
        self.assertEqual(len(pub.get_json()["entries"]), 1)
        self.assertEqual(self.delete("/mealplan/share", token=tok).status_code, 204)
        self.assertEqual(self.c.get(f"{V1}/shared/mealplan/{token}").status_code, 404)
        self.assertEqual(self.delete(f"/mealplan/{pid}", token=tok).status_code, 204)

    def test_auto_generate(self):
        tok = self.signup("autoplanner")
        self.new_recipe("Filler")
        r = self.post("/mealplan/auto-generate", json={"meal_types": ["dinner", "lunch"]}, token=tok).get_json()
        self.assertEqual(r["added"], 14)
        again = self.post("/mealplan/auto-generate", json={"meal_types": ["dinner", "lunch"]}, token=tok).get_json()
        self.assertEqual(again["added"], 0)
        self.assertEqual(self.post("/mealplan/auto-generate", json={"meal_types": ["elevenses"]}, token=tok).status_code, 422)


class TestShopping(Api):
    def test_list_flow(self):
        tok = self.signup("shopper")
        self.assertEqual(self.post("/shopping/items", token=tok, json={"name": "2 cups flour"}).status_code, 201)
        r = self.post("/shopping/items", token=tok, json={"name": "1 cup flour"}).get_json()
        self.assertEqual((r["added"], r["merged"]), (0, 1))
        self.assertEqual(self.post("/shopping/items", token=tok, json={"names": ["milk", "eggs"]}).get_json()["added"], 2)
        self.assertEqual(self.post("/shopping/items", token=tok, json={"name": " "}).status_code, 422)
        lst = self.get("/shopping", token=tok).get_json()
        self.assertEqual(len(lst["items"]), 3)
        self.assertIn("Other", lst["aisle_order"])
        self.assertTrue(all(i["aisle"] for i in lst["items"]))
        item = next(i for i in lst["items"] if "flour" in i["name"])
        self.assertIsNone(item["recipe_title"])
        self.assertIn("3", item["name"])  # quantities combined
        upd = self.patch(f"/shopping/items/{item['id']}", token=tok, json={"checked": True}).get_json()
        self.assertTrue(upd["checked"])
        other = self.signup("shopother")
        self.assertEqual(self.patch(f"/shopping/items/{item['id']}", token=other, json={"checked": False}).status_code, 403)
        self.assertEqual(self.delete("/shopping/items?checked=1", token=tok).status_code, 204)
        self.assertEqual(len(self.get("/shopping", token=tok).get_json()["items"]), 2)
        one = self.get("/shopping", token=tok).get_json()["items"][0]["id"]
        self.assertEqual(self.delete(f"/shopping/items/{one}", token=tok).status_code, 204)
        self.assertEqual(self.delete("/shopping/items", token=tok).status_code, 204)
        self.assertEqual(self.get("/shopping", token=tok).get_json()["items"], [])

    def test_from_recipe(self):
        tok = self.signup("recipeshopper")
        rid = self.new_recipe("Stew", ingredients="# Veg\n2 carrots\n1 leek\n# Meat\n500 g beef")["id"]
        r = self.post(f"/shopping/recipe/{rid}", token=tok, json={"items": ["2 carrots", "# Veg"]}).get_json()
        self.assertEqual(r["added"], 1)
        self.assertEqual(self.get("/shopping", token=tok).get_json()["items"][0]["recipe_title"], "Stew")
        self.assertEqual(self.post(f"/shopping/recipe/{rid}", token=tok, json={"items": []}).status_code, 422)
        r = self.post(f"/shopping/recipe/{rid}", token=tok).get_json()
        self.assertEqual(r["added"], 2)
        self.assertEqual(r["merged"], 1)


class TestGuidesAndAdmin(Api):
    def test_extras_and_calculators(self):
        pages = self.get("/extras").get_json()["items"]
        slug = pages[0]["slug"]
        self.assertIsNotNone(self.post(f"/extras/{slug}/share").get_json()["share_url"])
        self.assertEqual(self.post("/extras/nope/share").status_code, 404)
        self.assertEqual(self.delete(f"/extras/{slug}/share").status_code, 204)
        calc = self.post("/calculators", json={"name": "Dough", "url": "https://x.test"}).get_json()
        self.assertEqual(calc["icon"], "🧮")
        self.assertEqual(self.post("/calculators", json={"name": "NoUrl"}).status_code, 422)
        self.assertEqual(self.patch(f"/calculators/{calc['id']}", json={"name": "Dough 2"}).get_json()["name"], "Dough 2")
        user = self.signup("calcuser")
        self.assertEqual(len(self.get("/calculators", token=user).get_json()["items"]), 1)
        self.assertEqual(self.post("/calculators", token=user, json={"name": "a", "url": "b"}).status_code, 403)
        self.assertEqual(self.delete(f"/calculators/{calc['id']}").status_code, 204)

    def test_admin_users(self):
        r = self.post("/admin/users", json={"username": "newbie", "is_admin": False})
        self.assertEqual(r.status_code, 201)
        body = r.get_json()
        self.assertTrue(body["temp_password"])
        login = self.c.post(f"{V1}/auth/login", json={"username": "newbie", "password": body["temp_password"]})
        self.assertEqual(login.status_code, 200)
        self.assertEqual(self.post("/admin/users", json={"username": "newbie"}).status_code, 409)
        uid = body["user"]["id"]
        self.assertEqual(self.patch(f"/admin/users/{uid}", json={"is_admin": True}).get_json()["is_admin"], True)
        self.patch(f"/admin/users/{uid}", json={"new_password": "Fr3sh-start-1"})
        self.assertEqual(self.get("/me", token=login.get_json()["token"]).status_code, 401)  # signed out
        me_id = self.get("/me").get_json()["id"]
        self.assertEqual(self.delete(f"/admin/users/{me_id}").status_code, 422)
        self.assertEqual(self.patch(f"/admin/users/{me_id}", json={"is_admin": False}).status_code, 422)
        self.assertEqual(self.delete(f"/admin/users/{uid}").status_code, 204)
        plain = self.signup("plainjoe")
        self.assertEqual(self.get("/admin/users", token=plain).status_code, 403)
        self.assertEqual(self.post("/categories", token=plain, json={"name": "Nope"}).status_code, 403)

    def test_admin_settings(self):
        s = self.patch("/admin/settings", json={"site_name": "Our Kitchen", "public_show_author": True,
                                                "store_name": "Coles",
                                                "store_search_url": "https://coles.test/?q={q}"}).get_json()
        self.assertEqual((s["site_name"], s["public_show_author"], s["store_name"]), ("Our Kitchen", True, "Coles"))
        self.assertEqual(self.patch("/admin/settings", json={"store_search_url": "https://x.test/"}).status_code, 422)
        self.assertEqual(self.c.get(f"{V1}/site").get_json()["name"], "Our Kitchen")
        item = self.post("/shopping/items", json={"name": "butter"})
        store_url = self.get("/shopping").get_json()["items"][0]["store_url"]
        self.assertTrue(store_url.startswith("https://coles.test/?q="))
        self.assertEqual(self.get("/admin/settings", token=self.signup("setnope")).status_code, 403)
        self.patch("/admin/settings", json={"public_show_author": False})


if __name__ == "__main__":
    unittest.main()
