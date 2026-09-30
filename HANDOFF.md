# Handoff

Everything a new person (or a fresh Claude session) needs to keep working on Recipe Manager.
Product truth lives in `PRODUCT.md`; the visual system lives in `DESIGN.md` and `.impeccable/design.json`; the direction contract lives in `.impeccable/surfaces/app.md`. This file covers how the project is put together, how to run and ship it, what changed recently, and what is still unverified.

## What it is

A self-hosted Flask + Jinja recipe manager for a home server (Docker / Unraid), image `juzzycooks/recipemanager` on Docker Hub. No front-end framework, plain CSS and small vanilla JS files. SQLite in `DATA_DIR` (default `/app/data`). One shared recipe library for all users.

Main areas: recipe shelf and recipe page, import (link, Instagram/TikTok, photo/screenshot, PDF, Mealie), collections with public share links, weekly meal plan (plus a public plan link), shopping list, cook mode, unit converter, calculators and guides ("Guides" was "Extras"), admin (users, categories, settings, backup, pictures).

## Layout of the repo

| Path | What |
|---|---|
| `app.py` | App factory, security headers (CSP), gzip, template filters, `asset_v` cache-buster, `get_setting()` per-request cache |
| `models.py`, `migrate.py` | SQLAlchemy models; startup migrations |
| `routes/` | One blueprint per area (`recipes`, `collections`, `mealplan`, `shopping`, `admin`, `auth`, `extras`, `calculators`, `api`) |
| `routes/api_v1.py` | Token-authenticated JSON API for native apps, covering every area. Reference in `API.md`; tests in `tests/test_api_v1.py`. The old `routes/api.py` is the PantryTracker read-only API and is unchanged |
| `scraper.py` | URL import: JSON-LD, microdata, WPRM/Tasty/Mediavine sections and notes, Instagram oEmbed |
| `recipe_text.py` | One parser for loose text (captions, PDF text, OCR text) into title/ingredients/method/notes/times. Section headings are lines starting `# ` |
| `ocr.py` | Tesseract wrapper for photo/screenshot import (Tesseract is in the Docker image) |
| `shopping_utils.py` | Ingredient parsing, merging, aisle grouping (`_PANTRY_PHRASES` checked first) |
| `images.py`, `security.py` | Safe image saving + thumbnails; SSRF-guarded `safe_get` |
| `templates/` | Jinja. `base.html` is the shell (masthead, tab bar, menus, undo flash, offline/install/shortcut UI) |
| `static/css/` | `tokens.css` (single source of truth for colour/type/space), `app.css` (shell + components), then per-area files loaded with `{% block head %}` |
| `static/js/` | `app.js` (shortcuts, install hint, offline notice), `cook.js`, `shelf.js`, `shopping.js` |
| `static/pages/` | Self-contained guides and calculators (embedded pages); they load `_theme.css` which imports the tokens |
| `static/sw.js`, `static/offline.html` | Service worker (offline pages, cache-first uploads) |
| `tests/` | `unittest` suites plus `test_cook.js` (Node) and `smoke_routes.py` |

## Design system in one paragraph

"The Well-Used Cookbook": white index-card stock with pale-blue ruled lines, blue-black ink, one red-pen terracotta accent (`--accent` for text/lines, `--accent-solid` for fills that carry white text), Alegreya (self-hosted in `static/fonts`, declared in `css/fonts.css`) for display and recipe reading, system sans for controls. Dark theme is a chalkboard; cook mode is always chalkboard (`--cook-*` tokens). Photo-less recipes show a tinted letter tile, never "No image". Rules: change tokens only in `static/css/tokens.css`; no inline `style=""`, no hard-coded hex in templates, no emoji as icons (inline SVG, stroke 1.8), no side-stripe cards, 44px touch targets on coarse pointers, `prefers-reduced-motion` respected. One primary action per surface (recipe page: Start cooking; the rest in menus).

## Run, test, ship

Needs Python 3.10+ (the code uses `str | None`). Dependencies are in `requirements.txt`; the app also uses Tesseract for photo import (optional locally, present in Docker).

```bash
# run locally
pip install -r requirements.txt
DATA_DIR=./data python -c "from app import create_app; create_app().run(port=5000)"

# tests (unittest + Node for the cook-mode logic)
python -m unittest discover -s tests -t .
node tests/test_cook.js

# render every route with sample data and report server errors
python tests/smoke_routes.py

# build and push the multi-arch image (amd64 for Unraid, arm64 for Apple silicon / Pi)
docker buildx build --platform linux/amd64,linux/arm64 \
  -t juzzycooks/recipemanager:latest -t juzzycooks/recipemanager:$(git rev-parse --short HEAD) --push .
```

