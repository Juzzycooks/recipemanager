# Getting Spoonmate onto the App Store (iPhone only)

A working guide for the first submission. It covers what is already done in the repo, what only you can do (Apple account steps), ready-to-paste listing text, and what App Review is likely to ask about. **iPad is deliberately out of scope for 1.0**: the layouts have not been designed or tested for it.

## 0. Decide these first

| Decision | Recommendation | Why it matters |
|:--|:--|:--|
| **Bundle IDs** | `com.justinrahme.Spoonmate` (+ `.Share`, `.TimerWidget`) | **Permanent** once you create the App Store Connect record. Already renamed from the old `RecipeManager` ids. |
| **Seller name** | Your name (individual) or a company | Shown on the store page. A company needs a D-U-N-S number and extra verification time. |
| **A demo server for App Review** | Yes, required in practice (section 7) | Reviewers must be able to sign in and use the app. They will not set up a server. |
| **Support and privacy URLs** | GitHub pages now, your own site later | Both are required fields. `PRIVACY.md` is ready to publish. |

## 1. What is already done in the repo

| Area | State |
|:--|:--|
| Devices | iPhone only (`TARGETED_DEVICE_FAMILY = 1` for the app and both extensions); portrait only; not offered on Apple-silicon Macs or Vision Pro |
| Version | 1.0.0 (build 1), read from `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` by the app **and** both extensions (they must match or validation fails) |
| Icon | 1024 px light, dark and tinted, no transparency |
| Privacy manifest | `PrivacyInfo.xcprivacy`: no tracking, no data collected, UserDefaults reason `CA92.1` |
| Permission texts | Alarms, Local Network (app and share extension); Photos uses the system picker, so no permission is needed |
| Encryption | `ITSAppUsesNonExemptEncryption = NO` (only standard HTTPS), so no export-compliance paperwork |
| Account deletion | *Profile → Account → Delete account* (needs server v1.0+ with `DELETE /api/v1/me`). Required for apps with sign-in (guideline 5.1.1(v)) |
| Explaining the server | Sign-in screen says a server is needed and links to setup instructions (guidelines 2.3 and 4.2) |
| Launch screen | Cream/dark background colour, no white flash |
| Release build | Compiles for a real device (unsigned) with no warnings; 9 MB |
| Privacy policy | [`PRIVACY.md`](AppStore/PRIVACY.md) |

**Server requirement:** account deletion only works against a server running the image that includes `DELETE /api/v1/me`. Rebuild and push the image before you submit, and mention "server v1.0 or later" in the listing.

## 2. What only you can do

1. **Enrol in the Apple Developer Program** at developer.apple.com/programs (about US$99 / AU$149 a year). Approval can take from hours to a couple of days.
2. **Sign in to Xcode** (*Settings → Accounts*) and pick your **Team** for all three targets (*RecipeManager*, *RecipeManagerShare*, *RecipeManagerTimerWidget*) under *Signing & Capabilities*. Or uncomment `DEVELOPMENT_TEAM` in `IOS/project.yml` and run `xcodegen generate`.
3. **Keychain Sharing:** confirm the capability appears on the app and the share extension with the group `…com.justinrahme.Spoonmate.shared`. Automatic signing creates the App IDs and profiles.
4. **Create the app in App Store Connect** (appstoreconnect.apple.com → *Apps → +*): platform iOS, name **Spoonmate** (no exact match existed on the US store when I checked, but names are first-come), language English (Australia) or US, bundle ID from the list, and any SKU (e.g. `spoonmate-ios`).
5. **Host the two URLs** (support and privacy; section 6).
6. **Stand up the demo server** (section 7).

## 3. Build, upload, TestFlight

In Xcode:

1. Select the scheme **RecipeManager** and the destination **Any iOS Device (arm64)**.
2. *Product → Archive*. When the Organizer opens, choose **Distribute App → App Store Connect → Upload**.
3. After processing (10 to 30 minutes) the build appears in App Store Connect under *TestFlight*.

Command-line equivalent (needs a Team and a distribution profile):

```bash
cd IOS
xcodegen generate
xcodebuild archive -project RecipeManager.xcodeproj -scheme RecipeManager \
  -destination 'generic/platform=iOS' -archivePath build/Spoonmate.xcarchive
xcodebuild -exportArchive -archivePath build/Spoonmate.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export   # method: app-store-connect
```

