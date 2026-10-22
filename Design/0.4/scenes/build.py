#!/usr/bin/env python3
"""Glassine 0.4 design scenes as SVG.

    python3 build.py        # writes svg/*.svg and index.html
    ./render.sh             # svg/*.svg -> png/*@2x.png (headless Chrome)

Direction: glassine paper (the translucent sleeve stamps are kept in), ink and a postmark.
Ink is the accent; red means recording and nothing else.
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

with open(os.path.join(HERE, "..", "tokens.json")) as f:
    TOKENS = json.load(f)
LIGHT, DARK = TOKENS["light"], TOKENS["dark"]

FONTS = ("https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght,SOFT,WONK@"
         "0,9..144,100..900,0..100,0..1;1,9..144,100..900,0..100,0..1&display=swap")


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


class Scene:
    def __init__(self, name, w, h, c):
        self.name, self.w, self.h, self.c = name, w, h, c
        self.parts, self.defs, self.n = [], [], 0
        p = name
        self.defs.append(f"""
<filter id="{p}-sh-s" x="-20%" y="-20%" width="140%" height="160%">
  <feDropShadow dx="0" dy="1" stdDeviation="1.2" flood-color="{c['shadow']}" flood-opacity=".10"/></filter>
<filter id="{p}-sh-m" x="-30%" y="-30%" width="160%" height="170%">
  <feDropShadow dx="0" dy="1" stdDeviation="1" flood-color="{c['shadow']}" flood-opacity=".10"/>
  <feDropShadow dx="0" dy="8" stdDeviation="12" flood-color="{c['shadow']}" flood-opacity=".14"/></filter>
<filter id="{p}-grain" x="0" y="0" width="100%" height="100%">
  <feTurbulence type="fractalNoise" baseFrequency=".85" numOctaves="2" seed="4" stitchTiles="stitch"/>
  <feColorMatrix values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  1 0 0 0 -.15"/></filter>
<filter id="{p}-cloud" x="0" y="0" width="100%" height="100%">
  <feTurbulence type="fractalNoise" baseFrequency=".011" numOctaves="3" seed="9"/>
  <feColorMatrix values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  2.4 0 0 0 -1.1"/></filter>
