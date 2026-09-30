"""Fills a fresh Spoonmate server with a small demo library (original recipes, hand-drawn flat illustrations as the
pictures, collections, a meal plan and a shopping list). Used to take the screenshots in the README.

    DATA_DIR=/tmp/spoonmate-demo python3 -c "from app import create_app; create_app().run(port=5078)"   # a fresh server
    python3 tools/seed_demo.py http://localhost:5078                                                     # then seed it

Creates the admin user `Alex` with password `Spoonmate-demo-1`. Needs Pillow. Run it against a new, empty server only.
"""
import io, json, math, random, sys, urllib.request, uuid
from datetime import date, timedelta
from PIL import Image, ImageDraw, ImageFilter

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:5078").rstrip("/") + "/api/v1"
USER, PASSWORD = "Alex", "Spoonmate-demo-1"
W, H = 1200, 900


# ── tiny API client ──
def call(method, path, body=None, token=None, files=None):   # files: {field: (filename, bytes)}
    headers = {"Accept": "application/json"}
    if token: headers["Authorization"] = f"Bearer {token}"
    data = None
    if files:
        boundary = uuid.uuid4().hex
        data = b""
        for name, (filename, blob) in files.items():
            data += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"; filename=\"{filename}\"\r\n"
                     f"Content-Type: image/png\r\n\r\n").encode() + blob + b"\r\n"
        data += f"--{boundary}--\r\n".encode()
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
    elif body is not None:
        data = json.dumps(body).encode(); headers["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    with urllib.request.urlopen(req) as resp:
        raw = resp.read()
    return json.loads(raw) if raw else None


# ── illustrations: top-down plates drawn with flat shapes ──
def blob(d, cx, cy, rx, ry, fill, tilt=0):
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=fill)

def leaf(d, cx, cy, length, width, angle, fill):
    pts = []
    for i in range(21):
        t = i / 20; b = math.sin(math.pi * t) ** 0.8 * width / 2
        pts.append((t * length, b))
    pts += [(x, -y) for x, y in reversed(pts)]
    a = math.radians(angle)
    d.polygon([(cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)) for x, y in pts], fill=fill)

def plate(bg, plate_fill=(250, 248, 243), rim=(232, 228, 219), r=330, shadow=True):
    img = Image.new("RGB", (W, H), bg); d = ImageDraw.Draw(img)
    cx, cy = W // 2, H // 2
    if shadow:
        sh = Image.new("RGBA", (W, H), (0, 0, 0, 0)); ImageDraw.Draw(sh).ellipse([cx - r, cy - r + 26, cx + r, cy + r + 26], fill=(0, 0, 0, 70))
        img.paste(sh.filter(ImageFilter.GaussianBlur(22)), (0, 0), sh.filter(ImageFilter.GaussianBlur(22)))
        d = ImageDraw.Draw(img)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=rim)
    d.ellipse([cx - r + 18, cy - r + 18, cx + r - 18, cy + r - 18], fill=plate_fill)
    return img, d, cx, cy

def soup():
    img, d, cx, cy = plate((212, 196, 170), r=340)
    for i, c in enumerate([(178, 62, 38), (192, 74, 44), (204, 88, 52), (214, 104, 62)]):
        rr = 270 - i * 38; d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=c)
    for k in range(3):
        d.arc([cx - 110 + k * 12, cy - 70, cx + 110 - k * 12, cy + 80], 200, 340, fill=(250, 240, 222), width=16)
    for ang in (-40, 70, 190):
        leaf(d, cx + 30, cy + 10, 120, 54, ang, (52, 112, 66))
    rnd = random.Random(3)
    for _ in range(26): x, y = cx + rnd.randint(-200, 200), cy + rnd.randint(-200, 200); d.ellipse([x, y, x + 6, y + 6], fill=(60, 30, 24))
    return img

def pasta():
    img, d, cx, cy = plate((205, 214, 204))
    rnd = random.Random(5)
    for _ in range(46):
        a = rnd.uniform(0, math.tau); rr = rnd.uniform(40, 190)
        x, y = cx + math.cos(a) * rr * 0.6, cy + math.sin(a) * rr * 0.6
        d.arc([x - 120, y - 70, x + 120, y + 70], rnd.randint(0, 360), rnd.randint(0, 360) + 140,
              fill=rnd.choice([(236, 204, 120), (226, 190, 100), (242, 216, 140)]), width=16)
    for _ in range(40): x, y = cx + rnd.randint(-170, 170), cy + rnd.randint(-130, 130); d.ellipse([x, y, x + 12, y + 8], fill=(70, 130, 64))
    for _ in range(14): x, y = cx + rnd.randint(-150, 150), cy + rnd.randint(-110, 110); d.ellipse([x, y, x + 22, y + 14], fill=(248, 240, 214))
    return img

