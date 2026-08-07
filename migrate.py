"""
Auto-migration for SQLite database.
Adds missing columns and tables on startup without data loss.
"""
import sqlite3
import os


def get_existing_columns(cursor, table_name):
    """Get list of existing column names for a table."""
    cursor.execute(f"PRAGMA table_info({table_name})")
    return {row[1] for row in cursor.fetchall()}


def get_existing_tables(cursor):
    """Get list of existing table names."""
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
    return {row[0] for row in cursor.fetchall()}


def migrate(db_path):
    """Run migrations on the database."""
    if not os.path.exists(db_path):
        return  # New database, will be created by SQLAlchemy

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    existing_tables = get_existing_tables(cursor)

    # ── Recipe table migrations ──
    if "recipe" in existing_tables:
        recipe_cols = get_existing_columns(cursor, "recipe")

        if "notes" not in recipe_cols:
            try:
                cursor.execute("ALTER TABLE recipe ADD COLUMN notes TEXT DEFAULT ''")
                print("Migration: Added 'notes' column to recipe table")
            except sqlite3.OperationalError:
                pass

        if "share_token" not in recipe_cols:
            try:
                cursor.execute("ALTER TABLE recipe ADD COLUMN share_token VARCHAR(32)")
                print("Migration: Added 'share_token' column to recipe table")
            except sqlite3.OperationalError:
                pass

        try:
            cursor.execute("CREATE UNIQUE INDEX IF NOT EXISTS ix_recipe_share_token ON recipe(share_token)")
        except sqlite3.OperationalError:
            pass

    # ── New tables (IF NOT EXISTS prevents race conditions with multiple workers) ──
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS favorite (
            id INTEGER PRIMARY KEY,
            user_id INTEGER NOT NULL,
            recipe_id INTEGER NOT NULL,
            created_at DATETIME,
            FOREIGN KEY (user_id) REFERENCES user(id),
            FOREIGN KEY (recipe_id) REFERENCES recipe(id),
            UNIQUE (user_id, recipe_id)
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS rating (
            id INTEGER PRIMARY KEY,
            user_id INTEGER NOT NULL,
            recipe_id INTEGER NOT NULL,
            score INTEGER NOT NULL,
            created_at DATETIME,
            FOREIGN KEY (user_id) REFERENCES user(id),
            FOREIGN KEY (recipe_id) REFERENCES recipe(id),
            UNIQUE (user_id, recipe_id)
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS comment (
            id INTEGER PRIMARY KEY,
            user_id INTEGER NOT NULL,
            recipe_id INTEGER NOT NULL,
            text TEXT NOT NULL,
            created_at DATETIME,
            FOREIGN KEY (user_id) REFERENCES user(id),
            FOREIGN KEY (recipe_id) REFERENCES recipe(id)
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS meal_plan (
            id INTEGER PRIMARY KEY,
            user_id INTEGER NOT NULL,
            recipe_id INTEGER NOT NULL,
            date DATE NOT NULL,
            meal_type VARCHAR(20) DEFAULT 'dinner',
            created_at DATETIME,
            FOREIGN KEY (user_id) REFERENCES user(id),
            FOREIGN KEY (recipe_id) REFERENCES recipe(id)
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS site_setting (
            id INTEGER PRIMARY KEY,
            key VARCHAR(100) UNIQUE NOT NULL,
            value TEXT DEFAULT ''
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS cook_log (
            id INTEGER PRIMARY KEY,
            user_id INTEGER NOT NULL,
            recipe_id INTEGER NOT NULL,
            cooked_at DATETIME,
            FOREIGN KEY (user_id) REFERENCES user(id),
            FOREIGN KEY (recipe_id) REFERENCES recipe(id)
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS collection (
            id INTEGER PRIMARY KEY,
            name VARCHAR(200) NOT NULL,
            description TEXT DEFAULT '',
            user_id INTEGER NOT NULL,
            share_token VARCHAR(32),
            slug VARCHAR(200),
            cover_image VARCHAR(500) DEFAULT '',
            category_id INTEGER REFERENCES category(id),
            created_at DATETIME,
            FOREIGN KEY (user_id) REFERENCES user(id)
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS recipe_collections (
            recipe_id INTEGER NOT NULL,
            collection_id INTEGER NOT NULL,
            PRIMARY KEY (recipe_id, collection_id),
            FOREIGN KEY (recipe_id) REFERENCES recipe(id),
            FOREIGN KEY (collection_id) REFERENCES collection(id)
        )
    """)

    # ── MealPlan table: add sort_order column ──
    if "meal_plan" in existing_tables:
        mp_cols = get_existing_columns(cursor, "meal_plan")
        if "sort_order" not in mp_cols:
            try:
                cursor.execute("ALTER TABLE meal_plan ADD COLUMN sort_order INTEGER DEFAULT 0")
                print("Migration: Added 'sort_order' column to meal_plan table")
            except sqlite3.OperationalError:
                pass

    # ── Collection table: add share_token and category_id columns ──
    # Re-check tables since CREATE TABLE IF NOT EXISTS may have just created it
    refreshed_tables = get_existing_tables(cursor)
    if "collection" in refreshed_tables:
        coll_cols = get_existing_columns(cursor, "collection")
        if "share_token" not in coll_cols:
            try:
                cursor.execute("ALTER TABLE collection ADD COLUMN share_token VARCHAR(32)")
                print("Migration: Added 'share_token' column to collection table")
            except sqlite3.OperationalError:
                pass
        if "category_id" not in coll_cols:
            try:
                cursor.execute("ALTER TABLE collection ADD COLUMN category_id INTEGER REFERENCES category(id)")
                print("Migration: Added 'category_id' column to collection table")
            except sqlite3.OperationalError:
                pass
        if "slug" not in coll_cols:
            try:
                cursor.execute("ALTER TABLE collection ADD COLUMN slug VARCHAR(200)")
                print("Migration: Added 'slug' column to collection table")
            except sqlite3.OperationalError:
                pass
        if "cover_image" not in coll_cols:
            try:
                cursor.execute("ALTER TABLE collection ADD COLUMN cover_image VARCHAR(500) DEFAULT ''")
                print("Migration: Added 'cover_image' column to collection table")
            except sqlite3.OperationalError:
                pass

        try:
            cursor.execute("CREATE UNIQUE INDEX IF NOT EXISTS ix_collection_share_token ON collection(share_token)")
        except sqlite3.OperationalError:
            pass
        try:
            cursor.execute("CREATE UNIQUE INDEX IF NOT EXISTS ix_collection_slug ON collection(slug)")
        except sqlite3.OperationalError:
            pass

    conn.commit()
    conn.close()
    print("Migration: Complete")
