"""Woolworths product search — best-effort price lookup."""

import re
import logging
import requests

logger = logging.getLogger(__name__)

SEARCH_URL = "https://www.woolworths.com.au/apis/ui/Search/products"

_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Accept": "application/json, text/plain, */*",
    "Content-Type": "application/json",
    "Origin": "https://www.woolworths.com.au",
    "Referer": "https://www.woolworths.com.au/shop/search/products",
}


def _clean_ingredient(text: str) -> str:
    """Strip quantities/units to get a cleaner search term.

    '2 cups all-purpose flour' -> 'all-purpose flour'
    '400g canned tomatoes'     -> 'canned tomatoes'
    """
    # Remove leading numbers, fractions, units
    cleaned = re.sub(
        r"^[\d½¼¾⅓⅔⅛/.\s-]+"
        r"(cups?|tbsp|tsp|tablespoons?|teaspoons?|oz|ounces?|lbs?|pounds?"
        r"|g|grams?|kg|kilograms?|ml|mL|litres?|liters?|l|cans?|cloves?"
        r"|pinch(?:es)?|bunch(?:es)?|handful|slices?|pieces?|large|medium|small"
        r"|whole|fresh|dried|chopped|minced|diced|finely|roughly)[\s,]*",
        "", text, flags=re.IGNORECASE,
    ).strip(" ,.-")
    # If we stripped everything, fall back to original
    return cleaned if len(cleaned) > 1 else text


def search_product(ingredient: str) -> dict | None:
    """Search Woolworths for a single ingredient.

    Returns dict with keys: name, price, cup_string, image, url
    or None on failure.
    """
    term = _clean_ingredient(ingredient)
    payload = {
        "Filters": [],
        "IsSpecial": False,
        "Location": f"/shop/search/products?searchTerm={term}",
        "PageNumber": 1,
        "PageSize": 1,
        "SearchTerm": term,
        "SortType": "TraderRelevance",
    }
    try:
        resp = requests.post(SEARCH_URL, json=payload, headers=_HEADERS, timeout=8)
        if resp.status_code != 200:
            logger.debug("Woolworths search returned %s for '%s'", resp.status_code, term)
            return None
        data = resp.json()
        products = data.get("Products", [])
        if not products:
            return None
        first = products[0].get("Products", [])
        if not first:
            return None
        p = first[0]
        stockcode = p.get("Stockcode", "")
        url_name = p.get("UrlFriendlyName", "")
        return {
            "name": p.get("DisplayName") or p.get("Name", ""),
            "price": p.get("Price"),
            "was_price": p.get("WasPrice"),
            "is_on_special": p.get("IsOnSpecial", False),
            "cup_string": p.get("CupString", ""),
            "image": p.get("MediumImageFile", ""),
            "url": f"https://www.woolworths.com.au/shop/productdetails/{stockcode}/{url_name}"
                   if stockcode else "",
        }
    except Exception as e:
        logger.debug("Woolworths search error for '%s': %s", term, e)
        return None


def search_products_bulk(ingredients: list[str]) -> dict[str, dict | None]:
    """Look up multiple ingredients. Returns {ingredient: result_or_None}."""
    results = {}
    for ing in ingredients:
        ing = ing.strip()
        if ing:
            results[ing] = search_product(ing)
    return results
