import json
import os
import random
import re
import secrets
import time
from datetime import datetime, timezone
from flask import Blueprint, render_template, redirect, url_for, flash, request, make_response, jsonify, current_app
from flask_login import login_required, current_user
from models import db, User, Recipe, Category, Favorite, Rating, Comment, CookLog, Collection
from scraper import scrape_recipe, parse_pdf_recipe, _parse_caption_into_recipe
from recipe_text import parse_recipe_text
from ocr import images_to_text, ocr_available, OcrError
from security import FetchError, safe_get
from images import save_uploaded_image, delete_image
from nutrition import estimate_recipe

recipes_bp = Blueprint("recipes", __name__)


def _save_uploaded_image(file):
    """Verify, resize, strip EXIF and save an uploaded image (+thumbnail).
    Returns the filename, or empty string if missing/invalid."""
    data_dir = current_app.config.get("DATA_DIR", os.environ.get("DATA_DIR", "/app/data"))
    uploads_dir = os.path.join(data_dir, "uploads")
    return save_uploaded_image(file, uploads_dir, prefix="recipe")


def _first_ingredient_match(ingredients, term):
    """First ingredient line containing term (case-insensitive), skipping '# ' section headings."""
    needle = (term or "").strip().lower()
    if not needle:
        return ""
    for line in (ingredients or "").splitlines():
        line = line.strip()
        if not line or line.startswith("# "):
            continue
        if needle in line.lower():
            return line
    return ""


def _relative_cooked(when, now=None):
    """'today', 'yesterday', '3 days ago', '2 weeks ago' ... for a CookLog timestamp."""
    if when is None:
        return ""
    now = now or datetime.now(timezone.utc)
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    days = (now.date() - when.date()).days
    if days <= 0:
        return "today"
    if days == 1:
        return "yesterday"
    if days < 14:
        return f"{days} days ago"
    if days < 60:
        return f"{days // 7} weeks ago"
    if days < 730:
        return f"{max(days // 30, 2)} months ago"
    return f"{days // 365} years ago"


def _recently_cooked(user_id, limit=6):
    """Up to `limit` distinct recipes the user cooked, newest first, as (recipe, label) pairs."""
    seen, out = set(), []
    logs = (CookLog.query.filter_by(user_id=user_id)
            .order_by(CookLog.cooked_at.desc(), CookLog.id.desc()).all())
    for log in logs:
        if log.recipe_id in seen or log.recipe is None:
            continue
        seen.add(log.recipe_id)
        out.append((log.recipe, _relative_cooked(log.cooked_at)))
        if len(out) >= limit:
            break
    return out


# ── Trash (undo delete) ──

TRASH_MAX_AGE = 24 * 3600
_TRASH_TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{8,32}$")


def _data_dir():
    return current_app.config.get("DATA_DIR", os.environ.get("DATA_DIR", "/app/data"))


def _trash_dir():
    path = os.path.join(_data_dir(), "trash")
    os.makedirs(path, exist_ok=True)
    return path


def _purge_trash():
    """Remove trash entries older than 24h, and their image files if no recipe still uses them."""
    trash = _trash_dir()
    now = time.time()
    for name in os.listdir(trash):
        if not name.endswith(".json"):
            continue
        path = os.path.join(trash, name)
        try:
            with open(path, encoding="utf-8") as f:
                entry = json.load(f)
            age = now - float(entry.get("deleted_at", 0))
        except (OSError, ValueError):
            try:
                age = now - os.path.getmtime(path)
            except OSError:
                continue
            entry = {}
        if age < TRASH_MAX_AGE:
            continue
        image = (entry.get("recipe") or {}).get("image_url") or ""
        try:
            os.remove(path)
        except OSError:
            continue
        if image and not image.startswith(("http://", "https://", "//", "/")):
            if not Recipe.query.filter_by(image_url=image).first():
                delete_image(os.path.join(_data_dir(), "uploads"), image)


