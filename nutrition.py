"""Calories and macros for a recipe: the cook's own figure, the source site's, or an estimate.

The estimate reads each ingredient line, works out a weight in grams and looks the food up in
static/nutrition-foods.json (per 100 g, USDA FoodData Central). Cups of solids use grams_per_cup
from static/unit-ingredients.json, the same table the unit converter uses, so "1 cup flour" is
the same 120 g everywhere. It is a home cook's estimate, not medical data: pages that show it
carry a disclaimer.

Kept to Python 3.9 syntax so it can be tried outside the container.
"""
import json
import os
import re

_HERE = os.path.dirname(os.path.abspath(__file__))
_FOODS_PATH = os.path.join(_HERE, "static", "nutrition-foods.json")
_UNITS_PATH = os.path.join(_HERE, "static", "unit-ingredients.json")

# Same conventions as static/unitconv.js.
CUP_ML = 236.588
TBSP_ML = 14.7868
TSP_ML = 4.92892

_MASS = {"g": 1.0, "kg": 1000.0, "oz": 28.3495, "lb": 453.592, "mg": 0.001}
_VOLUME = {
    "ml": 1.0, "cl": 10.0, "dl": 100.0, "l": 1000.0, "cup": CUP_ML, "tbsp": TBSP_ML,
    "tsp": TSP_ML, "dsp": 10.0, "pint": 473.176, "quart": 946.353, "gallon": 3785.41,
    "floz": 29.5735, "dash": 0.6, "drop": 0.05, "splash": 10.0, "drizzle": 5.0, "glug": 15.0,
}
_PINCH_G = 0.35

# Unit words as written -> canonical unit.
_UNIT_WORDS = {
    "g": "g", "gm": "g", "gms": "g", "gr": "g", "gram": "g", "grams": "g", "gramme": "g", "grammes": "g",
    "kg": "kg", "kgs": "kg", "kilo": "kg", "kilos": "kg", "kilogram": "kg", "kilograms": "kg",
    "mg": "mg",
    "oz": "oz", "ounce": "oz", "ounces": "oz",
    "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb",
    "ml": "ml", "mls": "ml", "millilitre": "ml", "millilitres": "ml", "milliliter": "ml", "milliliters": "ml",
    "cl": "cl", "dl": "dl",
    "l": "l", "lt": "l", "ltr": "l", "litre": "l", "litres": "l", "liter": "l", "liters": "l",
    "cup": "cup", "cups": "cup", "c": "cup",
    "tbsp": "tbsp", "tbsps": "tbsp", "tbs": "tbsp", "tbl": "tbsp", "tbls": "tbsp", "tablespoon": "tbsp",
    "tablespoons": "tbsp",
    "tsp": "tsp", "tsps": "tsp", "teaspoon": "tsp", "teaspoons": "tsp",
    "dessertspoon": "dsp", "dessertspoons": "dsp", "dsp": "dsp",
    "pint": "pint", "pints": "pint", "pt": "pint", "quart": "quart", "quarts": "quart", "qt": "quart",
    "gallon": "gallon", "gallons": "gallon",
    "fl oz": "floz", "fl. oz": "floz", "fl.oz": "floz", "floz": "floz", "fluid ounce": "floz",
    "fluid ounces": "floz",
    "dash": "dash", "dashes": "dash", "drop": "drop", "drops": "drop", "splash": "splash",
    "splashes": "splash", "drizzle": "drizzle", "glug": "glug", "glugs": "glug",
    "pinch": "pinch", "pinches": "pinch",
}
_COUNT_UNITS = {
    "can": 400, "tin": 400, "jar": 300, "packet": 250, "pack": 250, "package": 250, "pkt": 250,
    "bag": 250, "box": 300, "bottle": 500, "carton": 1000, "tub": 250, "punnet": 250,
    "sachet": 10, "envelope": 7, "clove": 4, "slice": 30, "rasher": 30, "strip": 25, "sheet": 20,
    "stick": 113, "stalk": 40, "rib": 40, "sprig": 1, "bunch": 100, "head": 500, "bulb": 45,
    "piece": 50, "fillet": 150, "cube": 10, "knob": 15, "cm": 5, "inch": 12, "cob": 100, "ear": 100,
    "leaf": 1, "block": 250, "ball": 125, "scoop": 66, "wedge": 30, "square": 6, "bar": 100,
    "link": 70, "loaf": 650, "wheel": 200, "steak": 200, "portion": 150, "spear": 16, "stem": 15,
    "squeeze": 10, "dollop": 30, "shot": 30, "thumb": 15, "floret": 10, "handful": 30, "pat": 5,
    "cheek": 90, "ring": 40, "pot": 28, "tube": 140,
}
# Generic weights good enough to count as a real quantity when the food has none of its own.
_GENERIC_REAL = {"can", "tin", "clove", "slice", "rasher", "stick", "cube", "pat", "shot", "carton"}
# Containers whose bracketed weight is per item ("2 tins (400g)"); for plain items such as
# "2 chicken breasts (500g)" the bracket is the total unless it says "each".
_PACKAGES = {"can", "tin", "jar", "packet", "pack", "package", "pkt", "bag", "box", "bottle",
             "carton", "tub", "punnet", "sachet", "envelope", "block", "pot", "tube"}
