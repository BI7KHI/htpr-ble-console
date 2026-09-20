#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成「恒泰普瑞控制台」Android 启动图标。

设计语言与 App 仪表盘保持一致：
  深空蓝底 + 半圆环形速度表 + 蓝→绿→琥珀→红 四段渐变弧 + 白色指针

产出（写入 flutter_console/android/app/src/main/res/）：
  mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png            传统方形图标
  mipmap-{...}/ic_launcher_round.png                                 圆形图标
  mipmap-{...}/ic_launcher_foreground.png                            自适应图标前景
  mipmap-{...}/ic_launcher_monochrome.png                            Android13+ 主题图标
  mipmap-anydpi-v26/ic_launcher.xml / ic_launcher_round.xml          自适应图标声明
  values/ic_launcher_background.xml                                  自适应图标底色

用法：  python tools/make_icons.py [--preview out.png]
"""
from __future__ import annotations

import argparse
import math
import os
import sys

from PIL import Image, ImageDraw

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# ------------------------------------------------------------------ 配色
C_TRACK = (0x24, 0x30, 0x50)   # 弧底轨
C_TICK = (0x46, 0x58, 0x7F)    # 刻度
C_NEEDLE = (0xEA, 0xF3, 0xFF)  # 指针
C_HUB = (0x16, 0x20, 0x3A)     # 轴心
C_ACCENT = (0x4D, 0xA3, 0xFF)  # 品牌蓝
BG_TOP = (0x1E, 0x2B, 0x47)
BG_BOT = (0x0C, 0x10, 0x17)
BG_FLAT = (0x10, 0x18, 0x28)   # 自适应图标底色

GRAD = [
    (0.00, (0x4D, 0xA3, 0xFF)),
    (0.45, (0x35, 0xD0, 0x7F)),
    (0.75, (0xFF, 0xD4, 0x79)),
    (1.00, (0xFF, 0x5D, 0x5D)),
]

# ------------------------------------------------------------------ 几何
A0 = 150.0        # 起始角：Pillow 中 0°=3 点方向，顺时针增大 → 150° 位于左下
SWEEP = 240.0     # 扫角 → 缺口留在正下方
NEEDLE_T = 0.74   # 指针位置（占满量程）

SS = 4            # 超采样倍数


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def _mix(c1, c2, t: float):
    return tuple(int(round(_lerp(c1[i], c2[i], t))) for i in range(3))


def grad_color(t: float):
    """四段品牌渐变取色，t∈[0,1]"""
    t = max(0.0, min(1.0, t))
    for i in range(len(GRAD) - 1):
        t0, c0 = GRAD[i]
        t1, c1 = GRAD[i + 1]
        if t <= t1:
            span = t1 - t0
            return _mix(c0, c1, (t - t0) / span if span > 0 else 0.0)
    return GRAD[-1][1]


# ------------------------------------------------------------------ 背景
def _background(size: int, shape: str) -> Image.Image:
    if shape == "none":
        return Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if shape == "flat":
        return Image.new("RGBA", (size, size), BG_FLAT + (255,))

    grad = Image.new("RGBA", (size, size))
    px = grad.load()
    for y in range(size):
        col = _mix(BG_TOP, BG_BOT, y / max(1, size - 1))
        for x in range(size):
            px[x, y] = col + (255,)

    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    if shape == "circle":
        md.ellipse([0, 0, size - 1, size - 1], fill=255)
    else:  # rounded —— Android 传统图标标准圆角 22.5%
        md.rounded_rectangle([0, 0, size - 1, size - 1],
                             radius=int(size * 0.225), fill=255)
    grad.putalpha(mask)
    return grad


# ------------------------------------------------------------------ 表盘
def _draw_bolt(d: ImageDraw.ImageDraw, cx: float, cy: float,
               h: float, col) -> None:
    """在 (cx,cy) 居中绘制一枚高度 h 的闪电（多边形，避免字体依赖）"""
    w = h * 0.56
    # 归一化顶点（x∈[-0.5,0.5]·w, y∈[-0.5,0.5]·h）
    pts_n = [(0.16, -0.50), (-0.42, 0.10), (-0.02, 0.10),
             (-0.20, 0.50), (0.42, -0.12), (0.02, -0.12)]
    pts = [(cx + x * w, cy + y * h) for x, y in pts_n]
    d.polygon(pts, fill=col)


def _draw_gauge(img: Image.Image, zoom: float, mono: bool = False) -> None:
    """在 img 上绘制表盘；zoom 为整体缩放（相对画布边长）"""
    W = img.size[0]
    S = W * zoom
    cx = W / 2.0
    cy = W / 2.0 + 0.10 * S          # 略微下移，使半圆视觉居中
    R = 0.40 * S                     # 弧线中心线半径
    aw = 0.122 * S                   # 弧线粗细
    d = ImageDraw.Draw(img)
    bb = [cx - R, cy - R, cx + R, cy + R]

    track_c = (255, 255, 255, 255) if mono else C_TRACK + (255,)
    tick_c = (255, 255, 255, 200) if mono else C_TICK + (255,)
    needle_c = (255, 255, 255, 255) if mono else C_NEEDLE + (255,)
    hub_c = (0, 0, 0, 0) if mono else C_HUB + (255,)
    ring_c = (255, 255, 255, 255) if mono else C_ACCENT + (255,)

    # 1) 底轨：整条弧留一条更暗的底色，避免渐变弧两端出现硬边
    d.arc(bb, A0, A0 + SWEEP, fill=track_c, width=int(round(aw)))

    # 2) 闪电标：置于弧线缺口正中，点明「电动」属性
    if not mono:
        _draw_bolt(d, cx, cy + 0.30 * S, 0.175 * S, grad_color(0.10) + (255,))
    elif True:
        _draw_bolt(d, cx, cy + 0.30 * S, 0.175 * S, (255, 255, 255, 255))

    # 3) 渐变主弧：整条点亮，展示完整品牌四色
    if mono:
        d.arc(bb, A0, A0 + SWEEP, fill=(255, 255, 255, 255),
              width=int(round(aw)))
    else:
        seg = 288
        for i in range(seg):
            t = (i + 0.5) / seg
            a0 = A0 + SWEEP * (i / seg)
            a1 = A0 + SWEEP * ((i + 1) / seg)
            d.arc(bb, a0, a1 + 0.4,          # +0.4° 消除段间缝隙
                  fill=grad_color(t) + (255,), width=int(round(aw)))

    # 4) 指针（锥形）
    ang = math.radians(A0 + SWEEP * NEEDLE_T)
    L = 0.258 * S
    bw = 0.036 * S
    pa = ang + math.pi / 2.0
    tip = (cx + math.cos(ang) * L, cy + math.sin(ang) * L)
    b1 = (cx + math.cos(pa) * bw, cy + math.sin(pa) * bw)
    b2 = (cx - math.cos(pa) * bw, cy - math.sin(pa) * bw)
    d.polygon([tip, b1, b2], fill=needle_c)

    # 5) 轴心
    hr = 0.055 * S
    d.ellipse([cx - hr, cy - hr, cx + hr, cy + hr], fill=hub_c,
              outline=ring_c, width=max(1, int(round(0.017 * S))))


def render(size: int, zoom: float, shape: str, mono: bool = False) -> Image.Image:
    """渲染一张 size×size 图标（4× 超采样后降采样）"""
    big = size * SS
    bg_shape = "none" if mono else shape
    img = _background(big, bg_shape)
    _draw_gauge(img, zoom, mono=mono)
    return img.resize((size, size), Image.LANCZOS)


# ------------------------------------------------------------------ 资源
DENSITIES = [
    # 名称, 传统图标 px, 自适应图标 px
    ("mdpi", 48, 108),
    ("hdpi", 72, 162),
    ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324),
    ("xxxhdpi", 192, 432),
]

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
"""