@recipes_bp.route("/")
@login_required
def index():
    search = request.args.get("q", "").strip()
    active_cats = []
    for c in request.args.getlist("cat", type=int):
        if c not in active_cats:
            active_cats.append(c)
    favorites_only = request.args.get("favorites") == "1"
    ingredient_search = request.args.get("ingredient", "").strip()
    sort = request.args.get("sort", "newest")
    view_mode = request.args.get("view", "grid")
    page = request.args.get("page", 1, type=int)
    per_page = 24
    coll_id = request.args.get("collection", type=int)
    
    query = Recipe.query
    if search:
        query = query.filter(db.or_(Recipe.title.ilike(f"%{search}%"), Recipe.ingredients.ilike(f"%{search}%")))
    if ingredient_search:
        query = query.filter(Recipe.ingredients.ilike(f"%{ingredient_search}%"))
    for cid in active_cats:
        query = query.filter(Recipe.categories.any(Category.id == cid))
    if coll_id:
        coll = Collection.query.get(coll_id)
        if coll:
            coll_recipe_ids = [r.id for r in coll.get_all_recipes()]
            query = query.filter(Recipe.id.in_(coll_recipe_ids))
    if favorites_only:
        fav_ids = [f.recipe_id for f in Favorite.query.filter_by(user_id=current_user.id).all()]
        query = query.filter(Recipe.id.in_(fav_ids))
    
    # Sorting
    if sort == "oldest":
        query = query.order_by(Recipe.created_at.asc())
    elif sort == "title_az":
        query = query.order_by(Recipe.title.asc())
    elif sort == "title_za":
        query = query.order_by(Recipe.title.desc())
    else:
        query = query.order_by(Recipe.created_at.desc())
    
    # Pagination
    pagination = query.paginate(page=page, per_page=per_page, error_out=False)
    recipes = pagination.items
    
    categories = Category.query.order_by(Category.name).all()
    collections = Collection.query.filter_by(user_id=current_user.id).order_by(Collection.name).all()
    
    # Get user's favorites for star display
    user_favs = set(f.recipe_id for f in Favorite.query.filter_by(user_id=current_user.id).all())

    # Why did each result match? Show the first ingredient line when the title doesn't contain the term.
    match_lines, match_terms = {}, {}
    for term, is_q in ((search, True), (ingredient_search, False)):
        if not term:
            continue
        for r in recipes:
            if r.id in match_lines or (is_q and term.lower() in (r.title or "").lower()):
                continue
            line = _first_ingredient_match(r.ingredients, term)
            if line:
                match_lines[r.id] = line
                match_terms[r.id] = term

    filtered = bool(search or active_cats or favorites_only or ingredient_search or coll_id)
    recently_cooked = []
    if page == 1 and not filtered:
        recently_cooked = _recently_cooked(current_user.id)
    total_recipes = Recipe.query.count() if not recipes and not filtered else pagination.total

    return render_template("recipes/index.html", recipes=recipes,
                           search=search, categories=categories,
                           active_cat=(active_cats[0] if active_cats else None),
                           active_cats=active_cats, match_lines=match_lines, match_terms=match_terms,
                           recently_cooked=recently_cooked, total_recipes=total_recipes,
                           filtered=filtered, user_favs=user_favs,
                           favorites_only=favorites_only,
                           ingredient_search=ingredient_search,
                           sort=sort, view_mode=view_mode,
                           pagination=pagination, page=page,
                           collections=collections, active_coll=coll_id)