_CANNED_WORDS = re.compile(r"(?<![\w-])(?:cans?|tins?|canned|tinned)(?![\w-])")

_SIZE_WORDS = {"small": "small", "medium": "medium", "medium-sized": "medium", "large": "large",
               "big": "large", "large-sized": "large", "extra large": "extra large",
               "extra-large": "extra large", "xl": "extra large", "jumbo": "jumbo", "mini": "small"}
_SIZE_FACTOR = {"small": 0.7, "medium": 1.0, "large": 1.3, "extra large": 1.5, "jumbo": 1.7}
_MODIFIERS = {"heaped", "heaping", "level", "rounded", "scant", "generous", "good", "packed",
              "firmly", "lightly", "loosely", "about", "approx", "approx.", "approximately",
              "around", "roughly", "~", "plus", "extra"}

_WORD_NUMBERS = {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                 "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
                 "half": 0.5, "dozen": 12, "couple": 2, "few": 3, "quarter": 0.25}

_FRACTIONS = {"½": "1/2", "⅓": "1/3", "⅔": "2/3", "¼": "1/4", "¾": "3/4", "⅕": "1/5", "⅖": "2/5",
              "⅗": "3/5", "⅘": "4/5", "⅙": "1/6", "⅚": "5/6", "⅛": "1/8", "⅜": "3/8", "⅝": "5/8",
              "⅞": "7/8"}

_NUM = r"(?:\d+\s+\d+/\d+|\d+/\d+|\d+(?:[.,]\d+)?)"
_RANGE_SEP = r"\s*(?:-|–|—|to|or)\s*"

_OPTIONAL = re.compile(r"(?<![\w-])optional(?![\w-])")
_SERVE_ONLY = re.compile(
    r"\b(?:to taste|for (?:serving|garnish(?:ing)?|dusting|drizzling|sprinkling|brushing|topping|"
    r"decoration|decorating)|to (?:serve|garnish|dust|sprinkle|decorate)|as needed|if needed|"
    r"as required|as desired|garnish)\b")
_FRYING = re.compile(r"\b(?:for (?:deep[- ]|shallow[- ]|pan[- ])?frying|deep[- ]frying|"
                     r"for greasing|to grease|for the (?:tin|pan|tray|dish)|greasing)\b")
_JUICE_OF = re.compile(r"\bjuice (?:of|from) (?:(\d+(?:\.\d+)?|\d+/\d+|a|an|one|two|three|four|half|½)\s+)?"
                       r"(?:(small|medium|large|big)\s+)?(lemon|lime|orange)s?\b")
_JUICE_G = {"lemon": 45, "lime": 30, "orange": 85}

_cache = {}


# ---------------------------------------------------------------------------- data

def _plurals(alias):
    words = alias.split(" ")
    last = words[-1]
    forms = {last, last + "s", last + "es"}
    if len(last) > 2 and last.endswith("y") and last[-2] not in "aeiou":
        forms.add(last[:-1] + "ies")
    if last.endswith("f"):
        forms.add(last[:-1] + "ves")
    if last.endswith("fe"):
        forms.add(last[:-2] + "ves")
    if last.endswith("o"):
        forms.add(last + "es")
    return {" ".join(words[:-1] + [f]) for f in forms}


def _alternation(names):
    alts = sorted(set(names), key=lambda s: (-len(s), s))
    return re.compile(r"(?<![\w-])(" + "|".join(re.escape(a) for a in alts) + r")(?![\w-])")


