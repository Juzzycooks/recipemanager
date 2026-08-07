"""Rough nutrition estimation from ingredient lines.

Matches ingredient text against a small built-in per-100g table and converts
common units to grams. This is a best-effort estimate for home cooks, not
medical-grade data — the UI must present it with a disclaimer.
"""
import re

# kcal, protein g, fat g, carbs g — per 100 g
_DB = {
    # Proteins
    "chicken breast": (165, 31, 3.6, 0), "chicken thigh": (209, 26, 11, 0),
    "chicken": (190, 27, 8, 0), "beef mince": (250, 26, 15, 0),
    "ground beef": (250, 26, 15, 0), "beef": (250, 26, 15, 0),
    "pork": (242, 27, 14, 0), "bacon": (541, 37, 42, 1.4),
    "lamb": (294, 25, 21, 0), "salmon": (208, 20, 13, 0),
    "tuna": (132, 28, 1.3, 0), "fish": (140, 25, 4, 0),
    "prawn": (99, 24, 0.3, 0.2), "shrimp": (99, 24, 0.3, 0.2),
    "tofu": (76, 8, 4.8, 1.9), "egg": (143, 13, 9.5, 0.7),
    "sausage": (300, 14, 26, 3),
    # Dairy
    "butter": (717, 0.9, 81, 0.1), "cream cheese": (342, 6, 34, 4),
    "cheddar": (404, 25, 33, 1.3), "mozzarella": (280, 28, 17, 3),
    "parmesan": (431, 38, 29, 4), "cheese": (350, 25, 27, 2),
    "cream": (340, 2.8, 36, 2.8), "yoghurt": (59, 10, 0.4, 3.6),
    "yogurt": (59, 10, 0.4, 3.6), "milk": (61, 3.2, 3.3, 4.8),
    # Carbs
    "flour": (364, 10, 1, 76), "sugar": (387, 0, 0, 100),
    "brown sugar": (380, 0, 0, 98), "honey": (304, 0.3, 0, 82),
    "rice": (365, 7, 0.7, 80), "pasta": (371, 13, 1.5, 75),
    "spaghetti": (371, 13, 1.5, 75), "orzo": (371, 13, 1.5, 75),
    "noodle": (138, 4.5, 0.2, 25), "bread": (265, 9, 3.2, 49),
    "breadcrumb": (395, 13, 5.3, 72), "oat": (389, 17, 6.9, 66),
    "potato": (77, 2, 0.1, 17), "sweet potato": (86, 1.6, 0.1, 20),
    "quinoa": (368, 14, 6, 64), "couscous": (376, 13, 0.6, 77),
    "tortilla": (310, 8, 7.5, 52), "corn": (86, 3.3, 1.4, 19),
    # Fats / oils / nuts
    "olive oil": (884, 0, 100, 0), "vegetable oil": (884, 0, 100, 0),
    "coconut oil": (892, 0, 99, 0), "oil": (884, 0, 100, 0),
    "peanut butter": (588, 25, 50, 20), "almond": (579, 21, 50, 22),
    "walnut": (654, 15, 65, 14), "cashew": (553, 18, 44, 30),
    "peanut": (567, 26, 49, 16), "sesame": (573, 18, 50, 23),
    # Vegetables
    "onion": (40, 1.1, 0.1, 9.3), "garlic": (149, 6.4, 0.5, 33),
    "tomato paste": (82, 4.3, 0.5, 19), "tomato": (18, 0.9, 0.2, 3.9),
    "carrot": (41, 0.9, 0.2, 9.6), "celery": (16, 0.7, 0.2, 3),
    "capsicum": (31, 1, 0.3, 6), "bell pepper": (31, 1, 0.3, 6),
    "pepper": (31, 1, 0.3, 6), "broccoli": (34, 2.8, 0.4, 6.6),
    "spinach": (23, 2.9, 0.4, 3.6), "mushroom": (22, 3.1, 0.3, 3.3),
    "zucchini": (17, 1.2, 0.3, 3.1), "cucumber": (15, 0.7, 0.1, 3.6),
    "lettuce": (15, 1.4, 0.2, 2.9), "cabbage": (25, 1.3, 0.1, 5.8),
    "cauliflower": (25, 1.9, 0.3, 5), "pea": (81, 5.4, 0.4, 14),
    "green bean": (31, 1.8, 0.2, 7), "avocado": (160, 2, 15, 8.5),
    "pumpkin": (26, 1, 0.1, 6.5), "eggplant": (25, 1, 0.2, 5.9),
    # Legumes / canned
    "chickpea": (164, 8.9, 2.6, 27), "lentil": (116, 9, 0.4, 20),
    "black bean": (132, 8.9, 0.5, 24), "kidney bean": (127, 8.7, 0.5, 23),
    "baked bean": (94, 4.8, 0.5, 18), "bean": (130, 8.5, 0.5, 23),
    "coconut milk": (230, 2.3, 24, 5.5), "coconut cream": (330, 3.6, 35, 6.6),
    # Fruit
    "lemon": (29, 1.1, 0.3, 9), "lime": (30, 0.7, 0.2, 11),
    "apple": (52, 0.3, 0.2, 14), "banana": (89, 1.1, 0.3, 23),
    "berry": (50, 0.7, 0.3, 12), "raisin": (299, 3.1, 0.5, 79),
    # Condiments / misc
    "soy sauce": (53, 8.1, 0.6, 4.9), "fish sauce": (42, 5, 0, 5),
    "oyster sauce": (51, 1.4, 0.3, 11), "tomato sauce": (82, 1.3, 0.3, 18),
    "ketchup": (112, 1.3, 0.3, 26), "mayonnaise": (680, 1, 75, 0.6),
    "mustard": (66, 4.4, 3.3, 5.8), "vinegar": (18, 0, 0, 0.9),
    "wine": (83, 0.1, 0, 2.6), "stock": (5, 0.4, 0.2, 0.4),
    "broth": (5, 0.4, 0.2, 0.4), "chocolate": (546, 4.9, 31, 61),
    "cocoa": (228, 20, 14, 58), "vanilla": (288, 0.1, 0.1, 13),
    "maple syrup": (260, 0, 0.1, 67), "salt": (0, 0, 0, 0),
}

