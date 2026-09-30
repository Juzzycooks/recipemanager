---
version: 1
slug: "app"
primary_target: "app"
related_targets: []
---

# Surface brief: Recipe Manager (whole app)

Scope and mode: every surface. Operate (app, cook mode, shopping, meal plan, admin), Read (recipe pages, guides), Persuade (public share pages). Build path: code-led (no image generation or browser on this machine; stated, not asked).

Audience/task: a home cook using it in the kitchen on a phone with messy hands, planning on desktop; strangers open shared links from social media and must want to cook the thing. Site name and logo are admin-set, never hard-coded.

Chosen direction (user-pinned, beats the roll): A + C hybrid. A "Well-Used Cookbook" world for reading and sharing; "Kitchen Instrument Panel" rigour for cook mode, shopping, meal plan.

## Direction contract

THESIS: A recipe is an index card you would hand to someone, not a row in a dashboard. Refuses the SaaS shell (flat 11-link bar, bordered grey cards, Inter everywhere, "No image" boxes) and the cream-paper-plus-Fraunces cookbook cliche.

OWN-WORLD: Index-card materials: white card stock ruled with pale blue lines, fountain-pen blue-black ink (#1b2431), a red-pen terracotta accent for everything the cook marks (#b83a12 fills, #c0440e text). Ground is cool-warm flour (#f3f2ee), not cream. Display and recipe text set in Alegreya (calligraphic serif) with italic notes; UI chrome in the system sans. Dark theme is a chalkboard menu (#14181d, chalk #e9e6df, ember accent), which is also cook mode's fixed world. Cards are ruled stock with a hairline edge and a paper shadow, not boxed panels. Recipes without photos get a category-tinted monogram card, never "No image".

STORY: The cook sees their library as a shelf of cards, opens one and sees a single primary action (Start cooking), reads a two-column spread (ingredients beside method), and shares a page that looks like a magazine cover with their own site name.

FIRST VIEWPORT: Masthead: site name in Alegreya at left, four grouped items (Recipes, Plan, Shop, Tools) and a "+" menu (New, Import) at right, theme toggle, account menu. Below, a recipe grid of ruled cards, photo-led with monogram fallback, above it one search field that searches titles and ingredients together. Recipe page: photo or monogram band, title in large Alegreya, meta as handwritten-style lines, primary "Start cooking" button, everything else in a "..." menu.

FORM: Cookbook/index-card world, position 1 on the user's shortlist (A, with C for doing surfaces); seed key: user-pinned (no roll).

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.

## Unresolved
- No browser here: layouts are verified by Jinja compile and detector only until the user looks at them.