def _data():
    """Foods, the alias matcher and the cup table, rebuilt when either file changes."""
    stamp = (os.path.getmtime(_FOODS_PATH), os.path.getmtime(_UNITS_PATH))
    if _cache.get("stamp") == stamp:
        return _cache
    with open(_FOODS_PATH, encoding="utf-8") as f:
        foods_doc = json.load(f)
    with open(_UNITS_PATH, encoding="utf-8") as f:
        units_doc = json.load(f)
    foods = {}
    alias_to_food = {}
    for food in foods_doc["foods"]:
        foods[food["name"]] = food
        for alias in [food["name"]] + food.get("aka", []):
            for form in _plurals(_norm(alias)):
                alias_to_food.setdefault(form, food["name"])
    cups = {}
    for solid in units_doc.get("solids", []):
        for form in _plurals(_norm(solid["name"])):
            cups.setdefault(form, float(solid["grams_per_cup"]))
    for liquid in units_doc.get("liquids", []):
        for form in _plurals(_norm(liquid)):
            cups.setdefault(form, None)  # None = a liquid: measure by density
    _cache.clear()
    _cache.update(stamp=stamp, foods=foods, aliases=alias_to_food, food_re=_alternation(alias_to_food),
                  cups=cups, cup_re=_alternation(cups),
                  cup_by_name={_norm(s["name"]): float(s["grams_per_cup"])
                               for s in units_doc.get("solids", [])})
    return _cache


def food_count():
    return len(_data()["foods"])


# ---------------------------------------------------------------------------- parsing helpers

def _norm(text):
    text = (text or "").lower().replace("’", "'").replace("‘", "'").replace("⁄", "/")
    for ch, frac in _FRACTIONS.items():
        text = re.sub(r"(\d)" + ch, r"\1 " + frac, text)
        text = text.replace(ch, frac)
    return re.sub(r"\s+", " ", text).strip()


def _num(s):
    s = s.strip()
    m = re.fullmatch(r"(\d+)\s+(\d+)/(\d+)", s)
    if m:
        d = int(m.group(3))
        return int(m.group(1)) + (int(m.group(2)) / d if d else 0)
    m = re.fullmatch(r"(\d+)/(\d+)", s)
    if m:
        d = int(m.group(2))
        return int(m.group(1)) / d if d else None
    if re.fullmatch(r"\d{1,3}(?:,\d{3})+", s):
        return float(s.replace(",", ""))
    try:
        return float(s.replace(",", "."))
    except ValueError:
        return None


def _leading_qty(text):
    """(quantity, rest) for a number, range or word number at the start of the text."""
    m = re.match(r"(" + _NUM + r")(?:" + _RANGE_SEP + r"(" + _NUM + r"))?(?![\d/])", text)
    if m:
        a = _num(m.group(1))
        b = _num(m.group(2)) if m.group(2) else None
        if a is not None:
            q = (a + b) / 2 if b is not None and b >= a else a
            return q, text[m.end():]
    m = re.match(r"(one|two|three|four|five|six)\s+and\s+(?:a\s+)?(half|quarter)\b", text)
    if m:
        return _WORD_NUMBERS[m.group(1)] + _WORD_NUMBERS[m.group(2)], text[m.end():]
    m = re.match(r"(?:(a|an)\s+)?(half|quarter|dozen|couple|few)\s+(?:(?:a|an|of)\s+)*", text)
    if m:
        q = _WORD_NUMBERS[m.group(2)]
        return q, text[m.end():]
    m = re.match(r"(a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b\s*", text)
    if m:
        return _WORD_NUMBERS[m.group(1)], text[m.end():]
    return None, text


_UNIT_RE = re.compile(r"(" + "|".join(re.escape(u) for u in sorted(_UNIT_WORDS, key=len, reverse=True))
                      + r")\.?(?![a-z])")
_COUNT_FORMS = {}
for _u in _COUNT_UNITS:
    for _f in _plurals(_u):
        _COUNT_FORMS[_f] = _u
_COUNT_FORMS.update({"leaves": "leaf", "loaves": "loaf", "inches": "inch", "boxes": "box",
                     "bunches": "bunch", "pieces": "piece", "pcs": "piece", "pc": "piece"})
_COUNT_RE = re.compile(r"(" + "|".join(re.escape(u) for u in sorted(_COUNT_FORMS, key=len, reverse=True))
                       + r")\.?(?![\w-])")