**Before submitting, run TestFlight on real phones against a real HTTPS server.** These cannot be checked in the simulator and have not been tried on a device yet:

- [ ] The ringing kitchen timer and the Lock Screen / Dynamic Island countdown (AlarmKit, iOS 26.1+), and the notification fallback on iOS 18 to 26.0
- [ ] The Safari share extension appearing in the share sheet and seeing your sign-in (Keychain Sharing on a signed build)
- [ ] The local-network permission prompt when connecting to a server on your home Wi-Fi
- [ ] Sign in, offline mode (airplane mode), queued changes syncing, account deletion
- [ ] Small screen (iPhone SE class), large text (Dynamic Type) and VoiceOver on the main flows

Internal testers (up to 100, your own team) need no review. External testers need a short TestFlight review.

## 4. App Store Connect: listing

Paste-ready drafts. Adjust the tone freely.

| Field | Text |
|:--|:--|
| **Name** (30) | Spoonmate |
| **Subtitle** (30) | Recipes on your own server |
| **Category** | Food & Drink (secondary: Productivity) |
| **Promotional text** (170) | Import recipes from any link, plan your week, build the shopping list and cook step by step, all on your own server, and even offline. |
| **Keywords** (100) | `cookbook,meal plan,shopping list,cooking,kitchen,import,grocery,timer,self-hosted,offline,planner` |
| **Support URL** | https://github.com/Juzzycooks/recipemanager/issues |
| **Marketing URL** | https://github.com/Juzzycooks/recipemanager |
| **Privacy Policy URL** | https://github.com/Juzzycooks/recipemanager/blob/main/IOS/AppStore/PRIVACY.md |
| **Copyright** | 2026 Justin Rahme |
| **What's New** | First release. |
| **Age rating** | Answer the questionnaire honestly; expect 4+. (No mature content and no web browsing. Comments are visible only to people on the same private server.) |
| **Price** | Free |

**Description** (up to 4000 characters):

> Spoonmate is a recipe app for people who like to keep their recipes to themselves. It connects to a Spoonmate server that you run at home (or anywhere you like), so your collection stays yours.
>
> **Save recipes from anywhere**
> Paste a link, share a page from Safari, scan a photo or screenshot, or type it in yourself. Spoonmate reads the ingredients and method for you, and you can check them before saving.
>
> **Cook without fuss**
> Step-by-step cooking mode keeps the screen on, shows one step at a time, and starts timers straight from the method ("simmer for 20 minutes"). Timers ring like the Clock app, with a countdown on your Lock Screen.
>
> **Plan the week, shop once**
> Drop recipes into a weekly meal plan, then turn the plan (or a single recipe) into a shopping list that merges duplicates and groups items by aisle or by recipe.
>
> **Works offline**
> Your whole library and pictures are kept on your phone, so the recipe is there even when the signal isn't. Favourites, ratings and shopping-list changes you make offline sync when you're back online.
>
> **Yours to arrange**
> Collections, favourites, ratings, notes, search by ingredient, light and dark mode, and five colour themes.
>
> **Requires a Spoonmate server.** Spoonmate is free, open-source software that you run yourself (for example in Docker or on Unraid). Setup instructions: github.com/Juzzycooks/recipemanager

## 5. App Privacy answers

- **Data collection: "Data Not Collected."** The app sends what you type only to the server *you* configure, which the developer neither operates nor can access, and it has no analytics, advertising or third-party SDKs. This matches `PrivacyInfo.xcprivacy`.
- **Tracking:** No.
- Revisit these answers if you ever add analytics, crash reporting, or host accounts for other people. Running the review demo server does not change them, but the reviewer's activity on it is data you hold, so keep it disposable.

## 6. URLs you must host

A GitHub link works for the first submission, but a proper page looks better and can be shown in your website. Publish:

- **Privacy:** the text of [`PRIVACY.md`](AppStore/PRIVACY.md)
- **Support:** a page with setup instructions and a contact route (email or issues)

## 7. App Review: the demo server and review notes

Self-hosted apps are approved regularly, but **only when the reviewer can try them**. Apps that show a sign-in wall with no way in are rejected under guideline 2.1 (completeness).

**Demo server**
1. Run a second Spoonmate container on a public HTTPS address (Nginx Proxy Manager is fine), e.g. `https://demo.yourdomain`.
2. Seed it with the demo library: `python3 tools/seed_demo.py https://demo.yourdomain`.
3. In its *Admin → Users*, create a **non-admin** account for the reviewer.
4. Reset it on a schedule (wipe the volume and reseed nightly) so it stays tidy and holds no real data.
5. Keep it running for the whole review, and for every future update review.

