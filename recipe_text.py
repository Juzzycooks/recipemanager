"""Turn loose recipe text (Instagram captions, PDF text, OCR of photos/screenshots)
into structured fields.

Output conventions match the rest of the app: ingredients and instructions are
newline-separated, and section headings inside them are lines starting with
"# " (rendered as sub-headings on the recipe page).
"""
import html as html_mod
import re

# Section markers, compared after stripping emoji/punctuation and lower-casing.
_ING = {
    "ingredients", "ingredient", "you will need", "youll need", "what you need",
    "whatyoull need", "what youll need", "shopping list", "you need", "for the recipe",
}
_INS = {
    "instructions", "instruction", "directions", "direction", "method", "methods",
    "steps", "how to make", "how to make it", "preparation", "preparation method",
    "to make", "procedure", "recipe",
}
_NOTES = {
    "notes", "note", "tips", "tip", "chefs notes", "chefs tip", "chefs tips",
    "recipe notes", "cooks notes", "storage", "variations", "substitutions",
    "serving suggestions", "make ahead",
}

_HASHTAG_ONLY = re.compile(r"^(?:[#@][\w.]+\s*)+$")
_FLUFF = re.compile(
    r"^(?:save (?:this|for later)|follow (?:me|@)|link in bio|comment|share this|"
    r"tag (?:a|me|someone)|dm me|turn on post notifications)",
    re.I,
)
_BULLET = re.compile(r"^\s*(?:[-–—•●▪◦*·»›]+|[✓✔☐□▢])\s*")
_STEP_NUM = re.compile(r"^\s*(?:step\s*)?\d{1,2}\s*[.):\-]\s+(?=\S)", re.I)
_OCR_BULLET = re.compile(r"^[eo©®«»|*]\s+(?=\d)")
_UNIT = (
    r"(?:g|kg|mg|ml|l|oz|lb|lbs|cup|cups|tbsp|tsp|tablespoons?|teaspoons?|"
    r"bunch|cloves?|pinch|handful|can|cans|tin|tins|slices?|sticks?|sprigs?|dash)"
)
_QUANTITY = re.compile(rf"^\s*(?:\d+(?:[./]\d+)?|[¼½¾⅓⅔⅛])\s*(?:{_UNIT}\b|\w)", re.I)
_HAS_MEASURE = re.compile(rf"\b\d+(?:[./]\d+)?\s*{_UNIT}\b|[¼½¾⅓⅔⅛]", re.I)

# Meta lines must carry a number so "Cook on a hot pan" or "Makes a great dinner" stay steps/prose.
_META = [
    ("servings", re.compile(r"^(?:serves|servings?|makes|yields?|portions?)\s*:?\s*(\d.{0,29})$", re.I)),
    ("prep_time", re.compile(r"^prep(?:aration)?\s*(?:time\s*)?:?\s*(\d.{0,24})$", re.I)),
    ("cook_time", re.compile(r"^(?:cook(?:ing)?|bake)\s*(?:time\s*)?:?\s*(\d.{0,24})$", re.I)),
]


def _words(line):
    """Lower-case letters and spaces only, for marker comparison."""
    return re.sub(r"\s+", " ", re.sub(r"[^a-z\s]", "", line.lower().replace("'", "").replace("’", ""))).strip()


def _section_of(line):
    """Return ('ing'|'ins'|'notes', remainder) if the line is a section header."""
    raw = re.sub(r"^[^\w]+", "", line).strip()  # leading emoji / bullets
    head, colon, rest = raw.partition(":")
    words = _words(head if colon else raw)
    if not words or len(words.split()) > 5 or len(raw) > 60 and not colon:
        return None, ""
    for name, markers in (("ing", _ING), ("ins", _INS), ("notes", _NOTES)):
        if words in markers or any(words.startswith(m + " ") and len(words.split()) <= 4 for m in markers if len(m) > 4):
            remainder = rest.strip() if colon else ""
            return name, remainder
    return None, ""