def salad():
    img, d, cx, cy = plate((222, 206, 178), r=345)
    rnd = random.Random(8)
    for _ in range(9): leaf(d, cx + rnd.randint(-120, 120), cy + rnd.randint(-120, 120), 170, 74, rnd.randint(0, 360), (118, 160, 78))
    for _ in range(9):
        x, y = cx + rnd.randint(-190, 190), cy + rnd.randint(-190, 190)
        d.ellipse([x - 40, y - 40, x + 40, y + 40], fill=(168, 204, 120)); d.ellipse([x - 30, y - 30, x + 30, y + 30], fill=(212, 232, 176))
    for _ in range(8):
        x, y = cx + rnd.randint(-190, 190), cy + rnd.randint(-190, 190); d.pieslice([x - 48, y - 48, x + 48, y + 48], rnd.randint(0, 300), rnd.randint(0, 300) + 150, fill=(204, 58, 44))
    for _ in range(6):
        x, y = cx + rnd.randint(-180, 180), cy + rnd.randint(-180, 180); d.arc([x - 40, y - 40, x + 40, y + 40], 0, 340, fill=(150, 70, 140), width=10)
    for _ in range(8): x, y = cx + rnd.randint(-190, 190), cy + rnd.randint(-190, 190); d.rectangle([x, y, x + 44, y + 44], fill=(250, 248, 240))
    for _ in range(7): x, y = cx + rnd.randint(-190, 190), cy + rnd.randint(-190, 190); blob(d, x, y, 22, 28, (58, 40, 52))
    return img

def pancakes():
    img, d, cx, cy = plate((236, 214, 186), r=335)
    d.ellipse([cx - 240, cy - 230, cx + 240, cy + 250], fill=(196, 140, 82)); d.ellipse([cx - 222, cy - 214, cx + 222, cy + 232], fill=(226, 174, 108))
    d.ellipse([cx - 170, cy - 160, cx + 170, cy + 180], fill=(238, 190, 122))
    rnd = random.Random(2)
    for _ in range(34):
        x, y = cx + rnd.randint(-190, 190), cy + rnd.randint(-170, 190)
        if (x - cx) ** 2 + (y - cy) ** 2 < 200 ** 2: d.ellipse([x, y, x + 30, y + 30], fill=(58, 70, 140)); d.ellipse([x + 7, y + 6, x + 15, y + 13], fill=(120, 136, 204))
    d.rounded_rectangle([cx - 50, cy - 50, cx + 50, cy + 30], radius=14, fill=(252, 232, 130)); d.rounded_rectangle([cx - 50, cy - 50, cx + 50, cy - 20], radius=14, fill=(255, 244, 170))
    d.ellipse([cx + 40, cy + 10, cx + 210, cy + 150], fill=(194, 104, 34))
    return img

def curry():
    img, d, cx, cy = plate((204, 190, 166), r=345)
    d.ellipse([cx - 290, cy - 290, cx + 290, cy + 290], fill=(250, 248, 243)); d.ellipse([cx - 268, cy - 268, cx + 268, cy + 268], fill=(214, 122, 40))
    d.ellipse([cx - 210, cy - 210, cx + 210, cy + 210], fill=(228, 142, 54))
    rnd = random.Random(11)
    for _ in range(11):
        x, y = cx + rnd.randint(-150, 150), cy + rnd.randint(-150, 150); d.rounded_rectangle([x - 34, y - 26, x + 34, y + 26], radius=18, fill=(250, 224, 176))
    for _ in range(14): leaf(d, cx + rnd.randint(-160, 160), cy + rnd.randint(-160, 160), 54, 26, rnd.randint(0, 360), (60, 130, 70))
    d.pieslice([cx + 130, cy + 80, cx + 360, cy + 320], 190, 350, fill=(252, 250, 244))
    for _ in range(50): x, y = cx + 170 + rnd.randint(0, 150), cy + 110 + rnd.randint(0, 40); d.ellipse([x, y, x + 12, y + 7], fill=(238, 234, 222))
    return img

