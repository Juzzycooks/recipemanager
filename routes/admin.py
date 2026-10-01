import secrets
from functools import wraps
from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_required, current_user
from models import db, User, Category, Recipe, Calculator, SiteSetting
from mailer import send_welcome_email
from routes.auth import find_user
from mealie_import import (
    mealie_auth, mealie_get_recipes, mealie_get_recipe_detail, parse_mealie_recipe,
    download_mealie_image,
)

admin_bp = Blueprint("admin", __name__, url_prefix="/admin")


def admin_required(f):
    @wraps(f)
    @login_required
    def decorated(*args, **kwargs):
        if not current_user.is_admin:
            flash("That page is for admins only. Ask an admin if you need something changed.", "error")
            return redirect(url_for("recipes.index"))
        return f(*args, **kwargs)
    return decorated


@admin_bp.route("/")
@admin_required
def dashboard():
    users = User.query.order_by(User.created_at.desc()).all()
    categories = Category.query.order_by(Category.name).all()
    calculators = Calculator.query.order_by(Calculator.sort_order, Calculator.name).all()
    user_count = len(users)
    recipe_count = Recipe.query.count()
    remote_images = _remote_image_recipes().count()
    return render_template("admin/dashboard.html", users=users,
                           categories=categories, user_count=user_count,
                           recipe_count=recipe_count, calculators=calculators,
                           remote_image_count=remote_images)


def _remote_image_recipes():
    """Recipes whose picture is a link to another site (Mealie API links are unusable, so skipped)."""
    return Recipe.query.filter(
        db.or_(Recipe.image_url.like("http://%"), Recipe.image_url.like("https://%")),
        ~Recipe.image_url.like("%/api/media/recipes/%"))


@admin_bp.route("/localise-images", methods=["POST"])
@admin_required
def localise_images():
    """Keep our own copy of remote recipe pictures (in batches, so the request stays quick)."""
    from routes.recipes import _localise_remote_image
    BATCH = 25
    saved = failed = 0
    for recipe in _remote_image_recipes().order_by(Recipe.id).limit(BATCH).all():
        local = _localise_remote_image(recipe.image_url)
        if local:
            recipe.image_url = local
            saved += 1
        else:
            failed += 1
            recipe.image_url = ""  # the link is dead or blocked: better the monogram tile than a broken box
    db.session.commit()
    left = _remote_image_recipes().count()
    msg = f"Saved {saved} picture{'' if saved == 1 else 's'} to this server."
    if failed:
        msg += f" {failed} couldn't be downloaded (the site blocks it or the image is gone), so those recipes now show a letter tile."
    if left:
        msg += f" {left} more to go: run it again."
    flash(msg, "success")
    return redirect(url_for("admin.dashboard"))


# ── User Management ──

@admin_bp.route("/users/add", methods=["GET", "POST"])
@admin_required
def add_user():
    from routes.auth import is_valid_email
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        email = request.form.get("email", "").strip()
        is_admin = request.form.get("is_admin") == "on"
        gen_password = secrets.token_urlsafe(12)

        if not username:
            flash("Enter a username.", "error")
            return redirect(url_for("admin.add_user"))
        if email and not is_valid_email(email):
            flash("That email address doesn't look right. Check it for typos.", "error")
            return redirect(url_for("admin.add_user"))
        if find_user(username):
            flash("That username is taken. Try another.", "error")
            return redirect(url_for("admin.add_user"))

        user = User(username=username, email=email, is_admin=is_admin)
        user.set_password(gen_password)
        db.session.add(user)
        db.session.commit()

        email_sent = False
        if email:
            email_sent = send_welcome_email(email, username, gen_password)

        if email_sent:
            flash(f"User '{username}' created. Credentials emailed to {email}.", "success")
        else:
            flash(f"User '{username}' created. Temporary password: {gen_password}", "success")
        return redirect(url_for("admin.dashboard"))
    return render_template("admin/user_form.html", user=None)


