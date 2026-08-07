import re
import json
from bs4 import BeautifulSoup

from security import safe_get


def _is_social_media_url(url):
    """Check if URL is from TikTok, Instagram, or similar."""
    patterns = ['tiktok.com', 'instagram.com', 'facebook.com', 'threads.net']
    return any(p in url.lower() for p in patterns)


def _extract_meta(html, prop):
    """Extract a meta tag content by property name (handles both attribute orders)."""
    m = re.search(
        rf'<meta[^>]*property=["\']og:{prop}["\'][^>]*content=["\']([^"\']*)["\']', html, re.I
    ) or re.search(
        rf'<meta[^>]*content=["\']([^"\']*)["\'][^>]*property=["\']og:{prop}["\']', html, re.I
    )
    return m.group(1) if m else ""


def _html_unescape(text):
    """Decode common HTML entities and unicode escapes."""
    import html as html_mod
    text = html_mod.unescape(text)
    # Handle \\u00xx style unicode escapes from JSON
    text = re.sub(r'\\u([0-9a-fA-F]{4})', lambda m: chr(int(m.group(1), 16)), text)
    text = text.replace('\\n', '\n').replace('\\r', '')
    return text


def _extract_caption_from_html(html):
    """Try to pull the full post caption from embedded JSON or meta tags."""
    import json

    caption = ""

    # Instagram: look for caption in embedded JSON (shared_data or additional_data scripts)
    # Pattern 1: JSON-LD or script blocks with "caption" key
    for pattern in [
        r'"caption"\s*:\s*\{[^}]*"text"\s*:\s*"((?:[^"\\]|\\.)*)"',  # {"caption":{"text":"..."}}
        r'"edge_media_to_caption".*?"text"\s*:\s*"((?:[^"\\]|\\.)*)"',  # older IG format
        r'"description"\s*:\s*\{[^}]*"string"\s*:\s*"((?:[^"\\]|\\.)*)"',  # TikTok
    ]:
        m = re.search(pattern, html, re.S)
        if m:
            candidate = _html_unescape(m.group(1))
            if len(candidate) > len(caption):
                caption = candidate

    # TikTok: look for desc in their JSON data
    m = re.search(r'"desc"\s*:\s*"((?:[^"\\]|\\.)*)"', html)
    if m:
        candidate = _html_unescape(m.group(1))
        if len(candidate) > len(caption):
            caption = candidate

    # Fallback: meta description (often truncated but better than nothing)
    if not caption:
        caption = _html_unescape(_extract_meta(html, "description"))

    return caption.strip()


def _parse_caption_into_recipe(caption):
    """Parse a social media caption into structured recipe fields."""
    if not caption:
        return "", "", ""

    # Normalise: Instagram captions often use " . " as line breaks
    # Split on " . " (space-dot-space) which is the Instagram paragraph separator
    normalised = caption.replace(' . ', '\n')
    # Also handle lone dots on their own line
    normalised = re.sub(r'\n\s*\.\s*\n', '\n', normalised)

    lines = [l.strip() for l in normalised.split('\n') if l.strip() and l.strip() != '.']
    if not lines:
        return "", "", ""

    ingredients = []
    instructions = []
    section = None

    ingredient_markers = [
        'ingredient', 'you will need', "you'll need", 'what you need',
        "what you'll need", 'shopping list', 'you need',
    ]
    instruction_markers = [
        'instruction', 'direction', 'method', 'steps', 'how to make',
        'preparation',
    ]

    for line in lines:
        lower = line.lower().rstrip(':').rstrip('.')
        # Detect section headers — must be short and look like a heading
        if any(lower == m or lower == m + 's' for m in ingredient_markers) and len(line) < 40:
            section = 'ingredients'
            continue
        if any(lower == m or lower == m + 's' for m in instruction_markers) and len(line) < 40:
            section = 'instructions'
            continue
        # Also match "Method" specifically (common in UK/AU recipes)
        if lower in ('method', 'methods'):
            section = 'instructions'
            continue

        if section == 'ingredients':
            ingredients.append(line)
        elif section == 'instructions':
            instructions.append(line)

    # Post-process: split long ingredient lines that are actually multiple items
    # (common when Instagram captions lose their line breaks)
    split_ingredients = []
    for item in ingredients:
        if len(item) > 50:
            # Split before quantity patterns: "500g", "2 tsp", "1 onion"
            # Also before common non-quantity starters
            parts = re.split(
                r'(?<=\S)\s+(?='
                r'\d+\s*(?:g|kg|ml|l|oz|lb|cup|cups|tbsp|tsp|tablespoon|teaspoon)\b'
                r'|'
                r'\d+\s+[a-zA-Z]'  # "1 onion", "2 cloves"
                r'|'
                r'(?:Spray oil|Salt and|Juice of|Zest of)\b'
                r')',
                item, flags=re.I
            )
            if len(parts) > 1:
                split_ingredients.extend(p.strip() for p in parts if p.strip())
            else:
                split_ingredients.append(item)
        else:
            split_ingredients.append(item)
    ingredients = split_ingredients

    # Post-process: split long instruction blocks into individual steps
    split_instructions = []
    for item in instructions:
        if len(item) > 120:
            # Split on sentence boundaries ". " followed by a capital letter
            sentences = re.split(r'\.\s+(?=[A-Z])', item)
            for s in sentences:
                s = s.strip()
                if s and not s.endswith('.'):
                    s += '.'
                if s:
                    split_instructions.append(s)
        else:
            split_instructions.append(item)
    instructions = split_instructions

    # If no clear sections, try heuristic: lines with measurements/quantities = ingredients
    if not ingredients and not instructions:
        measure_pattern = re.compile(
            r'(\d+\s*(g|kg|ml|l|oz|lb|cup|cups|tbsp|tsp|tablespoon|teaspoon|bunch|clove|pinch|handful)s?\b)|'
            r'(^\s*[-•●]\s)',
            re.I
        )
        numbered_step = re.compile(r'^\d+[\.\)]\s')
        for line in lines:
            if measure_pattern.search(line):
                ingredients.append(line.lstrip('-•● '))
            elif numbered_step.match(line):
                instructions.append(line)

    return (
        caption,
        '\n'.join(ingredients),
        '\n'.join(instructions),
    )


