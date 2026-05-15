#!/usr/bin/env python3
"""jpg2pdf — Combine images into a single PDF.

Two input modes:
  jpg2pdf <folder> [options]
  jpg2pdf --files f1 f2 ... [options]
  jpg2pdf --files-from list.txt [options]   # one path per line (UTF-8)

See spec/SPEC.md for the full specification.
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageEnhance, ImageFilter, ImageOps

__version__ = "1.3.5"

# Pencil presets — tuned for faint handwritten text.
# Module-scope so prompt_pencil_strength() can render the live preview with
# the same numbers main() will use for the real conversion.
PENCIL_PRESETS = {
    "subtle": dict(opacity=0.32, ink_threshold=105, ink_darken=0.52, brightness=1.0),
    "normal": dict(opacity=0.20, ink_threshold=128, ink_darken=0.32, brightness=1.0),
    "extra":  dict(opacity=0.10, ink_threshold=165, ink_darken=0.12, brightness=1.02),
}

# ---- Persistent user prefs (last chosen pencil strength, etc.) ----
# Honors $JPG2PDF_CONFIG_DIR for tests / portable installs.
CONFIG_DIR  = Path(os.environ.get("JPG2PDF_CONFIG_DIR",
                                  str(Path.home() / ".jpg2pdf")))
CONFIG_PATH = CONFIG_DIR / "config.json"


def load_prefs() -> dict:
    try:
        return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except Exception:
        return {}


def save_prefs(prefs: dict) -> None:
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        CONFIG_PATH.write_text(json.dumps(prefs, indent=2), encoding="utf-8")
    except Exception as e:
        print(f"  (warning: could not save prefs: {e})", file=sys.stderr)


# ---- Output filename patterns ----
# Available placeholders for --name-pattern (case-insensitive):
#   {folder}    parent folder name (or input folder for folder-mode)
#   {first}     base name of the first input image (no extension)
#   {count}     number of images included
#   {style}     "none" or "pencil"
#   {strength}  pencil strength preset name when --style pencil, else ""
#   {date}      YYYY-MM-DD (local time)
#   {time}      HHMMSS (local time, no separators — filesystem-safe)
#   {datetime}  YYYY-MM-DD_HHMMSS
#   {y} {m} {d} {hh} {mm} {ss}   individual zero-padded parts
NAME_PATTERN_TOKENS = (
    "folder", "first", "count", "style", "strength",
    "date", "time", "datetime", "y", "m", "d", "hh", "mm", "ss",
)
DEFAULT_NAME_PATTERN = "{folder}"

_INVALID_FS_CHARS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


def _sanitize_filename(name: str) -> str:
    cleaned = _INVALID_FS_CHARS.sub("_", name).strip(" .")
    return cleaned or "images"


def format_pdf_name(pattern: str, *, folder_name: str, first_image: Path,
                    count: int, style: str, strength: str) -> str:
    """Render the user's name pattern into a safe filename (no extension)."""
    import datetime as _dt
    now = _dt.datetime.now()
    values = {
        "folder":   folder_name,
        "first":    first_image.stem,
        "count":    str(count),
        "style":    style,
        "strength": strength if style == "pencil" else "",
        "date":     now.strftime("%Y-%m-%d"),
        "time":     now.strftime("%H%M%S"),
        "datetime": now.strftime("%Y-%m-%d_%H%M%S"),
        "y":  now.strftime("%Y"), "m":  now.strftime("%m"), "d":  now.strftime("%d"),
        "hh": now.strftime("%H"), "mm": now.strftime("%M"), "ss": now.strftime("%S"),
    }
    try:
        rendered = pattern.format(**values)
    except (KeyError, IndexError, ValueError) as e:
        print(f"  (warning: bad --name-pattern {pattern!r}: {e}; "
              f"falling back to '{DEFAULT_NAME_PATTERN}')", file=sys.stderr)
        rendered = DEFAULT_NAME_PATTERN.format(**values)
    # Collapse leftover empty pieces (e.g. "{strength}" when style=none)
    rendered = re.sub(r"_{2,}", "_", rendered).strip("_- ")
    return _sanitize_filename(rendered)