def _is_subheading(line):
    """A short line that names a group of ingredients/steps ("For the sauce:")."""
    s = re.sub(r"[^\w:)]+$", "", line.strip())  # trailing emoji / punctuation
    if not s or len(s) > 48 or _QUANTITY.match(s) or s.endswith((".", "!", "?")):
        return None
    core = s.rstrip(":").strip()
    if not core or not re.search(r"[A-Za-z]", core):
        return None
    if s.endswith(":"):
        return core
    if re.match(r"^for the\s+\S", core, re.I) or re.match(r"^to (?:serve|assemble|finish|garnish)\b", core, re.I):
        return core
    letters = re.sub(r"[^A-Za-z]", "", core)
    if len(letters) >= 3 and letters.isupper() and len(core.split()) <= 5:
        return core.capitalize()
    return None


def _clean_line(line):
    line = html_mod.unescape(line).replace(" ", " ").replace("​", "")
    line = _OCR_BULLET.sub("", line.strip())
    return re.sub(r"[ \t]+", " ", line).strip()


def _split_glued_ingredients(item):
    """Instagram sometimes glues several ingredients onto one line."""
    if len(_HAS_MEASURE.findall(item)) < 2:
        return [item]
    parts = re.split(
        rf"(?<=[A-Za-z])\s+(?=(?:\d+(?:[./]\d+)?|[¼½¾⅓⅔⅛])\s*(?:{_UNIT}\b|[A-Za-z]))", item, flags=re.I
    )
    parts = [p.strip() for p in parts if p.strip()]
    # Two quantities in one normal ingredient ("1 cup flour (120 g)") must stay together
    if len(parts) >= 3 or (len(item) > 60 and len(parts) >= 2):
        return parts
    return [item]


def _split_long_step(item):
    if len(item) <= 160:
        return [item]
    sentences = re.split(r"(?<=[.!?])\s+(?=[A-Z])", item)
    return [s.strip() for s in sentences if s.strip()]


def _join_wrapped(lines):
    """Merge lines that are a single sentence wrapped by a PDF / OCR column."""
    out = []
    for line in lines:
        if line.startswith("# "):
            out.append(line)
        elif out and not out[-1].startswith("# ") and not re.search(r"[.!?:;)]$", out[-1]) and line[:1].islower():
            out[-1] = out[-1] + " " + line
        else:
            out.append(line)
    return out


_NOTE_START = re.compile(r"^(?:p\.?s\.?|note|nb|tip|pro tip|chef'?s tip)\b[\s:.\-]*", re.I)


def _kind(line):
    """'ing' | 'ins' | None for a line of an unlabelled recipe."""
    if _STEP_NUM.match(line):
        return "ins"
    if _BULLET.match(line):
        return "ing"
    if _HAS_MEASURE.search(line) and len(line) < 90 and not line.endswith((".", "!")):
        return "ing"
    return None


def _parse_unlabelled(lines):
    """Posts with no "Ingredients"/"Method" headings: bullets are ingredients, numbered
    lines are steps, and a short line announcing a new part ("For the sauce 🍅") starts a group
    whose heading is repeated in both lists."""
    ing, ins, notes, desc = [], [], [], []
    group, ing_done, ins_done = None, True, True  # first group is implicit (no heading)
    started = False
    for i, line in enumerate(lines):
        kind = _kind(line)
        if kind is None and started and _NOTE_START.match(line):
            notes.append(_NOTE_START.sub("", line).strip() or line)
            notes.extend(l for l in lines[i + 1:])
            break
        if kind is None:
            nxt = next((_kind(l) for l in lines[i + 1:i + 3] if _kind(l)), None)
            sub = _is_subheading(line)
            short = len(line.split()) <= 6 and not re.search(r"[.!?]$", line)
            if nxt and (sub or (started and short)):
                group, ing_done, ins_done = sub or re.sub(r"[^\w\s')&/-]+$", "", line).strip(), False, False
                continue
            if not started:
                desc.append(line)
            elif not ins and len(line) > 50:
                ins.append(line)  # prose method after a plain ingredient list
            else:
                notes.append(line)
            continue
        started = True
        if kind == "ing":
            if group and not ing_done:
                ing.append("# " + group); ing_done = True
            ing.append(line)
        else:
            if group and not ins_done:
                ins.append("# " + group); ins_done = True
            ins.append(line)
    return ing, ins, notes, desc


