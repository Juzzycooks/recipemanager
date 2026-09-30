# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users
Primary: a home cook (the owner) running the app on their own home server (Docker/Unraid). They cook from it in the kitchen (phone/tablet, hands busy, hands-free cook mode) and plan/organise on desktop. Secondary: public followers who open shared recipe/collection links (often from social media) without logging in, to read, cook, or print. Household members are additional logged-in users managed by an admin.

## Product Purpose
A self-hosted recipe manager for storing, organising, planning, and sharing recipes. Users import recipes from URLs, Mealie, social video, and PDFs; plan weekly meals; generate shopping lists; cook step by step; and publish themed collections. Success: the home cook reaches for it instead of bookmarks or paper, and shared links look good enough to post publicly.

## Positioning
Cooking tools are built in, not bolted on: embedded calculators (pizza dough, sourdough, admin-defined), unit converter, meal plan feeding a shopping list (including Woolworths integration), and a hands-free cook mode with timers, alongside public collection sharing. Ships as a single lightweight Docker image.

## Operating Context
Flask + Jinja templates, static HTML pages for calculators/guides in `static/pages/` (embedded via iframe, sharing `_theme.css`), PWA manifest and service worker. Runs on a home server (Unraid), SMTP optional for emailing recipes. Light and dark themes with system detection; public pages also support dark mode.

## Capabilities and Constraints
Recipes (import, edit, duplicate, export, print, categories, tags, favourites, ratings, comments, notes, cook history), collections with custom slugs and public share links, weekly meal plan with drag-and-drop and auto-generation, shopping lists, cook mode (wake lock, timers, audio/browser notifications), converter, calculators, admin (users, SMTP, site name/logo, Mealie import), CSRF, rate limiting, security headers (CSP). Stack is existing Flask/Jinja; no front-end framework.

## Brand Commitments
Site name and logo are admin-configurable, so the UI must not hard-code a brand identity. Current accent is a warm orange-red (`#c0440e`) in `static/pages/_theme.css`; existing incumbent, not a binding requirement.

## Evidence on Hand
Real recipes/pages exist as static pages in `static/pages/` (pasteis de nata, shish barak, sourdough guide, pizza dough calculator, meal plan). No testimonials, user counts, or benchmarks exist; do not fabricate them.

## Product Principles
1. Kitchen-first: cooking surfaces must work with messy hands, at arm's length, on a phone.
2. Public pages are the shop window: shared recipes and collections must look good to strangers with no login.
3. Self-hosted and configurable: never assume a fixed brand, data set, or external service.
4. Tools serve the cook: calculators, converter, and planning support the recipe, not compete with it.
5. Lightweight: no heavy dependencies; stay within the Flask/Jinja/plain CSS stack.

## Accessibility & Inclusion
No specific standard established; sensible baseline is readable contrast in both themes and usable touch targets for kitchen use.
