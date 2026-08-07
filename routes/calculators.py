from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_required
from models import db, Calculator

calc_bp = Blueprint("calculators", __name__)


@calc_bp.route("/calculators")
@login_required
def index():
    calcs = Calculator.query.order_by(Calculator.sort_order, Calculator.name).all()
    return render_template("calculators/index.html", calculators=calcs)


@calc_bp.route("/calculators/<int:calc_id>")
@login_required
def view(calc_id):
    calc = Calculator.query.get_or_404(calc_id)
    return render_template("calculators/view.html", calc=calc)