def _scrape_social_media(url, html):
    """Extract recipe info from social media pages (Instagram, TikTok, etc.)."""
    title = _html_unescape(_extract_meta(html, "title")) or "Imported Recipe"
    image = _extract_meta(html, "image")

    # Try extracting caption from the page HTML
    caption = _extract_caption_from_html(html)
    description, ingredients, instructions = _parse_caption_into_recipe(caption)

    # If we got a long caption, use the first line as a better title
    if caption and '\n' in caption:
        first_line = caption.split('\n')[0].strip()
        # Only use it if it looks like a title (not too long, not a hashtag dump)
        if 5 < len(first_line) < 120 and not first_line.startswith('#'):
            title = first_line

    # Strip hashtags from description for cleanliness
    clean_desc = re.sub(r'#\w+', '', description).strip()
    clean_desc = re.sub(r'\n{3,}', '\n\n', clean_desc)

    return {
        "title": title,
        "description": clean_desc,
        "ingredients": ingredients,
        "instructions": instructions or clean_desc,
        "prep_time": "",
        "cook_time": "",
        "servings": "",
        "image_url": image,
        "source_type": "social",
    }


def _parse_iso_duration(val):
    """Convert ISO 8601 duration (PT30M, PT1H15M) to a readable string."""
    if not val or not isinstance(val, str):
        return ""
    m = re.match(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?', val, re.I)
    if not m:
        return str(val)
    parts = []
    if m.group(1):
        parts.append(f"{m.group(1)}h")
    if m.group(2):
        parts.append(f"{m.group(2)}m")
    if m.group(3) and not parts:
        parts.append(f"{m.group(3)}s")
    return " ".join(parts) if parts else str(val)


def _parse_instructions(raw):
    """Flatten schema.org recipeInstructions into newline-separated steps.

    Section headings (from HowToSection) are emitted as lines prefixed with
    "# " so they survive as plain text and can be rendered as sub-headings.

    Handles every common shape:
      - a plain string (possibly with embedded newlines)
      - a list of strings
      - a list of HowToStep dicts (text in "text" or "name")
      - HowToSection dicts whose steps live in "itemListElement" (recursed,
        with the section name kept as a "# Heading" line)
      - a single dict wrapping "itemListElement"
    """
    out = []

    def _walk(node):
        if node is None:
            return
        if isinstance(node, str):
            text = node.strip()
            if text:
                out.append(text)
        elif isinstance(node, list):
            for child in node:
                _walk(child)
        elif isinstance(node, dict):
            node_type = node.get("@type", "")
            if isinstance(node_type, list):
                node_type = " ".join(node_type)
            sub = node.get("itemListElement") or node.get("steps")
            if "HowToSection" in str(node_type) or sub is not None:
                # A section: keep its name as a heading, then recurse into steps
                name = (node.get("name") or "").strip()
                if name and sub:
                    out.append("# " + name)
                _walk(sub)
            else:
                # A single step: prefer "text", fall back to "name"
                text = (node.get("text") or node.get("name") or "").strip()
                if text:
                    out.append(text)

    _walk(raw)
    return "\n".join(s for s in out if s)


def _has_class(tag, cls):
    """True if a BeautifulSoup tag carries an exact class token."""
    return tag.has_attr("class") and cls in tag["class"]


def _extract_wprm_groups(soup, kind):
    """Extract grouped ingredients/instructions from WordPress Recipe Maker markup.

    `kind` is "ingredient" or "instruction". Returns newline-separated text with
    section names as "# Heading" lines, or None if no WPRM groups are present.
    Many popular recipe sites (RecipeTinEats, etc.) use WPRM and only expose
    ingredient/instruction *grouping* in the HTML, not in JSON-LD.
    """
    group_cls = f"wprm-recipe-{kind}-group"
    item_cls = f"wprm-recipe-{kind}"
    groups = soup.find_all(lambda t: _has_class(t, group_cls))
    if not groups:
        return None

    out = []
    multiple = len(groups) > 1
    for g in groups:
        name_el = g.find(lambda t: _has_class(t, "wprm-recipe-group-name"))
        name = name_el.get_text(" ", strip=True) if name_el else ""

        texts = []
        for it in g.find_all(lambda t: _has_class(t, item_cls)):
            txt = re.sub(r"\s+", " ", it.get_text(" ", strip=True)).strip()
            if txt:
                texts.append(txt)
        if not texts:
            continue

        # Only emit a heading when it's meaningful (named, and either there are
        # several groups or the name isn't just the generic section label).
        if name and (multiple or name.lower() not in ("ingredients", "instructions")):
            out.append("# " + name)
        out.extend(texts)

    return "\n".join(out) if out else None


def _extract_json_ld_recipe(html):
    """Extract Recipe schema.org data from JSON-LD script tags."""
    soup = BeautifulSoup(html, "html.parser")
    for script in soup.find_all("script", type="application/ld+json"):
        try:
            data = json.loads(script.string or "")
        except (json.JSONDecodeError, TypeError):
            continue

        # Handle both single objects and arrays
        items = data if isinstance(data, list) else [data]

        # Also check @graph arrays
        for item in items:
            if isinstance(item, dict) and "@graph" in item:
                items.extend(item["@graph"])

        for item in items:
            if not isinstance(item, dict):
                continue
            item_type = item.get("@type", "")
            if isinstance(item_type, list):
                item_type = " ".join(item_type)
            if "Recipe" in item_type:
                return item
    return None


def _extract_microdata_recipe(soup):
    """Fallback: extract recipe from microdata (itemtype=schema.org/Recipe)."""
    node = soup.find(attrs={"itemtype": re.compile(r"schema\.org/Recipe", re.I)})
    if not node:
        return None

    def _prop(name):
        el = node.find(attrs={"itemprop": name})
        if not el:
            return ""
        return el.get("content", "") or el.get_text(strip=True)

    ingredients = []
    for el in node.find_all(attrs={"itemprop": "recipeIngredient"}):
        ingredients.append(el.get("content", "") or el.get_text(strip=True))
    if not ingredients:
        for el in node.find_all(attrs={"itemprop": "ingredients"}):
            ingredients.append(el.get("content", "") or el.get_text(strip=True))

    instructions = []
    for el in node.find_all(attrs={"itemprop": "recipeInstructions"}):
        text = el.get("content", "") or el.get_text(strip=True)
        if text:
            instructions.append(text)

    return {
        "title": _prop("name") or "Imported Recipe",
        "description": _prop("description"),
        "ingredients": "\n".join(ingredients),
        "instructions": "\n".join(instructions),
        "prep_time": _parse_iso_duration(_prop("prepTime")),
        "cook_time": _parse_iso_duration(_prop("cookTime")),
        "servings": _prop("recipeYield"),
        "image_url": _prop("image"),
    }


def _extract_wprm_notes(soup):
    """Extract the recipe notes block from WordPress Recipe Maker markup.

    Returns newline-separated note text (one line per list item / paragraph),
    or "" if there is no notes block.
    """
    notes_el = soup.find(lambda t: _has_class(t, "wprm-recipe-notes"))
    if not notes_el:
        return ""
    blocks = notes_el.find_all(["li", "p"])
    if blocks:
        lines = [re.sub(r"\s+", " ", b.get_text(" ", strip=True)).strip() for b in blocks]
        return "\n".join(l for l in lines if l)
    return re.sub(r"\n{3,}", "\n\n", notes_el.get_text("\n", strip=True)).strip()


def scrape_recipe(url: str) -> dict:
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }
    # SSRF-guarded fetch: http(s) only, public IPs only, 5 MB cap
    resp = safe_get(url, headers=headers, timeout=15)
    html_text = resp.text

    # Try social media extraction first for known platforms
    if _is_social_media_url(url):
        result = _scrape_social_media(url, html_text)
        result["source_url"] = url
        return result

    # Parse once for WPRM group/notes extraction and the microdata fallback
    soup = BeautifulSoup(html_text, "html.parser")
    notes = _extract_wprm_notes(soup)

    # Try JSON-LD structured data (most recipe sites use this)
    ld = _extract_json_ld_recipe(html_text)
    if ld:
        # Parse ingredients
        raw_ing = ld.get("recipeIngredient", [])
        if isinstance(raw_ing, list):
            ingredients = "\n".join(str(i) for i in raw_ing)
        else:
            ingredients = str(raw_ing)

        # Parse instructions (handles HowToStep, nested HowToSection, strings)
        instructions = _parse_instructions(ld.get("recipeInstructions", ""))

        # Parse image — can be a string URL, dict (ImageObject), or list of either
        raw_img = ld.get("image", "")
        if isinstance(raw_img, list):
            raw_img = raw_img[0] if raw_img else ""
        if isinstance(raw_img, dict):
            image = raw_img.get("url", "")
        elif isinstance(raw_img, str):
            image = raw_img
        else:
            image = str(raw_img)

        # Parse servings — can be string, int, or list
        raw_yield = ld.get("recipeYield", "")
        if isinstance(raw_yield, list):
            servings = str(raw_yield[0]) if raw_yield else ""
        else:
            servings = str(raw_yield) if raw_yield else ""

        # Parse description
        raw_desc = ld.get("description", "")
        if isinstance(raw_desc, dict):
            description = raw_desc.get("text", "") or raw_desc.get("@value", "")
        else:
            description = str(raw_desc) if raw_desc else ""

        # Prefer grouped sections from WPRM markup when they add structure.
        # JSON-LD ingredients are always flat, so any WPRM grouping wins.
        wprm_ing = _extract_wprm_groups(soup, "ingredient")
        if wprm_ing and "# " in wprm_ing:
            ingredients = wprm_ing
        # For instructions, JSON-LD HowToSection may already give headings;
        # only fall back to WPRM if JSON-LD didn't provide any.
        if "# " not in instructions:
            wprm_inst = _extract_wprm_groups(soup, "instruction")
            if wprm_inst and "# " in wprm_inst:
                instructions = wprm_inst

        return {
            "title": ld.get("name", "Imported Recipe"),
            "description": description,
            "ingredients": ingredients,
            "instructions": instructions,
            "prep_time": _parse_iso_duration(ld.get("prepTime", "")),
            "cook_time": _parse_iso_duration(ld.get("cookTime", "")),
            "servings": servings,
            "image_url": image,
            "notes": notes,
        }

    # Fallback: try microdata
    micro = _extract_microdata_recipe(soup)
    if micro:
        micro["notes"] = notes
        return micro

    # Last resort: grab what we can from meta tags and page content
    title = _extract_meta(html_text, "title") or "Imported Recipe"
    image = _extract_meta(html_text, "image")
    description = _extract_meta(html_text, "description")

    return {
        "title": _html_unescape(title),
        "description": _html_unescape(description),
        "ingredients": "",
        "instructions": "",
        "prep_time": "",
        "cook_time": "",
        "servings": "",
        "image_url": image,
        "notes": notes,
    }


