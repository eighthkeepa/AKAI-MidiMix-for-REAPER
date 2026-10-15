"""Pictures for the README, drawn from the script's own draw calls.

Runs the real script against the REAPER mock (tests/render_scene.lua), records every ReaImGui draw call and
paints it with Pillow. The font is a stand-in for ReaImGui's, so spacing differs by a pixel or two.

Usage (from the repo root):  python3 -I tests/render_preview.py       needs: lupa, Pillow
Writes docs/images/mixer-classic.png, mixer-mpc.png, mixer-demo.gif
"""
import os
import sys
import lupa
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 2  # supersampling for PNG
FONT_PATHS = ["/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
              "/usr/share/fonts/dejavu/DejaVuSansMono.ttf",
              "/System/Library/Fonts/Menlo.ttc"]
FONT_FILE = next(p for p in FONT_PATHS if os.path.exists(p))
FONT = ImageFont.truetype(FONT_FILE, 12 * S)


def measure(text):
    return FONT.getlength(str(text)) / S


def rgba(v):
    v = int(v)
    return ((v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255)


def make_scene(style, lang="en"):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().STYLE = style
    lua.globals().LANG = lang
    lua.globals().measure = measure
    lua.execute(open("tests/render_scene.lua", encoding="utf-8").read())
    return lua.globals().frame


TITLE_H = 22
BG = (15, 15, 15)


def paint(cmds, scale=S):
    cmds = list(cmds.values())
    # window size from the draw calls
    maxx = maxy = 0
    for c in cmds:
        p = c.split("\t")
        if p[0] in ("rectf", "rect", "line"):
            maxx = max(maxx, float(p[1]), float(p[3])); maxy = max(maxy, float(p[2]), float(p[4]))
    # the status line decides the width too (ImGui sizes the window to its widest row)
    wx = 8
    for c in cmds:
        p = c.split("\t")
        if p[0] == "w":
            wx += measure(p[3]) + (18 + 8 if p[1] == "radio" else (20 if p[1] == "button" else 0))
    maxx = max(maxx, wx)
    W, H = int(maxx + 8), int(maxy + 12)
    im = Image.new("RGB", (W * scale, H * scale), BG)
    d = ImageDraw.Draw(im, "RGBA")
    font = FONT if scale == S else ImageFont.truetype(FONT_FILE, 12 * scale)

    def sc(*v):
        return [x * scale for x in v]

    # title bar and the status / tab rows (laid out here, like ImGui would)
    d.rectangle(sc(0, 0, W, TITLE_H), fill=(0xBC, 0x01, 0x2E))
    d.text(sc(8, 4), "AKAI MidiMix", font=font, fill=(255, 255, 255))
    x, y, row_h = 8, TITLE_H + 6, 20
    first = True
    tabx, tab_y = 8, TITLE_H + 6 + 20 + 6
    for c in cmds:
        p = c.split("\t")
        if p[0] == "same":
            continue
    # widgets in order (same-line handling: widgets stay on one line except the first one after a break)
    for idx, c in enumerate(cmds):
        p = c.split("\t")
        if p[0] != "w":
            continue
        kind, a, text = p[1], p[2], p[3]
        w = measure(text)
        if kind == "text":
            d.text(sc(x, y + 3), text, font=font, fill=rgba(a))
            x += w
        elif kind == "radio":
            d.ellipse(sc(x, y + 3, x + 14, y + 17), fill=(40, 60, 90), outline=(70, 90, 120))
            if a == "1":
                d.ellipse(sc(x + 3.5, y + 6.5, x + 10.5, y + 13.5), fill=(110, 170, 255))
            d.text(sc(x + 18, y + 3), text, font=font, fill=(230, 230, 230))
            x += 18 + w + 8
        elif kind == "button":
            d.rounded_rectangle(sc(x, y + 1, x + w + 12, y + 19), radius=3 * scale, fill=(45, 80, 130))
            d.text(sc(x + 6, y + 3), text, font=font, fill=(230, 230, 230))
            x += w + 12 + 8
    for c in cmds:
        p = c.split("\t")
        if p[0] == "tab":
            w = measure(p[1]) + 16
            d.rounded_rectangle(sc(tabx, tab_y, tabx + w, tab_y + 22), radius=3 * scale,
                                fill=(66, 110, 180) if p[2] == "1" else (38, 48, 68))
            d.text(sc(tabx + 8, tab_y + 4), p[1], font=font, fill=(240, 240, 240))
            tabx += w + 3
    # draw list
    for c in cmds:
        p = c.split("\t")
        k = p[0]
        if k == "rectf":
            x1, y1, x2, y2, col, r = float(p[1]), float(p[2]), float(p[3]), float(p[4]), rgba(p[5]), float(p[6])
            if r > 0:
                d.rounded_rectangle(sc(x1, y1, x2 - 0.01, y2 - 0.01), radius=r * scale, fill=col)
            else:
                d.rectangle(sc(x1, y1, x2 - 0.01, y2 - 0.01), fill=col)
        elif k == "rect":
            x1, y1, x2, y2, col, r, t = float(p[1]), float(p[2]), float(p[3]), float(p[4]), rgba(p[5]), float(p[6]), float(p[7])
            d.rectangle(sc(x1, y1, x2, y2), outline=col, width=max(1, int(t * scale)))
        elif k == "line":
            x1, y1, x2, y2, col, t = float(p[1]), float(p[2]), float(p[3]), float(p[4]), rgba(p[5]), float(p[6])
            d.line(sc(x1, y1, x2, y2), fill=col, width=max(1, int(round(t * scale))))
        elif k == "circf":
            cx, cy, r, col = float(p[1]), float(p[2]), float(p[3]), rgba(p[4])
            d.ellipse(sc(cx - r, cy - r, cx + r, cy + r), fill=col)
        elif k == "text":
            tx, ty, col, text = float(p[1]), float(p[2]), rgba(p[3]), "\t".join(p[4:])
            d.text(sc(tx, ty), text, font=font, fill=col)
    return im


def staged(im, pad=36):
    """Window on a soft dark backdrop with a shadow, for the README."""
    W, H = im.size
    canvas = Image.new("RGB", (W + 2 * pad * S, H + 2 * pad * S), (28, 29, 33))
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rectangle([pad * S + 4, pad * S + 10, pad * S + W + 4, pad * S + H + 10], fill=(0, 0, 0, 160))
    sh = sh.filter(ImageFilter.GaussianBlur(14 * S))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), sh)
    canvas.paste(im, (pad * S, pad * S))
    return canvas.convert("RGB")


