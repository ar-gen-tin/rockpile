#!/usr/bin/env python3
"""
Fix baked-in checkered backgrounds using saturation-based detection.
Red crayfish = high saturation/color. Gray background = low saturation.
"""

import os, math, colorsys
from pathlib import Path
from collections import deque

try:
    from PIL import Image
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow"])
    from PIL import Image

GEN_DIR = Path(__file__).parent / "gen"
ASSETS_DIR = Path(__file__).parent / "Rockpile" / "Assets.xcassets"
FRAME_SIZE = 64


def pixel_is_background(r, g, b, a):
    """
    Determine if pixel is likely background (gray checkered pattern).
    Uses saturation + brightness to distinguish gray bg from colored crayfish.
    """
    if a == 0:
        return True

    # Convert to HSV
    rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
    h, s, v = colorsys.rgb_to_hsv(rf, gf, bf)

    # Very low saturation = gray (background candidate)
    # But we need to exclude black outlines (very low brightness)
    # and white elements (very high brightness with low saturation like eyes)

    # Background checkered pattern: mid-gray, low saturation
    # Typical values: (128,128,128) or (50,50,50) alternating

    if s < 0.15:
        # Low saturation (grayish/white)
        # Exclude only very dark pixels (black outlines): v < 0.10
        # Allow bright whites since flood-fill from edges protects interior white (eyes)
        if v > 0.10:
            return True

    return False


def remove_background(img: Image.Image) -> Image.Image:
    """
    Remove checkered background using saturation-based flood fill from edges.
    """
    img = img.convert("RGBA")
    w, h = img.size
    pixels = img.load()

    is_bg = [[False] * h for _ in range(w)]
    visited = [[False] * h for _ in range(w)]
    queue = deque()

    # Seed from all edge pixels that look like background
    for x in range(w):
        for y_edge in [0, h - 1]:
            r, g, b, a = pixels[x, y_edge]
            if pixel_is_background(r, g, b, a):
                queue.append((x, y_edge))
                is_bg[x][y_edge] = True
                visited[x][y_edge] = True

    for y in range(h):
        for x_edge in [0, w - 1]:
            if not visited[x_edge][y]:
                r, g, b, a = pixels[x_edge, y]
                if pixel_is_background(r, g, b, a):
                    queue.append((x_edge, y))
                    is_bg[x_edge][y] = True
                    visited[x_edge][y] = True

    # BFS flood fill - spread through background pixels only
    directions = [(0, 1), (0, -1), (1, 0), (-1, 0),
                  (1, 1), (1, -1), (-1, 1), (-1, -1)]  # 8-connected

    while queue:
        cx, cy = queue.popleft()
        for dx, dy in directions:
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < w and 0 <= ny < h and not visited[nx][ny]:
                visited[nx][ny] = True
                nr, ng, nb, na = pixels[nx, ny]
                if pixel_is_background(nr, ng, nb, na):
                    is_bg[nx][ny] = True
                    queue.append((nx, ny))

    # Apply transparency
    result = img.copy()
    rp = result.load()
    bg_count = 0

    for x in range(w):
        for y in range(h):
            if is_bg[x][y]:
                rp[x, y] = (0, 0, 0, 0)
                bg_count += 1

    # Edge softening: make border pixels between sprite and bg semi-transparent
    for x in range(1, w - 1):
        for y in range(1, h - 1):
            if not is_bg[x][y]:
                bg_neighbors = 0
                for dx, dy in [(0, 1), (0, -1), (1, 0), (-1, 0)]:
                    if is_bg[x + dx][y + dy]:
                        bg_neighbors += 1
                # If pixel is surrounded by mostly background, soften it
                if bg_neighbors >= 2:
                    r, g, b, a = rp[x, y]
                    rp[x, y] = (r, g, b, max(0, a - 80))

    pct = bg_count / (w * h) * 100
    return result, pct


# ── Sprite assembly ───────────────────────────────────────────────────

