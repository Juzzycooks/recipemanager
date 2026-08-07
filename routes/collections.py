import os
import re
import uuid
import secrets
from flask import Blueprint, render_template, redirect, url_for, flash, request, jsonify, current_app
from flask_login import login_required, current_user
from models import db, Recipe, Collection, Category

collections_bp = Blueprint("collections", __name__, url_prefix="/collections")

ALLOWED_IMG_EXT = {'png', 'jpg', 'jpeg', 'gif', 'webp'}


def _slugify(text):
    """Convert text to URL-friendly slug."""
    text = text.lower().strip()
    text = re.sub(r'[^\w\s-]', '', text)
    text = re.sub(r'[\s_]+', '-', text)
    text = re.sub(r'-+', '-', text).strip('-')
    return text[:200] if text else None


def _save_cover_image(file):
    """Save an uploaded cover image and return the filename."""
    if not file or not file.filename:
        return ""
    ext = file.filename.rsplit('.', 1)[-1].lower() if '.' in file.filename else ""
    if ext not in ALLOWED_IMG_EXT:
        return ""
    data_dir = current_app.config.get("DATA_DIR", os.environ.get("DATA_DIR", "/app/data"))
    uploads_dir = os.path.join(data_dir, "uploads")
    os.makedirs(uploads_dir, exist_ok=True)
    filename = f"cover_{uuid.uuid4().hex[:12]}.{ext}"
    file.save(os.path.join(uploads_dir, filename))
    return filename


def _find_collection_by_token_or_slug(token):
    """Find a collection by slug first, then share_token."""
    coll = Collection.query.filter_by(slug=token).first()
    if not coll:
        coll = Collection.query.filter_by(share_token=token).first()
    return coll


@collections_bp.route("/")
@login_required
def index():
    colls = Collection.query.filter_by(user_id=current_user.id)\
        .order_by(Collection.name).all()
    return render_template("collections/index.html", collections=colls)


@collections_bp.route("/create", methods=["GET", "POST"])
@login_required
def create():
    categories = Category.query.order_by(Category.name).all()
    if request.method == "POST":
        name = request.form.get("name", "").strip()
        if not name:
            flash("Name is required.", "error")
            return redirect(url_for("collections.create"))
        cat_id = request.form.get("category_id", type=int) or None
        slug_input = request.form.get("slug", "").strip()
        slug = _slugify(slug_input) if slug_input else None
        if slug:
            existing = Collection.query.filter_by(slug=slug).first()
            if existing:
                flash("That slug is already taken.", "error")
                return redirect(url_for("collections.create"))
        cover = ""
        if "cover_image" in request.files:
            cover = _save_cover_image(request.files["cover_image"])
        coll = Collection(
            name=name,
            description=request.form.get("description", "").strip(),
            user_id=current_user.id,
            category_id=cat_id,
            slug=slug,
            cover_image=cover,
        )
        db.session.add(coll)
        db.session.commit()
        flash(f"Collection '{name}' created.", "success")
        return redirect(url_for("collections.view", coll_id=coll.id))
    return render_template("collections/form.html", collection=None, categories=categories)


@collections_bp.route("/<int:coll_id>")
@login_required
def view(coll_id):
    coll = Collection.query.get_or_404(coll_id)
    if coll.user_id != current_user.id and not current_user.is_admin:
        flash("Access denied.", "error")
        return redirect(url_for("collections.index"))
    all_recipes = coll.get_all_recipes()
    return render_template("collections/view.html", collection=coll,
                           all_recipes=all_recipes,
                           recipes=Recipe.query.order_by(Recipe.title).all())


@collections_bp.route("/<int:coll_id>/edit", methods=["GET", "POST"])
@login_required
def edit(coll_id):
    coll = Collection.query.get_or_404(coll_id)
    if coll.user_id != current_user.id and not current_user.is_admin:
        flash("Access denied.", "error")
        return redirect(url_for("collections.index"))
    categories = Category.query.order_by(Category.name).all()
    if request.method == "POST":
        coll.name = request.form.get("name", "").strip()
        coll.description = request.form.get("description", "").strip()
        coll.category_id = request.form.get("category_id", type=int) or None
        slug_input = request.form.get("slug", "").strip()
        new_slug = _slugify(slug_input) if slug_input else None
        if new_slug and new_slug != coll.slug:
            existing = Collection.query.filter_by(slug=new_slug).first()
            if existing and existing.id != coll.id:
                flash("That slug is already taken.", "error")
                return redirect(url_for("collections.edit", coll_id=coll.id))
        coll.slug = new_slug
        if "cover_image" in request.files:
            uploaded = _save_cover_image(request.files["cover_image"])
            if uploaded:
                coll.cover_image = uploaded
        if request.form.get("remove_cover") == "1":
            coll.cover_image = ""
        db.session.commit()
        flash("Collection updated.", "success")
        return redirect(url_for("collections.view", coll_id=coll.id))
    return render_template("collections/form.html", collection=coll, categories=categories)