@admin_bp.route("/users/<int:user_id>/edit", methods=["GET", "POST"])
@admin_required
def edit_user(user_id):
    from routes.auth import is_valid_email
    user = User.query.get_or_404(user_id)
    if request.method == "POST":
        user.username = request.form.get("username", "").strip() or user.username
        email = request.form.get("email", "").strip()
        if email and not is_valid_email(email):
            flash("That email address doesn't look right. Check it for typos.", "error")
            return redirect(url_for("admin.edit_user", user_id=user_id))
        user.email = email
        user.is_admin = request.form.get("is_admin") == "on"
        new_pass = request.form.get("new_password", "").strip()
        if new_pass:
            # Validate password strength
            if len(new_pass) < 8:
                flash("Password must be at least 8 characters.", "error")
                return redirect(url_for("admin.edit_user", user_id=user_id))
            if new_pass.isdigit() or new_pass.isalpha():
                flash("Password must contain both letters and numbers.", "error")
                return redirect(url_for("admin.edit_user", user_id=user_id))
            user.set_password(new_pass)
        db.session.commit()
        flash(f"User '{user.username}' updated.", "success")
        return redirect(url_for("admin.dashboard"))
    return render_template("admin/user_form.html", user=user)


@admin_bp.route("/users/<int:user_id>/delete", methods=["POST"])
@admin_required
def delete_user(user_id):
    from models import ShoppingListItem
    user = User.query.get_or_404(user_id)
    if user.id == current_user.id:
        flash("You can't delete yourself.", "error")
        return redirect(url_for("admin.dashboard"))
    username = user.username
    # Shopping items have no ORM relationship — clean up explicitly
    ShoppingListItem.query.filter_by(user_id=user.id).delete()
    # ORM delete so cascades fire: the user's recipes (and those recipes'
    # ratings/comments/favorites/meal plans from ALL users), plus the user's
    # own ratings/comments/favorites/meal plans/cook logs/collections.
    db.session.delete(user)
    db.session.commit()
    flash(f"User '{username}' deleted.", "success")
    return redirect(url_for("admin.dashboard"))


# ── Category Management ──

@admin_bp.route("/categories/add", methods=["POST"])
@admin_required
def add_category():
    name = request.form.get("name", "").strip()
    if not name:
        flash("Give the category a name.", "error")
    elif Category.query.filter_by(name=name).first():
        flash("That category already exists.", "error")
    else:
        db.session.add(Category(name=name))
        db.session.commit()
        flash(f"Category '{name}' added.", "success")
    return redirect(url_for("admin.dashboard"))


@admin_bp.route("/categories/<int:cat_id>/delete", methods=["POST"])
@admin_required
def delete_category(cat_id):
    cat = Category.query.get_or_404(cat_id)
    db.session.delete(cat)
    db.session.commit()
    flash(f"Category '{cat.name}' deleted.", "success")
    return redirect(url_for("admin.dashboard"))


# ── Mealie Import ──

@admin_bp.route("/mealie", methods=["GET", "POST"])
@admin_required
def mealie_import_page():
    from flask import current_app
    
    if request.method == "POST":
        base_url = request.form.get("mealie_url", "").strip().rstrip("/")
        email = request.form.get("mealie_email", "").strip()
        password = request.form.get("mealie_password", "")

        if not base_url or not email or not password:
            flash("Fill in all the Mealie connection fields first.", "error")
            return redirect(url_for("admin.mealie_import_page"))

        try:
            token = mealie_auth(base_url, email, password)
        except Exception as e:
            flash(f"Mealie auth failed: {e}", "error")
            return redirect(url_for("admin.mealie_import_page"))

        # Setup uploads directory for images
        data_dir = current_app.config.get("DATA_DIR", os.environ.get("DATA_DIR", "/app/data"))
        uploads_dir = os.path.join(data_dir, "uploads")
        os.makedirs(uploads_dir, exist_ok=True)

        imported = 0
        page = 1
        while True:
            items, total = mealie_get_recipes(base_url, token, page=page, per_page=50)
            if not items:
                break
            for item in items:
                slug = item.get("slug", "")
                if not slug:
                    continue
                try:
                    detail = mealie_get_recipe_detail(base_url, token, slug)
                    parsed = parse_mealie_recipe(detail, base_url)
                    
                    # Download image locally instead of using URL
                    recipe_id = detail.get("id", "")
                    local_image = download_mealie_image(base_url, token, recipe_id, uploads_dir)
                    
                    recipe = Recipe(
                        title=parsed["title"],
                        description=parsed["description"],
                        ingredients=parsed["ingredients"],
                        instructions=parsed["instructions"],
                        prep_time=parsed["prep_time"],
                        cook_time=parsed["cook_time"],
                        servings=parsed["servings"],
                        source_url=parsed["source_url"],
                        image_url=local_image,  # Store local filename
                        user_id=current_user.id,
                    )
                    # Assign categories
                    for cat_name in parsed.get("categories", []):
                        cat = Category.query.filter_by(name=cat_name).first()
                        if not cat:
                            cat = Category(name=cat_name)
                            db.session.add(cat)
                            db.session.flush()
                        recipe.categories.append(cat)
                    db.session.add(recipe)
                    imported += 1
                except Exception:
                    continue
            page += 1
            if (page - 1) * 50 >= total:
                break

        db.session.commit()
        flash(f"Imported {imported} recipes from Mealie.", "success")
        return redirect(url_for("admin.dashboard"))

    return render_template("admin/mealie_import.html")


