# Handoff

Everything a new person (or a fresh Claude session) needs to keep working on Spoonmate: the Flask server and the native iPhone app in `IOS/`.
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
| `IOS/` | The SwiftUI iPhone app, its Safari share extension and timer widget. See the iPhone app section below and `IOS/README.md` |
| `docs/screenshots/` | Screenshots used by the README (web and iPhone) |
| `tools/` | `generate_icons.py` (web and iOS icons from one drawing) and `seed_demo.py` (fills an empty server with a demo library) |
| `.github/dependabot.yml` | Weekly pip and monthly Docker base-image update PRs (security alerts and updates are also on) |
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

## The iPhone app (`IOS/`)

SwiftUI, iOS 18+, Swift 6, iPhone only and portrait only. The project is generated from `IOS/project.yml` with XcodeGen, **but do not run `xcodegen generate` right now**: the committed `.xcodeproj` has drifted from `project.yml` (it carries `DEVELOPMENT_TEAM = 6HTZR75UR8` and `INFOPLIST_KEY_LSApplicationCategoryType` that `project.yml` lacks), so regenerating silently drops the signing team and category. Until those are added to `project.yml`, bump `CURRENT_PROJECT_VERSION` in both files and add new source files to `project.pbxproj` by hand (four entries: build file, file reference, group, Sources phase; see `UnitConversion.swift`). Three targets share a keychain group: the app, `ShareExtension` (Safari "Save to Spoonmate") and `TimerWidget` (Live Activity for timers). Bundle IDs are `com.justinrahme.Spoonmate`, `.Share` and `.TimerWidget`. Version and build come from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` and must match across all three.

- **API client:** bearer tokens against `/api/v1` (`API.md`). `APIClient` also cleans HTML entities out of every response (`HTMLEntities.swift`) because imported recipes sometimes carry `&quot;` and `&#39;`. `APIClient.swift` and `HTMLEntities.swift` are compiled into the share extension too, so new files they depend on must be added to its source list in `project.yml`.
- **Offline:** `OfflineStore` (response cache plus the whole library), `Outbox` (queued favourite, rating, made-it and shopping changes), `Connectivity`, `OfflineSync`. Pictures live in `ImageStore` (same file as `OfflineStore`, `Application Support/Offline/Images`, downloaded once, wiped by `OfflineStore.clear()`); `RecipeImage` and the sync's picture prefetch both go through it, not `URLCache`, which iOS can purge. At launch `Session.restore` opens with the cached `/me` account in offline mode if the server is unreachable; the "Can't reach the server / Try again" screen is only for installs that never synced. `APIClient` retries a GET once on transient network errors.
- **Timers:** AlarmKit on iOS 26.1+, a notification burst before that. AlarmKit cannot be exercised in the simulator.
- **Theme:** `ThemeStore` drives light/dark and five colour themes. `Color.accentColor` does not follow it; use `AppColors`.
- **Cook mode ingredients:** each step shows a "For this step" card. `Core/StepIngredients.swift` is a Swift port of `matchIngredients` in `static/js/cook.js`; keep the two in step. Ingredient tick state on the recipe page is keyed by section and position, not by text, so duplicate lines are independent.
- **Tab bar and Home button:** the custom tab bar is drawn by each tab's root screen via `.withAppTabBar()` (`Components/AppTabBar.swift`), inside its `NavigationStack`, so a push slides it away with the screen instead of resizing the shell. Do not put it back in `MainView`. Every pushed screen gets a round Home button bottom-left (`.homeBar()` / `.homeBar { action }`, applied in `AppRoute.appDestinations()` and by the screens that have a bottom action: recipe detail, shopping list, meal plan). It calls `AppState.goHome()`, which switches to Home and bumps `homeRequest`; every tab root clears its `path` on that change (Search now has a path for this).
- **Offline speed and cancellations:** `APIClient.perform` fails immediately with an offline error while `Connectivity` already says offline (via `ResponseCaching.isOffline()`), so saved data answers with no timeout wait; only the connectivity probe (`ping`) bypasses it. It also rethrows `CancellationError` / `URLError.cancelled` unwrapped, so a superseded request never shows the "Something went wrong" alert. The first request after losing signal still waits out one timeout before the app flags itself offline.
- **Units (metric / US):** `Core/UnitConversion.swift` converts weights, volumes and oven temperatures for display only (Settings, Units; per-recipe toggle on the Ingredients tab; also Steps and cook mode). The shopping list and stored recipes are never converted, and "Add to shopping list" sends the original lines. Ticking an ingredient on the recipe page now means "I already have it": the button adds only the unticked lines.
- **Layout guard:** every vertical scroll page uses `VerticalScroll` (`SmallComponents.swift`: content pinned to the screen width, no sideways bounce) so a page can't be dragged aside to show blank space. Use it instead of a bare `ScrollView` for vertical pages.
- **Account deletion:** Profile, Account, Delete account calls `DELETE /api/v1/me` (needs the current server image; older servers answer 404 and the app says so).

