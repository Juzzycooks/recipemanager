"""The ingredient table behind metric / US conversion of cups and ounces.

One copy, static/unit-ingredients.json, feeds both the website (written into recipe pages for
static/unitconv.js) and the iPhone app (GET /api/v1/units).
"""
import json
import os

_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static", "unit-ingredients.json")
_cache = {}


def unit_ingredients():
    """The parsed table, re-read only when the file changes."""
    mtime = os.path.getmtime(_PATH)
    if _cache.get("mtime") != mtime:
        with open(_PATH, encoding="utf-8") as f:
            data = json.load(f)
        data.pop("about", None)
        _cache.update(mtime=mtime, data=data)
    return _cache["data"]
