import re
import json
import html as html_mod
from bs4 import BeautifulSoup

from security import safe_get
from recipe_text import parse_recipe_text


def _clean(value):
    """Plain text from a JSON-LD / microdata value: unescape entities, drop tags, collapse spaces."""
    if value is None:
        return ""
    text = str(value)
    if "<" in text and ">" in text:
        text = BeautifulSoup(text, "html.parser").get_text(" ")
    text = html_mod.unescape(text).replace("\u00a0", " ")
    return re.sub(r"[ \t]+", " ", text).strip()


def _clean_lines(value):
    """Clean each line of a newline-separated block, keeping "# heading" markers."""
    return "\n".join(l for l in (_clean(x) for x in str(value).split("\n")) if l)


_GENERIC_TITLES = {"ingredients", "instructions", "directions", "method", "steps", "notes", "preparation"}
_PLUGIN_BLOCKS = {
    # (ingredients, instructions, notes) container class prefixes for popular recipe plugins
    "tasty": ("tasty-recipes-ingredients", "tasty-recipes-instructions", "tasty-recipes-notes"),
    "mediavine": ("mv-create-ingredients", "mv-create-instructions", "mv-create-notes"),
}


def _extract_plugin_block(soup, class_name, with_headings=True):
    """Lines from a recipe-plugin container: headings become "# Heading", <li>/<p> become lines."""
    box = soup.find(lambda t: _has_class(t, class_name))
    if not box:
        return None
    out = []
    for el in box.find_all(["h2", "h3", "h4", "h5", "h6", "li", "p"]):
        if el.name.startswith("h"):
            name = _clean(el.get_text(" ", strip=True))
            if with_headings and name and name.lower().rstrip(":") not in _GENERIC_TITLES:
                out.append("# " + name.rstrip(":"))
        elif el.name == "li" and el.find("li"):
            continue  # a wrapper around nested items
        elif el.name == "p" and el.find_parent("li"):
            continue
        else:
            text = _clean(el.get_text(" ", strip=True))
            if text:
                out.append(text)
    return "\n".join(out) if out else None


def _extract_grouped(soup, kind):
    """Ingredient/instruction lines with section headings, from WPRM, Tasty or Mediavine markup."""
    found = _extract_wprm_groups(soup, kind)
    if found and "# " in found:
        return found
    idx = 0 if kind == "ingredient" else 1
    for blocks in _PLUGIN_BLOCKS.values():
        found = _extract_plugin_block(soup, blocks[idx])
        if found and "# " in found:
            return found
    return None


def _extract_notes(soup):
    """Recipe notes from WPRM, Tasty or Mediavine markup."""
    notes = _extract_wprm_notes(soup)
    if notes:
        return notes
    for blocks in _PLUGIN_BLOCKS.values():
        found = _extract_plugin_block(soup, blocks[2], with_headings=False)
        if found:
            return found
    return ""


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
    """Kept for callers that want (description, ingredients, instructions)."""
    parsed = parse_recipe_text(caption)
    return caption or "", parsed["ingredients"], parsed["instructions"]


_IG_CODE = re.compile(r"instagram\.com/(?:[\w.]+/)?(p|reel|reels|tv)/([\w-]+)", re.I)


def _instagram_oembed(url, headers):
    """Instagram's public oEmbed endpoint returns the full caption (as "title") without a login."""
    from urllib.parse import quote
    m = _IG_CODE.search(url)
    if not m:
        return "", ""
    kind = "reel" if m.group(1).lower() in ("reel", "reels") else "p"
    canonical = f"https://www.instagram.com/{kind}/{m.group(2)}/"
    try:
        resp = safe_get(f"https://www.instagram.com/api/v1/oembed/?url={quote(canonical, safe='')}",
                        headers=headers, timeout=15)
        data = json.loads(resp.text)
    except Exception:
        return "", ""
    caption = (data.get("title") or "").strip() if isinstance(data, dict) else ""
    thumb = data.get("thumbnail_url", "") if isinstance(data, dict) else ""
    return caption, thumb