```bash
cd IOS
xcodebuild test -project RecipeManager.xcodeproj -scheme RecipeManager \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO   # 32 tests
```

Unsigned builds cannot use the keychain, so for hands-on testing in the simulator build with signing on (`-allowProvisioningUpdates`) and reinstall; `xcodebuild test` reinstalls an unsigned copy.

## App Store status

Prepared, not yet submitted. Everything lives in `IOS/APP_STORE.md` (step-by-step guide) and `IOS/AppStore/`:

- `AppStoreListing.md`: paste-ready name, subtitle, promo text, keywords, description, What's New, review notes.
- `PRIVACY.md`: the privacy policy. Public URL: `https://github.com/Juzzycooks/recipemanager/blob/main/IOS/AppStore/PRIVACY.md`.
- `Screenshots/`: raw simulator captures in `raw/` (a real library, status bar 9:41) and `raw-demo/` (seeded demo server), framed slides in `iphone-6.9/` and `iphone-6.5/`, and `generate.sh` to rebuild them with the captions.
- Privacy manifest (`IOS/RecipeManager/Resources/PrivacyInfo.xcprivacy`), export compliance flag, account deletion and the sign-in explainer are done.
- Questionnaire answers already decided: age rating 4+ (all capability questions No, Age Category Not Applicable), third-party content No, Data Not Collected, no tracking.

**Still to do (needs a person):** enrol in the Apple Developer Program, set the Team for all three targets, create the App Store Connect record, stand up a public demo server with a non-admin reviewer account and fill the three placeholders in the review notes, run TestFlight on real phones (timers, share extension, local-network prompt, offline), then archive and upload. The app has been tried on a real iPhone and works.

## Repo and hosting

- GitHub `Juzzycooks/recipemanager`, now **public**; secret scanning and push protection are on. History was rewritten once (1 October 2026) to remove a personal email and an old username, so any clone older than that must be re-cloned.
- Docker Hub `juzzycooks/recipemanager`, last pushed from `main` at `d047ad2` (multi-arch, `latest` and `d047ad2`, digest `sha256:9df1ea67…`; includes the web unit conversion). Not yet pulled and deployed on the Unraid box as far as Claude knows. Rebuild after any server change; iOS-only or docs-only changes do not need it.
- **Unraid Community Applications:** the template is `spoonmate.xml` here and is mirrored in the public repo `Juzzycooks/unraid-templates` (its `<TemplateURL>` points there; keep the two copies identical). The image name and default appdata path stay `recipemanager` / `RecipeManager` so existing installs keep updating. Status: template written and URLs verified, but **not yet tested on an Unraid box, no forum support thread created, and not yet submitted to CA**. Next: test via `/boot/config/plugins/dockerMan/templates-user/`, post `[Support] Juzzycooks - Spoonmate` in the Docker Containers forum, switch `<Support>` in both copies to that thread URL, then submit the templates repo in the Community Applications forum.
- Keep work or personal information out of the repo. Before publishing anything new, grep for it, including the demo data and screenshots.

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

iPhone 1.0.0 builds 5 to 9 (commits `455bceb` and later; pushed, none uploaded to App Store Connect yet, none tried on a device by Claude, only built and unit tested):
- Build 5: ticked ingredients now mean "I have it" and are left off the shopping list; fixed the "Something went wrong" alert at launch (a reload cancelling the first request surfaced as an error because the cancellation was wrapped in `APIError.network`).
- Build 6: offline launch and browsing answer instantly from the local copy instead of waiting out a timeout.
- Build 7: tab bar moved into each tab root so opening a recipe is a smooth slide (the old shell removed it after the push began and resized everything); Home button on pushed screens.
- Build 9: tsp and tbsp are no longer converted to metric. Build 8: metric / US conversion including °F to °C, in the app (`UnitConversion.swift`) and on the website (`static/unitconv.js`, a port: keep them in step; both have the same cases in `IOS/RecipeManagerTests/ModelsTests.swift` and `tests/test_unitconv.js`). Web: As written / Metric / US control beside the scale buttons on the recipe, cook, shared recipe and shared cook pages, saved per device in `localStorage` (`unitSystem`), applied on top of scaling (`units.js` re-renders on the `unitsystemchange` event) and to method text. "oz" next to milk, cream, oil and similar becomes ml, otherwise grams; "1 lb (450 g)" style text uses the figure already written. Not converted: the shopping list, the print view, the notes field. `app.py`'s `asset_v` now also covers files in the static root so `units.js` busts caches.
- The server tests could not be run here (no `flask`, `bs4` on this machine), so the web templates were checked by reading and the Node tests only. Do the browser pass below before relying on it, and the image with the web changes is on Docker Hub as `d047ad2`, so pull `latest` on the server and hard refresh the browser (the service worker caches scripts).

