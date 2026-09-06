# Deviations from the Tauri original

Every place this port departs from `negadice` (Tauri 2 + Rust + React), and why.
Tiers refer to `docs/PORTING-SPEC.md` §1.

**The sheet design is now a deliberate fork — see §0 below.** Everything the
spec still tags **[EXACT]** is exact against *this port's* spec and covered by
unit tests; the remaining items are **[BEST-EFFORT]** or **[STRUCTURAL]**.

---

## 0. The sheet design is the Figma file, not the Tauri original — [DELIBERATE]

**Original:** a fixed 3000x2100 white sheet, a 140px band with a bordered
"NOTE" memo, cells sized by dividing the available space, frame numbers over
each photograph's bottom-right corner.

**Here:** the layout in `negadice-sheet`, one frame per format. A dark sheet
(`#151515` ground, `#F0F0F0` ink) 3000 wide, each format taking **its own
negative's proportions** — 35mm 3:2, 6x6 square, 6x7 a 6:7 portrait. The header
is whatever the grid leaves above it, so it ranges from 252.67 to 928 and the
title type scales with it. Below it a **full-bleed** grid with 2px gutters
whose numbers sit in ground-coloured boxes inside each cell. Empty cells are
`#242424` blocks.

**Why:** requested, and designed by the user rather than derived from the Rust.
`docs/PORTING-SPEC.md` §2 and §3.3/§3.4 transcribe it; the Figma wins if they
disagree.

**Consequence:** the two apps produce entirely different sheets, intentionally.
`negadice` itself is untouched. **Capacities changed** with the new grids —
half-frame 72 to 78, 645 16 to 18, 6x6 12 to 12 via 5x3 then 4x3, 6x7 12 to 9 —
so a roll that fitted a 6x7 sheet before may not now. There is no longer one
output size: 35mm is 3000x2000, 6x7 is 3000x3500. The `memo` string became
`SheetMeta { name, description, author, date }`. Geometry is double-precision,
because the design's own positions are fractional.

---

## 0a. Undecodable files share the blank block — [STRUCTURAL]

The design has one empty state, `#242424`, for a cell with no photograph. The
app also has to represent a file that failed to decode, which the design does
not cover. Both use that block; the failed one keeps its frame number, so it is
distinguishable in context from the trailing empties, and the reorder grid
still shows it as a broken thumbnail.

---

## 1. Resampling filter — [BEST-EFFORT]

**Original:** `image` crate, `FilterType::Lanczos3` for cover-fit, `Triangle`
for the preview downscale.

**Here:** `Canvas.drawImageRect` with `FilterQuality.high` (Skia's mipmap +
cubic path) for cover-fit, and `FilterQuality.low` (bilinear) for the preview.

**Why:** `dart:ui` exposes no Lanczos kernel. Skia's high-quality filter is the
closest available.

**Consequence:** Frame pixels are visually equivalent but not byte-identical.
Fine detail in downscaled scans resolves slightly differently. Sheet dimensions,
cell placement, and crop framing are unaffected — those are all integer
arithmetic and match exactly.

---

## 2. Cover-fit expressed as a source rectangle — [STRUCTURAL]

**Original:** rotate the image 90° if needed, resize the whole image to
`nw x nh`, then center-crop `cw x ch`.

**Here:** compute the equivalent centered source rectangle and let
`drawImageRect` resample straight into the destination cell; the 90° rotation
becomes a canvas transform about the cell's top-right corner.

**Why:** One resample instead of resample-then-copy, and no intermediate
full-size bitmap per frame.

**Consequence:** Mathematically the same crop. The original rounds `nw`/`nh` to
whole pixels before cropping, so its crop window can differ from this one by a
fraction of a source pixel. Invisible at sheet scale.

---

## 3. `visual_v_bounds` via rasterization, not glyph outlines — [BEST-EFFORT]

**Original:** walks `ab_glyph` outlines and takes the min/max inked y directly
from `px_bounds()`.

**Here:** lays the string out, rasterizes it once to an offscreen image, and
scans rows for any non-zero alpha. Same quantity, measured after rendering
rather than before.

**Why:** Flutter exposes no glyph-outline API. Rasterizing is the only way to
get a true inked extent rather than a font-metrics approximation — and the
inked extent is the entire point, since it is what makes CJK and Latin memo
text centre optically inside the NOTE field.

**Consequence:** Anti-aliased edge pixels count as ink, so the measured band can
be up to one pixel taller at each end than the outline bounds. The resulting
baseline shifts by at most half a pixel. The all-blank fallback
`(-px * 0.7, 0.0)` is reproduced exactly.

**Cost:** Two extra small rasterizations per sheet composition (the memo value
and the `NOTE` caption). Negligible next to decoding a roll of scans.

---

## 4. Text advance widths are shaped, not summed — [BEST-EFFORT]

**Original:** `text_width` sums per-codepoint `h_advance` with no kerning,
shaping, or ligatures.

**Here:** `Paragraph.maxIntrinsicWidth`, which is fully shaped.

**Why:** `dart:ui` has no unshaped advance API.

**Consequence:** For UDEV Gothic — a monospaced-Latin/fixed-CJK face — the two
agree closely. Where they differ, `clipToWidth` may keep one character more or
fewer before the ellipsis, and the label box may be a pixel wider or narrower.
The `clipToWidth` *algorithm* (break on first overflow, always append `…`) is
reproduced exactly.

---



## 7. Parallel decode uses bounded async, not isolates — [STRUCTURAL]

**Original:** rayon `par_iter` across all cores.

**Here:** four concurrent `ui.instantiateImageCodec` calls.

**Why:** Two constraints force this. `ui.Image` handles cannot cross isolate
boundaries, so an isolate pool would have to ship raw pixel buffers back and
re-upload them. And Flutter's image codec already performs the decode off the
UI isolate internally, so the concurrency is real rather than cooperative.

**Consequence:** Comparable throughput without the copy overhead. Concurrency is
fixed at 4 rather than scaling to core count — a deliberate cap, since each
in-flight decode holds a full-resolution bitmap.

**Related:** `Picture.toImage` must run on the UI isolate, so composition is not
parallelised. It was not parallel in the original either (only decoding was).

---

## 8. Thumbnails and previews are raw bytes, not data URLs — [STRUCTURAL]

**Original:** returns `data:image/jpeg;base64,{...}` strings across the Tauri
IPC boundary.

**Here:** returns `Uint8List` directly to `Image.memory`.

**Why:** There is no IPC boundary — the renderer and the UI share one isolate.
Base64 would cost ~33% memory and a pointless encode/decode round trip.
The spec explicitly permits this (§3.6).

---

## 9. Toasts are SnackBars — [STRUCTURAL]

**Original:** `sonner` toasts, bottom-right.

**Here:** Material `SnackBar`, floating, bottom-centre, 420px wide. Message
strings are identical.

---

## 10. Drag-to-reorder uses Flutter's Draggable — [STRUCTURAL]

**Original:** a custom pointer-event hook (`use-pointer-reorder`) driving
opacity and a ring highlight.

**Here:** `Draggable` / `DragTarget`. The source cell drops to 40% opacity and
the hovered target gets a white ring, matching the original's feedback.

---

## Not verified in this environment

`flutter build windows --release` could not be run here: Visual Studio with the
"Desktop development with C++" workload is not installed, and Windows Developer
Mode is off (Flutter needs it for plugin symlinks). Both are system-level
changes left to the repo owner. See the README for prerequisites.

`flutter analyze`, `dart format --set-exit-if-changed`, `flutter test`, and
`flutter build bundle --release` all pass locally.
