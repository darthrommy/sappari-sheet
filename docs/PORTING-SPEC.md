# negadice — Porting Specification

Source of truth for the React Native and Flutter ports of **negadice**, a
contact-sheet (index sheet) generator for scanned film. One sheet = one roll.

Origin: `G:\programming\softwares\negadice` (Tauri 2 + Rust + React).
**The origin repo is read-only. No port may write inside it.**

Derived from `src-tauri/src/{geometry,render,text,naming,commands}.rs` and
`src/{App.tsx,lib/tauri-images.ts,components/app/*}` at version 26.7.0.

---

## 1. Fidelity tiers

Every requirement below is tagged. Respect the tag.

- **[EXACT]** — must produce identical values to the Rust original. Port as a
  pure function with a unit test. No latitude.
- **[STRUCTURAL]** — same algorithm and same visible result; sub-pixel and
  encoder differences acceptable.
- **[BEST-EFFORT]** — platform capability differs; implement the closest
  equivalent and record the divergence in `docs/DEVIATIONS.md`.

**No new features.** No EXIF reading, no extra film modes, no options the
original lacks. Match scope exactly.

---

## 2. Sheet geometry  [EXACT]

Fixed landscape sheet with a header band on top and a grid below.

```
SHEET_WIDTH  = 3000
SHEET_HEIGHT = 2100
MARGIN       = 144
GAP          = 8
HEADER_H     = 140
```

Derived, using **integer (floor) division** — do not use floats:

```
avail_w = SHEET_WIDTH  - MARGIN*2            = 2712
avail_h = SHEET_HEIGHT - MARGIN*2 - HEADER_H = 1672

cw = (avail_w - GAP*(cols-1)) / cols     // integer division
ch = (avail_h - GAP*(rows-1)) / rows     // integer division
```

### Film modes

| id      | label (UI)    | cols | rows | capacity | cell    | orientation |
|---------|---------------|------|------|----------|---------|-------------|
| `half`  | `35mm ハーフ` | 12   | 6    | 72       | 218×272 | portrait    |
| `35mm`  | `35mm`        | 7    | 6    | 42       | 380×272 | landscape   |
| `645`   | `645`         | 4    | 4    | 16       | 672×412 | landscape   |
| `66`    | `6×6`         | 4    | 3    | 12       | 672×552 | landscape   |
| `67`    | `6×7`         | 4    | 3    | 12       | 672×552 | landscape   |

`half` is the only portrait-cell mode; scanners emit every other format
landscape. An unknown mode id is an error: `unknown film mode: {id}`.

### Cell placement

```
row = index / cols        // integer division
col = index % cols
x   = MARGIN + col * (cw + GAP)
y   = MARGIN + HEADER_H + row * (ch + GAP)     // = 284 + row*(ch+GAP)
```

**Invariant to unit-test for all five modes**: the last cell
(`index = capacity-1`) satisfies `x+cw <= 2856` and `y+ch <= 1956`, and
`y >= 284`. All five modes land exactly on those bounds.

---

## 3. Rendering

### 3.1 cover_cell  [STRUCTURAL]

Fit one decoded image into a cell, `object-fit: cover` style.

1. `img_landscape = img.width >= img.height`
2. If `img_landscape != cell_landscape`, **rotate 90°** first. (No EXIF is
   consulted — orientation is inferred from pixel ratio alone.)
3. `scale = max(cw / w, ch / h)` in float
4. `nw = max(round(w * scale), cw)`, `nh = max(round(h * scale), ch)`
5. Resize to exactly `nw × nh`. Rust uses **Lanczos3**. [BEST-EFFORT]
6. Center-crop: `ox = (nw - cw) / 2`, `oy = (nh - ch) / 2` (integer division),
   take `cw × ch`.

Result is always exactly `cw × ch`.

### 3.2 Sheet composition  [STRUCTURAL]

1. Fill `3000×2100` with white `#FFFFFF`.
2. Draw the memo header (§3.4).
3. For each slot `i` in `0..min(len, capacity)`:
   - decoded → `cover_cell`, blit at `cell_origin(i)`
   - `None` (unreadable/undecodable file) → fill the cell with gray `#CCCCCC`
   - then draw the frame label (§3.3) — **labels draw over both cases**