iPhone 1.0.0 builds 3 and 4: fixed photos and recipes seeming to re-download on every open (photos were only in the purgeable `URLCache`, now persistent in `ImageStore`; the sync banner only shows when something is really being downloaded, not for the quick "Checking recipes…" pass) and the frequent "Can't reach the server" retry screen (launch now falls back to the saved account and goes offline, plus the one-shot GET retry). Recipe change detection (`updatedAt`, favourite, rating count) was reviewed and looks correct; if recipes still re-download, look at `OfflineStore.loadLibrary` silently resetting on a decode failure after a model change. Commit `f56089d`, builds bumped in `1892a09`. Not tried on a device yet, and build 4 is not yet uploaded to App Store Connect.

iPhone 1.0.0 build 2: ingredients listed against each step in cook mode; sideways-drag whitespace guarded with `VerticalScroll`; doubled ingredient tick boxes fixed. Cause: recipe-site imports kept a leading checkbox glyph (`▢`, sometimes `- ▢`) in the stored text, so the web page and the app each added their own box. Fixed at three levels: `scraper._clean` strips it on import, a startup migration in `migrate.py` cleans existing recipes (rewrites `recipe.ingredients`/`instructions`), and `_sections` in `api_v1.py` plus `RecipeSection` decoding in the app strip it defensively. Server image `a6ed450` is on Docker Hub; the version bump (`032bdd3`) is not yet uploaded to App Store Connect.

App Store preparation (iPhone only): renamed to Spoonmate with matching web and iOS icons, bundle IDs `com.justinrahme.Spoonmate`, `DELETE /api/v1/me`, privacy manifest and policy, listing copy and screenshots, HTML-entity cleaning in the app, MIT licence, public repo with Dependabot; before that the token API, the SwiftUI app, kitchen timers, themes, Safari share extension and offline use; Recipe pictures kept locally and repaired automatically; install hint fixed; "New recipe" offers Write / Link / Photo; cook mode upgrades; round-2 fixes to Plan, Shop, Admin and the recipe form; usability batch (import preview, photo import, Instagram, hearts, undo, offline, sharing); redesign to the current design system; earlier design-system, accessibility, motion, type and performance passes.

## Not verified in a real browser (do this before relying on it)

The work was built without a scriptable browser, so these were checked by tests and reading, not by clicking:
the metric / US control and converted text on the recipe, cook and shared pages,
dialogs (shopping picker, meal-plan share/move, keyboard shortcuts), the service worker and offline mode, the install hint on a real phone, drag and drop on the meal plan, the fetch-based favorite heart and cook-mode made-it/rating buttons, timer chips starting timers and swiping in cook mode, Instagram import against more than the one post tested, and OCR on real phone photos and handwriting (tested on generated screenshots only).

## Known gaps and ideas

- `project.yml` and the committed `.xcodeproj` have drifted (see the iPhone section); fold `DEVELOPMENT_TEAM` and the App Store category into `project.yml` so XcodeGen is safe to run again.
- Unit conversion on the web has not been seen in a browser (segmented controls on the four pages, the cook-mode row wrapping, method text on cook pages). tsp and tbsp are never converted to metric (spices and small amounts; only ml to tsp/tbsp going the other way). The conversion ignores cup-to-gram (volume stays volume), `dl`/`cl`, and gas marks; "oz" for an unusual liquid not in the word list will be read as weight.
- Tab bar slide and the new Home button have not been checked on a device; confirm the push animation feels right and that the Home button does not crowd the bottom action on the smallest phones.
- Not verified on a device: the sideways-drag fix was a blanket guard (the offending view was never identified), and the server tests could not be run in the session that made the glyph fix (missing dependencies on that machine); run `python3 -m unittest discover -s tests -t .` and re-import one recipe.
- Ingredient-to-step matching in cook mode (web and app) is word based (misses "the mixture", can over-match).
- "Overnight" is not turned into a timer.
- The users table on phones hides its Actions column behind a sideways scroll (the username links to the edit page).
- The `static/pages/*` guides still contain a few hard-coded names ("Juzzycooks") in titles.
- Collections have no equivalent of the recipe "undo delete".
- The iOS app has no UI tests; screens are checked by hand in the simulator. Account deletion was tested through the API tests and by hand on a phone, not by an automated UI run.
- The app does not scale servings or import PDFs (the web app does); keep store copy to what the app does.
- No automated browser tests; adding Playwright would cover most of the list above.

## Working notes for the next Claude session

- Don't guess at visuals: render pages and look. On macOS, Safari can be opened and captured with `screencapture`, but Safari blocks scripting unless the user enables "Allow JavaScript from Apple Events". If you screenshot from the user's Safari, open your own window, verify it is showing localhost, and close only that window by id. Screenshots can include desktop notifications; delete them.
- The sandbox server caches Jinja templates when not in debug mode: restart it after template edits.
- Scratch tooling (sandbox server, sample-data seeding, screenshot helper) lived outside the repo; `tests/smoke_routes.py` is the part worth keeping.
- iOS simulator work: the device-interaction tool only accepts taps from a subagent; take screenshots with `xcrun simctl io <udid> screenshot` and use `simctl status_bar ... override --time 9:41` first. Use the iPhone 18 Pro simulator.
- Impeccable design tooling lives in `.claude/` (untracked). `PRODUCT.md`, `DESIGN.md` and `.impeccable/` are tracked.
