#!/usr/bin/env python3
"""
Assemble single-frame key images into animated sprite strips.

V2: Upgraded from 6 frames to 12 frames with richer micro-transforms.
Inspired by Star-Office-UI pixel animation style and pixel-art-professional techniques.

For each state_emotion:
  1. Load the AI-generated key frame PNG
  2. Center-crop / resize to 64×64
  3. Generate 12 animation frames (10 for compacting) via combined micro-transforms
  4. Concatenate horizontally → sprite strip PNG (768×64 or 640×64)
  5. Save to Assets.xcassets/<name>.imageset/<name>.png
"""

import os, math, random
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow"])
    from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

try:
    from rembg import remove as rembg_remove
    HAS_REMBG = True
except ImportError:
    HAS_REMBG = False
    print("⚠️  rembg not installed — background removal disabled")

# ── Paths ──────────────────────────────────────────────────────────────
GEN_DIR = Path(__file__).parent / "gen"
ASSETS_DIR = Path(__file__).parent / "Rockpile" / "Assets.xcassets"
FRAME_SIZE = 64

# ── Sprite definitions ─────────────────────────────────────────────────
# name → (num_frames, animation_type)
SPRITES = {
    # idle: gentle breathing + squash/stretch
    "idle_neutral":       (12, "breathe"),
    "idle_happy":         (12, "breathe_bounce"),
    "idle_sad":           (12, "breathe_droop"),
    "idle_angry":         (12, "tremble"),
    # thinking: head tilt + thought pulse
    "thinking_neutral":   (12, "tilt"),
    "thinking_happy":     (12, "tilt_bounce"),
    # working: left-right sway + typing feel
    "working_neutral":    (12, "sway"),
    "working_happy":      (12, "sway_bounce"),
    "working_sad":        (12, "sway_droop"),
    # waiting: look around with anticipation
    "waiting_neutral":    (12, "look"),
    "waiting_sad":        (12, "look_droop"),
    # error: violent shake + flash
    "error_neutral":      (12, "tremble_hard"),
    "error_sad":          (12, "tremble"),
    # sleeping: slow breathe + gentle rock
    "sleeping_neutral":   (12, "sleep"),
    "sleeping_happy":     (12, "sleep_smile"),
    # compacting: spin + shrink pulse (10 frames)
    "compacting_neutral": (10, "rotate"),
    "compacting_happy":   (10, "rotate"),
}


def remove_background(img: Image.Image) -> Image.Image:
    """Remove background using rembg, with fallback to simple gray removal."""
    if HAS_REMBG:
        return rembg_remove(img)

    # Fallback: remove near-gray pixels (low saturation)
    img = img.convert("RGBA")
    data = img.getdata()
    new_data = []
    for r, g, b, a in data:
        max_c = max(r, g, b)
        min_c = min(r, g, b)
        saturation = (max_c - min_c) / max(max_c, 1)
        if saturation < 0.15 and a > 0:
            new_data.append((r, g, b, 0))  # Make transparent
        else:
            new_data.append((r, g, b, a))
    img.putdata(new_data)
    return img


def center_crop_resize(img: Image.Image, size: int) -> Image.Image:
    """Center-crop to square, then resize to size×size."""
    w, h = img.size
    s = min(w, h)
    left = (w - s) // 2
    top = (h - s) // 2
    cropped = img.crop((left, top, left + s, top + s))
    return cropped.resize((size, size), Image.NEAREST)


def apply_squash_stretch(img: Image.Image, t: float, amplitude: float = 0.03) -> Image.Image:
    """Apply squash & stretch: compress Y / expand X at bottom of bounce, expand Y / compress X at top."""
    factor = math.sin(t * 2 * math.pi) * amplitude
    sx = 1.0 - factor  # X gets wider when Y squashes
    sy = 1.0 + factor  # Y stretches when X narrows

    new_w = max(1, int(FRAME_SIZE * sx))
    new_h = max(1, int(FRAME_SIZE * sy))
    stretched = img.resize((new_w, new_h), Image.NEAREST)

    canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
    paste_x = (FRAME_SIZE - new_w) // 2
    paste_y = FRAME_SIZE - new_h  # anchor at bottom
    canvas.paste(stretched, (paste_x, paste_y), stretched)
    return canvas


