from datetime import datetime, timezone
from flask_sqlalchemy import SQLAlchemy
from flask_login import UserMixin
from werkzeug.security import generate_password_hash, check_password_hash

db = SQLAlchemy()

recipe_categories = db.Table(
    "recipe_categories",
    db.Column("recipe_id", db.Integer, db.ForeignKey("recipe.id"), primary_key=True),
    db.Column("category_id", db.Integer, db.ForeignKey("category.id"), primary_key=True),
)

recipe_collections = db.Table(
    "recipe_collections",
    db.Column("recipe_id", db.Integer, db.ForeignKey("recipe.id"), primary_key=True),
    db.Column("collection_id", db.Integer, db.ForeignKey("collection.id"), primary_key=True),
)


class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(200), default="")
    password_hash = db.Column(db.String(256), nullable=False)
    is_admin = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    recipes = db.relationship("Recipe", backref="author", lazy=True,
                              cascade="all, delete-orphan")

    def set_password(self, password):
        self.password_hash = generate_password_hash(password, method="scrypt")

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)


class Category(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), unique=True, nullable=False)


class Recipe(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text, default="")
    ingredients = db.Column(db.Text, nullable=False)
    instructions = db.Column(db.Text, nullable=False)
    prep_time = db.Column(db.String(50), default="")
    cook_time = db.Column(db.String(50), default="")
    servings = db.Column(db.String(50), default="")
    source_url = db.Column(db.String(500), default="")
    image_url = db.Column(db.String(500), default="")
    notes = db.Column(db.Text, default="")  # Personal notes
    share_token = db.Column(db.String(32), unique=True, nullable=True)  # Public sharing
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc),
                           onupdate=lambda: datetime.now(timezone.utc))
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    categories = db.relationship("Category", secondary=recipe_categories, backref="recipes", lazy=True)
    
    def avg_rating(self):
        if not self.ratings:
            return None
        return sum(r.score for r in self.ratings) / len(self.ratings)


class ShoppingListItem(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(300), nullable=False)
    checked = db.Column(db.Boolean, default=False)
    recipe_id = db.Column(db.Integer, db.ForeignKey("recipe.id"), nullable=True)
    recipe = db.relationship("Recipe", backref="shopping_items")
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    # Woolworths price cache
    ww_product_name = db.Column(db.String(300), default="")
    ww_price = db.Column(db.Float, nullable=True)
    ww_image = db.Column(db.String(500), default="")
    ww_url = db.Column(db.String(500), default="")
    ww_cup_string = db.Column(db.String(100), default="")
    ww_is_on_special = db.Column(db.Boolean, default=False)
    ww_was_price = db.Column(db.Float, nullable=True)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))


class Calculator(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text, default="")
    url = db.Column(db.String(500), nullable=False)
    icon = db.Column(db.String(10), default="🧮")
    sort_order = db.Column(db.Integer, default=0)


class SiteSetting(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    key = db.Column(db.String(100), unique=True, nullable=False)
    value = db.Column(db.Text, default="")


class ExtraShare(db.Model):
    """Public share token for a bundled 'Extras' page (keyed by its slug)."""
    id = db.Column(db.Integer, primary_key=True)
    slug = db.Column(db.String(100), unique=True, nullable=False)
    token = db.Column(db.String(32), unique=True, nullable=False)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))


class Favorite(db.Model):
    """User's favorite/bookmarked recipes."""
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    recipe_id = db.Column(db.Integer, db.ForeignKey("recipe.id"), nullable=False)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    user = db.relationship("User", backref=db.backref("favorites", cascade="all, delete-orphan"))
    recipe = db.relationship("Recipe", backref=db.backref("favorited_by", cascade="all, delete-orphan"))
    __table_args__ = (db.UniqueConstraint('user_id', 'recipe_id'),)


class Rating(db.Model):
    """User ratings for recipes (1-5 stars)."""
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    recipe_id = db.Column(db.Integer, db.ForeignKey("recipe.id"), nullable=False)
    score = db.Column(db.Integer, nullable=False)  # 1-5
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    user = db.relationship("User", backref=db.backref("ratings", cascade="all, delete-orphan"))
    recipe = db.relationship("Recipe", backref=db.backref("ratings", cascade="all, delete-orphan"))
    __table_args__ = (db.UniqueConstraint('user_id', 'recipe_id'),)


class Comment(db.Model):
    """Comments on recipes."""
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    recipe_id = db.Column(db.Integer, db.ForeignKey("recipe.id"), nullable=False)
    text = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    user = db.relationship("User", backref=db.backref("comments", cascade="all, delete-orphan"))
    recipe = db.relationship("Recipe", backref=db.backref("comments", cascade="all, delete-orphan"))


class MealPlan(db.Model):
    """Meal planning entries."""
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    recipe_id = db.Column(db.Integer, db.ForeignKey("recipe.id"), nullable=False)
    date = db.Column(db.Date, nullable=False)
    meal_type = db.Column(db.String(20), default="dinner")  # breakfast, lunch, dinner, snack
    sort_order = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    user = db.relationship("User", backref=db.backref("meal_plans", cascade="all, delete-orphan"))
    recipe = db.relationship("Recipe", backref=db.backref("meal_plans", cascade="all, delete-orphan"))


class CookLog(db.Model):
    """Track when a user makes a recipe."""
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    recipe_id = db.Column(db.Integer, db.ForeignKey("recipe.id"), nullable=False)
    cooked_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    user = db.relationship("User", backref=db.backref("cook_logs", cascade="all, delete-orphan"))
    recipe = db.relationship("Recipe", backref=db.backref("cook_logs", cascade="all, delete-orphan"))


class Collection(db.Model):
    """Recipe collections/cookbooks (themed sets)."""
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text, default="")
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    share_token = db.Column(db.String(32), unique=True, nullable=True)
    slug = db.Column(db.String(200), unique=True, nullable=True)
    cover_image = db.Column(db.String(500), default="")
    category_id = db.Column(db.Integer, db.ForeignKey("category.id"), nullable=True)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    user = db.relationship("User", backref=db.backref("collections", cascade="all, delete-orphan"))
    category = db.relationship("Category", backref="linked_collections")
    recipes = db.relationship("Recipe", secondary=recipe_collections, backref="collections", lazy=True)

    def get_all_recipes(self):
        """Get recipes: manual (preserving drag-drop order) + category-linked ones appended."""
        manual = list(self.recipes)  # preserves join-table insertion order
        manual_ids = {r.id for r in manual}
        if self.category_id and self.category:
            extras = sorted(
                [r for r in self.category.recipes if r.id not in manual_ids],
                key=lambda r: r.title,
            )
            manual.extend(extras)
        return manual

    @property
    def public_url_token(self):
        """Return slug if set, otherwise share_token."""
        return self.slug or self.share_token


class LoginAttempt(db.Model):
    """Failed login attempts — DB-backed so rate limiting works across
    gunicorn workers and survives restarts."""
    id = db.Column(db.Integer, primary_key=True)
    ip = db.Column(db.String(64), index=True, nullable=False)
    username = db.Column(db.String(80), index=True, default="")
    created_at = db.Column(db.DateTime, index=True,
                           default=lambda: datetime.now(timezone.utc))


class PasswordResetToken(db.Model):
    """Single-use, expiring password reset tokens (stores a hash, not the token)."""
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    token_hash = db.Column(db.String(64), unique=True, nullable=False)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    used = db.Column(db.Boolean, default=False)
    user = db.relationship("User", backref=db.backref("reset_tokens", cascade="all, delete-orphan"))
