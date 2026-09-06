# Deviations from the Tauri original

Every place this port departs from `negadice` (Tauri 2 + Rust + React), and why.
Tiers refer to `docs/PORTING-SPEC.md` §1.

Everything tagged **[EXACT]** in the spec is reproduced exactly and covered by
unit tests. The items below are all **[BEST-EFFORT]** or **[STRUCTURAL]**.

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

## 5. Label background alpha quantized — [STRUCTURAL]

**Original:** blends per channel in float: `p * 0.08 + 255 * 0.92`.

**Here:** draws `Color(0xEBFFFFFF)` — alpha 235, i.e. `0.92 * 255 = 234.6`
rounded — and lets Skia blend.

**Consequence:** Up to 1/255 difference per channel under the label box.

---

## 6. NOTE border drawn as a stroked rect — [STRUCTURAL]

**Original:** a manual pixel loop that paints only cells satisfying
`yy < y+t || yy+t >= y1 || xx < x+t || xx+t >= x1`, i.e. a 3px inward band.

**Here:** `PaintingStyle.stroke` with `strokeWidth = 3` on a rect inset by half
the stroke width, which produces the same 3px inward band.

**Consequence:** Identical geometry; Skia anti-aliases the outer edge where the
original was hard-edged. Verified by test: left border inked, field interior
still white.

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
