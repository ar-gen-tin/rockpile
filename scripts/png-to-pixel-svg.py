#!/usr/bin/env python3
"""
PNG → Pixel SVG 转换器
把每个非透明像素转成一个 SVG <rect>，100% 像素级保真。

用法:
  python3 scripts/png-to-pixel-svg.py                    # 转换全部 41 个精灵
  python3 scripts/png-to-pixel-svg.py idle_neutral        # 只转一个
"""

import os
import sys
import struct
import zlib
from pathlib import Path

ASSETS_DIR = Path("Rockpile/Assets.xcassets")
OUTPUT_DIR = Path("Rockpile/Resources/SVGSprites")
PIXEL_SCALE = 1  # 每个像素在 SVG 中的大小 (1=原始, 4=放大4倍)


def read_png(filepath):
    """Minimal PNG reader — returns (width, height, rows) where rows[y][x] = (r,g,b,a)"""
    with open(filepath, "rb") as f:
        sig = f.read(8)
        if sig != b'\x89PNG\r\n\x1a\n':
            raise ValueError(f"Not a PNG: {filepath}")

        chunks = []
        while True:
            length_bytes = f.read(4)
            if len(length_bytes) < 4:
                break
            length = struct.unpack(">I", length_bytes)[0]
            chunk_type = f.read(4)
            chunk_data = f.read(length)
            f.read(4)  # CRC
            chunks.append((chunk_type, chunk_data))

        # Parse IHDR
        ihdr = next(d for t, d in chunks if t == b'IHDR')
        width, height, bit_depth, color_type = struct.unpack(">IIBB", ihdr[:10])

        if bit_depth != 8 or color_type != 6:
            raise ValueError(f"Only 8-bit RGBA supported, got depth={bit_depth} type={color_type}")

        # Decompress IDAT
        idat_data = b''.join(d for t, d in chunks if t == b'IDAT')
        raw = zlib.decompress(idat_data)

        # Unfilter
        stride = width * 4
        rows = []
        prev_row = b'\x00' * stride
        offset = 0
        for y in range(height):
            filter_byte = raw[offset]
            offset += 1
            scanline = bytearray(raw[offset:offset + stride])
            offset += stride

            if filter_byte == 0:  # None
                pass
            elif filter_byte == 1:  # Sub
                for i in range(stride):
                    a = scanline[i - 4] if i >= 4 else 0
                    scanline[i] = (scanline[i] + a) & 0xFF
            elif filter_byte == 2:  # Up
                for i in range(stride):
                    scanline[i] = (scanline[i] + prev_row[i]) & 0xFF
            elif filter_byte == 3:  # Average
                for i in range(stride):
                    a = scanline[i - 4] if i >= 4 else 0
                    b = prev_row[i]
                    scanline[i] = (scanline[i] + (a + b) // 2) & 0xFF
            elif filter_byte == 4:  # Paeth
                for i in range(stride):
                    a = scanline[i - 4] if i >= 4 else 0
                    b = prev_row[i]
                    c = prev_row[i - 4] if i >= 4 else 0
                    p = a + b - c
                    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                    if pa <= pb and pa <= pc:
                        pr = a
                    elif pb <= pc:
                        pr = b
                    else:
                        pr = c
                    scanline[i] = (scanline[i] + pr) & 0xFF

            prev_row = bytes(scanline)
            row = []
            for x in range(width):
                idx = x * 4
                r, g, b, a = scanline[idx], scanline[idx+1], scanline[idx+2], scanline[idx+3]
                row.append((r, g, b, a))
            rows.append(row)

    return width, height, rows


def pixels_to_svg(width, height, rows, scale=1):
    """Convert pixel data to SVG string with grouped colors for compression."""
    # Group pixels by color
    color_pixels = {}
    for y, row in enumerate(rows):
        for x, (r, g, b, a) in enumerate(row):
            if a == 0:
                continue
            if a == 255:
                color = f"#{r:02x}{g:02x}{b:02x}"
            else:
                color = f"#{r:02x}{g:02x}{b:02x}{a:02x}"

            if color not in color_pixels:
                color_pixels[color] = []
            color_pixels[color].append((x, y))

    svg_w = width * scale
    svg_h = height * scale

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {svg_w} {svg_h}" width="{svg_w}" height="{svg_h}" shape-rendering="crispEdges">',
    ]

    for color, pixels in sorted(color_pixels.items(), key=lambda x: -len(x[1])):
        # Merge horizontal runs for compression
        runs = merge_runs(pixels, scale)
        if len(runs) == 1:
            x, y, w, h = runs[0]
            lines.append(f'  <rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{color}"/>')
        else:
            lines.append(f'  <g fill="{color}">')
            for x, y, w, h in runs:
                lines.append(f'    <rect x="{x}" y="{y}" width="{w}" height="{h}"/>')
            lines.append('  </g>')

    lines.append('</svg>')
    return '\n'.join(lines)


def merge_runs(pixels, scale):
    """Merge adjacent horizontal pixels into wider rects."""
    # Sort by y, then x
    pixels.sort(key=lambda p: (p[1], p[0]))

    runs = []
    i = 0
    while i < len(pixels):
        x0, y0 = pixels[i]
        # Extend horizontally
        run_len = 1
        while i + run_len < len(pixels):
            nx, ny = pixels[i + run_len]
            if ny == y0 and nx == x0 + run_len:
                run_len += 1
            else:
                break
        runs.append((x0 * scale, y0 * scale, run_len * scale, scale))
        i += run_len

    return runs


def convert_sprite(name, png_path, output_dir):
    """Convert a single sprite sheet PNG to SVG."""
    try:
        width, height, rows = read_png(png_path)
    except Exception as e:
        print(f"  ✗ {name}: {e}")
        return False

    svg = pixels_to_svg(width, height, rows, PIXEL_SCALE)

    output_dir.mkdir(parents=True, exist_ok=True)
    svg_path = output_dir / f"{name}.svg"
    svg_path.write_text(svg)

    png_size = os.path.getsize(png_path)
    svg_size = len(svg.encode())
    ratio = svg_size / png_size if png_size > 0 else 0

    print(f"  ✓ {name}: {width}×{height}px → {svg_size:,}B SVG (PNG was {png_size:,}B, ratio {ratio:.1f}x)")
    return True


def find_all_sprites():
    """Find all sprite imagesets in Assets.xcassets."""
    sprites = []
    for imageset in sorted(ASSETS_DIR.glob("*.imageset")):
        name = imageset.stem
        # Skip non-sprite assets
        if name in ("AppIcon",):
            continue
        png = next(imageset.glob("*.png"), None)
        if png:
            sprites.append((name, str(png)))
    return sprites


def main():
    filter_name = sys.argv[1] if len(sys.argv) > 1 else None

    sprites = find_all_sprites()
    if filter_name:
        sprites = [(n, p) for n, p in sprites if filter_name in n]

    if not sprites:
        print("No sprites found.")
        return

    print(f"Converting {len(sprites)} sprites → SVG (pixel-perfect)")
    print(f"Output: {OUTPUT_DIR}/")
    print()

    ok = 0
    fail = 0
    for name, png_path in sprites:
        if convert_sprite(name, png_path, OUTPUT_DIR):
            ok += 1
        else:
            fail += 1

    print(f"\n{'='*50}")
    print(f"Done: {ok} converted, {fail} failed")
    if ok > 0:
        total_size = sum(f.stat().st_size for f in OUTPUT_DIR.glob("*.svg"))
        print(f"Total SVG size: {total_size:,} bytes ({total_size/1024:.0f} KB)")


if __name__ == "__main__":
    main()