SPRITES = {
    "idle_neutral":       (6, "breathe"),
    "idle_happy":         (6, "breathe"),
    "idle_sad":           (6, "breathe"),
    "idle_angry":         (6, "tremble"),
    "thinking_neutral":   (6, "tilt"),
    "thinking_happy":     (6, "tilt"),
    "working_neutral":    (6, "sway"),
    "working_happy":      (6, "sway"),
    "working_sad":        (6, "sway"),
    "waiting_neutral":    (6, "look"),
    "waiting_sad":        (6, "look"),
    "error_neutral":      (6, "tremble"),
    "error_sad":          (6, "tremble"),
    "sleeping_neutral":   (6, "sleep"),
    "sleeping_happy":     (6, "sleep"),
    "compacting_neutral": (5, "rotate"),
    "compacting_happy":   (5, "rotate"),
}


def center_crop_resize(img, size):
    w, h = img.size
    s = min(w, h)
    left = (w - s) // 2
    top = (h - s) // 2
    cropped = img.crop((left, top, left + s, top + s))
    return cropped.resize((size, size), Image.LANCZOS)


def gen_frames(base, num_frames, anim_type):
    frames = []
    for i in range(num_frames):
        t = i / max(num_frames - 1, 1)
        frame = base.copy()
        if anim_type == "breathe":
            dy = round(math.sin(t * 2 * math.pi) * 1.5)
            c = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            c.paste(frame, (0, dy), frame)
            frame = c
        elif anim_type == "tilt":
            a = math.sin(t * 2 * math.pi) * 3
            frame = frame.rotate(a, resample=Image.BICUBIC, expand=False, fillcolor=(0, 0, 0, 0))
        elif anim_type in ("sway", "look"):
            dx = round(math.sin(t * 2 * math.pi) * 2)
            c = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            c.paste(frame, (dx, 0), frame)
            frame = c
        elif anim_type == "tremble":
            dx = round(math.sin(t * 4 * math.pi) * 2)
            dy = round(math.cos(t * 4 * math.pi) * 1)
            c = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            c.paste(frame, (dx, dy), frame)
            frame = c
        elif anim_type == "sleep":
            dy = round(math.sin(t * 2 * math.pi) * 1)
            c = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            c.paste(frame, (0, dy), frame)
            frame = c
        elif anim_type == "rotate":
            a = -t * 360
            frame = frame.rotate(a, resample=Image.BICUBIC, expand=False, fillcolor=(0, 0, 0, 0))
        frames.append(frame)
    return frames


def assemble_strip(frames):
    n = len(frames)
    strip = Image.new("RGBA", (FRAME_SIZE * n, FRAME_SIZE), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_SIZE, 0), f)
    return strip


def ensure_imageset(name, png_path):
    imageset_dir = ASSETS_DIR / f"{name}.imageset"
    imageset_dir.mkdir(parents=True, exist_ok=True)
    (imageset_dir / "Contents.json").write_text(f'''\u007b
  "images" : [
    \u007b
      "filename" : "{name}.png",
      "idiom" : "universal",
      "scale" : "1x"
    \u007d
  ],
  "info" : \u007b
    "author" : "xcode",
    "version" : 1
  \u007d
\u007d''')
    import shutil
    shutil.copy2(png_path, imageset_dir / f"{name}.png")


def main():
    print("🔧 Saturation-based background removal + sprite assembly")
    print()

    fixed_dir = GEN_DIR / "fixed2"
    fixed_dir.mkdir(exist_ok=True)
    strips_dir = GEN_DIR / "strips2"
    strips_dir.mkdir(exist_ok=True)

    success = 0
    for name, (num_frames, anim_type) in SPRITES.items():
        src = GEN_DIR / f"{name}.png"
        if not src.exists():
            print(f"❌ {name}: not found")
            continue

        # Step 1: Remove background
        print(f"🎨 {name}...", end=" ")
        img = Image.open(src).convert("RGBA")
        fixed, pct = remove_background(img)
        fixed.save(fixed_dir / f"{name}.png", "PNG")
        print(f"bg={pct:.0f}%", end=" → ")

        # Step 2: Crop, resize, animate, assemble
        base = center_crop_resize(fixed, FRAME_SIZE)
        frames = gen_frames(base, num_frames, anim_type)
        strip = assemble_strip(frames)

        strip_path = strips_dir / f"{name}.png"
        strip.save(strip_path, "PNG")
        ensure_imageset(name, strip_path)

        print(f"✅ {FRAME_SIZE * num_frames}×{FRAME_SIZE}")
        success += 1

    print(f"\n🎉 {success}/{len(SPRITES)} done")


if __name__ == "__main__":
    main()
