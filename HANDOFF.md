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
| `IOS/` | The SwiftUI iPhone app, its Safari share extension and widget extension (timer Live Activity, Tonight's Dinner, Shopping list). See the iPhone app section below and `IOS/README.md` |
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
# this Mac's system Python (3.9) can't install requirements.txt; run the server suite in the image instead
# (all pass at 0eb2561; the two Node-backed tests skip there because the image has no node, run them on the Mac)
docker build -t spoonmate-test . && docker run --rm --entrypoint sh spoonmate-test -c 'python -m unittest discover -s tests -t .'
node tests/test_unitconv.js
node tests/test_cook.js

# render every route with sample data and report server errors
python tests/smoke_routes.py

# build and push the multi-arch image (amd64 for Unraid, arm64 for Apple silicon / Pi)
# --pull --no-cache so apk upgrade really fetches the latest security fixes
docker buildx build --pull --no-cache --platform linux/amd64,linux/arm64 \
  -t juzzycooks/recipemanager:latest -t juzzycooks/recipemanager:$(git rev-parse --short HEAD) --push .
```

Tag each push with the commit hash so a rollback is one `docker pull`. After a deploy, users may need one hard refresh because the service worker caches scripts.

## The iPhone app (`IOS/`)

SwiftUI, iOS 18+, Swift 6, iPhone only and portrait only. The project is generated from `IOS/project.yml` with XcodeGen: edit `project.yml` (it now carries `DEVELOPMENT_TEAM` and the app category, so regenerating keeps them) and run `cd IOS && xcodegen generate`; never hand-edit `project.pbxproj`. Three targets share a keychain group: the app, `ShareExtension` (Safari "Save to Spoonmate") and `TimerWidget` (the timer Live Activity plus the Tonight's Dinner and Shopping list widgets; the app and `TimerWidget` also share the App Group `group.com.justinrahme.Spoonmate`). Bundle IDs are `com.justinrahme.Spoonmate`, `.Share` and `.TimerWidget`. Version and build come from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` and must match across all three.

- **API client:** bearer tokens against `/api/v1` (`API.md`). `APIClient` also cleans HTML entities out of every response (`HTMLEntities.swift`) because imported recipes sometimes carry `&quot;` and `&#39;`. `APIClient.swift` and `HTMLEntities.swift` are compiled into the share extension too, so new files they depend on must be added to its source list in `project.yml`.
- **Offline:** `OfflineStore` (response cache plus the whole library), `Outbox` (queued favourite, rating, made-it and shopping changes), `Connectivity`, `OfflineSync`. Pictures live in `ImageStore` (same file as `OfflineStore`, `Application Support/Offline/Images`, downloaded once, wiped by `OfflineStore.clear()`); `RecipeImage` and the sync's picture prefetch both go through it, not `URLCache`, which iOS can purge. At launch `Session.restore` opens with the cached `/me` account in offline mode if the server is unreachable; the "Can't reach the server / Try again" screen is only for installs that never synced. `APIClient` retries a GET once on transient network errors.
- **Timers:** AlarmKit on iOS 26.1+, a notification burst before that. AlarmKit cannot be exercised in the simulator.
- **Theme:** `ThemeStore` drives light/dark and five colour themes; Terracotta is the default. `Color.accentColor` does not follow it; use `AppColors`. `AppColors.primary` is for text, lines and icons, `AppColors.primaryFill` for fills behind white text (`OnPrimary` is white in both appearances). Alegreya is bundled in `Resources/Fonts` (static TTFs cut from the google/fonts variable fonts, listed in `UIAppFonts`) and used through `AppTypography`, all Dynamic Type relative. Cook mode never reads the theme: it uses the fixed `Cook*` colour sets via `CookColors` in `CookingView.swift`.
- **Cook mode ingredients:** each step shows a "For this step" card. `Core/StepIngredients.swift` is a Swift port of `matchIngredients` in `static/js/cook.js`; keep the two in step. Ingredient tick state on the recipe page is keyed by section and position, not by text, so duplicate lines are independent.
- **Tabs and navigation:** the system `TabView` (iOS 18 `Tab` API) in `MainView`: Recipes, Plan, Shop, Collections and Search (search role). Each tab is a `NavigationStack` whose path lives in `AppState.paths`; `app.selection` is a binding that pops the tab to its root when the current tab is tapped again. Push with `app.push(route, on: tab)`, open a recipe with `app.open(recipe:)`, switch with `app.tab = .plan`. Add is a + in the Recipes toolbar (`app.showingAdd`); Profile/Settings is a sheet from the Recipes avatar. There is no Home button and no custom tab bar; screens with one bottom action use `.bottomActionBar { }` (`Components/AppTabBar.swift`). Offline/sync/timer/toast/undo pills sit in a bottom safe-area inset (`StatusStack` in `RootView`) so they never cover content. **Undo** is one shared offer: `await app.offerUndo("Removed “X”", commit: { … }) { … }` (`App/UndoCenter.swift`), drawn as `UndoPill` in `StatusStack`. One at a time, 6 s (20 s with VoiceOver, which also announces it); a newer offer replaces the older, which commits; leaving the app commits. Used by meal-plan remove, shopping Clear completed (the deletes are held back until the offer commits) and recipe delete (restores from the server trash).
- **Offline speed and cancellations:** `APIClient.perform` fails immediately with an offline error while `Connectivity` already says offline (via `ResponseCaching.isOffline()`), so saved data answers with no timeout wait; only the connectivity probe (`ping`) bypasses it. It also rethrows `CancellationError` / `URLError.cancelled` unwrapped, so a superseded request never shows the "Something went wrong" alert. The first request after losing signal still waits out one timeout before the app flags itself offline.
- **Units (metric / US):** `Core/UnitConversion.swift` converts weights, volumes and oven temperatures for display only (Settings, Units; per-recipe toggle on the Ingredients tab; also Steps and cook mode). The shopping list and stored recipes are never converted, and "Add to shopping list" sends the lines unconverted (but scaled, see below). Ticking an ingredient on the recipe page now means "I already have it": the button adds only the unticked lines.
- **Scaling:** ½× / 1× / 2× / 3× beside the units control on the Ingredients tab, as on the web. `Core/IngredientScaling.swift` is a Swift port of `scaleLine` in `static/units.js` (keep in step; same cases in `ScalingAndUndoTests.swift` and `tests/test_units.js`). Scales the leading amount only, then units convert; method text is not scaled; cook mode gets the factor from the recipe page; "Add to shopping list" sends scaled lines (the web's picker sends what's shown). Not saved: it resets when the recipe closes. Known web quirks kept on purpose: "1-2" scales only the first number, "1,000 g" reads as 1.
- **Layout guard:** every vertical scroll page uses `VerticalScroll` (`SmallComponents.swift`: content pinned to the screen width, no sideways bounce) so a page can't be dragged aside to show blank space. Use it instead of a bare `ScrollView` for vertical pages.
- **Siri, widgets, Spotlight:** `App/Intents/` holds `RecipeEntity` (AppEntity + IndexedEntity; query reads the offline library first, then the server), the intents (add to shopping list, what's for dinner, open/cook a recipe, timers, plan a recipe) and `SpoonmateShortcuts` (phrases). Intents use `AppServices` (the one `Session`, `AppState`, `CookTimer`, `OfflineSync` per process, also what the scene injects), so they queue offline and sign out on 401 like the screens. The `TimerWidget` extension also holds **Tonight's Dinner** (small, medium, Lock Screen rectangle) and **Shopping list** (medium, large, tick via `TickShoppingItemIntent`). Data goes through the App Group `group.com.justinrahme.Spoonmate`: `OfflineStore.store` hands every `/shopping` and `/mealplan` response to `WidgetBridge`, which writes JSON snapshots (`Shared/WidgetSnapshot.swift`) and reloads the widget; the widget also refreshes from the server with the keychain credentials. Offline widget ticks are kept in the App Group and moved into the `Outbox` by `MainView.catchUp` (only once the session has a client, so ticks made before sign-in finishes aren't lost). Links are `spoonmate://recipe/<id>`, `cook/<id>`, `plan`, `shop` (`Shared/DeepLink.swift`, `AppState.handle`). Spotlight: `SpotlightIndexer` indexes changed recipes after each `OfflineSync` (keywords from ingredients and categories) and is wiped by `OfflineStore.clear()`. A phrase can carry one entity or enum only, so Siri asks for the shopping item and the day; "Start a 10 minute timer" works for the lengths in `TimerLength`.
- **Hands-free cook mode:** a microphone button in cook mode's header (off by default, remembered as `handsFree`). `Features/Cooking/VoiceCommand.swift` is the pure, tested grammar ("next", "back", "repeat", "ingredients", "how much butter", "set a timer for an hour and a half", "start the timer", "stop listening"); `HandsFreeController.swift` is the state machine (listening, speaking with recognition paused, paused for interruptions, restart with back-off when a recognition task ends); `HandsFreeLive.swift` holds the real `SFSpeechRecognizer` (on-device only: `requiresOnDeviceRecognition`; phones without it are told it isn't available), `AVSpeechSynthesizer` and audio session (`.playAndRecord` + `.mixWithOthers`/`.defaultToSpeaker`/`.allowBluetoothA2DP`, `.duckOthers` only while speaking). "Read steps aloud" speaks each new step from `advance(_:)`. Stops when cook mode closes or the app leaves the foreground. Privacy answer is still Data Not Collected: audio and transcripts never leave the phone. The simulator can't test the microphone.
- **Account deletion:** Profile, Account, Delete account calls `DELETE /api/v1/me` (needs the current server image; older servers answer 404 and the app says so).

```bash
cd IOS
xcrun simctl bootstatus 5B03F88E-6FEE-4427-9A6B-5A3B104C509E -b      # iPhone 17 Pro, iOS 26.5, on this Mac
xcodebuild test -project RecipeManager.xcodeproj -scheme RecipeManager \
  -destination 'platform=iOS Simulator,id=5B03F88E-6FEE-4427-9A6B-5A3B104C509E' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project RecipeManager.xcodeproj -scheme RecipeManager \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO        # device build check
```

On another Mac use an id from `xcrun simctl list devices available`, or `name=…,OS=…`: a bare `name=` resolves to the newest OS, which may not be installed. Running `xcodebuild test` several times back to back can fail with "Application failed preflight checks" (Busy): that is the simulator refusing the launch, not a test failure; wait a few seconds and rerun.

Unsigned builds cannot use the keychain, so for hands-on testing in the simulator build with signing on (`-allowProvisioningUpdates`) and reinstall; `xcodebuild test` reinstalls an unsigned copy.

## App Store status

Prepared, not yet submitted. Everything lives in `IOS/APP_STORE.md` (step-by-step guide) and `IOS/AppStore/`:

- `AppStoreListing.md`: paste-ready name, subtitle, promo text, keywords, description, What's New, review notes.
- `PRIVACY.md`: the privacy policy. Public URL: `https://github.com/Juzzycooks/recipemanager/blob/main/IOS/AppStore/PRIVACY.md`.
- `Screenshots/`: raw simulator captures in `raw/` (a real library, status bar 9:41) and `raw-demo/` (seeded demo server), framed slides in `iphone-6.9/` and `iphone-6.5/`, and `generate.sh` to rebuild them with the captions.
- Privacy manifest (`IOS/RecipeManager/Resources/PrivacyInfo.xcprivacy`; collects nothing, including for hands-free voice, which is recognised on the device), export compliance flag, account deletion and the sign-in explainer are done.
- Questionnaire answers already decided: age rating 4+ (all capability questions No, Age Category Not Applicable), third-party content No, Data Not Collected, no tracking.

**Still to do (needs a person):** enrol in the Apple Developer Program, set the Team for all three targets, create the App Store Connect record, stand up a public demo server with a non-admin reviewer account and fill the three placeholders in the review notes, run TestFlight on real phones (timers, share extension, local-network prompt, offline), then archive and upload. The app has been tried on a real iPhone and works.

## Repo and hosting

- GitHub `Juzzycooks/recipemanager`, now **public**; secret scanning and push protection are on. History was rewritten once (1 October 2026) to remove a personal email and an old username, so any clone older than that must be re-cloned.
- Docker Hub `juzzycooks/recipemanager`, last pushed from `main` at `87b1278` (multi-arch, `latest` and `87b1278`; 22 October 2026 CVE pass: Pillow 13.0.0, pypdf 6.21.2, Python 3.13.17 on Alpine 3.24.3, pip-audit clean). Not yet pulled and deployed on the Unraid box as far as Claude knows. Rebuild after any server change; iOS-only or docs-only changes do not need it.
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

iPhone 1.0.0 build 12 (not committed, not yet uploaded; `CURRENT_PROJECT_VERSION` is 12 on all targets via `project.yml`; before archiving, add the App Group `group.com.justinrahme.Spoonmate` to the app and TimerWidget in Signing & Capabilities). Build 11's unit tests now run: 91 pass on the iPhone 17 Pro / iOS 26.5 simulator, and the unsigned device build succeeds. What's in it:
- `project.yml` carries the Team, category, entitlements and App Group, so `xcodegen generate` is safe again.
- One undo system (`UndoCenter`, `UndoPill` in `StatusStack`) for meal-plan remove, Clear completed and recipe delete; swipe-down on the editor now opens the discard dialog.
- Servings scale ½× to 3× on the Ingredients tab, carried into cook mode and "Add to shopping list".
- `/units` is refetched on reconnect, not only at launch and sign-in.
- Siri and Shortcuts (App Intents), Tonight's Dinner and Shopping list widgets through the App Group, Spotlight indexing and `spoonmate://` links.
- Hands-free cook mode with optional "Read steps aloud" (see the iPhone section). New Info.plist strings `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`; `PRIVACY.md` (now effective 4 November 2026) has a hands-free section and permission rows, the listing has one truthful hands-free bullet, `APP_STORE.md` lists the new permissions. App Store privacy answer is still Data Not Collected.
- Fix: `WidgetBridge.drainPendingTicks` took (and deleted) offline widget ticks before checking the session had a client, so ticks could be lost at launch; it now checks first.

Needs a device check (none of this can be tried in the simulator):
- Widgets on the Home and Lock Screen with a signed build (the App Group must be on both app IDs), ticking the Shopping list widget online and offline, Siri phrases, a Spotlight search opening the recipe.
- Hands-free, with the phone on the bench about a metre away:
  1. First tap of the microphone: the Speech Recognition then Microphone prompts show the purpose strings. Deny one: the alert offers Open Settings and the toggle goes off. Allow it in Settings, come back, turn it on: it listens.
  2. "next", "back", "repeat", "what's the step", "ingredients", "what do I need", "how much butter" (on a recipe scaled 2×: the answer is the scaled line), "set a timer for ten minutes", "half an hour", "an hour and a half", "start the timer" on a step that names a time, "stop listening". Each fires once, with the caption and a haptic; "we'll do that next" in conversation does nothing.
  3. Music playing from another app: it keeps playing while listening, dips while a step is read, comes back up afterwards.
  4. A timer started by voice rings (AlarmKit, and the first-timer Alarms prompt appears while listening); after stopping it, the strip says Listening again and commands still work.
  5. Leave it listening for five minutes, partly silent and partly talking: it still answers (recognition tasks restart).
  6. A phone call and "Hey Siri" while listening: the strip says Paused, then listening resumes.
  7. AirPods: steps are read through them at normal quality, music isn't switched to call quality, and plugging or unplugging mid-session keeps it working.
  8. Lock the phone, switch apps, close cook mode: the orange microphone dot goes away at once. Reopen cook mode with hands-free left on: it listens again.
  9. "Read steps aloud" on: both the Next button and "next" read the new step, and it doesn't hear itself and skip ahead.
  10. VoiceOver on: the warning appears, both still work, captions are announced. Reduce Motion: the waveform is still. The screen stays awake throughout.
  11. A phone or language without on-device recognition says hands-free isn't available.

iPhone 1.0.0 build 11 (`c80c01f`, build bump `951686b`, both pushed; **uploaded to App Store Connect and on TestFlight** as of 4 November 2026; the unit tests were compiled but not run at the time because CoreSimulator was out of date; they have since been run and pass, see above): the app is brought into the web's cookbook design and the October critique (`.impeccable/critique/2026-10-19T23-46-35Z__ios-recipemanager.md`, 23/40) is fixed. Look: Alegreya bundled (`Resources/Fonts`, OFL), flour / card stock / chalkboard colours, Terracotta the default theme (the other four stay in Settings), `primaryFill` for fills behind white text, 4/6pt corners, ruled ingredient and step lists with terracotta dashes and italic numerals, italic monogram tiles. Cook mode: always chalkboard (`Cook*` colour sets), no photo, progress bar, Ingredients/Steps tabs, large step text, 64pt Previous/Next, a harder-to-trigger swipe, up to six named timers (AlarmKit and notification fallback carry a name; one Live Activity per timer), a "Marked as made" finish with optional rating, haptics, Reduce Motion. Navigation: system `TabView` (Recipes, Plan, Shop, Collections, Search), re-tap pops, + and Profile in the Recipes toolbar, no Home button. Safety: editor discard guard and swipe-back, no dead Save, labelled import progress and errors with Try again, meal-plan swipe remove with undo and offline queueing (new `Outbox` plan cases), inline multi-add on the shopping list, Clear completed undo, labelled sign-in fields, 44pt targets, plainer error titles. `PRODUCT.md` platform is now `adaptive`; `DESIGN.md` has an iPhone App section and `.impeccable/design.json` has iPhone components. Tested on a device from TestFlight (4 November 2026): tab re-tap, cook mode and several timers ringing, the shopping add field keeping focus, light/dark and large text. Known gaps at the time (the first two are fixed in build 12 above): the meal-plan and shopping undo toasts are drawn per screen and could overlap the offline pill; swipe-down on the editor is blocked while there are edits but doesn't open the discard dialog; `docs/screenshots/ios` and the App Store screenshots show the old design and need retaking.

Image hardening and a first-start fix (Docker Scout on Docker Hub had 8 high and 4 medium findings): pip is uninstalled from the runtime image (the app never runs it; its vendored urllib3 2.7.0, msgpack and setuptools were the Python findings, the app's own urllib3 is 2.8.0); `libexpat>=2.9.0` comes from Alpine edge until 3.24 ships it (remove that Dockerfile line then); zlib 1.3.2-r1 arrives with a fresh `apk upgrade`, so build with `--pull --no-cache` when patching CVEs, otherwise the cached upgrade layer keeps old packages. Left: two medium giflib findings with no fix anywhere (leptonica, needed by tesseract for photo import). Also fixed: on an empty data folder the two gunicorn workers raced to create tables ("table recipe_categories already exists", exit 3) and to write `.secret_key`; `app._startup_lock` (a flock on `DATA_DIR/.startup.lock`) now serialises first-run setup. Existing installs never hit it.

Web edit keeps the picture (`1e062ca`, image pushed): editing a recipe with an uploaded or imported picture used to wipe it, because the form only pre-fills the URL box for http links. An empty URL box now keeps the current picture; a "Remove picture" box clears it. The iPhone app was never affected (its PATCH omits `image_url`).

iPhone 1.0.0 builds 5 to 10 (commits `455bceb` and later; all pushed to GitHub (build 10 is `0eb2561`); none uploaded to App Store Connect yet; build 10 is built and unit tested but not tried on a device):
- Build 10: cups convert by ingredient: a cup of a known dry good becomes grams, a cup of a known liquid becomes ml, and a cup of anything unknown stays a cup (so "½ cup nuts" is 65 g, not 120 ml). Going to US, grams of flour, sugar, nuts and similar become cups; butter, cheese and chocolate stay ounces. The ingredient table moved out of the code into `static/unit-ingredients.json` (read by `units.py`): it is written into the recipe, cook and shared pages as `window.UNIT_INGREDIENTS` and served to the app at the public `GET /api/v1/units`, which the app fetches at launch and sign-in and caches in UserDefaults. Edit the JSON to add ingredients or fix weights; no app release needed. Image `0eb2561` is on Docker Hub.
- Build 9: tsp and tbsp are no longer converted to metric. Build 8: metric / US conversion including °F to °C, in the app (`UnitConversion.swift`) and on the website (`static/unitconv.js`, a port: keep the code in step; both run the same cases in `IOS/RecipeManagerTests/ModelsTests.swift` and `tests/test_unitconv.js`, which both load the shared JSON). Web: As written / Metric / US control beside the scale buttons on the recipe, cook, shared recipe and shared cook pages, saved per device in `localStorage` (`unitSystem`), applied on top of scaling (`units.js` re-renders on the `unitsystemchange` event) and to method text. "1 lb (450 g)" style text uses the figure already written. Not converted: the shopping list, the print view, the notes field. `app.py`'s `asset_v` now also covers files in the static root so `units.js` busts caches.
- Build 7: tab bar moved into each tab root so opening a recipe is a smooth slide (the old shell removed it after the push began and resized everything); Home button on pushed screens.
- Build 6: offline launch and browsing answer instantly from the local copy instead of waiting out a timeout.
- Build 5: ticked ingredients now mean "I have it" and are left off the shopping list; fixed the "Something went wrong" alert at launch (a reload cancelling the first request surfaced as an error because the cancellation was wrapped in `APIError.network`).
- To deploy build 10's server side: pull `latest` on the Unraid box, restart, hard refresh the browser once (the service worker caches scripts), then open the app while it can reach the server so it fetches the table. Until it has, cups stay as written and "oz milk" reads as a weight.

iPhone 1.0.0 builds 3 and 4: fixed photos and recipes seeming to re-download on every open (photos were only in the purgeable `URLCache`, now persistent in `ImageStore`; the sync banner only shows when something is really being downloaded, not for the quick "Checking recipes…" pass) and the frequent "Can't reach the server" retry screen (launch now falls back to the saved account and goes offline, plus the one-shot GET retry). Recipe change detection (`updatedAt`, favourite, rating count) was reviewed and looks correct; if recipes still re-download, look at `OfflineStore.loadLibrary` silently resetting on a decode failure after a model change. Commit `f56089d`, builds bumped in `1892a09`. Not tried on a device yet, and build 4 is not yet uploaded to App Store Connect.

iPhone 1.0.0 build 2: ingredients listed against each step in cook mode; sideways-drag whitespace guarded with `VerticalScroll`; doubled ingredient tick boxes fixed. Cause: recipe-site imports kept a leading checkbox glyph (`▢`, sometimes `- ▢`) in the stored text, so the web page and the app each added their own box. Fixed at three levels: `scraper._clean` strips it on import, a startup migration in `migrate.py` cleans existing recipes (rewrites `recipe.ingredients`/`instructions`), and `_sections` in `api_v1.py` plus `RecipeSection` decoding in the app strip it defensively. Server image `a6ed450` is on Docker Hub; the version bump (`032bdd3`) is not yet uploaded to App Store Connect.

App Store preparation (iPhone only): renamed to Spoonmate with matching web and iOS icons, bundle IDs `com.justinrahme.Spoonmate`, `DELETE /api/v1/me`, privacy manifest and policy, listing copy and screenshots, HTML-entity cleaning in the app, MIT licence, public repo with Dependabot; before that the token API, the SwiftUI app, kitchen timers, themes, Safari share extension and offline use; Recipe pictures kept locally and repaired automatically; install hint fixed; "New recipe" offers Write / Link / Photo; cook mode upgrades; round-2 fixes to Plan, Shop, Admin and the recipe form; usability batch (import preview, photo import, Instagram, hearts, undo, offline, sharing); redesign to the current design system; earlier design-system, accessibility, motion, type and performance passes.

## Not verified in a real browser (do this before relying on it)

The work was built without a scriptable browser, so these were checked by tests and reading, not by clicking:
the metric / US control and converted text on the recipe, cook and shared pages,
dialogs (shopping picker, meal-plan share/move, keyboard shortcuts), the service worker and offline mode, the install hint on a real phone, drag and drop on the meal plan, the fetch-based favorite heart and cook-mode made-it/rating buttons, timer chips starting timers and swiping in cook mode, Instagram import against more than the one post tested, and OCR on real phone photos and handwriting (tested on generated screenshots only).

## Known gaps and ideas

- Unit conversion has not been seen in a browser or on a phone (segmented controls on the four pages, the cook-mode row wrapping, method text on cook pages, cups turning into grams). Ideas: seed more of the table from a published dataset such as ExactCup (King Arthur weights cross-checked against USDA; check its licence first), (the app now also refetches `/units` on reconnect). tsp and tbsp are never converted to metric (spices and small amounts; only ml to tsp/tbsp going the other way). Cups are ingredient-aware (build 10): a cup of a known dry good becomes grams from a grams-per-cup table (King Arthur style weights), a cup of a known liquid becomes ml, and a cup of anything not in the lists stays a cup. Going to US, grams of cup-measured dry goods (flour, sugar, nuts, rice) become cups; butter, cheese and chocolate stay ounces. The table has one home, `static/unit-ingredients.json` (edit it there; `units.py` reads it): the server writes it into the recipe, cook and shared pages as `window.UNIT_INGREDIENTS` for `unitconv.js`, and the app fetches it from `GET /api/v1/units` at launch, sign-in and reconnect and keeps the last copy in UserDefaults (`unitIngredients`) for offline use. An app that has never reached a server with this endpoint has no table, so cups stay as written and "oz" is always read as weight. Still ignored: `dl`/`cl` and gas marks; "oz" for an unusual liquid not in the word list will be read as weight.
- Tab bar slide and the new Home button have not been checked on a device; confirm the push animation feels right and that the Home button does not crowd the bottom action on the smallest phones.
- Not verified on a device: the sideways-drag fix was a blanket guard (the offending view was never identified), and re-import one recipe to confirm the glyph fix end to end.
- Ingredient-to-step matching in cook mode (web and app) is word based (misses "the mixture", can over-match).
- "Overnight" is not turned into a timer.
- The users table on phones hides its Actions column behind a sideways scroll (the username links to the edit page).
- The `static/pages/*` guides still contain a few hard-coded names ("Juzzycooks") in titles.
- Collections have no equivalent of the recipe "undo delete".
- The iOS app has no UI tests; screens are checked by hand in the simulator. Account deletion was tested through the API tests and by hand on a phone, not by an automated UI run.
- The app does not import PDFs (the web app does); keep store copy to what the app does. Servings scaling is ½× to 3× only, like the web.
- Hands-free commands are English only, and an utterance must be the command on its own (after a short pause); ordinary talk ending in "next" is ignored by design.
- No automated browser tests; adding Playwright would cover most of the list above.

## Working notes for the next Claude session

- Don't guess at visuals: render pages and look. On macOS, Safari can be opened and captured with `screencapture`, but Safari blocks scripting unless the user enables "Allow JavaScript from Apple Events". If you screenshot from the user's Safari, open your own window, verify it is showing localhost, and close only that window by id. Screenshots can include desktop notifications; delete them.
- The sandbox server caches Jinja templates when not in debug mode: restart it after template edits.
- Scratch tooling (sandbox server, sample-data seeding, screenshot helper) lived outside the repo; `tests/smoke_routes.py` is the part worth keeping.
- iOS simulator work: if `xcodebuild` says "CoreSimulator is out of date", open Xcode once to install its components; until then build with `-destination 'generic/platform=iOS Simulator'` (tests compile but can't run). The device-interaction tool only accepts taps from a subagent; take screenshots with `xcrun simctl io <udid> screenshot` and use `simctl status_bar ... override --time 9:41` first. Use the iPhone 17 Pro (iOS 26.5) simulator by id.
- Impeccable design tooling lives in `.claude/` (untracked). `PRODUCT.md`, `DESIGN.md` and `.impeccable/` are tracked.
