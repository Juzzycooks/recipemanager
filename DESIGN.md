---
name: Recipe Manager
description: A well-used cookbook of index cards ruled in blue, marked in red pen; a chalkboard when the cook stands at the stove.
colors:
  accent: "#b83a12"
  accent-hover: "#9a300e"
  accent-subtle: "#fbebe3"
  accent-ember: "#f0784a"
  accent-ember-solid: "#c8501a"
  ink: "#1b2431"
  ink-secondary: "#4a5566"
  ink-tertiary: "#5a6577"
  flour: "#f3f2ee"
  card-stock: "#ffffff"
  hairline: "#d9d7cf"
  hairline-light: "#ebe9e2"
  rule-blue: "#cfdde8"
  margin-line: "#e9b8a6"
  success: "#1a7f37"
  error: "#b42318"
  chalkboard: "#14181d"
  chalkboard-card: "#1b2027"
  chalk: "#e9e6df"
  cook-bar: "#0f1216"
  cook-surface: "#262d36"
  cook-surface-raised: "#323b46"
  cook-text: "#f4f1ea"
  cook-muted: "#a6adb8"
  tint-1: "#f6e3d8"
  tint-2: "#e2ecd9"
  tint-3: "#f3e8c6"
  tint-4: "#dde6ee"
typography:
  display:
    fontFamily: "'Alegreya', Georgia, 'Times New Roman', serif"
    fontSize: "clamp(2rem, 5.5vw, 3.25rem)"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.015em"
  headline:
    fontFamily: "'Alegreya', Georgia, 'Times New Roman', serif"
    fontSize: "1.375rem"
    fontWeight: 700
    lineHeight: 1.2
  reading:
    fontFamily: "'Alegreya', Georgia, 'Times New Roman', serif"
    fontSize: "1.1875rem"
    fontWeight: 400
    lineHeight: 1.5
  title:
    fontFamily: "'Alegreya', Georgia, 'Times New Roman', serif"
    fontSize: "1.3rem"
    fontWeight: 700
    lineHeight: 1.2
  body:
    fontFamily: "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 600
    lineHeight: 1.4
  meta:
    fontFamily: "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"
    fontSize: "0.8125rem"
    fontWeight: 400
    lineHeight: 1.6
rounded:
  control: "4px"
  card: "6px"
  pill: "999px"
spacing:
  xs: "0.25rem"
  sm: "0.5rem"
  md: "1rem"
  lg: "1.5rem"
  xl: "2.25rem"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.card-stock}"
    rounded: "{rounded.control}"
    padding: "0.5rem 1rem"
    typography: "{typography.label}"
  button-primary-hover:
    backgroundColor: "{colors.accent-hover}"
  button-secondary:
    backgroundColor: "{colors.card-stock}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "0.5rem 1rem"
  card:
    backgroundColor: "{colors.card-stock}"
    rounded: "{rounded.card}"
    padding: "1.5rem"
  chip:
    backgroundColor: "{colors.card-stock}"
    textColor: "{colors.ink-secondary}"
    rounded: "{rounded.pill}"
    padding: "0.3rem 0.8rem"
  chip-active:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.card-stock}"
  input:
    backgroundColor: "{colors.card-stock}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "0.55rem 0.75rem"
  cook-next-button:
    backgroundColor: "{colors.accent-ember-solid}"
    textColor: "{colors.card-stock}"
    rounded: "{rounded.card}"
    height: "64px"
---

# Design System: Recipe Manager

## Overview

**Creative North Star: "The Well-Used Cookbook"**

A recipe is an index card you would hand to someone, not a row in a dashboard. The system is built from index-card materials: white card stock ruled with pale blue lines, blue-black fountain-pen ink, and a single red-pen terracotta for everything the cook marks. The ground is a cool-warm flour, not cream. Recipe text and titles are set in Alegreya, a calligraphic serif, with italic for notes and step numbers; interface chrome uses the system sans so controls stay quiet.

Reading and sharing surfaces (shelf, recipe page, public share pages) live in this paper world. Doing surfaces (cook mode, shopping, meal plan) borrow its rigour as a Kitchen Instrument Panel: big targets, tabular numerals, one action per screen. The dark theme is a chalkboard menu, and cook mode is always that chalkboard regardless of the theme toggle.

The site name and logo are admin-set and appear in the masthead in Alegreya; nothing is hard-coded.

