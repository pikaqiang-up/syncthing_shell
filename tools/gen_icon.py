#!/usr/bin/env python3
"""生成 MD3 风格自适应应用图标。

产物（写入 android/app/src/main/res/）：
  - mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher_foreground.png  108dp 画布，安全区内白色同步箭头
  - mipmap-anydpi-v26/ic_launcher.xml / ic_launcher_round.xml  自适应（背景色 + 前景 + 单色层）
  - mipmap-{...}dpi/ic_launcher.png / ic_launcher_round.png    遗留全彩（圆形安全形状）
  - values/ic_launcher_colors.xml                              背景色

设计：Material 3 风格 —— 品牌主色 #0891B1 纯色背景，
前景为两段粗圆弧对接箭头（sync 语义），粗描边、圆端点、几何化。
单色层复用前景（按 alpha 采样），支持 Android 13+ 主题色图标。
"""
import math
import os

from PIL import Image, ImageDraw

RES = os.path.join(os.path.dirname(__file__), '..', 'android', 'app', 'src', 'main', 'res')
BG = (8, 145, 177, 255)        # #0891B1
FG = (255, 255, 255, 255)      # 白色箭头
DENS = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0}


def draw_glyph(draw, cx, cy, r, stroke, color=FG):
    """两段 140° 圆弧 + 顺时针端箭头 + 圆端点。坐标基于中心/半径/描边宽。"""
    s = stroke

    def pt(deg, rr=None):
        rr = rr or r
        a = math.radians(deg)
        return (cx + rr * math.cos(a), cy + rr * math.sin(a))

    def cap(p, rad):
        draw.ellipse([p[0] - rad, p[1] - rad, p[0] + rad, p[1] + rad], fill=color)

    def arrow_head(tip_deg, ccw=False):
        """在弧的 tip_deg 端画三角箭头（指向切线方向）。"""
        tip = pt(tip_deg)
        base_deg = tip_deg + (18 if ccw else -18) * -1  # 箭头底边朝弧身
        # 箭头指向：切线方向（顺时针运动方向 = 角度增大方向）
        head = s * 2.6
        tangent = math.radians(tip_deg + (90 if not ccw else -90))
        bx = tip[0] - head * 0.9 * math.cos(tangent)
        by = tip[1] - head * 0.9 * math.sin(tangent)
        # 垂直方向展开
        nx = -math.sin(tangent)
        ny = math.cos(tangent)
        w = head * 0.62
        p1 = (bx + nx * w, by + ny * w)
        p2 = (bx - nx * w, by - ny * w)
        draw.polygon([tip, p1, p2], fill=color)
        # 圆角连接
        for p in (p1, p2):
            cap(p, w * 0.55)
        cap((bx, by), w * 0.5)

    # 弧 1：右上段（-60° → 80°），箭头在 80° 端（顺时针指向左上→下）
    a1_start, a1_end = -60, 80
    draw.arc([cx - r, cy - r, cx + r, cy + r], a1_start, a1_end, fill=color, width=s)
    cap(pt(a1_start), s / 2)
    arrow_head(a1_end)

    # 弧 2：左下段（120° → 260°），箭头在 260° 端（顺时针指向右下→上）
    a2_start, a2_end = 120, 260
    draw.arc([cx - r, cy - r, cx + r, cy + r], a2_start, a2_end, fill=color, width=s)
    cap(pt(a2_start), s / 2)
    arrow_head(a2_end)


def make_foreground(size):
    """108dp 自适应前景：glyph 限制在中央安全区（~66/108）"""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    scale = size / 108.0
    # 安全区直径 66dp，glyph 半径取 23dp，描边 8dp（M3 粗线条）
    cx = cy = size / 2
    draw_glyph(d, cx, cy, 18.5 * scale, int(round(7 * scale)))
    return img


def make_legacy(size, round_shape=True):
    """遗留图标：品牌色安全形状（圆/圆角方）+ 白色 glyph（占 ~64%）"""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # 圆形底（所有启动器都会显示的安全形状）
    margin = int(size * 0.02)
    d.ellipse([margin, margin, size - margin, size - margin], fill=BG)
    # 内描边高光（M3 tonal 层次感）：外缘 2px 亮一档
    ring = max(2, int(size * 0.012))
    d.ellipse([margin, margin, size - margin, size - margin],
              outline=(255, 255, 255, 46), width=ring)
    scale = size / 108.0
    draw_glyph(d, size / 2, size / 2, 20 * scale, int(round(8.5 * scale)))
    return img


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


def main():
    for dpi, mult in DENS.items():
        fg_size = int(108 * mult)
        save(make_foreground(fg_size),
             f'{RES}/mipmap-{dpi}/ic_launcher_foreground.png')
        legacy = int(48 * mult)
        save(make_legacy(legacy), f'{RES}/mipmap-{dpi}/ic_launcher.png')
        save(make_legacy(legacy), f'{RES}/mipmap-{dpi}/ic_launcher_round.png')

    # 自适应图标 XML（v26+）
    os.makedirs(f'{RES}/mipmap-anydpi-v26', exist_ok=True)
    for name in ('ic_launcher', 'ic_launcher_round'):
        with open(f'{RES}/mipmap-anydpi-v26/{name}.xml', 'w') as f:
            f.write(
                '<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')

    # 背景色
    with open(f'{RES}/values/ic_launcher_colors.xml', 'w') as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources>\n'
            '    <color name="ic_launcher_background">#0891B1</color>\n'
            '</resources>\n')

    # 预览图（供检查）
    prev = Image.new('RGBA', (512, 512), (0, 0, 0, 0))
    d = ImageDraw.Draw(prev)
    d.ellipse([6, 6, 506, 506], fill=BG)
    draw_glyph(d, 256, 256, 100, 34)
    prev.save('/tmp/icon_preview.png')
    print('生成完成')


if __name__ == '__main__':
    main()