<pattern id="{p}-dots" width="6" height="6" patternUnits="userSpaceOnUse">
  <circle cx="3" cy="3" r=".7" fill="{c['ink']}" fill-opacity=".13"/></pattern>""")

    def id(self, kind):
        self.n += 1
        return f"{self.name}-{kind}{self.n}"

    def add(self, s):
        self.parts.append(s)

    def svg(self):
        style = f"""<style><![CDATA[
@import url('{FONTS}');
.s{{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',sans-serif}}
.f{{font-family:'Fraunces',Georgia,serif;font-variation-settings:'SOFT' 100,'WONK' 0;font-feature-settings:'lnum' 1,'tnum' 1}}
.m{{font-family:'SF Mono',ui-monospace,Menlo,monospace}}
]]></style>"""
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" '
                f'viewBox="0 0 {self.w} {self.h}">\n{style}\n<defs>{"".join(self.defs)}</defs>\n'
                + "\n".join(self.parts) + "\n</svg>\n")

    # ---- primitives -------------------------------------------------------------------------

    def text(self, x, y, s, size, cls="s", fill="ink", anchor="start", weight=400,
             italic=False, ls=None, opacity=None):
        st = f"font-size:{size}px;font-weight:{weight}"
        if italic:
            st += ";font-style:italic"
        if ls is not None:
            st += f";letter-spacing:{ls}px"
        op = f' fill-opacity="{opacity}"' if opacity is not None else ""
        col = self.c.get(fill, fill)
        self.add(f'<text x="{x}" y="{y}" class="{cls}" fill="{col}"{op} text-anchor="{anchor}" '
                 f'style="{st}">{esc(s)}</text>')

    def label(self, x, y, s, fill="ink3", anchor="start", size=9.5):
        """Catalogue label: small mono caps."""
        self.text(x, y, s.upper(), size, "m", fill, anchor, 500, ls=1.1)

    def rect(self, x, y, w, h, r=0, fill="card", stroke=None, sw=1, extra=""):
        f = self.c.get(fill, fill)
        st = f' stroke="{self.c.get(stroke, stroke)}" stroke-width="{sw}"' if stroke else ""
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{f}"{st} {extra}/>')

    def circle(self, cx, cy, r, fill="card", stroke=None, sw=1, extra=""):
        f = self.c.get(fill, fill)
        st = f' stroke="{self.c.get(stroke, stroke)}" stroke-width="{sw}"' if stroke else ""
        self.add(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{f}"{st} {extra}/>')

    def line(self, x1, y1, x2, y2, stroke="rule", sw=1, extra=""):
        self.add(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" '
                 f'stroke="{self.c.get(stroke, stroke)}" stroke-width="{sw}" {extra}/>')

    def path(self, d, fill="none", stroke=None, sw=1, extra=""):
        f = self.c.get(fill, fill)
        st = f' stroke="{self.c.get(stroke, stroke)}" stroke-width="{sw}"' if stroke else ""
        self.add(f'<path d="{d}" fill="{f}"{st} {extra}/>')

    def texture(self, shape, kind):
        """Overlay paper grain / glassine cloud / dots, clipped to `shape` (an SVG element)."""
        cid = self.id("clip")
        self.defs.append(f'<clipPath id="{cid}">{shape}</clipPath>')
        if kind == "paper":
            cloud, grain = (".12", ".035") if self.c is LIGHT else (".025", ".05")
            self.add(f'<g clip-path="url(#{cid})">'
                     f'<rect width="100%" height="100%" filter="url(#{self.name}-cloud)" opacity="{cloud}"/>'
                     f'<rect width="100%" height="100%" filter="url(#{self.name}-grain)" opacity="{grain}"/></g>')
        else:
            self.add(f'<g clip-path="url(#{cid})"><rect width="100%" height="100%" '
                     f'fill="url(#{self.name}-dots)"/></g>')

    # ---- components ---------------------------------------------------------------------------

    def window(self, x, y, w, h, title=None, lights="color", r=14):
        c = self.c
        self.add(f'<g filter="url(#{self.name}-sh-m)">')
        self.rect(x, y, w, h, r, "paper", "border")
        self.add("</g>")
        self.texture(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}"/>', "paper")
        cols = ["#FF5F57", "#FEBC2E", "#28C840"]
        if lights == "modal":
            cols = ["#FF5F57", c["track"], c["track"]]
        for i, col in enumerate(cols):
            self.circle(x + 20 + i * 20, y + 20, 6, col)
        if title:
            self.text(x + w / 2, y + 25, title, 13, "s", "ink2", "middle", 600)

    def card(self, x, y, w, h, r=12, fill="card"):
        self.rect(x, y, w, h, r, fill, "border")

    def keycaps(self, right, cy, keys):
        """Separate keycaps, right-aligned at `right`, vertically centered on `cy`."""
        cw, gap = 21, 3
        x = right - len(keys) * cw - (len(keys) - 1) * gap
        for k in keys:
            self.rect(x, cy - 10 + 1.5, cw, 20, 5, "border")
            self.rect(x, cy - 10, cw, 20, 5, "key", "border", .8)
            self.text(x + cw / 2, cy + 4.3, k, 12 if k not in ",." else 14, "s", "ink2", "middle", 500)
            x += cw + gap

    def toggle(self, x, y, on):
        w, h = 38, 22
        if on:
            self.rect(x, y, w, h, h / 2, "ink")
            self.circle(x + w - h / 2, y + h / 2, h / 2 - 2.5, "on_ink")
        else:
            self.rect(x, y, w, h, h / 2, "track")
            self.add(f'<g filter="url(#{self.name}-sh-s)">')
            self.circle(x + h / 2, y + h / 2, h / 2 - 2.5, "#FFFFFF" if self.c is LIGHT else "ink2")
            self.add("</g>")

    def button(self, x, y, w, h, label, kind="primary", size=14):
        if kind == "primary":
            self.rect(x, y, w, h, h / 2, "ink")
            self.text(x + w / 2, y + h / 2 + size * .36, label, size, "s", "on_ink", "middle", 600)
        elif kind == "secondary":
            self.rect(x, y, w, h, h / 2, "card", "border")
            self.text(x + w / 2, y + h / 2 + size * .36, label, size, "s", "ink", "middle", 500)
        else:  # quiet
            self.text(x + w / 2, y + h / 2 + size * .36, label, size, "s", "ink2", "middle", 500)

    def popup(self, right, cy, label):
        w, h = 104, 26
        x = right - w
        self.rect(x, cy - h / 2, w, h, 7, "card", "border")
        self.text(x + 11, cy + 4.6, label, 13.5, "s", "ink", "start", 400)
        self.path(f"M{right - 20} {cy - 1.5} l3.5 3.5 l3.5 -3.5", stroke="ink2", sw=1.4,
                  extra='stroke-linecap="round" stroke-linejoin="round"')

    def segmented(self, right, cy, items, sel, iw=72, h=28):
        w = iw * len(items) + 4
        x = right - w
        self.rect(x, cy - h / 2, w, h, 8, "track")
        for i, it in enumerate(items):
            ix = x + 2 + i * iw
            if i == sel:
                self.add(f'<g filter="url(#{self.name}-sh-s)">')
                self.rect(ix, cy - h / 2 + 2, iw, h - 4, 6.5, "card")
                self.add("</g>")
            self.text(ix + iw / 2, cy + 4.5, it, 13, "s", "ink" if i == sel else "ink2", "middle",
                      500 if i == sel else 400)

    def stamp(self, x, y, w, h, fill="card", hole=2.4, pitch=8.0, shadow="m", extra=""):
        """Postage-stamp mat: a rect with perforations bitten out of every edge."""
        mid = self.id("perf")
        holes = []
        for (ax, ay, bx, by) in [(x, y, x + w, y), (x, y + h, x + w, y + h),
                                 (x, y, x, y + h), (x + w, y, x + w, y + h)]:
            length = math.hypot(bx - ax, by - ay)
            n = max(2, round(length / pitch))
            for i in range(1, n):
                t = i / n
                holes.append(f'<circle cx="{ax + (bx - ax) * t:.2f}" cy="{ay + (by - ay) * t:.2f}" r="{hole}"/>')
        self.defs.append(f'<mask id="{mid}"><rect x="{x - 1}" y="{y - 1}" width="{w + 2}" height="{h + 2}" '
                         f'fill="#fff"/><g fill="#000">{"".join(holes)}</g></mask>')
        f = self.c.get(fill, fill)
        filt = f' filter="url(#{self.name}-sh-{shadow})"' if shadow else ""
        self.add(f'<g{filt} {extra}><rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{f}" '
                 f'mask="url(#{mid})"/></g>')

    def perf_line(self, x1, x2, y, fill="border"):
        """Tear-off line: a row of small holes."""
        n = int((x2 - x1) / 6)
        for i in range(n + 1):
            self.circle(x1 + i * (x2 - x1) / n, y, 1.5, fill)

    def check(self, cx, cy, r=12):
        self.circle(cx, cy, r, "sage_tint")
        self.path(f"M{cx - 4.5} {cy + .2} l3 3 l6 -6.5", stroke="sage_deep", sw=1.9,
                  extra='stroke-linecap="round" stroke-linejoin="round"')

    # icons, centered on (cx, cy)
    def i_pause(self, cx, cy, col="ink"):
        self.rect(cx - 4.5, cy - 6, 3, 12, 1, col)
        self.rect(cx + 1.5, cy - 6, 3, 12, 1, col)

    def i_stop(self, cx, cy, s=11):
        self.rect(cx - s / 2, cy - s / 2, s, s, 2.5, "rec")

    def i_trash(self, cx, cy, col="ink2"):
        st = f'stroke="{self.c[col]}" stroke-width="1.4" fill="none" stroke-linecap="round" stroke-linejoin="round"'
        self.add(f'<g {st}><path d="M{cx - 6} {cy - 4.5} h12"/><path d="M{cx - 2} {cy - 4.5} v-1.8 h4 v1.8"/>'
                 f'<path d="M{cx - 4.6} {cy - 4.5} l.8 10.5 h7.6 l.8 -10.5"/></g>')

    def i_cursor(self, cx, cy, col="on_ink"):
        self.path(f"M{cx - 3.5} {cy - 7} v13 l3.2 -3 l2.3 5 l2 -.9 l-2.2 -4.8 h4.4 z",
                  fill=col, extra='stroke-linejoin="round"')

    def i_layout(self, cx, cy, col="ink2"):
        self.rect(cx - 7, cy - 5.5, 14, 11, 2.5, "none", col, 1.4)
        self.rect(cx + 1, cy - 3.5, 4, 7, 1, col)

    def i_close(self, cx, cy, s=4.2, col="ink2", sw=1.5):
        self.path(f"M{cx - s} {cy - s} L{cx + s} {cy + s} M{cx + s} {cy - s} L{cx - s} {cy + s}",
                  stroke=col, sw=sw, extra='stroke-linecap="round"')

    def i_pin(self, cx, cy, col="ink2"):
        st = f'stroke="{self.c[col]}" stroke-width="1.4" fill="none" stroke-linecap="round" stroke-linejoin="round"'
        self.add(f'<g {st}><path d="M{cx - 3} {cy - 5.5} h6 l-1 4 l2.5 2.5 h-9 l2.5 -2.5 z"/>'
                 f'<path d="M{cx} {cy + 1} v5"/></g>')

    def i_pencil(self, cx, cy, col="ink2"):
        st = f'stroke="{self.c[col]}" stroke-width="1.4" fill="none" stroke-linecap="round" stroke-linejoin="round"'
        self.add(f'<g {st}><path d="M{cx - 5} {cy + 5} l1 -3.6 l6.8 -6.8 l2.6 2.6 l-6.8 6.8 z"/></g>')

    def i_qr(self, cx, cy, col="on_ink"):
        f = self.c.get(col, col)
        g = [f'<rect x="{cx - 6}" y="{cy - 6}" width="5" height="5" rx="1" fill="none" stroke="{f}" stroke-width="1.3"/>',
             f'<rect x="{cx + 1}" y="{cy - 6}" width="5" height="5" rx="1" fill="none" stroke="{f}" stroke-width="1.3"/>',
             f'<rect x="{cx - 6}" y="{cy + 1}" width="5" height="5" rx="1" fill="none" stroke="{f}" stroke-width="1.3"/>',
             f'<rect x="{cx + 1.5}" y="{cy + 1.5}" width="2" height="2" fill="{f}"/>',
             f'<rect x="{cx + 4}" y="{cy + 4}" width="2" height="2" fill="{f}"/>']
        self.add("".join(g))


# ---- scenes -------------------------------------------------------------------------------------

def welcome():
    s = Scene("welcome", 640, 620, LIGHT)
    s.window(0, 0, 640, 620)

    s.text(40, 112, "Welcome to Glassine", 46, "f", "ink", weight=440, ls=-.6)
    s.text(42, 146, "A quiet screenshot tool. It runs in the background", 15, "s", "ink2")
    s.text(42, 168, "and wakes up on a few shortcuts.", 15, "s", "ink2")

    # A stamp half-slid into a glassine sleeve.
    s.add('<g transform="rotate(-5 540 110)">')
    s.stamp(494, 46, 92, 112, "card", hole=2.3, pitch=7.7)
    s.rect(503, 55, 74, 72, 2, "sage")
    s.circle(560, 108, 13, "peach")
    s.text(508, 72, "0.4", 13, "f", "on_ink", weight=500)
    s.text(540, 148, "Glassine", 11, "f", "ink2", "middle", italic=True)
    s.add("</g>")
    # Sleeve with a thumb cut; the stamp shows through it.
    s.add('<g filter="url(#welcome-sh-s)">')
    s.path("M482 104 H522 a18 11 0 0 0 36 0 H598 V170 a5 5 0 0 1 -5 5 H487 a5 5 0 0 1 -5 -5 Z",
           fill="#FBFBF8", extra='fill-opacity=".68" stroke="#1C2230" stroke-opacity=".14"')
    s.add("</g>")

    # Shortcuts, two columns.
    s.label(42, 236, "Shortcuts")
    s.card(40, 248, 560, 164)
    left = [("Capture area", "⇧⌘4"), ("Capture window", "⇧⌘5"), ("Capture screen", "⇧⌘3"),
            ("Record screen", "⌥⇧⌘R")]
    right = [("Copy text", "⌥⇧⌘T"), ("Pick a color", "⌥⇧⌘C"), ("Measure", "⌥⇧⌘M"),
             ("Settings", "⌥⇧⌘,")]
    s.line(320, 260, 320, 400, "rule")
    for col, (x0, x1) in enumerate([(60, 302), (340, 582)]):
        for i, (name, keys) in enumerate((left, right)[col]):
            cy = 248 + 20.5 + i * 41
            s.text(x0, cy + 5, name, 14, "s", "ink")
            s.keycaps(x1, cy, list(keys))
            if i < 3:
                s.line(x0, cy + 20.5, x1, cy + 20.5, "rule")

    s.check(54, 452)
    s.text(78, 457, "Screen Recording is on", 14, "s", "ink", weight=600)
    s.text(78, 477, "macOS asks about once a month whether Glassine can still see your", 13, "s", "ink2")
    s.text(78, 495, "screen. Choose Allow.", 13, "s", "ink2")

    s.check(54, 524)
    s.text(78, 529, "macOS screenshot shortcuts are off", 14, "s", "ink", weight=600)
    s.text(78, 549, "⇧⌘3, ⇧⌘4 and ⇧⌘5 now open Glassine.", 13, "s", "ink2")

    s.text(42, 597, "Everything stays on your Mac.", 12, "s", "ink3")
    s.button(318, 574, 124, 34, "Open Settings", "secondary")
    s.button(452, 574, 148, 34, "Start capturing")
    return s


def mini_screen(s, x, y, w, h, mode):
    s.rect(x, y, w, h, 9, "screen")
    s.rect(x + 14, y + 22, w * .38, h * .42, 3, "card")
    s.rect(x + w * .36, y + h * .44, w * .36, h * .40, 3, "peach")
    i, r, cx, nw, nh = 6, 7, x + w / 2, 40, 8
    L, R, T, B = x + i, x + w - i, y + i, y + h - i
    fr = f'stroke="#FFFFFF" stroke-width="2.6" fill="none" stroke-linejoin="round"'
    if mode == "straight":
        s.add(f'<rect x="{L}" y="{T}" width="{R - L}" height="{B - T}" rx="{r}" {fr}/>')
    elif mode == "notch":
        a, b, d = cx - nw / 2 - 4, cx + nw / 2 + 4, y + nh + 4
        s.add(f'<path d="M{L} {T + r} a{r} {r} 0 0 1 {r} -{r} H{a} '
              f'C{a + 3} {T} {a + 3} {d} {a + 7} {d} H{b - 7} C{b - 3} {d} {b - 3} {T} {b} {T} '
              f'H{R - r} a{r} {r} 0 0 1 {r} {r} V{B - r} a{r} {r} 0 0 1 -{r} {r} H{L + r} '
              f'a{r} {r} 0 0 1 -{r} -{r} Z" {fr}/>')
    s.path(f"M{cx - nw / 2} {y} H{cx + nw / 2} V{y + nh - 3} a3 3 0 0 1 -3 3 H{cx - nw / 2 + 3} "
           f"a3 3 0 0 1 -3 -3 Z", fill="notch")


def settings():
    s = Scene("settings", 640, 680, LIGHT)
    s.window(0, 0, 640, 680, "Glassine Settings")

    # Tabs
    tabs, sel, iw = ["General", "Capture", "Output", "Shortcuts"], 1, 92
    tx = 320 - (iw * 4 + 4) / 2
    s.rect(tx, 46, iw * 4 + 4, 32, 10, "track")
    for i, t in enumerate(tabs):
        if i == sel:
            s.add('<g filter="url(#settings-sh-s)">')
            s.rect(tx + 2 + i * iw, 48, iw, 28, 8, "card")
            s.add("</g>")
        s.text(tx + 2 + i * iw + iw / 2, 67, t, 13.5, "s", "ink" if i == sel else "ink2", "middle",
               600 if i == sel else 400)

    s.text(34, 132, "Area capture", 28, "f", "ink", weight=460, ls=-.3)
    s.label(36, 160, "Screen frame")
    cw = 181
    for i, (mode, name) in enumerate([("straight", "Straight"), ("notch", "Around the notch"),
                                      ("none", "No frame")]):
        x = 34 + i * (cw + 14.5)
        if i == 1:
            s.rect(x - 3.5, 168.5, cw + 7, 91, 13.5, "none", "ink", 1.8)
        mini_screen(s, x, 172, cw, 84, mode)
        s.text(x + cw / 2, 282, name, 13.5, "s", "ink" if i == 1 else "ink2", "middle",
               600 if i == 1 else 400)

    s.card(34, 304, 572, 138)
    rows = [("Frame bottom corners", "seg"), ("Magnifier while selecting", True), ("Start sound", False)]
    for i, (name, ctl) in enumerate(rows):
        cy = 304 + 23 + i * 46
        s.text(54, cy + 5, name, 14, "s", "ink")
        if ctl == "seg":
            s.segmented(586, cy, ["Rounded", "Square"], 0, 76)
        else:
            s.toggle(548, cy - 11, ctl)
        if i < 2:
            s.line(54, cy + 23, 586, cy + 23, "rule")

    s.text(34, 494, "Screen recording", 28, "f", "ink", weight=460, ls=-.3)
    s.card(34, 512, 572, 92)
    s.text(54, 540, "Countdown before recording", 14, "s", "ink")
    s.popup(586, 535, "3 seconds")
    s.line(54, 558, 586, 558, "rule")
    s.text(54, 586, "Show the pointer", 14, "s", "ink")
    s.toggle(548, 570, True)
    s.text(36, 630, "The countdown runs inside the record button. Off starts recording", 12.5, "s", "ink2")
    s.text(36, 648, "as soon as you press it.", 12.5, "s", "ink2")
    return s


def update():
    s = Scene("update", 520, 470, LIGHT)
    s.window(0, 0, 520, 470, "Software Update", "modal")

    # Icon: cream G on ink, the lower part in a glassine sleeve.
    s.add('<g filter="url(#update-sh-s)">')
    s.rect(30, 50, 62, 62, 15, "#1C2230")
    s.add("</g>")
    s.text(61, 99, "G", 46, "f", "#EDEBE2", "middle", 400, italic=True)
    s.path("M30 88 H92 V98 a14 14 0 0 1 -14 14 H44 a14 14 0 0 1 -14 -14 Z", fill="#FFFFFF",
           extra='fill-opacity=".13"')
    s.line(30, 88, 92, 88, "#FFFFFF", .8, 'stroke-opacity=".22"')

    s.text(108, 84, "Glassine 0.4 is here", 30, "f", "ink", weight=460, ls=-.3)
    s.text(109, 105, "You have 0.3.1 · 5.6 MB", 13, "s", "ink2")

    s.card(30, 134, 460, 254)
    y = 162
    for tag, col, items in [("Added", "sage_deep", ["A new look: paper, ink and Fraunces",
                                                    "Move and zoom the recorded area while recording"]),
                            ("Changed", "blue_deep", ["Previews sit on a stamp, dated like a postmark"]),
                            ("Fixed", "ochre", ["App audio from minimized or hidden windows"])]:
        w = len(tag) * 7.2 + 16
        s.rect(52, y - 13, w, 19, 3, "none", col, 1.1)
        s.text(52 + w / 2, y + 0.5, tag.upper(), 9.5, "m", col, "middle", 600, ls=1.2)
        y += 26
        for it in items:
            s.text(54, y, "–", 14, "s", "ink3")
            s.text(70, y, it, 14, "s", "ink")
            y += 23
        y += 14

    s.button(30, 412, 128, 32, "Skip this version", "quiet", 13.5)
    s.button(316, 412, 76, 32, "Later", "secondary")
    s.button(402, 412, 88, 32, "Update")
    return s


def recording():
    s = Scene("recording", 1000, 582, LIGHT)
    s.rect(0, 0, 1000, 582, 14, "desk")
    s.texture('<rect width="1000" height="582" rx="14"/>', "paper")
    s.add('<path d="M690 0 H986 a14 14 0 0 1 14 14 V568 a14 14 0 0 1 -14 14 H690 Z" fill="#EFEFEA"/>')

    # The window being recorded.
    s.add('<g filter="url(#recording-sh-m)">')
    s.rect(37, 55, 452, 345, 10, "card", "border")
    s.add("</g>")
    s.line(37, 83, 489, 83, "rule")
    for i in range(3):
        s.circle(52 + i * 15, 69, 4.5, "track")
    s.rect(61, 104, 256, 13, 6.5, "rule")
    s.rect(61, 126, 362, 8, 4, "rule")
    s.rect(61, 144, 330, 8, 4, "rule")
    s.rect(61, 171, 428, 155, 6, "sage")
    s.circle(433, 222, 26, "peach")

    # Selection: dashed frame, eight handles, size.
    x0, y0, x1, y1 = 80, 135, 462, 383
    s.rect(x0, y0, x1 - x0, y1 - y0, 0, "none", "ink", 1, 'stroke-dasharray="4 3" stroke-opacity=".7"')
    for hx in (x0, (x0 + x1) / 2, x1):
        for hy in (y0, (y0 + y1) / 2, y1):
            if hx == (x0 + x1) / 2 and hy == (y0 + y1) / 2:
                continue
            s.circle(hx, hy, 4, "#FFFFFF", "ink", 1.1)
    s.rect(225, 391, 92, 21, 6, "ink")
    s.text(271, 405.5, "840 × 540", 11, "m", "on_ink", "middle", 500)

    # Control strip, like a strip of stamps: tear-off lines between the record button, chips and tools.
    px, py, pw, ph = 475, 48, 76, 452
    cx = px + pw / 2
    s.add('<g filter="url(#recording-sh-m)">')
    s.rect(px, py, pw, ph, 22, "card", "border")
    s.add("</g>")
    s.texture(f'<rect x="{px}" y="{py}" width="{pw}" height="{ph}" rx="22"/>', "dots")
    s.circle(cx, py + 37, 23, "rec")
    s.circle(cx, py + 37, 16.5, "none", "#FFFFFF", 2)
    s.circle(cx, py + 37, 7, "#FFFFFF")
    s.perf_line(px + 14, px + pw - 14, py + 74)
    chips = [("Format", "MP4"), ("Codec", "H.264"), ("FPS", "60"), ("Bitrate", "Auto"),
             ("Scale", "Retina"), ("Audio", "2 tracks")]
    for i, (k, v) in enumerate(chips):
        cy = py + 84 + i * 40
        s.rect(px + 8, cy, pw - 16, 35, 9, "key")
        s.label(cx, cy + 13, k, "ink3", "middle", 8)
        s.text(cx, cy + 29, v, 14.5, "f", "ink", "middle", 500)
    s.perf_line(px + 14, px + pw - 14, py + 334)
    s.circle(cx, py + 362, 16, "ink")
    s.i_cursor(cx + 1, py + 362)
    s.circle(cx, py + 399, 16, "key", "border", .8)
    s.i_layout(cx, py + 399)
    s.circle(cx, py + 436, 16, "key", "border", .8)
    s.i_close(cx, py + 436)

    s.text(37, 555, "Before recording — drag inside or by the edge, eight handles", 15, "f", "ink2",
           italic=True)

    # Right: the two recording states.
    s.text(718, 46, "Recording, beside the area", 15, "f", "ink2", italic=True)
    bx, by = 718, 62
    s.add('<g filter="url(#recording-sh-m)">')
    s.rect(bx, by, 214, 46, 23, "card", "border")
    s.add("</g>")
    s.texture(f'<rect x="{bx}" y="{by}" width="214" height="46" rx="23"/>', "dots")
    for i, op in enumerate((1, .55, .25)):
        s.circle(bx + 18, by + 13 + i * 10, 2.4, "rec", extra=f'fill-opacity="{op}"')
    s.text(bx + 30, by + 31, "0:42", 23, "f", "ink", weight=460)
    s.circle(bx + 108, by + 23, 15, "key")
    s.i_pause(bx + 108, by + 23)
    s.circle(bx + 146, by + 23, 15, "key")
    s.i_stop(bx + 146, by + 23)
    s.circle(bx + 184, by + 23, 15, "key")
    s.i_trash(bx + 184, by + 23)

    s.text(718, 146, "No room — docked to the screen edge", 15, "f", "ink2", italic=True)
    s.rect(718, 162, 252, 308, 10, "desk")
    s.rect(736, 186, 138, 102, 6, "card", "border")
    s.rect(966, 162, 4, 308, 0, "notch")
    d = "M966 210 Q966 222 954 222 H918 Q902 222 902 238 V396 Q902 412 918 412 H954 Q966 412 966 424 Z"
    s.add('<g filter="url(#recording-sh-s)">')
    s.path(d, fill="card", stroke="border")
    s.add("</g>")
    s.texture(f'<path d="{d}"/>', "dots")
    dc = 934
    for i, op in enumerate((1, .55, .25)):
        s.circle(dc - 9 + i * 9, 240, 2.3, "rec", extra=f'fill-opacity="{op}"')
    s.text(dc, 271, "0:42", 19, "f", "ink", "middle", 460)
    s.circle(dc, 300, 14, "key")
    s.i_pause(dc, 300)
    s.circle(dc, 336, 14, "key")
    s.i_stop(dc, 336, 10)
    s.circle(dc, 372, 14, "key")
    s.i_trash(dc, 372)
    return s


def previews():
    s = Scene("previews", 520, 460, LIGHT)
    s.rect(0, 0, 520, 460, 14, "desk")
    s.texture('<rect width="520" height="460" rx="14"/>', "paper")

    # Toast
    s.add('<g filter="url(#previews-sh-m)">')
    s.rect(24, 24, 156, 52, 26, "card", "border")
    s.add("</g>")
    s.check(50, 50, 13)
    s.text(72, 47, "Text copied", 17, "f", "ink", weight=480)
    s.text(72, 64, "3 lines", 12, "s", "ink2")

    # Screenshot preview, hovered.
    x, y, w, h = 262, 112, 236, 184
    s.stamp(x, y, w, h, "card", hole=2.5, pitch=8.4)
    ix, iy, iw, ih = x + 12, y + 12, w - 24, 132
    s.rect(ix, iy, iw, ih, 3, "sage")
    s.rect(ix + 22, iy + 20, 112, 66, 4, "#E9EAE3")
    s.circle(ix + 172, iy + 92, 24, "peach")
    s.rect(ix, iy, iw, ih, 3, "ink", extra='fill-opacity=".42"')
    for i, lbl in enumerate(("Copy", "Save")):
        s.add('<g filter="url(#previews-sh-s)">')
        s.rect(ix + iw / 2 - 52, iy + 22 + i * 30, 104, 25, 12.5, "card")
        s.add("</g>")
        s.text(ix + iw / 2, iy + 39 + i * 30, lbl, 13, "s", "ink", "middle", 600)
    s.add('<g filter="url(#previews-sh-s)">')
    s.rect(ix + iw / 2 - 62, iy + 82, 124, 25, 12.5, "blue_deep")
    s.add("</g>")
    s.i_qr(ix + iw / 2 - 42, iy + 94.5)
    s.text(ix + iw / 2 + 8, iy + 99, "Copy QR link", 13, "s", "on_ink", "middle", 600)
    for cxx, icon in ((ix + 12, "close"), (ix + iw - 34, "pencil"), (ix + iw - 12, "pin")):
        s.circle(cxx, iy + 12, 9.5, "card")
        if icon == "close":
            s.i_close(cxx, iy + 12, 3.2, "ink", 1.6)
        elif icon == "pin":
            s.add(f'<g transform="translate({cxx} {iy + 12}) scale(.78) translate({-cxx} {-(iy + 12)})">')
            s.i_pin(cxx, iy + 12, "ink")
            s.add("</g>")
        else:
            s.add(f'<g transform="translate({cxx} {iy + 12}) scale(.8) translate({-cxx} {-(iy + 12)})">')
            s.i_pencil(cxx, iy + 12, "ink")
            s.add("</g>")
    s.text(ix + 1, y + h - 17, "22 Oct · 16:14", 14, "f", "ink", italic=True, weight=440)
    s.text(ix + iw, y + h - 17, "1280 × 760", 12, "s", "ink2", "end")

    # Recording preview.
    y2, h2 = 310, 132
    s.stamp(x, y2, w, h2, "card", hole=2.5, pitch=8.4)
    s.rect(ix, y2 + 12, iw, 80, 3, "blue")
    s.rect(ix + 18, y2 + 24, 126, 56, 4, "#E6E4DB")
    s.rect(ix + 10, y2 + 66, 58, 19, 6, "ink", extra='fill-opacity=".78"')
    s.path(f"M{ix + 18} {y2 + 71} v9 l7.5 -4.5 z", fill="on_ink")
    s.text(ix + 30, y2 + 79.5, "0:42", 11.5, "s", "on_ink", weight=600)
    s.text(ix + 1, y2 + h2 - 17, "22 Oct · 16:20", 14, "f", "ink", italic=True, weight=440)
    s.text(ix + iw, y2 + h2 - 17, "MP4 · 2 tracks", 12, "s", "ink2", "end")
    return s


def dark():
    c = DARK
    s = Scene("dark", 560, 460, c)
    s.rect(0, 0, 560, 460, 14, "desk")
    s.window(24, 24, 512, 228)
    s.text(48, 88, "Screen recording", 27, "f", "ink", weight=460, ls=-.3)
    s.card(48, 106, 464, 92)
    s.text(68, 134, "Countdown before recording", 14, "s", "ink")
    s.popup(492, 129, "3 seconds")
    s.line(68, 152, 492, 152, "rule")
    s.text(68, 180, "Show the pointer", 14, "s", "ink")
    s.toggle(454, 164, True)
    s.text(49, 226, "The countdown runs inside the record button. Off starts right away.", 12.5, "s", "ink2")

    bx, by = 24, 276
    s.rect(bx, by, 178, 46, 23, "card", "border")
    s.texture(f'<rect x="{bx}" y="{by}" width="178" height="46" rx="23"/>', "dots")
    for i, op in enumerate((1, .55, .25)):
        s.circle(bx + 18, by + 13 + i * 10, 2.4, "rec", extra=f'fill-opacity="{op}"')
    s.text(bx + 30, by + 31, "0:42", 23, "f", "ink", weight=460)
    s.circle(bx + 110, by + 23, 15, "key")
    s.i_pause(bx + 110, by + 23)
    s.circle(bx + 148, by + 23, 15, "key")
    s.i_stop(bx + 148, by + 23)

    s.button(226, 283, 80, 32, "Later", "secondary")
    s.button(316, 283, 92, 32, "Update")
    s.add('<g filter="url(#dark-sh-m)">')
    s.rect(424, 276, 112, 46, 23, "card", "border")
    s.add("</g>")
    s.check(447, 299, 12)
    s.text(466, 304, "Copied", 15, "f", "ink", weight=480)

    sw = [("desk", "Desk"), ("paper", "Paper"), ("card", "Card"), ("ink", "Ink"), ("ink2", "Ink 2"),
          ("rec", "Rec"), ("sage", "Sage"), ("blue", "Stamp")]
    for i, (k, name) in enumerate(sw):
        x = 24 + i * 64
        s.rect(x, 352, 54, 54, 10, k, "border")
        s.text(x, 424, name, 11, "s", "ink2", weight=500)
        s.text(x, 438, c[k].upper(), 9, "m", "ink3")
    return s


def editor():
    """The editor: neutral canvas (decision 4), paper only on the floating panels."""
    s = Scene("editor", 1120, 760, LIGHT)
    s.window(0, 0, 1120, 760, "Glassine 2026-10-22 at 16.14.06")
    s.path("M0 38 H1120 V746 a14 14 0 0 1 -14 14 H14 a14 14 0 0 1 -14 -14 Z", fill="#E6E6E4")
    s.line(0, 38, 1120, 38, "border")

    def stroke(col, sw=1.6):
        return (f'stroke="{s.c.get(col, col)}" stroke-width="{sw}" fill="none" '
                f'stroke-linecap="round" stroke-linejoin="round"')

    def icon(kind, cx, cy, col="ink2"):
        st, f = stroke(col), s.c.get(col, col)
        g = {
            "select": f'<path d="M{cx - 4} {cy - 7} v13 l3.2 -3 l2.3 5 l2 -.9 l-2.2 -4.8 h4.4 z" fill="{f}"/>',
            "arrow": f'<g {st}><path d="M{cx - 6} {cy + 6} L{cx + 6} {cy - 6}"/><path d="M{cx} {cy - 6} H{cx + 6} V{cy}"/></g>',
            "line": f'<path {st} d="M{cx - 6} {cy + 6} L{cx + 6} {cy - 6}"/>',
            "rectangle": f'<rect {st} x="{cx - 7}" y="{cy - 5.5}" width="14" height="11" rx="2"/>',
            "ellipse": f'<ellipse {st} cx="{cx}" cy="{cy}" rx="7.5" ry="5.8"/>',
            "pen": f'<path {st} d="M{cx - 7} {cy + 3} c2 -6 4 -6 5 -1 s3 5 5 0 s2 -5 3 -3"/>',
            "marker": (f'<g {st}><path d="M{cx - 4} {cy + 6} l-2 -2 l7 -9 l4 4 l-9 7 z"/>'
                       f'<path d="M{cx - 7} {cy + 7} h6" stroke-width="2.6" stroke-opacity=".45"/></g>'),
            "step": (f'<circle {st} cx="{cx}" cy="{cy}" r="7"/><text x="{cx}" y="{cy + 3.6}" class="s" fill="{f}" '
                     f'text-anchor="middle" style="font-size:10px;font-weight:700">1</text>'),
            "blur": "".join(f'<circle cx="{cx + dx}" cy="{cy + dy}" r="{r}" fill="{f}" fill-opacity="{o}"/>'
                            for dx, dy, r, o in [(0, 0, 2.6, .9), (-5, 0, 1.8, .5), (5, 0, 1.8, .5),
                                                 (0, -5, 1.8, .5), (0, 5, 1.8, .5), (-4.5, -4.5, 1.2, .25),
                                                 (4.5, -4.5, 1.2, .25), (-4.5, 4.5, 1.2, .25), (4.5, 4.5, 1.2, .25)]),
            "pixelate": "".join(f'<rect x="{cx - 6 + i % 3 * 4}" y="{cy - 6 + i // 3 * 4}" width="4" height="4" '
                                f'fill="{f}" fill-opacity="{o}"/>'
                                for i, o in enumerate([.9, .35, .7, .3, .85, .45, .6, .25, .9])),
            "redact": (f'<rect x="{cx - 7}" y="{cy - 4}" width="14" height="5" rx="1" fill="{f}"/>'
                       f'<path {st} d="M{cx - 7} {cy + 4.5} h9" stroke-opacity=".5"/>'),
            "crop": f'<g {st}><path d="M{cx - 4} {cy - 8} V{cy + 4} H{cx + 8}"/><path d="M{cx - 8} {cy - 4} H{cx + 4} V{cy + 8}"/></g>',
            "undo": f'<g {st}><path d="M{cx - 5} {cy - 2} h7 a4 4 0 0 1 0 8 h-3"/><path d="M{cx - 2} {cy - 5} l-3 3 l3 3"/></g>',
            "redo": f'<g {st}><path d="M{cx + 5} {cy - 2} h-7 a4 4 0 0 0 0 8 h3"/><path d="M{cx + 2} {cy - 5} l3 3 l-3 3"/></g>',
            "copy": f'<g {st}><rect x="{cx - 5}" y="{cy - 3}" width="9" height="10" rx="2"/><path d="M{cx - 2} {cy - 6} h7 a2 2 0 0 1 2 2 v7"/></g>',
            "save": f'<g {st}><path d="M{cx} {cy - 7} v9"/><path d="M{cx - 3.5} {cy - 1.5} l3.5 3.5 l3.5 -3.5"/><path d="M{cx - 7} {cy + 2} v4 h14 v-4"/></g>',
            "frame": (f'<g {st}><rect x="{cx - 8}" y="{cy - 6.5}" width="16" height="13" rx="2"/>'
                      f'<path d="M{cx - 5} {cy + 3} l3.5 -4 l2.5 2.5 l2 -2 l2.5 3.5"/></g>'),
        }[kind]
        s.add(g)

    def capsule(x, y, w, h):
        s.add(f'<g filter="url(#editor-sh-m)">')
        s.rect(x, y, w, h, h / 2, "card", "border")
        s.add("</g>")

    def vperf(x, cy):
        for dy in (-7, 0, 7):
            s.circle(x, cy + dy, 1.4, "border")

    # ---- the image being edited: background preset "Stamp", padding 40, corners 14, shadow ----
    gid = s.id("grad")
    s.defs.append(f'<linearGradient id="{gid}" x1="0" y1="0" x2="1" y2="1">'
                  f'<stop offset="0" stop-color="#9DB3CC"/><stop offset="1" stop-color="#5E7C9E"/></linearGradient>')
    bx, by, bw, bh = 430, 150, 600, 430
    s.rect(bx, by, bw, bh, 0, f"url(#{gid})")
    ix, iy, iw, ih = bx + 40, by + 40, bw - 80, bh - 80
    s.add('<g filter="url(#editor-sh-m)">')
    s.rect(ix, iy, iw, ih, 14, "#FFFFFF")
    s.add("</g>")
    # Screenshot content: a plain checkout page (user content, not themed).
    s.add(f'<g><clipPath id="editor-shot"><rect x="{ix}" y="{iy}" width="{iw}" height="{ih}" rx="14"/></clipPath>'
          f'<g clip-path="url(#editor-shot)">')
    s.rect(ix, iy, iw, 38, 0, "#F4F4F5")
    for i in range(3):
        s.circle(ix + 18 + i * 15, iy + 19, 4.5, "#D4D4D8")
    s.rect(ix + 190, iy + 11, 160, 16, 8, "#E4E4E7")
    s.add("</g></g>")
    tx = ix + 32
    s.text(tx, iy + 80, "Order summary", 21, "s", "#18181B", weight=600)
    rows = [("Glassine Pro — yearly", "$96.00"), ("Tax", "$0.00")]
    for i, (k, v) in enumerate(rows):
        y = iy + 118 + i * 32
        s.text(tx, y, k, 14, "s", "#3F3F46")
        s.text(ix + iw - 32, y, v, 14, "s", "#3F3F46", "end")
        s.line(tx, y + 12, ix + iw - 32, y + 12, "#ECECEE")
    s.text(tx, iy + 194, "Total", 15, "s", "#18181B", weight=600)
    s.text(ix + iw - 32, iy + 194, "$96.00", 15, "s", "#18181B", "end", 600)
    s.text(tx, iy + 236, "Receipt to", 13, "s", "#71717A")
    # Pixelated e-mail.
    px0, py0 = tx + 80, iy + 222
    for i in range(22):
        for j in range(3):
            shade = ["#D4D4D8", "#A1A1AA", "#E4E4E7", "#BDBDC4"][(i * 7 + j * 3) % 4]
            s.rect(px0 + i * 7, py0 + j * 6, 7, 6, 0, shade)
    s.rect(tx, iy + 270, 176, 40, 9, "#2563EB")
    s.text(tx + 88, iy + 295, "Place order", 14, "s", "#FFFFFF", "middle", 600)

    # Annotations in the system-bright palette.
    red, orange = "#FF3B30", "#FF9500"
    # Selected rectangle around Total, with ink handles.
    rx0, ry0, rx1, ry1 = tx - 12, iy + 172, ix + iw - 20, iy + 206
    s.rect(rx0, ry0, rx1 - rx0, ry1 - ry0, 6, "none", orange, 4)
    for hx in (rx0, (rx0 + rx1) / 2, rx1):
        for hy in (ry0, (ry0 + ry1) / 2, ry1):
            if (hx, hy) != ((rx0 + rx1) / 2, (ry0 + ry1) / 2):
                s.circle(hx, hy, 4.5, "#FFFFFF", "ink", 1.3)
    # Numbered steps.
    for n, (cx, cy) in enumerate([(px0 + 22 * 7 + 20, iy + 231), (tx + 196, iy + 290)], start=1):
        s.circle(cx, cy, 13, red)
        s.text(cx, cy + 5, str(n), 14, "s", "#FFFFFF", "middle", 700)
    # Arrow and text.
    s.path(f"M{ix + iw - 60} {iy + 262} Q{ix + iw - 120} {iy + 300} {tx + 220} {iy + 292}", stroke=red, sw=6,
           extra='stroke-linecap="round"')
    s.path(f"M{tx + 216} {iy + 292} l15 -11 l-1 21 z", fill=red, extra=f'stroke="{red}" stroke-width="2" stroke-linejoin="round"')
    s.text(ix + iw - 150, iy + 254, "Pay here", 22, "s", red, weight=700)

    # ---- toolbar ----
    groups = [["select"], ["arrow", "line", "rectangle", "ellipse"], ["text", "pen", "marker", "step"],
              ["blur", "pixelate", "redact"], ["crop"]]
    bw_, gap, sep = 34, 2, 18
    width = sum(len(g) * bw_ + (len(g) - 1) * gap for g in groups) + sep * (len(groups) - 1) + 16
    tx0, ty0, th = 560 - width / 2, 54, 46
    capsule(tx0, ty0, width, th)
    x = tx0 + 8
    hover = None
    for gi, g in enumerate(groups):
        if gi:
            vperf(x + sep / 2 - gap / 2, ty0 + th / 2)
            x += sep - gap
        for tool in g:
            cx, cy = x + bw_ / 2, ty0 + th / 2
            if tool == "select":
                s.circle(cx, cy, 16, "ink")
                icon(tool, cx + 1, cy, "on_ink")
            elif tool == "text":
                s.text(cx, cy + 6, "T", 17, "f", "ink2", "middle", 500)
            else:
                icon(tool, cx, cy)
            if tool == "pixelate":
                hover = (cx, cy)
                s.circle(cx, cy, 16, "key")
                icon(tool, cx, cy)
            x += bw_ + gap
    # Tooltip for the hovered tool.
    hx, hy = hover
    s.add('<g filter="url(#editor-sh-m)">')
    s.rect(hx - 112, hy + 30, 224, 62, 10, "card", "border")
    s.add("</g>")
    s.path(f"M{hx - 7} {hy + 31} l7 -7 l7 7", fill="card", stroke="border")
    s.rect(hx - 8, hy + 30.5, 16, 2, 0, "card")
    s.text(hx - 98, hy + 52, "Pixelate", 14, "s", "ink", weight=600)
    s.keycaps(hx + 98, hy + 47, ["P"])
    s.text(hx - 98, hy + 72, "Turns names and numbers into", 12.5, "s", "ink2")
    s.text(hx - 98, hy + 87, "large squares, for good.", 12.5, "s", "ink2")

    # ---- style bar, bottom left ----
    sy, sh = 760 - 16 - 50, 50
    palette = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#FFFFFF", "#1C1C1E"]
    sw_ = 7 * 24 + 26 + 18 + 158 + 18 + 36 + 28
    capsule(16, sy, sw_, sh)
    x = 16 + 18
    cy = sy + sh / 2
    for i, col in enumerate(palette):
        if i == 0:
            s.circle(x + 9, cy, 12.5, "none", "ink", 2)
        s.circle(x + 9, cy, 9, col, "border" if col == "#FFFFFF" else None, .8)
        x += 24
    # Custom color: a ring of the spectrum.
    for k, col in enumerate(["#FF3B30", "#FFCC00", "#34C759", "#007AFF"]):
        a0, a1 = k * math.pi / 2, (k + 1) * math.pi / 2
        x0, y0 = x + 9 + 9 * math.cos(a0), cy + 9 * math.sin(a0)
        x1, y1 = x + 9 + 9 * math.cos(a1), cy + 9 * math.sin(a1)
        s.path(f"M{x + 9} {cy} L{x0:.2f} {y0:.2f} A9 9 0 0 1 {x1:.2f} {y1:.2f} Z", fill=col)
    s.circle(x + 9, cy, 4.5, "card")
    x += 26
    vperf(x + 6, cy)
    x += 18
    s.circle(x + 8, cy, 4.5, "#FF3B30")
    s.rect(x + 22, cy - 2, 100, 4, 2, "track")
    s.rect(x + 22, cy - 2, 27, 4, 2, "ink")
    s.add('<g filter="url(#editor-sh-s)">')
    s.circle(x + 49, cy, 8, "#FFFFFF", "border", .8)
    s.add("</g>")
    s.text(x + 132, cy + 4.5, "6", 13, "s", "ink2", weight=500)
    x += 158
    vperf(x + 2, cy)
    x += 14
    s.circle(x + 18, cy, 17, "key", "ink", 1.4)
    icon("frame", x + 18, cy, "ink")
    bg_btn = (x + 18, cy)

    # ---- background popover above the background button ----
    ow, oh = 300, 286
    ox = bg_btn[0] - ow + 44  # the arrow sits near the panel's right end, over its button
    oy = sy - 14 - oh
    s.add('<g filter="url(#editor-sh-m)">')
    s.rect(ox, oy, ow, oh, 14, "card", "border")
    s.add("</g>")
    ax = bg_btn[0]
    s.path(f"M{ax - 9} {oy + oh - 1} l9 9 l9 -9", fill="card", stroke="border")
    s.rect(ax - 10, oy + oh - 2.5, 20, 2.5, 0, "card")
    s.texture(f'<rect x="{ox}" y="{oy}" width="{ow}" height="{oh}" rx="14"/>', "paper")
    s.text(ox + 18, oy + 36, "Background", 20, "f", "ink", weight=460)
    # Row 1: extend, transparent, white, black.
    r1 = oy + 54
    s.rect(ox + 18, r1, 34, 34, 8, "#F4F4F5", "border")
    s.path(f"M{ox + 29} {r1 + 23} l12 -12 M{ox + 35} {r1 + 11} h6 v6 M{ox + 29} {r1 + 17} v6 h6",
           stroke="ink2", sw=1.4, extra='stroke-linecap="round" stroke-linejoin="round"')
    for i in range(4):
        for j in range(4):
            s.rect(ox + 60 + i * 8.5, r1 + j * 8.5, 8.5, 8.5, 0, "#FFFFFF" if (i + j) % 2 else "#DADAD2")
    s.rect(ox + 60, r1, 34, 34, 8, "none", "border")
    s.rect(ox + 102, r1, 34, 34, 8, "#FFFFFF", "border")
    s.rect(ox + 144, r1, 34, 34, 8, "#1C1C1E", "border")
    # Row 2: gradients in the new palette.
    r2 = r1 + 44
    presets = [("Sleeve", "#F7F7F3", "#E2E3DC"), ("Sage", "#B9C7B2", "#6F8869"), ("Stamp", "#9DB3CC", "#5E7C9E"),
               ("Peach", "#F2D9BF", "#D9A57C"), ("Ink", "#3A4254", "#1C2230")]
    for i, (name, a, b) in enumerate(presets):
        gx = ox + 18 + i * 42
        g2 = s.id("grad")
        s.defs.append(f'<linearGradient id="{g2}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{a}"/>'
                      f'<stop offset="1" stop-color="{b}"/></linearGradient>')
        if name == "Stamp":
            s.rect(gx - 3.5, r2 - 3.5, 41, 41, 10.5, "none", "ink", 2)
        s.rect(gx, r2, 34, 34, 8, f"url(#{g2})", "border")
    # Sliders and shadow.
    def slider(y, title, frac, val):
        s.text(ox + 18, y + 4.5, title, 13.5, "s", "ink")
        s.rect(ox + 92, y - 2, 150, 4, 2, "track")
        s.rect(ox + 92, y - 2, 150 * frac, 4, 2, "ink")
        s.add('<g filter="url(#editor-sh-s)">')
        s.circle(ox + 92 + 150 * frac, y, 8, "#FFFFFF", "border", .8)
        s.add("</g>")
        s.text(ox + ow - 18, y + 4.5, val, 13, "s", "ink2", "end", 500)
    slider(r2 + 64, "Padding", .4, "40")
    slider(r2 + 96, "Corners", .45, "14")
    s.text(ox + 18, r2 + 133, "Shadow", 13.5, "s", "ink")
    s.toggle(ox + ow - 56, r2 + 117, True)
    s.text(ox + 18, oy + oh - 18, "Grows by itself when marks go past the edge.", 12, "s", "ink2")

    # ---- action bar, bottom right ----
    aw = 36 * 2 + 18 + 3 * 74 + 86 + 18
    ax0 = 1120 - 16 - aw
    capsule(ax0, sy, aw, sh)
    x = ax0 + 10
    for k in ("undo", "redo"):
        icon(k, x + 18, cy)
        x += 36
    vperf(x + 6, cy)
    x += 14
    for k, label in (("copy", "Copy"), ("save", "Save"), ("pin", "Pin")):
        s.rect(x, cy - 16, 70, 32, 16, "key")
        if k == "pin":
            s.i_pin(x + 18, cy)
        else:
            icon(k, x + 18, cy)
        s.text(x + 31, cy + 5, label, 13.5, "s", "ink", weight=500)
        x += 74
    s.button(x + 2, cy - 17, 84, 34, "Done")
    return s


SCENES = [("1-welcome", welcome), ("2-settings", settings), ("3-update", update),
          ("4-recording", recording), ("5-previews", previews), ("6-dark", dark), ("7-editor", editor)]


def main():
    os.makedirs(os.path.join(HERE, "svg"), exist_ok=True)
    blocks = []
    for name, fn in SCENES:
        sc = fn()
        svg = sc.svg()
        with open(os.path.join(HERE, "svg", f"{name}.svg"), "w") as f:
            f.write(svg)
        blocks.append(f'<figure><figcaption>{name}</figcaption>{svg.split("?>")[-1]}</figure>')
        print("svg/" + name + ".svg", sc.w, sc.h)
    with open(os.path.join(HERE, "index.html"), "w") as f:
        f.write("""<!doctype html><meta charset="utf-8"><title>Glassine 0.4 scenes</title>
<style>body{margin:0;padding:40px;background:#E6E7E1;font:13px -apple-system,sans-serif;color:#585F6C}
main{display:flex;flex-wrap:wrap;gap:40px;align-items:flex-start}figure{margin:0}
figcaption{margin:0 0 10px;font:500 11px 'SF Mono',ui-monospace,monospace;letter-spacing:1px;text-transform:uppercase}
svg{max-width:100%;height:auto;display:block}</style><main>""" + "\n".join(blocks) + "</main>\n")


if __name__ == "__main__":
    main()
