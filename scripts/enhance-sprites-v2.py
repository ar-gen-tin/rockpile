#!/usr/bin/env python3
"""
精灵增强 v2 — 在 v1 基础上优化:
1. 更智能的轮廓线 (自适应颜色深度, 对角线也描边)
2. 亚像素高光带 (顶部 2 行渐变提亮)
3. 底部环境光 (模拟水塘蓝光反射)
4. 对比度增强 (暗部加深, 亮部提亮)
5. @1x 也应用增强 (覆盖原文件)
"""

import os, sys, math
from pathlib import Path

try:
    from PIL import Image, ImageEnhance
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow"])
    from PIL import Image, ImageEnhance

ASSETS_DIR = Path("Rockpile/Assets.xcassets")
OUTPUT_DIR = Path("Rockpile/Resources/EnhancedSprites")
FRAME_SIZE = 64


def enhance_frame(img):
    """Apply all enhancements to a single 64x64 frame."""
    w, h = img.size
    px = img.load()

    # Pass 1: Boost contrast — darken darks, brighten brights
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 32: continue
            # S-curve contrast
            for ch in [r, g, b]:
                pass
            lum = (r * 299 + g * 587 + b * 114) / 1000
            if lum > 128:
                boost = 1.12  # brighten highlights
            else:
                boost = 0.88  # darken shadows
            px[x, y] = (
                max(0, min(255, int(r * boost))),
                max(0, min(255, int(g * boost))),
                max(0, min(255, int(b * boost))),
                a
            )

    # Pass 2: Top highlight (2px gradient)
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 64: continue
            # Is this a top-edge pixel? (pixel above is transparent)
            above_transparent = (y == 0 or px[x, y-1][3] < 32)
            above2_transparent = (y <= 1 or px[x, y-2][3] < 32) if y > 0 else True

            if above_transparent:
                # First row: strong highlight
                px[x, y] = (min(255, r+45), min(255, g+45), min(255, b+45), a)
            elif above2_transparent and y > 0 and px[x, y-1][3] >= 32:
                # Second row: softer highlight
                px[x, y] = (min(255, r+20), min(255, g+20), min(255, b+20), a)

    # Pass 3: Bottom shadow + blue ambient (water reflection)
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 64: continue
            below_transparent = (y == h-1 or px[x, y+1][3] < 32)
            below2_transparent = (y >= h-2 or px[x, y+2][3] < 32) if y < h-1 else True

            if below_transparent:
                # Bottom edge: darken + slight blue tint (water reflection)
                px[x, y] = (
                    max(0, r - 35),
                    max(0, g - 30),
                    min(255, max(0, b - 15)),  # less blue reduction = blue tint
                    a
                )
            elif below2_transparent and y < h-1 and px[x, y+1][3] >= 32:
                px[x, y] = (max(0, r-15), max(0, g-12), max(0, b-5), a)

    # Pass 4: Left light / right shadow (directional lighting)
    result = img.copy()
    rpx = result.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 64: continue
            left_edge = (x == 0 or px[x-1, y][3] < 32)
            right_edge = (x == w-1 or px[x+1, y][3] < 32)
            if left_edge:
                rpx[x, y] = (min(255, r+18), min(255, g+18), min(255, b+18), a)
            elif right_edge:
                rpx[x, y] = (max(0, r-18), max(0, g-18), max(0, b-18), a)
            else:
                rpx[x, y] = (r, g, b, a)

    return result


