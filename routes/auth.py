import hashlib
import re
import secrets
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse
from flask import Blueprint, render_template, redirect, url_for, flash, request, session, current_app
from flask_login import login_user, logout_user, login_required, current_user
from models import db, User, LoginAttempt, PasswordResetToken

auth_bp = Blueprint("auth", __name__)

_MAX_ATTEMPTS = 5
_WINDOW = timedelta(minutes=5)
_RESET_TOKEN_TTL = timedelta(hours=1)

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def is_valid_email(addr: str) -> bool:
    """Basic format check — also blocks header-injection via CR/LF."""
    return bool(addr) and len(addr) <= 200 and bool(EMAIL_RE.match(addr))


def _now():
    return datetime.now(timezone.utc)


def _prune_attempts():
    cutoff = _now() - _WINDOW
    LoginAttempt.query.filter(LoginAttempt.created_at < cutoff).delete()


def _is_rate_limited(ip: str, username: str = "") -> bool:
    """DB-backed: shared across workers; limits per-IP and per-username."""
    _prune_attempts()
    db.session.commit()
    cutoff = _now() - _WINDOW
    ip_count = LoginAttempt.query.filter(
        LoginAttempt.ip == ip, LoginAttempt.created_at >= cutoff).count()
    if ip_count >= _MAX_ATTEMPTS:
        return True
    if username:
        user_count = LoginAttempt.query.filter(
            LoginAttempt.username == username,
            LoginAttempt.created_at >= cutoff).count()
        if user_count >= _MAX_ATTEMPTS:
            return True
    return False


def _record_attempt(ip: str, username: str = ""):
    db.session.add(LoginAttempt(ip=ip, username=username[:80]))
    db.session.commit()


def _clear_attempts(ip: str, username: str = ""):
    q = LoginAttempt.query.filter(
        db.or_(LoginAttempt.ip == ip, LoginAttempt.username == username))
    q.delete()
    db.session.commit()


def _is_safe_redirect(target: str) -> bool:
    """Only allow redirects to relative paths on the same host."""
    if not target:
        return False
    parsed = urlparse(target)
    return parsed.scheme == "" and parsed.netloc == "" and not target.startswith("//")


def _validate_password(password: str) -> str | None:
    """Return an error message if password is too weak, else None."""
    if len(password) < 8:
        return "Password must be at least 8 characters."
    if password.isdigit() or password.isalpha():
        return "Password must contain both letters and numbers."
    return None


@auth_bp.route("/setup", methods=["GET", "POST"])
def setup():
    """Initial admin setup — only works when no users exist."""
    if User.query.count() > 0:
        return redirect(url_for("auth.login"))
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        confirm = request.form.get("confirm", "")
        email = request.form.get("email", "").strip()
        if not username or not password:
            flash("Enter a username and a password to continue.", "error")
            return redirect(url_for("auth.setup"))
        if password != confirm:
            flash("Those passwords don't match. Type them again to confirm.", "error")
            return redirect(url_for("auth.setup"))
        pw_error = _validate_password(password)
        if pw_error:
            flash(pw_error, "error")
            return redirect(url_for("auth.setup"))
        if email and not is_valid_email(email):
            flash("That email address doesn't look right. Check it for typos.", "error")
            return redirect(url_for("auth.setup"))
        user = User(username=username, email=email, is_admin=True)
        user.set_password(password)
        db.session.add(user)
        db.session.commit()
        login_user(user)
        session.permanent = True
        flash("Admin account created. Welcome!", "success")
        return redirect(url_for("recipes.index"))
    return render_template("auth/setup.html")


@auth_bp.route("/login", methods=["GET", "POST"])
def login():
    if User.query.count() == 0:
        return redirect(url_for("auth.setup"))
    if request.method == "POST":
        ip = request.remote_addr or "unknown"
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        if _is_rate_limited(ip, username):
            flash("Too many tries. Wait a few minutes, then try again.", "error")
            return redirect(url_for("auth.login"))

        user = User.query.filter_by(username=username).first()
        if user and user.check_password(password):
            _clear_attempts(ip, username)
            login_user(user)
            session.permanent = True
            next_page = request.args.get("next")
            if next_page and _is_safe_redirect(next_page):
                return redirect(next_page)
            return redirect(url_for("recipes.index"))
        _record_attempt(ip, username)
        flash("Invalid username or password.", "error")
        return redirect(url_for("auth.login"))
    return render_template("auth/login.html")


