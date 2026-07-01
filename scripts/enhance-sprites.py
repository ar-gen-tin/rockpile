#!/usr/bin/env python3
"""
精灵质量增强脚本 — 基于现有 PNG，不改造型

增强项:
1. 轮廓线 (1px 深色描边，增加辨识度)
2. 高光 (顶部边缘提亮)
3. 阴影 (底部边缘加深)
4. 导出 @1x (64px) + @2x (128px) + @3x (192px)

用法:
  python3 scripts/enhance-sprites.py                # 增强全部
  python3 scripts/enhance-sprites.py idle_neutral   # 只增强一个
  python3 scripts/enhance-sprites.py --preview      # 生成 HTML 对比
"""

import os, sys, math
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow"])
    from PIL import Image, ImageDraw, ImageFilter

ASSETS_DIR = Path("Rockpile/Assets.xcassets")
OUTPUT_DIR = Path("Rockpile/Resources/EnhancedSprites")
FRAME_SIZE = 64

# ── Enhancement functions ──────────────────────────────

def add_outline(img, color=None, thickness=1):
    """Add a 1px outline around non-transparent pixels."""
    w, h = img.size
    pixels = img.load()
    outline = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out_pixels = outline.load()

    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a > 0:
                continue
            # Check neighbors
            for dx, dy in [(-1,0),(1,0),(0,-1),(0,1)]:
                nx, ny = x+dx, y+dy
                if 0 <= nx < w and 0 <= ny < h:
                    _, _, _, na = pixels[nx, ny]
                    if na > 128:
                        if color:
                            out_pixels[x, y] = color
                        else:
                            # Auto-color: darker version of neighbor
                            nr, ng, nb, _ = pixels[nx, ny]
                            out_pixels[x, y] = (
                                max(0, nr - 60),
                                max(0, ng - 60),
                                max(0, nb - 60),
                                200
                            )
                        break

    result = Image.alpha_composite(outline, img)
    return result


def add_highlight(img, strength=0.15):
    """Brighten top edge pixels."""
    w, h = img.size
    result = img.copy()
    pixels = img.load()
    out = result.load()

    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a < 128:
                continue
            # Check if top edge (pixel above is transparent)
            if y == 0 or pixels[x, y-1][3] < 128:
                boost = int(255 * strength)
                out[x, y] = (
                    min(255, r + boost),
                    min(255, g + boost),
                    min(255, b + boost),
                    a
                )
    return result


def add_shadow(img, strength=0.2):
    """Darken bottom edge pixels."""
    w, h = img.size
    result = img.copy()
    pixels = img.load()
    out = result.load()

    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a < 128:
                continue
            # Check if bottom edge
            if y == h-1 or pixels[x, y+1][3] < 128:
                darken = int(255 * strength)
                out[x, y] = (
                    max(0, r - darken),
                    max(0, g - darken),
                    max(0, b - darken),
                    a
                )
    return result


def enhance_sprite_strip(img):
    """Apply all enhancements to a sprite strip, frame by frame."""
    w, h = img.size
    num_frames = w // FRAME_SIZE
    result = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    for i in range(num_frames):
        x0 = i * FRAME_SIZE
        frame = img.crop((x0, 0, x0 + FRAME_SIZE, h))

        # Apply enhancements
        frame = add_outline(frame)
        frame = add_highlight(frame)
        frame = add_shadow(frame)

        result.paste(frame, (x0, 0))

    return result


