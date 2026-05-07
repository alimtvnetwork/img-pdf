#!/usr/bin/env python3
"""jpg2pdf — Combine images into a single PDF.

Two input modes:
  jpg2pdf <folder> [options]
  jpg2pdf --files f1 f2 ... [options]
  jpg2pdf --files-from list.txt [options]   # one path per line (UTF-8)

See spec/SPEC.md for the full specification.
"""
import argparse
import re
import sys
from pathlib import Path
from PIL import Image

__version__ = "0.2.0"

PAGE_SIZES = {  # points (1/72 inch)
    "a4":     (595.28, 841.89),
    "letter": (612.00, 792.00),
    "legal":  (612.00, 1008.00),
}
EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}


def natural_key(p: Path):
    return [int(t) if t.isdigit() else t.lower()
            for t in re.split(r"(\d+)", p.name)]


def collect_from_folder(folder: Path, recursive: bool):
    it = folder.rglob("*") if recursive else folder.iterdir()
    files = [p for p in it if p.is_file() and p.suffix.lower() in EXTS]
    files.sort(key=natural_key)
    return files


def collect_from_list(paths):
    """Preserve given order. Skip non-image / missing files with a warning."""
    out = []
    for raw in paths:
        p = Path(raw).expanduser().resolve()
        if not p.is_file():
            print(f"  skip (not a file): {p}", file=sys.stderr); continue
        if p.suffix.lower() not in EXTS:
            print(f"  skip (unsupported): {p}", file=sys.stderr); continue
        out.append(p)
    return out


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
        description="Combine images into a single PDF.")
    ap.add_argument("folder", nargs="?", default=None,
                    help="Folder of images (omit if using --files / --files-from)")
    ap.add_argument("--files", nargs="+", default=None,
                    help="Explicit list of image files (preserves order)")
    ap.add_argument("--files-from", default=None,
                    help="Text file with one image path per line (UTF-8)")
    ap.add_argument("--size", choices=list(PAGE_SIZES), default="a4")
    ap.add_argument("--orientation",
                    choices=["portrait", "landscape"], default="portrait")
    ap.add_argument("--fit",
                    choices=["contain", "cover", "stretch", "original"],
                    default="contain")
    ap.add_argument("--out", default=None, help="Output PDF path")
    ap.add_argument("--recursive", action="store_true",
                    help="Folder mode: include subfolders")
    args = ap.parse_args()

    # ---- Resolve input mode ----
    images = []
    default_out = None

    if args.files_from:
        listfile = Path(args.files_from).expanduser().resolve()
        if not listfile.is_file():
            print(f"List file not found: {listfile}", file=sys.stderr); sys.exit(1)
        lines = [ln.strip() for ln in listfile.read_text(encoding="utf-8").splitlines()
                 if ln.strip() and not ln.strip().startswith("#")]
        images = collect_from_list(lines)
        if images:
            default_out = images[0].parent / "images.pdf"
    elif args.files:
        images = collect_from_list(args.files)
        if images:
            default_out = images[0].parent / "images.pdf"
    elif args.folder:
        folder = Path(args.folder).expanduser().resolve()
        if not folder.is_dir():
            print(f"Not a folder: {folder}", file=sys.stderr); sys.exit(1)
        images = collect_from_folder(folder, args.recursive)
        default_out = folder / f"{folder.name}.pdf"
    else:
        ap.error("Provide a folder, or --files, or --files-from.")

    if not images:
        print("No images to convert.", file=sys.stderr); sys.exit(1)

    w, h = PAGE_SIZES[args.size]
    if args.orientation == "landscape":
        w, h = h, w

    out = Path(args.out).expanduser().resolve() if args.out else default_out

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
