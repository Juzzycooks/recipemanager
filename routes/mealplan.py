import random
import secrets
from datetime import date, timedelta
from flask import Blueprint, render_template, redirect, url_for, flash, request, jsonify, abort
from flask_login import login_required, current_user
from models import db, Recipe, MealPlan, ShoppingListItem, Favorite, SiteSetting

mealplan_bp = Blueprint("mealplan", __name__, url_prefix="/mealplan")


def _get_week_dates(start_date):
    """Get list of 7 dates starting from start_date (Monday)."""
    # Adjust to Monday
    days_since_monday = start_date.weekday()
    monday = start_date - timedelta(days=days_since_monday)
    return [monday + timedelta(days=i) for i in range(7)]


@mealplan_bp.route("/")
@login_required
def index():
    # Get week offset from query param
    offset = request.args.get("week", 0, type=int)
    today = date.today()
    start = today + timedelta(weeks=offset)
    week_dates = _get_week_dates(start)
    
    # Get meal plans for this week
    plans = MealPlan.query.filter(
        MealPlan.user_id == current_user.id,
        MealPlan.date >= week_dates[0],
        MealPlan.date <= week_dates[-1]
    ).all()
    
    # Organize by date and meal type
    plan_map = {}
    for d in week_dates:
        plan_map[d] = {"breakfast": [], "lunch": [], "dinner": [], "snack": []}
    for p in plans:
        if p.date in plan_map:
            plan_map[p.date][p.meal_type].append(p)
    
    recipes = Recipe.query.order_by(Recipe.title).all()
    share_token = _get_share_token(current_user.id)
    share_url = (url_for("mealplan.view_shared", token=share_token, _external=True)
                 if share_token else "")

    return render_template("mealplan/index.html", 
                           share_url=share_url,
                           week_dates=week_dates, 
                           plan_map=plan_map,
                           recipes=recipes,
                           offset=offset,
                           today=today)


@mealplan_bp.route("/add", methods=["POST"])
@login_required
def add():
    recipe_id = request.form.get("recipe_id", type=int)
    date_str = request.form.get("date", "")
    meal_type = request.form.get("meal_type", "dinner")
    
    if not recipe_id or not date_str:
        flash("Pick a recipe and a day to add it to the plan.", "error")
        return redirect(url_for("mealplan.index"))
    
    try:
        plan_date = date.fromisoformat(date_str)
    except ValueError:
        flash("That date isn't valid. Pick a day from the calendar.", "error")
        return redirect(url_for("mealplan.index"))
    
    recipe = Recipe.query.get_or_404(recipe_id)
    
    plan = MealPlan(
        user_id=current_user.id,
        recipe_id=recipe_id,
        date=plan_date,
        meal_type=meal_type
    )
    db.session.add(plan)
    db.session.commit()
    
    flash(f"Added '{recipe.title}' to meal plan.", "success")
    
    # Calculate week offset to return to correct week
    today = date.today()
    days_diff = (plan_date - today).days
    week_offset = days_diff // 7
    
    return redirect(url_for("mealplan.index", week=week_offset))


@mealplan_bp.route("/remove/<int:plan_id>", methods=["POST"])
@login_required
def remove(plan_id):
    plan = MealPlan.query.get_or_404(plan_id)
    if plan.user_id != current_user.id:
        flash("That belongs to someone else, so you can't change it.", "error")
        return redirect(url_for("mealplan.index"))
    
    db.session.delete(plan)
    db.session.commit()
    flash("Removed from meal plan.", "success")
    return redirect(request.referrer or url_for("mealplan.index"))


@mealplan_bp.route("/shopping", methods=["POST"])
@login_required
def generate_shopping_list():
    """Generate shopping list from current week's meal plan."""
    offset = request.form.get("week", 0, type=int)
    today = date.today()
    start = today + timedelta(weeks=offset)
    week_dates = _get_week_dates(start)
    
    plans = MealPlan.query.filter(
        MealPlan.user_id == current_user.id,
        MealPlan.date >= week_dates[0],
        MealPlan.date <= week_dates[-1]
    ).all()
    
    from shopping_utils import add_lines_merged
    added = merged = 0
    for plan in plans:
        recipe = plan.recipe
        if recipe is None:
            continue
        a, m = add_lines_merged(current_user.id, recipe.ingredients.split("\n"),
                                recipe_id=recipe.id)
        added += a
        merged += m

    db.session.commit()
    msg = f"Added {added} ingredients to shopping list."
    if merged:
        msg += f" Combined {merged} duplicates."
    flash(msg, "success")
    return redirect(url_for("shopping.index"))


