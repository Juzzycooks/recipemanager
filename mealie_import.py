import os
import uuid
import requests


REQUEST_TIMEOUT = 15  # seconds — prevents a dead Mealie host hanging a worker


def validate_mealie_url(base_url):
    """Mealie usually lives on the LAN, so private IPs are allowed —
    but only http(s) schemes, and this is admin-only at the route level."""
    from urllib.parse import urlparse
    parsed = urlparse(base_url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ValueError("Mealie URL must start with http:// or https://")


def mealie_auth(base_url, email, password):
    """Authenticate with Mealie and return a bearer token."""
    validate_mealie_url(base_url)
    resp = requests.post(
        f"{base_url.rstrip('/')}/api/auth/token",
        data={"username": email, "password": password, "grant_type": ""},
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        timeout=REQUEST_TIMEOUT,
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def mealie_get_recipes(base_url, token, page=1, per_page=50):
    """Fetch a page of recipe summaries from Mealie."""
    resp = requests.get(
        f"{base_url.rstrip('/')}/api/recipes",
        params={"page": page, "perPage": per_page},
        headers={"Authorization": f"Bearer {token}"},
        timeout=REQUEST_TIMEOUT,
    )
    resp.raise_for_status()
    data = resp.json()
    return data.get("items", []), data.get("total", 0)


def mealie_get_recipe_detail(base_url, token, slug):
    """Fetch full recipe detail by slug."""
    resp = requests.get(
        f"{base_url.rstrip('/')}/api/recipes/{slug}",
        headers={"Authorization": f"Bearer {token}"},
        timeout=REQUEST_TIMEOUT,
    )
    resp.raise_for_status()
    return resp.json()


def download_mealie_image(base_url, token, recipe_id, uploads_dir):
    """Download recipe image from Mealie and save locally. Returns local filename or empty string."""
    if not recipe_id:
        return ""
    
    image_url = f"{base_url.rstrip('/')}/api/media/recipes/{recipe_id}/images/original.webp"
    try:
        resp = requests.get(
            image_url,
            headers={"Authorization": f"Bearer {token}"},
            timeout=30
        )
        if resp.status_code != 200:
            return ""
        
        # Determine extension from content-type
        content_type = resp.headers.get("Content-Type", "")
        ext = "webp"
        if "jpeg" in content_type or "jpg" in content_type:
            ext = "jpg"
        elif "png" in content_type:
            ext = "png"
        elif "gif" in content_type:
            ext = "gif"
        
        # Save with unique filename
        filename = f"recipe_{uuid.uuid4().hex[:12]}.{ext}"
        filepath = os.path.join(uploads_dir, filename)
        
        with open(filepath, "wb") as f:
            f.write(resp.content)
        
        return filename
    except Exception:
        return ""


def parse_mealie_recipe(data, base_url=""):
    """Convert a Mealie recipe JSON into our internal format."""
    # Ingredients: Mealie stores as list of objects with 'display' or 'note'
    ingredients = []
    for ing in data.get("recipeIngredient", []):
        if isinstance(ing, dict):
            ingredients.append(ing.get("display") or ing.get("note", ""))
        else:
            ingredients.append(str(ing))

    # Instructions: list of objects with 'text'
    instructions = []
    for step in data.get("recipeInstructions", []):
        if isinstance(step, dict):
            instructions.append(step.get("text", ""))
        else:
            instructions.append(str(step))

    # Image URL
    image_url = ""
    slug = data.get("slug", "")
    recipe_id = data.get("id", "")
    if slug and base_url:
        image_url = f"{base_url.rstrip('/')}/api/media/recipes/{recipe_id}/images/original.webp"

    # Categories
    categories = []
    for cat in data.get("recipeCategory", []):
        if isinstance(cat, dict):
            categories.append(cat.get("name", ""))
        elif isinstance(cat, str):
            categories.append(cat)

    prep_time = data.get("prepTime") or ""
    cook_time = data.get("totalTime") or ""
    servings = data.get("recipeYield") or ""

    return {
        "title": data.get("name", "Imported Recipe"),
        "description": data.get("description", ""),
        "ingredients": "\n".join(filter(None, ingredients)),
        "instructions": "\n".join(filter(None, instructions)),
        "prep_time": prep_time,
        "cook_time": cook_time,
        "servings": servings,
        "image_url": image_url,
        "source_url": data.get("orgURL", ""),
        "categories": [c for c in categories if c],
    }
