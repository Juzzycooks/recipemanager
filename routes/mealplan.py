import random
from datetime import date, timedelta
from flask import Blueprint, render_template, redirect, url_for, flash, request, jsonify
from flask_login import login_required, current_user
from models import db, Recipe, MealPlan, ShoppingListItem, Favorite

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
    
    return render_template("mealplan/index.html", 
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
        flash("Recipe and date are required.", "error")
        return redirect(url_for("mealplan.index"))
    
    try:
        plan_date = date.fromisoformat(date_str)
    except ValueError:
        flash("Invalid date.", "error")
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
        flash("Access denied.", "error")
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
        flash("No recipes available to generate a meal plan.", "error")
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
