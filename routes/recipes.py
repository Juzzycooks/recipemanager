import os
import random
import re
import secrets
from flask import Blueprint, render_template, redirect, url_for, flash, request, make_response, jsonify, current_app
from flask_login import login_required, current_user
from models import db, Recipe, Category, Favorite, Rating, Comment, CookLog, Collection
from scraper import scrape_recipe, parse_pdf_recipe, _parse_caption_into_recipe
from security import FetchError
from images import save_uploaded_image
from nutrition import estimate_recipe

recipes_bp = Blueprint("recipes", __name__)


def _save_uploaded_image(file):
    """Verify, resize, strip EXIF and save an uploaded image (+thumbnail).
    Returns the filename, or empty string if missing/invalid."""
    data_dir = current_app.config.get("DATA_DIR", os.environ.get("DATA_DIR", "/app/data"))
    uploads_dir = os.path.join(data_dir, "uploads")
    return save_uploaded_image(file, uploads_dir, prefix="recipe")


@recipes_bp.route("/")
@login_required
def index():
    search = request.args.get("q", "").strip()
    cat_id = request.args.get("cat", type=int)
    favorites_only = request.args.get("favorites") == "1"
    ingredient_search = request.args.get("ingredient", "").strip()
    sort = request.args.get("sort", "newest")
    view_mode = request.args.get("view", "grid")
    page = request.args.get("page", 1, type=int)
    per_page = 24
    coll_id = request.args.get("collection", type=int)
    
    query = Recipe.query
    if search:
        query = query.filter(Recipe.title.ilike(f"%{search}%"))
    if ingredient_search:
        query = query.filter(Recipe.ingredients.ilike(f"%{ingredient_search}%"))
    if cat_id:
        query = query.filter(Recipe.categories.any(Category.id == cat_id))
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
    
    return render_template("recipes/index.html", recipes=recipes,
                           search=search, categories=categories,
                           active_cat=cat_id, user_favs=user_favs,
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
        flash("Access denied.", "error")
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
        flash("Access denied.", "error")
        return redirect(url_for("recipes.index"))
    db.session.delete(recipe)
    db.session.commit()
    flash("Recipe deleted.", "success")
    return redirect(url_for("recipes.index"))


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
            flash("Please enter at least one URL.", "error")
            return redirect(url_for("recipes.import_url"))

        imported = 0
        failed = 0
        first_error = ""
        for url in urls:
            try:
                data = scrape_recipe(url)
                recipe = Recipe(
                    title=data.get("title", "Imported Recipe"),
                    description=data.get("description", ""),
                    ingredients=data.get("ingredients", ""),
                    instructions=data.get("instructions", ""),
                    prep_time=data.get("prep_time", ""),
                    cook_time=data.get("cook_time", ""),
                    servings=data.get("servings", ""),
                    source_url=url,
                    image_url=data.get("image_url", ""),
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

        msg = f"Imported {imported} recipe(s)."
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
    return render_template("recipes/import.html", shared_url=shared)


@recipes_bp.route("/recipe/import-pdf", methods=["POST"])
@login_required
def import_pdf():
    """Import recipe(s) from uploaded PDF files."""
    if "pdf_files" not in request.files:
        flash("No files uploaded.", "error")
        return redirect(url_for("recipes.import_url"))

    files = request.files.getlist("pdf_files")
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


@recipes_bp.route("/recipe/import-caption", methods=["POST"])
@login_required
def import_caption():
    """Import a recipe from pasted social media caption (Instagram, TikTok, etc.)."""
    caption = request.form.get("caption", "").strip()
    title_override = request.form.get("caption_title", "").strip()

    if not caption:
        flash("Please paste a caption.", "error")
        return redirect(url_for("recipes.import_url"))

    description, ingredients, instructions = _parse_caption_into_recipe(caption)

    # Derive title: user override > first line of caption > fallback
    if not title_override:
        first_line = caption.split('\n')[0].strip()
        if 3 < len(first_line) < 120 and not first_line.startswith('#'):
            title_override = first_line
        else:
            title_override = "Imported Recipe"

    recipe = Recipe(
        title=title_override,
        description=description,
        ingredients=ingredients,
        instructions=instructions,
        user_id=current_user.id,
    )
    db.session.add(recipe)
    db.session.commit()

    flash("Recipe imported from caption. Review and edit as needed.", "success")
    return redirect(url_for("recipes.edit", recipe_id=recipe.id))


# ── Favorites ──

@recipes_bp.route("/recipe/<int:recipe_id>/favorite", methods=["POST"])
@login_required
def toggle_favorite(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    fav = Favorite.query.filter_by(user_id=current_user.id, recipe_id=recipe_id).first()
    if fav:
        db.session.delete(fav)
        flash("Removed from favorites.", "success")
    else:
        db.session.add(Favorite(user_id=current_user.id, recipe_id=recipe_id))
        flash("Added to favorites.", "success")
    db.session.commit()
    return redirect(request.referrer or url_for("recipes.view", recipe_id=recipe_id))


# ── Ratings ──

@recipes_bp.route("/recipe/<int:recipe_id>/rate", methods=["POST"])
@login_required
def rate(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    score = request.form.get("score", type=int) or 0
    if score < 1 or score > 5:
        flash("Invalid rating.", "error")
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
        flash("Comment cannot be empty.", "error")
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
        flash("Access denied.", "error")
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
        flash("Access denied.", "error")
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
        flash("Access denied.", "error")
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
        flash("Access denied.", "error")
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
    flash(f"Logged! You've made this {count} time(s).", "success")
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
        flash("Please enter a valid email address.", "error")
        return redirect(url_for("recipes.view", recipe_id=recipe_id))

    sent = send_recipe_email(to_email, recipe, current_user.username)
    if sent:
        flash(f"Recipe emailed to {to_email}.", "success")
    else:
        flash("Failed to send email. Check SMTP settings.", "error")
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
        flash("No recipes to pick from.", "error")
        return redirect(url_for("recipes.index"))
    
    pick = random.choice(recipes)
    return redirect(url_for("recipes.view", recipe_id=pick.id))
