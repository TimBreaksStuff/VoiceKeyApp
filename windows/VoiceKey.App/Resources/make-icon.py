#!/usr/bin/env python3
"""Generates Resources/VoiceKey.ico from the keycap glyph geometry.

The glyph is four rectangles in an 18-unit box — the same spec TrayGlyph.cs
draws from — so the app icon is generated rather than hand-drawn, and stays in
step with the tray icon if the geometry ever changes. Run it after editing the
numbers below; the .ico it writes is committed.
"""

import struct
from pathlib import Path

BOX = 18.0
INK = (0x21, 0x1D, 0x1A)
SIZES = (256, 64, 48, 32, 16)
SUPERSAMPLE = 4

KEY = (1.3, 1.3, 15.4, 15.4)   # x, y, w, h of the keycap
KEY_RADIUS = 4.0
KEY_STROKE = 1.6
RULES = ((4.5, 6.9, 9.0, 1.4), (6.0, 10.3, 6.0, 1.4))


def rounded_rect_distance(px, py, rect, radius):
    """Signed distance to a rounded rectangle: negative inside, positive outside."""
    x, y, w, h = rect
    dx = abs(px - (x + w / 2)) - (w / 2 - radius)
    dy = abs(py - (y + h / 2)) - (h / 2 - radius)
    outside = (max(dx, 0.0) ** 2 + max(dy, 0.0) ** 2) ** 0.5
    return outside + min(max(dx, dy), 0.0) - radius


def covers(px, py):
    if abs(rounded_rect_distance(px, py, KEY, KEY_RADIUS)) <= KEY_STROKE / 2:
        return True
    return any(x <= px <= x + w and y <= py <= y + h for x, y, w, h in RULES)


def render(size):
    """One size, as bottom-up BGRA rows — the layout an ICO's bitmap wants."""
    step = BOX / (size * SUPERSAMPLE)
    rows = []
    for row in range(size - 1, -1, -1):
        pixels = bytearray()
        for column in range(size):
            hits = sum(
                covers((column * SUPERSAMPLE + sx + 0.5) * step,
                       (row * SUPERSAMPLE + sy + 0.5) * step)
                for sy in range(SUPERSAMPLE)
                for sx in range(SUPERSAMPLE)
            )
            alpha = round(255 * hits / SUPERSAMPLE ** 2)
            pixels += bytes((INK[2], INK[1], INK[0], alpha))
        rows.append(bytes(pixels))
    return b"".join(rows)


def bitmap(size):
    """BITMAPINFOHEADER + BGRA pixels + the (unused, all-zero) AND mask."""
    header = struct.pack("<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, size * size * 4,
                         0, 0, 0, 0)
    mask_stride = ((size + 31) // 32) * 4
    return header + render(size) + bytes(mask_stride * size)


def main():
    images = [bitmap(size) for size in SIZES]
    offset = 6 + 16 * len(images)
    directory = b""
    for size, image in zip(SIZES, images):
        directory += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32,
                                 len(image), offset)
        offset += len(image)

    target = Path(__file__).with_name("VoiceKey.ico")
    target.write_bytes(struct.pack("<HHH", 0, 1, len(images)) + directory + b"".join(images))
    print(f"wrote {target} ({target.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
