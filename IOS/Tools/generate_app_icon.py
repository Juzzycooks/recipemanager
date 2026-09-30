"""Draws the app icon (sprig in a bowl) at 1024x1024 in three variants and writes the AppIcon asset set.

Run from the repo root:  python3 IOS/Tools/generate_app_icon.py   (needs Pillow)
"""
import json, math, os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "RecipeManager", "Resources", "Assets.xcassets", "AppIcon.appiconset")
SIZE, SS = 1024, 4                     # final size, supersampling factor
W = SIZE * SS


def bezier(p0, p1, p2, p3, steps=60):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t ** 2, t ** 3
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return pts


def lens(base, angle_deg, length, width, steps=24):
    """A leaf: two curved edges from `base` to a tip, `length` long, `width` wide at the belly."""
    a = math.radians(angle_deg)
    ux, uy = math.cos(a), math.sin(a)
    nx, ny = -uy, ux
    left, right = [], []
    for i in range(steps + 1):
        t = i / steps
        belly = math.sin(math.pi * t) ** 0.85 * width / 2
        x, y = base[0] + ux * length * t, base[1] + uy * length * t
        left.append((x + nx * belly, y + ny * belly))
        right.append((x - nx * belly, y - ny * belly))
    return left + right[::-1]


def draw_icon(bg, bg_glow, leaf, leaf_edge, stem, bowl, bowl_shadow):
    img = Image.new("RGB", (W, W), bg)
    # soft glow behind the sprig
    glow = Image.new("RGB", (W, W), bg)
    gd = ImageDraw.Draw(glow)
    gd.ellipse([W * 0.12, W * 0.06, W * 0.88, W * 0.82], fill=bg_glow)
    glow = glow.filter(ImageFilter.GaussianBlur(W * 0.12))
    img = Image.blend(img, glow, 0.9)
    art = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)
    S = lambda x, y: (x * W, y * W)

    # stem
    stem_pts = [S(*p) for p in bezier((0.50, 0.66), (0.44, 0.50), (0.58, 0.34), (0.54, 0.16))]
    d.line(stem_pts, fill=stem, width=int(W * 0.014), joint="curve")

    def at(t):  # point along the stem
        i = min(int(t * (len(stem_pts) - 1)), len(stem_pts) - 1)
        return stem_pts[i]

    leaves = [(0.10, -28, 0.27, 0.115), (0.18, -152, 0.27, 0.115), (0.32, -30, 0.25, 0.108), (0.42, -150, 0.25, 0.108),
              (0.56, -36, 0.22, 0.095), (0.66, -144, 0.22, 0.095), (0.80, -42, 0.17, 0.076), (0.88, -138, 0.17, 0.076),
              (1.00, -90, 0.17, 0.070)]
    for t, ang, length, width in leaves:
        poly = lens(at(t), ang, length * W, width * W)
        d.polygon(poly, fill=leaf)
        d.line(poly + [poly[0]], fill=leaf_edge, width=int(W * 0.004))

    # bowl: a half-ellipse with a rim, plus a soft shadow under it
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse([W * 0.26, W * 0.80, W * 0.74, W * 0.86], fill=bowl_shadow + (90,))
    shadow = shadow.filter(ImageFilter.GaussianBlur(W * 0.018))
    art.alpha_composite(shadow)
    d = ImageDraw.Draw(art)
    left, right, top, bottom = W * 0.22, W * 0.78, W * 0.64, W * 0.86
    d.pieslice([left, top - (bottom - top), right, bottom], 0, 180, fill=bowl)
    d.rounded_rectangle([left - W * 0.012, top - W * 0.012, right + W * 0.012, top + W * 0.022], radius=W * 0.012, fill=bowl)
    # Keep the artwork inside the area iOS's rounded mask leaves visible: about 70% of the icon, centred.
    box = art.getbbox()
    art = art.crop(box)
    k = (W * 0.70) / max(art.size)
    art = art.resize((round(art.width * k), round(art.height * k)), Image.LANCZOS)
    img.paste(art, ((W - art.width) // 2, (W - art.height) // 2), art)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


VARIANTS = {
    "icon.png": dict(bg=(39, 78, 59), bg_glow=(66, 106, 85), leaf=(176, 208, 184), leaf_edge=(132, 176, 146),
                     stem=(150, 192, 162), bowl=(247, 244, 237), bowl_shadow=(10, 30, 20)),
    "icon-dark.png": dict(bg=(16, 30, 23), bg_glow=(34, 62, 48), leaf=(140, 190, 156), leaf_edge=(104, 156, 122),
                          stem=(120, 172, 138), bowl=(225, 228, 220), bowl_shadow=(0, 0, 0)),
    # Tinted: iOS recolours by luminosity, so supply greys on black.
    "icon-tinted.png": dict(bg=(20, 20, 20), bg_glow=(48, 48, 48), leaf=(215, 215, 215), leaf_edge=(170, 170, 170),
                            stem=(190, 190, 190), bowl=(245, 245, 245), bowl_shadow=(0, 0, 0)),
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, colours in VARIANTS.items():
        draw_icon(**colours).save(os.path.join(OUT, name), "PNG")
    size = {"idiom": "universal", "platform": "ios", "size": "1024x1024"}
    contents = {"images": [
        {**size, "filename": "icon.png"},
        {**size, "filename": "icon-dark.png", "appearances": [{"appearance": "luminosity", "value": "dark"}]},
        {**size, "filename": "icon-tinted.png", "appearances": [{"appearance": "luminosity", "value": "tinted"}]},
    ], "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    print("wrote", sorted(os.listdir(OUT)))