### 3.3 Frame label  [STRUCTURAL]

Bottom-right of every cell. Text is `1`-based, zero-padded to two digits
(`format!("{:02}")` → `01`, `02`, … `72`). Frame 100+ would print unpadded;
capacity caps at 72 so it never arises.

```
font    = UDEV Gothic 35JPDOC Bold
size    = 30px
pad     = 6
box_w   = ceil(text_width) + pad*2
box_h   = ceil(line_height) + pad*2        // line_height = ascent - descent
bx      = cx + cw - box_w - 4
by      = cy + ch - box_h - 4
```

Background: blend white over the existing pixels at **0.92 alpha** —
`p = round(p*0.08 + 255*0.92)` per channel, clipped to sheet bounds. Then draw
the text in black `#000000` with its **top-left** at `(bx+pad, by+pad)`.

### 3.4 Memo header — the "NOTE" field  [STRUCTURAL]

Always draw a hairline `#D2D2D2` across `y = MARGIN + HEADER_H - 1 = 283`,
from `x = 144` to `x = 2856`, separating the header band from the grid. This
happens **even when the memo is empty**.

Then `memo.trim()`; if empty, stop.

Otherwise a fixed-size framed field (constant size regardless of text length):

```
font         = UDEV Gothic 35JPDOC Regular
MEMO_PX      = 56    // value text
MEMO_CAP_PX  = 26    // "NOTE" caption
MEMO_BOX_H   = 96
MEMO_PAD_X   = 22
MEMO_BORDER  = 3
MEMO_INK     = #3C3C3C

box_x = 144
box_y = 144 + (140 - 96)/2 = 166
box_w = (3000 - 288) / 2 = 1356
```

1. **Border**: 3px-thick rectangle *outline* only (interior untouched) at
   `(x=144, y=166, w=1356, h=96)`, colour `#3C3C3C`, clipped to sheet bounds.
   A pixel is border if `yy < y+t || yy+t >= y1 || xx < x+t || xx+t >= x1`.
2. **Value**: `clip_to_width(memo, box_w - MEMO_PAD_X*2 = 1312)` (§3.5), drawn
   left-aligned at `x = box_x + 22`, colour `#1E1E1E`, vertically centred by
   **inked glyph extent**, not font metrics:
   `(vtop, vbot) = visual_v_bounds(value)`;
   `baseline = box_y + 96/2 - (vtop+vbot)/2`; top-left y = `baseline - ascent`.
3. **Caption** `"NOTE"` straddling the top border: compute
   `(ctop, cbot) = visual_v_bounds("NOTE")` at 26px, `cap_x = box_x + 16`.
   White out a notch `[cap_x-8, cap_x+cap_w+8] × [box_y+ctop-2, box_y+cbot+4]`
   (clipped, colour `#FFFFFF`), then draw `"NOTE"` in `#3C3C3C` with
   `baseline = box_y - (ctop+cbot)/2`, top-left y = `baseline - ascent`.

### 3.5 clip_to_width  [EXACT]

```
if text_width(text) <= max_w: return text unchanged
ell_w = text_width("…")
accumulate chars while (w + char_width + ell_w) <= max_w
append "…"
```

Note the loop **breaks** on the first char that would overflow — it does not
skip it and continue. Result always ends with `…` when clipping occurred.

### 3.6 Encoding  [BEST-EFFORT]

| output    | size                   | JPEG quality |
|-----------|------------------------|--------------|
| sheet     | 3000×2100              | 92           |
| thumbnail | `cw × ch` for the mode  | 72           |
| preview   | 1500×1050 (half sheet) | 82           |

Thumbnails and previews are returned as `data:image/jpeg;base64,{b64}` in the
original. A port may pass raw bytes / a native image object instead if that
suits the platform better — **record it in DEVIATIONS.md**. The preview
downscale uses `Triangle` (bilinear) filtering, not Lanczos3.

---

## 4. Text rendering  [BEST-EFFORT; metrics EXACT where computable]

Font: **UDEV Gothic 35JPDOC**, SIL OFL 1.1, Bold + Regular. Copy both `.ttf`
files **and `OFL.txt`** from `negadice/src-tauri/assets/fonts/` into the port
and register them in the app bundle. The font is embedded so there is no
runtime font lookup and Japanese memo text renders identically everywhere.

