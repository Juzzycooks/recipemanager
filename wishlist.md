# Spoonmate Wishlist

A review of the iPhone app (`IOS/`, 1.0.0 build 11) and a list of what could come next, from small fixes to ideas with no limit on time, money or skill. Ordered from "do it this week" to "build it when we have a lab".

Written 4 November 2026 from the code, `HANDOFF.md`, `IOS/README.md` and the October critique.

---

## Where the app stands

Strong already: real offline use (full library, pictures, a queue of changes), AlarmKit timers with Live Activities, a Safari share extension, ingredient-aware metric/US conversion, a chalkboard cook mode with per-step ingredients, and the cookbook look carried over from the web. No mock data anywhere.

Missing or thin: no iPad or Watch, no UI tests, no PDF import. Build 11 is on TestFlight; servings scaling, Siri/Shortcuts, Spotlight, two widgets and hands-free voice are built on top of it but not yet in a numbered build or tried on a device.

---

## 1. Fixes (known problems, do first)

- [x] **Test build 11 from TestFlight on a phone.** Done 4 November 2026: tab re-tap, cook mode with several timers ringing, the shopping add field keeping focus, light/dark, the largest text size.
- [x] **Run build 11's unit tests.** They were compiled but never run (CoreSimulator went out of date).
  Done 4 November 2026: all pass on the iPhone 17 Pro / iOS 26.5 simulator (91 tests with this batch's additions), and the device build succeeds.
- [x] **Fix the `project.yml` drift.** Move `DEVELOPMENT_TEAM` and `LSApplicationCategoryType` into `project.yml` so `xcodegen generate` is safe again and new files stop needing four hand-made `project.pbxproj` entries.
  Done 4 November 2026 (unreleased, after build 11): `project.yml` carries the Team, category, entitlements and App Group; regenerate freely.
- [x] **One undo system.** Meal plan and shopping list each draw their own `UndoToast`, which can overlap the offline pill. Move undo into `AppState` and show it in `StatusStack`.
  Done 4 November 2026 (unreleased, after build 11): `UndoCenter` and `UndoPill` in `StatusStack`, used by meal-plan remove, Clear completed and recipe delete.
- [x] **Swipe-down on the editor** is blocked when there are edits but doesn't open the discard dialog. It should ask.
  Done 4 November 2026 (unreleased, after build 11): it now opens the discard dialog (`SheetDismissAttempt`).
- [x] **Undo for deleting a collection**, like recipes have. Done 4 November 2026: web flash and iPhone pill, restorable for 30 days.
- [x] **Refetch `/units` on reconnect**, not only at launch and sign-in, so a phone that first met an older server picks up the cup table.
  Done 4 November 2026 (unreleased, after build 11).
- [x] **"Overnight", "until doubled", "2–3 hours"** should become timers (ranges pick the low end and offer to extend). Done 4 November 2026 (web and iPhone, same test cases; also fractions, "an hour" and seconds on the iPhone).
- [x] **Better step-ingredient matching.** "Add the mixture" and "the dough" match nothing today; track what each step produces so later steps can refer back to it. Done 4 November 2026: "the dough" and "the filling" pull in a section with that heading, and a group word no heading claims ("the mixture") lists what the earlier steps of that section used, under "From earlier" (web and iPhone).
- [x] **Retake screenshots.** `docs/screenshots/ios` and the App Store slides are retaken from the seeded demo server by `IOS/scripts/run-ui-tests.sh --screenshots`. (`docs/screenshots/hero.png` is still the old composite.)
- [x] **UI tests.** At least sign in, open a recipe, cook it to the end, add to the shopping list, go offline and come back. Done 4 November 2026: `IOS/scripts/run-ui-tests.sh` against a seeded Docker server.
- [x] **Silent library reset.** `OfflineStore.loadLibrary` resets quietly on a decode failure after a model change, which looks like "everything re-downloads". Migrate or log it instead. Done 4 November 2026: recipes decode one by one, failures are logged, an unreadable file is kept aside.

## 2. Near-term features (the app is ready for these)

- [x] **Servings scaling** in the recipe and cook mode (the web has it; the app doesn't). Scale, then convert units, like the web.
  Done 4 November 2026 (unreleased, after build 11): ½× to 3× on the Ingredients tab, carried into cook mode and "Add to shopping list".
- [x] **PDF import** in the app, matching the web. Done 4 November 2026 (Add screen; the share sheet doesn't take PDFs yet).
- [x] **Siri and Shortcuts (App Intents):** "Add milk to my shopping list", "What's for dinner tonight?", "Start a 10 minute pasta timer", "Plan lasagne for Thursday".
  Done 4 November 2026 (unreleased, after build 11): all four, plus open or cook a recipe. Siri asks for the item and the day (a phrase can carry only one value). Not yet tried on a device.
- [x] **Spotlight:** index recipes so searching "nata" on the home screen opens the recipe.
  Done 4 November 2026 (unreleased, after build 11): indexed after each offline sync, wiped on sign-out. Not yet tried on a device.
- [x] **Widgets:** Tonight's dinner, This week's plan, Shopping list (interactive ticks), a random recipe from a chosen collection.
  Done 4 November 2026 (unreleased, after build 11): built Tonight's Dinner (small, medium, Lock Screen) and Shopping list (medium, large, interactive ticks, offline too). Not built: a whole-week plan widget and the random-recipe widget. Needs a signed device build to check.
- [ ] **Control Center and Action button:** a kitchen timer and "add to shopping list" control.
- [x] **Hands-free cook mode:** voice "next", "back", "repeat", "how much butter?", "set a timer". `CookingView.advance(_:)` is already the single hook for it.
  Done 4 November 2026 (unreleased, after build 11): on-device recognition only, also "ingredients", "start the timer" and "stop listening"; timers understand "half an hour" and "an hour and a half". Needs the device checklist in `HANDOFF.md`.
- [x] **Read steps aloud** with the system voice, paced so you can follow.
  Done 4 November 2026 (unreleased, after build 11): a "Read steps aloud" switch for hands-free mode (cook mode strip, help sheet, Settings); it uses the system voice at its normal pace, or VoiceOver's voice and rate when VoiceOver is on.
- [x] **Shopping list shared live** between household members, with who added what and pushes when someone ticks the last item. Done 4 November 2026: households with invite codes, "Added by", 15-second refresh. No push notifications (self-hosted, no APNs).
- [x] **Reminders and Calendar export:** push the week's plan into Calendar and the list into Reminders. Done 4 November 2026 (iPhone EventKit, re-export updates; web .ics download).
- [ ] **Pantry tracking:** mark what's at home; the list skips it and the meal plan prefers recipes that use it up.
- [ ] **Leftovers:** "made 8 serves, ate 4" puts the rest on tomorrow's lunch in the plan.
- [x] **Cook history with photos:** "I made this" takes a picture and a note, and the recipe shows a timeline of every time you cooked it. Done 4 November 2026 (web and iPhone, offline photo queueing).
- [ ] **Recipe diff:** see what changed since you imported it, and keep your tweaks separate from the original.
- [ ] **iPad layout** (recipe on the left, cook steps on the right, landscape on a stand).
- [ ] **Dietary, difficulty and cuisine** fields on the server so the search filters from the original design can come back with real data.
- [x] **Nutrition** per serve shown in the app (the server already has `nutrition.py`). Done 4 November 2026: a much better estimate (352 foods, real cup weights), the recipe site's own figures on import, calories per serving you can type in, per serving and whole recipe on web and iPhone.
- [ ] **Woolworths in the app:** send the shopping list straight to a Woolworths cart, as the web does.

## 3. Big swings (serious work, clearly worth it)

- [ ] **Apple Watch app:** current step on the wrist, timers that tap you, tick shopping items in the aisle, "next step" by double-tap gesture.
- [ ] **Vision Pro / spatial cook mode:** steps float above the bench, timers hover over each pan, the next ingredient glows in the pantry.
- [ ] **On-device AI import:** point the camera at a cookbook page, a handwritten card or a YouTube video and get a clean recipe with sections, times and a photo, without the server's OCR.
- [ ] **"What can I make?"** Photograph the open fridge; get ranked recipes from your own library, plus what one item you'd need to buy to unlock five more.
- [ ] **Grandma mode:** scan a stack of stained handwritten family recipe cards, keep the original scan beside the typed version, and print a bound family cookbook from a collection.
- [ ] **Smart meal planning:** fill the week from what you've rated highly, what's in season in Australia, what's on special at Woolworths this week, and what you haven't cooked in a while, while sharing ingredients across nights to cut waste.
- [ ] **Multi-recipe cook schedule:** pick a roast, two sides and a dessert for 6:30pm; the app works backwards and tells you when to start each step, with one combined timer timeline (a Sunday-lunch conductor).
- [ ] **Substitutions that understand cooking:** "no buttermilk" gives milk + lemon with amounts; "make it vegan" rewrites the recipe and flags where it will behave differently.
- [ ] **Federated Spoonmate:** self-hosted servers can follow each other, so friends' public collections show up in a "From friends" shelf without a central service.
- [ ] **Recipe forks:** cook someone's shared recipe, change it, and publish your fork with a link back, like code.
- [ ] **Smart-home hooks:** preheat the oven when you open cook mode, dim the lights for dinner, show the current step on the TV or a kitchen display.
- [ ] **CarPlay:** "What do I need for tonight?" read out on the drive home, with a stop at the shops added to the route.

## 4. Outlandish (no constraints at all)

- [ ] **The stove watches back.** A camera over the cooktop sees the onions go translucent and moves to the next step by itself. It notices the pan is smoking before you do and says so.
- [ ] **Taste prediction.** Before you cook, the app tells you how *you* will rate it, based on every rating you've ever given, and suggests the one change that would get it to five stars.
- [ ] **Flavour printer.** Tap a recipe and a countertop device sprays a sample of the finished dish's aroma so you can decide if it's what you feel like tonight.
- [ ] **Holographic chef.** A life-size projection of the original recipe's author (with their blessing) stands at the bench and shows the fold, the knead, the knife cut, at your pace.
- [ ] **Robot sous-chef.** Spoonmate drives a kitchen arm for the boring parts: dicing, stirring the risotto for 18 minutes, washing up while you plate.
- [ ] **Self-restocking pantry.** Smart shelves and jars weigh what's left; when flour drops below a cup the order is placed and the delivery lands before your Sunday bake.
- [ ] **Recipe time travel.** Ask for "Nonna's ragù as she made it in 1962" and the app reconstructs it from family recipes, regional cookbooks of the time and what was in the shops then.
- [ ] **Body-aware plans.** With permission, the plan reads sleep, training load and bloodwork, and quietly moves the iron-rich dinner to the night you need it, without ever turning dinner into a diet.
- [ ] **Universal translator for kitchens.** Cook from any language's recipe, any era's units ("a gill", "a teacup", "butter the size of an egg"), and any oven, from a wood-fired one to an air fryer, with timings adjusted for your actual appliance.
- [ ] **Dinner party AI host.** Invite guests; it collects allergies and likes, designs a menu nobody can complain about, writes the shopping list split by who's bringing what, and runs the timeline on the night.
- [ ] **Spoonmate Live.** Cook the same recipe at the same time with friends in other cities: shared step sync, picture-in-picture, a group timer, and a vote at the end on whose looks best.
- [ ] **Fork-to-farm.** Each ingredient on the list knows its farm, its season and its carbon cost; the app suggests the swap that halves your footprint without changing the dish.
- [ ] **Edible receipts.** The printed family cookbook comes with the first page as a sheet of rice paper you can put on a cake.
- [ ] **Smell-to-recipe.** Hold the phone near something delicious at a market and get the closest recipe in your library, or a new one to try.
- [ ] **Retire the screen.** Cook mode with no display at all: steps whispered through earbuds, timers felt as taps on the wrist, and the recipe projected onto the chopping board exactly where you need to cut.

---

## Suggested next three

1. Upload build 13 to TestFlight (add the App Group in Signing first) and work through the device checks: widgets, Calendar and Reminders, the timer "+N min", the camera, households with two accounts.
2. Control Center and Action button controls: a kitchen timer and "add to shopping list". Small, and builds on the App Intents already there.
3. Pantry tracking, then leftovers: both make the meal plan and shopping list smarter with data the app already has.