@mealplan_bp.route("/move/<int:plan_id>", methods=["POST"])
@login_required
def move(plan_id):
    """Move a meal plan entry to a new date/meal_type (drag-and-drop)."""
    plan = MealPlan.query.get_or_404(plan_id)
    if plan.user_id != current_user.id:
        return jsonify({"error": "Access denied"}), 403
    
    data = request.get_json(silent=True) or {}
    new_date = data.get("date")
    new_meal_type = data.get("meal_type")
    
    if new_date:
        try:
            plan.date = date.fromisoformat(new_date)
        except ValueError:
            return jsonify({"error": "Invalid date"}), 400
    if new_meal_type and new_meal_type in ("breakfast", "lunch", "dinner", "snack"):
        plan.meal_type = new_meal_type
    
    db.session.commit()
    return jsonify({"ok": True})


@mealplan_bp.route("/auto-generate", methods=["POST"])
@login_required
def auto_generate():
    """Auto-generate a week of meals based on user preferences."""
    offset = request.form.get("week", 0, type=int)
    meal_types = request.form.getlist("meal_types") or ["dinner"]
    
    today = date.today()
    start = today + timedelta(weeks=offset)
    week_dates = _get_week_dates(start)
    
    # Gather candidate recipes: prefer favorites, then all
    fav_ids = [f.recipe_id for f in Favorite.query.filter_by(user_id=current_user.id).all()]
    fav_recipes = Recipe.query.filter(Recipe.id.in_(fav_ids)).all() if fav_ids else []
    all_recipes = Recipe.query.all()
    
    if not all_recipes:
        flash("Add a few recipes first, then the planner can fill your week.", "error")
        return redirect(url_for("mealplan.index", week=offset))
    
    # Use favorites if we have enough, otherwise mix in all recipes
    pool = fav_recipes if len(fav_recipes) >= 7 else all_recipes
    
    added = 0
    for d in week_dates:
        for mt in meal_types:
            # Skip if already has a plan for this slot
            existing = MealPlan.query.filter_by(
                user_id=current_user.id, date=d, meal_type=mt
            ).first()
            if existing:
                continue
            
            recipe = random.choice(pool)
            plan = MealPlan(
                user_id=current_user.id,
                recipe_id=recipe.id,
                date=d,
                meal_type=mt
            )
            db.session.add(plan)
            added += 1
    
    db.session.commit()
    flash(f"Auto-generated {added} meals for the week.", "success")
    return redirect(url_for("mealplan.index", week=offset))



# ── Public read-only sharing ──
# Tokens live in SiteSetting under "mealplan_share_<user_id>" (no schema change).

_SHARE_PREFIX = "mealplan_share_"


def _get_share_token(user_id):
    row = SiteSetting.query.filter_by(key=f"{_SHARE_PREFIX}{user_id}").first()
    return row.value if row and row.value else None


def _user_for_token(token):
    if not token or len(token) > 100:
        return None
    row = SiteSetting.query.filter(SiteSetting.key.like(f"{_SHARE_PREFIX}%"),
                                   SiteSetting.value == token).first()
    if not row:
        return None
    try:
        return int(row.key[len(_SHARE_PREFIX):])
    except ValueError:
        return None


@mealplan_bp.route("/share", methods=["POST"])
@login_required
def share():
    """Create the public link for this user's plan, or keep the existing one."""
    if not _get_share_token(current_user.id):
        db.session.add(SiteSetting(key=f"{_SHARE_PREFIX}{current_user.id}",
                                   value=secrets.token_urlsafe(16)))
        db.session.commit()
        flash("Public link created. Anyone with it can see your meal plan titles.", "success")
    return redirect(request.referrer or url_for("mealplan.index"))


@mealplan_bp.route("/unshare", methods=["POST"])
@login_required
def unshare():
    row = SiteSetting.query.filter_by(key=f"{_SHARE_PREFIX}{current_user.id}").first()
    if row:
        db.session.delete(row)
        db.session.commit()
        flash("Stopped sharing your meal plan. The old link no longer works.", "success")
    return redirect(request.referrer or url_for("mealplan.index"))


@mealplan_bp.route("/shared/<token>")
def view_shared(token):
    """Public, read-only week view. Unknown tokens 404."""
    user_id = _user_for_token(token)
    if user_id is None:
        abort(404)
    offset = max(-520, min(520, request.args.get("week", 0, type=int)))
    week_dates = _get_week_dates(date.today() + timedelta(weeks=offset))
    plans = MealPlan.query.filter(
        MealPlan.user_id == user_id,
        MealPlan.date >= week_dates[0],
        MealPlan.date <= week_dates[-1]).all()
    plan_map = {d: {"breakfast": [], "lunch": [], "dinner": [], "snack": []} for d in week_dates}
    for p in plans:
        if p.date in plan_map and p.meal_type in plan_map[p.date] and p.recipe is not None:
            plan_map[p.date][p.meal_type].append(p)
    return render_template("mealplan/shared.html", token=token, week_dates=week_dates,
                           plan_map=plan_map, offset=offset, today=date.today())