# ── Calculator Management ──

@admin_bp.route("/calculators/add", methods=["GET", "POST"])
@admin_required
def add_calculator():
    if request.method == "POST":
        name = request.form.get("name", "").strip()
        url = request.form.get("url", "").strip()
        description = request.form.get("description", "").strip()
        icon = request.form.get("icon", "🧮").strip() or "🧮"
        sort_order = request.form.get("sort_order", type=int) or 0

        if not name or not url:
            flash("Enter both a name and a web address.", "error")
            return redirect(url_for("admin.add_calculator"))

        calc = Calculator(name=name, url=url, description=description,
                          icon=icon, sort_order=sort_order)
        db.session.add(calc)
        db.session.commit()
        flash(f"Calculator '{name}' added.", "success")
        return redirect(url_for("admin.dashboard"))
    return render_template("admin/calculator_form.html", calc=None)


@admin_bp.route("/calculators/<int:calc_id>/edit", methods=["GET", "POST"])
@admin_required
def edit_calculator(calc_id):
    calc = Calculator.query.get_or_404(calc_id)
    if request.method == "POST":
        calc.name = request.form.get("name", "").strip() or calc.name
        calc.url = request.form.get("url", "").strip() or calc.url
        calc.description = request.form.get("description", "").strip()
        calc.icon = request.form.get("icon", "🧮").strip() or "🧮"
        calc.sort_order = request.form.get("sort_order", type=int) or 0
        db.session.commit()
        flash(f"Calculator '{calc.name}' updated.", "success")
        return redirect(url_for("admin.dashboard"))
    return render_template("admin/calculator_form.html", calc=calc)


@admin_bp.route("/calculators/<int:calc_id>/delete", methods=["POST"])
@admin_required
def delete_calculator(calc_id):
    calc = Calculator.query.get_or_404(calc_id)
    db.session.delete(calc)
    db.session.commit()
    flash(f"Calculator '{calc.name}' deleted.", "success")
    return redirect(url_for("admin.dashboard"))


# ── Site Settings ──

import os
from images import save_uploaded_image, delete_image

# SVG removed: inline-served SVGs can contain scripts (stored XSS)
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'webp'}

def _allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def _set_setting(key, value):
    setting = SiteSetting.query.filter_by(key=key).first()
    if setting:
        setting.value = value
    else:
        setting = SiteSetting(key=key, value=value)
        db.session.add(setting)
    db.session.commit()


