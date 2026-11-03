# Spoonmate for iPhone

SwiftUI app (iOS 18+, Swift 6, Observation) for the Spoonmate server in this repo. It talks to the JSON API
described in [`../API.md`](../API.md): no mock data, everything you see is your real library.

## Run it

```bash
brew install xcodegen          # once
cd IOS && xcodegen generate    # after editing project.yml or adding/removing files
open RecipeManager.xcodeproj
```

`project.yml` is the source of truth and carries everything the project needs (Team `6HTZR75UR8` on the app and both
extensions, the App Store category, entitlements, the App Group, Info.plist keys, versions), so regenerating is safe.
Never hand-edit `project.pbxproj`. Keep `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` the same on all three shipping targets
(they come from the shared settings).

Pick a simulator and Run. On first launch tap **Get Started**, enter your server address (for example
`recipes.example.com`, `https` is assumed) and your normal username and password. The token is kept in the Keychain.

- **On a device:** set your Team under Signing & Capabilities (the project signs automatically).
- **Local server without HTTPS:** `http://localhost:5000` and `http://192.168.x.x:5000` work (local networking is allowed); anything
  public must be HTTPS.
- **Command-line builds** must be signed (ad-hoc is fine: `CODE_SIGN_IDENTITY=-`), otherwise the Keychain refuses the token and
  you'll be signed out on every launch.
- **Tests:** pick a simulator from `xcrun simctl list devices available`, boot it, then pass its id (or name *and* `OS=`;
  a bare `name=` resolves to the newest OS, which may not be installed):

  ```bash
  xcrun simctl bootstatus <udid> -b
  xcodebuild test -project RecipeManager.xcodeproj -scheme RecipeManager \
    -destination 'platform=iOS Simulator,id=<udid>' CODE_SIGNING_ALLOWED=NO
  # or: -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
  ```

  Device build check: `xcodebuild build -project RecipeManager.xcodeproj -scheme RecipeManager -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`.
  `RecipeManagerTests/Fixtures/*.json` are real server responses; regenerate them when `API.md` changes.

## Structure

```
RecipeManager/
├── App/          RecipeManagerApp, RootView (+ MainView), AppState (tab, Add sheet, toasts), AppRoute (every pushable screen)
├── Core/         APIClient (URLSession, bearer token, multipart), Session (sign-in, Keychain, 401 handling),
│                 Models (mirrors API.md), RecipeFeed (paginated lists), Keychain
├── Theme/        AppColors (semantic assets), AppSpacing (Spacing/Radius/Size), AppTypography (serif headings, nav bar)
├── Components/   AppTabBar, PrimaryButton, FilterChip, SearchBar, SectionHeader, RatingView, RecipeCard, CollectionCard,
│                 RecipeImage (the one place images load), IngredientRow, EmptyStateView, RecipePickerSheet, RecipeGrid
└── Features/     Onboarding, Home, Search, RecipeDetail, Cooking, Collections, AddRecipe, MealPlan, ShoppingList, Profile
```

Conventions: `@Observable` models own loading and mutations, views own presentation state only. Screens call
`session.run { client in … }`, which signs the user out if the token has been revoked. Colours come from
`Assets.xcassets` (light and dark variants exist; dark follows Profile → Appearance). Text uses Dynamic Type styles.
After any change that affects lists, call `session.recipesChanged()` and the visible screens reload.

## Screens

Onboarding → Sign in · **Home** (greeting, Quick Picks with All / Favorites / Recently Added, collections, shortcuts) ·
**Search** (live results, filters for category / ingredient / favorites / sort, recent searches) · **Recipe** (hero,
rating, Ingredients / Steps / Notes, ½× / 1× / 2× / 3× servings scale and metric / US units on the Ingredients tab, add
ingredients to the shopping list (scaled), plan, share, edit, duplicate, delete with undo) ·
**Cooking mode** (one step at a time, screen stays awake, the recipe page's scale carried in, timers detected from the step
text, hands-free voice; see below) ·
**Collections** (My / Shared, create, add and remove recipes, share link) · **Add** (import from a URL or pasted text, scan
photos with the server's OCR, add manually) · **Editor** (photo, reorderable ingredient and step rows, tags) ·
**Meal plan** (week view, plan a meal, swipe to remove with undo, add the week to the shopping list, fill empty dinners) ·
**Shopping list** (by aisle or by recipe, completed section, Clear completed with undo) · **Profile** (counts, account, devices) → **Settings** (light/dark/system, five colour themes, keep-screen-awake, store links, and for admins: site settings, users, categories).

## Where the design and the server differ

The design reference had fields the server has no data for, so they are not faked:

- **Difficulty, Cuisine, Dietary**: no such data. Search filters use categories, ingredient, favorites and sort instead.
- **Trending searches**: replaced by your recent searches (kept on the device) and a category list.
- **Shared collections**: the server has no "shared with me"; the Shared tab lists collections you have given a public link.
- **Dietary Preferences, Units, Notifications, Import Settings, Data & Backup** in Profile: no backend behind them yet.
  Backup export/import is admin-only and still lives in the web app.

## Undo

One shared offer for the whole app: `await app.offerUndo("Removed “X”", commit: { … }) { … }` (`App/UndoCenter.swift`), drawn as
`UndoPill` in `RootView`'s `StatusStack` so it never overlaps the offline pill. One at a time, 6 s (20 s and announced with
VoiceOver); a newer offer commits the older; leaving the app commits. Used by meal-plan remove, shopping Clear completed and
recipe delete. The editor asks before a swipe-down throws away edits (`Components/SheetDismissAttempt.swift`).

