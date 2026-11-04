# Spoonmate JSON API (v1)

Base path `/api/v1`. For native apps and scripts; the web UI does not use it.
Code: `routes/api_v1.py`. Tests: `tests/test_api_v1.py`.

## Conventions

- **Auth:** `Authorization: Bearer <token>`. Get a token from `POST /auth/login` (or `/auth/setup` on a fresh server). Tokens are stored hashed, never expire, and are revoked by `POST /auth/logout` or `DELETE /auth/tokens/{id}`. Changing a password signs out the other devices. Cookie sessions are ignored, so CSRF does not apply.
- **Bodies:** JSON (`Content-Type: application/json`). Endpoints that take files use `multipart/form-data`; recipe and collection create/update accept multipart too.
- **Errors:** `{"error": {"code": "...", "message": "..."}}`. Codes: `unauthorized` 401, `forbidden` 403, `not_found` 404, `validation` 422, `conflict` 409, `rate_limited` 429, plus `import_failed`, `no_caption`, `ocr_unavailable`, `restore_failed`, `setup_required`.
- **Lists:** `{"items": [...]}`. Recipes add `page`, `per_page` (max 100), `total`, `pages`.
- **Dates:** ISO 8601 UTC (`2026-10-01T09:30:00+00:00`); plan days are `YYYY-MM-DD`.
- **Images:** `image_url` / `thumb_url` are a path on this server (`/admin/uploads/...`, no token needed) or an absolute `https://` link. Empty string means no picture (show a letter tile).
- **Ingredients / instructions** are plain text with `# Heading` lines as section markers. Every recipe also carries `ingredient_sections` / `instruction_sections`: `[{heading|null, lines[]}]`.
- **Deletes and unshares** return `204` with no body.
- One shared recipe library; ratings are per user, favourites, cook history, collections, shopping list and meal plan are per user. Only a recipe's owner or an admin can edit or delete it.

## Endpoints

### Public (no token)
| | |
|---|---|
| `GET /site` | `{api_version, name, logo_url, setup_required, ocr_available, store}` |
| `GET /units` | `{version, liquids[], solids[{name, grams_per_cup, us_cups}]}`, the ingredient table for converting cups and ounces (`static/unit-ingredients.json`) |
| `POST /auth/setup` | `{username, password, email?, device_name?}` first admin only (409 after). Returns `{token, user}` |
| `POST /auth/login` | `{username, password, device_name?}` returns `{token, user}`. 5 failures per 5 min per IP/user, then 429 |
| `POST /auth/forgot-password` | `{email}` always answers the same |
| `GET /shared/recipes/{token}` | public recipe (no notes, ratings or comments; author only if the admin setting allows) |
| `GET /shared/collections/{token-or-slug}` and `/recipes/{id}` | public collection / a recipe in it |
| `GET /shared/mealplan/{token}?from&to&week` | public plan |

### Account
| | |
|---|---|
| `POST /auth/logout` | revoke this token |
| `GET /auth/tokens`, `DELETE /auth/tokens/{id}` | list / revoke devices |
| `GET /me`, `PATCH /me` | `{email}` |
| `POST /me/password` | `{current_password, new_password}` |
| `DELETE /me` | `{password}` deletes your account and everything you added; 422 for the last admin |

