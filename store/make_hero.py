import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

icon_path, out = sys.argv[1], sys.argv[2]
W, H = 1440, 720
NAVY = (10, 26, 48)
TEAL = (14, 124, 134)
ORANGE = (255, 138, 61)
WHITE = (245, 248, 250)
MUTED = (190, 214, 222)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


img = Image.new("RGB", (W, H))
px = img.load()
for y in range(H):
    for x in range(W):
        t = (x / W) * 0.7 + (y / H) * 0.3
        px[x, y] = lerp(NAVY, TEAL, t ** 1.2)
img = img.convert("RGBA")

# Soft glow behind the icon
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([60, 80, 620, 640], fill=(255, 255, 255, 40))
img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(60)))

# Icon with shadow
size = 500
icon = Image.open(icon_path).convert("RGBA").resize((size, size), Image.LANCZOS)
ix, iy = 90, (H - size) // 2
shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([ix + 10, iy + 24, ix + size + 10, iy + size + 24], radius=95, fill=(0, 0, 0, 140))
img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))
img.alpha_composite(icon, (ix, iy))

d = ImageDraw.Draw(img)
bold = "C:/Windows/Fonts/segoeuib.ttf"
semi = "C:/Windows/Fonts/seguisb.ttf"
tx = 670
d.text((tx, 150), "Appleton Comms", font=ImageFont.truetype(bold, 82), fill=WHITE)
d.text((tx, 268), "Call and text your contacts", font=ImageFont.truetype(semi, 44), fill=MUTED)
d.text((tx, 322), "from your Garmin watch", font=ImageFont.truetype(semi, 44), fill=MUTED)

features = ["Quick messages in one click", "Write texts on the watch", "Calls, favourites and recents"]
f = ImageFont.truetype(semi, 36)
y = 420
for text in features:
    d.ellipse([tx, y + 14, tx + 20, y + 34], fill=ORANGE)
    d.text((tx + 40, y), text, font=f, fill=WHITE)
    y += 60

d.text((tx, 628), "For Android phones  ·  No Internet needed", font=ImageFont.truetype(semi, 26), fill=MUTED)

img.convert("RGB").save(out, quality=95)
print("saved", out, img.size)