## Servings scale

`Core/IngredientScaling.swift` is a port of `scaleLine` in `static/units.js` (same cases in `ScalingAndUndoTests.swift` and
`tests/test_units.js`; keep them in step). It scales the leading amount, then units convert. Method text isn't scaled. The
choice isn't saved; cook mode gets it from the recipe page as `scale`.

## Siri and Shortcuts

`App/Intents/`: `RecipeEntity` (an `AppEntity` + `IndexedEntity`; queries read the offline library first, then the server) and
intents to add to the shopping list, ask what's for dinner, open or cook a recipe, start a timer and plan a recipe, with phrases
in `SpoonmateShortcuts`. Intents use `AppServices` (the one `Session`, `AppState`, `CookTimer` and `OfflineSync` per process),
so they queue offline and sign out on a 401 just like the screens. A phrase can carry one entity or enum only, so Siri asks
for the shopping item and the day; "Start a 10 minute timer" works for the lengths in `TimerLength`.

## Widgets

In the `TimerWidget` extension beside the timer Live Activity: **Tonight's Dinner** (small, medium, Lock Screen rectangle) and
**Shopping list** (medium, large, tick items with `TickShoppingItemIntent`). They read JSON snapshots in the App Group
`group.com.justinrahme.Spoonmate` (`Shared/WidgetSnapshot.swift`), written by `Core/WidgetBridge.swift` whenever
`OfflineStore.store` saves a `/shopping` or `/mealplan` response, and refresh from the server with the shared keychain
credentials. Ticks made while offline wait in the App Group until the app moves them into the `Outbox`. Links use
`spoonmate://recipe/<id>`, `cook/<id>`, `plan`, `shop` (`Shared/DeepLink.swift`).

Signing: the App Group must be enabled for both `com.justinrahme.Spoonmate` and `com.justinrahme.Spoonmate.TimerWidget` in
the developer account (automatic signing does it with Team `6HTZR75UR8`). Unsigned builds (`CODE_SIGNING_ALLOWED=NO`) get no
App Group container, so the widgets have no data there; test them on a device.

## Spotlight

`Core/SpotlightIndexer.swift` indexes recipes that changed after each `OfflineSync` (title, description, ingredients and
categories as keywords); tapping a result opens the recipe. `OfflineStore.clear()` (sign-out) wipes the index.

## Hands-free cook mode

The microphone button in cook mode's header turns on voice commands (off by default; the choice is kept in UserDefaults as
`handsFree`). The first time it asks for Speech Recognition and Microphone. Commands, parsed by `VoiceCommand.parse(_:)`
(pure and unit tested): "next" / "continue", "back" / "previous", "repeat" / "what's the step", "ingredients" / "what do I
need", "how much butter", "set a timer for ten minutes" (also "half an hour", "an hour and a half", digits), "start the
timer" (the step's own time) and "stop listening". "Read steps aloud" (in the strip, the help sheet and Settings) speaks each
new step.

- `HandsFreeController` is the state machine (off, listening, speaking, paused): it parses an utterance once the transcript
  has been still for 0.7 s (or is final), restarts the recognition task when it ends or fails (with back-off), stops
  listening while it speaks so it doesn't hear itself, pauses for calls and Siri, and stops when cook mode closes or the app
  leaves the foreground. The microphone, recogniser, voice, audio session and permissions sit behind small protocols;
  `HandsFreeLive.swift` has the real ones and `HandsFreeTests.swift` the fakes.
