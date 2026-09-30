"""Text recognition for recipe photos and screenshots (Tesseract, runs locally).

Nothing leaves the server: images are OCR'd in-process and only the resulting
text is kept. Tesseract is installed in the Docker image; when it is missing
(local dev without it) `ocr_available()` is False and the UI says so.
"""
import io
import shutil

from PIL import Image, ImageOps, ImageStat

MAX_IMAGES = 8
MAX_PIXELS = 40_000_000


class OcrError(Exception):
    """Raised with a user-presentable message."""


def ocr_available():
    if not shutil.which("tesseract"):
        return False
    try:
        import pytesseract  # noqa: F401
    except ImportError:
        return False
    return True


def _prepare(img):
    """Make a screenshot or phone photo friendlier to Tesseract."""
    img = ImageOps.exif_transpose(img)
    img = img.convert("L")
    # Small screenshots OCR badly: scale text up to a comfortable size
    if img.width < 1400:
        scale = 1600 / img.width
        img = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
    # Dark-mode screenshots (light text on dark) confuse it: invert them
    if ImageStat.Stat(img).mean[0] < 110:
        img = ImageOps.invert(img)
    return ImageOps.autocontrast(img)


def image_to_text(data: bytes) -> str:
    import pytesseract

    try:
        img = Image.open(io.BytesIO(data))
        img.load()
    except Exception:
        raise OcrError("That file isn't a readable image.")
    if img.width * img.height > MAX_PIXELS:
        raise OcrError("That image is too large to read; try a smaller screenshot.")
    prepared = _prepare(img)
    text = pytesseract.image_to_string(prepared, config="--oem 1 --psm 4", timeout=90)
    if len(text.strip()) < 20:
        text = pytesseract.image_to_string(prepared, config="--oem 1 --psm 6", timeout=90)
    return text.strip()


def images_to_text(blobs):
    """OCR several images (e.g. a recipe split over multiple screenshots) in order."""
    if not ocr_available():
        raise OcrError("Photo import needs Tesseract, which isn't installed on this server.")
    if not blobs:
        raise OcrError("No images were uploaded.")
    if len(blobs) > MAX_IMAGES:
        raise OcrError(f"Please upload at most {MAX_IMAGES} images at a time.")
    parts = [image_to_text(b) for b in blobs]
    return "\n".join(p for p in parts if p)