def parse_pdf_recipe(file_storage):
    """Extract recipe text from a PDF file and return structured data."""
    from pypdf import PdfReader
    import io

    reader = PdfReader(io.BytesIO(file_storage.read()))
    text = ""
    for page in reader.pages:
        page_text = page.extract_text()
        if page_text:
            text += page_text + "\n"

    if not text.strip():
        return None

    lines = [l.strip() for l in text.split("\n") if l.strip()]
    if not lines:
        return None

    # Heuristic parsing: first line is title, look for ingredient/instruction sections
    title = lines[0]
    ingredients = []
    instructions = []
    current_section = None

    ingredient_markers = ['ingredient', 'you will need', 'you\'ll need', 'what you need']
    instruction_markers = ['instruction', 'direction', 'method', 'steps', 'preparation', 'how to']

    for line in lines[1:]:
        lower = line.lower()
        if any(m in lower for m in ingredient_markers):
            current_section = 'ingredients'
            continue
        elif any(m in lower for m in instruction_markers):
            current_section = 'instructions'
            continue

        if current_section == 'ingredients':
            ingredients.append(line)
        elif current_section == 'instructions':
            instructions.append(line)

    # If no sections detected, try splitting: short lines = ingredients, long = instructions
    if not ingredients and not instructions and len(lines) > 2:
        for line in lines[1:]:
            if len(line) < 60 and not line.endswith('.'):
                ingredients.append(line)
            else:
                instructions.append(line)

    return {
        "title": title,
        "description": "",
        "ingredients": "\n".join(ingredients),
        "instructions": "\n".join(instructions),
        "prep_time": "",
        "cook_time": "",
        "servings": "",
        "image_url": "",
    }
