"""Image upload processing: content verification, resizing, EXIF stripping,
and thumbnail generation (Pillow)."""
import os
import uuid

from PIL import Image, UnidentifiedImageError

MAX_DIMENSION = 1600   # main image long edge
THUMB_DIMENSION = 480  # thumbnail long edge

# Pillow format -> (extension, save kwargs)
_FORMATS = {
    "JPEG": ("jpg", {"quality": 85, "optimize": True}),
    "PNG": ("png", {"optimize": True}),
    "WEBP": ("webp", {"quality": 85}),
    "GIF": ("gif", {}),
}


def save_uploaded_image(file_storage, uploads_dir, prefix="recipe",
                        max_dim=MAX_DIMENSION, make_thumb=True):
    """Verify, sanitise and save an uploaded image.

    - Verifies the file really is an image (content, not just extension)
    - Re-encodes to strip EXIF/metadata
    - Resizes to max_dim on the long edge
    - Writes a thumb_<name> alongside (skipped for animated GIFs)

    Returns the saved filename, or "" if the file is missing/invalid.
    """
    if not file_storage or not file_storage.filename:
        return ""
    os.makedirs(uploads_dir, exist_ok=True)

    try:
        img = Image.open(file_storage.stream)
        img.verify()  # cheap integrity check
        file_storage.stream.seek(0)
        img = Image.open(file_storage.stream)  # reopen after verify()
        img.load()
    except (UnidentifiedImageError, OSError, ValueError):
        return ""

    fmt = (img.format or "").upper()
    if fmt not in _FORMATS:
        return ""
    ext, save_kwargs = _FORMATS[fmt]
    filename = f"{prefix}_{uuid.uuid4().hex[:12]}.{ext}"
    filepath = os.path.join(uploads_dir, filename)

    animated = fmt == "GIF" and getattr(img, "n_frames", 1) > 1
    try:
        if animated:
            # Re-encoding would lose animation; save raw bytes (already
            # verified as a real GIF). GIFs carry no EXIF.
            file_storage.stream.seek(0)
            with open(filepath, "wb") as f:
                f.write(file_storage.stream.read())
        else:
            out = img
            if fmt == "JPEG" and out.mode not in ("RGB", "L"):
                out = out.convert("RGB")
            out.thumbnail((max_dim, max_dim))  # no-op if already smaller
            # Re-save without the exif kwarg -> metadata stripped
            out.save(filepath, format=fmt, **save_kwargs)

        if make_thumb and not animated:
            thumb = img.copy()
            if fmt == "JPEG" and thumb.mode not in ("RGB", "L"):
                thumb = thumb.convert("RGB")
            thumb.thumbnail((THUMB_DIMENSION, THUMB_DIMENSION))
            thumb.save(os.path.join(uploads_dir, f"thumb_{filename}"),
                       format=fmt, **save_kwargs)
    except OSError:
        # Clean up partial writes
        for p in (filepath, os.path.join(uploads_dir, f"thumb_{filename}")):
            if os.path.exists(p):
                try:
                    os.remove(p)
                except OSError:
                    pass
        return ""

    return filename


def delete_image(uploads_dir, filename):
    """Remove an uploaded image and its thumbnail if present."""
    if not filename or "/" in filename or "\\" in filename or ".." in filename:
        return
    for name in (filename, f"thumb_{filename}"):
        path = os.path.join(uploads_dir, name)
        if os.path.exists(path):
            try:
                os.remove(path)
            except OSError:
                pass
