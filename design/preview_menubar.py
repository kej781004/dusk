"""Fast iteration preview of the menu-bar glyph (laptop + moon, evenodd-hole
style) before porting the numbers to StatusIcon.swift. Renders on a mock
light and dark menu bar strip, at 3x for inspection."""
from PIL import Image, ImageDraw

SS = 20  # working scale: 1 unit -> 20px for crisp preview
CANVAS = 18 * SS  # matches the 18x18pt NSStatusItem canvas

def u(v): return v * SS

# geometry in the 18x18 local space (AppKit y-up convention: larger y = higher up)
SCREEN = (3.6, 7.2, 10.7, 13.0)   # x0,y0,x1,y1 (rounded rect)
BASE   = (2.6, 5.8, 11.7, 7.4)
MOON_C = (6.4, 10.4); MOON_R = 2.05
CUT_C  = (7.4, 11.1); CUT_R  = 1.72
SCREEN_RADIUS = 0.55
BASE_RADIUS = 0.4

SHAPE_CENTER = (7.15, 9.4)
TIMER_SCALE = 0.8

def scaled_for_timer(pt):
    x, y = pt
    cx, cy = SHAPE_CENTER
    return (cx + (x - cx) * TIMER_SCALE, cy + (y - cy) * TIMER_SCALE)

def build_silhouette_mask(size_canvas=CANVAS, timer=False):
    """Returns an L-mode alpha mask using the even-odd hole trick, done here
    with explicit region composition (Python doesn't have a one-call evenodd
    fill, so we reproduce the same boolean result with masks directly)."""
    def flipy(y):  # PIL is y-down; local space is y-up
        return 18 - y

    def tr(x, y):
        if timer:
            x, y = scaled_for_timer((x, y))
        return x, y

    def rr(x0, y0, x1, y1):
        x0,y0 = tr(x0,y0); x1,y1 = tr(x1,y1)
        return [u(x0), u(flipy(y1)), u(x1), u(flipy(y0))]

    r_scale = TIMER_SCALE if timer else 1.0

    body = Image.new("L", (size_canvas, size_canvas), 0)
    bd = ImageDraw.Draw(body)
    x0,y0,x1,y1 = SCREEN
    bd.rounded_rectangle(rr(x0,y0,x1,y1), radius=u(SCREEN_RADIUS*r_scale), fill=255)
    x0,y0,x1,y1 = BASE
    bd.rounded_rectangle(rr(x0,y0,x1,y1), radius=u(BASE_RADIUS*r_scale), fill=255)

    crescent = Image.new("L", (size_canvas, size_canvas), 0)
    cd = ImageDraw.Draw(crescent)
    mcx, mcy = tr(*MOON_C); mcy = flipy(mcy); mr = MOON_R*r_scale
    cd.ellipse([u(mcx-mr), u(mcy-mr), u(mcx+mr), u(mcy+mr)], fill=255)
    ccx, ccy = tr(*CUT_C); ccy = flipy(ccy); cr = CUT_R*r_scale
    hole = Image.new("L", (size_canvas, size_canvas), 0)
    hd = ImageDraw.Draw(hole)
    hd.ellipse([u(ccx-cr), u(ccy-cr), u(ccx+cr), u(ccy+cr)], fill=255)
    from PIL import ImageChops
    crescent = ImageChops.subtract(crescent, hole)

    silhouette = ImageChops.subtract(body, crescent)
    return silhouette

def render(bg_rgba, fill_rgba, out, ring=False, ring_color=(255,255,255,180)):
    mask = build_silhouette_mask(timer=ring)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), bg_rgba)
    fill_layer = Image.new("RGBA", (CANVAS, CANVAS), fill_rgba)
    canvas.paste(fill_layer, (0,0), mask)
    if ring:
        d = ImageDraw.Draw(canvas)
        cx = cy = CANVAS/2
        r = u(7.4)
        d.ellipse([cx-r,cy-r,cx+r,cy+r], outline=ring_color, width=max(2,int(u(0.5))))
    canvas.save(out)
    print("wrote", out)

render((40,40,42,255), (255,255,255,255), "mb-idle-dark.png")
render((235,235,237,255), (10,10,10,255), "mb-idle-light.png")
render((40,40,42,255), (255,255,255,255), "mb-timer-dark.png", ring=True)
render((40,40,42,255), (74,58,250,255), "mb-active.png")
render((40,40,42,255), (74,58,250,255), "mb-active-timer.png", ring=True, ring_color=(150,140,255,220))