@admin_bp.route("/settings", methods=["GET", "POST"])
@admin_required
def settings():
    from flask import current_app
    data_dir = current_app.config.get("DATA_DIR", os.environ.get("DATA_DIR", "/app/data"))
    uploads_dir = os.path.join(data_dir, "uploads")
    os.makedirs(uploads_dir, exist_ok=True)
    
    if request.method == "POST":
        site_name = request.form.get("site_name", "").strip()
        _set_setting("site_name", site_name)
        _set_setting("public_show_author", "1" if request.form.get("public_show_author") else "0")

        # Shopping: store label and search link ({q} = item name)
        store_name = request.form.get("store_name", "").strip()[:60]
        store_url = request.form.get("store_search_url", "").strip()
        if not store_name:
            store_name = "Woolworths" if store_url else ""
        store_ok = True
        if store_url and not (store_url.lower().startswith(("http://", "https://"))
                              and "{q}" in store_url and len(store_url) <= 500):
            flash("The store search link needs to start with http:// or https:// and include {q} where the item name goes. "
                  "Your previous link was kept.", "error")
            store_ok = False
        else:
            _set_setting("store_search_url", store_url)
            _set_setting("store_name", store_name)

        # Handle logo upload (content-verified, re-encoded, EXIF stripped)
        if "logo_file" in request.files:
            file = request.files["logo_file"]
            if file and file.filename and _allowed_file(file.filename):
                filename = save_uploaded_image(file, uploads_dir, prefix="logo",
                                               max_dim=600, make_thumb=False)
                if filename:
                    # Delete old logo if exists
                    old_logo = SiteSetting.query.filter_by(key="logo_file").first()
                    if old_logo and old_logo.value:
                        delete_image(uploads_dir, old_logo.value)
                    _set_setting("logo_file", filename)
                else:
                    flash("That file doesn't appear to be a valid image.", "error")

        # Handle logo removal
        if request.form.get("remove_logo") == "1":
            logo_setting = SiteSetting.query.filter_by(key="logo_file").first()
            if logo_setting and logo_setting.value:
                delete_image(uploads_dir, logo_setting.value)
                logo_setting.value = ""
                db.session.commit()
        
        if store_ok:
            flash("Settings saved.", "success")
        else:
            flash("Your other settings were saved.", "success")
        return redirect(url_for("admin.settings"))
    
    logo_file = SiteSetting.query.filter_by(key="logo_file").first()
    site_name = SiteSetting.query.filter_by(key="site_name").first()
    from routes.shopping import _store_settings
    store_name, store_url = _store_settings()
    show_author = SiteSetting.query.filter_by(key="public_show_author").first()
    return render_template("admin/settings.html",
                           store_name=store_name, store_search_url=store_url,
                           public_show_author=bool(show_author and show_author.value == "1"),
                           logo_file=logo_file.value if logo_file else "",
                           site_name=site_name.value if site_name else "")


@admin_bp.route("/uploads/<filename>")
def uploaded_file(filename):
    """Serve uploaded files."""
    from flask import send_from_directory, current_app
    data_dir = current_app.config.get("DATA_DIR", os.environ.get("DATA_DIR", "/app/data"))
    uploads_dir = os.path.join(data_dir, "uploads")
    # Filenames are random per upload (never reused), so they are safe to cache long-term
    return send_from_directory(uploads_dir, filename, max_age=60 * 60 * 24 * 30)


# ── Backup / Export / Import ──

import io
import json
import re as _re
import sqlite3
import zipfile
from datetime import datetime, timezone
from flask import send_file, current_app


def _export_payload():
    """Build the JSON-serialisable export of all recipes."""
    recipes = []
    for r in Recipe.query.order_by(Recipe.id).all():
        recipes.append({
            "title": r.title,
            "description": r.description or "",
            "ingredients": r.ingredients or "",
            "instructions": r.instructions or "",
            "prep_time": r.prep_time or "",
            "cook_time": r.cook_time or "",
            "servings": r.servings or "",
            "source_url": r.source_url or "",
            "image_url": r.image_url or "",
            "notes": r.notes or "",
            "categories": [c.name for c in r.categories],
            "author": r.author.username if r.author else "",
            "created_at": r.created_at.isoformat() if r.created_at else "",
        })
    return {
        "app": "RecipeManager",
        "version": 1,
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "recipes": recipes,
    }


@admin_bp.route("/backup/export.json")
@admin_required
def export_json():
    """Download all recipes as JSON."""
    payload = json.dumps(_export_payload(), indent=2, ensure_ascii=False)
    buf = io.BytesIO(payload.encode("utf-8"))
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d")
    return send_file(buf, mimetype="application/json", as_attachment=True,
                     download_name=f"recipes-export-{stamp}.json")


@admin_bp.route("/backup/export.zip")
@admin_required
def export_zip():
    """Download all recipes + uploaded images as a zip."""
    data_dir = current_app.config.get("DATA_DIR", os.environ.get("DATA_DIR", "/app/data"))
    uploads_dir = os.path.join(data_dir, "uploads")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("recipes.json",
                    json.dumps(_export_payload(), indent=2, ensure_ascii=False))
        if os.path.isdir(uploads_dir):
            for name in os.listdir(uploads_dir):
                path = os.path.join(uploads_dir, name)
                if os.path.isfile(path):
                    zf.write(path, f"uploads/{name}")
    buf.seek(0)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d")
    return send_file(buf, mimetype="application/zip", as_attachment=True,
                     download_name=f"recipemanager-backup-{stamp}.zip")