def tart():
    img, d, cx, cy = plate((224, 222, 196), plate_fill=(244, 240, 228), r=345)
    d.ellipse([cx - 265, cy - 265, cx + 265, cy + 265], fill=(196, 150, 84)); d.ellipse([cx - 240, cy - 240, cx + 240, cy + 240], fill=(226, 186, 110))
    d.ellipse([cx - 205, cy - 205, cx + 205, cy + 205], fill=(246, 214, 76)); d.ellipse([cx - 150, cy - 150, cx + 150, cy + 150], fill=(250, 226, 106))
    for k in range(3):
        x, y = cx + [-70, 80, 0][k], cy + [-40, -10, 90][k]
        d.ellipse([x - 62, y - 62, x + 62, y + 62], fill=(255, 250, 214)); d.ellipse([x - 52, y - 52, x + 52, y + 52], fill=(250, 236, 130))
        for a in range(0, 360, 45): d.line([x, y, x + math.cos(math.radians(a)) * 50, y + math.sin(math.radians(a)) * 50], fill=(255, 250, 214), width=4)
    for ang in (30, 160, 280): leaf(d, cx + 10, cy + 10, 90, 40, ang, (70, 140, 84))
    return img

def shakshuka():
    img, d, cx, cy = plate((206, 192, 172), plate_fill=(58, 54, 52), rim=(40, 38, 36), r=350)
    d.rounded_rectangle([cx + 330, cy - 26, cx + 560, cy + 26], radius=20, fill=(40, 38, 36))
    d.ellipse([cx - 300, cy - 300, cx + 300, cy + 300], fill=(176, 52, 36)); d.ellipse([cx - 250, cy - 250, cx + 250, cy + 250], fill=(196, 68, 44))
    for x, y in [(-120, -90), (110, -60), (-10, 110)]:
        blob(d, cx + x, cy + y, 92, 84, (252, 250, 244)); blob(d, cx + x + 4, cy + y + 6, 44, 44, (246, 184, 40)); blob(d, cx + x - 10, cy + y - 8, 12, 12, (255, 226, 130))
    rnd = random.Random(4)
    for _ in range(26): leaf(d, cx + rnd.randint(-210, 210), cy + rnd.randint(-210, 210), 40, 18, rnd.randint(0, 360), (70, 140, 76))
    return img

def banana_bread():
    img = Image.new("RGB", (W, H), (214, 196, 170)); d = ImageDraw.Draw(img)
    d.rounded_rectangle([90, 110, W - 90, H - 110], radius=44, fill=(178, 132, 88)); d.rounded_rectangle([110, 130, W - 110, H - 130], radius=34, fill=(194, 150, 104))
    for k in range(12): d.line([130, 170 + k * 52, W - 130, 170 + k * 52], fill=(186, 140, 94), width=3)
    for k in range(3):
        x = 250 + k * 250
        d.rounded_rectangle([x, 210, x + 330, 700], radius=70, fill=(118, 76, 40)); d.rounded_rectangle([x + 18, 228, x + 312, 682], radius=56, fill=(214, 168, 104))
        rnd = random.Random(k)
        for _ in range(18): px, py = x + rnd.randint(50, 280), 260 + rnd.randint(0, 400); d.ellipse([px, py, px + 12, py + 10], fill=(132, 88, 52))
    for k in range(3):
        x, y = 880 + k * 10, 250 + k * 150; d.ellipse([x, y, x + 120, y + 120], fill=(246, 226, 150)); d.ellipse([x + 16, y + 16, x + 104, y + 104], fill=(252, 240, 184))
    return img


ART = {"Tomato Basil Soup": soup, "Garlic Butter Pasta": pasta, "Greek Salad": salad, "Blueberry Pancakes": pancakes,
       "Coconut Chicken Curry": curry, "Lemon Tart": tart, "Shakshuka": shakshuka, "Banana Bread": banana_bread}

