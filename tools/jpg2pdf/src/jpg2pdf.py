#!/usr/bin/env python3
"""jpg2pdf — Combine all images in a folder into one PDF. See spec/SPEC.md."""
import argparse
import re
import sys
from pathlib import Path
from PIL import Image

PAGE_SIZES = {  # points (1/72 inch)
    "a4":     (595.28, 841.89),
    "letter": (612.00, 792.00),
    "legal":  (612.00, 1008.00),
}
EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}


def natural_key(p: Path):
    return [int(t) if t.isdigit() else t.lower()
            for t in re.split(r"(\d+)", p.name)]


def collect_images(folder: Path, recursive: bool):
    it = folder.rglob("*") if recursive else folder.iterdir()
    files = [p for p in it if p.is_file() and p.suffix.lower() in EXTS]
    files.sort(key=natural_key)
    return files


def make_page(img_path: Path, page_w: float, page_h: float, fit: str) -> Image.Image:
    page = Image.new("RGB", (int(page_w), int(page_h)), "white")
    with Image.open(img_path) as im:
        im = im.convert("RGB")
        iw, ih = im.size
        if fit == "original":
            new_w, new_h = iw, ih
        elif fit == "stretch":
            new_w, new_h = int(page_w), int(page_h)
        elif fit == "cover":
            s = max(page_w / iw, page_h / ih)
            new_w, new_h = int(iw * s), int(ih * s)
        else:  # contain
            s = min(page_w / iw, page_h / ih)
            new_w, new_h = int(iw * s), int(ih * s)
        if (new_w, new_h) != (iw, ih):
            im = im.resize((new_w, new_h), Image.LANCZOS)
        x = (int(page_w) - new_w) // 2
        y = (int(page_h) - new_h) // 2
        page.paste(im, (x, y))
    return page


def main():
    ap = argparse.ArgumentParser(
        description="Combine all images in a folder into a single PDF.")
    ap.add_argument("folder", nargs="?", default=".",
                    help="Folder of images (default: current)")
    ap.add_argument("--size", choices=list(PAGE_SIZES), default="a4")
    ap.add_argument("--orientation",
                    choices=["portrait", "landscape"], default="portrait")
    ap.add_argument("--fit",
                    choices=["contain", "cover", "stretch", "original"],
                    default="contain")
    ap.add_argument("--out", default=None,
                    help="Output PDF (default: <folder>.pdf)")
    ap.add_argument("--recursive", action="store_true",
                    help="Include subfolders")
    args = ap.parse_args()

    folder = Path(args.folder).expanduser().resolve()
    if not folder.is_dir():
        print(f"Not a folder: {folder}", file=sys.stderr); sys.exit(1)

    images = collect_images(folder, args.recursive)
    if not images:
        print(f"No images found in {folder}", file=sys.stderr); sys.exit(1)

    w, h = PAGE_SIZES[args.size]
    if args.orientation == "landscape":
        w, h = h, w

    out = Path(args.out).resolve() if args.out else (folder / f"{folder.name}.pdf")

    print(f"Folder:  {folder}")
    print(f"Files:   {len(images)}")
    print(f"Page:    {args.size} {args.orientation} ({int(w)}x{int(h)} pt)")
    print(f"Fit:     {args.fit}")
    print(f"Output:  {out}")

    pages = []
    for i, p in enumerate(images, 1):
        print(f"  [{i}/{len(images)}] {p.name}")
        pages.append(make_page(p, w, h, args.fit))

    pages[0].save(out, "PDF", resolution=72.0,
                  save_all=True, append_images=pages[1:])
    print(f"Done -> {out}")


if __name__ == "__main__":
    main()
