"""JSON API v1 for native and third-party clients (see API.md).

Auth is a bearer token from POST /api/v1/auth/login (Authorization: Bearer <token>).
Cookie sessions are never read here, so the blueprint is exempt from CSRF.
Errors are always {"error": {"code": ..., "message": ...}}.
"""
import hashlib
import io
import re
import secrets
from datetime import date, datetime, timedelta, timezone
from functools import wraps

from flask import Blueprint, current_app, g, jsonify, request, url_for
from werkzeug.exceptions import HTTPException

from images import delete_image
from models import (
    ApiToken, Calculator, Category, Collection, Comment, CookLog, ExtraShare, Favorite,
    MealPlan, Rating, Recipe, ShoppingListItem, SiteSetting, User, db,
)

api_v1_bp = Blueprint("api_v1", __name__, url_prefix="/api/v1")

MAX_PER_PAGE = 100
MAX_PICKED_ITEMS = 200
MAX_ITEM_LEN = 300
MAX_BULK_URLS = 50
MAX_PLAN_DAYS = 92
TOKEN_TOUCH_INTERVAL = timedelta(hours=1)


# ── Errors, auth, request helpers ──

class ApiError(Exception):
    def __init__(self, code, message, status=400):
        super().__init__(message)
        self.code, self.message, self.status = code, message, status


@api_v1_bp.errorhandler(ApiError)
def _handle_api_error(e):
    resp = jsonify(error={"code": e.code, "message": e.message})
    resp.status_code = e.status
    if e.status == 401:
        resp.headers["WWW-Authenticate"] = "Bearer"
    return resp


_HTTP_CODES = {400: "bad_request", 401: "unauthorized", 403: "forbidden", 404: "not_found",
               405: "method_not_allowed", 413: "too_large", 429: "rate_limited"}


def json_http_error(e):
    """App-level handler: JSON bodies for errors under /api/v1, default behaviour elsewhere."""
    if not request.path.startswith("/api/v1/") or (e.code or 500) < 400:
        return e
    resp = jsonify(error={"code": _HTTP_CODES.get(e.code, "error"), "message": e.description or e.name})
    resp.status_code = e.code or 500
    return resp


def init_app(app, csrf):
    app.register_blueprint(api_v1_bp)
    csrf.exempt(api_v1_bp)
    app.register_error_handler(HTTPException, json_http_error)


def _hash(raw):
    return hashlib.sha256(raw.encode()).hexdigest()


def _now():
    return datetime.now(timezone.utc)


def _aware(dt):
    return dt.replace(tzinfo=timezone.utc) if dt is not None and dt.tzinfo is None else dt


def _iso(dt):
    return _aware(dt).isoformat() if dt else None