def _take_unit(text):
    """(unit, kind, rest): kind is 'mass', 'volume', 'pinch', 'count' or None."""
    text = text.lstrip()
    m = _UNIT_RE.match(text)
    if m:
        unit = _UNIT_WORDS[m.group(1)]
        rest = text[m.end():]
        if unit == "cup" and m.group(1) == "c" and not re.match(r"\s", rest):
            return None, None, text
        kind = "mass" if unit in _MASS else "pinch" if unit == "pinch" else "volume"
        return unit, kind, rest
    m = _COUNT_RE.match(text)
    if m:
        return _COUNT_FORMS[m.group(1)], "count", text[m.end():]
    return None, None, text


def _take_modifiers(text):
    size = None
    while True:
        text = text.lstrip(" ,")
        m = re.match(r"(extra[- ]large|medium-sized|large-sized|[a-z.~]+)\b\.?", text)
        if not m:
            return size, text
        word = m.group(1)
        if word in _SIZE_WORDS:
            size = _SIZE_WORDS[word]
        elif word not in _MODIFIERS:
            return size, text
        text = text[m.end():]


_BRACKET_MASS = re.compile(r"\(([^)]*?)(" + _NUM + r")\s*(kg|g|grams?|oz|ounces?|lbs?|ml|l|litres?)\b([^)]*)\)")


def _parse_amount(line):
    """Work out how much of the ingredient a line asks for.

    Returns dict(qty, unit, kind, size, rest, bracket=(amount, unit_kind, each)|None, trailing).
    """
    text = re.sub(r"^[\s\-*•▢◦·]+", "", line)
    qty, rest = _leading_qty(text)
    multiplier = 1.0
    # "2 x 400g tins": the first number counts the second.
    if qty is not None:
        m = re.match(r"\s*[x×]\s*(?=\d)", rest)
        if m:
            q2, rest2 = _leading_qty(rest[m.end():])
            if q2 is not None:
                multiplier, qty, rest = qty, q2, rest2
    out = {"qty": qty, "mult": multiplier, "unit": None, "kind": None, "size": None, "bracket": None}
    # "2 (400g) tins" / "1 (14 oz) can"
    m = re.match(r"\s*\(\s*(?:about|approx\.?|around|~)?\s*(" + _NUM + r")\s*(kg|g|oz|lb|ml|l)\b[^)]*\)", rest)
    if qty is not None and m:
        out["bracket"] = (_num(m.group(1)), m.group(2), True)
        rest = rest[m.end():]
    size, rest = _take_modifiers(rest)
    if qty is not None:
        unit, kind, rest = _take_unit(rest)
        out.update(unit=unit, kind=kind)
        # "400g/14oz": keep the first figure.
        m = re.match(r"\s*/\s*" + _NUM + r"\s*[a-z.]*", rest)
        if m and kind in ("mass", "volume"):
            rest = rest[m.end():]
        # "400g tins tomatoes": the container word after a weight is not the food.
        if kind in ("mass", "volume"):
            m = re.match(r"\s*(?:\(\s*[^)]*\)\s*)?(" + "|".join(sorted(_PACKAGES, key=len, reverse=True))
                         + r")s?\b", rest)
            if m:
                rest = rest[m.end():]
        s2, rest = _take_modifiers(rest)
        size = size or s2
        if out["unit"] is None:
            unit, kind, rest2 = _take_unit(rest)
            if kind == "count":
                out.update(unit=unit, kind=kind)
                rest = rest2
    rest = re.sub(r"^\s*of\b", "", rest).strip(" ,")
    out["size"] = size
    out["rest"] = rest
    if out["bracket"] is None:
        m = _BRACKET_MASS.search(line)
        if m:
            each = "each" in (m.group(1) + m.group(4))
            total = re.search(r"\b(?:total|in total|altogether|combined)\b", m.group(1) + m.group(4))
            out["bracket"] = (_num(m.group(2)), _bracket_unit(m.group(3)), each and not total)
    if qty is None:
        m = re.search(r"(?<![\w/])(" + _NUM + r")\s*(kg|g|grams?|ml|l|litres?|oz|lbs?)(?![\w])", line)
        if m:
            out.update(qty=_num(m.group(1)), unit=_UNIT_WORDS.get(m.group(2), _bracket_unit(m.group(2))))
            out["kind"] = "mass" if out["unit"] in _MASS else "volume"
            out["trailing"] = True
    return out


def _bracket_unit(u):
    u = u.rstrip("s") if u not in ("g",) else u
    return {"gram": "g", "ounce": "oz", "litre": "l", "lb": "lb"}.get(u, u)


