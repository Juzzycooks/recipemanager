"""Households: people who share one shopping list.

A user with no household sees only the items they added. In a household, the list is every item
added by any member, and any member may tick, rename or delete any of them. Items stay keyed to
the person who added them, so leaving takes your own items with you.
"""
import hashlib
import secrets

from models import db, Household, ShoppingListItem, User

# No 0/O, 1/I/L: easy to read out and type
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 8
NAME_MAX = 100


class HouseholdError(Exception):
    """kind: 'conflict' (already in one), 'not_found' (bad code), 'forbidden', 'validation'."""

    def __init__(self, kind, message):
        super().__init__(message)
        self.kind, self.message = kind, message


def normalise_code(raw):
    """'abcd-efgh', 'ABCD EFGH' and 'abcdefgh' all become 'ABCDEFGH'."""
    return "".join(ch for ch in str(raw or "").upper() if ch not in " -\t")


def format_code(code):
    """'ABCDEFGH' -> 'ABCD-EFGH'."""
    code = code or ""
    return f"{code[:4]}-{code[4:]}" if len(code) == CODE_LENGTH else code


def _new_code():
    while True:
        code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
        if not Household.query.filter_by(invite_code=code).first():
            return code


def member_ids(user):
    """Ids of everyone whose items appear on this user's shopping list."""
    if user is None:
        return []
    if not user.household_id:
        return [user.id]
    ids = [uid for (uid,) in db.session.query(User.id).filter(User.household_id == user.household_id)]
    return ids or [user.id]


def member_ids_for(user_id):
    return member_ids(db.session.get(User, user_id))


def shopping_query(user):
    """Every item on the user's (household) shopping list."""
    return ShoppingListItem.query.filter(ShoppingListItem.user_id.in_(member_ids(user)))


def can_edit_item(user, item):
    return item is not None and item.user_id in member_ids(user)


def list_version(user):
    """Changes whenever the visible list changes: an add, edit, tick or delete by any member.
    A hash of every visible item's id, tick and updated_at (so deletes change it too)."""
    rows = (db.session.query(ShoppingListItem.id, ShoppingListItem.checked, ShoppingListItem.updated_at,
                             ShoppingListItem.created_at)
            .filter(ShoppingListItem.user_id.in_(member_ids(user)))
            .order_by(ShoppingListItem.id).all())
    h = hashlib.sha1(str(len(rows)).encode())
    for item_id, checked, updated, created in rows:
        h.update(f"|{item_id}:{int(bool(checked))}:{(updated or created or '')}".encode())
    return h.hexdigest()[:16]


def summary(user):
    """The API / page shape: None, or {id, name, invite_code, is_owner, members[{id, username}]}."""
    hh = db.session.get(Household, user.household_id) if user.household_id else None
    if hh is None:
        return None
    members = User.query.filter_by(household_id=hh.id).order_by(User.id).all()
    return {"id": hh.id, "name": hh.name, "invite_code": format_code(hh.invite_code),
            "is_owner": hh.owner_id == user.id,
            "members": [{"id": m.id, "username": m.username} for m in members]}


def create(user, name):
    """Make a household with this user as its only member and owner. Does not commit."""
    if user.household_id:
        raise HouseholdError("conflict", "You're already in a household. Leave it first to start a new one.")
    name = (name or "").strip()[:NAME_MAX]
    if not name:
        raise HouseholdError("validation", "Give the household a name.")
    hh = Household(name=name, invite_code=_new_code(), owner_id=user.id)
    db.session.add(hh)
    db.session.flush()
    user.household_id = hh.id
    return hh


def join(user, code):
    """Join by invite code (any case, spaces or dash). The user's own items join the shared list."""
    if user.household_id:
        raise HouseholdError("conflict", "You're already in a household. Leave it first to join another.")
    code = normalise_code(code)
    hh = Household.query.filter_by(invite_code=code).first() if code else None
    if hh is None:
        raise HouseholdError("not_found", "No household has that code. Check it and try again.")
    user.household_id = hh.id
    if hh.owner_id is None:
        hh.owner_id = user.id
    return hh


def leave(user):
    """Leave the household. Your own items leave with you; the owner role passes to the
    longest-standing member (lowest id); an empty household is deleted. Does not commit."""
    hh = db.session.get(Household, user.household_id) if user.household_id else None
    user.household_id = None
    if hh is None:
        return
    db.session.flush()
    rest = User.query.filter_by(household_id=hh.id).order_by(User.id).all()
    if not rest:
        db.session.delete(hh)
    elif hh.owner_id == user.id or hh.owner_id not in {m.id for m in rest}:
        hh.owner_id = rest[0].id


def regenerate_code(user):
    hh = db.session.get(Household, user.household_id) if user.household_id else None
    if hh is None:
        raise HouseholdError("not_found", "You're not in a household.")
    if hh.owner_id != user.id:
        raise HouseholdError("forbidden", "Only the household's owner can make a new invite code.")
    hh.invite_code = _new_code()
    return hh