def export_multiscale(name, enhanced, original):
    """Export @1x, @2x, @3x versions."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    w, h = enhanced.size

    # @1x — original size (64px frames)
    enhanced.save(OUTPUT_DIR / f"{name}@1x.png", "PNG")

    # @2x — doubled (128px frames)
    scaled2 = enhanced.resize((w * 2, h * 2), Image.NEAREST)
    scaled2.save(OUTPUT_DIR / f"{name}@2x.png", "PNG")

    # @3x — tripled (192px frames)
    scaled3 = enhanced.resize((w * 3, h * 3), Image.NEAREST)
    scaled3.save(OUTPUT_DIR / f"{name}@3x.png", "PNG")

    return {
        "@1x": os.path.getsize(OUTPUT_DIR / f"{name}@1x.png"),
        "@2x": os.path.getsize(OUTPUT_DIR / f"{name}@2x.png"),
        "@3x": os.path.getsize(OUTPUT_DIR / f"{name}@3x.png"),
    }


def update_imageset(name):
    """Update Contents.json to include @1x/@2x/@3x."""
    imageset_dir = ASSETS_DIR / f"{name}.imageset"
    if not imageset_dir.exists():
        return

    import shutil
    src_dir = OUTPUT_DIR

    # Copy enhanced files
    for scale in ["@1x", "@2x", "@3x"]:
        src = src_dir / f"{name}{scale}.png"
        if src.exists():
            if scale == "@1x":
                dst = imageset_dir / f"{name}.png"
            else:
                dst = imageset_dir / f"{name}{scale}.png"
            shutil.copy2(src, dst)

    # Update Contents.json
    contents = '''{
  "images" : [
    {
      "filename" : "''' + name + '''.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "''' + name + '''@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "''' + name + '''@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}'''
    (imageset_dir / "Contents.json").write_text(contents)


def generate_preview_html(results):
    """Generate before/after comparison HTML."""
    import base64

    html_parts = ['''<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>Sprite Enhancement Preview</title>
<style>
body { background: #0a0a0a; color: #fafafa; font-family: "JetBrains Mono", monospace; padding: 40px; }
h1 { color: #10B981; }
.pair { display: flex; gap: 24px; margin: 16px 0; align-items: center; }
.pair img { image-rendering: pixelated; height: 64px; }
.pair .enhanced img { height: 128px; }
.label { font-size: 10px; color: #666; }
.tag { font-size: 9px; padding: 2px 6px; background: #10B98122; color: #10B981; }
hr { border: 0; border-top: 1px solid #222; margin: 24px 0; }
</style></head><body>
<h1>Sprite Enhancement: Before / After</h1>
<p style="color:#666">轮廓线 + 高光 + 阴影 | 造型不变 | @1x/@2x/@3x</p><hr>''']

    for name, data in results.items():
        orig_path = data["original"]
        enh_path = OUTPUT_DIR / f"{name}@2x.png"
        if not enh_path.exists():
            continue

        with open(orig_path, "rb") as f:
            orig_b64 = base64.b64encode(f.read()).decode()
        with open(enh_path, "rb") as f:
            enh_b64 = base64.b64encode(f.read()).decode()

        html_parts.append(f'''
<div class="pair">
  <div>
    <div class="label">BEFORE — {name}</div>
    <img src="data:image/png;base64,{orig_b64}">
  </div>
  <div>→</div>
  <div class="enhanced">
    <div class="label">AFTER — enhanced @2x <span class="tag">{data["sizes"]["@1x"]//1024}KB @1x / {data["sizes"]["@2x"]//1024}KB @2x</span></div>
    <img src="data:image/png;base64,{enh_b64}">
  </div>
</div>''')

    html_parts.append('</body></html>')

    preview_path = Path("/tmp/sprite-enhance-preview.html")
    preview_path.write_text('\n'.join(html_parts))
    return preview_path


# ── Main ──────────────────────────────────────────────

def main():
    filter_name = None
    preview = False
    for arg in sys.argv[1:]:
        if arg == "--preview":
            preview = True
        else:
            filter_name = arg

    # Find all sprites
    sprites = []
    for imageset in sorted(ASSETS_DIR.glob("*.imageset")):
        name = imageset.stem
        if name == "AppIcon":
            continue
        png = next(imageset.glob("*.png"), None)
        if not png:
            continue
        if filter_name and filter_name not in name:
            continue
        sprites.append((name, str(png)))

    print(f"Enhancing {len(sprites)} sprites...")
    results = {}

    for name, png_path in sprites:
        try:
            img = Image.open(png_path).convert("RGBA")
            enhanced = enhance_sprite_strip(img)
            sizes = export_multiscale(name, enhanced, img)
            update_imageset(name)
            results[name] = {"original": png_path, "sizes": sizes}
            print(f"  ✓ {name}: @1x {sizes['@1x']//1024}KB, @2x {sizes['@2x']//1024}KB, @3x {sizes['@3x']//1024}KB")
        except Exception as e:
            print(f"  ✗ {name}: {e}")

    print(f"\nDone: {len(results)} enhanced")

    if preview or "--preview" in sys.argv:
        path = generate_preview_html(results)
        print(f"Preview: {path}")
        os.system(f"open {path}")


if __name__ == "__main__":
    main()