def main():
    os.makedirs("docs/images", exist_ok=True)
    gif_frames = []
    for style in ("classic", "mpc"):
        frame = make_scene(style)
        last = None
        for k in range(1, 70):
            cmds = frame()
            if k == 40:
                last = cmds
            if style and k >= 8 and k % 2 == 0 and len(gif_frames) < 10_000:
                gif_frames.append((style, cmds))
        im = staged(paint(last))
        im.save(f"docs/images/mixer-{style}.png", optimize=True)
        print("wrote", f"docs/images/mixer-{style}.png", im.size)
    # GIF: classic first, then MPC; 1x
    frames = []
    for style, cmds in gif_frames:
        im = paint(cmds, scale=1)
        frames.append(im)
    # same canvas size for all frames
    W = max(f.size[0] for f in frames); H = max(f.size[1] for f in frames)
    out = []
    for f in frames:
        c = Image.new("RGB", (W, H), BG)
        c.paste(f, (0, 0))
        out.append(c.quantize(colors=96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
    out[0].save("docs/images/mixer-demo.gif", save_all=True, append_images=out[1:], duration=160, loop=0, optimize=True, disposal=1)
    print("wrote docs/images/mixer-demo.gif", len(out), "frames", os.path.getsize("docs/images/mixer-demo.gif") // 1024, "KB")


if __name__ == "__main__":
    main()