@auth_bp.route("/logout")
@login_required
def logout():
    logout_user()
    flash("You're signed out. See you next time.", "success")
    return redirect(url_for("auth.login"))


# ── Profile / change password ──

@auth_bp.route("/profile", methods=["GET", "POST"])
@login_required
def profile():
    if request.method == "POST":
        action = request.form.get("action", "")

        if action == "email":
            email = request.form.get("email", "").strip()
            if email and not is_valid_email(email):
                flash("That email address doesn't look right. Check it for typos.", "error")
                return redirect(url_for("auth.profile"))
            current_user.email = email
            db.session.commit()
            flash("Email updated.", "success")
            return redirect(url_for("auth.profile"))

        if action == "password":
            current_pw = request.form.get("current_password", "")
            new_pw = request.form.get("new_password", "")
            confirm = request.form.get("confirm_password", "")
            if not current_user.check_password(current_pw):
                flash("That isn't your current password. Try again.", "error")
                return redirect(url_for("auth.profile"))
            if new_pw != confirm:
                flash("The new passwords don't match. Type them again to confirm.", "error")
                return redirect(url_for("auth.profile"))
            pw_error = _validate_password(new_pw)
            if pw_error:
                flash(pw_error, "error")
                return redirect(url_for("auth.profile"))
            current_user.set_password(new_pw)
            db.session.commit()
            flash("Password changed.", "success")
            return redirect(url_for("auth.profile"))

    return render_template("auth/profile.html")


# ── Password reset via email ──

def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


@auth_bp.route("/forgot-password", methods=["GET", "POST"])
def forgot_password():
    if current_user.is_authenticated:
        return redirect(url_for("recipes.index"))
    smtp_enabled = bool(current_app.config.get("SMTP_HOST"))
    if request.method == "POST":
        ip = request.remote_addr or "unknown"
        if _is_rate_limited(ip):
            flash("Too many tries. Wait a few minutes, then try again.", "error")
            return redirect(url_for("auth.forgot_password"))
        _record_attempt(ip)  # count reset requests against the limiter

        email = request.form.get("email", "").strip()
        if smtp_enabled and is_valid_email(email):
            user = User.query.filter_by(email=email).first()
            if user:
                token = secrets.token_urlsafe(32)
                db.session.add(PasswordResetToken(
                    user_id=user.id, token_hash=_hash_token(token)))
                db.session.commit()
                from mailer import send_password_reset_email
                reset_url = url_for("auth.reset_password", token=token, _external=True)
                send_password_reset_email(user.email, user.username, reset_url)
        # Same message whether or not the account exists (no enumeration)
        flash("If an account exists with that email, a reset link has been sent.", "success")
        return redirect(url_for("auth.login"))
    return render_template("auth/forgot.html", smtp_enabled=smtp_enabled)


@auth_bp.route("/reset-password/<token>", methods=["GET", "POST"])
def reset_password(token):
    if current_user.is_authenticated:
        return redirect(url_for("recipes.index"))
    prt = PasswordResetToken.query.filter_by(
        token_hash=_hash_token(token), used=False).first()
    valid = False
    if prt:
        created = prt.created_at
        if created.tzinfo is None:
            created = created.replace(tzinfo=timezone.utc)
        valid = (_now() - created) <= _RESET_TOKEN_TTL
    if not valid:
        flash("That reset link is invalid or has expired.", "error")
        return redirect(url_for("auth.login"))

    if request.method == "POST":
        new_pw = request.form.get("new_password", "")
        confirm = request.form.get("confirm_password", "")
        if new_pw != confirm:
            flash("Those passwords don't match. Type them again to confirm.", "error")
            return redirect(url_for("auth.reset_password", token=token))
        pw_error = _validate_password(new_pw)
        if pw_error:
            flash(pw_error, "error")
            return redirect(url_for("auth.reset_password", token=token))
        user = db.session.get(User, prt.user_id)
        user.set_password(new_pw)
        prt.used = True
        # Invalidate any other outstanding tokens for this user
        PasswordResetToken.query.filter_by(user_id=user.id, used=False)\
            .update({"used": True})
        db.session.commit()
        flash("Password reset. You can now log in.", "success")
        return redirect(url_for("auth.login"))
    return render_template("auth/reset.html", token=token)
