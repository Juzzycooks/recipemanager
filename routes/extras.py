import os
import secrets

from flask import (
    Blueprint, render_template, abort, redirect, url_for, flash,
    send_from_directory, current_app,
)
from flask_login import login_required, current_user

from models import db, ExtraShare

extras_bp = Blueprint("extras", __name__)

# Bundled standalone HTML pages, served from static/pages/.
# To add another: drop the file in static/pages/ and add an entry here.
PAGES = [
    {
        "slug": "pizza-dough-calculator",
        "name": "Pizza Dough Calculator",
        "icon": "🍕",
        "file": "pages/pizza-dough-calculator.html",
        "description": "Work out dough by pizza count, size and hydration.",
    },
    {
        "slug": "sourdough-guide",
        "name": "Sourdough Guide",
        "icon": "🍞",
        "file": "pages/sourdough-guide.html",
        "description": "Starter care and baking walkthrough.",
    },
    {
        "slug": "meal-plan",
        "name": "2-Week Meal Plan",
        "icon": "📅",
        "file": "pages/meal-plan.html",
        "description": "A two-week dinner plan at a glance.",
    },
    {
        "slug": "shish-barak",
        "name": "Shish Barak",
        "icon": "🥟",
        "file": "pages/shish-barak.html",
        "description": "Meat dumplings in yogurt sauce.",
    },
    {
        "slug": "pasteis-de-nata",
        "name": "Pastéis de Nata",
        "icon": "🥧",
        "file": "pages/pasteis-de-nata.html",
        "description": "Portuguese custard tarts — metric and scalable.",
    },
]

_BY_SLUG = {p["slug"]: p for p in PAGES}


@extras_bp.route("/extras")
@login_required
def index():
    return render_template("extras/index.html", pages=PAGES)


@extras_bp.route("/extras/<slug>")
@login_required
def view(slug):
    page = _BY_SLUG.get(slug)
    if not page:
        abort(404)
    share = ExtraShare.query.filter_by(slug=slug).first()
    return render_template("extras/view.html", page=page, share=share)


# ── External sharing ──

@extras_bp.route("/extras/<slug>/share", methods=["POST"])
@login_required
def create_share_link(slug):
    if slug not in _BY_SLUG:
        abort(404)
    share = ExtraShare.query.filter_by(slug=slug).first()
    if not share:
        share = ExtraShare(slug=slug, token=secrets.token_urlsafe(16))
        db.session.add(share)
        db.session.commit()
    flash("Share link created.", "success")
    return redirect(url_for("extras.view", slug=slug))


@extras_bp.route("/extras/<slug>/unshare", methods=["POST"])
@login_required
def remove_share_link(slug):
    share = ExtraShare.query.filter_by(slug=slug).first()
    if share:
        db.session.delete(share)
        db.session.commit()
    flash("Share link removed.", "success")
    return redirect(url_for("extras.view", slug=slug))


@extras_bp.route("/e/<token>")
def view_shared(token):
    """Public view for a shared Extras page — no login required."""
    share = ExtraShare.query.filter_by(token=token).first_or_404()
    page = _BY_SLUG.get(share.slug)
    if not page:
        abort(404)
    pages_dir = os.path.join(current_app.static_folder, "pages")
    filename = os.path.basename(page["file"])
    return send_from_directory(pages_dir, filename)