# Grams per unit (approximate cooking averages)
_UNIT_GRAMS = {
    "g": 1, "gram": 1, "grams": 1, "kg": 1000, "kilogram": 1000, "kilograms": 1000,
    "mg": 0.001,
    "ml": 1, "millilitre": 1, "milliliter": 1, "l": 1000, "litre": 1000, "liter": 1000,
    "cup": 240, "cups": 240,
    "tbsp": 15, "tablespoon": 15, "tablespoons": 15,
    "tsp": 5, "teaspoon": 5, "teaspoons": 5,
    "oz": 28.35, "ounce": 28.35, "ounces": 28.35,
    "lb": 453.6, "lbs": 453.6, "pound": 453.6, "pounds": 453.6,
    "can": 400, "cans": 400, "tin": 400, "tins": 400,
    "clove": 5, "cloves": 5,
    "pinch": 0.5, "pinches": 0.5, "dash": 0.5,
    "handful": 30, "bunch": 80, "slice": 25, "slices": 25,
    "stick": 113, "sticks": 113,  # butter sticks
}

# Approximate grams for "1 <item>" with no unit
_ITEM_GRAMS = {
    "egg": 50, "onion": 110, "carrot": 60, "potato": 170, "tomato": 120,
    "zucchini": 200, "capsicum": 120, "bell pepper": 120, "lemon": 60,
    "lime": 45, "apple": 180, "banana": 120, "avocado": 150, "garlic": 5,
    "chicken breast": 175, "chicken thigh": 130, "sausage": 70, "tortilla": 45,
    "cucumber": 250, "eggplant": 350,
}