- Recognition is **on device only** (`requiresOnDeviceRecognition`). A phone or language without on-device recognition is told
  hands-free isn't available; audio is never sent to Apple's servers. Commands are English (the phone's English variant, else US).
- Audio session: `.playAndRecord` with `.mixWithOthers` (music keeps playing), `.defaultToSpeaker` (not the earpiece) and
  `.allowBluetoothA2DP` (no call-quality switch on AirPods); `.duckOthers` is added only while speaking and the session is
  cycled afterwards so the music comes back up. Haptics and system sounds are allowed while recording (iOS mutes them
  by default), so the command haptic and foreground timer notifications still sound. AlarmKit alarms are system alarms and
  ring regardless; if one (or a call, or Siri) interrupts the session, listening resumes when the interruption ends.
- The simulator can't exercise the microphone; check it on a phone (see HANDOFF.md).

## Kitchen timers

`CookTimer` (app-wide, so it keeps running when you leave cooking mode) hands the countdown to the system via `SystemTimer`:

- **iOS 26.1+:** an AlarmKit timer. It rings like the Clock app (even on silent or in a Focus) and shows a countdown on the Lock Screen and
  in the Dynamic Island. The countdown UI lives in the `TimerWidget` extension; `Shared/TimerMetadata.swift` is compiled into both targets.
  The first timer asks for Alarms permission.
- **Earlier iOS, or Alarms turned off:** a burst of local notifications (one every 10 seconds for a minute) with sound.

AlarmKit does not work in the simulator (authorization is always denied, so you get the notification path there). Test the ringing alarm and
Live Activity on a device.

## Themes

`AppTheme` defines the colour themes (light and dark values each). `ThemeStore` is observable and `AppColors.primary` / `secondary` read it,
so every view that uses them updates as soon as the theme changes. (`Color.accentColor` does not follow `.tint`, so don't use it for brand colour.)

## Share extension ("Save to Recipes")

Share a web page from Safari (or any app that shares a link) and choose **Recipes**. The extension reads the link, has your server parse it
(`POST /import/url`), shows the picture, title and counts so you can rename it, and saves it (`POST /import/save`). Selected recipe text, or a
caption with a link in it (Instagram, TikTok), works too. It has no account of its own: the app and the extension list the same keychain
access group in their entitlements, and the app stores the server address and token as one keychain item (`Shared/Credentials.swift`), so
signing in to the app is all that's needed. If you are not signed in, or are offline, the extension says so.

`ShareExtension/` holds its UI; it compiles `APIClient`, `Models` and the `Shared/` helpers from the app, nothing else.

## Offline use

All client-side; the server is unchanged.

- **Local copy of your library** (`OfflineStore`): every recipe in full, plus the collections, shopping list, categories and a few weeks of meal
  plan, and (optionally) the pictures. `OfflineSync` keeps it current: it lists the recipes, downloads only the ones that changed, and runs on
  sign-in, on returning to the app (at most every 10 minutes) and from Settings → Offline → Update now.
- **Browsing offline:** `APIClient.get` saves every response, and when the network is unreachable answers from that. The recipe list, search,
  filters, sorting and paging are rebuilt locally from the library, so they behave like the server's.
- **Changes made offline** (`Outbox`): favourites, ratings, "I made this" and shopping list adds, ticks and deletes are applied on the phone at
  once and queued (kept on disk, so they survive a relaunch). `Connectivity` notices when the server is back (it probes every 10 seconds while
  offline) and the queue is sent in order. Later changes to the same thing replace earlier ones. Everything else (editing a recipe, importing,
  the meal plan, collections) needs a connection and says "You're offline".
- **Signing out** erases the offline copy and the queue.
- Settings → Offline shows what is stored, when it last updated and how many changes are waiting.

## Publishing

See [`APP_STORE.md`](APP_STORE.md) for the App Store checklist, listing text and review notes. The app is iPhone-only, portrait, iOS 18+, and ships with a privacy manifest, [`PRIVACY.md`](AppStore/PRIVACY.md) as its privacy policy, and in-app account deletion.

## App icon and name

The name is **Spoonmate**. Its icon (a spoon whose bowl is a leaf) is drawn by `tools/generate_icons.py`, which writes both the iPhone icons
(light, dark and tinted) and the web icons (`static/icon-*.png`, maskable, apple-touch, favicon) so they always match. Change the drawing or
colours there and run `python3 tools/generate_icons.py`. The web name comes from `APP_NAME` in `app.py` (an admin can override it under
Admin → Site settings); the iPhone name is `CFBundleDisplayName` in `project.yml`.