def generate_frames(base: Image.Image, num_frames: int, anim_type: str) -> list:
    """Generate animation frames from a single base image with rich micro-transforms."""
    frames = []

    for i in range(num_frames):
        t = i / max(num_frames - 1, 1)  # 0.0 → 1.0
        frame = base.copy()

        if anim_type == "breathe":
            # Gentle up-down oscillation + subtle squash/stretch
            dy = round(math.sin(t * 2 * math.pi) * 1.5)
            frame = apply_squash_stretch(frame, t, 0.02)
            canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            canvas.paste(frame, (0, dy), frame)
            frame = canvas

        elif anim_type == "breathe_bounce":
            # Happy breathing: more pronounced bounce + slight sway
            dy = round(math.sin(t * 2 * math.pi) * 2.0)
            dx = round(math.sin(t * 4 * math.pi) * 0.8)
            frame = apply_squash_stretch(frame, t, 0.035)
            canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            canvas.paste(frame, (dx, dy), frame)
            frame = canvas

        elif anim_type == "breathe_droop":
            # Sad breathing: slower, mostly downward, slight tilt
            dy = round(math.sin(t * 2 * math.pi) * 1.0) + 1  # biased down
            angle = math.sin(t * 2 * math.pi) * 1.5  # subtle droop tilt
            frame = frame.rotate(angle, resample=Image.BICUBIC, expand=False,
                                 fillcolor=(0, 0, 0, 0))
            canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            canvas.paste(frame, (0, dy), frame)
            frame = canvas

        elif anim_type == "tilt":
            # Head tilt: rotate ±3 degrees + subtle vertical
            angle = math.sin(t * 2 * math.pi) * 3
            dy = round(math.sin(t * 4 * math.pi) * 0.5)
            frame = frame.rotate(angle, resample=Image.BICUBIC, expand=False,
                                 fillcolor=(0, 0, 0, 0))
            canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            canvas.paste(frame, (0, dy), frame)
            frame = canvas

        elif anim_type == "tilt_bounce":
            # Happy thinking: tilt + bounce
            angle = math.sin(t * 2 * math.pi) * 3
            dy = round(abs(math.sin(t * 4 * math.pi)) * -1.5)  # upward bounce
            frame = apply_squash_stretch(frame, t * 2, 0.02)
            frame = frame.rotate(angle, resample=Image.BICUBIC, expand=False,
                                 fillcolor=(0, 0, 0, 0))
            canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            canvas.paste(frame, (0, dy), frame)
            frame = canvas

        elif anim_type == "sway":
            # Left-right sway: ±2px horizontal shift + squash
            dx = round(math.sin(t * 2 * math.pi) * 2)
            dy = round(abs(math.sin(t * 2 * math.pi)) * -0.5)
            frame = apply_squash_stretch(frame, t, 0.015)
            canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            canvas.paste(frame, (dx, dy), frame)
            frame = canvas

        elif anim_type == "sway_bounce":
            # Happy working: more energetic sway
            dx = round(math.sin(t * 2 * math.pi) * 2.5)
            dy = round(abs(math.sin(t * 4 * math.pi)) * -1.0)
            frame = apply_squash_stretch(frame, t * 2, 0.025)
            canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            canvas.paste(frame, (dx, dy), frame)
            frame = canvas

        elif anim_type == "sway_droop":
            # Sad working: slower sway, slight downward lean
            dx = round(math.sin(t * 2 * math.pi) * 1.5)
            angle = math.sin(t * 2 * math.pi) * 1.5
            frame = frame.rotate(angle, resample=Image.BICUBIC, expand=False,
                                 fillcolor=(0, 0, 0, 0))
            canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            canvas.paste(frame, (dx, 1), frame)
            frame = canvas

        elif anim_type == "look":
            # Look left-right: shift + subtle head turn
            dx = round(math.sin(t * 2 * math.pi) * 2.5)
            angle = math.sin(t * 2 * math.pi) * 2
            frame = frame.rotate(angle, resample=Image.BICUBIC, expand=False,
                                 fillcolor=(0, 0, 0, 0))
            canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            canvas.paste(frame, (dx, 0), frame)
            frame = canvas

        elif anim_type == "look_droop":
            # Sad looking: slower, lower gaze
            dx = round(math.sin(t * 2 * math.pi) * 1.5)
            dy = 1  # head slightly down
            angle = math.sin(t * 2 * math.pi) * 1.5
            frame = frame.rotate(angle, resample=Image.BICUBIC, expand=False,
                                 fillcolor=(0, 0, 0, 0))
            canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            canvas.paste(frame, (dx, dy), frame)
            frame = canvas

        elif anim_type == "tremble":
            # Random shake: ±2px in both axes (12 frames = smoother shake)
            dx = round(math.sin(t * 6 * math.pi) * 2)
            dy = round(math.cos(t * 6 * math.pi) * 1)
            canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            canvas.paste(frame, (dx, dy), frame)
            frame = canvas

        elif anim_type == "tremble_hard":
            # Violent shake for error: ±3px + rotation
            dx = round(math.sin(t * 8 * math.pi) * 3)
            dy = round(math.cos(t * 8 * math.pi) * 2)
            angle = math.sin(t * 6 * math.pi) * 4
            frame = frame.rotate(angle, resample=Image.BICUBIC, expand=False,
                                 fillcolor=(0, 0, 0, 0))
            canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            canvas.paste(frame, (dx, dy), frame)
            frame = canvas

        elif anim_type == "sleep":
            # Very slow breathe + gentle rock
            dy = round(math.sin(t * 2 * math.pi) * 1.0)
            angle = math.sin(t * 2 * math.pi) * 1.0  # gentle rock
            frame = frame.rotate(angle, resample=Image.BICUBIC, expand=False,
                                 fillcolor=(0, 0, 0, 0))
            canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            canvas.paste(frame, (0, dy), frame)
            frame = canvas

        elif anim_type == "sleep_smile":
            # Happy sleeping: same as sleep but with brighter colors
            dy = round(math.sin(t * 2 * math.pi) * 1.0)
            angle = math.sin(t * 2 * math.pi) * 1.0
            frame = frame.rotate(angle, resample=Image.BICUBIC, expand=False,
                                 fillcolor=(0, 0, 0, 0))
            canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            canvas.paste(frame, (0, dy), frame)
            frame = canvas

        elif anim_type == "rotate":
            # Rotation for compacting: 36° per frame (10 frames = 360°)
            angle = -t * 360  # Full rotation
            # Add scale pulse: slightly shrink/grow during spin
            scale_factor = 1.0 + math.sin(t * 4 * math.pi) * 0.05
            new_size = max(1, int(FRAME_SIZE * scale_factor))
            frame = frame.resize((new_size, new_size), Image.NEAREST)
            frame = frame.rotate(angle, resample=Image.BICUBIC, expand=False,
                                 fillcolor=(0, 0, 0, 0))
            canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            paste_offset = (FRAME_SIZE - new_size) // 2
            canvas.paste(frame, (paste_offset, paste_offset), frame)
            frame = canvas

        frames.append(frame)

    return frames


