# Spoonmate — App Store Connect Listing Copy

Paste these into App Store Connect (iPhone only). Character limits are Apple's; counts are current as of 1 October 2026.
Screenshots: `Screenshots/iphone-6.9/` (required) and `iphone-6.5/`. Submission steps: [`../APP_STORE.md`](../APP_STORE.md).

---

## App name (max 30)

```
Spoonmate
```

> 9 characters. Names are first come, first served; if it is taken when you create the record, fallbacks: `Spoonmate Recipes`, `Spoonmate: Recipe Keeper`.

## Subtitle (max 30)

```
Recipes on your own server
```

> 26 characters. The subtitle is indexed for search at a higher weight than the keyword field, so it carries the highest-intent term ("recipes") and the differentiator (your own server). Alternative: `Self-hosted recipe manager` (26).

## Promotional text (max 170, editable any time without review)

1.0 (recommended, 161 characters):

Save recipes from any link, plan your week, build the shopping list and cook step by step with real kitchen timers. All on your own server, and it works offline.

Alternates:

- (147) Your recipe box, on your own server. Import from a link or photo, plan the week, shop from the plan and cook hands-free. Free, no ads, no tracking.
- (153) Import from a link, cook with ringing timers, plan your week and shop from the plan. Spoonmate keeps your recipes on a server you run, and works offline.

## Keywords (max 100 bytes, comma-separated, no spaces)

```
cookbook,meal plan,shopping list,cooking,kitchen,import,grocery,timer,self-hosted,offline,planner
```

> 97 bytes, 11 terms. No overlap with the name, subtitle or category (Food & Drink): `recipe` and `recipes` come from the subtitle, `spoonmate` from the name. No singular/plural pairs and no competitor names (guideline 2.3.7).

## Description (max 4000, not indexed for search; only the first three lines show before "more")

Spoonmate is a recipe app for people who like to keep their recipes to themselves. It connects straight to a Spoonmate server that you run at home (or anywhere you like), so your collection stays yours: no Spoonmate account, no ads, no tracking.

SAVE RECIPES FROM ANYWHERE
• Paste a link, or share a page from Safari with the Save to Spoonmate extension
• Scan a photo or screenshot of a recipe
• Check the ingredients and method before you save, or type a recipe in yourself

COOK WITHOUT FUSS
• Step-by-step cooking mode keeps the screen awake and shows one step at a time
• Start timers straight from the method ("simmer for 20 minutes")
• Timers ring like the Clock app, with a countdown on your Lock Screen and Dynamic Island

PLAN THE WEEK, SHOP ONCE
• Drop recipes into a weekly meal plan
• Turn the plan, or a single recipe, into a shopping list that merges duplicates
• Group the list by aisle or by recipe, and tick things off in the shop

WORKS OFFLINE
• Your whole library and its pictures are kept on your phone, so the recipe is there even when the signal isn't
• Favourites, ratings and shopping-list changes you make offline sync when you reconnect

YOURS TO ARRANGE
• Collections, favourites, star ratings and notes
• Search by name, ingredient or tag
• Light and dark mode and five colour themes
• Share a recipe as text, or a collection as a link
• Delete your account from the app whenever you like

REQUIRES A SPOONMATE SERVER
Spoonmate is free, open-source software that you run yourself, for example in Docker or on Unraid. Setup takes a few minutes: see github.com/Juzzycooks/recipemanager. Spoonmate includes no recipes of its own and needs an existing server to sign in to.

PRIVATE BY DESIGN
No analytics, no advertising, no third-party code. The app talks only to the server you configure.

## What's New (version 1.0)

```
First release. Save recipes from a link, photo or Safari, cook step by step with real kitchen timers, plan your week, shop from the plan, and take it all offline.
```

## Other fields

| Field | Value |
|:--|:--|
| **Primary category** | Food & Drink |
| **Secondary category** | Productivity |
| **Support URL** | https://github.com/Juzzycooks/recipemanager/issues |
| **Marketing URL** | https://github.com/Juzzycooks/recipemanager |
| **Privacy Policy URL** | https://github.com/Juzzycooks/recipemanager/blob/main/IOS/AppStore/PRIVACY.md |
| **Copyright** | 2026 Justin Rahme |
| **Price** | Free |
| **Availability** | All countries and regions (iPhone only; not offered on iPad, Mac or Vision Pro) |
| **Age rating** | Expect 4+. No mature content, no unrestricted web access; comments are visible only to people on the same private server. |
| **App Privacy** | Data Not Collected; no tracking. See `../APP_STORE.md` section 5. |
| **Export compliance** | Uses only standard HTTPS: `ITSAppUsesNonExemptEncryption = NO`, already set. |

## Screenshot plan (6.9" and 6.5", upload in this order)

| # | File | Caption | Subtitle |
|:--|:--|:--|:--|
| 1 | `01-home.png` | Your recipes, beautifully kept | Quick picks, collections and your week at a glance |
| 2 | `02-recipe.png` | Everything on one page | Ingredients, steps, ratings and notes in one clean view |
| 3 | `03-cooking.png` | Cook hands-free, step by step | Big text, a screen that stays awake and real kitchen timers |
| 4 | `04-collections.png` | Organise your way | Group recipes into collections for weeknights, slow cooking and more |
| 5 | `05-collection.png` | Every collection, one tap away | Browse a collection as a grid of photos |
| 6 | `06-search.png` | Find dinner fast | Search by name, ingredient or tag |
| 7 | `07-all-recipes.png` | Your whole library, offline too | Browse everything, even without a connection |
| 8 | `08-add.png` | Save recipes from anywhere | Import from a link, scan a photo or write your own |
| 9 | `09-settings.png` | Make it yours | Light, dark and colour themes |
| 10 | `10-sign-in.png` | Your server. Your recipes. | Free. No ads, no tracking. It talks only to the server you run |

Captions live in `Screenshots/generate.sh`; edit there and re-run it to change them. Apple shows the first three slides in search results, so 1 to 3 carry the pitch.

## App Review notes (App Store Connect → App Review Information)

> Spoonmate is a client for a self-hosted recipe server (open source: github.com/Juzzycooks/recipemanager). Users run their own server, so the sign-in screen asks for a server address. A demo server with sample data is running for review:
>
> Server: `<demo server URL>`
> Username: `<reviewer username>`   Password: `<reviewer password>`
>
> After signing in you can browse recipes, open one and tap Start Cooking (timers ring like the Clock app; alarms and notifications will ask permission), add a recipe from a link, build a meal plan and a shopping list, and try offline mode with airplane mode. Account deletion is under Profile → Account → Delete account. Please use the demo account for that, as it is reset daily.
>
> The app collects no data, has no analytics or advertising, and talks only to the server the user enters.

Fill in the three placeholders once your demo server is up. Use a non-admin account.
