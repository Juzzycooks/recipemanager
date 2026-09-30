# Spoonmate for iPhone

SwiftUI app (iOS 18+, Swift 6, Observation) for the Spoonmate server in this repo. It talks to the JSON API
described in [`../API.md`](../API.md): no mock data, everything you see is your real library.

## Run it

```bash
brew install xcodegen          # once
cd IOS && xcodegen generate    # only needed after editing project.yml or adding files
open RecipeManager.xcodeproj
```

Pick a simulator and Run. On first launch tap **Get Started**, enter your server address (for example
`recipes.example.com`, `https` is assumed) and your normal username and password. The token is kept in the Keychain.

- **On a device:** set your Team under Signing & Capabilities (the project signs automatically).
- **Local server without HTTPS:** `http://localhost:5000` and `http://192.168.x.x:5000` work (local networking is allowed); anything
  public must be HTTPS.
- **Command-line builds** must be signed (ad-hoc is fine: `CODE_SIGN_IDENTITY=-`), otherwise the Keychain refuses the token and
  you'll be signed out on every launch.
- **Tests:** `xcodebuild test -scheme RecipeManager -destination 'platform=iOS Simulator,name=iPhone 18 Pro'`.
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
rating, Ingredients / Steps / Notes, add ingredients to the shopping list, plan, share, edit, duplicate, delete with undo) ·
**Cooking mode** (one step at a time, screen stays awake, timers detected from the step text, see below) ·
**Collections** (My / Shared, create, add and remove recipes, share link) · **Add** (import from a URL or pasted text, scan
photos with the server's OCR, add manually) · **Editor** (photo, reorderable ingredient and step rows, tags) ·
**Meal plan** (week view, plan a meal, add the week to the shopping list, fill empty dinners) ·
**Shopping list** (by aisle or by recipe, completed section) · **Profile** (counts, account, devices) → **Settings** (light/dark/system, five colour themes, keep-screen-awake, store links, and for admins: site settings, users, categories).

## Where the design and the server differ

The design reference had fields the server has no data for, so they are not faked:

- **Difficulty, Cuisine, Dietary**: no such data. Search filters use categories, ingredient, favorites and sort instead.
- **Trending searches**: replaced by your recent searches (kept on the device) and a category list.
- **Shared collections**: the server has no "shared with me"; the Shared tab lists collections you have given a public link.
- **Dietary Preferences, Units, Notifications, Import Settings, Data & Backup** in Profile: no backend behind them yet.
  Backup export/import is admin-only and still lives in the web app.

## Where to extend

- **Voice control in cooking mode:** `CookingView.advance(_:)` is the single place steps change.

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

## App icon and name

The name is **Spoonmate**. Its icon (a spoon whose bowl is a leaf) is drawn by `tools/generate_icons.py`, which writes both the iPhone icons
(light, dark and tinted) and the web icons (`static/icon-*.png`, maskable, apple-touch, favicon) so they always match. Change the drawing or
colours there and run `python3 tools/generate_icons.py`. The web name comes from `APP_NAME` in `app.py` (an admin can override it under
Admin → Site settings); the iPhone name is `CFBundleDisplayName` in `project.yml`.
