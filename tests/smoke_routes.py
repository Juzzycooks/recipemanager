"""Render smoke test: logs in and GETs every route with sample data; prints any server errors.
Run from the project root:  python tests/smoke_routes.py   (not collected by unittest discovery)."""
import os, re, sys, tempfile, gzip, traceback
os.environ["DATA_DIR"] = tempfile.mkdtemp()
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app import create_app
from models import db, User, Recipe, Category, Collection, Calculator, ExtraShare, ShoppingListItem
app = create_app(); app.config["WTF_CSRF_ENABLED"] = False; app.testing = True
with app.app_context():
    u = User(username="cook", email="c@example.com", is_admin=True); u.set_password("Sup3r-secret-pass!"); db.session.add(u)
    cat = Category(name="Dinner"); db.session.add(cat); db.session.flush()
    for i, (t, img) in enumerate([("Pastéis de Nata", ""), ("A very long recipe title that just keeps going and going to test wrapping behaviour of cards", "recipe_x.jpg"), ("Shish Barak", "")]):
        r = Recipe(title=t, description="A lovely dish.", ingredients="# Dough\n2 cups flour\n1 tsp salt\n3 eggs", instructions="# Make\nMix everything.\nBake for 20 minutes.", image_url=img, user_id=1, prep_time="20 min", cook_time="30 min", servings="4")
        r.categories.append(cat); db.session.add(r)
    db.session.flush()
    c = Collection(name="Weeknights", description="Quick dinners", user_id=1, share_token="tok123", slug="weeknights"); db.session.add(c)
    db.session.add(ShoppingListItem(name="Flour", user_id=1))
    try: db.session.add(Calculator(name="Dough", url="https://example.com", icon="🍕"))
    except Exception as e: print("calc", e)
    db.session.commit()
    r1 = Recipe.query.first(); r1.share_token = "rectok"; c.recipes.append(r1); db.session.commit()
c = app.test_client()
r = c.post("/login", data={"username": "cook", "password": "Sup3r-secret-pass!"}, follow_redirects=False); print("login", r.status_code)
bad = 0; n = 0
subs = {"int": "1", "string": "tok123", "path": "x", "uuid": "x"}
for rule in sorted(app.url_map.iter_rules(), key=lambda r: r.rule):
    if "GET" not in rule.methods or rule.endpoint == "static": continue
    if any(k in rule.rule for k in ("logout", "random", "export", "backup", "api/", "media", "uploads", "download")): continue
    def sub(m):
        arg = m.group(1)
        if arg == "token":
            return "rectok" if "collections" not in rule.rule else "tok123"
        if arg == "slug": return "weeknights"
        return "1"
    path = re.sub(r"<(?:\w+:)?(\w+)>", sub, rule.rule)
    try:
        resp = c.get(path, headers={"Accept-Encoding": "gzip"}, follow_redirects=True)
        body = resp.get_data(); body = gzip.decompress(body) if resp.headers.get("Content-Encoding") == "gzip" else body
        n += 1
        flag = "" if resp.status_code < 400 else "  <-- %d" % resp.status_code
        if resp.status_code >= 500: bad += 1
        print("%3d %-46s %6d bytes%s" % (resp.status_code, path, len(body), flag))
    except Exception as e:
        bad += 1; n += 1; print("EXC", path, type(e).__name__, str(e)[:200])
for p in ["/extras/pizza-dough-calculator","/extras/sourdough-guide","/calculators/1","/recipe/1","/recipe/2","/recipe/3","/recipe/1/cook","/recipe/1/print","/recipe/1/edit","/recipe/1/cook-history","/collections/1","/collections/1/edit","/collections/shared/tok123/recipe/1","/collections/shared/tok123/recipe/1/cook","/shared/rectok","/static/pages/pasteis-de-nata.html","/static/pages/meal-plan.html","/static/pages/shish-barak.html","/static/pages/sourdough-guide.html","/static/pages/pizza-dough-calculator.html","/recipes/?view=list","/?view=list","/?q=flour","/?ingredient=flour","/shopping/"]:
    resp = c.get(p, headers={"Accept-Encoding": "gzip"}, follow_redirects=True); n += 1
    body = resp.get_data(); body = gzip.decompress(body) if resp.headers.get("Content-Encoding") == "gzip" else body
    if resp.status_code >= 500: bad += 1
    print("%3d %-46s %6d bytes" % (resp.status_code, p, len(body)))
print("routes", n, "server errors", bad)
