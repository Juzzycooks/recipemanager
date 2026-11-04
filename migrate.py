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

        # Calories: the figure the recipe site published (JSON) and the cook's own per serving.
        for col, decl in (("source_nutrition", "TEXT"), ("calories_per_serving", "INTEGER")):
            if col not in recipe_cols:
                try:
                    cursor.execute(f"ALTER TABLE recipe ADD COLUMN {col} {decl}")
                    print(f"Migration: Added '{col}' column to recipe table")
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

        # Soft delete (undo for deleting a collection)
        if "deleted_at" not in coll_cols:
            try:
                cursor.execute("ALTER TABLE collection ADD COLUMN deleted_at DATETIME")
                print("Migration: Added 'deleted_at' column to collection table")
            except sqlite3.OperationalError:
                pass

        # Imports used to keep the checkbox glyph (and a bullet) at the start of ingredient/method lines.
        if "recipe" in existing_tables:
            import re
            lead = re.compile(r"^(?:[-–—•*]\s*)?[▢☐□◻☑✓✔]+\s*", re.M)
            for rid, ing, ins in cursor.execute("SELECT id, ingredients, instructions FROM recipe").fetchall():
                new_ing, new_ins = lead.sub("", ing or ""), lead.sub("", ins or "")
                if new_ing != (ing or "") or new_ins != (ins or ""):
                    cursor.execute("UPDATE recipe SET ingredients=?, instructions=? WHERE id=?", (new_ing, new_ins, rid))

    # ── Households: a shopping list shared by several people ──
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS household (
            id INTEGER PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            invite_code VARCHAR(16) NOT NULL UNIQUE,
            owner_id INTEGER,
            created_at DATETIME
        )
    """)
    if "user" in existing_tables:
        user_cols = get_existing_columns(cursor, "user")
        if "household_id" not in user_cols:
            try:
                cursor.execute("ALTER TABLE user ADD COLUMN household_id INTEGER REFERENCES household(id)")
                print("Migration: Added 'household_id' column to user table")
            except sqlite3.OperationalError:
                pass

    if "shopping_list_item" in existing_tables:
        shop_cols = get_existing_columns(cursor, "shopping_list_item")
        if "updated_at" not in shop_cols:
            try:
                cursor.execute("ALTER TABLE shopping_list_item ADD COLUMN updated_at DATETIME")
                cursor.execute("UPDATE shopping_list_item SET updated_at = created_at WHERE updated_at IS NULL")
                print("Migration: Added 'updated_at' column to shopping_list_item table")
            except sqlite3.OperationalError:
                pass

    # ── Cook log: a note and a photo per cook ──
    cook_cols = get_existing_columns(cursor, "cook_log")
    for col, decl in (("note", "TEXT DEFAULT ''"), ("photo", "VARCHAR(200) DEFAULT ''")):
        if col not in cook_cols:
            try:
                cursor.execute(f"ALTER TABLE cook_log ADD COLUMN {col} {decl}")
                print(f"Migration: Added '{col}' column to cook_log table")
            except sqlite3.OperationalError:
                pass

    conn.commit()
    conn.close()
    print("Migration: Complete")