Required primitives (Rust uses `ab_glyph`):

- `text_width(px, s)` — sum of horizontal advances of each **char** (Unicode
  scalar; no kerning, no shaping, no ligatures). Naive per-codepoint advance is
  the correct behaviour to reproduce.
- `line_height(px)` = `ascent - descent` (descent is negative).
- `ascent(px)` — top of line to baseline.
- `visual_v_bounds(px, s)` — min/max **inked** y of the outlined glyphs
  relative to baseline (top negative). Falls back to `(-px*0.7, 0.0)` when
  nothing is drawable (e.g. all spaces). This is what makes CJK and Latin
  centre optically rather than by font padding.
- `draw_text(px, x, y_top, colour, s)` — baseline = `y_top + ascent`; each
  glyph alpha-blended by coverage: `p = round(p*(1-cov) + colour*cov)`; skip
  `cov <= 0`; clip out-of-bounds pixels.

---

## 5. Filenames and ordering  [EXACT]

### Accepted inputs

Extension, ASCII-lowercased, in `{jpg, jpeg, png}`. No extension → rejected.

### natural_cmp

File-manager ordering. Walk both names bytewise:

- Both positions digits → consume the full digit run from each, strip leading
  zeros (keeping at least one digit), compare **by length first, then
  lexicographically**. Unequal → return.
- Otherwise compare ASCII-lowercased bytes; equal → advance both, else return.
- On exhaustion, compare remaining lengths.

Test vectors: `img2 < img10`; `img10 > img2`; `IMG_001 == img_001`; `a < b`.

### sanitize_file_name

Trim; replace each of `< > : " / \ | ? *` and every control char `< 0x20` with
`_`; strip trailing `.` and ` ` repeatedly; empty result → `index_sheet`.

Vectors: `a<b>c/d` → `a_b_c_d`; `"  name..  "` → `name`; `"   "` →
`index_sheet`; `holiday 2024` unchanged.

### build_output_path

Separator is `\` if the folder string contains `\`, else `/`. Result is
`{folder}{sep}{sanitized}.jpg`.

Vectors: `("/a/b","roll")` → `/a/b/roll.jpg`;
`("C:\photos","roll")` → `C:\photos\roll.jpg`;
`("/a/b","bad*name")` → `/a/b/bad_name.jpg`.

---

## 6. Operation contracts

Three operations, mirroring the Tauri commands. Ports may expose them as
services/providers rather than IPC, but the semantics are fixed.

### analyze(paths, mode, sort) -> { frames, total, capacity }

1. Filter to accepted extensions.
2. `total` = count **after** filtering, **before** truncation.
3. If `sort`, order by `natural_cmp` on the **file name** (not full path).
   `sort=false` preserves input order — used after a manual reorder and on
   mode switch, so the user's arrangement survives.
4. Truncate to `mode.capacity`.
5. Build a thumbnail per frame (`cover_cell` + JPEG q72). Undecodable → null.
6. `frame = { path, fileName, thumb }`.
7. Emit `analyze` progress per item, then a final `done`.

### render(paths, outDir, fileName, mode, memo) -> writtenPath

Decode all → compose → encode q92 → create the parent directory if needed →
write to `build_output_path(outDir, fileName)`. Returns the path.
Progress: `decode` per item, `compose`, `done`.

### preview(paths, mode, memo) -> imageData

Identical pipeline to `render`, but downscale to 1500×1050 and return it
instead of writing. **Must share the decode/compose code path with `render`**
so the on-screen preview cannot drift from the exported file.

### Progress events

`{ phase: "analyze" | "decode" | "compose" | "done", done, total }`.
The UI hides the progress bar only on `done`. `compose` renders as an
indeterminate (100%-width) bar.

### Concurrency

Rust decodes with rayon across all cores. Ports should parallelise decoding
(worker threads / isolates) and must keep the UI responsive. Decode failures
are non-fatal: the slot becomes `None` → a gray cell.

---

## 7. UI parity  [STRUCTURAL]

Two-pane desktop layout. **Japanese strings are copied verbatim — do not
re-translate or "improve" them.**

Shell `#1a1a1a`, white text.

### Sidebar — 280px wide, `#232323`, right border `#333`

