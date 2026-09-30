<p align="center">
  <h1 align="center">Spoonmate</h1>
  <p align="center">
    A self-hosted recipe management app built with Flask for Docker and Unraid.
    <br />
    <code>docker pull juzzycooks/recipemanager:latest</code>
  </p>
</p>

---

## About

Spoonmate is a lightweight, self-hosted web app for storing, organising, and sharing your recipes. Import from any recipe website, plan your weekly meals, build public collections for social media, and cook hands-free with step-by-step cook mode.

Built for home servers and Unraid — just pull the Docker image and go.

---

## Features

<table>
<tr>
<td width="50%" valign="top">

### Recipes
- Import from URL (single or bulk)
- Import from Mealie v4 (with images)
- Import from TikTok, Instagram, Facebook
- Import from PDF cookbooks
- Upload images or pull from web
- Search by title or ingredient
- Duplicate, edit, export, print
- Categories and tags
- Favorites, ratings (1-5 stars), comments
- Personal notes per recipe
- "Made it" counter with cook history

</td>
<td width="50%" valign="top">

### Collections & Sharing
- Group recipes into themed collections
- Auto-populate collections from categories
- Custom cover images
- Custom URL slugs (e.g. `/collections/shared/bbq-favourites`)
- Drag-and-drop recipe reordering
- Public share links (no login required)
- Public cook mode and print view
- Dark mode on public pages
- Share individual recipes via link
- Email recipes to anyone
- OG meta tags for social media previews

</td>
</tr>
<tr>
<td width="50%" valign="top">

### Meal Planning
- Weekly calendar view
- Drag-and-drop to reorder/move meals
- Auto-generate a week of meals
- Generate shopping list from meal plan
- Breakfast, lunch, dinner, snack slots

</td>
<td width="50%" valign="top">

### Cook Mode
- Full-screen step-by-step instructions
- Ingredient checklist with strikethrough
- Progress bar
- Screen wake lock
- Cooking timers with audio alerts
- Browser notifications

</td>
</tr>
<tr>
<td width="50%" valign="top">

### Organisation
- Grid or list view toggle
- Sort by newest, oldest, A-Z, Z-A
- Pagination (24 per page)
- Filter by category, collection, favorites
- Random recipe picker ("Surprise me")
- Unit converter (volume, weight, temp)
- Embedded calculators (iframe)

</td>
<td width="50%" valign="top">

### Admin & Security
- User management with admin roles
- SMTP email (Gmail App Passwords)
- Custom site name and logo
- Dark mode with system detection
- CSRF protection
- Login rate limiting
- Scrypt password hashing
- Security headers (CSP, XSS, etc.)
- Auto database migrations on startup

</td>
</tr>
</table>

---

## Quick Start

### Docker Compose

```yaml
version: "3"
services:
  recipemanager:
    image: juzzycooks/recipemanager:latest
    container_name: RecipeManager
    ports:
      - "8114:5000"
    volumes:
      - /mnt/user/appdata/RecipeManager:/app/data
    environment:
      - SMTP_HOST=smtp.gmail.com
      - SMTP_PORT=465
      - SMTP_USER=your@gmail.com
      - SMTP_PASS=your-app-password
      - SMTP_FROM=your@gmail.com
      - SMTP_TLS=true
    network_mode: bridge
    restart: unless-stopped
```

### First Run

1. Start the container
2. Visit `http://your-server:8114`
3. Create your account — first user is automatically admin
4. Head to **Admin > Settings** to set your site name, logo, and SMTP

---

## Environment Variables

| Variable | Description | Default |
|:---------|:------------|:--------|
| `DATA_DIR` | Data storage path inside container | `/app/data` |
| `FLASK_SECRET_KEY` | Session secret key | Auto-generated |
| `SMTP_HOST` | SMTP server hostname | — |
| `SMTP_PORT` | SMTP port (`465` for Gmail SSL) | `587` |
| `SMTP_USER` | SMTP username | — |
| `SMTP_PASS` | SMTP password / App Password | — |
| `SMTP_FROM` | Sender email address | — |
| `SMTP_TLS` | Enable TLS/SSL | `true` |
| `PUID` / `PGID` | User/group the app runs as (container drops root) | `99` / `100` |
| `TRUSTED_PROXY` | Set to `1` behind a reverse proxy (real client IPs for rate limiting) | — |
| `COOKIE_SECURE` | Set to `1` when serving over HTTPS (Secure cookies) | — |

---

## Data Storage

All persistent data lives in the mounted volume (`/app/data`):

```
/app/data/
├── recipes.db          # SQLite database
├── uploads/            # Recipe images, logo
└── .secret_key         # Auto-generated Flask secret
```

> Back up this directory to preserve all your data.

---

## Development

```bash
pip install -r requirements.txt
python main.py
```

### Build & Push

```bash
docker build -t juzzycooks/recipemanager:latest .
docker push juzzycooks/recipemanager:latest
```

---

## Tech Stack

| | |
|:--|:--|
| Backend | Flask, Gunicorn, SQLAlchemy |
| Database | SQLite |
| Auth | Flask-Login, scrypt hashing |
| Security | Flask-WTF CSRF, rate limiting, CSP headers |
| Frontend | Jinja2, vanilla JS, Inter font |
| Container | Multi-stage Alpine Docker build |
| Migrations | Automatic on startup (zero downtime upgrades) |

---

## License

This project is for personal use.