def _instagram_embed_caption(url, headers):
    """Caption + image for an Instagram post: oEmbed first, then the public embed page.

    Both come back empty when Instagram refuses (private/removed posts, or blocked IPs).
    """
    caption, image = _instagram_oembed(url, headers)
    if caption:
        return caption, image
    m = _IG_CODE.search(url)
    if not m:
        return "", ""
    kind = "reel" if m.group(1).lower() in ("reel", "reels") else "p"
    embed_url = f"https://www.instagram.com/{kind}/{m.group(2)}/embed/captioned/"
    try:
        page = safe_get(embed_url, headers=headers, timeout=15).text
    except Exception:
        return "", image
    soup = BeautifulSoup(page, "html.parser")
    cap_el = soup.find(lambda t: _has_class(t, "Caption"))
    caption = ""
    if cap_el:
        for junk in cap_el.find_all(lambda t: _has_class(t, "CaptionUsername") or _has_class(t, "CaptionComments")):
            junk.decompose()
        for br in cap_el.find_all("br"):
            br.replace_with("\n")
        caption = re.sub(r"\n{3,}", "\n\n", cap_el.get_text()).strip()
    if not caption:
        caption = _extract_caption_from_html(page)
    img = soup.find("img", class_="EmbeddedMediaImage")
    return caption, image or (img.get("src", "") if img else _extract_meta(page, "image"))


def _scrape_social_media(url, html, headers=None):
    """Extract recipe info from social media pages (Instagram, TikTok, etc.)."""
    title = _html_unescape(_extract_meta(html, "title")) or ""
    image = _extract_meta(html, "image")
    caption = _extract_caption_from_html(html)

    if "instagram.com" in url.lower():
        embed_caption, embed_image = _instagram_embed_caption(url, headers or {})
        if len(embed_caption) > len(caption):
            caption = embed_caption
        image = image or embed_image

    parsed = parse_recipe_text(caption)
    if not parsed["title"]:
        parsed["title"] = title if title and title.lower() != "instagram" else "Imported Recipe"

    return {
        "title": parsed["title"],
        "description": parsed["description"],
        "ingredients": parsed["ingredients"],
        "instructions": parsed["instructions"],
        "notes": parsed["notes"],
        "prep_time": parsed["prep_time"],
        "cook_time": parsed["cook_time"],
        "servings": parsed["servings"],
        "image_url": image,
        "source_type": "social",
        "caption_found": bool(caption),
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
        "title": _clean(_prop("name")) or "Imported Recipe",
        "description": _clean(_prop("description")),
        "ingredients": "\n".join(c for c in (_clean(i) for i in ingredients) if c),
        "instructions": "\n".join(c for c in (_clean(i) for i in instructions) if c),
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
        result = _scrape_social_media(url, html_text, headers)
        result["source_url"] = url
        return result

    # Parse once for WPRM group/notes extraction and the microdata fallback
    soup = BeautifulSoup(html_text, "html.parser")
    notes = _extract_notes(soup)

    # Try JSON-LD structured data (most recipe sites use this)
    ld = _extract_json_ld_recipe(html_text)
    if ld:
        # Parse ingredients
        raw_ing = ld.get("recipeIngredient") or ld.get("ingredients") or []
        if isinstance(raw_ing, list):
            ingredients = "\n".join(c for c in (_clean(i) for i in raw_ing) if c)
        else:
            ingredients = _clean_lines(raw_ing)

        # Parse instructions (handles HowToStep, nested HowToSection, strings)
        instructions = _clean_lines(_parse_instructions(ld.get("recipeInstructions", "")))

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
        grouped_ing = _extract_grouped(soup, "ingredient")
        if grouped_ing:
            ingredients = grouped_ing
        # For instructions, JSON-LD HowToSection may already give headings;
        # only fall back to WPRM if JSON-LD didn't provide any.
        if "# " not in instructions:
            grouped_inst = _extract_grouped(soup, "instruction")
            if grouped_inst:
                instructions = grouped_inst

        return {
            "title": _clean(ld.get("name")) or "Imported Recipe",
            "description": _clean(description),
            "ingredients": ingredients,
            "instructions": instructions,
            "prep_time": _parse_iso_duration(ld.get("prepTime", "")),
            "cook_time": _parse_iso_duration(ld.get("cookTime", "")),
            "servings": _clean(servings),
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

    parsed = parse_recipe_text(text)
    if not parsed["title"]:
        return None
    parsed["image_url"] = ""
    return parsed