- Header: film icon + `negadice`, 15px semibold.
- `ソースファイル` (11px, `#888`, uppercase, wide tracking)
  - Button `写真を選択` / while busy `読み込み中...`
  - When frames exist: `{n} / {capacity} frames` (12px, `#888`)
- `シート設定`
  - `フィルム` → select, options `{label}（最大{capacity}枚）`
  - `メモ（シート上部に印字）` → 2-row textarea,
    placeholder `ロール名・日付・現像所など`
  - `ファイル名` → text input, placeholder `index_sheet`,
    hint `拡張子 .jpg は自動で追加されます`
- Footer: primary button `書き出す` / while busy `生成中...`,
  enabled only when `!generating && !analyzing && frames.length > 0`.

### Preview pane

- Header row: `PREVIEW - {label}` and `JPEG - 3000x2100`, both 11px `#666`.
- Progress bar when active. Phase labels:
  `analyze`→`読み込み中`, `decode`→`書き出し中`, `compose`→`合成中`, `done`→`完了`.
- Empty state: dashed drop zone, click to pick,
  `写真をドラッグ&ドロップ、またはクリックして選択` and
  `JPEG / PNG - 最大{capacity}枚 · ドラッグで並べ替え`.
- With frames, two tabs:
  - `並べ替え` — grid at the mode's `cols`, cells at the mode's aspect
    (`2/3` for half, `3/2` otherwise), thumbnails `object-fit: cover`,
    null thumb → `#cccccc` block, 2-digit index badge bottom-right on
    white 90%. Drag to reorder: source cell at 40% opacity, target ringed.
  - `プレビュー` — the real composed sheet on `#151515`, contain-fit,
    **debounced 350ms**, re-rendered when paths/mode/memo change, dimmed to
    40% while refreshing. Keyed on `paths.join("|") + mode + memo`.

### Behaviours

- Input is **file paths** — native file dialog + OS drag-and-drop onto the
  window. Never a browser File object.
- Export: pick a directory, render, toast `書き出しが完了しました`, then
  **clear the image list and the memo**. Failure toasts
  `書き出しに失敗しました: {err}`. Empty list toasts `書き出す画像がありません`.
- Changing film mode re-analyzes with `sort=false`, preserving arrangement.

---

## 8. Required test coverage

Port these Rust tests. They are the acceptance criteria.

**geometry** — mode parse including the error case; orientation flags; for all
five modes: positive cell dims, last cell inside margins, grid starts below
header; half cells portrait, 35mm cells landscape.

**naming** — extension acceptance (including `.JPG` uppercase, `.tiff` reject,
no-extension reject); the three sanitize vectors plus fallback; both separator
cases and the sanitizing case for output paths; all four `natural_cmp` vectors.

**render** — `clip_to_width` returns unchanged when it fits, ellipsizes and
stays within budget when it does not; rect border paints edges only, leaving
interior and outside untouched; `cover_cell` output is exactly `cw × ch` for
both a portrait source into a landscape cell and vice versa; `compose_sheet`
is 3000×2100, corner is white, cells 0/1/2 have the expected centre colour, an
unfilled cell centre is white; `None` → `#CCCCCC` centre; the label paints
bright pixels over a dark cell in the bottom-right region; **a Japanese memo
(`テストロール 2024`) paints more than 100 dark pixels in the header band while
an empty memo paints zero** (this is the CJK-font-path test — keep it);
encoded sheet round-trips to 3000×2100; preview decodes to exactly 1500×1050;
thumbnail decodes to exactly `cw × ch`.

**text** — Latin and Japanese both yield positive advance width; `draw_text`
darkens pixels.

---

## 9. Repo requirements (both ports)

- `git init`, sensible `.gitignore`, initial commit. **No remote, no push.**
- Fonts and `OFL.txt` vendored, with attribution in the README.
- `README.md`: what it is, its origin, how to run/build/test.
- `docs/PORTING-SPEC.md`: this file, verbatim.
- `docs/DEVIATIONS.md`: every [BEST-EFFORT] divergence, with the reason.
- Formatter, linter, type/analysis check, tests, and a release build — all
  runnable by a single documented command each, all exiting 0.
- A GitHub Actions workflow running that whole chain on `windows-latest`,
  committed and ready for whenever a remote is added.