def api_auth(admin=False):
    def deco(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            header = request.headers.get("Authorization", "")
            if header[:7].lower() != "bearer ":
                raise ApiError("unauthorized", "Send an Authorization: Bearer <token> header.", 401)
            token = ApiToken.query.filter_by(token_hash=_hash(header[7:].strip())).first()
            if token is None:
                raise ApiError("unauthorized", "That token is invalid or has been revoked.", 401)
            last = _aware(token.last_used_at)
            if last is None or _now() - last > TOKEN_TOUCH_INTERVAL:
                token.last_used_at = _now()
                db.session.commit()
            g.api_user, g.api_token = token.user, token
            if admin and not token.user.is_admin:
                raise ApiError("forbidden", "Admins only.", 403)
            return f(*args, **kwargs)
        return wrapper
    return deco


def me():
    return g.api_user


class Body:
    """Request fields from a JSON object or a form / multipart body."""

    def __init__(self):
        self.json = None
        if request.is_json:
            data = request.get_json(silent=True)
            if not isinstance(data, dict):
                raise ApiError("bad_request", "The request body must be a JSON object.")
            self.json = data

    def has(self, key):
        return key in (self.json if self.json is not None else request.form)

    def get(self, key, default=None):
        return self.json.get(key, default) if self.json is not None else request.form.get(key, default)

    def text(self, key, default=""):
        value = self.get(key, default)
        return "" if value is None else str(value).strip()

    def list(self, key):
        if self.json is not None:
            value = self.json.get(key)
            return value if isinstance(value, list) else ([] if value is None else [value])
        return request.form.getlist(key)

    def flag(self, key, default=False):
        if not self.has(key):
            return default
        return self.get(key) in (True, 1, "1", "true", "True", "on", "yes")

    def integer(self, key):
        value = self.get(key)
        if isinstance(value, bool):
            return None
        try:
            return int(value)
        except (TypeError, ValueError):
            return None


def _no_content():
    return "", 204


def _owner_or_admin(obj):
    if obj.user_id != me().id and not me().is_admin:
        raise ApiError("forbidden", "That belongs to someone else, so you can't change it.", 403)


def _paginate(query, serialise):
    page = max(request.args.get("page", 1, type=int), 1)
    per_page = min(max(request.args.get("per_page", 24, type=int), 1), MAX_PER_PAGE)
    p = query.paginate(page=page, per_page=per_page, error_out=False)
    return jsonify(items=[serialise(i) for i in p.items], page=page, per_page=per_page,
                   total=p.total, pages=p.pages)


def _parse_date(value, field="date"):
    try:
        return date.fromisoformat(str(value))
    except ValueError:
        raise ApiError("validation", f"{field} must be a date like 2026-10-31.", 422)


# ── Serialisers ──

def _image(url):
    return current_app.jinja_env.filters["recipe_image"](url or "")


def _thumb(url):
    return current_app.jinja_env.filters["recipe_thumb"](url or "")


def _upload_url(filename):
    return f"/admin/uploads/{filename}" if filename else ""


def _sections(text):
    """Split '# Heading' section markers: [{heading|None, lines[]}]."""
    out, cur = [], {"heading": None, "lines": []}
    for raw in (text or "").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("# "):
            if cur["lines"] or cur["heading"]:
                out.append(cur)
            cur = {"heading": line[2:].strip(), "lines": []}
        else:
            cur["lines"].append(line)
    if cur["lines"] or cur["heading"]:
        out.append(cur)
    return out


def _user_brief(u):
    return {"id": u.id, "username": u.username} if u else None


def _user_full(u):
    return {"id": u.id, "username": u.username, "email": u.email or "", "is_admin": bool(u.is_admin),
            "created_at": _iso(u.created_at)}


def _recipe_brief(r):
    """Enough for a card: no per-user data."""
    return {"id": r.id, "title": r.title, "description": r.description or "",
            "prep_time": r.prep_time or "", "cook_time": r.cook_time or "", "servings": r.servings or "",
            "image_url": _image(r.image_url), "thumb_url": _thumb(r.image_url)}


def _recipe_summary(r, fav_ids=None):
    if fav_ids is None:
        fav_ids = {f.recipe_id for f in Favorite.query.filter_by(user_id=me().id).all()}
    avg = r.avg_rating()
    out = _recipe_brief(r)
    out.update(categories=[{"id": c.id, "name": c.name} for c in r.categories],
               is_favorite=r.id in fav_ids,
               avg_rating=round(avg, 2) if avg is not None else None, rating_count=len(r.ratings),
               author=_user_brief(r.author), created_at=_iso(r.created_at), updated_at=_iso(r.updated_at))
    return out


def _comment(c):
    return {"id": c.id, "text": c.text, "created_at": _iso(c.created_at), "user": _user_brief(c.user),
            "can_delete": c.user_id == me().id or bool(me().is_admin)}


def _recipe_detail(r):
    from nutrition import estimate_recipe
    out = _recipe_summary(r)
    rating = Rating.query.filter_by(user_id=me().id, recipe_id=r.id).first()
    logs = CookLog.query.filter_by(user_id=me().id, recipe_id=r.id).order_by(CookLog.cooked_at.desc()).all()
    comments = Comment.query.filter_by(recipe_id=r.id).order_by(Comment.created_at.desc()).all()
    mine = Collection.query.filter_by(user_id=me().id).order_by(Collection.name).all()
    out.update(
        ingredients=r.ingredients or "", instructions=r.instructions or "", notes=r.notes or "",
        source_url=r.source_url or "",
        ingredient_sections=_sections(r.ingredients), instruction_sections=_sections(r.instructions),
        share_url=(url_for("recipes.view_shared", token=r.share_token, _external=True)
                   if r.share_token else None),
        my_rating=rating.score if rating else None,
        made_count=len(logs), last_made=_iso(logs[0].cooked_at) if logs else None,
        nutrition=estimate_recipe(r.ingredients, r.servings),
        collections=[{"id": c.id, "name": c.name} for c in mine if r in c.recipes],
        comments=[_comment(c) for c in comments],
        can_edit=r.user_id == me().id or bool(me().is_admin))
    return out


def _recipe_public(r):
    """What an anonymous visitor may see: no notes, ratings or comments."""
    show_author = _setting("public_show_author") == "1"
    out = _recipe_brief(r)
    out.update(ingredients=r.ingredients or "", instructions=r.instructions or "",
               source_url=r.source_url or "",
               ingredient_sections=_sections(r.ingredients), instruction_sections=_sections(r.instructions),
               categories=[c.name for c in r.categories],
               author=r.author.username if show_author and r.author else None)
    return out


def _collection(c, detail=False):
    out = {"id": c.id, "name": c.name, "description": c.description or "", "slug": c.slug,
           "cover_url": _upload_url(c.cover_image),
           "category": {"id": c.category.id, "name": c.category.name} if c.category else None,
           "share_url": (url_for("collections.view_shared", token=c.public_url_token, _external=True)
                         if c.share_token else None),
           "recipe_count": len(c.get_all_recipes()), "created_at": _iso(c.created_at)}
    if detail:
        fav_ids = {f.recipe_id for f in Favorite.query.filter_by(user_id=me().id).all()}
        out["recipes"] = [_recipe_summary(r, fav_ids) for r in c.get_all_recipes()]
        out["manual_recipe_ids"] = [r.id for r in c.recipes]
    return out


def _plan_entry(p):
    return {"id": p.id, "date": p.date.isoformat(), "meal_type": p.meal_type,
            "sort_order": p.sort_order or 0, "recipe": _recipe_brief(p.recipe)}


def _setting(key, default=""):
    row = SiteSetting.query.filter_by(key=key).first()
    return row.value if row and row.value is not None else default


# ── Public: site info and sign-in ──

@api_v1_bp.route("/site")
def site():
    """Public: what a client needs before signing in."""
    from ocr import ocr_available
    from routes.shopping import _store_settings
    store_name, store_url = _store_settings()
    return jsonify(api_version=1, name=_setting("site_name"), logo_url=_upload_url(_setting("logo_file")),
                   setup_required=User.query.count() == 0, ocr_available=bool(ocr_available()),
                   store={"name": store_name, "search_url": store_url})


def _issue_token(user, name):
    raw = "rm_" + secrets.token_urlsafe(32)
    db.session.add(ApiToken(user_id=user.id, token_hash=_hash(raw), name=(name or "")[:100]))
    db.session.commit()
    return raw


@api_v1_bp.route("/auth/setup", methods=["POST"])
def setup():
    """Create the first (admin) account. Only works while no users exist."""
    from routes.auth import _validate_password, is_valid_email
    if User.query.count() > 0:
        raise ApiError("conflict", "Setup is already done.", 409)
    b = Body()
    username, password, email = b.text("username"), b.get("password") or "", b.text("email")
    if not username or not password:
        raise ApiError("validation", "Enter a username and a password.", 422)
    problem = _validate_password(password)
    if problem:
        raise ApiError("validation", problem, 422)
    if email and not is_valid_email(email):
        raise ApiError("validation", "That email address doesn't look right.", 422)
    user = User(username=username, email=email, is_admin=True)
    user.set_password(password)
    db.session.add(user)
    db.session.commit()
    return jsonify(token=_issue_token(user, b.text("device_name")), user=_user_full(user)), 201


@api_v1_bp.route("/auth/login", methods=["POST"])
def login():
    from routes.auth import _clear_attempts, _is_rate_limited, _record_attempt
    if User.query.count() == 0:
        raise ApiError("setup_required", "No accounts yet. Create the admin with POST /api/v1/auth/setup.", 409)
    b = Body()
    username, password = b.text("username"), b.get("password") or ""
    ip = request.remote_addr or "unknown"
    if _is_rate_limited(ip, username):
        raise ApiError("rate_limited", "Too many tries. Wait a few minutes, then try again.", 429)
    user = User.query.filter_by(username=username).first()
    if not (user and user.check_password(password)):
        _record_attempt(ip, username)
        raise ApiError("invalid_credentials", "Invalid username or password.", 401)
    _clear_attempts(ip, username)
    return jsonify(token=_issue_token(user, b.text("device_name")), user=_user_full(user))


@api_v1_bp.route("/auth/logout", methods=["POST"])
@api_auth()
def logout():
    db.session.delete(g.api_token)
    db.session.commit()
    return _no_content()


@api_v1_bp.route("/auth/tokens")
@api_auth()
def list_tokens():
    tokens = ApiToken.query.filter_by(user_id=me().id).order_by(ApiToken.created_at.desc()).all()
    return jsonify(items=[{"id": t.id, "name": t.name, "created_at": _iso(t.created_at),
                           "last_used_at": _iso(t.last_used_at), "current": t.id == g.api_token.id}
                          for t in tokens])


@api_v1_bp.route("/auth/tokens/<int:token_id>", methods=["DELETE"])
@api_auth()
def revoke_token(token_id):
    token = ApiToken.query.filter_by(id=token_id, user_id=me().id).first_or_404()
    db.session.delete(token)
    db.session.commit()
    return _no_content()


@api_v1_bp.route("/auth/forgot-password", methods=["POST"])
def forgot_password():
    """Always answers the same way, whether or not the address belongs to an account."""
    from routes.auth import (_hash_token, _is_rate_limited, _record_attempt, is_valid_email)
    from models import PasswordResetToken
    ip = request.remote_addr or "unknown"
    if _is_rate_limited(ip):
        raise ApiError("rate_limited", "Too many tries. Wait a few minutes, then try again.", 429)
    _record_attempt(ip)
    email = Body().text("email")
    if current_app.config.get("SMTP_HOST") and is_valid_email(email):
        user = User.query.filter_by(email=email).first()
        if user:
            token = secrets.token_urlsafe(32)
            db.session.add(PasswordResetToken(user_id=user.id, token_hash=_hash_token(token)))
            db.session.commit()
            from mailer import send_password_reset_email
            send_password_reset_email(user.email, user.username,
                                      url_for("auth.reset_password", token=token, _external=True))
    return jsonify(message="If an account exists with that email, a reset link has been sent.")


# ── Me ──

@api_v1_bp.route("/me")
@api_auth()
def get_me():
    return jsonify(_user_full(me()))


@api_v1_bp.route("/me", methods=["PATCH"])
@api_auth()
def update_me():
    from routes.auth import is_valid_email
    b = Body()
    if b.has("email"):
        email = b.text("email")
        if email and not is_valid_email(email):
            raise ApiError("validation", "That email address doesn't look right.", 422)
        me().email = email
        db.session.commit()
    return jsonify(_user_full(me()))


@api_v1_bp.route("/me", methods=["DELETE"])
@api_auth()
def delete_me():
    """Delete your own account (App Store rule 5.1.1(v)). Needs your password. Like an admin deleting a user, this
    removes the recipes you added, your ratings, comments, collections, meal plan and shopping list. The last admin
    can't do it, since the server would be left with nobody to manage it."""
    if not me().check_password(Body().get("password") or ""):
        raise ApiError("invalid_credentials", "That isn't your password.", 403)
    if me().is_admin and User.query.filter_by(is_admin=True).count() <= 1:
        raise ApiError("validation", "You're the only admin. Make someone else an admin before deleting your account.", 422)
    user = me()
    ShoppingListItem.query.filter_by(user_id=user.id).delete()
    db.session.delete(user)   # ORM delete so the cascades fire (tokens, recipes, ratings, ...)
    db.session.commit()
    return _no_content()


@api_v1_bp.route("/me/password", methods=["POST"])
@api_auth()
def change_password():
    from routes.auth import _validate_password
    b = Body()
    if not me().check_password(b.get("current_password") or ""):
        raise ApiError("invalid_credentials", "That isn't your current password.", 403)
    new_pw = b.get("new_password") or ""
    problem = _validate_password(new_pw)
    if problem:
        raise ApiError("validation", problem, 422)
    me().set_password(new_pw)
    # Sign out every other device
    ApiToken.query.filter(ApiToken.user_id == me().id, ApiToken.id != g.api_token.id).delete()
    db.session.commit()
    return _no_content()


# ── Categories ──

@api_v1_bp.route("/categories")
@api_auth()
def list_categories():
    return jsonify(items=[{"id": c.id, "name": c.name} for c in Category.query.order_by(Category.name).all()])


@api_v1_bp.route("/categories", methods=["POST"])
@api_auth(admin=True)
def create_category():
    name = Body().text("name")[:100]
    if not name:
        raise ApiError("validation", "Give the category a name.", 422)
    if Category.query.filter_by(name=name).first():
        raise ApiError("conflict", "That category already exists.", 409)
    cat = Category(name=name)
    db.session.add(cat)
    db.session.commit()
    return jsonify(id=cat.id, name=cat.name), 201


@api_v1_bp.route("/categories/<int:cat_id>", methods=["DELETE"])
@api_auth(admin=True)
def delete_category(cat_id):
    db.session.delete(Category.query.get_or_404(cat_id))
    db.session.commit()
    return _no_content()


# ── Recipes ──

_SORTS = {"newest": lambda: Recipe.created_at.desc(), "oldest": lambda: Recipe.created_at.asc(),
          "title_az": lambda: Recipe.title.asc(), "title_za": lambda: Recipe.title.desc()}


def _accessible_collection(coll_id):
    coll = db.session.get(Collection, coll_id)
    if coll is None or (coll.user_id != me().id and not me().is_admin):
        raise ApiError("not_found", "No such collection.", 404)
    return coll


@api_v1_bp.route("/recipes")
@api_auth()
def list_recipes():
    search = request.args.get("q", "").strip()
    ingredient = request.args.get("ingredient", "").strip()
    query = Recipe.query
    if search:
        query = query.filter(db.or_(Recipe.title.ilike(f"%{search}%"), Recipe.ingredients.ilike(f"%{search}%")))
    if ingredient:
        query = query.filter(Recipe.ingredients.ilike(f"%{ingredient}%"))
    for cid in request.args.getlist("cat", type=int):
        query = query.filter(Recipe.categories.any(Category.id == cid))
    coll_id = request.args.get("collection", type=int)
    if coll_id:
        query = query.filter(Recipe.id.in_([r.id for r in _accessible_collection(coll_id).get_all_recipes()]))
    fav_ids = {f.recipe_id for f in Favorite.query.filter_by(user_id=me().id).all()}
    if request.args.get("favorites") in ("1", "true"):
        query = query.filter(Recipe.id.in_(fav_ids))
    query = query.order_by(_SORTS.get(request.args.get("sort"), _SORTS["newest"])(), Recipe.id.desc())
    return _paginate(query, lambda r: _recipe_summary(r, fav_ids))


@api_v1_bp.route("/recipes/recent")
@api_auth()
def recently_cooked():
    from routes.recipes import _recently_cooked
    fav_ids = {f.recipe_id for f in Favorite.query.filter_by(user_id=me().id).all()}
    limit = min(max(request.args.get("limit", 6, type=int), 1), 50)
    items = []
    for recipe, label in _recently_cooked(me().id, limit=limit):
        item = _recipe_summary(recipe, fav_ids)
        item["cooked"] = label
        items.append(item)
    return jsonify(items=items)


@api_v1_bp.route("/recipes/random")
@api_auth()
def random_recipe():
    import random
    query = Recipe.query
    cat_id = request.args.get("cat", type=int)
    if cat_id:
        query = query.filter(Recipe.categories.any(Category.id == cat_id))
    if request.args.get("favorites") in ("1", "true"):
        query = query.filter(Recipe.id.in_([f.recipe_id for f in Favorite.query.filter_by(user_id=me().id)]))
    recipes = query.all()
    if not recipes:
        raise ApiError("not_found", "No recipes match.", 404)
    return jsonify(_recipe_detail(random.choice(recipes)))


@api_v1_bp.route("/recipes/<int:recipe_id>")
@api_auth()
def get_recipe(recipe_id):
    return jsonify(_recipe_detail(Recipe.query.get_or_404(recipe_id)))


_TEXT_FIELDS = ("title", "description", "ingredients", "instructions", "prep_time", "cook_time",
                "servings", "source_url", "notes")
_FIELD_LIMITS = {"title": 200, "prep_time": 50, "cook_time": 50, "servings": 50, "source_url": 500}
_IMAGE_NAME_RE = re.compile(r"^[\w.\-]+$")


def _store_image(file):
    from routes.recipes import _save_uploaded_image
    name = _save_uploaded_image(file)
    if not name:
        raise ApiError("validation", "That file isn't a valid image.", 422)
    return name


def _apply_recipe_fields(recipe, b):
    for key in _TEXT_FIELDS:
        if b.has(key):
            setattr(recipe, key, b.text(key)[:_FIELD_LIMITS.get(key, 10 ** 9)])
    if not recipe.title:
        raise ApiError("validation", "A recipe needs a title.", 422)
    if b.has("category_ids"):
        cats = []
        for raw in b.list("category_ids"):
            cat = db.session.get(Category, raw) if isinstance(raw, int) else (
                db.session.get(Category, int(raw)) if str(raw).isdigit() else None)
            if cat is None:
                raise ApiError("validation", f"Unknown category {raw}.", 422)
            cats.append(cat)
        recipe.categories = cats
    upload = request.files.get("image_file")
    if upload and upload.filename:
        recipe.image_url = _store_image(upload)
    elif b.has("image_url"):
        url = b.text("image_url")
        if url and not (url.lower().startswith(("http://", "https://")) or _IMAGE_NAME_RE.match(url)):
            raise ApiError("validation", "image_url must be an http(s) link or empty.", 422)
        recipe.image_url = url[:500]


@api_v1_bp.route("/recipes", methods=["POST"])
@api_auth()
def create_recipe():
    recipe = Recipe(title="", ingredients="", instructions="", user_id=me().id)
    _apply_recipe_fields(recipe, Body())
    db.session.add(recipe)
    db.session.commit()
    return jsonify(_recipe_detail(recipe)), 201


@api_v1_bp.route("/recipes/<int:recipe_id>", methods=["PATCH"])
@api_auth()
def update_recipe(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    _owner_or_admin(recipe)
    _apply_recipe_fields(recipe, Body())
    db.session.commit()
    return jsonify(_recipe_detail(recipe))


@api_v1_bp.route("/recipes/<int:recipe_id>", methods=["DELETE"])
@api_auth()
def delete_recipe(recipe_id):
    from routes.recipes import trash_recipe
    recipe = Recipe.query.get_or_404(recipe_id)
    _owner_or_admin(recipe)
    try:
        token = trash_recipe(recipe, me().id)
    except OSError:
        raise ApiError("server_error", "Couldn't set that recipe aside safely, so it wasn't deleted.", 500)
    return jsonify(restore_token=token, expires_in=24 * 3600)


@api_v1_bp.route("/recipes/restore/<token>", methods=["POST"])
@api_auth()
def restore_recipe(token):
    from routes.recipes import restore_trash
    recipe, problem = restore_trash(token, me())
    if problem:
        status = 403 if problem == "forbidden" else 404
        raise ApiError("restore_failed", {
            "invalid": "That restore token isn't valid.",
            "expired": "Undo is only available for 24 hours after deleting.",
            "forbidden": "Only the person who deleted a recipe can restore it."}[problem], status)
    return jsonify(_recipe_detail(recipe)), 201


@api_v1_bp.route("/recipes/<int:recipe_id>/duplicate", methods=["POST"])
@api_auth()
def duplicate_recipe(recipe_id):
    o = Recipe.query.get_or_404(recipe_id)
    clone = Recipe(title=f"{o.title} (Copy)"[:200], description=o.description, ingredients=o.ingredients,
                   instructions=o.instructions, prep_time=o.prep_time, cook_time=o.cook_time,
                   servings=o.servings, source_url=o.source_url, image_url=o.image_url, user_id=me().id)
    clone.categories = list(o.categories)
    db.session.add(clone)
    db.session.commit()
    return jsonify(_recipe_detail(clone)), 201


@api_v1_bp.route("/recipes/<int:recipe_id>/image", methods=["PUT"])
@api_auth()
def put_recipe_image(recipe_id):
    """Multipart upload in `image_file`."""
    recipe = Recipe.query.get_or_404(recipe_id)
    _owner_or_admin(recipe)
    upload = request.files.get("image_file")
    if not upload or not upload.filename:
        raise ApiError("validation", "Send the picture as multipart field image_file.", 422)
    recipe.image_url = _store_image(upload)
    db.session.commit()
    return jsonify(image_url=_image(recipe.image_url), thumb_url=_thumb(recipe.image_url))


@api_v1_bp.route("/recipes/<int:recipe_id>/image", methods=["DELETE"])
@api_auth()
def delete_recipe_image(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    _owner_or_admin(recipe)
    recipe.image_url = ""
    db.session.commit()
    return _no_content()


@api_v1_bp.route("/recipes/<int:recipe_id>/image/localise", methods=["POST"])
@api_auth()
def localise_recipe_image(recipe_id):
    """Keep our own copy of a remote picture (for links that stop loading)."""
    from routes.recipes import _localise_remote_image
    recipe = Recipe.query.get_or_404(recipe_id)
    _owner_or_admin(recipe)
    url = recipe.image_url or ""
    if url.startswith(("http://", "https://")):
        local = _localise_remote_image(url)
        if not local:
            raise ApiError("unavailable", "That picture couldn't be downloaded.", 502)
        recipe.image_url = local
        db.session.commit()
    return jsonify(image_url=_image(recipe.image_url), thumb_url=_thumb(recipe.image_url))


@api_v1_bp.route("/recipes/<int:recipe_id>/favorite", methods=["PUT", "DELETE"])
@api_auth()
def set_favorite(recipe_id):
    Recipe.query.get_or_404(recipe_id)
    fav = Favorite.query.filter_by(user_id=me().id, recipe_id=recipe_id).first()
    if request.method == "PUT" and not fav:
        db.session.add(Favorite(user_id=me().id, recipe_id=recipe_id))
    elif request.method == "DELETE" and fav:
        db.session.delete(fav)
    db.session.commit()
    return jsonify(favorited=request.method == "PUT")


def _rating_summary(recipe, mine):
    avg = recipe.avg_rating()
    return {"my_rating": mine, "avg_rating": round(avg, 2) if avg is not None else None,
            "rating_count": len(recipe.ratings)}


@api_v1_bp.route("/recipes/<int:recipe_id>/rating", methods=["PUT"])
@api_auth()
def put_rating(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    score = Body().integer("score")
    if score is None or not 1 <= score <= 5:
        raise ApiError("validation", "Choose a rating from 1 to 5 stars.", 422)
    rating = Rating.query.filter_by(user_id=me().id, recipe_id=recipe_id).first()
    if rating:
        rating.score = score
    else:
        db.session.add(Rating(user_id=me().id, recipe_id=recipe_id, score=score))
    db.session.commit()
    db.session.refresh(recipe)
    return jsonify(_rating_summary(recipe, score))


@api_v1_bp.route("/recipes/<int:recipe_id>/rating", methods=["DELETE"])
@api_auth()
def delete_rating(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    Rating.query.filter_by(user_id=me().id, recipe_id=recipe_id).delete()
    db.session.commit()
    db.session.refresh(recipe)
    return jsonify(_rating_summary(recipe, None))


@api_v1_bp.route("/recipes/<int:recipe_id>/comments")
@api_auth()
def list_comments(recipe_id):
    Recipe.query.get_or_404(recipe_id)
    comments = Comment.query.filter_by(recipe_id=recipe_id).order_by(Comment.created_at.desc()).all()
    return jsonify(items=[_comment(c) for c in comments])


@api_v1_bp.route("/recipes/<int:recipe_id>/comments", methods=["POST"])
@api_auth()
def add_comment(recipe_id):
    Recipe.query.get_or_404(recipe_id)
    text = Body().text("text")
    if not text:
        raise ApiError("validation", "Write something before posting your comment.", 422)
    comment = Comment(user_id=me().id, recipe_id=recipe_id, text=text)
    db.session.add(comment)
    db.session.commit()
    return jsonify(_comment(comment)), 201


@api_v1_bp.route("/comments/<int:comment_id>", methods=["DELETE"])
@api_auth()
def delete_comment(comment_id):
    comment = Comment.query.get_or_404(comment_id)
    _owner_or_admin(comment)
    db.session.delete(comment)
    db.session.commit()
    return _no_content()


@api_v1_bp.route("/recipes/<int:recipe_id>/notes", methods=["PUT"])
@api_auth()
def put_notes(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    _owner_or_admin(recipe)
    recipe.notes = Body().text("notes")
    db.session.commit()
    return jsonify(notes=recipe.notes)


@api_v1_bp.route("/recipes/<int:recipe_id>/share", methods=["POST"])
@api_auth()
def share_recipe(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    _owner_or_admin(recipe)
    if not recipe.share_token:
        recipe.share_token = secrets.token_urlsafe(16)
        db.session.commit()
    return jsonify(share_url=url_for("recipes.view_shared", token=recipe.share_token, _external=True))


@api_v1_bp.route("/recipes/<int:recipe_id>/share", methods=["DELETE"])
@api_auth()
def unshare_recipe(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    _owner_or_admin(recipe)
    recipe.share_token = None
    db.session.commit()
    return _no_content()


@api_v1_bp.route("/recipes/<int:recipe_id>/made", methods=["POST"])
@api_auth()
def made_it(recipe_id):
    Recipe.query.get_or_404(recipe_id)
    log = CookLog(user_id=me().id, recipe_id=recipe_id)
    db.session.add(log)
    db.session.commit()
    count = CookLog.query.filter_by(user_id=me().id, recipe_id=recipe_id).count()
    return jsonify(made_count=count, cooked_at=_iso(log.cooked_at)), 201


@api_v1_bp.route("/recipes/<int:recipe_id>/cook-history")
@api_auth()
def cook_history(recipe_id):
    Recipe.query.get_or_404(recipe_id)
    logs = CookLog.query.filter_by(user_id=me().id, recipe_id=recipe_id).order_by(CookLog.cooked_at.desc()).all()
    return jsonify(items=[{"id": l.id, "cooked_at": _iso(l.cooked_at)} for l in logs])


@api_v1_bp.route("/recipes/<int:recipe_id>/email", methods=["POST"])
@api_auth()
def email_recipe(recipe_id):
    from mailer import send_recipe_email
    from routes.auth import is_valid_email
    recipe = Recipe.query.get_or_404(recipe_id)
    to_email = Body().text("email")
    if not is_valid_email(to_email):
        raise ApiError("validation", "Enter a valid email address.", 422)
    if not send_recipe_email(to_email, recipe, me().username):
        raise ApiError("email_failed", "The email couldn't be sent. Ask an admin to check the email settings.", 502)
    return _no_content()


# ── Import ──

_DRAFT_FIELDS = ("title", "description", "ingredients", "instructions", "notes", "servings",
                 "prep_time", "cook_time")


def _import_preview(data, kind, source_url="", image_name="", raw_text=""):
    from routes.recipes import import_warning
    draft = {k: (data.get(k) or "") for k in _DRAFT_FIELDS}
    return jsonify(kind=kind, draft=draft, source_url=source_url, image_name=image_name,
                   image_url=_image(image_name), raw_text=raw_text,
                   warning=import_warning(draft, raw_text))


def _no_caption_error():
    return ApiError("no_caption", "Couldn't read the caption from that post: Instagram and TikTok often block "
                                  "this. Send the caption text or a screenshot instead.", 422)


def _scrape(url):
    """(data, image_name) for a link, with our own copy of the picture. Raises ApiError."""
    from routes.recipes import _localise_remote_image
    from scraper import scrape_recipe
    from security import FetchError
    try:
        data = scrape_recipe(url)
    except FetchError as e:
        raise ApiError("import_failed", f"Couldn't import that link: {e}", 422)
    except Exception:
        raise ApiError("import_failed", "Couldn't read a recipe from that link.", 422)
    if data.get("source_type") == "social" and not data.get("caption_found"):
        raise _no_caption_error()
    image = data.get("image_url", "") or ""
    if image.startswith("http"):
        image = _localise_remote_image(image) or ("" if data.get("source_type") == "social" else image)
    return data, image


@api_v1_bp.route("/import/url", methods=["POST"])
@api_auth()
def import_url():
    """Parse one link into a draft. Nothing is saved; send the draft to /import/save."""
    url = Body().text("url")
    if not url.lower().startswith(("http://", "https://")):
        raise ApiError("validation", "Send a recipe link starting with http:// or https://.", 422)
    data, image = _scrape(url)
    return _import_preview(data, "url", source_url=url, image_name=image)


@api_v1_bp.route("/import/urls", methods=["POST"])
@api_auth()
def import_urls():
    """Import several links straight into the shelf."""
    urls = [str(u).strip() for u in Body().list("urls") if str(u).strip()]
    if not urls:
        raise ApiError("validation", "Send at least one link in `urls`.", 422)
    if len(urls) > MAX_BULK_URLS:
        raise ApiError("validation", f"Send {MAX_BULK_URLS} links or fewer at a time.", 422)
    imported, failed = [], []
    for url in urls:
        if not url.lower().startswith(("http://", "https://")):
            failed.append({"url": url, "code": "validation", "message": "Not a web link."})
            continue
        try:
            data, image = _scrape(url)
        except ApiError as e:
            failed.append({"url": url, "code": e.code, "message": e.message})
            continue
        recipe = Recipe(title=(data.get("title") or "Imported Recipe")[:200],
                        description=data.get("description", ""), ingredients=data.get("ingredients", ""),
                        instructions=data.get("instructions", ""), prep_time=(data.get("prep_time") or "")[:50],
                        cook_time=(data.get("cook_time") or "")[:50], servings=(data.get("servings") or "")[:50],
                        source_url=url[:500], image_url=image, notes=data.get("notes", ""), user_id=me().id)
        db.session.add(recipe)
        db.session.commit()
        imported.append(_recipe_summary(recipe))
    return jsonify(imported=imported, failed=failed), 200 if imported or not failed else 422


@api_v1_bp.route("/import/pdf", methods=["POST"])
@api_auth()
def import_pdf():
    """One PDF (`pdf_files`) returns a draft; several PDFs are saved directly."""
    from scraper import parse_pdf_recipe
    from werkzeug.datastructures import FileStorage
    files = [f for f in request.files.getlist("pdf_files") if f and f.filename]
    if not files:
        raise ApiError("validation", "Send PDFs as multipart field pdf_files.", 422)
    if len(files) == 1:
        blob = files[0].read()
        try:
            data = parse_pdf_recipe(FileStorage(io.BytesIO(blob), filename="recipe.pdf"))
        except Exception:
            data = None
        if not data or not data.get("title"):
            raise ApiError("import_failed", "Couldn't find readable text in that PDF. "
                                            "Scanned PDFs need the photo import instead.", 422)
        raw = ""
        try:
            from pypdf import PdfReader
            raw = "\n".join((p.extract_text() or "") for p in PdfReader(io.BytesIO(blob)).pages).strip()
        except Exception:
            pass
        return _import_preview(data, "pdf", raw_text=raw)
    imported, failed = [], []
    for f in files:
        try:
            data = parse_pdf_recipe(f) if f.filename.lower().endswith(".pdf") else None
        except Exception:
            data = None
        if not data or not data.get("title"):
            failed.append({"filename": f.filename, "code": "import_failed", "message": "No readable recipe."})
            continue
        recipe = Recipe(title=data["title"][:200], description=data.get("description", ""),
                        ingredients=data.get("ingredients", ""), instructions=data.get("instructions", ""),
                        notes=data.get("notes", ""), prep_time=(data.get("prep_time") or "")[:50],
                        cook_time=(data.get("cook_time") or "")[:50], servings=(data.get("servings") or "")[:50],
                        user_id=me().id)
        db.session.add(recipe)
        db.session.commit()
        imported.append(_recipe_summary(recipe))
    return jsonify(imported=imported, failed=failed)


@api_v1_bp.route("/import/photo", methods=["POST"])
@api_auth()
def import_photo():
    """Photos or screenshots (`photos`, in order) of one recipe, read with OCR."""
    from ocr import OcrError, images_to_text
    from recipe_text import parse_recipe_text
    files = [f for f in request.files.getlist("photos") if f and f.filename]
    if not files:
        raise ApiError("validation", "Send photos as multipart field photos.", 422)
    try:
        text = images_to_text([f.read() for f in files])
    except OcrError as e:
        raise ApiError("ocr_unavailable", str(e), 422)
    if len(text) < 20:
        raise ApiError("import_failed", "Couldn't find readable text in that image. "
                                        "Try a sharper, straight-on photo.", 422)
    b = Body()
    parsed = parse_recipe_text(text, title=b.text("photo_title") or None)
    parsed["title"] = parsed.get("title") or "Recipe from photo"
    image_name = ""
    if b.flag("use_as_cover"):
        files[0].stream.seek(0)
        image_name = _store_image(files[0])
    return _import_preview(parsed, "photo", image_name=image_name, raw_text=text)


@api_v1_bp.route("/import/caption", methods=["POST"])
@api_auth()
def import_caption():
    """Pasted social-media caption or any loose recipe text."""
    from recipe_text import parse_recipe_text
    b = Body()
    caption = b.text("caption")
    if not caption:
        raise ApiError("validation", "Send the caption text in `caption`.", 422)
    parsed = parse_recipe_text(caption, title=b.text("title") or None)
    parsed["title"] = parsed.get("title") or "Imported Recipe"
    return _import_preview(parsed, "caption", raw_text=caption)


@api_v1_bp.route("/import/save", methods=["POST"])
@api_auth()
def import_save():
    """Create a recipe from a (possibly edited) draft returned by the import previews."""
    b = Body()
    data = {k: b.text(k) for k in _DRAFT_FIELDS}
    if not data["title"]:
        raise ApiError("validation", "Give the recipe a title before saving.", 422)
    image_name = b.text("image_name")
    if image_name and not (image_name.startswith(("http://", "https://")) or _IMAGE_NAME_RE.match(image_name)):
        image_name = ""
    recipe = Recipe(title=data["title"][:200], description=data["description"], ingredients=data["ingredients"],
                    instructions=data["instructions"], notes=data["notes"], servings=data["servings"][:50],
                    prep_time=data["prep_time"][:50], cook_time=data["cook_time"][:50],
                    source_url=b.text("source_url")[:500],
                    image_url=image_name if b.flag("use_image", True) else "", user_id=me().id)
    db.session.add(recipe)
    db.session.commit()
    return jsonify(_recipe_detail(recipe)), 201


# ── Collections ──

def _owned_collection(coll_id):
    coll = Collection.query.get_or_404(coll_id)
    _owner_or_admin(coll)
    return coll


def _apply_collection_fields(coll, b, creating):
    from routes.collections import _slugify
    if b.has("name") or creating:
        name = b.text("name")[:200]
        if not name:
            raise ApiError("validation", "Give the collection a name.", 422)
        coll.name = name
    if b.has("description"):
        coll.description = b.text("description")
    if b.has("category_id"):
        cat_id = b.integer("category_id")
        if cat_id is not None and db.session.get(Category, cat_id) is None:
            raise ApiError("validation", "Unknown category.", 422)
        coll.category_id = cat_id
    if b.has("slug"):
        slug = _slugify(b.text("slug")) if b.text("slug") else None
        clash = Collection.query.filter_by(slug=slug).first() if slug else None
        if clash and clash.id != coll.id:
            raise ApiError("conflict", "That web address is already used by another collection.", 409)
        coll.slug = slug
    upload = request.files.get("cover_image")
    if upload and upload.filename:
        coll.cover_image = _store_image_named(upload, "cover")
    elif b.flag("remove_cover"):
        coll.cover_image = ""


def _store_image_named(file, prefix):
    from images import save_uploaded_image
    name = save_uploaded_image(file, _uploads_dir(), prefix=prefix)
    if not name:
        raise ApiError("validation", "That file isn't a valid image.", 422)
    return name


def _uploads_dir():
    import os
    return os.path.join(current_app.config["DATA_DIR"], "uploads")


@api_v1_bp.route("/collections")
@api_auth()
def list_collections():
    colls = Collection.query.filter_by(user_id=me().id).order_by(Collection.name).all()
    return jsonify(items=[_collection(c) for c in colls])


@api_v1_bp.route("/collections", methods=["POST"])
@api_auth()
def create_collection():
    coll = Collection(name="", user_id=me().id)
    _apply_collection_fields(coll, Body(), creating=True)
    db.session.add(coll)
    db.session.commit()
    return jsonify(_collection(coll, detail=True)), 201


@api_v1_bp.route("/collections/<int:coll_id>")
@api_auth()
def get_collection(coll_id):
    return jsonify(_collection(_owned_collection(coll_id), detail=True))


@api_v1_bp.route("/collections/<int:coll_id>", methods=["PATCH"])
@api_auth()
def update_collection(coll_id):
    coll = _owned_collection(coll_id)
    _apply_collection_fields(coll, Body(), creating=False)
    db.session.commit()
    return jsonify(_collection(coll, detail=True))


@api_v1_bp.route("/collections/<int:coll_id>", methods=["DELETE"])
@api_auth()
def delete_collection(coll_id):
    db.session.delete(_owned_collection(coll_id))
    db.session.commit()
    return _no_content()


@api_v1_bp.route("/collections/<int:coll_id>/share", methods=["POST"])
@api_auth()
def share_collection(coll_id):
    coll = _owned_collection(coll_id)
    if not coll.share_token:
        coll.share_token = secrets.token_urlsafe(16)
        db.session.commit()
    return jsonify(share_url=url_for("collections.view_shared", token=coll.public_url_token, _external=True))


@api_v1_bp.route("/collections/<int:coll_id>/share", methods=["DELETE"])
@api_auth()
def unshare_collection(coll_id):
    coll = _owned_collection(coll_id)
    coll.share_token = None
    db.session.commit()
    return _no_content()


@api_v1_bp.route("/collections/<int:coll_id>/recipes", methods=["POST"])
@api_auth()
def add_collection_recipe(coll_id):
    coll = _owned_collection(coll_id)
    recipe = Recipe.query.get_or_404(Body().integer("recipe_id") or 0)
    if recipe not in coll.recipes:
        coll.recipes.append(recipe)
        db.session.commit()
    return jsonify(_collection(coll, detail=True)), 201


@api_v1_bp.route("/collections/<int:coll_id>/recipes/<int:recipe_id>", methods=["DELETE"])
@api_auth()
def remove_collection_recipe(coll_id, recipe_id):
    coll = _owned_collection(coll_id)
    recipe = Recipe.query.get_or_404(recipe_id)
    if recipe in coll.recipes:
        coll.recipes.remove(recipe)
        db.session.commit()
    return _no_content()


@api_v1_bp.route("/collections/<int:coll_id>/order", methods=["PUT"])
@api_auth()
def reorder_collection(coll_id):
    """`order`: recipe ids in the wanted order. Manual recipes left out keep their place at the end."""
    coll = _owned_collection(coll_id)
    order = Body().list("order")
    if not order:
        raise ApiError("validation", "Send `order` as a list of recipe ids.", 422)
    by_id = {r.id: r for r in coll.recipes}
    ordered = [by_id[i] for i in dict.fromkeys(order) if i in by_id]
    ordered += [r for r in coll.recipes if r not in ordered]
    coll.recipes.clear()
    db.session.flush()
    coll.recipes.extend(ordered)
    db.session.commit()
    return jsonify(_collection(coll, detail=True))


# ── Meal plan ──

def _plan_range(params=None):
    """(first, last) from `from`/`to` dates or a `week` offset (default: this week, Monday to Sunday)."""
    from routes.mealplan import _get_week_dates
    params = request.args if params is None else params
    start, end = params.get("from"), params.get("to")
    if start or end:
        first = _parse_date(start, "from") if start else _parse_date(end, "to") - timedelta(days=6)
        last = _parse_date(end, "to") if end else first + timedelta(days=6)
    else:
        try:
            offset = int(params.get("week") or 0)
        except ValueError:
            raise ApiError("validation", "week must be a whole number.", 422)
        week = _get_week_dates(date.today() + timedelta(weeks=max(-520, min(520, offset))))
        first, last = week[0], week[-1]
    if last < first or (last - first).days >= MAX_PLAN_DAYS:
        raise ApiError("validation", f"`from`..`to` must be a range of at most {MAX_PLAN_DAYS} days.", 422)
    return first, last


def _plan_entries(user_id, first, last):
    plans = (MealPlan.query.filter(MealPlan.user_id == user_id, MealPlan.date >= first, MealPlan.date <= last)
             .order_by(MealPlan.date, MealPlan.sort_order, MealPlan.id).all())
    return [_plan_entry(p) for p in plans if p.recipe is not None]


def _meal_type(value, default="dinner"):
    from routes.mealplan import MEAL_TYPES
    value = value or default
    if value not in MEAL_TYPES:
        raise ApiError("validation", f"meal_type must be one of {', '.join(MEAL_TYPES)}.", 422)
    return value


@api_v1_bp.route("/mealplan")
@api_auth()
def get_mealplan():
    from routes.mealplan import _get_share_token
    first, last = _plan_range()
    token = _get_share_token(me().id)
    return jsonify({"from": first.isoformat(), "to": last.isoformat(),
                    "entries": _plan_entries(me().id, first, last),
                    "share_url": url_for("mealplan.view_shared", token=token, _external=True) if token else None})


@api_v1_bp.route("/mealplan", methods=["POST"])
@api_auth()
def add_to_mealplan():
    b = Body()
    recipe = Recipe.query.get_or_404(b.integer("recipe_id") or 0)
    plan = MealPlan(user_id=me().id, recipe_id=recipe.id, date=_parse_date(b.get("date")),
                    meal_type=_meal_type(b.text("meal_type")))
    db.session.add(plan)
    db.session.commit()
    return jsonify(_plan_entry(plan)), 201


def _own_plan(plan_id):
    plan = MealPlan.query.get_or_404(plan_id)
    if plan.user_id != me().id:
        raise ApiError("forbidden", "That belongs to someone else, so you can't change it.", 403)
    return plan


@api_v1_bp.route("/mealplan/<int:plan_id>", methods=["PATCH"])
@api_auth()
def move_plan_entry(plan_id):
    plan = _own_plan(plan_id)
    b = Body()
    if b.has("date"):
        plan.date = _parse_date(b.get("date"))
    if b.has("meal_type"):
        plan.meal_type = _meal_type(b.text("meal_type"))
    if b.has("recipe_id"):
        plan.recipe_id = Recipe.query.get_or_404(b.integer("recipe_id") or 0).id
    db.session.commit()
    db.session.refresh(plan)
    return jsonify(_plan_entry(plan))


@api_v1_bp.route("/mealplan/<int:plan_id>", methods=["DELETE"])
@api_auth()
def remove_plan_entry(plan_id):
    db.session.delete(_own_plan(plan_id))
    db.session.commit()
    return _no_content()


@api_v1_bp.route("/mealplan/shopping", methods=["POST"])
@api_auth()
def plan_to_shopping():
    """Add the ingredients of every planned recipe in the range (default: this week) to the list."""
    from routes.mealplan import add_week_to_shopping
    b = Body()
    first, last = _plan_range({k: str(b.get(k)) for k in ("from", "to", "week") if b.get(k) is not None})
    added, merged = add_week_to_shopping(me().id, first, last)
    db.session.commit()
    return jsonify(added=added, merged=merged)


@api_v1_bp.route("/mealplan/auto-generate", methods=["POST"])
@api_auth()
def auto_generate_plan():
    """Fill the empty slots of a week with random recipes (favourites first)."""
    from routes.mealplan import _get_week_dates, fill_week
    b = Body()
    offset = max(-520, min(520, b.integer("week") or 0))
    types = [_meal_type(t) for t in b.list("meal_types")] or ["dinner"]
    week = _get_week_dates(date.today() + timedelta(weeks=offset))
    added = fill_week(me().id, week, types)
    if added is None:
        raise ApiError("no_recipes", "Add a few recipes first, then the planner can fill your week.", 409)
    db.session.commit()
    return jsonify({"added": added, "from": week[0].isoformat(), "to": week[-1].isoformat(),
                    "entries": _plan_entries(me().id, week[0], week[-1])})


@api_v1_bp.route("/mealplan/share", methods=["POST"])
@api_auth()
def share_mealplan():
    from routes.mealplan import _SHARE_PREFIX, _get_share_token
    token = _get_share_token(me().id)
    if not token:
        token = secrets.token_urlsafe(16)
        db.session.add(SiteSetting(key=f"{_SHARE_PREFIX}{me().id}", value=token))
        db.session.commit()
    return jsonify(share_url=url_for("mealplan.view_shared", token=token, _external=True))


@api_v1_bp.route("/mealplan/share", methods=["DELETE"])
@api_auth()
def unshare_mealplan():
    from routes.mealplan import _SHARE_PREFIX
    SiteSetting.query.filter_by(key=f"{_SHARE_PREFIX}{me().id}").delete()
    db.session.commit()
    return _no_content()


# ── Shopping list ──

def _shopping_item(item, store_url):
    from routes.shopping import store_link
    from shopping_utils import aisle_for, parse_line
    name = parse_line(item.name)[2] or item.name
    return {"id": item.id, "name": item.name, "checked": bool(item.checked), "recipe_id": item.recipe_id,
            "recipe_title": item.recipe.title if item.recipe else None,
            "aisle": aisle_for(name), "store_url": store_link(store_url, name) or None,
            "created_at": _iso(item.created_at)}


@api_v1_bp.route("/shopping")
@api_auth()
def get_shopping():
    from routes.shopping import _store_settings
    from shopping_utils import _AISLES
    items = (ShoppingListItem.query.filter_by(user_id=me().id)
             .order_by(ShoppingListItem.checked, ShoppingListItem.created_at.desc(), ShoppingListItem.id.desc())
             .all())
    store_name, store_url = _store_settings()
    return jsonify(store={"name": store_name, "search_url": store_url},
                   aisle_order=[a for a, _ in _AISLES] + ["Other"],
                   items=[_shopping_item(i, store_url) for i in items])


def _add_lines(lines, recipe_id=None):
    from shopping_utils import add_lines_merged
    added, merged = add_lines_merged(me().id, lines, recipe_id=recipe_id)
    db.session.commit()
    return jsonify(added=added, merged=merged), 201


@api_v1_bp.route("/shopping/items", methods=["POST"])
@api_auth()
def add_shopping_items():
    """`name` or `names`; quantities for the same item are combined."""
    b = Body()
    raw = b.list("names") if b.has("names") else [b.get("name")]
    lines = [str(n).strip()[:MAX_ITEM_LEN] for n in raw if n is not None and str(n).strip()]
    if not lines:
        raise ApiError("validation", "Send an item in `name` (or several in `names`).", 422)
    if len(lines) > MAX_PICKED_ITEMS:
        raise ApiError("validation", f"Send {MAX_PICKED_ITEMS} items or fewer at once.", 422)
    return _add_lines(lines)


@api_v1_bp.route("/shopping/recipe/<int:recipe_id>", methods=["POST"])
@api_auth()
def add_recipe_to_shopping(recipe_id):
    """Add every ingredient, or only the lines in `items` (as on the recipe page)."""
    recipe = Recipe.query.get_or_404(recipe_id)
    b = Body()
    if b.has("items"):
        picked = [str(v).strip()[:MAX_ITEM_LEN] for v in b.list("items")]
        if len(picked) > MAX_PICKED_ITEMS:
            raise ApiError("validation", f"Pick {MAX_PICKED_ITEMS} or fewer.", 422)
        lines = [v for v in picked if v and not v.startswith("# ")]
        if not lines:
            raise ApiError("validation", "Nothing was selected.", 422)
    else:
        lines = (recipe.ingredients or "").split("\n")
    return _add_lines(lines, recipe_id=recipe.id)


def _own_item(item_id):
    item = ShoppingListItem.query.get_or_404(item_id)
    if item.user_id != me().id:
        raise ApiError("forbidden", "That belongs to someone else, so you can't change it.", 403)
    return item


@api_v1_bp.route("/shopping/items/<int:item_id>", methods=["PATCH"])
@api_auth()
def update_shopping_item(item_id):
    from routes.shopping import _store_settings
    item = _own_item(item_id)
    b = Body()
    if b.has("checked"):
        item.checked = b.flag("checked")
    if b.has("name"):
        name = b.text("name")[:MAX_ITEM_LEN]
        if not name:
            raise ApiError("validation", "An item needs a name.", 422)
        item.name = name
    db.session.commit()
    return jsonify(_shopping_item(item, _store_settings()[1]))


@api_v1_bp.route("/shopping/items/<int:item_id>", methods=["DELETE"])
@api_auth()
def delete_shopping_item(item_id):
    db.session.delete(_own_item(item_id))
    db.session.commit()
    return _no_content()


@api_v1_bp.route("/shopping/items", methods=["DELETE"])
@api_auth()
def clear_shopping():
    """Clear the whole list, or only ticked items with ?checked=1."""
    query = ShoppingListItem.query.filter_by(user_id=me().id)
    if request.args.get("checked") in ("1", "true"):
        query = query.filter_by(checked=True)
    query.delete()
    db.session.commit()
    return _no_content()


# ── Guides (extras) and calculators ──

def _extra(page):
    share = ExtraShare.query.filter_by(slug=page["slug"]).first()
    return {"slug": page["slug"], "name": page["name"], "description": page["description"],
            "icon": page["icon"], "path": f"/extras/{page['slug']}",
            "file_url": f"/static/{page['file']}",
            "share_url": url_for("extras.view_shared", token=share.token, _external=True) if share else None}


@api_v1_bp.route("/extras")
@api_auth()
def list_extras():
    from routes.extras import PAGES
    return jsonify(items=[_extra(p) for p in PAGES])


@api_v1_bp.route("/extras/<slug>/share", methods=["POST"])
@api_auth()
def share_extra(slug):
    from routes.extras import _BY_SLUG
    if slug not in _BY_SLUG:
        raise ApiError("not_found", "No such guide.", 404)
    if not ExtraShare.query.filter_by(slug=slug).first():
        db.session.add(ExtraShare(slug=slug, token=secrets.token_urlsafe(16)))
        db.session.commit()
    return jsonify(_extra(_BY_SLUG[slug]))


@api_v1_bp.route("/extras/<slug>/share", methods=["DELETE"])
@api_auth()
def unshare_extra(slug):
    ExtraShare.query.filter_by(slug=slug).delete()
    db.session.commit()
    return _no_content()


def _calculator(c):
    return {"id": c.id, "name": c.name, "description": c.description or "", "url": c.url,
            "icon": c.icon or "", "sort_order": c.sort_order or 0}


@api_v1_bp.route("/calculators")
@api_auth()
def list_calculators():
    calcs = Calculator.query.order_by(Calculator.sort_order, Calculator.name).all()
    return jsonify(items=[_calculator(c) for c in calcs])


@api_v1_bp.route("/calculators/<int:calc_id>")
@api_auth()
def get_calculator(calc_id):
    return jsonify(_calculator(Calculator.query.get_or_404(calc_id)))


def _apply_calculator(calc, b, creating):
    for key, limit in (("name", 200), ("url", 500), ("description", 10 ** 6), ("icon", 10)):
        if b.has(key):
            setattr(calc, key, b.text(key)[:limit])
    if b.has("sort_order"):
        calc.sort_order = b.integer("sort_order") or 0
    if not calc.name or not calc.url:
        raise ApiError("validation", "Enter both a name and a web address.", 422)
    if not calc.icon:
        calc.icon = "🧮"


@api_v1_bp.route("/calculators", methods=["POST"])
@api_auth(admin=True)
def create_calculator():
    calc = Calculator(name="", url="")
    _apply_calculator(calc, Body(), True)
    db.session.add(calc)
    db.session.commit()
    return jsonify(_calculator(calc)), 201


@api_v1_bp.route("/calculators/<int:calc_id>", methods=["PATCH"])
@api_auth(admin=True)
def update_calculator(calc_id):
    calc = Calculator.query.get_or_404(calc_id)
    _apply_calculator(calc, Body(), False)
    db.session.commit()
    return jsonify(_calculator(calc))


@api_v1_bp.route("/calculators/<int:calc_id>", methods=["DELETE"])
@api_auth(admin=True)
def delete_calculator(calc_id):
    db.session.delete(Calculator.query.get_or_404(calc_id))
    db.session.commit()
    return _no_content()


# ── Admin: users and site settings ──

@api_v1_bp.route("/admin/users")
@api_auth(admin=True)
def admin_list_users():
    return jsonify(items=[_user_full(u) for u in User.query.order_by(User.created_at.desc()).all()])


@api_v1_bp.route("/admin/users", methods=["POST"])
@api_auth(admin=True)
def admin_create_user():
    """Creates the account with a generated password, emailed if an email is given and mail works;
    otherwise returned once as `temp_password`."""
    from mailer import send_welcome_email
    from routes.auth import is_valid_email
    b = Body()
    username, email = b.text("username"), b.text("email")
    if not username:
        raise ApiError("validation", "Enter a username.", 422)
    if email and not is_valid_email(email):
        raise ApiError("validation", "That email address doesn't look right.", 422)
    if User.query.filter_by(username=username).first():
        raise ApiError("conflict", "That username is taken.", 409)
    password = secrets.token_urlsafe(12)
    user = User(username=username, email=email, is_admin=b.flag("is_admin"))
    user.set_password(password)
    db.session.add(user)
    db.session.commit()
    emailed = bool(email) and bool(send_welcome_email(email, username, password))
    return jsonify(user=_user_full(user), emailed=emailed, temp_password=None if emailed else password), 201


@api_v1_bp.route("/admin/users/<int:user_id>", methods=["PATCH"])
@api_auth(admin=True)
def admin_update_user(user_id):
    from routes.auth import _validate_password, is_valid_email
    user = User.query.get_or_404(user_id)
    b = Body()
    if b.has("username") and b.text("username"):
        name = b.text("username")
        clash = User.query.filter_by(username=name).first()
        if clash and clash.id != user.id:
            raise ApiError("conflict", "That username is taken.", 409)
        user.username = name
    if b.has("email"):
        email = b.text("email")
        if email and not is_valid_email(email):
            raise ApiError("validation", "That email address doesn't look right.", 422)
        user.email = email
    if b.has("is_admin"):
        if user.id == me().id and not b.flag("is_admin"):
            raise ApiError("validation", "You can't remove your own admin access.", 422)
        user.is_admin = b.flag("is_admin")
    if b.text("new_password"):
        problem = _validate_password(b.text("new_password"))
        if problem:
            raise ApiError("validation", problem, 422)
        user.set_password(b.text("new_password"))
        ApiToken.query.filter(ApiToken.user_id == user.id,
                              ApiToken.id != (g.api_token.id if user.id == me().id else -1)).delete()
    db.session.commit()
    return jsonify(_user_full(user))


@api_v1_bp.route("/admin/users/<int:user_id>", methods=["DELETE"])
@api_auth(admin=True)
def admin_delete_user(user_id):
    user = User.query.get_or_404(user_id)
    if user.id == me().id:
        raise ApiError("validation", "You can't delete yourself.", 422)
    ShoppingListItem.query.filter_by(user_id=user.id).delete()
    db.session.delete(user)  # ORM delete so the cascades fire
    db.session.commit()
    return _no_content()


def _settings_payload():
    from routes.shopping import _store_settings
    store_name, store_url = _store_settings()
    return {"site_name": _setting("site_name"), "logo_url": _upload_url(_setting("logo_file")),
            "public_show_author": _setting("public_show_author") == "1",
            "store_name": store_name, "store_search_url": store_url}


@api_v1_bp.route("/admin/settings")
@api_auth(admin=True)
def admin_get_settings():
    return jsonify(_settings_payload())


@api_v1_bp.route("/admin/settings", methods=["PATCH"])
@api_auth(admin=True)
def admin_update_settings():
    from routes.admin import _set_setting
    b = Body()
    if b.has("site_name"):
        _set_setting("site_name", b.text("site_name"))
    if b.has("public_show_author"):
        _set_setting("public_show_author", "1" if b.flag("public_show_author") else "0")
    if b.has("store_search_url") or b.has("store_name"):
        url = b.text("store_search_url") if b.has("store_search_url") else _settings_payload()["store_search_url"]
        name = b.text("store_name")[:60] if b.has("store_name") else _settings_payload()["store_name"]
        if url and not (url.lower().startswith(("http://", "https://")) and "{q}" in url and len(url) <= 500):
            raise ApiError("validation", "The store search link must start with http:// or https:// "
                                         "and include {q} where the item name goes.", 422)
        _set_setting("store_search_url", url)
        _set_setting("store_name", name or ("Woolworths" if url else ""))
    upload = request.files.get("logo_file")
    if upload and upload.filename:
        from images import save_uploaded_image
        filename = save_uploaded_image(upload, _uploads_dir(), prefix="logo", max_dim=600, make_thumb=False)
        if not filename:
            raise ApiError("validation", "That file isn't a valid image.", 422)
        if _setting("logo_file"):
            delete_image(_uploads_dir(), _setting("logo_file"))
        _set_setting("logo_file", filename)
    elif b.flag("remove_logo") and _setting("logo_file"):
        delete_image(_uploads_dir(), _setting("logo_file"))
        _set_setting("logo_file", "")
    return jsonify(_settings_payload())


# ── Public, no token ──

@api_v1_bp.route("/shared/recipes/<token>")
def shared_recipe(token):
    return jsonify(_recipe_public(Recipe.query.filter_by(share_token=token).first_or_404()))


def _shared_collection(token):
    from routes.collections import _find_collection_by_token_or_slug
    coll = _find_collection_by_token_or_slug(token)
    if not coll or not coll.share_token:
        raise ApiError("not_found", "Collection not found.", 404)
    return coll


@api_v1_bp.route("/shared/collections/<token>")
def shared_collection(token):
    coll = _shared_collection(token)
    return jsonify(name=coll.name, description=coll.description or "", cover_url=_upload_url(coll.cover_image),
                   recipes=[_recipe_brief(r) for r in coll.get_all_recipes()])


@api_v1_bp.route("/shared/collections/<token>/recipes/<int:recipe_id>")
def shared_collection_recipe(token, recipe_id):
    coll = _shared_collection(token)
    recipe = Recipe.query.get_or_404(recipe_id)
    if recipe not in coll.get_all_recipes():
        raise ApiError("not_found", "Recipe not found in this collection.", 404)
    return jsonify(_recipe_public(recipe))


@api_v1_bp.route("/shared/mealplan/<token>")
def shared_mealplan(token):
    from routes.mealplan import _user_for_token
    user_id = _user_for_token(token)
    if user_id is None:
        raise ApiError("not_found", "Meal plan not found.", 404)
    first, last = _plan_range()
    return jsonify({"from": first.isoformat(), "to": last.isoformat(),
                    "entries": _plan_entries(user_id, first, last)})
