"""Draws the Spoonmate icon (a spoon whose bowl is a leaf) and writes every size the iPhone app and the web app use,
so the two always match.

Run from the repo root:   python3 tools/generate_icons.py      (needs Pillow)

iPhone  IOS/RecipeManager/Resources/Assets.xcassets/AppIcon.appiconset/  icon.png, icon-dark.png, icon-tinted.png (1024)
Web     static/  icon-192.png, icon-512.png (rounded), icon-maskable-512.png, apple-touch-icon.png (180), favicon-32.png, favicon.ico
"""
import json, math, os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
APPICON = os.path.join(ROOT, "IOS", "RecipeManager", "Resources", "Assets.xcassets", "AppIcon.appiconset")
STATIC = os.path.join(ROOT, "static")
W = 2048  # master canvas; everything is drawn once here and scaled down (smooth edges)

# Palette: (background, glow, leaf bowl, handle). Vein cut-outs reuse the background.
LIGHT = dict(bg=(39, 78, 59), glow=(66, 106, 85), bowl=(176, 208, 184), handle=(247, 244, 237))
DARK = dict(bg=(16, 30, 23), glow=(34, 62, 48), bowl=(140, 190, 156), handle=(225, 228, 220))
TINTED = dict(bg=(20, 20, 20), glow=(48, 48, 48), bowl=(205, 205, 205), handle=(245, 245, 245))


def bezier(p0, p1, p2, p3, steps=80):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t ** 2, t ** 3
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return pts


def leaf_edges(base, length, width):
    """Left and right edges of a leaf pointing straight up: full and rounded low down, tapering to a point."""
    x, y = base
    tip = (x, y - length)
    left = bezier(base, (x - width * 0.78, y - length * 0.04), (x - width * 0.56, y - length * 0.78), tip)
    right = [(2 * x - px, py) for px, py in left]
    return left, right


def spoon(colors, detail=True):
    """The spoon, upright, on a transparent layer (leaf bowl on top, handle below)."""
    art = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)
    cx = W * 0.5
    bowl_base, bowl_len, bowl_w = (cx, W * 0.60), W * 0.50, W * 0.40

    # handle: slim at the neck, flaring to a rounded end like a real spoon
    top_y, end_y, top_r, end_r = W * 0.55, W * 0.925, W * 0.017, W * 0.040
    d.polygon([(cx - top_r, top_y), (cx + top_r, top_y), (cx + end_r, end_y), (cx - end_r, end_y)], fill=colors["handle"])
    d.ellipse([cx - end_r, end_y - end_r, cx + end_r, end_y + end_r], fill=colors["handle"])
    d.ellipse([cx - top_r, top_y - top_r, cx + top_r, top_y + top_r], fill=colors["handle"])

    # leaf bowl
    left, right = leaf_edges(bowl_base, bowl_len, bowl_w)
    d.polygon(left + right[::-1], fill=colors["bowl"])

    # veins, cut through the leaf in the background colour, always ending inside the leaf
    vein, lw = colors["bg"], int(W * 0.014)
    def half_width(t):
        target = bowl_base[1] - bowl_len * min(max(t, 0), 1)
        px, _ = min(left, key=lambda pt: abs(pt[1] - target))
        return cx - px
    def stroke(p, q):
        d.line([p, q], fill=vein, width=lw)
        for x, y in (p, q): d.ellipse([x - lw / 2, y - lw / 2, x + lw / 2, y + lw / 2], fill=vein)
    stroke((cx, bowl_base[1] - W * 0.012), (cx, bowl_base[1] - bowl_len * 0.80))
    if detail:
        rise = W * 0.06
        for t in (0.26, 0.46, 0.64):
            y = bowl_base[1] - bowl_len * t
            reach = half_width(t + rise / bowl_len) * 0.62
            stroke((cx, y), (cx - reach, y - rise)); stroke((cx, y), (cx + reach, y - rise))
    return art


def tilted_art(colors, detail=True, tilt=-28):
    art = spoon(colors, detail).rotate(tilt, resample=Image.BICUBIC, expand=True)
    return art.crop(art.getbbox())


def background(colors):
    img = Image.new("RGB", (W, W), colors["bg"])
    glow = Image.new("RGB", (W, W), colors["bg"])
    ImageDraw.Draw(glow).ellipse([W * 0.14, W * 0.08, W * 0.86, W * 0.80], fill=colors["glow"])
    return Image.blend(img, glow.filter(ImageFilter.GaussianBlur(W * 0.12)), 0.9)


def compose(colors, art_fraction, detail=True):
    """Full-bleed square icon: background + soft shadow + spoon scaled so its longest side is `art_fraction` of the icon."""
    img = background(colors).convert("RGBA")
    art = tilted_art(colors, detail)
    k = (W * art_fraction) / max(art.size)
    art = art.resize((round(art.width * k), round(art.height * k)), Image.LANCZOS)
    pos = ((W - art.width) // 2, (W - art.height) // 2)
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", art.size, (0, 0, 0, 90)), (pos[0], pos[1] + round(W * 0.012)), art)
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(W * 0.014)))
    img.alpha_composite(art, pos)
    return img


def rounded(img, radius_fraction=0.2237):
    """iOS-style rounded square with transparent corners (web 'any' icons)."""
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius=img.width * radius_fraction, fill=255)
    out = img.copy(); out.putalpha(mask)
    return out


def save(img, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path, "PNG")


if __name__ == "__main__":
    # iPhone
    for name, colors in (("icon.png", LIGHT), ("icon-dark.png", DARK), ("icon-tinted.png", TINTED)):
        save(compose(colors, 0.80).convert("RGB"), os.path.join(APPICON, name), 1024)
    size = {"idiom": "universal", "platform": "ios", "size": "1024x1024"}
    with open(os.path.join(APPICON, "Contents.json"), "w") as f:
        json.dump({"images": [
            {**size, "filename": "icon.png"},
            {**size, "filename": "icon-dark.png", "appearances": [{"appearance": "luminosity", "value": "dark"}]},
            {**size, "filename": "icon-tinted.png", "appearances": [{"appearance": "luminosity", "value": "tinted"}]},
        ], "info": {"author": "xcode", "version": 1}}, f, indent=2)

    # Web
    main = compose(LIGHT, 0.80)
    save(rounded(main), os.path.join(STATIC, "icon-192.png"), 192)
    save(rounded(main), os.path.join(STATIC, "icon-512.png"), 512)
    save(compose(LIGHT, 0.60).convert("RGB"), os.path.join(STATIC, "icon-maskable-512.png"), 512)   # inside the 80% safe zone
    save(main.convert("RGB"), os.path.join(STATIC, "apple-touch-icon.png"), 180)                   # iOS rounds it itself
    small = compose(LIGHT, 0.88, detail=False)                                                      # fewer details, bigger mark
    save(rounded(small, 0.2), os.path.join(STATIC, "favicon-32.png"), 32)
    ico = rounded(small, 0.2)
    ico.resize((48, 48), Image.LANCZOS).save(os.path.join(STATIC, "favicon.ico"), format="ICO", sizes=[(16, 16), (32, 32), (48, 48)])
    print("icons written")
