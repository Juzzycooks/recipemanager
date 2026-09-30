---
name: Recipe Manager
description: A warm, uncluttered kitchen workspace for a self-hosted recipe app, with a single terracotta accent.
colors:
  terracotta-ember: "#c0440e"
  terracotta-ember-deep: "#a33a0b"
  ember-fill-dark: "#c8501a"
  ember-wash: "#fdf0eb"
  ink: "#1a1a1a"
  ink-soft: "#595959"
  ink-faint: "#6b6b6b"
  flour: "#f7f7f5"
  countertop: "#ffffff"
  grout: "#e5e5e3"
  grout-light: "#f0f0ee"
  herb: "#1a7f37"
  herb-wash: "#dafbe1"
  chili: "#cf222e"
  chili-wash: "#ffebe9"
  ember-dark: "#e85a24"
  ember-dark-hover: "#f06b35"
  ember-dark-wash: "#2d1f1a"
  night-ink: "#e8e8e6"
  night-bg: "#121212"
  night-surface: "#1e1e1e"
  night-border: "#333333"
typography:
  headline:
    fontFamily: "Inter, -apple-system, system-ui, sans-serif"
    fontSize: "1.25rem"
    fontWeight: 700
    lineHeight: 1.6
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Inter, -apple-system, system-ui, sans-serif"
    fontSize: "0.95rem"
    fontWeight: 600
    lineHeight: 1.35
  body:
    fontFamily: "Inter, -apple-system, system-ui, sans-serif"
    fontSize: "0.9rem"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "Inter, -apple-system, system-ui, sans-serif"
    fontSize: "0.72rem"
    fontWeight: 600
    letterSpacing: "0.05em"
rounded:
  sm: "4px"
  md: "8px"
  lg: "12px"
  pill: "20px"
spacing:
  xs: "0.35rem"
  sm: "0.5rem"
  md: "1rem"
  lg: "1.5rem"
  xl: "2rem"
components:
  button-primary:
    backgroundColor: "{colors.terracotta-ember}"
    textColor: "#ffffff"
    rounded: "{rounded.md}"
    padding: "0.5rem 1rem"
  button-primary-hover:
    backgroundColor: "{colors.terracotta-ember-deep}"
  button-secondary:
    backgroundColor: "{colors.countertop}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "0.5rem 1rem"
  card:
    backgroundColor: "{colors.countertop}"
    textColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    padding: "1.5rem"
  input:
    backgroundColor: "{colors.countertop}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "0.55rem 0.75rem"
  chip:
    backgroundColor: "{colors.countertop}"
    textColor: "{colors.ink-soft}"
    rounded: "{rounded.pill}"
    padding: "0.3rem 0.7rem"
  chip-active:
    backgroundColor: "{colors.terracotta-ember}"
    textColor: "#ffffff"
  tag:
    backgroundColor: "{colors.ember-wash}"
    textColor: "{colors.terracotta-ember}"
    rounded: "{rounded.sm}"
    padding: "0.15rem 0.5rem"
---

# Design System: Recipe Manager

## Overview

**Creative North Star: "The Kitchen Counter"**

A clear, sturdy workspace where everything is within reach. Surfaces are calm off-white and white, text is near-black Inter, and a single terracotta accent marks what is active, actionable, or the cook's own. Nothing is decorative for its own sake: the recipe, its photo, and its ingredients are the content, and the interface stays out of the way while hands are busy.

Density is comfortable and app-like: a 980px centred column, generous card padding, small readable UI type (0.84–0.9rem) with bold headings. Cards sit on the page with a hairline border and an ambient shadow that lifts on hover. Light and dark themes are first-class and share the same structure; only the palette shifts.

**Key Characteristics:**
- One accent, used for links, active states, primary actions, and list markers.
- Single sans family (Inter); hierarchy comes from weight, size, and uppercase labels, not from font mixing.
- Soft-lifted cards: hairline border plus ambient shadow, deeper on hover.
- Rounded but not bubbly: 8px controls, 12px cards, pill chips.
- Theme via CSS custom properties on `data-theme`, mirrored in `static/pages/_theme.css` for embedded pages.

