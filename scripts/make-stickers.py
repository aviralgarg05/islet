#!/usr/bin/env python3
"""Draw Casement's built-in stickers and write them to Resources/Stickers/*.gif.

Every sticker is drawn here, in code, from circles, polygons and lines: no artwork comes from
anywhere else, and the files are MIT like the rest of Casement. Each frame is drawn 8 times too
big and scaled down, so the edges are smooth, then matted onto black (the closed island is
black, or the dark graphite) because a GIF pixel is either opaque or clear.

The canvas is 64 x 64 pixels: 32 points at 2x, the tallest the menu bar row lets a sticker be,
so smaller sizes are drawn by scaling down, never up.

Usage:
  scripts/make-stickers.py                  write Resources/Stickers/*.gif
  scripts/make-stickers.py --sheet DIR      also write a contact sheet of every frame to DIR
  scripts/make-stickers.py --only cat       draw one sticker

Needs Pillow (pip3 install pillow).
"""

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "Resources/Stickers"

SIZE = 64          # pixels, 32 pt at 2x
SS = 8             # supersampling factor
TAU = math.tau


# MARK: - A small vector kit: shapes are point lists in canvas units, transformed, then filled.

class Pen:
    """Draws on one supersampled RGBA frame. Coordinates are in canvas pixels (0...SIZE),
    y down, through a stack of affine transforms."""

    def __init__(self):
        self.image = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
        self.draw = ImageDraw.Draw(self.image)
        self.stack = [(1, 0, 0, 1, 0, 0)]

    # Transforms (a, b, c, d, tx, ty): x' = a x + c y + tx, y' = b x + d y + ty
    @property
    def m(self):
        return self.stack[-1]

    def push(self):
        self.stack.append(self.m)

    def pop(self):
        self.stack.pop()

    def concat(self, n):
        a, b, c, d, tx, ty = self.m
        a2, b2, c2, d2, tx2, ty2 = n
        self.stack[-1] = (a * a2 + c * b2, b * a2 + d * b2, a * c2 + c * d2, b * c2 + d * d2,
                          a * tx2 + c * ty2 + tx, b * tx2 + d * ty2 + ty)

    def translate(self, x, y):
        self.concat((1, 0, 0, 1, x, y))

    def scale(self, sx, sy=None):
        self.concat((sx, 0, 0, sx if sy is None else sy, 0, 0))

    def rotate(self, degrees, cx=0, cy=0):
        r = math.radians(degrees)
        self.translate(cx, cy)
        self.concat((math.cos(r), math.sin(r), -math.sin(r), math.cos(r), 0, 0))
        self.translate(-cx, -cy)

    def map(self, pts):
        a, b, c, d, tx, ty = self.m
        return [((a * x + c * y + tx) * SS, (b * x + d * y + ty) * SS) for x, y in pts]

    def unit(self):
        """How many canvas pixels one unit is, for line widths."""
        a, b, c, d, _, _ = self.m
        return math.sqrt(abs(a * d - b * c))

    # Drawing
    def fill(self, pts, colour):
        self.draw.polygon(self.map(pts), fill=colour)

    def line(self, pts, colour, width):
        mapped = self.map(pts)
        w = max(1, int(round(width * self.unit() * SS)))
        self.draw.line(mapped, fill=colour, width=w, joint="curve")
        r = w / 2
        for x, y in (mapped[0], mapped[-1]):
            self.draw.ellipse((x - r, y - r, x + r, y + r), fill=colour)

    def ellipse(self, cx, cy, rx, ry, colour, rotation=0):
        self.fill(ellipse_pts(cx, cy, rx, ry, rotation), colour)

    def circle(self, cx, cy, r, colour):
        self.ellipse(cx, cy, r, r, colour)

    def finish(self):
        """The frame at canvas size."""
        return self.image.resize((SIZE, SIZE), Image.LANCZOS)


def ellipse_pts(cx, cy, rx, ry, rotation=0, n=72):
    r = math.radians(rotation)
    pts = []
    for k in range(n):
        t = TAU * k / n
        x, y = rx * math.cos(t), ry * math.sin(t)
        pts.append((cx + x * math.cos(r) - y * math.sin(r), cy + x * math.sin(r) + y * math.cos(r)))
    return pts


