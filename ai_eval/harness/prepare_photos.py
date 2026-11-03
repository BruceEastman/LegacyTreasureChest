"""Prepare private photos so they match what the iOS app sends, minus private metadata.

  python3 -I harness/prepare_photos.py private/inventory_v1/originals private/inventory_v1/photos

For each image (HEIC, JPEG, PNG, TIFF) in the input folder, writes <name>.jpg that is:
  - JPEG at quality 85 (the app uses UIImage.jpegData(compressionQuality: 0.85), no resizing)
  - rotated upright according to its EXIF orientation (as UIImage would render it)
  - stripped of EXIF (including GPS), XMP, IPTC and comments. The ICC color profile is kept.
Output file names come from the input names, so name originals with neutral ids (inv-01.heic).
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import jpeg_private_metadata, jpeg_segments  # noqa: E402

EXTS = {".heic", ".heif", ".jpg", ".jpeg", ".png", ".tif", ".tiff"}

# EXIF orientation -> sips operations (sips rotates clockwise).
ORIENT_OPS = {
    1: [], 2: [["-f", "horizontal"]], 3: [["-r", "180"]], 4: [["-f", "vertical"]],
    5: [["-r", "90"], ["-f", "horizontal"]], 6: [["-r", "90"]],
    7: [["-r", "270"], ["-f", "horizontal"]], 8: [["-r", "270"]],
}


def exif_orientation(data: bytes) -> int:
    for marker, start, end in jpeg_segments(data):
        payload = data[start + 4:end]
        if marker != 0xE1 or not payload.startswith(b"Exif\x00\x00"):
            continue
        tiff = payload[6:]
        order = "little" if tiff[:2] == b"II" else "big"
        ifd = int.from_bytes(tiff[4:8], order)
        count = int.from_bytes(tiff[ifd:ifd + 2], order)
        for i in range(count):
            e = ifd + 2 + i * 12
            if int.from_bytes(tiff[e:e + 2], order) == 0x0112:
                return int.from_bytes(tiff[e + 8:e + 10], order)
    return 1


def strip_metadata(data: bytes) -> bytes:
    """Drop APP1 (EXIF/XMP), APP3-APP13 and APP15, and COM segments. Keep APP0, APP2 (ICC), APP14 (Adobe)."""
    drop = {0xE1, 0xFE} | {m for m in range(0xE3, 0xF0) if m != 0xEE}
    segs = jpeg_segments(data)
    out = bytearray(b"\xff\xd8")
    for marker, start, end in segs:
        if marker == 0xDA:
            out += data[start:]
            break
        if marker not in drop:
            out += data[start:end]
    return bytes(out)


def sips(*args) -> None:
    subprocess.run(["sips", *args], check=True, capture_output=True)


def prepare_one(src: Path, out: Path, max_px: int | None = None) -> dict:
    """Write a metadata-free, upright JPEG (q85) of src to out. Never modifies src."""
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td) / "img.jpg"
        sips("-s", "format", "jpeg", "-s", "formatOptions", "85", str(src), "--out", str(tmp))
        orient = exif_orientation(tmp.read_bytes())
        for op in ORIENT_OPS.get(orient, []):
            sips(*op, str(tmp))
        if max_px:
            sips("-Z", str(max_px), str(tmp))
        clean = strip_metadata(tmp.read_bytes())
    left = jpeg_private_metadata(clean)
    if left:
        raise RuntimeError(f"{src.name}: metadata still present {left}")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(clean)
    dims = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(out)],
                          capture_output=True, text=True).stdout.split()
    return {"width": int(dims[-3]), "height": int(dims[-1]), "bytes": len(clean), "orientation": orient}


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    dst.mkdir(parents=True, exist_ok=True)
    files = sorted(p for p in src.iterdir() if p.suffix.lower() in EXTS)
    if not files:
        print(f"No images found in {src}")
        return 1
    for f in files:
        try:
            info = prepare_one(f, dst / f"{f.stem.lower()}.jpg")
        except RuntimeError as e:
            print(f"{e}; skipped")
            continue
        print(f"{f.name} -> {f.stem.lower()}.jpg  {info['width']}x{info['height']}  {info['bytes'] / 1024:.0f} KB  "
              f"(orientation {info['orientation']} applied, metadata stripped)")
    return 0


if __name__ == "__main__":
    shutil.which("sips") or sys.exit("sips not found (macOS only)")
    sys.exit(main())