Tag each push with the commit hash so a rollback is one `docker pull`. After a deploy, users may need one hard refresh because the service worker caches scripts.

## Settings stored in `SiteSetting` (Admin, Site settings)

`site_name`, `logo_file`, `store_name` and `store_search_url` (shopping "find" link, `{q}` is replaced; empty hides it), `public_show_author` (show the owner's username on shared pages, off by default), `mealplan_share_<user_id>` (meal-plan share token).

## Behaviours worth knowing

- **Import** opens a preview ("Check what we found") for a single recipe; several links or PDFs save immediately. Nothing is saved from a social post whose caption can't be read.
- **Instagram** uses the public oEmbed endpoint (`/api/v1/oembed/`) first, then the embed page. It can be blocked or changed by Instagram; the fallback is paste-the-caption or screenshot import. The thumbnail is downloaded (their links expire).
- **Pictures**: imports keep a local copy plus a 480px thumbnail. Old recipes that still point at another site are repaired automatically on first view (`POST /recipe/<id>/localise-image`) and in bulk from Admin, Pictures. The downloader sends the image site's own origin as Referer.
- **Undo delete**: deleted recipes are written to `DATA_DIR/trash/<token>.json` for 24 hours (images are kept until the trash entry expires). The "Undo" button is a flash with category `undo` and message `text|token`.
- **Offline**: the service worker saves the shelf, recipe pages, cook mode, shopping list and meal plan as you visit them (cleared on sign-out) and serves `static/offline.html` otherwise.
- **Cook mode** (`static/js/cook.js`, shared by the signed-in and public cook pages): timer chips parsed from step text, per-step "You'll need" from the live (scaled) ingredient list, finish screen with made-it and rating, swipe/arrow keys, two-pane on wide screens, `#step-3` / `#timers` / `#finish` deep links, progress kept in `sessionStorage`.
- **Keyboard shortcuts**: `/` search, `n` new recipe, `g` then `r/c/p/s`, `?` help.
- **Install hint** appears only on phones, from the third session, only when an install prompt exists (or iOS instructions), and always goes away.

## Recent changes (newest first)

Recipe pictures kept locally and repaired automatically; install hint fixed; "New recipe" offers Write / Link / Photo; cook mode upgrades; round-2 fixes to Plan, Shop, Admin and the recipe form; usability batch (import preview, photo import, Instagram, hearts, undo, offline, sharing); redesign to the current design system; earlier design-system, accessibility, motion, type and performance passes.

## Not verified in a real browser (do this before relying on it)

The work was built without a scriptable browser, so these were checked by tests and reading, not by clicking:
dialogs (shopping picker, meal-plan share/move, keyboard shortcuts), the service worker and offline mode, the install hint on a real phone, drag and drop on the meal plan, the fetch-based favorite heart and cook-mode made-it/rating buttons, timer chips starting timers and swiping in cook mode, Instagram import against more than the one post tested, and OCR on real phone photos and handwriting (tested on generated screenshots only).

## Known gaps and ideas

- Ingredient-to-step matching in cook mode is word based (misses "the mixture", can over-match).
- "Overnight" is not turned into a timer.
- The users table on phones hides its Actions column behind a sideways scroll (the username links to the edit page).
- The `static/pages/*` guides still contain a few hard-coded names ("Juzzycooks") in titles.
- Collections have no equivalent of the recipe "undo delete".
- No automated browser tests; adding Playwright would cover most of the list above.

## Working notes for the next Claude session

- Don't guess at visuals: render pages and look. On macOS, Safari can be opened and captured with `screencapture`, but Safari blocks scripting unless the user enables "Allow JavaScript from Apple Events". If you screenshot from the user's Safari, open your own window, verify it is showing localhost, and close only that window by id. Screenshots can include desktop notifications; delete them.
- The sandbox server caches Jinja templates when not in debug mode: restart it after template edits.
- Scratch tooling (sandbox server, sample-data seeding, screenshot helper) lived outside the repo; `tests/smoke_routes.py` is the part worth keeping.
- Impeccable design tooling lives in `.claude/` (untracked). `PRODUCT.md`, `DESIGN.md` and `.impeccable/` are tracked.
