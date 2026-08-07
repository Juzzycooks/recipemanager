"""Simple JSON API for external integrations (e.g., PantryTracker).

Provides read-only access to recipes for ingredient matching and suggestions.
Authentication: requires X-API-Key header matching the auto-generated key
stored in /app/data/.api_key. The key is created on first startup and
displayed in the admin panel for copying to PantryTracker.
"""

import os
import secrets
from functools import wraps
from flask import Blueprint, jsonify, request, abort

from models import db, Recipe

api_bp = Blueprint("api", __name__, url_prefix="/api")


def _get_api_key():
    """Get or generate the API key. Persists to /app/data/.api_key."""
    data_dir = os.environ.get("DATA_DIR", "/app/data")
    key_path = os.path.join(data_dir, ".api_key")
    
    # Check env var first (manual override)
    env_key = os.environ.get("PANTRY_API_KEY", "")
    if env_key:
        return env_key
    
    # Read from file or generate
    if os.path.exists(key_path):
        with open(key_path, "r") as f:
            return f.read().strip()
    
    # Generate new key
    key = secrets.token_urlsafe(32)
    os.makedirs(data_dir, exist_ok=True)
    with open(key_path, "w") as f:
        f.write(key)
    return key


def _check_api_key(f):
    """Verify API key only if PANTRY_API_KEY env var is set.
    If no key is configured, the API is open (home network trust model).
    """
    @wraps(f)
    def decorated(*args, **kwargs):
        api_key = os.environ.get("PANTRY_API_KEY", "")
        if api_key:
            provided = request.headers.get("X-API-Key", "")
            if provided != api_key:
                return jsonify({"error": "UNAUTHORIZED", "message": "Invalid or missing API key"}), 401
        return f(*args, **kwargs)
    return decorated


@api_bp.route("/key", methods=["GET"])
def show_api_key():
    """Show the API key (only accessible from localhost / for admin setup).
    
    This endpoint is intentionally unprotected so you can retrieve the key
    on first setup. Access it from the server: curl http://localhost:5000/api/key
    """
    # Only allow from localhost or if user is authenticated as admin
    remote = request.remote_addr
    if remote not in ("127.0.0.1", "::1", "172.17.0.1"):
        # Check if user is logged in as admin via session
        from flask_login import current_user
        if not current_user.is_authenticated or not current_user.is_admin:
            abort(403)
    
    key = _get_api_key()
    return jsonify({"api_key": key, "usage": "Set this as RECIPEMANAGER_API_KEY in your PantryTracker container"})


@api_bp.route("/recipes", methods=["GET"])
@_check_api_key
def list_recipes():
    """List all recipes as JSON.
    
    Returns: [{id, title, ingredients, description, prep_time, cook_time, servings, image_url}]
    """
    recipes = Recipe.query.order_by(Recipe.title).all()
    return jsonify([
        {
            "id": r.id,
            "title": r.title,
            "ingredients": r.ingredients,
            "description": r.description,
            "prep_time": r.prep_time,
            "cook_time": r.cook_time,
            "servings": r.servings,
            "image_url": r.image_url,
        }
        for r in recipes
    ])


@api_bp.route("/recipes/<int:recipe_id>", methods=["GET"])
@_check_api_key
def get_recipe(recipe_id):
    """Get a single recipe by ID.
    
    Returns: {id, title, ingredients, instructions, description, prep_time, cook_time, servings, image_url}
    """
    recipe = Recipe.query.get_or_404(recipe_id)
    return jsonify({
        "id": recipe.id,
        "title": recipe.title,
        "ingredients": recipe.ingredients,
        "instructions": recipe.instructions,
        "description": recipe.description,
        "prep_time": recipe.prep_time,
        "cook_time": recipe.cook_time,
        "servings": recipe.servings,
        "image_url": recipe.image_url,
    })