def prompt_pencil_strength(default: str = "subtle", sample_path=None) -> str:
    """Show a Tk dropdown to pick pencil strength, with a LIVE preview.

    When `sample_path` points to a real image, a thumbnail of that image is
    rendered with each preset on the fly — switching the dropdown immediately
    re-renders the preview so the user can pick the strength that makes
    faint text most readable before any PDF is written.

    Returns the chosen value ('subtle' | 'normal' | 'extra'), or `default`
    if Tk is unavailable or the user cancels.
    """
    try:
        import tkinter as tk
        from tkinter import ttk
    except Exception:
        return default

    # ImageTk is part of Pillow's tk extras — gracefully degrade without it.
    try:
        from PIL import ImageTk
        has_imagetk = True
    except Exception:
        ImageTk = None
        has_imagetk = False

    choices = ["subtle", "normal", "extra"]
    descriptions = {
        "subtle": "Subtle  — gentle, keeps paper texture (default)",
        "normal": "Normal  — balanced ink + paper grain",
        "extra":  "Extra visible — aggressive darkening for very faint pencil",
    }
    result = {"value": default}

    try:
        root = tk.Tk()
    except Exception:
        return default

    root.title("jpg2pdf — Pencil strength")
    try:
        root.attributes("-topmost", True)
    except Exception:
        pass
    root.resizable(False, False)

    frm = ttk.Frame(root, padding=16)
    frm.grid(row=0, column=0, sticky="nsew")
    ttk.Label(frm, text="Choose pencil rendering strength:").grid(
        row=0, column=0, columnspan=2, sticky="w", pady=(0, 8))

    var = tk.StringVar(value=descriptions.get(default, descriptions["normal"]))
    combo = ttk.Combobox(frm, textvariable=var, state="readonly",
                         values=[descriptions[c] for c in choices], width=46)
    combo.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(0, 12))

    # ---- Live preview ----
    preview_thumb = None     # base RGB thumbnail (PIL Image), small for speed
    preview_label = None
    photo_ref = {"img": None}   # keep PhotoImage reference alive

    if sample_path is not None and has_imagetk:
        try:
            with Image.open(sample_path) as raw:
                base = raw.convert("RGB")
                base.thumbnail((520, 520), Image.LANCZOS)
                preview_thumb = base.copy()
        except Exception:
            preview_thumb = None

    if preview_thumb is not None:
        ttk.Label(frm, text="Live preview (faint text gets clearer →):").grid(
            row=2, column=0, columnspan=2, sticky="w", pady=(4, 4))
        preview_label = ttk.Label(frm, relief="solid", borderwidth=1)
        preview_label.grid(row=3, column=0, columnspan=2, pady=(0, 12))
    elif sample_path is not None:
        ttk.Label(frm,
                  text="(Install Pillow's Tk extras for a live preview)",
                  foreground="#888").grid(row=2, column=0, columnspan=2,
                                          sticky="w", pady=(0, 8))

    def _selected_key():
        sel = var.get()
        for c in choices:
            if descriptions[c] == sel:
                return c
        return default

    def _render_preview(*_):
        if preview_thumb is None or preview_label is None:
            return
        key = _selected_key()
        p = PENCIL_PRESETS[key]
        try:
            rendered = apply_pencil(
                preview_thumb,
                opacity=p["opacity"],
                brightness=p["brightness"],
                ink_threshold=p["ink_threshold"],
                ink_darken=p["ink_darken"],
            )
        except Exception:
            return
        photo_ref["img"] = ImageTk.PhotoImage(rendered)
        preview_label.configure(image=photo_ref["img"])

    combo.bind("<<ComboboxSelected>>", _render_preview)
    _render_preview()  # initial render for `default`

    def _ok(_evt=None):
        result["value"] = _selected_key()
        root.destroy()

    def _cancel(_evt=None):
        root.destroy()

    btns = ttk.Frame(frm)
    btns.grid(row=4, column=0, columnspan=2, sticky="e")
    ttk.Button(btns, text="Cancel", command=_cancel).grid(row=0, column=0, padx=(0, 6))
    ok_btn = ttk.Button(btns, text="Convert", command=_ok)
    ok_btn.grid(row=0, column=1)
    root.bind("<Return>", _ok)
    root.bind("<Escape>", _cancel)
    ok_btn.focus_set()

    # Center on screen
    root.update_idletasks()
    w = root.winfo_width(); h = root.winfo_height()
    sw = root.winfo_screenwidth(); sh = root.winfo_screenheight()
    root.geometry(f"+{(sw - w) // 2}+{max(20, (sh - h) // 4)}")

    root.mainloop()
    return result["value"]