_FRACTIONS = {"½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1 / 3, "⅔": 2 / 3, "⅛": 0.125}

_QTY_RE = re.compile(
    r"^\s*(?P<qty>\d+\s+\d/\d|\d+/\d|\d*[.,]?\d+|[½¼¾⅓⅔⅛])\s*"
    r"(?P<frac>[½¼¾⅓⅔⅛])?\s*"
    r"(?P<unit>[a-zA-Z]+)?\.?\s+(?P<rest>.+)$"
)


def _parse_qty(text):
    """Parse leading quantity, returns (number|None, unit|None, rest)."""
    text = text.strip().lstrip("-•● ").strip()
    if text in _FRACTIONS:
        return _FRACTIONS[text], None, ""
    m = _QTY_RE.match(text)
    if not m:
        return None, None, text
    raw = m.group("qty")
    try:
        if raw in _FRACTIONS:
            qty = _FRACTIONS[raw]
        elif "/" in raw:
            if " " in raw:  # "1 1/2"
                whole, frac = raw.split()
                num, den = frac.split("/")
                qty = float(whole) + float(num) / float(den)
            else:
                num, den = raw.split("/")
                qty = float(num) / float(den)
        else:
            qty = float(raw.replace(",", "."))
    except (ValueError, ZeroDivisionError):
        return None, None, text
    if m.group("frac"):
        qty += _FRACTIONS[m.group("frac")]
    unit = (m.group("unit") or "").lower()
    rest = m.group("rest").strip()
    if unit and unit not in _UNIT_GRAMS:
        # "2 large onions" — treat the word as part of the name
        rest = f"{unit} {rest}"
        unit = None
    return qty, unit or None, rest


def _match_food(name):
    """Find the best (longest) matching food key in the lowered name."""
    lowered = name.lower()
    best = None
    for key in _DB:
        if key in lowered and (best is None or len(key) > len(best)):
            best = key
    return best


def estimate_line(line):
    """Estimate one ingredient line. Returns dict or None if unmatched."""
    qty, unit, rest = _parse_qty(line)
    food = _match_food(rest or line)
    if not food:
        return None
    if qty is None:
        qty = 1.0
    if unit:
        grams = qty * _UNIT_GRAMS[unit]
    else:
        grams = qty * _ITEM_GRAMS.get(food, 100)
    kcal, protein, fat, carbs = _DB[food]
    factor = grams / 100.0
    return {
        "food": food, "grams": grams,
        "kcal": kcal * factor, "protein": protein * factor,
        "fat": fat * factor, "carbs": carbs * factor,
    }


def estimate_recipe(ingredients_text, servings_text=""):
    """Estimate totals for a recipe. Returns dict or None if too few matches.

    Keys: kcal, protein, fat, carbs, matched, total_lines, per_serving (dict|None),
    servings (int|None).
    """
    lines = [l.strip() for l in (ingredients_text or "").split("\n")
             if l.strip() and not l.strip().startswith("# ")]
    if not lines:
        return None
    totals = {"kcal": 0.0, "protein": 0.0, "fat": 0.0, "carbs": 0.0}
    matched = 0
    for line in lines:
        est = estimate_line(line)
        if est:
            matched += 1
            for k in totals:
                totals[k] += est[k]
    # Require at least half the lines matched for a meaningful estimate
    if matched == 0 or matched < len(lines) / 2:
        return None

    servings = None
    m = re.search(r"\d+", servings_text or "")
    if m:
        s = int(m.group())
        if 1 <= s <= 100:
            servings = s

    result = {
        "kcal": round(totals["kcal"]),
        "protein": round(totals["protein"], 1),
        "fat": round(totals["fat"], 1),
        "carbs": round(totals["carbs"], 1),
        "matched": matched,
        "total_lines": len(lines),
        "servings": servings,
        "per_serving": None,
    }
    if servings and servings > 1:
        result["per_serving"] = {
            "kcal": round(totals["kcal"] / servings),
            "protein": round(totals["protein"] / servings, 1),
            "fat": round(totals["fat"] / servings, 1),
            "carbs": round(totals["carbs"] / servings, 1),
        }
    return result
