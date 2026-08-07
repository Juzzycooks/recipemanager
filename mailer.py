import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.utils import formataddr
from flask import current_app, request


def send_welcome_email(to_email, username, password):
    """Send a welcome email with login credentials to a new user."""
    cfg = current_app.config
    if not cfg.get("SMTP_HOST") or not to_email:
        return False

    # Get the site URL
    site_url = request.url_root.rstrip('/')

    msg = MIMEMultipart("alternative")
    msg["Subject"] = "Welcome to Recipe Manager"
    
    # Format From header as "Display Name <email>" if SMTP_FROM is set
    from_email = cfg["SMTP_USER"]
    from_name = cfg.get("SMTP_FROM", "").strip()
    if from_name:
        msg["From"] = formataddr((from_name, from_email))
    else:
        msg["From"] = from_email
    
    msg["To"] = to_email

    text = (
        f"Hi {username},\n\n"
        f"Your Recipe Manager account has been created.\n\n"
        f"Username: {username}\n"
        f"Password: {password}\n\n"
        f"Log in here: {site_url}\n\n"
        f"Please change your password after logging in.\n\n"
        f"Happy cooking!"
    )
    html = (
        f"<h2>Welcome to Recipe Manager 🍳</h2>"
        f"<p>Hi <strong>{username}</strong>,</p>"
        f"<p>Your account has been created. Here are your login details:</p>"
        f"<table style='border-collapse:collapse;'>"
        f"<tr><td style='padding:4px 12px;font-weight:600;'>Username</td>"
        f"<td style='padding:4px 12px;'>{username}</td></tr>"
        f"<tr><td style='padding:4px 12px;font-weight:600;'>Password</td>"
        f"<td style='padding:4px 12px;'><code>{password}</code></td></tr>"
        f"</table>"
        f"<p style='margin-top:16px;'><a href='{site_url}' style='display:inline-block;padding:10px 20px;"
        f"background:#c0440e;color:#fff;text-decoration:none;border-radius:6px;font-weight:600;'>Log In Now</a></p>"
        f"<p style='margin-top:16px;'>Please change your password after logging in.</p>"
        f"<p>Happy cooking! 🍽️</p>"
    )

    msg.attach(MIMEText(text, "plain"))
    msg.attach(MIMEText(html, "html"))

    try:
        port = cfg["SMTP_PORT"]
        if port == 465:
            # Implicit SSL (SMTPS)
            server = smtplib.SMTP_SSL(cfg["SMTP_HOST"], port)
        else:
            server = smtplib.SMTP(cfg["SMTP_HOST"], port)
            server.ehlo()
            if cfg.get("SMTP_TLS"):
                server.starttls()
                server.ehlo()
        if cfg.get("SMTP_USER"):
            server.login(cfg["SMTP_USER"], cfg["SMTP_PASS"])
        server.sendmail(from_email, [to_email], msg.as_string())
        server.quit()
        return True
    except Exception as e:
        current_app.logger.error(f"Failed to send email: {e}")
        return False


def send_password_reset_email(to_email, username, reset_url):
    """Send a password reset link. Returns True on success."""
    cfg = current_app.config
    if not cfg.get("SMTP_HOST") or not to_email:
        return False

    msg = MIMEMultipart("alternative")
    msg["Subject"] = "Reset your Recipe Manager password"

    from_email = cfg["SMTP_USER"]
    from_name = cfg.get("SMTP_FROM", "").strip()
    if from_name:
        msg["From"] = formataddr((from_name, from_email))
    else:
        msg["From"] = from_email
    msg["To"] = to_email

    text = (
        f"Hi {username},\n\n"
        f"A password reset was requested for your Recipe Manager account.\n\n"
        f"Reset your password here (link valid for 1 hour):\n{reset_url}\n\n"
        f"If you didn't request this, you can ignore this email."
    )
    html = (
        f"<h2>Password reset</h2>"
        f"<p>Hi <strong>{username}</strong>,</p>"
        f"<p>A password reset was requested for your Recipe Manager account.</p>"
        f"<p><a href='{reset_url}' style='display:inline-block;padding:10px 20px;"
        f"background:#c0440e;color:#fff;text-decoration:none;border-radius:6px;font-weight:600;'>"
        f"Reset password</a></p>"
        f"<p style='color:#666;font-size:13px;'>This link is valid for 1 hour. "
        f"If you didn't request this, you can ignore this email.</p>"
    )

    msg.attach(MIMEText(text, "plain"))
    msg.attach(MIMEText(html, "html"))

    try:
        port = cfg["SMTP_PORT"]
        if port == 465:
            server = smtplib.SMTP_SSL(cfg["SMTP_HOST"], port)
        else:
            server = smtplib.SMTP(cfg["SMTP_HOST"], port)
            server.ehlo()
            if cfg.get("SMTP_TLS"):
                server.starttls()
                server.ehlo()
        if cfg.get("SMTP_USER"):
            server.login(cfg["SMTP_USER"], cfg["SMTP_PASS"])
        server.sendmail(from_email, [to_email], msg.as_string())
        server.quit()
        return True
    except Exception as e:
        current_app.logger.error(f"Failed to send reset email: {e}")
        return False


