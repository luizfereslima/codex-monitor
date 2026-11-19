"""Gera o ícone do app macOS com Pillow e iconutil."""

from pathlib import Path
import subprocess
import tempfile

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
SIZE = 1024


def main():
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pixels = image.load()
    for y in range(SIZE):
        for x in range(SIZE):
            pixels[x, y] = (23, 25 + y // 128, 44 + y // 64, 255)

    mask = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((48, 48, 976, 976), radius=218, fill=255)
    image.putalpha(mask)

    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((52, 52, 972, 972), radius=214, outline=(90, 115, 169, 255), width=18)
    draw.rounded_rectangle((178, 710, 294, 846), radius=28, fill=(107, 222, 190, 255))
    draw.rounded_rectangle((338, 620, 454, 846), radius=28, fill=(107, 222, 190, 255))
    draw.rounded_rectangle((498, 530, 614, 846), radius=28, fill=(107, 222, 190, 255))
    draw.rounded_rectangle((658, 440, 774, 846), radius=28, fill=(107, 222, 190, 255))
    draw.polygon(
        [(555, 140), (290, 510), (474, 510), (424, 678), (740, 286), (554, 286)],
        fill=(155, 199, 255, 255),
    )

    image.save(ROOT / "CodexPulse.png")
    with tempfile.TemporaryDirectory() as directory:
        iconset = Path(directory) / "CodexPulse.iconset"
        iconset.mkdir()
        for points in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                pixels = points * scale
                resized = image.resize((pixels, pixels), Image.Resampling.LANCZOS)
                suffix = "@2x" if scale == 2 else ""
                resized.save(iconset / f"icon_{points}x{points}{suffix}.png")
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ROOT / "CodexPulse.icns")], check=True)


if __name__ == "__main__":
    main()
