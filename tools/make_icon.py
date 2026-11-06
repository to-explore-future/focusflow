"""生成 FocusFlow 的 App 图标 + 菜单栏模板图标。

构图（按真实桌面习惯）：下方一台笔记本，上方两台显示器，
两台显示器的中线对齐笔记本的中线；鼠标指针停在左边那块屏上，表示"这块是当前屏"。
"""
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
S = 1024
SS = 4


def rounded_bg(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = int(size * 0.225)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=(28, 26, 40, 255))
    top, bottom = (40, 38, 62), (16, 15, 24)
    for y in range(size):
        t = y / (size - 1)
        c = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        d.line([(0, y), (size, y)], fill=c + (255,))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=255)
    img.putalpha(mask)
    return img


def cursor_polygon(x, y, h):
    pts = [
        (0.00, 0.00), (0.00, 0.78), (0.20, 0.60), (0.33, 0.98),
        (0.47, 0.93), (0.35, 0.56), (0.62, 0.54),
    ]
    return [(x + px * h, y + py * h) for px, py in pts]


def draw_screen(img, d, box, lit, radius, bezel):
    x0, y0, x1, y1 = box
    d.rounded_rectangle([x0 - bezel, y0 - bezel, x1 + bezel, y1 + bezel],
                        radius=radius + bezel // 2, fill=(46, 49, 63, 255))
    inner_r = radius
    if lit:
        w, h = x1 - x0, y1 - y0
        screen = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        sd = ImageDraw.Draw(screen)
        for yy in range(h):
            t = yy / max(1, h - 1)
            c = (int(150 * (1 - t) + 62 * t), int(214 * (1 - t) + 150 * t), 255)
            sd.line([(0, yy), (w, yy)], fill=c + (255,))
        mask = Image.new("L", (w, h), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=inner_r, fill=255)
        screen.putalpha(mask)
        img.alpha_composite(screen, (x0, y0))
    else:
        d.rounded_rectangle([x0, y0, x1, y1], radius=inner_r, fill=(29, 31, 41, 255))


def build():
    w = S * SS
    img = rounded_bg(w)
    d = ImageDraw.Draw(img)

    cx = w // 2
    bezel = int(w * 0.009)

    # 三块屏幕同等大小
    scr_w, scr_h = int(w * 0.360), int(w * 0.360 / (16.0 / 9.0))
    gap_x = int(w * 0.030)
    row_gap = int(w * 0.075)

    # 依据整体高度反推起始位置，让构图在画布里居中
    total_h = scr_h * 2 + row_gap + int(w * 0.030)
    top = (w - total_h) // 2
    top_row_bottom = top + scr_h
    bottom_row_top = top_row_bottom + row_gap

    left_x = cx - gap_x // 2 - scr_w
    right_x = cx + gap_x // 2
    boxes = [
        (left_x, top, left_x + scr_w, top_row_bottom),
        (right_x, top, right_x + scr_w, top_row_bottom),
    ]
    laptop = (cx - scr_w // 2, bottom_row_top, cx + scr_w // 2, bottom_row_top + scr_h)

    # 左边那块是当前屏：外发光
    glow = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rounded_rectangle(list(boxes[0]), radius=int(w * 0.014), fill=(90, 180, 255, 210))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(int(w * 0.045))))
    d = ImageDraw.Draw(img)

    # 上方两台显示器的支架
    for (x0, y0, x1, y1) in boxes:
        mcx = (x0 + x1) // 2
        neck_w, neck_h = int(w * 0.022), int(w * 0.024)
        base_w, base_h = int(w * 0.110), int(w * 0.010)
        d.rectangle([mcx - neck_w // 2, y1, mcx + neck_w // 2, y1 + neck_h], fill=(58, 62, 78, 255))
        d.rounded_rectangle([mcx - base_w // 2, y1 + neck_h, mcx + base_w // 2, y1 + neck_h + base_h],
                            radius=base_h // 2, fill=(58, 62, 78, 255))

    draw_screen(img, d, boxes[0], True, int(w * 0.010), bezel)
    draw_screen(img, d, boxes[1], False, int(w * 0.010), bezel)

    # 下方笔记本：同样的屏幕尺寸 + 更宽的底座
    lx0, ly0, lx1, ly1 = laptop
    draw_screen(img, d, laptop, False, int(w * 0.010), bezel)
    base_h = int(w * 0.018)
    base_w = int(scr_w * 1.12)
    by = ly1 + int(w * 0.007)
    d.rounded_rectangle([cx - base_w // 2, by, cx + base_w // 2, by + base_h],
                        radius=base_h // 2, fill=(52, 56, 71, 255))
    d.rounded_rectangle([cx - int(base_w * 0.16), by - int(w * 0.006),
                         cx + int(base_w * 0.16), by],
                        radius=int(w * 0.003), fill=(40, 43, 56, 255))

    # 鼠标指针：停在左边那块亮屏上
    cur_h = int(w * 0.150)
    cur_x = boxes[0][0] + scr_w * 0.44
    cur_y = top + scr_h * 0.14
    pts = cursor_polygon(cur_x, cur_y, cur_h)
    d.polygon(pts, fill=(255, 255, 255, 255))
    d.line(pts + [pts[0]], fill=(18, 22, 36, 255), width=max(2, int(w * 0.0045)))

    out = img.resize((S, S), Image.LANCZOS)
    iconset = ROOT / "build" / "AppIcon.iconset"
    iconset.mkdir(parents=True, exist_ok=True)
    for base in (16, 32, 128, 256, 512):
        out.resize((base, base), Image.LANCZOS).save(iconset / f"icon_{base}x{base}.png")
        out.resize((base * 2, base * 2), Image.LANCZOS).save(iconset / f"icon_{base}x{base}@2x.png")
    subprocess.run(["iconutil", "-c", "icns", str(iconset),
                    "-o", str(ROOT / "Resources" / "AppIcon.icns")], check=True)

    out.save("/tmp/focusflow-icon-v3.png")
    print("已生成 v3 图标")


if __name__ == "__main__":
    build()