**Review notes** (App Store Connect → *App Review Information*; paste, filling in the blanks):

> Spoonmate is a client for a self-hosted recipe server (open source: github.com/Juzzycooks/recipemanager). Users run their own server, so the sign-in screen asks for a server address. A demo server with sample data is running for review:
>
> Server: `https://demo.yourdomain`
> Username: `<reviewer username>`   Password: `<reviewer password>`
>
> Enter the server address, username and password on the sign-in screen (tap "Get Started" then sign in). The account is a normal user; all features can be tried: browsing, search, cooking mode with timers, meal plan, shopping list, collections, and Profile → Account → Delete account (please use the demo account only for this last step if you need it; it can be recreated).
>
> Notes: the app uses the local-network permission only to reach servers on a user's home network; photos are chosen through the system picker; the timer uses AlarmKit on iOS 26.1+ and notifications on earlier versions. The app collects no data and contains no third-party SDKs.

Also tick **"Sign-in required"** and enter the same credentials in the demo-account fields.

## 8. Screenshots

- **Size:** iPhone 6.9-inch: **1320 × 2868** (or 1290 × 2796). Provide this one set and App Store Connect scales it for smaller phones. Up to 10; use 5 to 8. iPad screenshots are not needed (iPhone only).
- **How:** the ones in `docs/screenshots/ios` are 1206 × 2622 (6.3-inch), good for the README but not the store. Retake on the **iPhone 18 Pro Max** simulator, seeded with `tools/seed_demo.py`, status bar set with `xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`.
- **Suggested order:** Home → Recipe → Cooking mode (with the timer chip) → Meal plan → Shopping list → Collections → Offline → Dark theme. Put the strongest first; only the first three show in search results.
- Captions over the screenshots are optional but help. No device-frame rules apply.

## 9. Likely questions from App Review, and answers

| Question | Answer |
|:--|:--|
| *"We can't sign in."* (2.1) | Demo server and account in the review notes (section 7). Make sure it is up. |
| *"App requires external server."* (4.2 / 2.3) | The listing and the sign-in screen both say so, and the source and setup guide are public. |
| *"Account deletion?"* (5.1.1(v)) | *Profile → Account → Delete account*. Mention it in the review notes. |
| *"Why local network?"* | Reaching a server on the user's home network. Text is in the permission prompt. |
| *"Why AlarmKit / Live Activities?"* | Kitchen timers that must ring while the phone is locked or silenced. |
| *"Data collection?"* | None; see section 5. |
| *"User-generated content?"* (1.2) | Comments exist only between people on the same private server that the user runs. There is no public feed. |

## 10. After approval

- **Releases:** bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION` on *every* upload) in `project.yml`, regenerate, archive, upload.
- **Server and app compatibility:** the app talks to `/api/v1`. Additive changes are safe; if you ever make a breaking change, add `/api/v2` rather than changing v1, because old app versions stay installed. The app shows a friendly message for endpoints an older server lacks.
- **Phased release** is available and recommended for updates.
- **iPad later:** turn `TARGETED_DEVICE_FAMILY` back to `"1,2"`, design and test the layouts (sidebar navigation would suit), add iPad orientations, and capture 13-inch iPad screenshots.

## 11. Pre-submission checklist

- [ ] Developer Program active; Team set on all three targets
- [ ] Bundle IDs final (section 0)
- [ ] Server image with `DELETE /api/v1/me` pushed and running
- [ ] Demo server up, non-admin reviewer account created, credentials in the review notes
- [ ] Privacy and support URLs live
- [ ] TestFlight run on at least two real devices (checklist in section 3)
- [ ] 6.9-inch screenshots uploaded; description, keywords, age rating, privacy answers filled in
- [ ] Accessibility checked (VoiceOver, large text). Don't claim Accessibility Nutrition Labels until this has been done.
- [ ] Build selected on the version page; export compliance and content-rights questions answered (no third-party content; encryption: standard HTTPS only)
- [ ] Submit for Review; release manually or automatically after approval

Finished 6.9" and 6.5" screenshot slides are in `IOS/AppStore/Screenshots/` (see its README).

Paste-ready listing copy with alternates and the screenshot captions: [`AppStore/AppStoreListing.md`](AppStore/AppStoreListing.md).
