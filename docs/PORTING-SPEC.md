# negadice — Porting Specification

Source of truth for **negadice-flutter**, a contact-sheet (index sheet)
generator for scanned film. One sheet = one roll.

Origin: `G:\programming\softwares\negadice` (Tauri 2 + Rust + React).
**The origin repo is read-only. This port must never write inside it.**

Originally derived from
`src-tauri/src/{geometry,render,text,naming,commands}.rs` and
`src/{App.tsx,lib/tauri-images.ts,components/app/*}` at version 26.7.0.

**The sheet design has since been deliberately forked** toward an
International Typographic layout, so §2, §3.3 and §3.4 describe this port's
own design rather than the Rust original's, and their [EXACT] tags bind
against the tables here. Everything else — cover-fit, naming, ordering, the
operation contracts — still tracks the original. See `docs/DEVIATIONS.md` §0.

---

## 1. Fidelity tiers

Every requirement below is tagged. Respect the tag.

- **[EXACT]** — must produce exactly the values tabulated here. Implement as a
  pure function with a unit test. No latitude.
- **[STRUCTURAL]** — same algorithm and same visible result; sub-pixel and
  encoder differences acceptable.
- **[BEST-EFFORT]** — platform capability differs; implement the closest
  equivalent and record the divergence in `docs/DEVIATIONS.md`.

**No new features.** No EXIF reading, no extra film modes, no options the
original lacks. Match scope exactly.

---

## 2. Sheet geometry  [EXACT]

Fixed landscape sheet: a title block on top, then a centred grid whose frame
numbers sit below each cell.

```
SHEET_WIDTH   = 3000      MARGIN        = 120
SHEET_HEIGHT  = 2100      HEADER_H      = 240
GUTTER        = 54        ROW_GAP       = 14
NUMBER_BLOCK  = 26        NUMBER_BASELINE_OFFSET = 20

contentWidth  = 3000 - 2*120       = 2760
contentHeight = 2100 - 2*120 - 240 = 1620
```

### Film modes

Cells take the **true aspect of the film format**, not a division of the
available space.

| id      | label (UI)    | cols | rows | capacity | aspect          | cell    |
|---------|---------------|------|------|----------|-----------------|---------|
| `half`  | `35mm ハーフ` | 12   | 6    | 72       | 18/24 = 0.750   | 174x232 |
| `35mm`  | `35mm`        | 7    | 6    | 42       | 36/24 = 1.500   | 348x232 |
| `645`   | `645`         | 4    | 4    | 16       | 56/41.5 = 1.349 | 497x368 |
| `66`    | `6×6`         | 4    | 3    | 12       | 1.000           | 504x504 |
| `67`    | `6×7`         | 4    | 3    | 12       | 70/56 = 1.250   | 630x504 |

`half` is the only portrait format. An unknown mode id is an error:
`unknown film mode: {id}`.

### Cell sizing

Take whichever constraint binds first, then keep the aspect exact:

```
heightLimitedCellHeight = (contentHeight - NUMBER_BLOCK*rows - ROW_GAP*(rows-1)) / rows
widthLimitedCellWidth   = (contentWidth - GUTTER*(cols-1)) / cols

cw = min(round(heightLimitedCellHeight * aspect), widthLimitedCellWidth)
ch = cw derived back through the aspect
```

All division truncates. Height binds for every current mode; for 35mm **both**
bind at once, which is what lets 42 frames at 3:2 fit a 3000x2100 sheet at all.

### Placement

The grid is **centred horizontally** and sits directly under the header:

```
gridWidth = cols*cw + GUTTER*(cols-1)
gridLeft  = (SHEET_WIDTH - gridWidth) / 2
gridTop   = MARGIN + HEADER_H              = 360
rowPitch  = ch + NUMBER_BLOCK + ROW_GAP

x = gridLeft + col * (cw + GUTTER)
y = gridTop  + row * rowPitch

numberBaseline(i) = (x, y + ch + NUMBER_BASELINE_OFFSET)
```

**Invariants to unit-test for all five modes**: cell aspect equals the film
aspect (within rounding); the grid is centred to within a pixel and never
narrower than `MARGIN`; the last cell clears the right margin; the last
**number baseline** — not the cell — clears the bottom margin at `y <= 1980`
(every mode lands on 1972). For 35mm specifically, `gridWidth == contentWidth`
and `gridLeft == MARGIN`.

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
2. Draw the title block (§3.4), whose `Frames` value is the slot count below.
3. For each slot `i` in `0..min(len, capacity)`:
   - decoded → `cover_cell`, blit at `cell_origin(i)`
   - `None` (unreadable/undecodable file) → fill the cell with gray `#CCCCCC`
   - then draw the frame number (§3.3) **below** the cell — drawn in both cases