def add_outline(img):
    """Add 1px adaptive outline around non-transparent pixels."""
    w, h = img.size
    px = img.load()
    # Create larger canvas for outline
    out = Image.new("RGBA", (w+2, h+2), (0,0,0,0))
    opx = out.load()

    # 8-directional outline
    dirs = [(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]

    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 64:
                for dx, dy in dirs:
                    nx, ny = x+dx, y+dy
                    if 0 <= nx < w and 0 <= ny < h:
                        if px[nx, ny][3] < 32:
                            # Outline color: darker version of source pixel
                            dark_factor = 0.35
                            opx[nx+1, ny+1] = (
                                max(0, int(r * dark_factor)),
                                max(0, int(g * dark_factor)),
                                max(0, int(b * dark_factor)),
                                min(a, 210)
                            )
                    else:
                        # Outside image bounds
                        opx[x+dx+1, y+dy+1] = (
                            max(0, int(r * 0.35)),
                            max(0, int(g * 0.35)),
                            max(0, int(b * 0.35)),
                            min(a, 210)
                        )

    # Paste enhanced sprite on top
    out.paste(img, (1, 1), img)
    return out


def process_strip(img):
    """Process entire sprite strip frame by frame."""
    w, h = img.size
    num_frames = w // FRAME_SIZE
    result_frames = []

    for i in range(num_frames):
        x0 = i * FRAME_SIZE
        frame = img.crop((x0, 0, x0 + FRAME_SIZE, h))
        enhanced = enhance_frame(frame)
        outlined = add_outline(enhanced)
        result_frames.append(outlined)

    # Assemble strip (each frame is now FRAME_SIZE+2 x h+2)
    fw = result_frames[0].width
    fh = result_frames[0].height
    strip = Image.new("RGBA", (fw * num_frames, fh), (0,0,0,0))
    for i, frame in enumerate(result_frames):
        strip.paste(frame, (i * fw, 0))

    return strip, num_frames


def export(name, strip, num_frames):
    """Export @1x, @2x, @3x and update imageset."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # @1x — enhanced at original resolution
    strip.save(OUTPUT_DIR / f"{name}@1x.png", "PNG")

    # @2x — pixel-perfect doubling
    w, h = strip.size
    s2 = strip.resize((w*2, h*2), Image.NEAREST)
    s2.save(OUTPUT_DIR / f"{name}@2x.png", "PNG")

    # @3x
    s3 = strip.resize((w*3, h*3), Image.NEAREST)
    s3.save(OUTPUT_DIR / f"{name}@3x.png", "PNG")

    # Update imageset
    imageset = ASSETS_DIR / f"{name}.imageset"
    if imageset.exists():
        import shutil
        # @1x replaces original
        shutil.copy2(OUTPUT_DIR / f"{name}@1x.png", imageset / f"{name}.png")
        shutil.copy2(OUTPUT_DIR / f"{name}@2x.png", imageset / f"{name}@2x.png")
        shutil.copy2(OUTPUT_DIR / f"{name}@3x.png", imageset / f"{name}@3x.png")

        # Update Contents.json
        contents = '''{
  "images" : [
    { "filename" : "''' + name + '''.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "''' + name + '''@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "''' + name + '''@3x.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}'''
        (imageset / "Contents.json").write_text(contents)

    sizes = {s: os.path.getsize(OUTPUT_DIR / f"{name}{s}.png") for s in ["@1x","@2x","@3x"]}
    return sizes


def main():
    filter_name = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] != "--preview" else None
    preview = "--preview" in sys.argv

    sprites = []
    for imageset in sorted(ASSETS_DIR.glob("*.imageset")):
        name = imageset.stem
        if name == "AppIcon": continue
        # Use ORIGINAL backup if exists, otherwise current
        png = next(imageset.glob("*.png"), None)
        if not png: continue
        if filter_name and filter_name not in name: continue
        sprites.append((name, str(png)))

    print(f"Enhancing v2: {len(sprites)} sprites")
    print(f"  Contrast boost + 2-row highlight + bottom blue ambient + directional light + 8-dir outline")
    print()

    results = {}
    for name, path in sprites:
        try:
            img = Image.open(path).convert("RGBA")
            strip, nf = process_strip(img)
            sizes = export(name, strip, nf)
            results[name] = {"path": path, "sizes": sizes}
            print(f"  ✓ {name}: {nf}f → @1x {sizes['@1x']//1024}KB @2x {sizes['@2x']//1024}KB @3x {sizes['@3x']//1024}KB")
        except Exception as e:
            print(f"  ✗ {name}: {e}")

    print(f"\n{'='*50}")
    print(f"Done: {len(results)} enhanced")

    if preview:
        generate_preview(results)


def generate_preview(results):
    import base64
    html = ['<!DOCTYPE html><html><head><meta charset="utf-8"><title>Enhanced v2 Preview</title>']
    html.append('<style>body{background:#050510;color:#fafafa;font-family:"JetBrains Mono",monospace;padding:24px}')
    html.append('h1{color:#10B981;font-size:18px}')
    html.append('.row{display:flex;gap:12px;margin:6px 0;align-items:center}')
    html.append('.row img{image-rendering:pixelated;background:#080810;border:1px solid #111;padding:3px}')
    html.append('.lb{font-size:7px;color:#444}')
    html.append('.nm{font-size:8px;color:#666;width:100px;text-align:right}')
    html.append('.pond{background:linear-gradient(180deg,#010610,#030E28,#051838);padding:20px;margin:16px 0;border-radius:8px;display:flex;gap:32px;justify-content:center}')
    html.append('@keyframes bob{0%,100%{transform:translateY(0)}50%{transform:translateY(-4px)}}')
    html.append('.bob{animation:bob 2.5s ease-in-out infinite}')
    html.append('</style></head><body>')
    html.append('<h1>Enhanced v2 — 增强效果预览</h1>')
    html.append('<p style="color:#555;font-size:9px">对比度增强 + 2行高光 + 底部蓝色环境光 + 左右方向光 + 8向自适应描边</p>')

    # Pond preview with enhanced sprites
    html.append('<div class="pond">')
    for name in ["crab_idle_neutral", "crab_working_neutral", "idle_neutral", "working_neutral"]:
        enh = OUTPUT_DIR / f"{name}@2x.png"
        if enh.exists():
            with open(enh, "rb") as f:
                b64 = base64.b64encode(f.read()).decode()
            html.append(f'<div class="bob" style="animation-delay:{-hash(name)%20/10}s"><img src="data:image/png;base64,{b64}" height="80"><div style="text-align:center;font-size:7px;color:#444">{name.split("_")[0]}</div></div>')
    html.append('</div>')

    for name, data in sorted(results.items()):
        enh2 = OUTPUT_DIR / f"{name}@2x.png"
        if not enh2.exists(): continue
        with open(enh2, "rb") as f:
            eb64 = base64.b64encode(f.read()).decode()
        html.append(f'<div class="row">')
        html.append(f'<div class="nm">{name}</div>')
        html.append(f'<img src="data:image/png;base64,{eb64}" height="64">')
        html.append(f'<div class="lb">@2x {data["sizes"]["@2x"]//1024}KB</div>')
        html.append(f'</div>')

    html.append('</body></html>')
    out = Path("/tmp/rockpile-enhance-v2.html")
    out.write_text('\n'.join(html))
    print(f"Preview: {out}")
    os.system(f"open {out}")


if __name__ == "__main__":
    main()