def _strip_brackets(text):
    return re.sub(r"\([^)]*\)|\[[^\]]*\]", " ", text)


# ---------------------------------------------------------------------------- matching

def _match_food(text):
    d = _data()
    m = d["food_re"].search(text)
    if not m:
        return None, None
    return d["foods"][d["aliases"][m.group(1)]], m


def _grams_per_cup(food, food_m, rest, variant_from):
    d = _data()
    if variant_from:
        if food.get("cup"):
            return float(food["cup"])
        by_name = d["cup_by_name"].get(_norm(food["name"]))
        if by_name:
            return by_name
    m = d["cup_re"].search(rest)
    liquid = False
    if m and food_m and m.start() >= food_m.start() and m.end() <= food_m.end() \
            and m.group(1).split(" ")[-1] == food_m.group(1).split(" ")[-1]:
        gpc = d["cups"][m.group(1)]
        if gpc:
            return gpc
        liquid = True
    if food.get("cup"):
        return float(food["cup"])
    if food.get("density"):
        return CUP_ML * float(food["density"])
    if liquid:
        return CUP_ML
    return 140.0


def _variant(food, line):
    """The cooked / canned / dried / skin-on form when the line says so."""
    foods = _data()["foods"]
    checks = (
        ("cooked", r"(?<![\w])(?:cooked|boiled|steamed|leftover)(?![\w])"),
        ("canned", r"(?<![\w-])(?:cans?|tins?|canned|tinned)(?![\w-])"),
        ("dried", r"(?<![\w-])(?:dried|dry)(?![\w-])"),
        ("skin_on", r"(?<![\w])(?:skin-on|skin on|bone-in|bone in|with skin)(?![\w])"),
    )
    for key, pattern in checks:
        target = food.get(key)
        if target and target in foods and re.search(pattern, line):
            if key == "cooked" and re.search(r"\b(?:uncooked|raw)\b", line):
                continue
            return foods[target]
    return None


def _round_grams(g):
    if g is None:
        return None
    return round(g) if g >= 10 else round(g, 1)


def estimate_line(line):
    """One ingredient line -> {text, food, grams, kcal, protein, fat, carbs, status, real}.

    status: 'matched' (counted), 'negligible' (salt, spices, water, optional or garnish lines:
    shown but left out of the coverage count) or 'unmatched'. real is True when the weight came
    from a stated quantity rather than a guess.
    """
    raw = (line or "").strip()
    text = _norm(raw)
    result = {"text": raw, "food": None, "grams": None, "kcal": None, "protein": None,
              "fat": None, "carbs": None, "status": "unmatched", "real": False}
    if not text:
        return result

    foods = _data()["foods"]
    jm = _JUICE_OF.search(text)
    if jm:
        q = jm.group(1)
        qty = 1.0 if not q else (_WORD_NUMBERS.get(q) or _num(q.replace("½", "1/2")) or 1.0)
        size = _SIZE_FACTOR.get(_SIZE_WORDS.get(jm.group(2) or "", "medium"), 1.0)
        food = foods["orange juice" if jm.group(3) == "orange" else "lemon juice"]
        return _fill(result, food, qty * _JUICE_G[jm.group(3)] * size, True, text)

    amt = _parse_amount(text)
    rest = amt["rest"]
    food, food_m = _match_food(_strip_brackets(rest))
    if not food:
        food, food_m = _match_food(_strip_brackets(text))
    if not food:
        food, food_m = _match_food(text)
    if not food:
        return result

    qty, unit, kind = amt["qty"], amt["unit"], amt["kind"]
    if food.get("count_as") and qty is not None and kind in (None, "count") \
            and food["count_as"] in foods:
        food = foods[food["count_as"]]
    variant = _variant(food, text)
    if variant:
        food = variant

    grams, real = None, False
    mult = amt["mult"]
    bracket = amt["bracket"]
    if qty is not None:
        if bracket and bracket[0] and kind != "mass" and bracket[1] in _MASS:
            per = bracket[0] * _MASS[bracket[1]]
            per_item = bracket[2] or unit in _PACKAGES
            grams = per * (qty if per_item else 1) * mult
            real = True
        elif bracket and bracket[0] and kind == "count" and bracket[1] in ("ml", "l"):
            grams = bracket[0] * (1000 if bracket[1] == "l" else 1) * float(food.get("density", 1.0)) * qty * mult
            real = True
        elif kind == "mass":
            grams = qty * _MASS[unit] * mult
            real = True
        elif kind == "volume":
            ml = qty * _VOLUME[unit] * mult
            grams = ml / CUP_ML * _grams_per_cup(food, food_m, _strip_brackets(rest), variant)
            real = True
        elif kind == "pinch":
            grams = qty * _PINCH_G * mult
            real = True
        elif kind == "count":
            units = food.get("units", {})
            if unit in units:
                grams, real = qty * units[unit], True
            elif unit == "piece" and food.get("each"):
                grams, real = qty * food["each"], True
            else:
                grams, real = qty * _COUNT_UNITS[unit], unit in _GENERIC_REAL
            grams *= mult
        else:
            each = _each(food, amt["size"])
            if each:
                grams, real = qty * each * mult, True
            else:
                grams, real = qty * 100.0 * mult, False
        if grams is not None and food.get("drained") and _CANNED_WORDS.search(text) and kind != "volume":
            grams *= float(food["drained"])
    else:
        each = _each(food, amt["size"])
        if each:
            grams = each

    status = "matched"
    if food.get("negligible"):
        status = "negligible"
    if _OPTIONAL.search(text):
        status, grams = "negligible", None
    elif _FRYING.search(text) and (qty is None or kind == "volume" and grams and grams > 120):
        status, grams = "negligible", None
    elif qty is None and _SERVE_ONLY.search(text):
        status, grams = "negligible", None
    elif grams is None and status == "matched":
        status = "unmatched"

    result = _fill(result, food, grams, real, text)
    result["status"] = status
    return result