**Key Characteristics:**
- Ruled stock, not boxed panels: pale blue rules divide lists; cards are white with a hairline edge and a paper shadow.
- One accent (red-pen terracotta), used for what the cook marks: links, active state, list ticks, step numbers, the primary button.
- Alegreya for everything that is read; system sans for everything that is pressed.
- Photo-led cards, with a category-tinted italic monogram when there is no photo.
- Motion is short and functional: 0.15s state changes, one ease-out curve, all of it honoring reduced motion.

## Colors

Cool ink on warm-white stock, one red pen, and a chalkboard for the dark side.

### Primary
- **Red-Pen Terracotta** (`accent`, #b83a12): links, active nav underline, list ticks, step numbers, tags, focus outline, and (in light theme) the fill of primary buttons and active chips. Hover deepens to **Deep Red Pen** (`accent-hover`, #9a300e). **Marginalia Wash** (`accent-subtle`, #fbebe3) is the selection, badge, and menu-hover background.
- **Ember** (`accent-ember`, #f0784a): the same accent in the chalkboard theme and in cook mode, for text and lines on dark ground. **Ember Fill** (`accent-ember-solid`, #c8501a) is the dark-theme and cook-mode fill behind white text.

### Neutral
- **Fountain-Pen Ink** (`ink`, #1b2431): primary text. **Ink Secondary** (#4a5566) and **Ink Tertiary** (#5a6577) for supporting text and meta.
- **Flour** (`flour`, #f3f2ee): page ground and masthead. **Card Stock** (`card-stock`, #ffffff): cards, inputs, menus, secondary buttons.
- **Ruled-Line Blue** (`rule-blue`, #cfdde8): list dividers, page-header underline, the double masthead rule. **Hairline** (#d9d7cf) and **Hairline Light** (#ebe9e2) are card edges and table rows. **Margin Line** (#e9b8a6) is the pink-red margin rule tone.
- **Chalkboard** (`chalkboard`, #14181d): dark-theme ground and cook-mode ground; **Chalkboard Card** (#1b2027) is dark-theme card stock; **Chalk** (#e9e6df) is dark-theme text. Cook mode uses a fixed set: bar #0f1216, surface #262d36, raised #323b46, text #f4f1ea, muted #a6adb8.
- **Status:** success #1a7f37, error #b42318 (dark theme lifts them to #3fb950 and #f85149), each with a tinted wash and border.

### Monogram tints
Four wash-and-ink pairs for photo-less recipes: **Terracotta** (#f6e3d8 / ink #9a300e), **Herb** (#e2ecd9 / #3d6a2a), **Butter** (#f3e8c6 / #7a5c0d), **Slate** (#dde6ee / #3a5670). Dark theme swaps to deep washes with lighter inks.

### Named Rules
**The Red-Pen Rule.** There is one accent. Terracotta marks what the cook touches or has marked; no second hue is added for emphasis. Tints are for monograms only.

**The Accent-Solid Rule.** `--accent` is for text, lines, and marks. `--accent-solid` is the only accent that may fill a surface carrying white text. In light theme they are the same value (#b83a12). In dark theme they split: text accent #f0784a, fill #c8501a, whose white text contrast is only 4.55:1. That is the floor; do not lighten the fill, and never put white text on the dark-theme text accent.

**The Wash Not Fill Rule.** Quiet emphasis uses a wash (`accent-subtle`, hairline-light, a tint) rather than a solid fill. Solid accent fills are reserved for the primary action, the active chip, and the active segment.

**The Cook Mode Is Always Chalkboard Rule.** Cook mode reads the fixed `--cook-*` palette, never the theme tokens, so it is identical in a bright kitchen and a dark one.

## Typography

**Display / Reading Font:** Alegreya (self-hosted, weights 400/500/700, italic 500/700), fallback Georgia, serif.
**UI Font:** system-ui stack (system-ui, -apple-system, Segoe UI, Roboto, sans-serif).

**Character:** A calligraphic serif with handwritten italics for the cookbook voice, over a neutral system sans that never competes with it.

### Hierarchy
- **Display** (700, `--fs-display` clamp(2rem, 5.5vw, 3.25rem), 1.05, -0.015em): recipe titles, collection covers, page titles.
- **Headline** (700, `--fs-lg` 1.375rem, 1.2): section headings on the recipe page, stat values, empty-state lines.
- **Title** (700, 1.3rem, 1.2): recipe card titles (1.1rem on mobile).
- **Reading** (400, `--fs-reading` 1.1875rem, 1.45 to 1.5, max 68ch): ingredient and instruction lists in Alegreya. Cook mode raises this to 1.375rem for ingredients and clamp(1.4rem, 1.1rem + 1.6vw, 1.9rem) for the current step.
- **Notes** (Alegreya italic 500/700): the lede under a title, list-section headings in terracotta, step numbers (1.6rem in the spread, 4.5rem in cook mode), monograms.
- **Body / UI** (system sans, `--fs-base` 1rem, 1.6): forms and prose. **Label** (600, `--fs-sm` 0.875rem): buttons, nav, menu items. **Meta** (`--fs-xs` 0.8125rem): meta lines, hints, tags. `--fs-2xs` (0.75rem) is the floor.
- Numerals in meta, timers, tables, and stats use `font-variant-numeric: tabular-nums`.

### Named Rules
**The Sentence-Case Data Rule.** User-supplied strings (titles, tags, ingredients, categories) are never uppercased or letter-spaced, and no kicker or eyebrow sits above a heading. Meta is a plain label and value pair.

**The Two-Voices Rule.** Alegreya is for what is read (titles, recipe text, notes); the sans is for what is pressed (buttons, nav, inputs, menus). Do not set buttons in Alegreya or recipe text in the sans.

## Layout

A single centered column, `max-width: 1100px`, with 2.25rem 1.5rem padding (1.5rem 1rem on mobile). The recipe page is a 1000px card that becomes a two-column spread at 900px and up: ingredients (0.8fr, sticky at top 84px) beside method (1.4fr), 3rem gap; below 900px it is a single column. The shelf is `repeat(auto-fill, minmax(250px, 1fr))` with 1.5rem gap, two columns at 860px and below, one at 480px and below. Public pages use a 1080px column and a 260px-minimum grid; the cover is up to 62vh with a double blue rule beneath. Cook mode is a 46rem column between a sticky header, tabs, and a 4px progress bar, with a fixed bottom control bar.

Spacing is rem-based and unscaled (0.25, 0.5, 0.75, 1, 1.5, 2.25). Section rhythm is ~1.9rem between recipe sections. Masthead is 64px tall (56px mobile), sticky, with a 3px double blue rule underneath. At 860px and below the nav collapses behind a hamburger and menus become inline lists. Breakpoints in use: 480, 560, 600, 699, 860, 899/900, 1000.

## Elevation & Depth

Paper, not glass: depth is a hairline edge plus a soft, low shadow, like a card resting on a table. A 1px top highlight-line component in the light shadows reads as the card's edge. Cards rise a few pixels on hover (pointer devices only). In dark theme shadows are plain black and deeper because the ground is dark.

### Shadow Vocabulary
- **Card rest** (`--shadow-sm`: `0 1px 0 rgba(27,36,49,0.05), 0 1px 3px rgba(27,36,49,0.05)`): cards, inputs' neighbors.
- **Raised** (`--shadow`: `0 1px 0 rgba(27,36,49,0.05), 0 2px 8px rgba(27,36,49,0.07)`): detail hero image.
- **Lifted** (`--shadow-md`: `0 1px 0 rgba(27,36,49,0.06), 0 8px 24px rgba(27,36,49,0.12)`): open menus, hovered cards, the mobile nav sheet.
- **Focus ring** (`--focus-ring`: `0 0 0 3px rgba(184,58,18,0.18)`): fields on focus, with the accent border. Keyboard focus elsewhere is a 2px accent outline at 2px offset (2px chalk outline in cook mode).

### Named Rules
**The Paper Shadow Rule.** Shadows are soft, low, and blurred with no offset x-axis. Hard offset shadows do not exist here.

## Shapes

Index-card corners: **4px** (`--radius`) on controls, inputs, badges, menu items; **6px** (`--radius-lg`) on cards, hero images, menus, and cook-mode buttons; **pill** (999px) on filter chips only. Masthead and section separators are rules, not boxes: 1px blue rules between list rows, a 3px double blue rule under the masthead and covers. The ingredient tick is a 0.55rem terracotta dash; notes use a round dot. Photos are 4:3 on cards, 16:9 (max 420px) on the recipe page, 21:9 on public pages.

## Components

### Buttons
- **Shape:** 4px corners, 600 weight sans, 0.5rem 1rem padding (sm: 0.3rem 0.65rem; lg: 0.65rem 1.25rem).
- **Primary:** accent-solid fill, white text. One per surface. **Hover:** deepens to accent-hover. **Active:** scales to 0.98.
- **Secondary:** card-stock fill, ink text, hairline border; hover fills hairline-light. **Danger:** card-stock with error text and error border; hover fills the error wash.
- **Disabled:** 60% opacity. Coarse pointers get 44px minimum height.

### Chips
Pill, card-stock with hairline border and secondary ink text, 0.3rem 0.8rem. Hover turns border and text accent. Active fills accent-solid with white text. Tags are plain 600-weight terracotta text, no box or pill.

### Cards / Containers
White card stock, 6px corners, hairline border, card-rest shadow, 1.5rem padding. Recipe cards are photo-led (4:3) with a 0.9rem 1.15rem body, an Alegreya title clamped to two lines, and tabular meta beneath; hover lifts 3px on pointer devices. No-photo recipes get a monogram tile: the recipe's first letter in Alegreya bold italic (4.5rem), on one of four tints.

### Ruled lists
Ingredients and steps are unboxed lists on 1px rule-blue lines. Ingredients carry a terracotta dash; steps carry an italic terracotta numeral; section headings inside a list are italic terracotta.

### Inputs / Fields
Card-stock fill (input-bg #222932 on chalkboard), hairline border, 4px corners, 0.55rem 0.75rem padding. Focus swaps the border to accent and adds the focus ring. Labels are 600-weight, 0.8125rem, above the field. Placeholder uses ink-tertiary.

### Navigation (masthead)
Flour ground, double blue rule below. Site name in Alegreya 700 at 1.625rem at left; four grouped items (Recipes, Plan, Shop, Tools) as sans 600 items with details-based dropdown menus (white 6px panel, lifted shadow, terracotta wash on hover); the active item takes a 2px terracotta underline. At right, a filled "+" menu (New, Import), theme toggle (36px, 44px coarse), and account menu. Under 860px everything folds into a hamburger sheet.

### Cook mode (Instrument Panel)
Fixed chalkboard palette. Sticky header with a 48px Close, two 52px tabs (ingredients, steps) with an ember underline, a 4px ember progress bar, a 56px-minimum ingredient checklist with 30px checkboxes, a 4.5rem italic step numeral over 1.4 to 1.9rem Alegreya step text, and a fixed bottom bar with 64px Previous and Next buttons (Next in ember fill). Timers: presets and custom fields at 56 to 64px, remove buttons 56px. Segmented scale control at 48px.

### Public cover
Share pages carry the admin's site name and a cover: full-bleed photo under a bottom-up dark gradient with chalk text, or a tinted monogram band. Below it, a two-column recipe spread mirroring the in-app recipe page.

## Do's and Don'ts

### Do:
- **Do** change tokens only in `static/css/tokens.css`; every stylesheet and the embedded-page adapter (`static/pages/_theme.css`) reads them.
- **Do** give each surface exactly one primary action. On the recipe page it is Start cooking; Share, More, and everything else sit in menus or secondary buttons.
- **Do** use `--accent` for text and lines and `--accent-solid` for fills that carry white text.
- **Do** keep touch targets at 44px minimum on coarse pointers and 56px or larger in cook mode.
- **Do** give photo-less recipes a monogram tile in a category tint.
- **Do** honor `prefers-reduced-motion` on every animation and transition you add.
- **Do** divide lists with rule-blue lines; keep cards white.

- **Do** keep the four kitchen actions (Recipes, Plan, Shop, Add) in the thumb-reach tab bar on phones (<=860px); the top masthead carries the rest.

### Don't:
- **Don't** use `border-left` or `border-right` stripes as accents.
- **Don't** use emoji as icons; use inline SVG (stroke 2, round caps, 22px in cook mode).
- **Don't** show a "No image" box; use the monogram.
- **Don't** uppercase, letter-space, or set kickers or eyebrows above headings, and never transform user strings.
- **Don't** add a second accent hue or use the tints outside monograms.
- **Don't** theme cook mode; it always reads `--cook-*`.
- **Don't** hard-code hex values in component CSS or use offset-style shadows.
- **Don't** put a dashboard shell on the app: no flat many-link bar, no bordered grey boxes, no sans on every surface.
