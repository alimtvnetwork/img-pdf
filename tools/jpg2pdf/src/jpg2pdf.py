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
from PIL import Image, ImageEnhance

__version__ = "0.5.0"

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


def apply_pencil(im: Image.Image, opacity: float, brightness: float,
                 ink_threshold: int = 90, ink_darken: float = 0.65) -> Image.Image:
    """Make the image look like pencil writing on paper.

    Two-zone level remap (per channel) so text stays readable:
      * Dark pixels (<= ink_threshold)  -> kept (or slightly darkened) so writing is bold.
      * Lighter pixels (> ink_threshold) -> pushed toward white by (1 - opacity)
        so paper / background / mid-tones fade out.

    opacity:    how much of the *non-ink* pixels survives (0..1).
                Lower = more washed out paper. Default 0.4 keeps faint shading.
    brightness: post-process multiplier on the whole image (default 1.0 = none).
    """
    opacity       = max(0.0, min(1.0, opacity))
    brightness    = max(0.1, brightness)
    ink_threshold = max(0, min(255, ink_threshold))
    ink_darken    = max(0.1, min(1.0, ink_darken))

    fade = 1.0 - opacity  # how strongly non-ink pixels are pulled toward white
    lut_single = []
    for v in range(256):
        if v <= ink_threshold:
            # Keep ink — and darken a touch so it reads as "more black".
            lut_single.append(max(0, int(round(v * ink_darken))))
        else:
            # Push toward white: out = 255 - (255 - v) * (1 - fade)
            lut_single.append(int(round(255 - (255 - v) * (1.0 - fade))))

    im = im.convert("RGB")
    im = im.point(lut_single * 3)  # apply same LUT to R, G, B
    if brightness != 1.0:
        im = ImageEnhance.Brightness(im).enhance(brightness)
    return im


def make_page(img_path: Path, page_w_pt: float, page_h_pt: float,
              fit: str, dpi: int, auto_rotate: str, rotate: int,
              style: str = "none",
              pencil_opacity: float = 0.25,
              pencil_brightness: float = 1.0,
              pencil_ink_threshold: int = 90,
              pencil_ink_darken: float = 0.65) -> Image.Image:
    """Render one PDF page at `dpi` DPI.

    rotate:      extra rotation applied to every image (0/90/180/270, CCW).
    auto_rotate: 'cw'  -> rotate landscape images 90° clockwise to fit portrait page
                 'ccw' -> rotate 90° counter-clockwise
                 'off' -> never auto-rotate
    style:       'none' (default) or 'pencil' (text/dark strokes stay black,
                 paper & mid-tones fade out).
    """
    with Image.open(img_path) as im:
        im = im.convert("RGB")

        if rotate:
            im = im.rotate(rotate, expand=True)

        iw, ih = im.size
        if auto_rotate != "off":
            img_landscape  = iw > ih
            page_landscape = page_w_pt > page_h_pt
            if img_landscape != page_landscape:
                # PIL rotates CCW with positive angle.
                angle = 90 if auto_rotate == "ccw" else -90
                im = im.rotate(angle, expand=True)
                iw, ih = im.size

        if style == "pencil":
            im = apply_pencil(im, pencil_opacity, pencil_brightness,
                              ink_threshold=pencil_ink_threshold,
                              ink_darken=pencil_ink_darken)

        scale = dpi / 72.0
        canvas_w = max(1, int(round(page_w_pt * scale)))
        canvas_h = max(1, int(round(page_h_pt * scale)))

        if fit == "original":
            new_w, new_h = iw, ih
        elif fit == "stretch":
            new_w, new_h = canvas_w, canvas_h
        elif fit == "cover":
            s = max(canvas_w / iw, canvas_h / ih)
            new_w, new_h = int(round(iw * s)), int(round(ih * s))
        else:  # contain
            s = min(canvas_w / iw, canvas_h / ih)
            new_w, new_h = int(round(iw * s)), int(round(ih * s))

        if (new_w, new_h) != (iw, ih):
            im = im.resize((new_w, new_h), Image.LANCZOS)

        page = Image.new("RGB", (canvas_w, canvas_h), "white")
        x = (canvas_w - new_w) // 2
        y = (canvas_h - new_h) // 2
        page.paste(im, (x, y))
        return page


def main():
    ap = argparse.ArgumentParser(
        description="Combine images into a single PDF.")
    ap.add_argument("--version", action="version",
                    version=f"jpg2pdf {__version__}")
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
    ap.add_argument("--dpi", type=int, default=300,
                    help="Render DPI for embedded raster (default: 300)")
    ap.add_argument("--rotate", type=int, choices=[0, 90, 180, 270], default=0,
                    help="Rotate every image by N degrees CCW before fitting")
    ap.add_argument("--auto-rotate", choices=["cw", "ccw", "off"], default="cw",
                    help="Auto-rotate landscape images to fit portrait page "
                         "(cw = clockwise, default; ccw = counter-clockwise; off)")
    ap.add_argument("--no-auto-rotate", action="store_true",
                    help="Shortcut for --auto-rotate off")
    ap.add_argument("--style", choices=["none", "pencil"], default="none",
                    help="Rendering style. 'pencil' = pencil-on-paper look "
                         "(text/dark strokes stay black, paper & mid-tones fade out)")
    ap.add_argument("--pencil-opacity", type=float, default=0.25,
                    help="Pencil style: how much non-ink survives (0..1, default 0.25). "
                         "Lower = whiter paper.")
    ap.add_argument("--pencil-ink-threshold", type=int, default=90,
                    help="Pencil style: pixel value (0..255) below which a pixel is "
                         "treated as ink and kept dark (default 90).")
    ap.add_argument("--pencil-ink-darken", type=float, default=0.65,
                    help="Pencil style: ink multiplier (<1 makes ink blacker, default 0.65).")
    ap.add_argument("--pencil-brightness", type=float, default=1.0,
                    help="Pencil style: post-process brightness multiplier (default 1.0).")
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

    auto_rot = "off" if args.no_auto_rotate else args.auto_rotate

    print(f"Files:    {len(images)}")
    print(f"Page:     {args.size} {args.orientation} ({int(w)}x{int(h)} pt) @ {args.dpi} DPI")
    print(f"Fit:      {args.fit}  rotate: {args.rotate}  auto-rotate: {auto_rot}")
    if args.style == "pencil":
        print(f"Style:    pencil (opacity={args.pencil_opacity}, "
              f"ink<= {args.pencil_ink_threshold} *{args.pencil_ink_darken}, "
              f"brightness={args.pencil_brightness})")
    print(f"Output:   {out}")

    pages = []
    for i, p in enumerate(images, 1):
        print(f"  [{i}/{len(images)}] {p.name}")
        pages.append(make_page(p, w, h, args.fit, args.dpi,
                               auto_rotate=auto_rot, rotate=args.rotate,
                               style=args.style,
                               pencil_opacity=args.pencil_opacity,
                               pencil_brightness=args.pencil_brightness,
                               pencil_ink_threshold=args.pencil_ink_threshold,
                               pencil_ink_darken=args.pencil_ink_darken))

    pages[0].save(out, "PDF", resolution=float(args.dpi),
                  save_all=True, append_images=pages[1:])
    print(f"Done -> {out}")


if __name__ == "__main__":
    main()