def _each(food, size):
    if size and food.get("sizes", {}).get(size):
        return float(food["sizes"][size])
    if food.get("each"):
        return float(food["each"]) * _SIZE_FACTOR.get(size or "medium", 1.0)
    return None


def _fill(result, food, grams, real, text):
    result.update(food=food["name"], real=bool(real),
                  status="negligible" if food.get("negligible") else "matched")
    if grams is not None:
        f = grams / 100.0
        result.update(grams=grams, kcal=food["kcal"] * f, protein=food["protein"] * f,
                      fat=food["fat"] * f, carbs=food["carbs"] * f)
    return result


def _is_heading(line):
    s = line.strip()
    if s.startswith("#"):
        return True
    if not re.search(r"\d", s):
        if s.endswith(":"):
            return True
        if re.fullmatch(r"(?i)for (?:the )?[a-z' ]{2,40}", s):
            return True
    return False


def analyse(ingredients_text):
    """Every line estimated, plus totals. None when there are no ingredient lines."""
    lines = [l for l in (ingredients_text or "").splitlines() if l.strip() and not _is_heading(l)]
    if not lines:
        return None
    rows = [estimate_line(l) for l in lines]
    tot = {"kcal": 0.0, "protein": 0.0, "fat": 0.0, "carbs": 0.0}
    for r in rows:
        if r["status"] in ("matched", "negligible") and r["kcal"] is not None:
            for k in tot:
                tot[k] += r[k]
    counted = [r for r in rows if r["status"] != "negligible"]
    matched = [r for r in counted if r["status"] == "matched"]
    real = [r for r in matched if r["real"]]
    return dict(tot, rows=rows, total_lines=len(rows), counted=len(counted), matched=len(matched),
                negligible=len(rows) - len(counted), real=len(real))


def _confidence(a):
    share = a["real"] / a["counted"] if a["counted"] else 0
    return "high" if share >= 0.85 else "medium" if share >= 0.6 else "low"


def _usable(a):
    return bool(a) and a["counted"] > 0 and a["matched"] / a["counted"] >= 0.5


# ---------------------------------------------------------------------------- servings

_SERVING_WORDS = {"serving", "servings", "serves", "serve", "people", "person", "persons",
                  "portion", "portions", "adults", "adult", "pax", "guests", "guest", "plates"}
_YIELD_SKIP = {"x", "about", "approx", "approximately", "around", "roughly", "up", "small",
               "medium", "large", "big", "mini", "regular", "individual", "generous", "hungry"}
_YIELD_STOP = {"as", "to", "for", "and", "or", "with", "the", "main", "mains", "side", "sides",
               "starter", "starters", "each", "per", "depending"}