def arc_pts(cx, cy, rx, ry, start, end, n=24):
    """Degrees, clockwise on screen (y down)."""
    return [(cx + rx * math.cos(math.radians(start + (end - start) * k / n)),
             cy + ry * math.sin(math.radians(start + (end - start) * k / n))) for k in range(n + 1)]


def rounded_poly(pts, radius, n=8):
    """A polygon with its corners rounded by `radius`."""
    out = []
    count = len(pts)
    for i in range(count):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % count]
        v1 = (p0[0] - p1[0], p0[1] - p1[1])
        v2 = (p2[0] - p1[0], p2[1] - p1[1])
        l1, l2 = math.hypot(*v1), math.hypot(*v2)
        r = min(radius, l1 / 2, l2 / 2)
        a = (p1[0] + v1[0] / l1 * r, p1[1] + v1[1] / l1 * r)
        b = (p1[0] + v2[0] / l2 * r, p1[1] + v2[1] / l2 * r)
        for k in range(n + 1):
            t = k / n
            # Quadratic curve from a to b with p1 as the control point.
            x = (1 - t) ** 2 * a[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * b[0]
            y = (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * b[1]
            out.append((x, y))
    return out


def rounded_rect(x, y, w, h, r):
    return rounded_poly([(x, y), (x + w, y), (x + w, y + h), (x, y + h)], r)


def star_pts(cx, cy, outer, inner, points=5, rotation=-90):
    pts = []
    for k in range(points * 2):
        r = outer if k % 2 == 0 else inner
        t = math.radians(rotation + 180 * k / points)
        pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
    return pts


def sparkle(pen, cx, cy, r, colour):
    """A four-pointed glint."""
    if r <= 0.2:
        return
    w = r * 0.28
    pen.fill([(cx, cy - r), (cx + w, cy - w), (cx + r, cy), (cx + w, cy + w),
              (cx, cy + r), (cx - w, cy + w), (cx - r, cy), (cx - w, cy - w)], colour)


def mix(c1, c2, t):
    return tuple(int(round(a + (b - a) * t)) for a, b in zip(c1, c2))


def ease(t):
    return 0.5 - 0.5 * math.cos(math.pi * t)


# Colours (RGBA)
INK = (46, 30, 28, 255)
WHITE = (255, 255, 255, 255)
BLUSH = (255, 138, 160, 255)


# MARK: - Cat: a ginger cat in headphones, nodding along

def cat(t):
    pen = Pen()
    fur = (247, 166, 92, 255)
    fur_dark = (226, 128, 62, 255)
    muzzle = (255, 228, 196, 255)
    ear_in = (255, 160, 178, 255)
    band = (94, 222, 196, 255)
    band_dark = (46, 176, 156, 255)

    # A nod: down on the beat, twice a loop, with a small tilt from side to side.
    tilt = 7 * math.sin(TAU * t)
    dip = 1.8 * (0.5 - 0.5 * math.cos(2 * TAU * t))
    pen.translate(0, dip)
    pen.rotate(tilt, 32, 52)

    # Ears, behind the head. The far tips flick a little with the tilt.
    flick = 1.2 * math.sin(TAU * t + 0.6)
    for side in (-1, 1):
        base_in, base_out, tip = (32 + side * 5, 23), (32 + side * 19, 29), (32 + side * 17.5, 6 - flick * side)
        pen.fill(rounded_poly([base_in, tip, base_out], 2.5), fur)
        pen.fill(rounded_poly([(32 + side * 9, 22.5), (32 + side * 16.4, 10.5 - flick * side), (32 + side * 16.4, 24)], 1.5), ear_in)

    # Head: wide and soft.
    head = ellipse_pts(32, 37, 21, 17)
    pen.fill(head, fur)
    # Tabby stripes on the forehead.
    for dx, h in ((-5, 6), (0, 7.5), (5, 6)):
        pen.line([(32 + dx, 21.5), (32 + dx * 0.8, 21.5 + h)], fur_dark, 2.2)
    # Muzzle and cheeks.
    pen.ellipse(32, 44, 9, 6.2, muzzle)
    pen.ellipse(19.5, 42.5, 3.4, 2.2, BLUSH)
    pen.ellipse(44.5, 42.5, 3.4, 2.2, BLUSH)
    # Happy closed eyes.
    for cx in (23.5, 40.5):
        pen.line(arc_pts(cx, 37.5, 4, 3.4, 200, 340), INK, 2.4)
    # Nose and mouth.
    pen.fill(rounded_poly([(29.6, 40.6), (34.4, 40.6), (32, 43.4)], 1.0), (232, 96, 118, 255))
    pen.line(arc_pts(30, 44, 2, 1.8, 10, 170), INK, 1.4)
    pen.line(arc_pts(34, 44, 2, 1.8, 10, 170), INK, 1.4)

    # Headphones: a band over the top and a cup on each side.
    # The band hugs the top of the head, between the ears.
    pen.line(arc_pts(32, 37, 22.2, 18.6, 190, 350), band_dark, 4.2)
    pen.line(arc_pts(32, 37, 22.2, 18.6, 194, 346), band, 2.6)
    for side in (-1, 1):
        cx = 32 + side * 21.5
        pen.fill(rounded_rect(cx - 5, 30, 10, 15, 4.5), band_dark)
        pen.fill(rounded_rect(cx - 4, 31, 8, 13, 3.5), band)
        pen.fill(rounded_rect(cx - 1.4 + side * 1.2, 33.5, 2.4, 8, 1.2), (190, 255, 240, 255))
    return pen.finish()


# MARK: - Jelly: a soft jelly blob hopping

def jelly(t):
    pen = Pen()
    body = (120, 226, 168, 255)
    body_dark = (64, 186, 132, 255)
    ground = 58

    # One hop a loop. It starts standing still (the first frame is the one Reduce Motion
    # shows), crouches, springs up stretched, lands squashed and settles again.
    hop, contact, stretch = 0.0, 0.0, 0.0
    if 0.18 <= t < 0.3:                      # crouch
        contact = math.sin(math.pi / 2 * (t - 0.18) / 0.12)
    elif 0.3 <= t < 0.8:                     # in the air
        u = (t - 0.3) / 0.5
        hop = math.sin(math.pi * u)
        stretch = 0.11 * abs(math.cos(math.pi * u))
    elif 0.8 <= t < 0.95:                    # landing
        contact = math.sin(math.pi * (t - 0.8) / 0.15)
    lift = 16 * hop ** 1.2
    sx = 1 + 0.22 * contact - stretch
    sy = 1 - 0.22 * contact + stretch * 1.2

    # A shadow that shrinks as the blob rises.
    shadow = 1 - 0.5 * hop
    pen.ellipse(32, ground + 2, 15 * shadow, 2.4 * shadow, (58, 58, 64, 255))

    pen.push()
    pen.translate(32, ground - lift)
    pen.scale(sx, sy)
    # A dome: round on top, a little flat underneath, drawn up from its base.
    w = 18
    # Tall and round on top, gently round underneath: one blob, from its centre 9 above the base.
    dome = [(w * math.cos(a), -9 + 24 * math.sin(a)) for a in [math.pi + math.pi * k / 47 for k in range(48)]]
    belly = [(w * math.cos(a), -9 + 9 * math.sin(a)) for a in [math.pi * k / 47 for k in range(48)]]
    outline = dome + belly
    pen.fill(outline, body_dark)
    inner = [(x * 0.9, y * 0.92 - 1.4) for x, y in outline]
    pen.fill(inner, body)
    # A shine on the top left.
    pen.ellipse(-8.5, -21, 4.2, 2.6, (214, 255, 232, 255), rotation=-28)
    pen.circle(-3.6, -25.5, 1.3, (214, 255, 232, 255))
    # Face: eyes that squeeze a little when it lands.
    blink = 1 - 0.55 * contact
    for ex in (-6.5, 6.5):
        pen.ellipse(ex, -13, 2.5, 3.1 * blink, INK)
        if blink > 0.7:
            pen.circle(ex + 0.9, -14.2, 0.9, WHITE)
    pen.ellipse(-11.5, -8.5, 2.6, 1.6, BLUSH)
    pen.ellipse(11.5, -8.5, 2.6, 1.6, BLUSH)
    pen.line(arc_pts(0, -10, 3, 2.6, 20, 160), INK, 1.6)
    pen.pop()
    return pen.finish()


# MARK: - Notes: two notes floating up and swaying

def eighth_note(pen, colour, dark):
    """One quaver, its head at the origin."""
    pen.ellipse(0, 0, 5.4, 4.2, dark, rotation=-24)
    pen.ellipse(-0.2, -0.3, 4.4, 3.3, colour, rotation=-24)
    pen.fill(rounded_rect(3.2, -19, 2.6, 19, 1.2), colour)
    flag = [(5.6, -19), (11.5, -13.5), (10.5, -7.5), (9.8, -11.5), (5.6, -14)]
    pen.fill(rounded_poly(flag, 1.6), colour)


def beamed_notes(pen, colour, dark):
    """Two quavers joined by a beam, the left head at the origin."""
    for x, y in ((0, 0), (11, -3)):
        pen.ellipse(x, y, 5.0, 3.9, dark, rotation=-24)
        pen.ellipse(x - 0.2, y - 0.3, 4.1, 3.1, colour, rotation=-24)
        pen.fill(rounded_rect(x + 2.9, y - 18, 2.5, 18, 1.1), colour)
    pen.fill(rounded_poly([(2.9, -18.5), (16.4, -21.5), (16.4, -16.6), (2.9, -13.6)], 1.2), colour)


def notes(t):
    pen = Pen()
    tracks = [
        # (phase, start x, sway, colour, dark, drawer, size)
        # The two sway the same way at the same moment, half a loop apart, so they never touch.
        (0.3, 12, 4.0, (255, 214, 102, 255), (226, 168, 42, 255), eighth_note, 1.35),
        (0.8, 38, -3.5, (255, 143, 171, 255), (224, 92, 128, 255), beamed_notes, 1.2),
    ]
    for phase, x0, sway, colour, dark, drawer, size in tracks:
        u = (t + phase) % 1.0
        y = 60 - 44 * u
        x = x0 + sway * math.sin(TAU * u)
        # Each note pops in at the bottom and shrinks away at the top, dimming a little as it
        # goes. (A GIF can't fade: dimming alone would leave dark notes on the graphite island.)
        fade = ease(max(0.0, min(1.0, u / 0.16, (1 - u) / 0.26)))
        dim = 0.5 + 0.5 * fade
        c, d = mix((0, 0, 0, 255), colour, dim), mix((0, 0, 0, 255), dark, dim)
        if fade < 0.05:
            continue
        pen.push()
        pen.translate(x, y)
        pen.rotate(10 * math.sin(TAU * u + 1.2))
        pen.scale(size * fade)
        drawer(pen, c, d)
        pen.pop()
    return pen.finish()


# MARK: - Record: a little vinyl record spinning

def record(t):
    pen = Pen()
    cx, cy, r = 32, 32, 27
    angle = 180 * t  # the label has two-fold symmetry: half a turn a loop
    pen.circle(cx, cy, r + 1.2, (72, 72, 84, 255))       # rim
    pen.circle(cx, cy, r, (26, 26, 32, 255))              # vinyl
    for gr in (24.5, 21.5, 18.5, 15.5):                   # grooves
        pen.line(arc_pts(cx, cy, gr, gr, 0, 360, 72), (48, 48, 58, 255), 0.9)
    # A sheen that stays where the light is while the record turns under it.
    for start in (205, 25):
        pts = [(cx, cy)] + arc_pts(cx, cy, r - 1.5, r - 1.5, start, start + 38, 16)
        pen.fill(pts, (64, 64, 78, 255))
    for gr in (24.5, 21.5, 18.5):
        for start in (205, 25):
            pen.line(arc_pts(cx, cy, gr, gr, start + 6, start + 32, 10), (92, 92, 108, 255), 0.9)
    # The label turns.
    pen.push()
    pen.rotate(angle, cx, cy)
    pen.circle(cx, cy, 12, (255, 112, 112, 255))
    for a in (0, 180):
        pts = [(cx, cy)] + arc_pts(cx, cy, 12, 12, a - 30, a + 30, 12)
        pen.fill(pts, (255, 214, 102, 255))
    pen.circle(cx, cy, 3.2, (255, 242, 228, 255))
    pen.pop()
    pen.circle(cx, cy, 1.4, (26, 26, 32, 255))            # spindle hole
    return pen.finish()


# MARK: - Star: a smiling star that twinkles

def star(t):
    pen = Pen()
    gold = (255, 210, 84, 255)
    gold_dark = (240, 164, 34, 255)
    beat = 0.5 - 0.5 * math.cos(TAU * t)
    s = 0.93 + 0.09 * beat
    pen.push()
    pen.translate(32, 34)
    pen.rotate(6 * math.sin(TAU * t))
    pen.scale(s)
    outer = rounded_poly(star_pts(0, 0, 25, 11.5), 4.2)
    pen.fill(outer, gold_dark)
    pen.fill(rounded_poly(star_pts(0, -0.8, 22.2, 10.2), 3.6), gold)
    pen.ellipse(-6.5, -8.5, 2.6, 1.6, (255, 240, 180, 255), rotation=-35)
    # Face.
    blink = 0.15 if 0.62 < t < 0.70 else 1.0
    for ex in (-4.6, 4.6):
        pen.ellipse(ex, 0, 1.8, 2.4 * blink, INK)
    pen.ellipse(-8.6, 4.2, 2.3, 1.4, BLUSH)
    pen.ellipse(8.6, 4.2, 2.3, 1.4, BLUSH)
    pen.line(arc_pts(0, 3.4, 2.4, 2.2, 20, 160), INK, 1.4)
    pen.pop()
    # Glints that come and go around it, one after another.
    for phase, x, y, size in ((0.0, 9, 11, 5.5), (0.33, 55, 15, 4.5), (0.66, 52, 54, 5.0)):
        u = (t - phase) % 1.0
        g = math.sin(math.pi * min(1.0, u / 0.45)) if u < 0.45 else 0.0
        sparkle(pen, x, y, size * g, (255, 246, 200, 255))
    return pen.finish()


# MARK: - Writing

# name: (draw, frames, delay in ms)
STICKERS = {
    "cat": (cat, 20, 50),
    "jelly": (jelly, 24, 50),
    "notes": (notes, 24, 60),
    "record": (record, 16, 60),
    "star": (star, 20, 60),
}

THRESHOLD = 40  # alpha below this is clear; above it, the colour is matted onto black


def matte(frame):
    """Premultiply onto black and make faint edges clear: what a GIF can hold."""
    rgb = Image.new("RGB", frame.size, (0, 0, 0))
    rgb.paste(frame, mask=frame.getchannel("A"))
    clear = frame.getchannel("A").point(lambda a: 255 if a < THRESHOLD else 0)
    return rgb, clear


def write_gif(name, frames, delay):
    pairs = [matte(f) for f in frames]
    # One palette for every frame, so colours never shift between them.
    strip = Image.new("RGB", (SIZE, SIZE * len(pairs)))
    for i, (rgb, _) in enumerate(pairs):
        strip.paste(rgb, (0, i * SIZE))
    palette = strip.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    out = []
    for rgb, clear in pairs:
        p = rgb.quantize(palette=palette, dither=Image.Dither.NONE)
        p.paste(255, mask=clear)
        out.append(p)
    path = OUTPUT / f"{name}.gif"
    out[0].save(path, save_all=True, append_images=out[1:], duration=delay, loop=0, transparency=255,
                disposal=2, optimize=False)
    return path


def contact_sheet(name, frames, directory):
    """Every frame at 4x on black, on graphite and at island size, for checking by eye."""
    scale = 4
    cols = len(frames)
    sheet = Image.new("RGB", (cols * SIZE * scale // 2, SIZE * scale // 2 * 2 + 60), (0, 0, 0))
    half = SIZE * scale // 2
    for i, f in enumerate(frames):
        rgb, clear = matte(f)
        big = rgb.resize((half, half), Image.NEAREST)
        sheet.paste(big, (i * half, 0))
        g = Image.new("RGB", (half, half), (27, 27, 27))
        mask = clear.point(lambda a: 0 if a else 255).resize((half, half), Image.NEAREST)
        g.paste(big, mask=mask)
        sheet.paste(g, (i * half, half))
        # At the size it is drawn in the island (24 pt at 2x), on black.
        small = rgb.resize((48, 48), Image.LANCZOS)
        sheet.paste(small, (i * half + (half - 48) // 2, half * 2 + 6))
    sheet.save(Path(directory) / f"sheet-{name}.png")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sheet", help="write contact sheets to this folder")
    parser.add_argument("--only", help="draw one sticker")
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, (draw, count, delay) in STICKERS.items():
        if args.only and name != args.only:
            continue
        frames = [draw(k / count) for k in range(count)]
        path = write_gif(name, frames, delay)
        print(f"{path.relative_to(ROOT)}: {count} frames, {path.stat().st_size / 1024:.1f} KB")
        if args.sheet:
            Path(args.sheet).mkdir(parents=True, exist_ok=True)
            contact_sheet(name, frames, args.sheet)


if __name__ == "__main__":
    main()
