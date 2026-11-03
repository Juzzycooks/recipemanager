# Spoonmate Privacy Policy

*Effective 4 November 2026*

**Short version:** Spoonmate does not collect, sell or share your personal data. The app has no analytics, no advertising, no tracking and no third-party code that talks to the internet. It only ever talks to the server you tell it to.

## How Spoonmate works

Spoonmate is a recipe app that connects to a **Spoonmate server that you (or someone you trust) run yourself**. When you sign in, the app sends your username, password and everything you do in the app (recipes, pictures you import, your meal plan, shopping list and so on) **to that server and nowhere else**.

The developer of Spoonmate does not run that server, cannot see what is on it, and receives no data from the app. Whoever operates your server is responsible for the data on it and for how it is protected and backed up.

## What the app stores on your iPhone

- **Your server address and sign-in token**, in the iOS Keychain. The "Save to Spoonmate" share extension reads the same item so it can save recipes for you. Signing out, or deleting your account, removes it.
- **An offline copy** of your recipes, collections, shopping list, recent meal plan and (optionally) pictures, so the app works without a connection. You can remove it any time in **Settings → Offline → Remove offline data**. Signing out also removes it. The offline library is excluded from iCloud backups.
- **Changes made while offline**, until they can be sent to your server.
- **Your preferences** (appearance, colour theme, recent searches, whether hands-free is on). Recent searches never leave your phone.

## Hands-free cook mode

If you turn on hands-free in cook mode, the app listens through the microphone for commands such as "next step" while cook mode is open. Speech is recognised **on your iPhone** using Apple's on-device speech recognition; the app requires on-device recognition and does not use hands-free on phones that can't do it, rather than sending your voice to Apple's servers. Audio and transcripts are not recorded, stored or sent to your server, the developer or anyone else. Listening stops when you leave cook mode, switch apps or turn hands-free off. Steps read aloud use the iPhone's built-in voices, also on the device.

## Permissions the app may ask for

| Permission | Why |
|:--|:--|
| Photos | Only the pictures you choose, through the system photo picker. The app cannot see the rest of your library. |
| Alarms and Notifications | Kitchen timers that ring when time is up. |
| Local network | To reach your server when it runs on your home network. |
| Microphone and Speech Recognition | Only if you turn on hands-free in cook mode, to hear commands like "next step". Recognised on the iPhone; nothing is recorded or sent. |

## Third parties

There are none inside the app. A few features involve other sites, always on your initiative:

- **Importing a recipe from a link:** *your server* (not the app) downloads that web page. The site you import from can see your server's request, as with any visit.
- **Shopping-list store links** open the store's search page in your browser.

## Children

Spoonmate is not directed at children and collects no personal information from anyone.

## Your choices

- **Delete your account:** *Profile → Account → Delete account* removes your account and what you added from the server.
- **Remove what is on your phone:** sign out, or use *Settings → Offline → Remove offline data*, or delete the app.
- Questions about data held on a particular server should go to the person who runs it.

## Changes

If this policy changes, the new version will be published at this address with a new effective date.

## Contact

Questions or concerns: open an issue at <https://github.com/Juzzycooks/recipemanager/issues>.
