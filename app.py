import os
import secrets
from datetime import timedelta
from flask import Flask, url_for, g, request
from flask_login import LoginManager
from flask_wtf.csrf import CSRFProtect
from models import db, User, SiteSetting

csrf = CSRFProtect()


def create_app():
    app = Flask(__name__)

    # ── Data directory ──
    data_dir = os.environ.get("DATA_DIR", "/app/data")
    os.makedirs(data_dir, exist_ok=True)

    # ── Secret key: env > persisted file > auto-generate ──
    secret_file = os.path.join(data_dir, ".secret_key")
    secret_key = os.environ.get("FLASK_SECRET_KEY", "")
    if not secret_key or secret_key == "change-me-in-production":
        if os.path.exists(secret_file):
            with open(secret_file) as f:
                secret_key = f.read().strip()
        if not secret_key:
            secret_key = secrets.token_hex(32)
            with open(secret_file, "w") as f:
                f.write(secret_key)
            os.chmod(secret_file, 0o600)

    app.config["SECRET_KEY"] = secret_key
    app.config["DATA_DIR"] = data_dir
    app.config["SQLALCHEMY_DATABASE_URI"] = f"sqlite:///{data_dir}/recipes.db"
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # ── Request limits ──
    # Caps uploads (images/PDFs/backup zips); prevents disk/memory DoS
    app.config["MAX_CONTENT_LENGTH"] = 64 * 1024 * 1024  # 64 MB (backup imports)

    # ── Reverse proxy support (opt-in) ──
    # Set TRUSTED_PROXY=1 when running behind a reverse proxy so
    # request.remote_addr reflects the real client IP (X-Forwarded-For).
    if os.environ.get("TRUSTED_PROXY", "").lower() in ("1", "true", "yes"):
        from werkzeug.middleware.proxy_fix import ProxyFix
        app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)

    # ── Session security ──
    # Set COOKIE_SECURE=1 when serving over HTTPS
    cookie_secure = os.environ.get("COOKIE_SECURE", "").lower() in ("1", "true", "yes")
    app.config["SESSION_COOKIE_SECURE"] = cookie_secure
    app.config["REMEMBER_COOKIE_SECURE"] = cookie_secure
    app.config["SESSION_COOKIE_HTTPONLY"] = True
    app.config["SESSION_COOKIE_SAMESITE"] = "Lax"
    app.config["REMEMBER_COOKIE_HTTPONLY"] = True
    app.config["REMEMBER_COOKIE_DURATION"] = timedelta(days=14)
    app.config["PERMANENT_SESSION_LIFETIME"] = timedelta(days=7)

    # ── SMTP config (all optional) ──
    app.config["SMTP_HOST"] = os.environ.get("SMTP_HOST", "")
    app.config["SMTP_PORT"] = int(os.environ.get("SMTP_PORT", "587"))
    app.config["SMTP_USER"] = os.environ.get("SMTP_USER", "")
    app.config["SMTP_PASS"] = os.environ.get("SMTP_PASS", "")
    app.config["SMTP_FROM"] = os.environ.get("SMTP_FROM", "")
    app.config["SMTP_TLS"] = os.environ.get("SMTP_TLS", "true").lower() == "true"

    # Static files: cache for an hour (tokens.css is version-stamped, sw.js is served no-cache below)
    app.config["SEND_FILE_MAX_AGE_DEFAULT"] = timedelta(hours=1)

    db.init_app(app)
    csrf.init_app(app)

    login_manager = LoginManager()
    login_manager.login_view = "auth.login"
    login_manager.session_protection = "strong"
    login_manager.init_app(app)

    @login_manager.user_loader
    def load_user(user_id):
        return db.session.get(User, int(user_id))

    from routes.auth import auth_bp
    from routes.recipes import recipes_bp
    from routes.admin import admin_bp
    from routes.calculators import calc_bp
    from routes.shopping import shopping_bp
    from routes.mealplan import mealplan_bp
    from routes.collections import collections_bp
    from routes.api import api_bp
    from routes.extras import extras_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(recipes_bp)
    app.register_blueprint(admin_bp)
    app.register_blueprint(calc_bp)
    app.register_blueprint(shopping_bp)
    app.register_blueprint(mealplan_bp)
    app.register_blueprint(collections_bp)
    app.register_blueprint(api_bp)
    app.register_blueprint(extras_bp)

    @app.after_request
    def set_security_headers(response):
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "SAMEORIGIN"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        # CSP: allow self, inline styles (needed for our CSS), and external images/fonts
        csp = (
            "default-src 'self'; "
            "script-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com; "
            "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
            "font-src 'self' https://fonts.gstatic.com; "
            "img-src 'self' https: data:; "
            "frame-src 'self' https:; "
            "connect-src 'self'"
        )
        response.headers["Content-Security-Policy"] = csp
        return response

    _COMPRESSIBLE = ("text/html", "text/css", "text/plain", "application/javascript",
                     "application/json", "text/javascript", "image/svg+xml")

    @app.after_request
    def gzip_response(response):
        """Gzip text responses (HTML carries ~10KB of inline CSS per page).
        Skips streamed/file responses, small bodies and clients without gzip."""
        import gzip
        if (response.direct_passthrough or response.status_code < 200 or response.status_code in (204, 304)
                or "Content-Encoding" in response.headers
                or "gzip" not in request.headers.get("Accept-Encoding", "")
                or (response.mimetype or "") not in _COMPRESSIBLE):
            return response
        data = response.get_data()
        if len(data) < 1024:
            return response
        response.set_data(gzip.compress(data, compresslevel=6))
        response.headers["Content-Encoding"] = "gzip"
        response.headers["Content-Length"] = str(len(response.get_data()))
        response.headers.add("Vary", "Accept-Encoding")
        if response.headers.get("ETag") and not response.headers["ETag"].endswith('-gzip"'):
            response.headers["ETag"] = response.headers["ETag"].rstrip('"') + '-gzip"'
        return response

    with app.app_context():
        # Run migrations first (adds missing columns/tables to existing DB)
        from migrate import migrate
        migrate(f"{data_dir}/recipes.db")
        # Then create any remaining new tables
        db.create_all()

    @app.context_processor
    def inject_settings():
        def get_setting(key, default=""):
            # Load all settings once per request instead of one query per call
            if not hasattr(g, "_site_settings"):
                g._site_settings = {row.key: row.value for row in SiteSetting.query.all()}
            return g._site_settings.get(key, default)

        try:
            asset_v = int(max(
                os.path.getmtime(os.path.join(app.static_folder, d, n))
                for d in ("css", "js") if os.path.isdir(os.path.join(app.static_folder, d))
                for n in os.listdir(os.path.join(app.static_folder, d)) if n.endswith((".css", ".js"))))
        except (OSError, ValueError):
            asset_v = 0
        return dict(get_setting=get_setting, asset_v=asset_v)

    @app.template_filter('recipe_image')
    def recipe_image_filter(image_url):
        """Convert image_url to proper URL - local file or external URL."""
        if not image_url:
            return ""
        # If it's already a full URL, return as-is (unless it's a broken Mealie URL)
        if image_url.startswith(('http://', 'https://', '//')):
            # Skip broken Mealie API URLs - they require auth and won't work
            if '/api/media/recipes/' in image_url:
                return ""
            return image_url
        # If it starts with /, it's already an absolute path
        if image_url.startswith('/'):
            return image_url
        # Otherwise it's a local filename in uploads
        return f"/admin/uploads/{image_url}"

    @app.route("/sw.js")
    def service_worker():
        """Serve the service worker from the root so its scope covers '/'
        (a SW under /static/ could only control /static/)."""
        from flask import send_from_directory
        resp = send_from_directory(app.static_folder, "sw.js",
                                   mimetype="application/javascript")
        resp.headers["Cache-Control"] = "no-cache"
        return resp

    @app.template_filter('recipe_thumb')
    def recipe_thumb_filter(image_url):
        """Like recipe_image, but prefers a local thumbnail when one exists."""
        if not image_url:
            return ""
        if image_url.startswith(('http://', 'https://', '//', '/')):
            return recipe_image_filter(image_url)
        thumb_name = f"thumb_{image_url}"
        thumb_path = os.path.join(data_dir, "uploads", thumb_name)
        if os.path.exists(thumb_path):
            return f"/admin/uploads/{thumb_name}"
        return f"/admin/uploads/{image_url}"

    return app


if __name__ == "__main__":
    create_app().run(host="0.0.0.0")