### Recipes
| | |
|---|---|
| `GET /recipes` | `q`, `ingredient`, `cat` (repeatable), `collection`, `favorites=1`, `sort` = `newest\|oldest\|title_az\|title_za`, `page`, `per_page` |
| `GET /recipes/recent` | recently cooked, each with `cooked` ("3 days ago"); `limit` |
| `GET /recipes/random` | `cat`, `favorites` |
| `POST /recipes` | `title` (required), `description`, `ingredients`, `instructions`, `prep_time`, `cook_time`, `servings`, `source_url`, `notes`, `image_url`, `calories_per_serving` (whole number 0-20000; `null` or `""` clears it), `category_ids[]`, `image_file` (multipart) |
| `GET /recipes/{id}` | full detail: sections, `nutrition` (estimate), `calories_per_serving`, `nutrition_facts` (see [Nutrition](#nutrition)), `my_rating`, `made_count`, `last_made`, `collections`, `comments`, `share_url`, `can_edit` |
| `PATCH /recipes/{id}` | any subset of the create fields |
| `DELETE /recipes/{id}` | returns `{restore_token, expires_in}` |
| `POST /recipes/restore/{token}` | undo within 24 h |
| `POST /recipes/{id}/duplicate` | |
| `PUT /recipes/{id}/image` (multipart `image_file`), `DELETE`, `POST .../image/localise` | |
| `PUT` / `DELETE /recipes/{id}/favorite` | idempotent; returns `{favorited}` |
| `PUT /recipes/{id}/rating` `{score: 1-5}`, `DELETE` | returns `{my_rating, avg_rating, rating_count}` |
| `GET` / `POST /recipes/{id}/comments` `{text}`, `DELETE /comments/{id}` | |
| `PUT /recipes/{id}/notes` | `{notes}` |
| `POST` / `DELETE /recipes/{id}/share` | returns `{share_url}` |
| `POST /recipes/{id}/made`, `GET .../cook-history` | cook log |
| `POST /recipes/{id}/email` | `{email}` |
| `GET /categories`, `POST` (admin) `{name}`, `DELETE /categories/{id}` (admin) | |

### Import (nothing saves until `/import/save`, except the bulk forms)
| | |
|---|---|
| `POST /import/url` | `{url}` returns `{kind, draft, source_url, image_name, image_url, raw_text, source_nutrition, warning}`. `source_nutrition` is what the site published per serving, `{kcal, protein, fat, carbs, serving_size}` (each may be null), or null. The other previews return it as null |
| `POST /import/caption` | `{caption, title?}` pasted text or social caption |
| `POST /import/photo` | multipart `photos` (in order), `photo_title?`, `use_as_cover?` (OCR) |
| `POST /import/pdf` | one file in `pdf_files` returns a draft; several are saved directly |
| `POST /import/urls` | `{urls: []}` (max 50) saved directly; `{imported[], failed[]}` |
| `POST /import/save` | the (edited) `draft` fields plus `source_url`, `image_name`, `use_image`, `source_nutrition` (pass back the preview's object, or null) and optional `calories_per_serving`; returns the recipe (201) |

### Nutrition

Recipe detail carries three related keys:

- `calories_per_serving`: int or null, the figure the cook typed in.
- `nutrition`: the ingredient estimate in the original shape, kept for older clients: `{kcal, protein, fat, carbs, matched, total_lines, servings, per_serving: {kcal, protein, fat, carbs} | null}`, or null when under half the countable lines are recognised. Numbers are never null. `matched` counts recognised lines including salt, spices and garnishes; `per_serving` is present whenever `servings` is 1 or more.
- `nutrition_facts`: what to show, or null when there is no figure at all:

```json
{
  "source": "manual" | "recipe" | "estimate",
  "servings": 4,
  "yield_unit": "serving",
  "per_serving": {"kcal": 512, "protein": 31.2, "fat": 18.4, "carbs": 52.0},
  "total": {"kcal": 2048, "protein": 124.8, "fat": 73.6, "carbs": 208.0},
  "estimate": {
    "kcal": 2010, "protein": 120.3, "fat": 70.1, "carbs": 205.6,
    "confidence": "high" | "medium" | "low",
    "matched": 9, "counted_lines": 10, "total_lines": 13,
    "lines": [{"text": "2 cups plain flour", "food": "plain flour", "grams": 240, "kcal": 874, "status": "matched"}]
  }
}
```

- **Precedence:** `manual` (`calories_per_serving` is set) beats `recipe` (the source site published calories, kept from import) beats `estimate`.
- **servings / yield_unit:** parsed from the recipe's servings text. "Serves 4-6" is 4; "Makes 12 cookies" is 12 with `yield_unit` "cookies" (show "per cookie"); anything about people or servings is "serving". `servings` is null when there is no number.
- **per_serving:** for `manual`, `kcal` is the typed figure and protein, fat and carbs come from the recipe source when it has them, else from the estimate divided by servings, else null. For `recipe`, all four come from the source (any may be null). For `estimate`, it is the estimate divided by servings, or null when servings is unknown.
- **total:** for `manual` and `recipe`, `per_serving` times `servings`, or null when servings is unknown. For `estimate`, the estimate's totals.
- **estimate:** present whenever the ingredients can be estimated, whatever the source, so a client can show "our estimate" beside a typed or published figure. Totals are for the whole recipe. `lines` lists every ingredient line (headings left out) with `status`: `matched` (counted), `negligible` (salt, pepper, spices, small herbs, water, raising agents, stock cubes, plus optional, garnish and to-taste lines: shown, not counted) or `unmatched` (not recognised). `food`, `grams` and `kcal` may be null. `matched` and `counted_lines` leave the negligible lines out. `confidence` is the share of counted lines matched with a stated quantity: high at 85% or more, medium at 60% or more, else low. There is no estimate when under half the counted lines match.
- **Rounding:** kcal are integers, protein, fat and carbs one decimal.
- Food values per 100 g come from USDA FoodData Central (`static/nutrition-foods.json`); cups of solids use `grams_per_cup` from `GET /units`.

### Collections (your own)
`GET/POST /collections` (`name`, `description`, `slug`, `category_id`, `cover_image`), `GET/PATCH/DELETE /collections/{id}` (`remove_cover`), `POST/DELETE /collections/{id}/share`, `POST /collections/{id}/recipes` `{recipe_id}`, `DELETE /collections/{id}/recipes/{rid}`, `PUT /collections/{id}/order` `{order: [recipe ids]}`. Detail has `recipes` (manual first, then category-linked) and `manual_recipe_ids` (the removable ones).

### Meal plan
`GET /mealplan?from&to` (or `?week=offset`; default this Monday to Sunday; max 92 days), `POST /mealplan` `{recipe_id, date, meal_type}`, `PATCH /mealplan/{id}` `{date?, meal_type?, recipe_id?}`, `DELETE /mealplan/{id}`, `POST /mealplan/shopping` `{from, to}` or `{week}`, `POST /mealplan/auto-generate` `{week?, meal_types?}`, `POST/DELETE /mealplan/share`. `meal_type` is `breakfast|lunch|dinner|snack`.

### Shopping list
`GET /shopping` returns `{store, aisle_order, items[]}` (each item has `aisle`, `store_url` and `recipe_title` when it came from a recipe; group by `aisle` in `aisle_order`). `POST /shopping/items` `{name}` or `{names: []}` (same item + compatible unit combines quantities; returns `{added, merged}`). `POST /shopping/recipe/{id}` optional `{items: [lines]}`. `PATCH /shopping/items/{id}` `{checked?, name?}`. `DELETE /shopping/items/{id}`. `DELETE /shopping/items` clears all, or only ticked with `?checked=1`.

### Guides and calculators
`GET /extras`, `POST/DELETE /extras/{slug}/share`. `GET /calculators`, `GET /calculators/{id}`; admin: `POST`, `PATCH`, `DELETE`.

### Admin (admin tokens only)
`GET/POST /admin/users` (create returns `temp_password` unless it was emailed), `PATCH/DELETE /admin/users/{id}` (`username`, `email`, `is_admin`, `new_password`), `GET/PATCH /admin/settings` (`site_name`, `public_show_author`, `store_name`, `store_search_url` with `{q}`, `logo_file` multipart, `remove_logo`).

## Not in the API (yet)

Backup export/import and the Mealie importer stay web-only (large files, admin-only). Print, export-as-text and cook mode are presentation: a client builds them from `ingredient_sections` / `instruction_sections`. The unit converter is client-side in the web app too.

## Trying it

```bash
TOKEN=$(curl -s localhost:5000/api/v1/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"me","password":"..."}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -s localhost:5000/api/v1/recipes?q=soup -H "Authorization: Bearer $TOKEN"
```

Over the internet, serve it behind HTTPS (set `COOKIE_SECURE=1`, `TRUSTED_PROXY=1` behind a proxy): iOS refuses plain HTTP by default and the bearer token is a password.