### 3.3 Frame number  [STRUCTURAL]

Set **below** the cell, flush with its left edge, baseline at
`cellY + cellHeight + 20`, size 24, colour `#1A1A1A`. **Unpadded** — `1`, not
`01`. Nothing is ever painted over the photograph.

### 3.4 Title block  [STRUCTURAL]

```
titlePx = 68 (bold)   metaLabelPx = 24 (bold)   metaValuePx = 34
titleMaxWidth = 1000  titleFirstBaseline = 190
columnsLeft = 1180    columnWidth = 300    columnSpacing = 40
columnRuleInset = 20  columnRuleTop = 134  columnRuleBottom = 232
columnRuleWidth = 2   headerRuleY = 328    headerRuleWidth = 3
ink = #1A1A1A         ground = #FFFFFF
```

1. **Title** — the roll name, flush left at `MARGIN`, wrapped within
   `titleMaxWidth`, capped at 2 lines with an ellipsis, first baseline at
   `titleFirstBaseline`. An **empty name falls back to the film format label**,
   so the title is never blank.
2. **Columns** — `Date`, `Frames`, `Film`, in that order. Column `i` starts at
   `columnsLeft + i*(columnWidth + columnSpacing)`, with a `columnRuleWidth`
   vertical rule `columnRuleInset` to its left spanning
   `columnRuleTop..columnRuleBottom`. Caption baseline 168 in bold; value
   baseline 214, clipped to `columnWidth` by §3.5. `Frames` is the number of
   slots actually placed and `Film` the mode label — both derived, never typed.
3. **Closing rule** — full content width at `headerRuleY`, `headerRuleWidth`
   thick, in `ink`.

Colour carries no hierarchy: one grey does title, captions, values, numbers and
rules alike. Weight and size do the work.

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

Fonts: **Google Sans Flex** (primary) with **Noto Sans JP** (fallback), both
from Google Fonts under SIL OFL 1.1, Regular + Bold each, all four embedded
alongside `OFL-GoogleSansFlex.txt` and `OFL-NotoSansJP.txt`. Google Sans Flex
carries no CJK, so Japanese resolves through Noto Sans JP. Embedding means no
runtime font lookup and identical rendering on every machine.

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

### render(paths, outDir, fileName, mode, meta) -> writtenPath

Decode all → compose → encode q92 → create the parent directory if needed →
write to `build_output_path(outDir, fileName)`. Returns the path.
Progress: `decode` per item, `compose`, `done`.

### preview(paths, mode, meta) -> imageData

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
  - `ロール名（シート表題に印字）` → single-line input,
    placeholder `Kodak Gold 200 など`
  - `日付` → single-line input, defaulting to today as `YYYY-MM-DD`
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
    (each mode's true film aspect), thumbnails `object-fit: cover`,
    null thumb → `#cccccc` block, 2-digit index badge bottom-right on
    white 90%. Drag to reorder: source cell at 40% opacity, target ringed.
  - `プレビュー` — the real composed sheet on `#151515`, contain-fit,
    **debounced 350ms**, re-rendered when paths/mode/memo change, dimmed to
    40% while refreshing. Keyed on `paths.join("|") + mode + memo`.

### Behaviours

- Input is **file paths** — native file dialog + OS drag-and-drop onto the
  window. Never a browser File object.
- Export: pick a directory, render, toast `書き出しが完了しました`, then
  **clear the image list and the roll name**. Failure toasts
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

**render** — `clip_to_width` returns unchanged when it fits and ellipsizes
within budget when it does not; `cover_cell` output is exactly `cw × ch` for
both a portrait source into a landscape cell and vice versa; `compose_sheet` is
3000×2100, corner white, cells 0/1/2 have the expected centre colour, an
unfilled cell centre is white; `None` → `#CCCCCC` centre; `composeSheetFromCells`
agrees with `composeSheet` at every cell centre and corner (this guards the cell
cache); **the cell interior is entirely untouched where the old design painted
its label box**, and ink appears in the number block below; numbers are
unpadded; the title paints ink and the closing rule spans the content width;
**a Japanese roll name paints materially more ink than the fallback title** —
this is the CJK-fallback test, and the only thing that catches a broken font
chain, so keep it; an empty name still paints a title; encoded sheet
round-trips to 3000×2100; preview decodes to exactly 1500×1050; thumbnail
decodes to exactly `cw × ch`.

**text** — Latin (primary) and Japanese (fallback) both yield positive advance
width; inked bounds sit above the baseline and fall back on blanks.

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
