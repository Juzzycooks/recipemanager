"""Shopping list smarts: ingredient parsing, duplicate merging, aisle grouping."""
import re

from models import db, ShoppingListItem

_FRACTIONS = {"½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1 / 3, "⅔": 2 / 3, "⅛": 0.125}

_UNITS = {
    "g": "g", "gram": "g", "grams": "g", "kg": "kg", "kilogram": "kg", "kilograms": "kg",
    "ml": "ml", "millilitre": "ml", "milliliter": "ml", "l": "l", "litre": "l", "liter": "l",
    "cup": "cup", "cups": "cup", "tbsp": "tbsp", "tablespoon": "tbsp", "tablespoons": "tbsp",
    "tsp": "tsp", "teaspoon": "tsp", "teaspoons": "tsp",
    "oz": "oz", "ounce": "oz", "ounces": "oz", "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb",
    "can": "can", "cans": "can", "tin": "can", "tins": "can",
    "clove": "clove", "cloves": "clove", "bunch": "bunch", "bunches": "bunch",
    "slice": "slice", "slices": "slice",
}

# Descriptors stripped when normalising names for matching
_DESCRIPTORS = re.compile(
    r"\b(fresh|dried|chopped|minced|diced|sliced|grated|finely|roughly|thinly|"
    r"large|medium|small|whole|ripe|raw|cooked|frozen|ground|crushed|peeled|"
    r"boneless|skinless|lean|extra|virgin|free.range|organic)\b", re.I)

_QTY_RE = re.compile(
    r"^\s*(?P<qty>\d+\s+\d/\d|\d+/\d|\d*[.,]?\d+|[½¼¾⅓⅔⅛])\s*"
    r"(?P<unit>[a-zA-Z]+)?\.?\s+(?P<rest>.+)$"
)

_AISLES = [
    ("Produce", ["onion", "garlic", "tomato", "carrot", "celery", "capsicum", "pepper",
                 "broccoli", "spinach", "mushroom", "zucchini", "cucumber", "lettuce",
                 "cabbage", "cauliflower", "bean", "avocado", "pumpkin", "eggplant",
                 "potato", "lemon", "lime", "apple", "banana", "berr", "herb", "basil",
                 "parsley", "coriander", "cilantro", "mint", "thyme", "rosemary",
                 "ginger", "chilli", "chili", "spring onion", "shallot", "leek", "corn",
                 "salad", "fruit", "veg"]),
    ("Meat & Seafood", ["chicken", "beef", "pork", "lamb", "mince", "steak", "bacon",
                        "sausage", "ham", "turkey", "salmon", "tuna", "fish", "prawn",
                        "shrimp", "seafood", "chorizo"]),
    ("Dairy & Eggs", ["milk", "cheese", "cheddar", "mozzarella", "parmesan", "feta",
                      "butter", "cream", "yoghurt", "yogurt", "egg", "custard"]),
    ("Bakery", ["bread", "roll", "bun", "wrap", "tortilla", "pita", "bagel", "croissant"]),
    ("Frozen", ["frozen", "ice cream", "pastry sheet", "puff pastry"]),
    ("Pantry", ["flour", "sugar", "rice", "pasta", "spaghetti", "noodle", "oil",
                "vinegar", "sauce", "stock", "broth", "can", "tin", "spice", "salt",
                "pepper", "paprika", "cumin", "oregano", "cinnamon", "vanilla",
                "honey", "syrup", "oat", "cereal", "lentil", "chickpea", "coconut milk",
                "tomato paste", "mustard", "mayonnaise", "ketchup", "soy", "curry",
                "chocolate", "cocoa", "nut", "almond", "peanut", "seed", "quinoa",
                "couscous", "breadcrumb", "baking"]),
    ("Beverages", ["juice", "water", "soda", "wine", "beer", "coffee", "tea"]),
]


def parse_line(line):
    """Parse an ingredient line -> (qty: float|None, unit: str|None, name: str)."""
    text = line.strip().lstrip("-•● ").strip()
    if not text:
        return None, None, ""
    if text[0] in _FRACTIONS:
        rest = text[1:].strip()
        m = re.match(r"^(?P<unit>[a-zA-Z]+)\.?\s+(?P<rest>.+)$", rest)
        if m and m.group("unit").lower() in _UNITS:
            return _FRACTIONS[text[0]], _UNITS[m.group("unit").lower()], m.group("rest").strip()
        return _FRACTIONS[text[0]], None, rest
    m = _QTY_RE.match(text)
    if not m:
        return None, None, text
    raw = m.group("qty")
    try:
        if raw in _FRACTIONS:
            qty = _FRACTIONS[raw]
        elif "/" in raw:
            if " " in raw:
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
    unit_raw = (m.group("unit") or "").lower()
    rest = m.group("rest").strip()
    if unit_raw and unit_raw in _UNITS:
        return qty, _UNITS[unit_raw], rest
    if unit_raw:
        rest = f"{unit_raw} {rest}"  # "2 large onions" — unit is a descriptor
    return qty, None, rest


def normalise_name(name):
    """Lowercase, strip descriptors/punctuation/plural 's' for matching."""
    n = name.lower()
    n = n.split(",")[0]  # drop trailing prep notes: "onion, finely diced"
    n = _DESCRIPTORS.sub("", n)
    n = re.sub(r"[^\w\s]", "", n)
    n = re.sub(r"\s+", " ", n).strip()
    if n.endswith("es") and len(n) > 4:
        n = n[:-2] if n.endswith(("oes", "ches", "shes")) else n[:-1]
    elif n.endswith("s") and len(n) > 3:
        n = n[:-1]
    return n


def _fmt_qty(qty):
    if qty == int(qty):
        return str(int(qty))
    return f"{qty:g}"


def display_name(qty, unit, name):
    if qty is None:
        return name
    if unit:
        return f"{_fmt_qty(qty)} {unit} {name}"
    return f"{_fmt_qty(qty)} {name}"


# Words that say "this is the packaged/pantry version", checked before the ingredient keywords
# (so "tinned tomatoes", "chicken stock" and "coconut milk" don't land in Produce, Meat or Dairy).
_PANTRY_PHRASES = ("tinned", "canned", "tin of", "can of", "dried", "stock", "broth", "paste", "puree",
                   "coconut milk", "coconut cream", "black pepper", "peppercorn", "sauce", "jar of",
                   "packet", "powder", "essence", "extract", "passata")


def aisle_for(name):
    """Classify an item name into an aisle/section."""
    lowered = name.lower()
    if "frozen" in lowered:
        return "Frozen"
    if any(p in lowered for p in _PANTRY_PHRASES) or re.search(r"\b(?:cans?|tins?)\b", lowered):
        return "Pantry"
    for aisle, keywords in _AISLES:
        for kw in keywords:
            if kw in lowered:
                return aisle
    return "Other"


def add_lines_merged(user_id, lines, recipe_id=None):
    """Add ingredient lines to a user's list, merging with existing unchecked
    items when the normalised name matches and units are compatible.

    Returns (added, merged) counts.
    """
    existing = ShoppingListItem.query.filter_by(user_id=user_id, checked=False).all()
    # normalised name -> item
    index = {}
    for item in existing:
        _, _, item_name = parse_line(item.name)
        index.setdefault(normalise_name(item_name), item)

    added = merged = 0
    for line in lines:
        line = line.strip()
        if not line or line.startswith("# "):
            continue  # skip blank lines and section headings
        qty, unit, name = parse_line(line)
        key = normalise_name(name)
        match = index.get(key) if key else None
        if match is not None:
            m_qty, m_unit, m_name = parse_line(match.name)
            if qty is not None and m_qty is not None and unit == m_unit:
                # Compatible units -> combine quantities
                match.name = display_name(m_qty + qty, unit, m_name)
            else:
                # Same item, incompatible quantities -> note the extra
                match.name = f"{match.name} + {line}"
            merged += 1
        else:
            item = ShoppingListItem(name=line, user_id=user_id, recipe_id=recipe_id)
            db.session.add(item)
            if key:
                index[key] = item
            added += 1
    return added, merged


def group_by_aisle(items):
    """Group items into ordered (aisle, items) pairs for display."""
    order = [a for a, _ in _AISLES] + ["Other"]
    groups = {}
    for item in items:
        _, _, name = parse_line(item.name)
        groups.setdefault(aisle_for(name or item.name), []).append(item)
    return [(a, groups[a]) for a in order if a in groups]