def assemble_strip(frames: list, frame_size: int = FRAME_SIZE) -> Image.Image:
    """Concatenate frames horizontally into a sprite strip."""
    n = len(frames)
    strip = Image.new("RGBA", (frame_size * n, frame_size), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        strip.paste(frame, (i * frame_size, 0), frame)
    return strip


def ensure_imageset(name: str, png_path: Path):
    """Create/update the .imageset directory with Contents.json."""
    imageset_dir = ASSETS_DIR / f"{name}.imageset"
    imageset_dir.mkdir(parents=True, exist_ok=True)

    contents_json = f'''{{\n  "images" : [\n    {{\n      "filename" : "{name}.png",\n      "idiom" : "universal",\n      "scale" : "1x"\n    }}\n  ],\n  "info" : {{\n    "author" : "xcode",\n    "version" : 1\n  }}\n}}'''

    (imageset_dir / "Contents.json").write_text(contents_json)
    import shutil
    shutil.copy2(png_path, imageset_dir / f"{name}.png")


def main():
    print(f"📂 Source: {GEN_DIR}")
    print(f"📦 Target: {ASSETS_DIR}")
    print()

    success = 0
    errors = []

    for name, (num_frames, anim_type) in SPRITES.items():
        src = GEN_DIR / f"{name}.png"
        if not src.exists():
            errors.append(f"❌ {name}: source not found at {src}")
            continue

        print(f"🎨 {name}: {num_frames} frames, {anim_type} animation...")

        # Load, remove background, then crop to 64×64
        img = Image.open(src).convert("RGBA")
        img = remove_background(img)
        base = center_crop_resize(img, FRAME_SIZE)

        # Generate animation frames
        frames = generate_frames(base, num_frames, anim_type)

        # Assemble into strip
        strip = assemble_strip(frames)
        strip_w = FRAME_SIZE * num_frames

        # Save strip to temp location
        out_dir = GEN_DIR / "strips"
        out_dir.mkdir(exist_ok=True)
        strip_path = out_dir / f"{name}.png"
        strip.save(strip_path, "PNG")

        # Deploy to Assets.xcassets
        ensure_imageset(name, strip_path)

        print(f"   ✅ {strip_w}×{FRAME_SIZE} strip → Assets.xcassets/{name}.imageset/")
        success += 1

    print()
    print(f"🎉 Done: {success}/{len(SPRITES)} sprite strips assembled")
    if errors:
        print("\n".join(errors))


if __name__ == "__main__":
    main()
