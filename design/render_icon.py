"""
Renders the Dusk app icon (laptop + crescent moon glyph) at high resolution
using Pillow, in a normalized 0..100 coordinate space so the same numbers can
be ported to StatusIcon.swift's CGPath geometry later.

Usage: python3 render_icon.py <out.png> <size> <variant>
  variant: black | indigo | outline
"""
import sys
from PIL import Image, ImageDraw

SIZE = int(sys.argv[2]) if len(sys.argv) > 2 else 1024
VARIANT = sys.argv[3] if len(sys.argv) > 3 else "black"
OUT = sys.argv[1] if len(sys.argv) > 1 else "preview.png"

SS = 4  # supersample factor for clean antialiasing
CANVAS = SIZE * SS

BG_BLACK = (28, 28, 30, 255)      # macOS-ish near-black graphite
BG_INDIGO = (74, 58, 250, 255)    # sampled brand indigo-violet
WHITE = (255, 255, 255, 255)

def u(v):
    """normalized 0..100 unit -> pixel, in the supersampled canvas"""
    return v / 100.0 * CANVAS

def rrect(draw, box, radius, **kw):
    draw.rounded_rectangle(box, radius=radius, **kw)

def squircle_mask(size):
    """Approximate macOS squircle: inset rounded rect at ~22% corner radius,
    with a margin around it so the shape does not touch the canvas edge —
    matching the approved reference, which has clear air around the chip."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    inset = size * 0.045
    r = (size - 2 * inset) * 0.225
    d.rounded_rectangle([inset, inset, size - 1 - inset, size - 1 - inset], radius=r, fill=255)
    return m

NOTCH_BG = (0, 0, 0, 0)

def draw_laptop_moon(draw, stroke_color, screen_fill, moon_color, base_fill, stroke_w_u):
    """All coordinates in normalized 0..100 units."""
    sw = u(stroke_w_u)

    # Screen: rounded rect
    screen_box = [u(26), u(28), u(74), u(60)]
    if screen_fill:
        rrect(draw, screen_box, radius=u(3.2), fill=screen_fill)
    else:
        rrect(draw, screen_box, radius=u(3.2), outline=stroke_color, width=int(sw))

    # Base: wide rounded trapezoid-ish shape below the screen, drawn as a
    # rounded rect slightly wider than the screen with a small notch at the
    # top-center (the lid-opening tab).
    base_top = u(60)
    base_bottom = u(68.5)
    base_left = u(19)
    base_right = u(81)
    base_box = [base_left, base_top, base_right, base_bottom]
    if base_fill:
        rrect(draw, base_box, radius=u(2.2), fill=base_fill)
    else:
        rrect(draw, base_box, radius=u(2.2), outline=stroke_color, width=int(sw))

    # Notch/tab: a small filled pill cut into the top edge of the base,
    # centered, matching the little hinge detail in the reference.
    notch_w = u(11)
    notch_h = u(2.6)
    cx = CANVAS / 2
    notch_box = [cx - notch_w / 2, base_top - notch_h * 0.4, cx + notch_w / 2, base_top + notch_h * 0.6]
    # Cut the notch by painting the real background colour over the seam —
    # a transparent fill is a no-op against opaque white beneath it, so the
    # erase has to be an actual paint, not an alpha trick.
    if base_fill:
        draw.rounded_rectangle(notch_box, radius=notch_h / 2, fill=NOTCH_BG)
    else:
        draw.rounded_rectangle(notch_box, radius=notch_h / 2, outline=stroke_color, width=max(1, int(sw * 0.7)))

    # Crescent moon: big circle minus an offset smaller circle, centered in
    # the upper-middle of the screen.
    moon_cx, moon_cy, moon_r = 45.5, 42.5, 12.5
    cut_cx, cut_cy, cut_r = 51.0, 39.0, 10.5

    moon_layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    md = ImageDraw.Draw(moon_layer)
    md.ellipse([u(moon_cx - moon_r), u(moon_cy - moon_r), u(moon_cx + moon_r), u(moon_cy + moon_r)], fill=moon_color)
    md.ellipse([u(cut_cx - cut_r), u(cut_cy - cut_r), u(cut_cx + cut_r), u(cut_cy + cut_r)], fill=(0, 0, 0, 0))
    # composite the cutout as erase
    cutout = Image.new("L", (CANVAS, CANVAS), 0)
    cd = ImageDraw.Draw(cutout)
    cd.ellipse([u(cut_cx - cut_r), u(cut_cy - cut_r), u(cut_cx + cut_r), u(cut_cy + cut_r)], fill=255)
    moon_alpha = moon_layer.split()[-1]
    from PIL import ImageChops
    moon_alpha = ImageChops.subtract(moon_alpha, cutout)
    moon_layer.putalpha(moon_alpha)

    return moon_layer

def render(variant):
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    global NOTCH_BG
    if variant == "outline":
        # transparent bg, template-style black stroke only (for menu bar preview)
        draw = ImageDraw.Draw(canvas)
        draw_laptop_moon(draw, stroke_color=(0,0,0,255), screen_fill=None, moon_color=(0,0,0,255), base_fill=None, stroke_w_u=3.4)
        moon = draw_laptop_moon.__wrapped__ if False else None
    else:
        bg = BG_BLACK if variant == "black" else BG_INDIGO
        NOTCH_BG = bg
        mask = squircle_mask(CANVAS)
        bgimg = Image.new("RGBA", (CANVAS, CANVAS), bg)
        canvas = Image.composite(bgimg, canvas, mask)
        draw = ImageDraw.Draw(canvas)
        # screen: white fill (icon-1/3 style)
        draw_laptop_moon(draw, stroke_color=WHITE, screen_fill=WHITE, moon_color=bg, base_fill=WHITE, stroke_w_u=3.4)

    # moon drawn as its own layer so the cutout composites cleanly over whatever is beneath
    moon_color = BG_BLACK if variant == "black" else (BG_INDIGO if variant == "indigo" else (0,0,0,255))
    moon_layer = draw_laptop_moon(ImageDraw.Draw(Image.new("RGBA",(1,1))), stroke_color=(0,0,0,0), screen_fill=None, moon_color=moon_color, base_fill=None, stroke_w_u=0)
    canvas.alpha_composite(moon_layer)

    canvas = canvas.resize((SIZE, SIZE), Image.LANCZOS)
    canvas.save(OUT)
    print("wrote", OUT, canvas.size)

render(VARIANT)