def parse_servings(text):
    """'Serves 4-6' -> (4, 'serving'); 'Makes 12 cookies' -> (12, 'cookies'); '' -> (None, 'serving')."""
    s = _norm(text)
    if not s:
        return None, "serving"
    m = re.search(r"(\d+)(?:\s*(?:-|–|—|to|or)\s*\d+)?", s)
    n = None
    after = ""
    if m:
        n = int(m.group(1))
        after = s[m.end():]
    else:
        m = re.search(r"\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|dozen)\b", s)
        if m:
            n = int(_WORD_NUMBERS[m.group(1)])
            after = s[m.end():]
    if n is None or not 1 <= n <= 500:
        return None, "serving"
    unit = "serving"
    for word in re.findall(r"[a-z'-]+|[^\sa-z'-]", after):
        if word in _YIELD_SKIP:
            continue
        if not re.fullmatch(r"[a-z][a-z'-]+", word) or word in _YIELD_STOP or len(word) < 3:
            break
        if word not in _SERVING_WORDS:
            unit = word
        break
    return n, unit


_Y_PLURALS = {"patties", "pastries", "berries", "quantities", "parties", "jellies", "lollies"}


def yield_singular(word):
    """'cookies' -> 'cookie', 'loaves' -> 'loaf', for 'per cookie'."""
    w = (word or "serving").strip()
    if w in _Y_PLURALS:
        return w[:-3] + "y"
    if w.endswith("ves") and len(w) > 4:
        return w[:-3] + "f"
    if re.search(r"(?:ch|sh|ss|x)es$", w):
        return w[:-2]
    if w.endswith("s") and not w.endswith("ss") and len(w) > 3:
        return w[:-1]
    return w


# ---------------------------------------------------------------------------- source nutrition

_KCAL_RANGE = (0, 5000)
_MACRO_RANGE = (0, 1000)


def _first_number(s):
    m = re.search(r"\d+(?:\.\d+)?", s)
    return float(m.group(0)) if m else None


def _energy(value):
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        kcal = float(value)
    else:
        s = re.sub(r"(?<=\d),(?=\d{3}\b)", "", str(value).lower())
        s = re.sub(r"(?<=\d),(?=\d)", ".", s)
        m = re.search(r"(\d+(?:\.\d+)?)\s*(?:kcal|kilocalories?|cal\b|cals\b|calories?)", s)
        if m:
            kcal = float(m.group(1))
        else:
            m = re.search(r"(\d+(?:\.\d+)?)\s*(?:kj|kilojoules?)", s)
            kcal = float(m.group(1)) / 4.184 if m else _first_number(s)
    if kcal is None or not _KCAL_RANGE[0] <= kcal <= _KCAL_RANGE[1]:
        return None
    return int(round(kcal))


def _mass(value):
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        g = float(value)
    else:
        s = re.sub(r"(?<=\d),(?=\d)", ".", str(value).lower())
        m = re.search(r"(\d+(?:\.\d+)?)\s*(mg|milligrams?|g|grams?)?\b", s)
        if not m:
            return None
        g = float(m.group(1))
        if m.group(2) and m.group(2).startswith("m"):
            g /= 1000.0
    if not _MACRO_RANGE[0] <= g <= _MACRO_RANGE[1]:
        return None
    return round(g, 1)


def parse_source_nutrition(obj):
    """schema.org NutritionInformation (or our own stored shape) -> per-serving figures.

    Returns {kcal, protein, fat, carbs, serving_size} with None for what is missing, or None
    when nothing usable is there. Accepts a dict, a list holding one, or JSON text.
    """
    if isinstance(obj, str):
        try:
            obj = json.loads(obj)
        except ValueError:
            return None
    if isinstance(obj, list):
        obj = next((o for o in obj if isinstance(o, dict)), None)
    if not isinstance(obj, dict):
        return None

    def pick(*keys):
        for k in keys:
            if obj.get(k) not in (None, ""):
                return obj.get(k)
        return None

    size = pick("servingSize", "serving_size")
    if isinstance(size, list):
        size = size[0] if size else None
    size = str(size).strip()[:100] if size not in (None, "") else None
    out = {
        "kcal": _energy(pick("calories", "kcal", "energy")),
        "protein": _mass(pick("proteinContent", "protein")),
        "fat": _mass(pick("fatContent", "fat")),
        "carbs": _mass(pick("carbohydrateContent", "carbs", "carbohydrates")),
        "serving_size": size,
    }
    if all(out[k] is None for k in ("kcal", "protein", "fat", "carbs")):
        return None
    return out


# ---------------------------------------------------------------------------- public results