def send_recipe_email(to_email, recipe, sender_name):
    """Email a recipe to someone."""
    cfg = current_app.config
    if not cfg.get("SMTP_HOST") or not to_email:
        return False

    site_url = request.url_root.rstrip('/')

    msg = MIMEMultipart("alternative")
    msg["Subject"] = f"Recipe: {recipe.title}"

    from_email = cfg["SMTP_USER"]
    from_name = cfg.get("SMTP_FROM", "").strip()
    if from_name:
        msg["From"] = formataddr((from_name, from_email))
    else:
        msg["From"] = from_email
    msg["To"] = to_email

    ingredients = "\n".join(f"  - {line.strip()}" for line in recipe.ingredients.split("\n") if line.strip())
    instructions = "\n".join(f"  {i+1}. {line.strip()}" for i, line in enumerate(recipe.instructions.split("\n")) if line.strip())

    text = (
        f"{sender_name} shared a recipe with you!\n\n"
        f"{recipe.title}\n{'='*len(recipe.title)}\n\n"
        f"{recipe.description}\n\n"
        f"Prep: {recipe.prep_time or 'N/A'} | Cook: {recipe.cook_time or 'N/A'} | Servings: {recipe.servings or 'N/A'}\n\n"
        f"Ingredients:\n{ingredients}\n\n"
        f"Instructions:\n{instructions}\n\n"
        f"---\nSent from Recipe Manager"
    )

    ing_html = "".join(f"<li>{line.strip()}</li>" for line in recipe.ingredients.split("\n") if line.strip())
    ins_html = "".join(f"<li style='margin-bottom:8px;'>{line.strip()}</li>" for line in recipe.instructions.split("\n") if line.strip())

    html = (
        f"<div style='max-width:600px;margin:0 auto;font-family:-apple-system,sans-serif;'>"
        f"<p style='color:#666;'>{sender_name} shared a recipe with you</p>"
        f"<h1 style='color:#1a1a1a;'>{recipe.title}</h1>"
        f"{'<p style=\"color:#666;\">' + recipe.description + '</p>' if recipe.description else ''}"
        f"<div style='display:flex;gap:24px;padding:12px 0;border-top:1px solid #e5e5e3;border-bottom:1px solid #e5e5e3;margin:16px 0;color:#666;font-size:14px;'>"
        f"{'<span>Prep: ' + recipe.prep_time + '</span>' if recipe.prep_time else ''}"
        f"{'<span>Cook: ' + recipe.cook_time + '</span>' if recipe.cook_time else ''}"
        f"{'<span>Servings: ' + recipe.servings + '</span>' if recipe.servings else ''}"
        f"</div>"
        f"<h3 style='color:#c0440e;text-transform:uppercase;font-size:13px;letter-spacing:0.04em;'>Ingredients</h3>"
        f"<ul style='padding-left:20px;'>{ing_html}</ul>"
        f"<h3 style='color:#c0440e;text-transform:uppercase;font-size:13px;letter-spacing:0.04em;margin-top:24px;'>Instructions</h3>"
        f"<ol style='padding-left:20px;'>{ins_html}</ol>"
        f"<hr style='border:none;border-top:1px solid #e5e5e3;margin-top:24px;'>"
        f"<p style='font-size:12px;color:#999;'>Sent from <a href='{site_url}' style='color:#c0440e;'>Recipe Manager</a></p>"
        f"</div>"
    )

    msg.attach(MIMEText(text, "plain"))
    msg.attach(MIMEText(html, "html"))

    try:
        port = cfg["SMTP_PORT"]
        if port == 465:
            server = smtplib.SMTP_SSL(cfg["SMTP_HOST"], port)
        else:
            server = smtplib.SMTP(cfg["SMTP_HOST"], port)
            server.ehlo()
            if cfg.get("SMTP_TLS"):
                server.starttls()
                server.ehlo()
        if cfg.get("SMTP_USER"):
            server.login(cfg["SMTP_USER"], cfg["SMTP_PASS"])
        server.sendmail(from_email, [to_email], msg.as_string())
        server.quit()
        return True
    except Exception as e:
        current_app.logger.error(f"Failed to send recipe email: {e}")
        return False
