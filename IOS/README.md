# Recipe Manager for iPhone

SwiftUI app (iOS 18+, Swift 6, Observation) for the Recipe Manager server in this repo. It talks to the JSON API
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
**Cooking mode** (one step at a time, screen stays awake, timer with minutes detected from the step text) ·
**Collections** (My / Shared, create, add and remove recipes, share link) · **Add** (import from a URL or pasted text, scan
photos with the server's OCR, add manually) · **Editor** (photo, reorderable ingredient and step rows, tags) ·
**Meal plan** (week view, plan a meal, add the week to the shopping list, fill empty dinners) ·
**Shopping list** (by aisle or by recipe, completed section) · **Profile** (counts, appearance, account, devices).

## Where the design and the server differ

The design reference had fields the server has no data for, so they are not faked:

- **Difficulty, Cuisine, Dietary**: no such data. Search filters use categories, ingredient, favorites and sort instead.
- **Trending searches**: replaced by your recent searches (kept on the device) and a category list.
- **Shared collections**: the server has no "shared with me"; the Shared tab lists collections you have given a public link.
- **Dietary Preferences, Units, Notifications, Import Settings, Data & Backup** in Profile: no backend behind them yet.
  Backup export/import is admin-only and still lives in the web app.

## Where to extend

- **Offline / caching:** add a store beneath `Session.run` (or swap `RecipeImage`'s `AsyncImage` for a cached loader). Views don't
  talk to `URLSession` directly.
- **Share extension** (save a link from Safari): a new target posting to `POST /import/url`, reusing `APIClient` and the Keychain
  (needs a shared keychain access group).
- **Voice control in cooking mode:** `CookingView.advance(_:)` is the single place steps change.
