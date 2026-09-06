# Deviations from the Tauri original

Every place this port departs from `negadice` (Tauri 2 + Rust + React), and why.
Tiers refer to `docs/PORTING-SPEC.md` §1.

**The sheet design is now a deliberate fork — see §0 below.** Everything the
spec still tags **[EXACT]** is exact against *this port's* spec and covered by
unit tests; the remaining items are **[BEST-EFFORT]** or **[STRUCTURAL]**.

---

## 0. The sheet design is forked, not ported — [DELIBERATE]

**Original:** a 140px band carrying a bordered "NOTE" field with the memo, then
a grid whose cells are pure division of the available space (35mm at 380x272,
an aspect of 1.40), each frame's number painted *over* its bottom-right corner
on a 92%-opaque white box.

**Here:** an International Typographic layout. The roll name is a large
flush-left title, with ruled `Date` / `Frames` / `Film` columns beside it and a
3px rule closing a 240px header. Cells take their **true film aspect** — 35mm is
genuinely 3:2, 6x6 genuinely square — and frame numbers are set *below* each
cell, unpadded (`1`, not `01`), so nothing is ever painted over a photograph.
The grid is centred, so formats that do not fill the content box get symmetric
margins rather than oversized gutters.

**Why:** requested. Sheets get shared, so the roll's identity should lead and
the photographs should be unobscured.

**Consequence:** the two apps produce visibly different sheets from the same
roll, and this is intended. `negadice` itself is untouched. Capacities are
unchanged, so no roll that fitted one sheet now fails to. Frames are smaller
than before (35mm went from 380x272 to 348x232) because the below-cell numbers
and the taller header both cost vertical space. The single free-text `memo`
became a structured `SheetMeta { name, date }`; `Frames` and `Film` are derived
and never typed.

---

## 0b. Fonts — [DELIBERATE]

**Original:** UDEV Gothic 35JPDOC (Regular + Bold), one family covering both
Latin and CJK.

**Here:** **Google Sans Flex** primary with **Noto Sans JP** as the fallback,
both from Google Fonts, both SIL OFL 1.1, both embedded. Google Sans Flex has no
CJK coverage, so a Japanese roll name resolves through Noto Sans JP — a mixed
run like `テストロール 2024` draws its digits from the primary and its kana from
the fallback.

`dart:ui`'s `ParagraphStyle` has no `fontFamilyFallback`; only `TextStyle` does,
so the chain is set on the pushed style, which is what shaping actually uses.

**Consequence:** assets grew from 7.7 MB to ~10.9 MB. `test/font_fixture.dart`
registers *both* families deliberately — loading only the primary would let
Japanese fall through to the test harness's placeholder font and hide a broken
fallback chain.

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
