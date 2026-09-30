from urllib.parse import quote_plus
from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_required, current_user
from models import db, ShoppingListItem, Recipe, SiteSetting
from shopping_utils import add_lines_merged, group_by_aisle

shopping_bp = Blueprint("shopping", __name__, url_prefix="/shopping")

DEFAULT_STORE_NAME = "Woolworths"
DEFAULT_STORE_URL = "https://www.woolworths.com.au/shop/search/products?searchTerm={q}"
MAX_PICKED_ITEMS = 200
MAX_ITEM_LEN = 300


def _store_settings():
    """Return (store_name, store_search_url); an empty URL means no link."""
    rows = {r.key: r.value for r in SiteSetting.query.filter(
        SiteSetting.key.in_(["store_name", "store_search_url"])).all()}
    name = (rows.get("store_name") or "").strip() or DEFAULT_STORE_NAME
    url = rows["store_search_url"] if "store_search_url" in rows else DEFAULT_STORE_URL
    return name, (url or "").strip()


def store_link(template, item_name):
    """Build a store search URL, URL-encoding the item name into {q}."""
    if not template:
        return ""
    return template.replace("{q}", quote_plus(item_name or ""))


@shopping_bp.route("/")
@login_required
def index():
    items = (ShoppingListItem.query
             .filter_by(user_id=current_user.id)
             .order_by(ShoppingListItem.checked, ShoppingListItem.created_at.desc())
             .all())
    unchecked = [i for i in items if not i.checked]
    checked = [i for i in items if i.checked]
    aisle_groups = group_by_aisle(unchecked)
    store_name, store_url = _store_settings()
    return render_template("shopping/index.html", unchecked=unchecked,
                           checked=checked, quote_plus=quote_plus,
                           aisle_groups=aisle_groups, store_name=store_name,
                           store_url=store_url,
                           store_link=lambda n: store_link(store_url, n))


@shopping_bp.route("/add", methods=["POST"])
@login_required
def add_item():
    name = request.form.get("name", "").strip()
    if name:
        added, merged = add_lines_merged(current_user.id, [name])
        db.session.commit()
        if merged:
            flash("Combined with an item already on your list.", "success")
    return redirect(url_for("shopping.index"))


@shopping_bp.route("/recipe/<int:recipe_id>", methods=["POST"])
@login_required
def add_recipe_to_list(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    lines = recipe.ingredients.split("\n")
    added, merged = add_lines_merged(current_user.id, lines, recipe_id=recipe.id)
    db.session.commit()
    msg = f"Added {added} ingredients from '{recipe.title}' to your shopping list."
    if merged:
        msg += f" Combined {merged} with items already on the list."
    flash(msg, "success")
    return redirect(url_for("shopping.index"))


@shopping_bp.route("/add-selected", methods=["POST"])
@login_required
def add_selected():
    """Add only the ingredient lines picked on the recipe page."""
    recipe = Recipe.query.get_or_404(request.form.get("recipe_id", type=int) or 0)
    raw = request.form.getlist("items")
    if len(raw) > MAX_PICKED_ITEMS:
        flash(f"That is a lot of items at once. Pick {MAX_PICKED_ITEMS} or fewer and try again.", "error")
        return redirect(url_for("recipes.view", recipe_id=recipe.id))
    lines = []
    for value in raw:
        value = value.strip()
        if not value or value.startswith("# "):
            continue
        lines.append(value[:MAX_ITEM_LEN])
    if not lines:
        flash("Nothing was selected, so nothing was added. Tick at least one ingredient and try again.", "error")
        return redirect(url_for("recipes.view", recipe_id=recipe.id))
    added, merged = add_lines_merged(current_user.id, lines, recipe_id=recipe.id)
    db.session.commit()
    msg = f"Added {added} ingredients from \u201c{recipe.title}\u201d to your shopping list."
    if merged:
        msg += f" Combined {merged} with items already on the list."
    flash(msg, "success")
    return redirect(url_for("shopping.index"))


@shopping_bp.route("/toggle/<int:item_id>", methods=["POST"])
@login_required
def toggle(item_id):
    item = ShoppingListItem.query.get_or_404(item_id)
    if item.user_id != current_user.id:
        flash("That belongs to someone else, so you can't change it.", "error")
        return redirect(url_for("shopping.index"))
    item.checked = not item.checked
    db.session.commit()
    return redirect(url_for("shopping.index"))


@shopping_bp.route("/remove/<int:item_id>", methods=["POST"])
@login_required
def remove(item_id):
    item = ShoppingListItem.query.get_or_404(item_id)
    if item.user_id != current_user.id:
        flash("That belongs to someone else, so you can't change it.", "error")
        return redirect(url_for("shopping.index"))
    db.session.delete(item)
    db.session.commit()
    return redirect(url_for("shopping.index"))


@shopping_bp.route("/clear", methods=["POST"])
@login_required
def clear():
    ShoppingListItem.query.filter_by(user_id=current_user.id).delete()
    db.session.commit()
    flash("Shopping list cleared.", "success")
    return redirect(url_for("shopping.index"))


@shopping_bp.route("/clear-checked", methods=["POST"])
@login_required
def clear_checked():
    ShoppingListItem.query.filter_by(user_id=current_user.id, checked=True).delete()
    db.session.commit()
    return redirect(url_for("shopping.index"))