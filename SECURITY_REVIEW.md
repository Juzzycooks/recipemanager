# Spoonmate — Security & Code Review
*Reviewed 2026-06-12 — **all security items below were fixed the same day**, along with the high-value features (profile/password reset, scaling, smart shopping list, nutrition estimates, thumbnails, backup/export, PWA share target).*

A solid foundation: CSRF protection is global, templates autoescape (no `|safe` anywhere), passwords use scrypt, open redirects are blocked, share tokens use `secrets`, the secret key persists correctly, and the Dockerfile is multi-stage. The items below are what's left.

---

## Security fixes

### High

**1. SSRF in URL import** — `scraper.py: scrape_recipe()`
Any logged-in user can make the server fetch arbitrary URLs (`/recipe/import`), including internal services and cloud metadata (`http://169.254.169.254`, `http://192.168.x.x`, `http://localhost:...`). The Mealie import has the same issue (admin-only, lower risk).
**Fix:** allow only `http/https`, resolve the hostname and reject private/loopback/link-local ranges before fetching. Also cap response size (e.g. read max 5 MB) and check `resp.status_code`.

**2. No request size limit** — `app.py`
`MAX_CONTENT_LENGTH` is unset, so image/PDF uploads are unbounded → trivial disk/memory DoS.
**Fix:** `app.config["MAX_CONTENT_LENGTH"] = 16 * 1024 * 1024`

**3. SVG upload = stored XSS** — `routes/admin.py: ALLOWED_EXTENSIONS`
Logo upload accepts `.svg`, which is served inline from `/admin/uploads/` and can contain `<script>`. Admin-only upload, but it's a persistent XSS vector for every visitor including public shared pages.
**Fix:** drop `svg` from the allowlist, or serve uploads with `Content-Disposition: attachment` / a sandboxing CSP. Also consider verifying image content (Pillow `verify()`), not just the extension.

**4. Deleting users/recipes corrupts data** — `models.py`, `routes/admin.py: delete_user`
No cascade rules anywhere:
- `delete_user` bulk-deletes recipes but leaves the user's comments, ratings, favorites, meal plans, shopping items and collections orphaned — and orphaned children of the deleted recipes. Templates that touch `comment.user` / `plan.recipe` will then crash.
- Deleting a single recipe with ratings/comments/meal plans will likely 500: SQLAlchemy tries to NULL the child FK, which is `nullable=False`.
**Fix:** add `cascade="all, delete-orphan"` to the Recipe/User relationships (ratings, comments, favorites, meal plans, cook logs, shopping items), and clean up all owned rows in `delete_user`.

### Medium

**5. Login rate limiter is per-worker and proxy-blind** — `routes/auth.py`
In-memory dict × 2 gunicorn workers = 10 attempts, not 5. Behind a reverse proxy (common on Unraid), `request.remote_addr` is the proxy IP, so one attacker's failures lock out everyone.
**Fix:** store attempts in the DB or use Flask-Limiter; add optional `ProxyFix` (env-gated, e.g. `TRUSTED_PROXY=1`) so `remote_addr` is real behind a proxy. Consider also rate-limiting per username.

**6. Users can't change their own password**
The welcome email says "Please change your password after logging in" — but no such page exists (only admins can, via user edit). Temporary passwords also persist indefinitely.
**Fix:** add a `/profile` route with change-password (and email update). Optionally force a change on first login.

**7. No timeouts on Mealie requests** — `mealie_import.py`
`mealie_auth`, `mealie_get_recipes`, `mealie_get_recipe_detail` have no `timeout=` → a slow/dead host hangs a gunicorn worker indefinitely (you only have 2).
**Fix:** add `timeout=15` to all three.

**8. Email recipient not validated** — `routes/recipes.py: email_recipe`
`to_email` goes straight into the `To:` header — validate the format (simple regex or `email.utils.parseaddr`) to rule out header injection, and you may want a per-user send rate limit since any account can email anyone.

**9. Container runs as root** — `Dockerfile`
**Fix:**
```dockerfile
RUN addgroup -S app && adduser -S app -G app && chown -R app:app /app
USER app
```
Plus in compose: `security_opt: [no-new-privileges:true]`. A `HEALTHCHECK` would also help Unraid show container state.

### Low

- **Cookies:** add env-configurable `SESSION_COOKIE_SECURE` (and `REMEMBER_COOKIE_SECURE`) for HTTPS deployments.
- **CSP:** `script-src 'unsafe-inline'` undermines the policy; move to nonces when convenient. `X-XSS-Protection` is deprecated — harmless, can drop.
- **Unpinned dependencies:** `requirements.txt` uses `>=`, so builds aren't reproducible and an upstream regression ships silently. Pin exact versions and bump deliberately (Dependabot/Renovate).
- **500s on bad input:** `int(request.form.get("score", 0))` in `rate()` and `int(...sort_order...)` in calculators raise on non-numeric input. Use `request.form.get(..., type=int)`.
- **`docker-compose.yml`:** `version: "3.8"` is obsolete; empty `SMTP_*` vars are fine but consider an `.env.example` instead.
- **Rate-limiter dict grows unbounded** (one key per IP, never pruned globally) — trivial, but prune on a timer or use Flask-Limiter (covered by #5).

---

## Feature recommendations

**Finish the Woolworths integration** — `woolworths.py` and all the `ww_*` columns on `ShoppingListItem` exist, but no route ever calls `search_product()`. The shopping list only links out to a Woolworths search. Wiring up a "Fetch prices" button (with cached results + estimated basket total + specials highlighting) is your highest-value, lowest-effort feature since it's 80% built.

High value:
- **User profile / password change + SMTP password reset** (doubles as security fix #6).
- **Recipe scaling** — multiply ingredient quantities by servings; you already parse quantities in `_clean_ingredient`.
- **Smarter shopping list** — merge duplicate ingredients across recipes, combine quantities, group by aisle/category.
- **Backup/export** — one-click JSON/zip export of all recipes + images, plus import. SQLite makes scheduled backup easy (`VACUUM INTO`).
- **PWA + share target** — a manifest makes it installable on phones; a share-target lets you share a TikTok/Instagram URL straight from the share sheet into the importer. Big win given the social-import focus.

Nice to have:
- Full-text search over instructions/notes via SQLite FTS5.
- Cook-mode ingredient checkboxes and per-step ingredient highlighting (timers/wake-lock already done).
- Meal plan: copy last week, iCal feed export, "leftovers" slot.
- Image thumbnails (Pillow) — uploads are currently served full-size; also strips EXIF.
- Duplicate detection on import (same source_url or fuzzy title match).
- API tokens for automation/mobile (Mealie-style REST endpoints).
- Reverse-proxy auth header support (e.g. Authelia/Authentik `Remote-User`) for Unraid SSO setups.
- Recipe nutrition estimates from parsed ingredients.