@admin_bp.route("/backup/db")
@admin_required
def export_db():
    """Download a consistent SQLite snapshot (VACUUM INTO)."""
    data_dir = current_app.config.get("DATA_DIR", os.environ.get("DATA_DIR", "/app/data"))
    db_path = os.path.join(data_dir, "recipes.db")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    snap_path = os.path.join(data_dir, f"snapshot-{stamp}.db")
    try:
        conn = sqlite3.connect(db_path)
        conn.execute("VACUUM INTO ?", (snap_path,))
        conn.close()
        with open(snap_path, "rb") as f:
            buf = io.BytesIO(f.read())
        return send_file(buf, mimetype="application/x-sqlite3", as_attachment=True,
                         download_name=f"recipes-{stamp}.db")
    finally:
        if os.path.exists(snap_path):
            try:
                os.remove(snap_path)
            except OSError:
                pass


_SAFE_UPLOAD_NAME = _re.compile(r"^[\w.-]+$")


@admin_bp.route("/backup/import", methods=["POST"])
@admin_required
def import_backup():
    """Import recipes from a JSON or zip export. Recipes are assigned to the
    importing admin. Images are restored if they don't already exist."""
    file = request.files.get("backup_file")
    if not file or not file.filename:
        flash("Please choose a backup file.", "error")
        return redirect(url_for("admin.dashboard"))

    data_dir = current_app.config.get("DATA_DIR", os.environ.get("DATA_DIR", "/app/data"))
    uploads_dir = os.path.join(data_dir, "uploads")
    os.makedirs(uploads_dir, exist_ok=True)

    payload = None
    restored_images = 0
    try:
        if file.filename.lower().endswith(".zip"):
            zf = zipfile.ZipFile(file.stream)
            with zf.open("recipes.json") as jf:
                payload = json.load(jf)
            for info in zf.infolist():
                if info.is_dir() or not info.filename.startswith("uploads/"):
                    continue
                name = os.path.basename(info.filename)
                # Zip-slip guard: plain filenames only
                if not name or not _SAFE_UPLOAD_NAME.match(name):
                    continue
                if info.file_size > 20 * 1024 * 1024:
                    continue
                dest = os.path.join(uploads_dir, name)
                if not os.path.exists(dest):
                    with zf.open(info) as src, open(dest, "wb") as out:
                        out.write(src.read())
                    restored_images += 1
        else:
            payload = json.load(file.stream)
    except (zipfile.BadZipFile, json.JSONDecodeError, KeyError, UnicodeDecodeError):
        flash("That doesn't look like a valid backup file.", "error")
        return redirect(url_for("admin.dashboard"))

    if not isinstance(payload, dict) or not isinstance(payload.get("recipes"), list):
        flash("That backup file isn't in a format we recognise. Use one exported from this app.", "error")
        return redirect(url_for("admin.dashboard"))

    # Skip exact-title duplicates to make re-imports safe
    existing_titles = {r.title for r in Recipe.query.with_entities(Recipe.title).all()}
    imported = skipped = 0
    for entry in payload["recipes"]:
        if not isinstance(entry, dict):
            continue
        title = str(entry.get("title", "")).strip()
        if not title:
            continue
        if title in existing_titles:
            skipped += 1
            continue
        recipe = Recipe(
            title=title[:200],
            description=str(entry.get("description", "")),
            ingredients=str(entry.get("ingredients", "")),
            instructions=str(entry.get("instructions", "")),
            prep_time=str(entry.get("prep_time", ""))[:50],
            cook_time=str(entry.get("cook_time", ""))[:50],
            servings=str(entry.get("servings", ""))[:50],
            source_url=str(entry.get("source_url", ""))[:500],
            image_url=str(entry.get("image_url", ""))[:500],
            notes=str(entry.get("notes", "")),
            user_id=current_user.id,
        )
        for cat_name in entry.get("categories", []) or []:
            cat_name = str(cat_name).strip()[:100]
            if not cat_name:
                continue
            cat = Category.query.filter_by(name=cat_name).first()
            if not cat:
                cat = Category(name=cat_name)
                db.session.add(cat)
                db.session.flush()
            recipe.categories.append(cat)
        db.session.add(recipe)
        existing_titles.add(title)
        imported += 1

    db.session.commit()
    msg = f"Imported {imported} recipe(s)."
    if skipped:
        msg += f" Skipped {skipped} duplicate(s)."
    if restored_images:
        msg += f" Restored {restored_images} image(s)."
    flash(msg, "success")
    return redirect(url_for("admin.dashboard"))