@recipes_bp.route("/recipe/<int:recipe_id>")
@login_required
def view(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    is_favorite = Favorite.query.filter_by(user_id=current_user.id, recipe_id=recipe_id).first() is not None
    user_rating = Rating.query.filter_by(user_id=current_user.id, recipe_id=recipe_id).first()
    comments = Comment.query.filter_by(recipe_id=recipe_id).order_by(Comment.created_at.desc()).all()
    made_count = CookLog.query.filter_by(user_id=current_user.id, recipe_id=recipe_id).count()
    nutrition = estimate_recipe(recipe.ingredients, recipe.servings)
    return render_template("recipes/view.html", recipe=recipe, is_favorite=is_favorite,
                           user_rating=user_rating, comments=comments, made_count=made_count,
                           nutrition=nutrition)


def _save_recipe_categories(recipe, form):
    """Update recipe categories from form data."""
    recipe.categories.clear()
    cat_ids = request.form.getlist("categories")
    for cid in cat_ids:
        cat = db.session.get(Category, int(cid))
        if cat:
            recipe.categories.append(cat)


@recipes_bp.route("/recipe/add", methods=["GET", "POST"])
@login_required
def add():
    categories = Category.query.order_by(Category.name).all()
    if request.method == "POST":
        # Handle image: upload takes priority over URL
        image_url = request.form.get("image_url", "").strip()
        if "image_file" in request.files:
            uploaded = _save_uploaded_image(request.files["image_file"])
            if uploaded:
                image_url = uploaded
        
        recipe = Recipe(
            title=request.form.get("title", "").strip(),
            description=request.form.get("description", "").strip(),
            ingredients=request.form.get("ingredients", "").strip(),
            instructions=request.form.get("instructions", "").strip(),
            prep_time=request.form.get("prep_time", "").strip(),
            cook_time=request.form.get("cook_time", "").strip(),
            servings=request.form.get("servings", "").strip(),
            source_url=request.form.get("source_url", "").strip(),
            image_url=image_url,
            notes=request.form.get("notes", "").strip(),
            user_id=current_user.id,
        )
        db.session.add(recipe)
        db.session.flush()
        _save_recipe_categories(recipe, request.form)
        db.session.commit()
        flash("Recipe added.", "success")
        return redirect(url_for("recipes.view", recipe_id=recipe.id))
    return render_template("recipes/form.html", recipe=None, categories=categories)


@recipes_bp.route("/recipe/<int:recipe_id>/edit", methods=["GET", "POST"])
@login_required
def edit(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    if recipe.user_id != current_user.id and not current_user.is_admin:
        flash("That belongs to someone else, so you can't change it.", "error")
        return redirect(url_for("recipes.index"))
    categories = Category.query.order_by(Category.name).all()
    if request.method == "POST":
        recipe.title = request.form.get("title", "").strip()
        recipe.description = request.form.get("description", "").strip()
        recipe.ingredients = request.form.get("ingredients", "").strip()
        recipe.instructions = request.form.get("instructions", "").strip()
        recipe.prep_time = request.form.get("prep_time", "").strip()
        recipe.cook_time = request.form.get("cook_time", "").strip()
        recipe.servings = request.form.get("servings", "").strip()
        recipe.source_url = request.form.get("source_url", "").strip()
        recipe.notes = request.form.get("notes", "").strip()

        # Handle image: upload takes priority over URL
        if "image_file" in request.files:
            uploaded = _save_uploaded_image(request.files["image_file"])
            if uploaded:
                recipe.image_url = uploaded
            else:
                recipe.image_url = request.form.get("image_url", "").strip()
        else:
            recipe.image_url = request.form.get("image_url", "").strip()
        
        _save_recipe_categories(recipe, request.form)
        db.session.commit()
        flash("Recipe updated.", "success")
        return redirect(url_for("recipes.view", recipe_id=recipe.id))
    return render_template("recipes/form.html", recipe=recipe, categories=categories)


@recipes_bp.route("/recipe/<int:recipe_id>/delete", methods=["POST"])
@login_required
def delete(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    if recipe.user_id != current_user.id and not current_user.is_admin:
        flash("That belongs to someone else, so you can't change it.", "error")
        return redirect(url_for("recipes.index"))
    try:
        _purge_trash()
    except OSError:
        current_app.logger.warning("Trash purge failed", exc_info=True)
    token = secrets.token_urlsafe(12)
    entry = {
        "deleted_by": current_user.id,
        "deleted_at": time.time(),
        "recipe": {
            "title": recipe.title, "description": recipe.description,
            "ingredients": recipe.ingredients, "instructions": recipe.instructions,
            "notes": recipe.notes, "servings": recipe.servings,
            "prep_time": recipe.prep_time, "cook_time": recipe.cook_time,
            "source_url": recipe.source_url, "image_url": recipe.image_url,
            "user_id": recipe.user_id,
            "categories": [c.name for c in recipe.categories],
            "created_at": recipe.created_at.isoformat() if recipe.created_at else None,
        },
    }
    try:
        with open(os.path.join(_trash_dir(), f"{token}.json"), "w", encoding="utf-8") as f:
            json.dump(entry, f)
    except OSError:
        current_app.logger.error("Could not write trash entry", exc_info=True)
        flash("Couldn't set that recipe aside safely, so it wasn't deleted. Please try again.", "error")
        return redirect(url_for("recipes.view", recipe_id=recipe_id))
    title = recipe.title
    db.session.delete(recipe)
    db.session.commit()
    flash(f"Deleted \u201c{title}\u201d.|{token}", "undo")
    return redirect(url_for("recipes.index"))


@recipes_bp.route("/recipe/restore/<token>", methods=["POST"])
@login_required
def restore(token):
    if not _TRASH_TOKEN_RE.match(token or ""):
        flash("That undo link isn't valid. The recipe can't be restored from it.", "error")
        return redirect(url_for("recipes.index"))
    path = os.path.join(_trash_dir(), f"{token}.json")
    try:
        with open(path, encoding="utf-8") as f:
            entry = json.load(f)
        age = time.time() - float(entry.get("deleted_at", 0))
    except (OSError, ValueError):
        entry, age = None, 0
    if not entry or age >= TRASH_MAX_AGE:
        flash("Sorry, that recipe can't be restored. Undo is only available for 24 hours after deleting.", "error")
        return redirect(url_for("recipes.index"))
    if entry.get("deleted_by") != current_user.id and not current_user.is_admin:
        flash("Access denied. Only the person who deleted a recipe can restore it.", "error")
        return redirect(url_for("recipes.index"))
    data = entry.get("recipe") or {}
    owner_id = data.get("user_id")
    if not User.query.get(owner_id):
        owner_id = current_user.id
    recipe = Recipe(
        title=data.get("title") or "Untitled recipe", description=data.get("description") or "",
        ingredients=data.get("ingredients") or "", instructions=data.get("instructions") or "",
        notes=data.get("notes") or "", servings=data.get("servings") or "",
        prep_time=data.get("prep_time") or "", cook_time=data.get("cook_time") or "",
        source_url=data.get("source_url") or "", image_url=data.get("image_url") or "",
        user_id=owner_id,
    )
    if data.get("created_at"):
        try:
            recipe.created_at = datetime.fromisoformat(data["created_at"])
        except ValueError:
            pass
    with db.session.no_autoflush:
        for name in data.get("categories") or []:
            cat = Category.query.filter_by(name=name).first()
            if not cat:
                cat = Category(name=name)
                db.session.add(cat)
            recipe.categories.append(cat)
    db.session.add(recipe)
    db.session.commit()
    try:
        os.remove(path)
    except OSError:
        pass
    flash(f"Restored \u201c{recipe.title}\u201d.", "success")
    return redirect(url_for("recipes.view", recipe_id=recipe.id))


@recipes_bp.route("/recipe/<int:recipe_id>/duplicate", methods=["POST"])
@login_required
def duplicate(recipe_id):
    original = Recipe.query.get_or_404(recipe_id)
    clone = Recipe(
        title=f"{original.title} (Copy)",
        description=original.description,
        ingredients=original.ingredients,
        instructions=original.instructions,
        prep_time=original.prep_time,
        cook_time=original.cook_time,
        servings=original.servings,
        source_url=original.source_url,
        image_url=original.image_url,
        user_id=current_user.id,
    )
    db.session.add(clone)
    db.session.flush()
    for cat in original.categories:
        clone.categories.append(cat)
    db.session.commit()
    flash("Recipe duplicated.", "success")
    return redirect(url_for("recipes.edit", recipe_id=clone.id))


_URL_RE = re.compile(r"https?://\S+")


def _render_import_preview(data, source_url="", image_name="", kind="url", raw_text="", error=None, status=200):
    """Render the 'Check what we found' page for a parsed recipe (nothing is saved yet)."""
    fields = {k: (data.get(k) or "") for k in
              ("title", "description", "ingredients", "instructions", "notes", "servings", "prep_time", "cook_time")}
    ing = bool(fields["ingredients"].strip())
    met = bool(fields["instructions"].strip())
    fix = "Check the original text below and paste them in." if raw_text else "Add them in the boxes below."
    if not ing and not met:
        warning = "We couldn't find ingredients or a method. " + fix
    elif not ing:
        warning = "We found the method but no ingredients. " + fix
    elif not met:
        warning = "We found the ingredients but no method. " + fix
    else:
        warning = ""
    return render_template("recipes/import_preview.html", f=fields, source_url=source_url,
                           image_name=image_name or "", kind=kind, raw_text=raw_text,
                           warning=warning, error=error), status


def _localise_remote_image(url):
    """Download a remote image (SSRF-guarded, size-capped) and store it in uploads. '' on failure."""
    import io
    from werkzeug.datastructures import FileStorage
    from urllib.parse import urlparse
    parts = urlparse(url)
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
        # Many sites only serve images to their own pages: present ourselves as one of them
        "Referer": f"{parts.scheme}://{parts.netloc}/",
    }
    try:
        resp = safe_get(url, headers=headers, timeout=15)
        content = resp.content
        if not content:
            return ""
        return _save_uploaded_image(FileStorage(io.BytesIO(content), filename="remote.jpg"))
    except Exception:
        return ""


@recipes_bp.route("/recipe/<int:recipe_id>/localise-image", methods=["POST"])
@login_required
def localise_image(recipe_id):
    """Repair a recipe whose image is a remote link the browser can't load: keep our own copy.

    Called by the page script when an image fails to load. Returns the new local URL as JSON.
    """
    recipe = Recipe.query.get_or_404(recipe_id)
    if recipe.user_id != current_user.id and not current_user.is_admin:
        return jsonify(error="forbidden"), 403
    url = recipe.image_url or ""
    if not url.startswith(("http://", "https://")):
        public = f"/admin/uploads/{url}" if url and not url.startswith("/") else url
        return jsonify(url=public, thumb=public)
    local = _localise_remote_image(url)
    if not local:
        return jsonify(error="unavailable"), 502
    recipe.image_url = local
    db.session.commit()
    uploads = os.path.join(current_app.config.get("DATA_DIR", os.environ.get("DATA_DIR", "/app/data")), "uploads")
    thumb = f"thumb_{local}" if os.path.exists(os.path.join(uploads, f"thumb_{local}")) else local
    return jsonify(url=f"/admin/uploads/{local}", thumb=f"/admin/uploads/{thumb}")


@recipes_bp.route("/recipe/import", methods=["GET", "POST"])
@login_required
def import_url():
    if request.method == "POST":
        urls_text = request.form.get("urls", "").strip()
        single_url = request.form.get("url", "").strip()

        # Support both single URL field and bulk textarea
        urls = []
        if urls_text:
            urls = [u.strip() for u in urls_text.splitlines() if u.strip()]
        elif single_url:
            urls = [single_url]

        if not urls:
            flash("Paste at least one recipe link to import.", "error")
            return redirect(url_for("recipes.import_url"))

        if len(urls) == 1:
            url = urls[0]
            try:
                data = scrape_recipe(url)
            except FetchError as e:
                flash(f"Couldn't import that link: {e} Check the address, or paste the recipe text below.", "error")
                return redirect(url_for("recipes.import_url"))
            except Exception:
                flash("Couldn't read a recipe from that link. Check the address, or paste the recipe text below.", "error")
                return redirect(url_for("recipes.import_url"))
            if data.get("source_type") == "social" and not data.get("caption_found"):
                flash("Couldn't read the caption from that post: Instagram and TikTok often block this. "
                      "Paste the caption or upload a screenshot below instead.", "error")
                return redirect(url_for("recipes.import_url"))
            image_url = data.get("image_url", "") or ""
            if image_url.startswith("http"):
                # Keep our own copy so signed/expiring CDN links don't break the preview
                local = _localise_remote_image(image_url)
                image_url = local or ("" if data.get("source_type") == "social" else image_url)
            return _render_import_preview(data, source_url=url, image_name=image_url, kind="url")

        imported = 0
        failed = 0
        first_error = ""
        no_caption = []
        for url in urls:
            try:
                data = scrape_recipe(url)
                if data.get("source_type") == "social" and not data.get("caption_found"):
                    # Don't save an empty draft: the caller is told to paste the caption or a screenshot
                    no_caption.append(url)
                    continue
                image_url = data.get("image_url", "") or ""
                if image_url.startswith("http"):
                    # Keep our own copy: hotlink protection and expiring CDN links break remote images later
                    image_url = _localise_remote_image(image_url) or ("" if data.get("source_type") == "social" else image_url)
                recipe = Recipe(
                    title=data.get("title", "Imported Recipe"),
                    description=data.get("description", ""),
                    ingredients=data.get("ingredients", ""),
                    instructions=data.get("instructions", ""),
                    prep_time=data.get("prep_time", ""),
                    cook_time=data.get("cook_time", ""),
                    servings=data.get("servings", ""),
                    source_url=url,
                    image_url=image_url,
                    notes=data.get("notes", ""),
                    user_id=current_user.id,
                )
                db.session.add(recipe)
                imported += 1
            except FetchError as e:
                failed += 1
                first_error = first_error or str(e)
            except Exception:
                failed += 1

        db.session.commit()

        if len(urls) == 1 and imported == 1:
            last = Recipe.query.filter_by(user_id=current_user.id).order_by(Recipe.id.desc()).first()
            flash("Recipe imported.", "success")
            return redirect(url_for("recipes.view", recipe_id=last.id))

        if no_caption and not imported and not failed:
            flash("Couldn't read the caption from that post: Instagram and TikTok often block this. "
                  "Paste the caption or upload a screenshot below instead.", "error")
            return redirect(url_for("recipes.import_url"))

        msg = f"Imported {imported} recipe(s)."
        if no_caption:
            msg += f" {len(no_caption)} social post(s) had no readable caption (paste it or upload a screenshot)."
        if failed:
            msg += f" {failed} failed."
            if first_error:
                msg += f" ({first_error})"
        flash(msg, "success" if imported else "error")
        return redirect(url_for("recipes.index"))

    # GET — prefill from PWA share target (?url=... or ?text=... or ?title=...)
    shared = ""
    for param in ("url", "text", "title"):
        value = request.args.get(param, "")
        m = _URL_RE.search(value)
        if m:
            shared = m.group(0)
            break
    return render_template("recipes/import.html", shared_url=shared, ocr_ok=ocr_available())


@recipes_bp.route("/recipe/import-pdf", methods=["POST"])
@login_required
def import_pdf():
    """Import recipe(s) from uploaded PDF files."""
    if "pdf_files" not in request.files:
        flash("Choose a PDF file to import.", "error")
        return redirect(url_for("recipes.import_url"))

    files = request.files.getlist("pdf_files")
    real_files = [f for f in files if f and f.filename]
    if len(real_files) == 1 and real_files[0].filename.lower().endswith(".pdf"):
        # Single PDF: show a preview instead of saving straight away
        import io
        from werkzeug.datastructures import FileStorage
        blob = real_files[0].read()
        try:
            data = parse_pdf_recipe(FileStorage(io.BytesIO(blob), filename="recipe.pdf"))
        except Exception:
            data = None
        if not data or not data.get("title"):
            flash("Couldn't find readable text in that PDF. Scanned PDFs need the photo import instead.", "error")
            return redirect(url_for("recipes.import_url"))
        raw_text = ""
        try:
            from pypdf import PdfReader
            raw_text = "\n".join((p.extract_text() or "") for p in PdfReader(io.BytesIO(blob)).pages).strip()
        except Exception:
            pass
        return _render_import_preview(data, kind="pdf", raw_text=raw_text)

    imported = 0
    failed = 0

    for f in files:
        if not f.filename or not f.filename.lower().endswith('.pdf'):
            failed += 1
            continue
        try:
            data = parse_pdf_recipe(f)
            if not data or not data.get("title"):
                failed += 1
                continue
            recipe = Recipe(
                title=data["title"],
                description=data.get("description", ""),
                ingredients=data.get("ingredients", ""),
                instructions=data.get("instructions", ""),
                notes=data.get("notes", ""),
                prep_time=data.get("prep_time", ""),
                cook_time=data.get("cook_time", ""),
                servings=data.get("servings", ""),
                image_url="",
                user_id=current_user.id,
            )
            db.session.add(recipe)
            imported += 1
        except Exception:
            failed += 1

    db.session.commit()

    if imported == 1 and len(files) == 1:
        last = Recipe.query.filter_by(user_id=current_user.id).order_by(Recipe.id.desc()).first()
        flash("Recipe imported from PDF. You may want to review and edit it.", "success")
        return redirect(url_for("recipes.edit", recipe_id=last.id))

    msg = f"Imported {imported} recipe(s) from PDF."
    if failed:
        msg += f" {failed} failed."
    flash(msg, "success" if imported else "error")
    return redirect(url_for("recipes.index"))


@recipes_bp.route("/recipe/import-photo", methods=["POST"])
@login_required
def import_photo():
    """Import one recipe from photos or screenshots (several images = one recipe, in order)."""
    files = [f for f in request.files.getlist("photos") if f and f.filename]
    if not files:
        flash("Choose at least one photo or screenshot.", "error")
        return redirect(url_for("recipes.import_url"))
    blobs = [f.read() for f in files]
    try:
        text = images_to_text(blobs)
    except OcrError as e:
        flash(str(e), "error")
        return redirect(url_for("recipes.import_url"))
    if len(text) < 20:
        flash("Couldn't find readable text in that image. Try a sharper, straight-on photo.", "error")
        return redirect(url_for("recipes.import_url"))

    parsed = parse_recipe_text(text, title=request.form.get("photo_title", "").strip() or None)
    image_name = ""
    if request.form.get("use_as_cover"):
        files[0].stream.seek(0)
        image_name = _save_uploaded_image(files[0])

    parsed["title"] = parsed.get("title") or "Recipe from photo"
    return _render_import_preview(parsed, image_name=image_name, kind="photo", raw_text=text)


@recipes_bp.route("/recipe/import-caption", methods=["POST"])
@login_required
def import_caption():
    """Import a recipe from pasted social media caption (Instagram, TikTok, etc.)."""
    caption = request.form.get("caption", "").strip()
    title_override = request.form.get("caption_title", "").strip()

    if not caption:
        flash("Paste the post's caption first, then import.", "error")
        return redirect(url_for("recipes.import_url"))

    parsed = parse_recipe_text(caption, title=title_override or None)
    parsed["title"] = parsed.get("title") or "Imported Recipe"
    return _render_import_preview(parsed, kind="caption", raw_text=caption)


@recipes_bp.route("/recipe/import-save", methods=["POST"])
@login_required
def import_save():
    """Create a recipe from the (possibly edited) import preview form."""
    form = request.form
    data = {k: form.get(k, "").strip() for k in
            ("title", "description", "ingredients", "instructions", "notes", "servings", "prep_time", "cook_time")}
    source_url = form.get("source_url", "").strip()
    image_name = form.get("image_name", "").strip()
    kind = form.get("kind", "url")
    raw_text = form.get("raw_text", "")
    # Only accept an image we could have produced: an uploads filename or an http(s) link
    if image_name and not (image_name.startswith(("http://", "https://")) or re.fullmatch(r"[\w.\-]+", image_name)):
        image_name = ""
    use_image = bool(form.get("use_image")) if image_name else False

    if not data["title"]:
        return _render_import_preview(data, source_url=source_url, image_name=image_name, kind=kind,
                                      raw_text=raw_text, status=400,
                                      error="Give the recipe a title before saving. Everything else you typed is still here.")

    recipe = Recipe(
        title=data["title"][:200],
        description=data["description"],
        ingredients=data["ingredients"],
        instructions=data["instructions"],
        notes=data["notes"],
        servings=data["servings"][:50],
        prep_time=data["prep_time"][:50],
        cook_time=data["cook_time"][:50],
        source_url=source_url[:500],
        image_url=image_name if use_image else "",
        user_id=current_user.id,
    )
    db.session.add(recipe)
    db.session.commit()
    flash("Recipe saved.", "success")
    return redirect(url_for("recipes.view", recipe_id=recipe.id))


# ── Favorites ──

@recipes_bp.route("/recipe/<int:recipe_id>/favorite", methods=["POST"])
@login_required
def toggle_favorite(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    fav = Favorite.query.filter_by(user_id=current_user.id, recipe_id=recipe_id).first()
    wants_json = (request.headers.get("X-Requested-With") == "fetch"
                  or request.accept_mimetypes.best == "application/json")
    if fav:
        db.session.delete(fav)
        favorited = False
    else:
        db.session.add(Favorite(user_id=current_user.id, recipe_id=recipe_id))
        favorited = True
    db.session.commit()
    if wants_json:
        return jsonify(favorited=favorited)
    flash("Added to favorites." if favorited else "Removed from favorites.", "success")
    return redirect(request.referrer or url_for("recipes.view", recipe_id=recipe_id))


# ── Ratings ──

@recipes_bp.route("/recipe/<int:recipe_id>/rate", methods=["POST"])
@login_required
def rate(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    score = request.form.get("score", type=int) or 0
    if score < 1 or score > 5:
        flash("Choose a rating from 1 to 5 stars.", "error")
        return redirect(url_for("recipes.view", recipe_id=recipe_id))
    
    rating = Rating.query.filter_by(user_id=current_user.id, recipe_id=recipe_id).first()
    if rating:
        rating.score = score
    else:
        rating = Rating(user_id=current_user.id, recipe_id=recipe_id, score=score)
        db.session.add(rating)
    db.session.commit()
    flash("Rating saved.", "success")
    return redirect(url_for("recipes.view", recipe_id=recipe_id))


# ── Comments ──

@recipes_bp.route("/recipe/<int:recipe_id>/comment", methods=["POST"])
@login_required
def add_comment(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    text = request.form.get("text", "").strip()
    if not text:
        flash("Write something before posting your comment.", "error")
        return redirect(url_for("recipes.view", recipe_id=recipe_id))
    
    comment = Comment(user_id=current_user.id, recipe_id=recipe_id, text=text)
    db.session.add(comment)
    db.session.commit()
    flash("Comment added.", "success")
    return redirect(url_for("recipes.view", recipe_id=recipe_id))


@recipes_bp.route("/comment/<int:comment_id>/delete", methods=["POST"])
@login_required
def delete_comment(comment_id):
    comment = Comment.query.get_or_404(comment_id)
    if comment.user_id != current_user.id and not current_user.is_admin:
        flash("That belongs to someone else, so you can't change it.", "error")
        return redirect(url_for("recipes.index"))
    recipe_id = comment.recipe_id
    db.session.delete(comment)
    db.session.commit()
    flash("Comment deleted.", "success")
    return redirect(url_for("recipes.view", recipe_id=recipe_id))


# ── Notes ──

@recipes_bp.route("/recipe/<int:recipe_id>/notes", methods=["POST"])
@login_required
def save_notes(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    if recipe.user_id != current_user.id and not current_user.is_admin:
        flash("That belongs to someone else, so you can't change it.", "error")
        return redirect(url_for("recipes.view", recipe_id=recipe_id))
    recipe.notes = request.form.get("notes", "").strip()
    db.session.commit()
    flash("Notes saved.", "success")
    return redirect(url_for("recipes.view", recipe_id=recipe_id))


# ── Sharing ──

@recipes_bp.route("/recipe/<int:recipe_id>/share", methods=["POST"])
@login_required
def create_share_link(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    if recipe.user_id != current_user.id and not current_user.is_admin:
        flash("That belongs to someone else, so you can't change it.", "error")
        return redirect(url_for("recipes.view", recipe_id=recipe_id))
    
    if not recipe.share_token:
        recipe.share_token = secrets.token_urlsafe(16)
        db.session.commit()
    
    flash("Share link created.", "success")
    return redirect(url_for("recipes.view", recipe_id=recipe_id))


@recipes_bp.route("/recipe/<int:recipe_id>/unshare", methods=["POST"])
@login_required
def remove_share_link(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    if recipe.user_id != current_user.id and not current_user.is_admin:
        flash("That belongs to someone else, so you can't change it.", "error")
        return redirect(url_for("recipes.view", recipe_id=recipe_id))
    
    recipe.share_token = None
    db.session.commit()
    flash("Share link removed.", "success")
    return redirect(url_for("recipes.view", recipe_id=recipe_id))


@recipes_bp.route("/shared/<token>")
def view_shared(token):
    """Public view for shared recipes - no login required."""
    recipe = Recipe.query.filter_by(share_token=token).first_or_404()
    return render_template("recipes/shared.html", recipe=recipe)


# ── Print View ──

@recipes_bp.route("/recipe/<int:recipe_id>/print")
@login_required
def print_view(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    return render_template("recipes/print.html", recipe=recipe)


# ── Cook Mode ──

@recipes_bp.route("/recipe/<int:recipe_id>/cook")
@login_required
def cook_mode(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    return render_template("recipes/cook.html", recipe=recipe)


# ── Export ──

@recipes_bp.route("/recipe/<int:recipe_id>/export")
@login_required
def export(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    
    # Generate plain text export
    content = f"""# {recipe.title}

{recipe.description}

## Info
- Prep Time: {recipe.prep_time or 'N/A'}
- Cook Time: {recipe.cook_time or 'N/A'}
- Servings: {recipe.servings or 'N/A'}

## Ingredients
{recipe.ingredients}

## Instructions
{recipe.instructions}

---
Exported from Recipe Manager
"""
    if recipe.source_url:
        content += f"Source: {recipe.source_url}\n"
    
    response = make_response(content)
    response.headers["Content-Type"] = "text/plain; charset=utf-8"
    response.headers["Content-Disposition"] = f'attachment; filename="{recipe.title}.txt"'
    return response


# ── Made It (Cook Log) ──

@recipes_bp.route("/recipe/<int:recipe_id>/made-it", methods=["POST"])
@login_required
def made_it(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    log = CookLog(user_id=current_user.id, recipe_id=recipe_id)
    db.session.add(log)
    db.session.commit()
    count = CookLog.query.filter_by(user_id=current_user.id, recipe_id=recipe_id).count()
    flash(f"Logged. You've made this {count} time{'' if count == 1 else 's'}.", "success")
    return redirect(url_for("recipes.view", recipe_id=recipe_id))


@recipes_bp.route("/recipe/<int:recipe_id>/cook-history")
@login_required
def cook_history(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    logs = CookLog.query.filter_by(user_id=current_user.id, recipe_id=recipe_id)\
        .order_by(CookLog.cooked_at.desc()).all()
    return render_template("recipes/cook_history.html", recipe=recipe, logs=logs)


# ── Email Recipe ──

@recipes_bp.route("/recipe/<int:recipe_id>/email", methods=["POST"])
@login_required
def email_recipe(recipe_id):
    from mailer import send_recipe_email
    from routes.auth import is_valid_email
    recipe = Recipe.query.get_or_404(recipe_id)
    to_email = request.form.get("email", "").strip()
    if not is_valid_email(to_email):
        flash("Enter a valid email address to send the recipe to.", "error")
        return redirect(url_for("recipes.view", recipe_id=recipe_id))

    sent = send_recipe_email(to_email, recipe, current_user.username)
    if sent:
        flash(f"Recipe emailed to {to_email}.", "success")
    else:
        flash("The email couldn't be sent. Ask an admin to check the email settings.", "error")
    return redirect(url_for("recipes.view", recipe_id=recipe_id))


# ── Unit Converter ──

@recipes_bp.route("/converter")
@login_required
def unit_converter():
    return render_template("recipes/converter.html")


@recipes_bp.route("/random")
@login_required
def random_recipe():
    """Pick a random recipe - 'What should I cook?'"""
    cat_id = request.args.get("cat", type=int)
    favorites_only = request.args.get("favorites") == "1"
    
    query = Recipe.query
    if cat_id:
        query = query.filter(Recipe.categories.any(Category.id == cat_id))
    if favorites_only:
        fav_ids = [f.recipe_id for f in Favorite.query.filter_by(user_id=current_user.id).all()]
        query = query.filter(Recipe.id.in_(fav_ids))
    
    recipes = query.all()
    if not recipes:
        flash("You don't have any recipes yet. Add one first, then try Surprise me.", "error")
        return redirect(url_for("recipes.index"))
    
    pick = random.choice(recipes)
    return redirect(url_for("recipes.view", recipe_id=pick.id))