def prompt_thumbnail_grid(images, thumb_px: int = 140, cols: int = 4):
    """Show a scrollable Tk grid of thumbnails so the user can confirm /
    deselect images before the PDF is built.

    Returns: a (filtered, original-order) list of Paths to actually convert,
    or None if the user cancelled. If Tk or Pillow's ImageTk isn't available,
    returns the input unchanged so conversion proceeds without an interactive
    step.
    """
    try:
        import tkinter as tk
        from tkinter import ttk
    except Exception:
        return list(images)
    try:
        from PIL import ImageTk
    except Exception:
        return list(images)
    try:
        root = tk.Tk()
    except Exception:
        return list(images)

    root.title(f"jpg2pdf — confirm {len(images)} image(s)")
    try:
        root.attributes("-topmost", True)
    except Exception:
        pass

    state = {"result": None}
    vars_ = []  # list of (Path, BooleanVar)

    header = ttk.Frame(root, padding=(12, 10, 12, 6))
    header.grid(row=0, column=0, sticky="ew")
    counter = ttk.Label(header, text="")
    counter.grid(row=0, column=0, sticky="w")

    def _refresh_counter(*_):
        n = sum(1 for _, v in vars_ if v.get())
        counter.configure(text=f"{n} of {len(vars_)} selected")

    def _select_all():
        for _, v in vars_: v.set(True)
        _refresh_counter()

    def _select_none():
        for _, v in vars_: v.set(False)
        _refresh_counter()

    ttk.Button(header, text="All",  command=_select_all ).grid(row=0, column=1, padx=(12, 4))
    ttk.Button(header, text="None", command=_select_none).grid(row=0, column=2)
    header.columnconfigure(0, weight=1)

    body = ttk.Frame(root, padding=(8, 4, 8, 4))
    body.grid(row=1, column=0, sticky="nsew")
    root.columnconfigure(0, weight=1)
    root.rowconfigure(1, weight=1)

    rows = max(1, (len(images) + cols - 1) // cols)
    canvas = tk.Canvas(body, highlightthickness=0,
                       width=cols * (thumb_px + 24) + 20,
                       height=min(3, rows) * (thumb_px + 60) + 20)
    vbar = ttk.Scrollbar(body, orient="vertical", command=canvas.yview)
    canvas.configure(yscrollcommand=vbar.set)
    canvas.grid(row=0, column=0, sticky="nsew")
    vbar.grid(row=0, column=1, sticky="ns")
    body.columnconfigure(0, weight=1)
    body.rowconfigure(0, weight=1)

    inner = ttk.Frame(canvas)
    canvas.create_window((0, 0), window=inner, anchor="nw")
    inner.bind("<Configure>",
               lambda _e: canvas.configure(scrollregion=canvas.bbox("all")))
    canvas.bind_all("<MouseWheel>",
                    lambda e: canvas.yview_scroll(-1 if e.delta > 0 else 1, "units"))

    photos = []  # keep PhotoImage references alive
    for idx, p in enumerate(images):
        cell = ttk.Frame(inner, padding=6, relief="solid", borderwidth=1)
        cell.grid(row=idx // cols, column=idx % cols, padx=4, pady=4, sticky="n")
        kind = kind_of(p)
        photo = None
        if kind == "image":
            try:
                with Image.open(p) as im:
                    im = im.convert("RGB")
                    im.thumbnail((thumb_px, thumb_px), Image.LANCZOS)
                    photo = ImageTk.PhotoImage(im)
            except Exception:
                photo = None
        photos.append(photo)
        if photo is not None:
            ttk.Label(cell, image=photo).grid(row=0, column=0)
        else:
            badge = {"pdf": "PDF", "html": "HTML",
                     "word": "DOC", "image": "(unreadable)"}.get(kind, "FILE")
            ttk.Label(cell, text=badge, width=18,
                      anchor="center").grid(row=0, column=0, ipady=thumb_px // 3)
        var = tk.BooleanVar(value=True)
        vars_.append((p, var))
        name = p.name if len(p.name) <= 22 else p.name[:19] + "…"
        ttk.Checkbutton(cell, text=name, variable=var,
                        command=_refresh_counter).grid(row=1, column=0, sticky="w")

    _refresh_counter()

    footer = ttk.Frame(root, padding=(12, 6, 12, 12))
    footer.grid(row=2, column=0, sticky="ew")
    footer.columnconfigure(0, weight=1)

    def _ok():
        state["result"] = [p for p, v in vars_ if v.get()]
        root.destroy()

    def _cancel():
        state["result"] = None
        root.destroy()

    ttk.Button(footer, text="Cancel",  command=_cancel).grid(row=0, column=1, padx=(0, 6))
    ok_btn = ttk.Button(footer, text="Convert", command=_ok)
    ok_btn.grid(row=0, column=2)
    root.bind("<Return>", lambda _e: _ok())
    root.bind("<Escape>", lambda _e: _cancel())
    ok_btn.focus_set()

    root.update_idletasks()
    w = min(root.winfo_reqwidth(),  root.winfo_screenwidth()  - 80)
    h = min(root.winfo_reqheight(), root.winfo_screenheight() - 120)
    sw = root.winfo_screenwidth(); sh = root.winfo_screenheight()
    root.geometry(f"{w}x{h}+{(sw - w) // 2}+{max(20, (sh - h) // 5)}")

    root.mainloop()
    return state["result"]


PAGE_SIZES = {  # points (1/72 inch)
    "a4":     (595.28, 841.89),
    "letter": (612.00, 792.00),
    "legal":  (612.00, 1008.00),
}
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}
PDF_EXTS   = {".pdf"}
HTML_EXTS  = {".html", ".htm"}
WORD_EXTS  = {".docx", ".doc"}
SUPPORTED_EXTS = IMAGE_EXTS | PDF_EXTS | HTML_EXTS | WORD_EXTS
# Backwards-compat alias (some older callers / tests imported EXTS).
EXTS = IMAGE_EXTS


def kind_of(p: Path) -> str:
    """Classify an input path: 'image' | 'pdf' | 'html' | 'word' | 'unknown'."""
    ext = p.suffix.lower()
    if ext in IMAGE_EXTS: return "image"
    if ext in PDF_EXTS:   return "pdf"
    if ext in HTML_EXTS:  return "html"
    if ext in WORD_EXTS:  return "word"
    return "unknown"


def natural_key(p: Path):
    return [int(t) if t.isdigit() else t.lower()
            for t in re.split(r"(\d+)", p.name)]


def collect_from_folder(folder: Path, recursive: bool):
    it = folder.rglob("*") if recursive else folder.iterdir()
    files = [p for p in it if p.is_file() and p.suffix.lower() in SUPPORTED_EXTS]
    files.sort(key=natural_key)
    return files


def collect_from_list(paths):
    """Preserve given order. Skip unsupported / missing files with a warning."""
    out = []
    for raw in paths:
        p = Path(raw).expanduser().resolve()
        if not p.is_file():
            print(f"  skip (not a file): {p}", file=sys.stderr); continue
        if p.suffix.lower() not in SUPPORTED_EXTS:
            print(f"  skip (unsupported): {p}", file=sys.stderr); continue
        out.append(p)
    return out


# ---------- Per-type → PDF converters ----------
# Each returns a Path to a PDF file (either a freshly-written temp file or
# the original input for already-PDF inputs). They never raise on missing
# optional deps — they print a warning and return None so the caller can skip.

def html_to_pdf(src: Path, out_pdf: Path) -> Path | None:
    try:
        from xhtml2pdf import pisa  # type: ignore
    except Exception as e:
        print(f"  skip {src.name}: HTML support needs xhtml2pdf ({e})",
              file=sys.stderr)
        return None
    try:
        html = src.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        print(f"  skip {src.name}: cannot read HTML ({e})", file=sys.stderr)
        return None
    with open(out_pdf, "wb") as f:
        result = pisa.CreatePDF(src=html, dest=f, encoding="utf-8")
    if result.err:
        print(f"  skip {src.name}: HTML→PDF failed ({result.err} error(s))",
              file=sys.stderr)
        return None
    return out_pdf


def word_to_pdf(src: Path, out_pdf: Path) -> Path | None:
    try:
        from docx2pdf import convert as _docx_convert  # type: ignore
    except Exception as e:
        print(f"  skip {src.name}: Word support needs docx2pdf ({e})",
              file=sys.stderr)
        return None
    try:
        # docx2pdf needs a real installed Word (Win) / LibreOffice (mac).
        _docx_convert(str(src), str(out_pdf))
    except Exception as e:
        print(f"  skip {src.name}: Word→PDF failed ({e}). "
              "Install Microsoft Word (Windows) or LibreOffice.",
              file=sys.stderr)
        return None
    if not out_pdf.is_file():
        print(f"  skip {src.name}: Word→PDF produced no output", file=sys.stderr)
        return None
    return out_pdf


def images_to_pdf_chunk(image_paths, out_pdf: Path, *, page_w_pt, page_h_pt,
                        fit, dpi, auto_rotate, rotate, style,
                        pencil_opacity, pencil_brightness,
                        pencil_ink_threshold, pencil_ink_darken) -> Path | None:
    pages = []
    for p in image_paths:
        pages.append(make_page(p, page_w_pt, page_h_pt, fit, dpi,
                               auto_rotate=auto_rotate, rotate=rotate,
                               style=style,
                               pencil_opacity=pencil_opacity,
                               pencil_brightness=pencil_brightness,
                               pencil_ink_threshold=pencil_ink_threshold,
                               pencil_ink_darken=pencil_ink_darken))
    if not pages:
        return None
    pages[0].save(out_pdf, "PDF", resolution=float(dpi),
                  save_all=True, append_images=pages[1:])
    return out_pdf


def merge_pdfs(pdf_paths, out: Path) -> None:
    from pypdf import PdfWriter  # local import — heavy dep
    writer = PdfWriter()
    for p in pdf_paths:
        writer.append(str(p))
    with open(out, "wb") as f:
        writer.write(f)
    writer.close()


def apply_pencil(im: Image.Image, opacity: float, brightness: float,
                 ink_threshold: int = 110, ink_darken: float = 0.45) -> Image.Image:
    """Render the image as crisp pencil writing on clean paper.

    Pipeline:
      1. Flatten onto white (kill any alpha haze) and convert to grayscale
         using luminance — picks up colored ink/text as well as black.
      2. Auto-stretch the histogram (1% / 99%) so a slightly grey scan is
         pulled to true white-paper range before the LUT runs. This is the
         single biggest quality win versus a naive contrast curve.
      3. Unsharp-mask to recover stroke crispness (graphite edges) before
         we flatten tones.
      4. Smoothstep LUT: anything darker than `dark_point` is treated as
         pure ink (multiplied by `ink_darken` so it stays solid black),
         anything lighter than `light_point` snaps to paper white, and the
         band between them gets an anti-aliased ramp so small text edges
         don't break up.

    opacity:    how aggressive the paper-whitening is (0..1).
                Lower  → wider whitening band, cleaner page.
                Default 0.25 → light_point ≈ 215, dark_point ≈ 70.
    brightness: post brightness multiplier (1.0 = none).
    ink_threshold: pixel value (0..255) that defines "definitely ink".
                   Pixels at or below get the full ink_darken treatment.
    ink_darken: ink multiplier (<1 makes ink blacker; default 0.55).
    """
    opacity    = max(0.0, min(1.0, opacity))
    brightness = max(0.1, brightness)
    ink_darken = max(0.05, min(1.0, ink_darken))

    # 1. Flatten alpha → white, then luminance-grayscale.
    if im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info):
        bg = Image.new("RGB", im.size, (255, 255, 255))
        bg.paste(im.convert("RGBA"), mask=im.convert("RGBA").split()[-1])
        im = bg
    gray = im.convert("L")
    raw_gray = gray

    # 2a. Background flattening — divide by a heavily-blurred copy of the page
    # to remove uneven lighting / shadow gradients from phone photos. This is
    # the key trick that makes faint pencil pop: paper goes uniformly white,
    # so the LUT below has more room to darken the actual strokes.
    bg_blur = gray.filter(ImageFilter.GaussianBlur(radius=max(gray.size) / 30))
    from PIL import ImageMath
    _eval = getattr(ImageMath, "unsafe_eval", None) or ImageMath.eval
    # Avoid div-by-zero by lifting bg floor to 1 via point().
    bg_safe = bg_blur.point(lambda v: max(v, 1))
    gray = _eval(
        "convert(float(a) * 255.0 / float(b), 'L')",  # convert('L') saturates to 0..255
        a=gray, b=bg_safe,
    )

    # 2a.1 Stroke-lift mask — recover very faint graphite/text before the
    # histogram stretch can wash it away.  We compare the original pixels with
    # the local paper background; anything slightly darker than nearby paper is
    # amplified into a subtraction mask.  This gives pencil writing actual
    # depth while leaving flat white paper alone.
    depth = max(0.0, min(1.0, (ink_threshold - 90) / 75.0))
    stroke_lift = ImageChops.subtract(bg_blur, raw_gray)
    stroke_lift = ImageEnhance.Contrast(stroke_lift).enhance(1.8 + 2.6 * depth)
    lift_floor = 3 if depth < 0.45 else 2
    lift_gain = 3.2 + 4.8 * depth
    stroke_lift = stroke_lift.point(
        lambda v: 0 if v <= lift_floor else min(255, int(round((v - lift_floor) * lift_gain)))
    )
    lifted = ImageChops.subtract(gray, stroke_lift.point(lambda v: int(round(v * (0.42 + 0.38 * depth)))))
    gray = Image.blend(gray, lifted, 0.28 + 0.42 * depth)

    # 2b. Auto-level (stretch 1%..99% to 0..255) so dingy scans go truly white.
    gray = ImageOps.autocontrast(gray, cutoff=(1, 1))

    # 3. Edge sharpening — recovers crisp pencil-stroke contours.
    gray = gray.filter(ImageFilter.UnsharpMask(radius=1.4, percent=180, threshold=2))

    # 3b. Stroke-depth pass. A small MinFilter expands only dark strokes, then
    # blends them back into the original so faint pencil/text gains body without
    # turning the paper grey. Stronger presets raise ink_threshold, which also
    # increases this depth pass.
    gray = ImageEnhance.Contrast(gray).enhance(1.08 + 0.20 * depth)
    stroke_shadow = gray.filter(ImageFilter.MinFilter(3))
    if depth > 0.55:
        wider_shadow = gray.filter(ImageFilter.MinFilter(5))
        stroke_shadow = Image.blend(stroke_shadow, wider_shadow, 0.10 + 0.18 * depth)
    gray = Image.blend(gray, stroke_shadow, 0.18 + 0.30 * depth)

    # 3c. Gamma > 1 darkens midtones — pulls grey graphite toward black without
    # crushing paper (paper is already near 255 from the flatten step).
    gamma = 1.12 + 0.30 * depth
    gamma_lut = [int(round(((v / 255.0) ** gamma) * 255)) for v in range(256)]
    gray = gray.point(gamma_lut)

    # 4. Smoothstep LUT.
    dark_point  = max(0,   min(200, ink_threshold - 20))   # full-ink boundary
    light_point = max(dark_point + 10,
                      int(round(255 - 40 * opacity)))      # paper-white boundary
                                                            # opacity 0 → 255, opacity 1 → 215
    span = max(1, light_point - dark_point)

    lut = []
    for v in range(256):
        if v <= dark_point:
            # Solid ink: darken aggressively so writing reads jet black.
            out = int(round(v * ink_darken))
        elif v >= light_point:
            # Paper.
            out = 255
        else:
            # Smoothstep ramp ink → paper.
            t = (v - dark_point) / span
            s = t * t * (3 - 2 * t)                        # smoothstep
            ink_val   = v * ink_darken
            paper_val = 255
            out = int(round(ink_val + (paper_val - ink_val) * s))
        lut.append(max(0, min(255, out)))

    gray = gray.point(lut)

    if brightness != 1.0:
        gray = ImageEnhance.Brightness(gray).enhance(brightness)

    return gray.convert("RGB")


def make_page(img_path: Path, page_w_pt: float, page_h_pt: float,
              fit: str, dpi: int, auto_rotate: str, rotate: int,
              style: str = "none",
              pencil_opacity: float = 0.25,
              pencil_brightness: float = 1.0,
              pencil_ink_threshold: int = 90,
              pencil_ink_darken: float = 0.55) -> Image.Image:
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
    ap.add_argument("--out", default=None,
                    help="Explicit output PDF path (overrides --name-pattern)")
    ap.add_argument("--name-pattern", default=None,
                    help="Pattern for the auto-generated PDF filename when "
                         "--out isn't given. Placeholders: "
                         "{folder} {first} {count} {style} {strength} "
                         "{date} {time} {datetime} {y} {m} {d} {hh} {mm} {ss}. "
                         "Examples: '{folder}', '{folder}_{date}', "
                         "'{folder}-{count}p-{datetime}', "
                         "'{first}_{strength}'. Saved as your default after "
                         "each run (in ~/.jpg2pdf/config.json).")
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
    ap.add_argument("--pencil-strength",
                    choices=["subtle", "normal", "extra"], default=None,
                    help="Pencil preset for faint text: "
                         "'subtle' (default, gentle, keeps paper texture), "
                         "'normal' (balanced ink + paper grain), "
                         "'extra' (extra-visible — aggressive darkening for very faint pencil). "
                         "Defaults to your last chosen value (saved in "
                         "~/.jpg2pdf/config.json), or 'subtle' on first run. "
                         "Individual --pencil-* flags override the preset.")
    ap.add_argument("--pencil-opacity", type=float, default=None,
                    help="Pencil style: how much non-ink survives (0..1, default 0.25). "
                         "Lower = whiter paper.")
    ap.add_argument("--pencil-ink-threshold", type=int, default=None,
                    help="Pencil style: pixel value (0..255) below which a pixel is "
                         "treated as ink and kept dark.")
    ap.add_argument("--pencil-ink-darken", type=float, default=None,
                    help="Pencil style: ink multiplier (<1 makes ink blacker).")
    ap.add_argument("--pencil-brightness", type=float, default=None,
                    help="Pencil style: post-process brightness multiplier (default 1.0).")
    ap.add_argument("--ask-strength", action="store_true",
                    help="When --style pencil, show a desktop dropdown to pick "
                         "subtle/normal/extra before converting.")
    ap.add_argument("--reset-prefs", action="store_true",
                    help="Forget the saved pencil-strength preference and exit.")
    ap.add_argument("--preview-grid", action="store_true",
                    help="Before converting, open a scrollable thumbnail grid "
                         "so you can confirm / deselect images. Cancel aborts "
                         "the run; uncheck any image to skip it.")
    ap.add_argument("--thumb-size", type=int, default=140,
                    help="--preview-grid: max thumbnail edge in pixels (default 140).")
    ap.add_argument("--thumb-cols", type=int, default=4,
                    help="--preview-grid: number of columns (default 4).")
    args = ap.parse_args()

    # Load persisted prefs (last chosen pencil strength).
    prefs = load_prefs()
    if args.reset_prefs:
        try:
            CONFIG_PATH.unlink()
            print(f"Removed {CONFIG_PATH}")
        except FileNotFoundError:
            print("No saved prefs to remove.")
        sys.exit(0)

    # Seed default from saved prefs (CLI value always wins).
    cli_strength_explicit = args.pencil_strength is not None
    if not cli_strength_explicit:
        args.pencil_strength = prefs.get("pencil_strength", "subtle")
        if args.pencil_strength not in PENCIL_PRESETS:
            args.pencil_strength = "subtle"

    # ---- Resolve input mode (BEFORE the strength picker so we can pass a
    # real sample image into the live preview) ----
    images = []
    out_dir = None       # where the PDF will be written
    folder_name = None   # used by {folder} in --name-pattern

    if args.files_from:
        listfile = Path(args.files_from).expanduser().resolve()
        if not listfile.is_file():
            print(f"List file not found: {listfile}", file=sys.stderr); sys.exit(1)
        lines = [ln.strip() for ln in listfile.read_text(encoding="utf-8").splitlines()
                 if ln.strip() and not ln.strip().startswith("#")]
        images = collect_from_list(lines)
        if images:
            out_dir = images[0].parent
            folder_name = images[0].parent.name
    elif args.files:
        images = collect_from_list(args.files)
        if images:
            out_dir = images[0].parent
            folder_name = images[0].parent.name
    elif args.folder:
        folder = Path(args.folder).expanduser().resolve()
        if not folder.is_dir():
            print(f"Not a folder: {folder}", file=sys.stderr); sys.exit(1)
        images = collect_from_folder(folder, args.recursive)
        out_dir = folder
        folder_name = folder.name
    else:
        ap.error("Provide a folder, or --files, or --files-from.")

    if not images:
        print("No images to convert.", file=sys.stderr); sys.exit(1)

    # Optional: confirm/deselect images via thumbnail grid before conversion.
    if args.preview_grid:
        kept = prompt_thumbnail_grid(images,
                                     thumb_px=max(48, args.thumb_size),
                                     cols=max(1, args.thumb_cols))
        if kept is None:
            print("Cancelled by user.", file=sys.stderr); sys.exit(130)
        if not kept:
            print("No images selected — nothing to convert.", file=sys.stderr); sys.exit(1)
        if len(kept) != len(images):
            print(f"  preview-grid: kept {len(kept)} of {len(images)} image(s)")
        images = kept

    # Interactive picker with LIVE preview (only meaningful with --style pencil)
    if args.ask_strength and args.style == "pencil":
        cli_overrode = any(v is not None for v in (
            args.pencil_opacity, args.pencil_ink_threshold,
            args.pencil_ink_darken, args.pencil_brightness))
        if not cli_overrode:
            args.pencil_strength = prompt_pencil_strength(
                args.pencil_strength, sample_path=images[0])

    # Persist the resolved strength so the NEXT export reuses it automatically.
    if args.style == "pencil" and args.pencil_strength in PENCIL_PRESETS:
        if prefs.get("pencil_strength") != args.pencil_strength:
            prefs["pencil_strength"] = args.pencil_strength
            save_prefs(prefs)

    # Apply preset (defined at module scope) for any --pencil-* flag the user
    # didn't override on the CLI.
    preset = PENCIL_PRESETS[args.pencil_strength]
    if args.pencil_opacity       is None: args.pencil_opacity       = preset["opacity"]
    if args.pencil_ink_threshold is None: args.pencil_ink_threshold = preset["ink_threshold"]
    if args.pencil_ink_darken    is None: args.pencil_ink_darken    = preset["ink_darken"]
    if args.pencil_brightness    is None: args.pencil_brightness    = preset["brightness"]

    w, h = PAGE_SIZES[args.size]
    if args.orientation == "landscape":
        w, h = h, w

    # Resolve output filename: explicit --out wins, else apply --name-pattern
    # (CLI > saved pref > built-in default), persist if user passed one.
    cli_pattern_explicit = args.name_pattern is not None
    if args.name_pattern is None:
        args.name_pattern = prefs.get("name_pattern", DEFAULT_NAME_PATTERN)

    if args.out:
        out = Path(args.out).expanduser().resolve()
    else:
        base = format_pdf_name(
            args.name_pattern,
            folder_name=folder_name or "images",
            first_image=images[0],
            count=len(images),
            style=args.style,
            strength=args.pencil_strength,
        )
        out = (out_dir / f"{base}.pdf").resolve()

    if cli_pattern_explicit and prefs.get("name_pattern") != args.name_pattern:
        prefs["name_pattern"] = args.name_pattern
        save_prefs(prefs)

    auto_rot = "off" if args.no_auto_rotate else args.auto_rotate

    print(f"Files:    {len(images)}")
    print(f"Page:     {args.size} {args.orientation} ({int(w)}x{int(h)} pt) @ {args.dpi} DPI")
    print(f"Fit:      {args.fit}  rotate: {args.rotate}  auto-rotate: {auto_rot}")
    if args.style == "pencil":
        print(f"Style:    pencil [{args.pencil_strength}] (opacity={args.pencil_opacity}, "
              f"ink<= {args.pencil_ink_threshold} *{args.pencil_ink_darken}, "
              f"brightness={args.pencil_brightness})")
    print(f"Output:   {out}")

    # Group consecutive inputs by kind so adjacent images become a single
    # image-PDF chunk (efficient + matches user's selection order).
    import tempfile
    with tempfile.TemporaryDirectory(prefix="jpg2pdf-") as td:
        tmp = Path(td)
        chunks = []          # list of Path to PDF chunks (in final order)
        chunk_idx = 0
        i = 0
        n = len(images)
        while i < n:
            p = images[i]
            kind = kind_of(p)
            if kind == "image":
                # Greedily collect consecutive images.
                j = i
                batch = []
                while j < n and kind_of(images[j]) == "image":
                    batch.append(images[j]); j += 1
                for k, ip in enumerate(batch, 1):
                    print(f"  [{i + k}/{n}] image: {ip.name}")
                chunk_idx += 1
                out_chunk = tmp / f"chunk_{chunk_idx:03d}_img.pdf"
                if images_to_pdf_chunk(
                        batch, out_chunk,
                        page_w_pt=w, page_h_pt=h, fit=args.fit, dpi=args.dpi,
                        auto_rotate=auto_rot, rotate=args.rotate,
                        style=args.style,
                        pencil_opacity=args.pencil_opacity,
                        pencil_brightness=args.pencil_brightness,
                        pencil_ink_threshold=args.pencil_ink_threshold,
                        pencil_ink_darken=args.pencil_ink_darken):
                    chunks.append(out_chunk)
                i = j
                continue

            print(f"  [{i + 1}/{n}] {kind}: {p.name}")
            chunk_idx += 1
            if kind == "pdf":
                chunks.append(p)  # use as-is
            elif kind == "html":
                out_chunk = tmp / f"chunk_{chunk_idx:03d}_html.pdf"
                if html_to_pdf(p, out_chunk):
                    chunks.append(out_chunk)
            elif kind == "word":
                out_chunk = tmp / f"chunk_{chunk_idx:03d}_word.pdf"
                if word_to_pdf(p, out_chunk):
                    chunks.append(out_chunk)
            else:
                print(f"  skip (unknown type): {p.name}", file=sys.stderr)
            i += 1

        if not chunks:
            print("Nothing was successfully converted.", file=sys.stderr)
            sys.exit(1)

        if len(chunks) == 1 and chunks[0].suffix.lower() == ".pdf" \
                and chunks[0].parent != tmp:
            # Single pre-existing PDF input — copy to output instead of round-trip.
            import shutil
            shutil.copyfile(chunks[0], out)
        else:
            merge_pdfs(chunks, out)
    print(f"Done -> {out}")


if __name__ == "__main__":
    main()
