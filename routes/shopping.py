from urllib.parse import quote_plus
from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_required, current_user
from models import db, ShoppingListItem, Recipe
from shopping_utils import add_lines_merged, group_by_aisle

shopping_bp = Blueprint("shopping", __name__, url_prefix="/shopping")


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
    return render_template("shopping/index.html", unchecked=unchecked,
                           checked=checked, quote_plus=quote_plus,
                           aisle_groups=aisle_groups)


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


@shopping_bp.route("/toggle/<int:item_id>", methods=["POST"])
@login_required
def toggle(item_id):
    item = ShoppingListItem.query.get_or_404(item_id)
    if item.user_id != current_user.id:
        flash("Access denied.", "error")
        return redirect(url_for("shopping.index"))
    item.checked = not item.checked
    db.session.commit()
    return redirect(url_for("shopping.index"))


@shopping_bp.route("/remove/<int:item_id>", methods=["POST"])
@login_required
def remove(item_id):
    item = ShoppingListItem.query.get_or_404(item_id)
    if item.user_id != current_user.id:
        flash("Access denied.", "error")
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