def _macros(d, scale=1.0):
    def r(v, nd):
        if v is None:
            return None
        v = v * scale
        return int(round(v)) if nd == 0 else round(v, nd)
    return {"kcal": r(d.get("kcal"), 0), "protein": r(d.get("protein"), 1),
            "fat": r(d.get("fat"), 1), "carbs": r(d.get("carbs"), 1)}


def estimate_recipe(ingredients_text, servings_text=""):
    """The legacy estimate shape (the `nutrition` key in the API and older clients).

    {kcal, protein, fat, carbs, matched, total_lines, servings, per_serving|None}; None when
    under half the countable lines are recognised. matched counts recognised lines including
    salt and spices; per_serving is there whenever servings is known (1 included).
    """
    a = analyse(ingredients_text)
    if not _usable(a):
        return None
    servings, _unit = parse_servings(servings_text)
    out = _macros(a)
    out.update(matched=a["matched"] + a["negligible"], total_lines=a["total_lines"],
               servings=servings, per_serving=_macros(a, 1.0 / servings) if servings else None)
    return out


def estimate_detail(ingredients_text, analysis=None):
    """The `estimate` block of nutrition_facts, or None."""
    a = analysis if analysis is not None else analyse(ingredients_text)
    if not _usable(a):
        return None
    out = _macros(a)
    out.update(
        confidence=_confidence(a), matched=a["matched"], counted_lines=a["counted"],
        total_lines=a["total_lines"],
        lines=[{"text": r["text"], "food": r["food"], "grams": _round_grams(r["grams"]),
                "kcal": None if r["kcal"] is None else int(round(r["kcal"])),
                "status": r["status"]} for r in a["rows"]],
    )
    return out


def nutrition_facts(ingredients_text, servings_text="", calories_per_serving=None, source_nutrition=None):
    """The figure to show, by precedence: what the cook entered, then the recipe source, then
    the estimate. Shape documented in API.md (`nutrition_facts`)."""
    servings, unit = parse_servings(servings_text)
    est = estimate_detail(ingredients_text)
    src = parse_source_nutrition(source_nutrition) if source_nutrition else None
    est_per = None
    if est and servings:
        est_per = _macros(est, 1.0 / servings)

    if calories_per_serving is not None:
        source = "manual"
        per = {"kcal": int(calories_per_serving), "protein": None, "fat": None, "carbs": None}
        # Only calories are typed in; macros come from the recipe source when it has them,
        # else from the estimate per serving, else stay null.
        macro_from = src or est_per
        if macro_from:
            per.update(protein=macro_from.get("protein"), fat=macro_from.get("fat"),
                       carbs=macro_from.get("carbs"))
    elif src and src.get("kcal") is not None:
        source = "recipe"
        per = {k: src.get(k) for k in ("kcal", "protein", "fat", "carbs")}
    elif est:
        source = "estimate"
        per = est_per
    else:
        return None

    if source == "estimate":
        total = {k: est[k] for k in ("kcal", "protein", "fat", "carbs")}
    elif servings:
        total = _macros(per, servings)
    else:
        total = None
    return {"source": source, "servings": servings, "yield_unit": unit, "per_serving": per,
            "total": total, "estimate": est}


# ---------------------------------------------------------------------------- helpers for routes

CALORIES_MAX = 20000


def facts_for(recipe):
    """nutrition_facts for a Recipe row."""
    return nutrition_facts(recipe.ingredients, recipe.servings,
                           getattr(recipe, "calories_per_serving", None),
                           getattr(recipe, "source_nutrition", None))


def source_nutrition_json(value):
    """Normalise source nutrition (dict, list or JSON text) for the source_nutrition column."""
    parsed = parse_source_nutrition(value) if value else None
    return json.dumps(parsed, separators=(",", ":")) if parsed else None


def parse_calories(value):
    """Form or JSON input for calories per serving -> (ok, int|None). Blank or null clears it."""
    if value is None or isinstance(value, bool) and not value:
        return True, None
    if isinstance(value, bool):
        return False, None
    if isinstance(value, (int, float)):
        number = float(value)
    else:
        text = str(value).strip().lower().replace(",", "")
        text = re.sub(r"\s*(?:kcal|cal|calories)$", "", text)
        if not text:
            return True, None
        try:
            number = float(text)
        except ValueError:
            return False, None
    if number != number or not 0 <= number <= CALORIES_MAX:
        return False, None
    return True, int(round(number))
