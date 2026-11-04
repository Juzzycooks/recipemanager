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
- **UI tests** (`RecipeManagerUITests`, own scheme, not run by the `RecipeManager` scheme): sign in, open a recipe, cook it to the
  end, add its ingredients to the shopping list and tick one, and tick an item offline and see it sent when back online. They run
  against a real server, so use the script (needs Docker; it builds the image, starts and seeds a throwaway container on a free
  localhost port, boots the simulator, runs the tests and removes the container):

  ```bash
  IOS/scripts/run-ui-tests.sh                  # SIMULATOR_ID=<udid> for another simulator
  IOS/scripts/run-ui-tests.sh --screenshots    # retake docs/screenshots/ios and the App Store slides
  ```

  They build signed ad hoc (`CODE_SIGN_IDENTITY=-`, no team) because the app keeps its sign-in in the Keychain and the offline
  test relaunches it. The app has two DEBUG-only launch arguments for them (`App/UITestHooks.swift`): `-UITestReset` (start
  signed out with nothing saved) and `-UITestForceOffline` (treat the server as unreachable).
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
photos with the server's OCR, import a PDF (`.fileImporter`, sent to `POST /import/pdf`), add manually) · **Editor** (photo, reorderable ingredient and step rows, tags) ·
**Meal plan** (week view, plan a meal, swipe to remove with undo, add the week to the shopping list, fill empty dinners, add the
week to Calendar) ·
**Shopping list** (by aisle or by recipe, completed section, Clear completed with undo, add to Reminders, "Added by …" on a
household member's items) · **Profile** (counts, cook history, household, account, devices) → **Settings** (light/dark/system, five colour themes, keep-screen-awake, store links, and for admins: site settings, users, categories).

## Households

Profile → Household (`Features/Profile/HouseholdView.swift`, API.md "Households"): create one (a name), join with a code (typed any
case, with or without the dash or spaces; `Household.normaliseCode` tidies it), see the members, copy or share the invite code
("Join my Spoonmate household with code ABCD-EFGH"), make a new code (owner only) and leave (asks first). Errors are the server's
own messages. A server without `/household` (404) gets "This server doesn't support households yet".

The shopping list is shared. Items someone else added say "Added by sam" (`ShoppingItem.addedByLine`; nil for yours and on older
servers). While the list is on screen and the app is active it asks `GET /shopping/version` every 15 s (and once on coming back to
the app) and reloads in place when the version moved; the add field and its text are untouched. `ShoppingPoll` holds the rules
(tested): no asking while offline, while shopping changes wait in the `Outbox` or it is replaying, while an add / tick / delete /
clear is on its way, or while an Undo is on offer (a held-back Clear completed would come back). Offline ticks therefore stay as
they are until the Outbox has sent them, and the reload after that shows the merged list. A server without versions (404 or no
`version`) stops the polling. The reload goes through `GET /shopping`, so the saved copy and the shopping widget follow.

## Cook history

Finishing cook mode shows "Nice. You made it." with an optional photo (camera through `CameraPicker`, a `UIImagePickerController`
wrapper, or the library through `PhotosPicker`; both in `Components/PhotoCapture.swift`) and an optional note, then Save or Skip
(Skip still records the cook, as before). Photos are prepared like recipe photos (`ImagePrep`: 2000 px, JPEG 0.85). Online it is one
request (`CookLog.logMade`: multipart `note` + `photo`, JSON `{note}`, or no body). If the server refuses the picture (413 / 415 /
422) the cook is saved without it and the app says so.

Offline the cook is still recorded at once (made count, Outbox `madeIt(recipeID:note:photo:)`). The photo is written to
`Application Support/OutboxPhotos` (excluded from backup) and sent with the cook when the connection returns; if it can't be
kept, the app says the cook was saved without it so it can be added later from Cook history. A queued photo the server refuses is
retried without the photo; files are deleted once sent, rejected, or on sign-out. Queues saved by build 12 (no note or photo)
still decode.

The recipe page shows a strip of past cook photos (tap for full size, `CookPhotoViewer`), and "Made N times" opens that recipe's
history. Profile → Cook history (`Features/CookLog/CookLogView.swift`) is the whole timeline, newest first, paged with `before`
(`next_before`). Each entry shows the date, recipe (tap to open), photo and note; its menu edits the note, takes, chooses or
removes the photo, and deletes it (asks, then offers Undo; the DELETE waits until the offer ends). GETs are cached like every
other, so the timeline reads offline; changes need a connection.

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
recipe delete, collection delete (newer servers keep a deleted collection 30 days: Undo calls `POST /collections/{id}/restore`;
an older server's empty 204, or a restore that answers 404 / 405, offers no Undo or says it can't be restored) and cook-history
delete. The editor asks before a swipe-down throws away edits (`Components/SheetDismissAttempt.swift`).

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

More widgets, from the same snapshots:

- **This Week** (medium, large): today and the next six days (a rolling week, not Monday to Sunday), each with its dinner or
  else its first meal; today is highlighted. A day opens its recipe; an empty day opens the plan. Text only, no pictures.
- **Random Recipe** (small, medium): a recipe with its picture, a new one every 3 hours (five entries per timeline). Edit the
  widget to pick "All recipes" or one collection (`RecipeCollectionEntity`, whose query reads the App Group). The widget can't
  page the library, so after each `OfflineSync` the app writes `recipe-pool.json` (up to 100 recipes, and 60 per collection;
  the pool stays stable between syncs and is topped up at random) and ~300 px JPEG thumbnails in `Widgets/Thumbs`, made from the
  pictures the offline copy already downloaded; unused thumbnails are deleted. With offline pictures off, it shows letter tiles.

## Calendar and Reminders

- **Meal plan → Add week to Calendar:** asks for full Calendar access, lets you pick a calendar (the default for new events
  first, the last choice remembered), and adds one all-day event per meal ("Dinner: Lasagne", with `spoonmate://recipe/<id>` as
  the URL and in the notes). Spoonmate remembers which event belongs to which plan entry (UserDefaults `calendarExport.events`), so
  exporting again updates moved or renamed meals instead of duplicating, re-creates events you deleted, and removes events for
  meals no longer planned that week.
- **Shopping list → Add to Reminders:** puts the unticked items in a list called "Spoonmate shopping" (made in the default
  Reminders account if it's missing), skipping names the list already has open (ignoring case). Completed reminders are never
  touched. After the first export, ticking an item in the app also completes its reminder (it never asks for access to do so).
- The decisions are in `Core/CalendarExport.swift` (pure, tested in `CookAndExportTests.swift`); `Core/EventKitExporter.swift`
  only talks to EventKit. If access is refused, a short alert offers Open Settings.

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

Times in a step are found by `StepDurations` (a port of `findDurations` in `static/js/cook.js`; keep them in step, same cases
in `CookAndExportTests.swift` / `HouseholdAndCookLogTests.swift` and `tests/test_cook.js`): "20 min", decimals with a point or a
comma ("1.5 hours", "1,5 hours"), fractions ("1/2 hour", "½ hour", "1 1/2 hours"), "a minute" / "an hour" / "one hour", seconds
("45 secs"), joined times ("1 hour and 30 minutes", "1 hr, 15 min", "2 minutes 30 seconds"; only a smaller unit joins, across
nothing, "and", "," or "&"), nothing over 72 hours, ranges like "2–3 hours", "overnight" (8–12 hr, shown as "Overnight · about 8 hr") and "until doubled" (about
1–1½ hr, only when the step gives no time of its own). Times are kept in whole seconds (the web uses fractional minutes), so
"45 secs" starts a 45-second timer. Each time gets its own button. A range starts at the low end; when it
finishes, the timer pill (and, on iOS 26.1+, the alarm, via `ExtendKitchenTimerIntent`) offers "+N min" to reach the high end.

Each step lists the ingredients it mentions (`Core/StepIngredients.swift`, a port of cook.js). A step that names a part of the
recipe ("spread the filling", "roll out the dough") also lists every line of a section whose heading names it, unless the step is
in that section itself.

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
- **Changes made offline** (`Outbox`): favourites, ratings, "I made this" (with its note and photo) and shopping list adds, ticks and deletes are applied on the phone at
  once and queued (kept on disk, so they survive a relaunch). `Connectivity` notices when the server is back (it probes every 10 seconds while
  offline) and the queue is sent in order. Later changes to the same thing replace earlier ones. Everything else (editing a recipe, importing,
  the meal plan, collections) needs a connection and says "You're offline".
- **A damaged library file** doesn't wipe the copy: recipes are read one by one and any that don't decode are skipped (and
  downloaded again on the next sync). A file that can't be read at all is moved to `library-corrupt-<time>.json` (the newest two
  are kept) and the library starts again. Both are logged (`os.Logger`, category `OfflineStore`).
- **Signing out** erases the offline copy and the queue.
- Settings → Offline shows what is stored, when it last updated and how many changes are waiting.

## Permissions

No extra capabilities are needed beyond those in `project.yml` (App Group, keychain sharing). Usage strings (Info.plist, set in
`project.yml`): `NSLocalNetworkUsageDescription`, `NSAlarmKitUsageDescription`, `NSMicrophoneUsageDescription`,
`NSSpeechRecognitionUsageDescription`, `NSCameraUsageDescription` (cook photos), and for the Calendar and Reminders export `NSCalendarsFullAccessUsageDescription` and
`NSRemindersFullAccessUsageDescription` (EventKit needs only these strings, no entitlement).

## Publishing

See [`APP_STORE.md`](APP_STORE.md) for the App Store checklist, listing text and review notes. The app is iPhone-only, portrait, iOS 18+, and ships with a privacy manifest, [`PRIVACY.md`](AppStore/PRIVACY.md) as its privacy policy, and in-app account deletion.

## App icon and name

The name is **Spoonmate**. Its icon (a spoon whose bowl is a leaf) is drawn by `tools/generate_icons.py`, which writes both the iPhone icons
(light, dark and tinted) and the web icons (`static/icon-*.png`, maskable, apple-touch, favicon) so they always match. Change the drawing or
colours there and run `python3 tools/generate_icons.py`. The web name comes from `APP_NAME` in `app.py` (an admin can override it under
Admin → Site settings); the iPhone name is `CFBundleDisplayName` in `project.yml`.