@collections_bp.route("/<int:coll_id>/delete", methods=["POST"])
@login_required
def delete(coll_id):
    coll = Collection.query.get_or_404(coll_id)
    if coll.user_id != current_user.id and not current_user.is_admin:
        flash("Access denied.", "error")
        return redirect(url_for("collections.index"))
    db.session.delete(coll)
    db.session.commit()
    flash("Collection deleted.", "success")
    return redirect(url_for("collections.index"))


@collections_bp.route("/<int:coll_id>/share", methods=["POST"])
@login_required
def share(coll_id):
    coll = Collection.query.get_or_404(coll_id)
    if coll.user_id != current_user.id and not current_user.is_admin:
        flash("Access denied.", "error")
        return redirect(url_for("collections.index"))
    if not coll.share_token:
        coll.share_token = secrets.token_urlsafe(16)
        db.session.commit()
    flash("Public link created.", "success")
    return redirect(url_for("collections.view", coll_id=coll.id))


@collections_bp.route("/<int:coll_id>/unshare", methods=["POST"])
@login_required
def unshare(coll_id):
    coll = Collection.query.get_or_404(coll_id)
    if coll.user_id != current_user.id and not current_user.is_admin:
        flash("Access denied.", "error")
        return redirect(url_for("collections.index"))
    coll.share_token = None
    db.session.commit()
    flash("Public link removed.", "success")
    return redirect(url_for("collections.view", coll_id=coll.id))


@collections_bp.route("/<int:coll_id>/reorder", methods=["POST"])
@login_required
def reorder(coll_id):
    """Reorder recipes within a collection via drag-and-drop."""
    coll = Collection.query.get_or_404(coll_id)
    if coll.user_id != current_user.id and not current_user.is_admin:
        return jsonify({"error": "Access denied"}), 403
    data = request.get_json(silent=True) or {}
    order = data.get("order", [])  # list of recipe IDs in desired order
    if not order:
        return jsonify({"error": "No order provided"}), 400
    # Rebuild the recipes list in the new order
    recipe_map = {r.id: r for r in coll.recipes}
    new_list = []
    for rid in order:
        if rid in recipe_map:
            new_list.append(recipe_map[rid])
    # Clear and re-add in order
    coll.recipes.clear()
    db.session.flush()
    for r in new_list:
        coll.recipes.append(r)
    db.session.commit()
    return jsonify({"ok": True})


# ── Public routes (slug or token) ──

@collections_bp.route("/shared/<token>")
def view_shared(token):
    """Public view for shared collections - no login required."""
    coll = _find_collection_by_token_or_slug(token)
    if not coll or not coll.share_token:
        return "Collection not found.", 404
    all_recipes = coll.get_all_recipes()
    return render_template("collections/shared.html", collection=coll, all_recipes=all_recipes)


@collections_bp.route("/shared/<token>/recipe/<int:recipe_id>")
def view_shared_recipe(token, recipe_id):
    """Public view for a recipe within a shared collection."""
    coll = _find_collection_by_token_or_slug(token)
    if not coll or not coll.share_token:
        return "Collection not found.", 404
    all_recipes = coll.get_all_recipes()
    recipe = Recipe.query.get_or_404(recipe_id)
    if recipe not in all_recipes:
        return "Recipe not found in this collection.", 404
    return render_template("collections/shared_recipe.html", recipe=recipe, collection=coll)


@collections_bp.route("/shared/<token>/recipe/<int:recipe_id>/cook")
def shared_cook_mode(token, recipe_id):
    """Public cook mode for a recipe within a shared collection."""
    coll = _find_collection_by_token_or_slug(token)
    if not coll or not coll.share_token:
        return "Collection not found.", 404
    all_recipes = coll.get_all_recipes()
    recipe = Recipe.query.get_or_404(recipe_id)
    if recipe not in all_recipes:
        return "Recipe not found in this collection.", 404
    return render_template("collections/shared_cook.html", recipe=recipe, collection=coll)


# ── Recipe management ──

@collections_bp.route("/<int:coll_id>/add-recipe", methods=["POST"])
@login_required
def add_recipe(coll_id):
    coll = Collection.query.get_or_404(coll_id)
    if coll.user_id != current_user.id and not current_user.is_admin:
        flash("Access denied.", "error")
        return redirect(url_for("collections.index"))
    recipe_id = request.form.get("recipe_id", type=int)
    recipe = Recipe.query.get_or_404(recipe_id)
    if recipe not in coll.recipes:
        coll.recipes.append(recipe)
        db.session.commit()
        flash(f"Added '{recipe.title}' to collection.", "success")
    else:
        flash("Recipe already in this collection.", "error")
    return redirect(url_for("collections.view", coll_id=coll.id))


@collections_bp.route("/<int:coll_id>/remove-recipe/<int:recipe_id>", methods=["POST"])
@login_required
def remove_recipe(coll_id, recipe_id):
    coll = Collection.query.get_or_404(coll_id)
    if coll.user_id != current_user.id and not current_user.is_admin:
        flash("Access denied.", "error")
        return redirect(url_for("collections.index"))
    recipe = Recipe.query.get_or_404(recipe_id)
    if recipe in coll.recipes:
        coll.recipes.remove(recipe)
        db.session.commit()
        flash("Recipe removed from collection.", "success")
    return redirect(url_for("collections.view", coll_id=coll.id))
