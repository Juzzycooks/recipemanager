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

### Recipes
| | |
|---|---|
| `GET /recipes` | `q`, `ingredient`, `cat` (repeatable), `collection`, `favorites=1`, `sort` = `newest\|oldest\|title_az\|title_za`, `page`, `per_page` |
| `GET /recipes/recent` | recently cooked, each with `cooked` ("3 days ago"); `limit` |
| `GET /recipes/random` | `cat`, `favorites` |
| `POST /recipes` | `title` (required), `description`, `ingredients`, `instructions`, `prep_time`, `cook_time`, `servings`, `source_url`, `notes`, `image_url`, `category_ids[]`, `image_file` (multipart) |
| `GET /recipes/{id}` | full detail: sections, nutrition estimate, `my_rating`, `made_count`, `last_made`, `collections`, `comments`, `share_url`, `can_edit` |
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
| `POST /import/url` | `{url}` returns `{kind, draft, source_url, image_name, image_url, raw_text, warning}` |
| `POST /import/caption` | `{caption, title?}` pasted text or social caption |
| `POST /import/photo` | multipart `photos` (in order), `photo_title?`, `use_as_cover?` (OCR) |
| `POST /import/pdf` | one file in `pdf_files` returns a draft; several are saved directly |
| `POST /import/urls` | `{urls: []}` (max 50) saved directly; `{imported[], failed[]}` |
| `POST /import/save` | the (edited) `draft` fields plus `source_url`, `image_name`, `use_image` returns the recipe (201) |

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