def parse_recipe_text(text, title=None):
    """Parse free text into a dict of recipe fields.

    Returns keys: title, description, ingredients, instructions, notes,
    servings, prep_time, cook_time. Never raises on odd input.
    """
    result = {
        "title": "", "description": "", "ingredients": "", "instructions": "",
        "notes": "", "servings": "", "prep_time": "", "cook_time": "",
    }
    if not text or not text.strip():
        return result

    # Instagram paragraph breaks arrive as " . " or a lone dot line
    normalised = text.replace("\r", "").replace(" . ", "\n")
    normalised = re.sub(r"\n\s*[.·•]\s*\n", "\n", normalised)
    raw_lines = [_clean_line(l) for l in normalised.split("\n")]
    lines = [l for l in raw_lines if l and l != "." and not _HASHTAG_ONLY.match(l) and not _FLUFF.match(l)]
    if not lines:
        return result

    first = lines[0]
    if title:
        result["title"] = title
    elif 3 < len(first) < 120 and not first.startswith("#") and _section_of(first)[0] is None:
        result["title"] = re.sub(r"\s*#\w+", "", first).strip()
        lines = lines[1:]

    buckets = {"pre": [], "ing": [], "ins": [], "notes": []}
    section = "pre"
    seen_marker = False
    for line in lines:
        # Meta lines (Serves 4, Prep 10 mins) can appear anywhere before the notes.
        # Several often share one line: "Serves 2   Prep time: 10 mins".
        if section != "notes" and len(line) < 80:
            fragments = [f for f in re.split(r"\s{2,}|\s*[|•·]\s*|\s+(?=(?:prep|cook|bake|serves|makes|yields?)\b)", line, flags=re.I) if f.strip()]
            found = {}
            for frag in fragments:
                for key, pat in _META:
                    m = pat.match(frag.strip().rstrip("."))
                    if m and not result[key] and key not in found:
                        found[key] = m.group(1).strip(" .:")
                        break
            if found and len(found) == len(fragments):
                result.update(found)
                continue
        kind, remainder = _section_of(line)
        if kind:
            section, seen_marker = kind, True
            if remainder:
                buckets[section].append(remainder)
            continue
        buckets[section].append(line)

    ingredients, instructions, notes = buckets["ing"], buckets["ins"], buckets["notes"]

    if not seen_marker:
        ingredients, instructions, notes_extra, desc_lines = _parse_unlabelled(buckets["pre"])
        notes = notes + notes_extra
        buckets["pre"] = desc_lines

    def build(items, kind):
        out = []
        for raw in items:
            line = _BULLET.sub("", raw) if kind != "notes" else _BULLET.sub("", raw)
            if kind == "ins":
                line = _STEP_NUM.sub("", line)
            line = line.strip()
            if not line:
                continue
            if kind in ("ing", "ins"):
                sub = _is_subheading(line)
                if sub:
                    out.append("# " + sub)
                    continue
            if kind == "ing":
                out.extend(_split_glued_ingredients(line))
            elif kind == "ins":
                out.extend(_split_long_step(line))
            else:
                out.append(line)
        return _join_wrapped(out) if kind in ("ins", "notes") else out

    ing_lines = build(ingredients, "ing")
    ins_lines = build(instructions, "ins")
    note_lines = build(notes, "notes")

    # A trailing heading with nothing under it is noise
    for lst in (ing_lines, ins_lines):
        while lst and lst[-1].startswith("# "):
            lst.pop()

    desc = " ".join(buckets["pre"]).strip()
    result["description"] = re.sub(r"\s*#\w+", "", desc).strip()[:600]
    result["ingredients"] = "\n".join(ing_lines)
    result["instructions"] = "\n".join(ins_lines)
    result["notes"] = "\n".join(note_lines)
    return result