BG_COLOR_XML = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#101828</color>
</resources>
"""


def write_xml(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def generate(res_dir: str) -> None:
    if not os.path.isdir(res_dir):
        raise SystemExit(f"未找到资源目录: {res_dir}")

    for name, legacy_px, adaptive_px in DENSITIES:
        out = os.path.join(res_dir, f"mipmap-{name}")
        os.makedirs(out, exist_ok=True)

        # 传统方形（圆角已烘进图里，兼容 API < 26）
        render(legacy_px, 0.96, "rounded").save(
            os.path.join(out, "ic_launcher.png"))
        # 圆形（部分启动器/ROM 会取用）
        render(legacy_px, 0.88, "circle").save(
            os.path.join(out, "ic_launcher_round.png"))
        # 自适应前景：内容需落在 108dp 画布中心安全区内
        render(adaptive_px, 0.66, "none").save(
            os.path.join(out, "ic_launcher_foreground.png"))
        # 单色层（Android 13+ 主题化图标）
        render(adaptive_px, 0.66, "none", mono=True).save(
            os.path.join(out, "ic_launcher_monochrome.png"))

        print(f"  mipmap-{name:<8} legacy {legacy_px}px · adaptive {adaptive_px}px")

    anydpi = os.path.join(res_dir, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    write_xml(os.path.join(anydpi, "ic_launcher.xml"), ADAPTIVE_XML)
    write_xml(os.path.join(anydpi, "ic_launcher_round.xml"), ADAPTIVE_XML)
    write_xml(os.path.join(res_dir, "values", "ic_launcher_background.xml"),
              BG_COLOR_XML)
    print("  mipmap-anydpi-v26/ic_launcher.xml + ic_launcher_round.xml")
    print("  values/ic_launcher_background.xml")


def main() -> None:
    ap = argparse.ArgumentParser(description="生成 HTPR 控制台启动图标")
    here = os.path.dirname(os.path.abspath(__file__))
    default_res = os.path.normpath(os.path.join(
        here, "..", "flutter_console", "android", "app", "src", "main", "res"))
    ap.add_argument("--res", default=default_res, help="res 目录")
    ap.add_argument("--preview", help="额外导出一张大图预览 (512px)")
    args = ap.parse_args()

    print("生成图标 →", args.res)
    generate(args.res)

    if args.preview:
        render(512, 0.96, "rounded").save(args.preview)
        print("预览图 →", args.preview)


if __name__ == "__main__":
    main()