# ── the library ──
RECIPES = [
    dict(title="Tomato Basil Soup", description="Silky, slow-simmered tomato soup with a swirl of cream. Better the next day.",
         prep_time="15 min", cook_time="35 min", servings="4", cats=["Dinner", "Healthy"], fav=True, rating=5,
         ingredients="# Soup\n2 tbsp olive oil\n1 large onion, diced\n3 cloves garlic, sliced\n2 x 400 g tins whole tomatoes\n2 cups vegetable stock\n1 tsp sugar\n# To finish\n1/2 cup cream\nFresh basil leaves\nSalt and black pepper",
         instructions="# Soup\nSoften the onion in the olive oil over medium heat for 8 minutes.\nAdd the garlic and cook for 1 minute until fragrant.\nTip in the tomatoes, stock and sugar, then simmer for 20 minutes.\n# To finish\nBlend until completely smooth and stir through the cream.\nSeason to taste and serve with torn basil.",
         notes="Add a parmesan rind while it simmers for extra depth."),
    dict(title="Garlic Butter Pasta", description="Twenty-minute weeknight pasta with lots of garlic, lemon and parmesan.",
         prep_time="5 min", cook_time="15 min", servings="2", cats=["Dinner"], fav=False, rating=4,
         ingredients="200 g spaghetti\n4 tbsp butter\n5 cloves garlic, minced\n1 lemon, zest and juice\n1/2 cup grated parmesan\nChopped parsley\nChilli flakes",
         instructions="Cook the spaghetti in well-salted water for 10 minutes, saving a cup of the water.\nMelt the butter and cook the garlic for 1 to 2 minutes without browning it.\nToss in the pasta with a splash of pasta water, the lemon and the parmesan.\nFinish with parsley and chilli flakes."),
    dict(title="Greek Salad", description="Crunchy, salty, bright. No lettuce, just good tomatoes.",
         prep_time="15 min", cook_time="", servings="4", cats=["Healthy"], fav=False, rating=4,
         ingredients="4 ripe tomatoes, cut in wedges\n1 cucumber, sliced\n1 small red onion, sliced thin\n150 g feta\n1/2 cup kalamata olives\n3 tbsp olive oil\n1 tbsp red wine vinegar\n1 tsp dried oregano",
         instructions="Combine the tomatoes, cucumber, onion and olives in a wide bowl.\nWhisk the oil, vinegar and oregano and pour over.\nTop with the feta and finish with a little more oregano."),
    dict(title="Blueberry Pancakes", description="Fluffy buttermilk pancakes, dotted with blueberries.",
         prep_time="10 min", cook_time="15 min", servings="4", cats=["Breakfast"], fav=True, rating=5,
         ingredients="# Batter\n1 1/2 cups plain flour\n2 tsp baking powder\n2 tbsp sugar\n1 1/4 cups buttermilk\n1 egg\n3 tbsp melted butter\n# To serve\n1 cup blueberries\nMaple syrup",
         instructions="# Batter\nWhisk the dry ingredients together, then the wet ingredients separately.\nFold them together gently and rest the batter for 5 minutes.\n# Cook\nCook spoonfuls in a buttered pan over medium heat for 2 minutes a side, pressing in the blueberries.\nStack and serve with maple syrup."),
    dict(title="Coconut Chicken Curry", description="A mild, creamy curry that comes together in one pan.",
         prep_time="15 min", cook_time="30 min", servings="4", cats=["Dinner"], fav=True, rating=5,
         ingredients="# Curry\n600 g chicken thighs, cubed\n1 onion, diced\n3 tbsp mild curry paste\n400 ml coconut milk\n1 cup chicken stock\n1 red capsicum, sliced\n# To serve\nCooked basmati rice\nFresh coriander\nLime wedges",
         instructions="# Curry\nBrown the chicken in a hot pan, then set aside.\nSoften the onion, stir in the curry paste and cook for 2 minutes.\nAdd the coconut milk, stock and chicken and simmer for 20 minutes.\nAdd the capsicum for the last 5 minutes.\n# To serve\nServe over rice with coriander and a squeeze of lime."),
    dict(title="Lemon Tart", description="A buttery shortcrust case with a sharp, silky lemon filling.",
         prep_time="30 min", cook_time="45 min", servings="8", cats=["Dessert"], fav=False, rating=4,
         ingredients="# Pastry\n1 1/2 cups plain flour\n100 g cold butter\n1/4 cup icing sugar\n1 egg yolk\n# Filling\n4 eggs\n3/4 cup caster sugar\n3/4 cup lemon juice\nZest of 2 lemons\n1/2 cup cream",
         instructions="# Pastry\nRub the butter into the flour and sugar, bind with the yolk and chill for 30 minutes.\nRoll out, line a tart tin and blind bake for 15 minutes.\n# Filling\nWhisk the filling ingredients until smooth and pour into the warm case.\nBake at 150 C for 25 minutes until just set with a slight wobble.\nCool completely before slicing."),
    dict(title="Shakshuka", description="Eggs poached in a spiced tomato and pepper sauce.",
         prep_time="10 min", cook_time="25 min", servings="3", cats=["Breakfast", "Dinner"], fav=False, rating=5,
         ingredients="2 tbsp olive oil\n1 onion, diced\n1 red capsicum, diced\n3 cloves garlic\n2 tsp cumin\n1 tsp smoked paprika\n1 tin crushed tomatoes\n6 eggs\nFeta and parsley, to serve",
         instructions="Soften the onion and capsicum in the oil for 8 minutes.\nStir in the garlic and spices for 1 minute.\nAdd the tomatoes and simmer for 10 minutes until thick.\nMake six wells, crack in the eggs and cover for 6 minutes.\nTop with feta and parsley and serve with bread."),
    dict(title="Banana Bread", description="Moist, deeply banana-y and impossible to stop slicing.",
         prep_time="15 min", cook_time="55 min", servings="10", cats=["Dessert", "Breakfast"], fav=False, rating=4,
         ingredients="3 very ripe bananas, mashed\n1/3 cup melted butter\n3/4 cup sugar\n1 egg\n1 tsp vanilla\n1 tsp baking soda\n1 1/2 cups plain flour\n1/2 cup walnuts, chopped",
         instructions="Heat the oven to 175 C and line a loaf tin.\nStir the butter into the mashed bananas, then the sugar, egg and vanilla.\nFold in the baking soda, flour and walnuts.\nBake for 55 minutes until a skewer comes out clean.\nCool in the tin for 10 minutes."),
]