## Colors

A warm off-white workspace with near-black ink and one baked-clay accent; semantic green and red appear only for status.

### Primary
- **Ember Fill** (`--accent-solid`: #c0440e light, #c8501a dark, hover #a33a0b / #b84616): any surface that carries white text (primary button, active chip, active toggle). White on the bright dark-theme accent #e85a24 is only 3.5:1, so that colour is for text and lines on dark, never fills behind white.
- **Terracotta Ember** (#c0440e): links, primary buttons, active nav item, active chips, ingredient bullets, step numbers, focus border. Deep hover state **Terracotta Ember Deep** (#a33a0b). In dark theme it lifts to #e85a24 (hover #f06b35) for contrast.
- **Ember Wash** (#fdf0eb; dark #2d1f1a): tint behind tags, badges, and the active nav item.

### Neutral
- **Flour** (#f7f7f5): page background.
- **Countertop** (#ffffff): cards, nav, inputs, chips.
- **Ink** (#1a1a1a), **Ink Soft** (#595959), **Ink Faint** (#6b6b6b): primary, secondary, and tertiary text (meta, placeholders, hints). All pass 4.5:1 on Flour and Countertop. Dark tertiary is #949494.
- **Grout** (#e5e5e3) and **Grout Light** (#f0f0ee): borders and row dividers.
- **Night** set: background #121212, surface #1e1e1e, border #333333, text #e8e8e6.

### Status
- **Herb** (#1a7f37 on #dafbe1) success; **Chili** (#cf222e on #ffebe9) errors and destructive actions. Dark variants #3fb950 and #f85149.

### Named Rules
**The One Ember Rule.** Terracotta is the only chromatic accent. Green and red mean status, never decoration.

**The Wash, Not Fill Rule.** Secondary emphasis uses Ember Wash tints; solid Terracotta is reserved for the primary action and the selected state.

## Typography

**Display / Body / Label Font:** Inter (with -apple-system, system-ui, sans-serif), loaded from Google Fonts at weights 400–700.

**Character:** Neutral, legible, workmanlike. Tight tracking (-0.02em) on headings and brand; wide tracking on small uppercase labels.

### Hierarchy
Sizes come from the `--fs-*` tokens in `static/css/tokens.css`; templates never hard-code a rem value.
- **Display** (700, 2rem, -0.02em): public collection and recipe titles.
- **Headline / `--fs-lg`** (700, 1.25rem, -0.02em): page titles in `.page-header`.
- **Reading / `--fs-base`** (400, 1rem, 1.6): ingredients, instructions, form inputs (16px also stops iOS focus-zoom). Lists are capped at 68ch. Card titles are 600 at this size.
- **UI / `--fs-sm`** (500–600, 0.875rem): nav links, buttons, labels, secondary copy.
- **Meta / `--fs-xs`** (0.8125rem): hints, card meta, small buttons.
- **Label / `--fs-2xs`** (600, 0.75rem, uppercase 0.04–0.06em, short strings only): table headers, stat labels, tags. 12px is the floor for functional text.
- **Cook step / `--fs-md`** (1.125rem): large text in cook mode. Stat values are 1.75rem with tabular figures.

### Named Rules
**The One Family Rule.** Inter only. Add hierarchy with weight and case, not a second typeface. The single exception is the print sheet (`print.html`), which is set in Georgia at 12pt for paper.

**The Sentence-Case Data Rule.** User-generated strings (aisle names, categories, titles) are never uppercased; uppercase is for fixed, short labels.

## Layout

Content sits in a centred `.container` (max-width 980px, 2rem/1.5rem padding) under a 56px sticky top nav. Recipe grids use `repeat(auto-fill, minmax(260px, 1fr))` with a 1.25rem gap and collapse to one column below 700px. Spacing rhythm is rem-based: 0.35 / 0.5 / 1 / 1.25 / 1.5 / 2. Below 700px the nav links collapse into a hamburger dropdown and page headers stack.

## Elevation & Depth

Hybrid: surfaces are tonal (Flour page, Countertop cards) with a hairline Grout border, plus ambient shadows that carry structure.

### Shadow Vocabulary
- **Resting** (`box-shadow: 0 1px 2px rgba(0,0,0,0.04)`): cards at rest.
- **Standard** (`0 1px 3px rgba(0,0,0,0.06), 0 1px 2px rgba(0,0,0,0.04)`): raised elements.
- **Lifted** (`0 4px 12px rgba(0,0,0,0.08)`): recipe-card hover (with `translateY(-2px)`), mobile nav dropdown. Dark theme uses stronger alphas (0.2 / 0.3 / 0.4).
- **Focus ring** (`0 0 0 3px rgba(192,68,14,0.1)`) with an Ember border on inputs.

### Named Rules
**The Lift On Touch Rule.** Cards lift only in response to hover; at rest they stay quiet.

## Shapes

Rounded but disciplined: 4px on tags and badges, 6px on nav links and the theme toggle, 8px on buttons/inputs/flash messages, 12px on cards and hero images, 20px pill on filter chips. 1px borders in Grout define edges; list rows are separated by Grout Light hairlines. Recipe photos are edge-to-edge at the top of a card (180px, `object-fit: cover`).

## Components

### Buttons
- **Shape:** 8px radius, 0.5rem 1rem padding, 0.84rem / 600 text; `.btn-sm` is 0.3rem 0.6rem.
- **Primary:** Terracotta fill, white text; hover deepens to #a33a0b.
- **Secondary:** Countertop fill, Grout border; hover fills Grout Light.
- **Danger:** Countertop fill, Chili text and pink border; hover Chili Wash.
- Transitions: 0.15s on all properties.

### Chips
- **Style:** pill, Countertop fill, Grout border, Ink Soft text 0.78rem.
- **State:** hover turns border and text Terracotta; active is solid Terracotta with white text.

### Cards / Containers
- **Corner Style:** 12px. **Background:** Countertop. **Border:** 1px Grout. **Padding:** 1.5rem (recipe cards use 0 with a body padding of 1rem 1.25rem 1.25rem). **Shadow:** Resting, Lifted on hover for recipe cards.

### Inputs / Fields
- **Style:** full width, 1px Grout border, 8px radius, `--input-bg` fill (#fff / #2a2a2a), 0.9rem.
- **Focus:** Ember border and soft Ember ring. Labels are 0.84rem / 600 above the field; hints 0.78rem Ink Faint.

### Navigation
- 56px sticky bar, Countertop (dark #1a1a1a) with a bottom hairline. Links are 0.84rem / 500 Ink Soft with a 6px radius; hover fills Grout Light; active is Terracotta on Ember Wash. Brand is 1rem / 700 with -0.02em tracking; an admin logo (max 32px tall) and a 32px theme toggle sit at the right.

### Recipe Detail Lists (signature)
Ingredients get a 5px Terracotta dot bullet; instructions get a Terracotta bold step number in a flex row. Section sub-headings inside either list are small uppercase Terracotta labels that restart step numbering.

## Do's and Don'ts

### Do:
- **Do** use `var(--accent)` and the existing custom properties; never hard-code hex in templates.
- **Do** change tokens only in `static/css/tokens.css`; every template and `static/pages/_theme.css` loads it. Cook mode uses its own `--cook-*` set from the same file.
- **Do** design every surface for light and dark.
- **Do** keep touch targets comfortable for kitchen use on phones and tablets.
- **Do** keep public shared pages self-contained and attractive for a first-time visitor.

### Don't:
- **Don't** introduce a second accent colour or a second typeface.
- **Don't** hard-code the brand name; the site name and logo are admin-set.
- **Don't** use shadows at rest beyond the Resting/Standard tokens; reserve Lifted for hover and overlays.
- **Don't** put white text on `--accent` in dark theme; use `--accent-solid`.