if __name__ == "__main__":
    token = None
    try:
        token = call("POST", "/auth/setup", {"username": USER, "password": PASSWORD, "device_name": "seed"})["token"]
    except Exception:
        token = call("POST", "/auth/login", {"username": USER, "password": PASSWORD, "device_name": "seed"})["token"]
    cats = {}
    for name in ["Breakfast", "Dinner", "Dessert", "Healthy"]:
        try: cats[name] = call("POST", "/categories", {"name": name}, token)["id"]
        except Exception: pass
    if not cats:
        cats = {c["name"]: c["id"] for c in call("GET", "/categories", token=token)["items"]}
    ids = {}
    for r in RECIPES:
        rec = call("POST", "/recipes", {k: r[k] for k in ("title", "description", "prep_time", "cook_time", "servings", "ingredients", "instructions")}
                   | {"notes": r.get("notes", ""), "category_ids": [cats[c] for c in r["cats"]]}, token)
        ids[r["title"]] = rec["id"]
        buf = io.BytesIO(); ART[r["title"]]().save(buf, "PNG")
        call("PUT", f"/recipes/{rec['id']}/image", token=token, files={"image_file": ("photo.png", buf.getvalue())})
        if r["fav"]: call("PUT", f"/recipes/{rec['id']}/favorite", token=token)
        call("PUT", f"/recipes/{rec['id']}/rating", {"score": r["rating"]}, token)
    call("POST", f"/recipes/{ids['Tomato Basil Soup']}/made", token=token)
    call("POST", f"/recipes/{ids['Blueberry Pancakes']}/made", token=token)
    # collections
    for name, desc, titles in [("Weeknight Dinners", "Quick meals for busy evenings.", ["Garlic Butter Pasta", "Coconut Chicken Curry", "Shakshuka", "Tomato Basil Soup"]),
                               ("Weekend Baking", "Slow Sunday projects.", ["Lemon Tart", "Banana Bread", "Blueberry Pancakes"]),
                               ("Fresh & Light", "Bright, easy, vegetable-forward.", ["Greek Salad", "Tomato Basil Soup", "Shakshuka"])]:
        c = call("POST", "/collections", {"name": name, "description": desc}, token)
        for t in titles: call("POST", f"/collections/{c['id']}/recipes", {"recipe_id": ids[t]}, token)
        cover = io.BytesIO(); ART[titles[0] if name != "Weeknight Dinners" else "Coconut Chicken Curry"]().save(cover, "PNG")
        call("PATCH", f"/collections/{c['id']}", token=token, files={"cover_image": ("cover.png", cover.getvalue())})
        if name == "Weekend Baking": call("POST", f"/collections/{c['id']}/share", token=token)
    # meal plan for this week (Monday first)
    monday = date.today() - timedelta(days=date.today().weekday())
    for offset, title, meal in [(0, "Garlic Butter Pasta", "dinner"), (1, "Coconut Chicken Curry", "dinner"), (2, "Greek Salad", "lunch"),
                                (2, "Shakshuka", "dinner"), (3, "Tomato Basil Soup", "dinner"), (4, "Blueberry Pancakes", "breakfast"),
                                (5, "Lemon Tart", "dinner"), (6, "Banana Bread", "breakfast")]:
        call("POST", "/mealplan", {"recipe_id": ids[title], "date": (monday + timedelta(days=offset)).isoformat(), "meal_type": meal}, token)
    # shopping list
    call("POST", f"/shopping/recipe/{ids['Coconut Chicken Curry']}", token=token)
    call("POST", f"/shopping/recipe/{ids['Greek Salad']}", token=token)
    call("POST", "/shopping/items", {"names": ["Sourdough loaf", "Dishwasher tablets", "Oat milk"]}, token)
    print("seeded", len(ids), "recipes; sign in as", USER, "/", PASSWORD)
