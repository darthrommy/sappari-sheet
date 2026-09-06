# negadice — Flutter desktop port

Generates a photo index sheet (contact sheet) as a JPEG, laid out on a grid
chosen by film format. One sheet, one roll.

This is a Flutter desktop port of [negadice](../negadice), which is a Tauri 2
app with the rendering core in Rust. The port reimplements that core natively in
Dart rather than binding to it — see `docs/PORTING-SPEC.md` for the contract it
holds to, and `docs/DEVIATIONS.md` for everywhere it departs from the original.

The sheet layout is a Figma design —
[negadice-sheet](https://www.figma.com/design/QMS8aKf6lWRNeUhuXVirfR/negadice-sheet?node-id=1-2),
one frame per format — transcribed into `lib/core/geometry.dart`. **The Figma
is the source of truth**; if code and design disagree, the design wins.

A dark sheet — `#151515` ground, `#F0F0F0` ink — **3000 wide, each format
taking its own negative's proportions**: 35mm 3:2, 6x6 square, 6x7 a 6:7
portrait. The header carries the roll name over a description line, with
`Photographer` / `Date` / `Frames` / `Format` columns right-aligned beside it;
its height is **whatever the grid leaves**, so the title type scales with it.
Below, the grid runs **full bleed** to the sheet's edges with 2px gutters, each
frame numbered in a box inside its bottom-left corner. Cells with no photograph
are `#242424` blocks, so a sheet is always its format's full height.

| Film mode     | Grid   | Frames | Cell                | Sheet       | Title |
| ------------- | ------ | ------ | ------------------- | ----------- | ----- |
| `35mm ハーフ` | 13 x 6 | 78     | 228.92 x 305.23     | 3000 x 2250 | 96    |
| `35mm`        | 7 x 6  | 42     | 426.86 x 284.57     | 3000 x 2000 | 96    |
| `645`         | 6 x 3  | 18     | 498.33 x 664.44     | 3000 x 2250 | 80    |
| `6x6`         | 4 x 3  | 12     | 748.50 x 748.50     | 3000 x 3000 | 128   |
| `6x7`         | 3 x 3  | 9      | 998.67 x 856.00     | 3000 x 3500 | 128   |

Half-frame is the one exception to the negative-proportions rule: 18x24 would
give a 3000x4000 sheet its grid could not fill, so its frame is 4:3.

Frames are ordered by natural filename sort and can be rearranged by dragging.
**EXIF is never read** — a frame's orientation is inferred from its pixel ratio
and rotated to match the cell, on the assumption that scanners emit landscape.

## Layout

```
lib/
  core/       geometry.dart, naming.dart, sheet_meta.dart — no Flutter imports
  render/     text_metrics.dart, sheet_renderer.dart — dart:ui composition
  services/   sheet_service.dart           — analyze / render / preview
  ui/         app_shell.dart, sidebar.dart, preview_pane.dart, theme.dart
test/         geometry, naming, render, sheet_service, sample_sheet
installer/    negadice.iss, build-installer.ps1 — Inno Setup packaging
```

`core/` is deliberately Flutter-free and holds everything the spec tags
**[EXACT]**: the transcribed layout constants and cell arithmetic, filename
acceptance, natural ordering, sanitization, output paths, date parsing. The
naming tests are 1:1 translations of the Rust `#[cfg(test)]` assertions; the
geometry tests check the design's own numbers, to a thousandth of a pixel —
Figma stores coordinates as float32, so its reported values carry rounding that
these doubles do not.

## Develop

```bash
flutter pub get
flutter run -d windows
```

## Verify

```bash
dart format --set-exit-if-changed .   # formatting
flutter analyze --fatal-infos         # lints + types
flutter test                          # unit + raster tests
flutter build windows --release       # release build
```

`flutter test` exercises the real `dart:ui` raster path with the bundled fonts,
including a check that a Japanese roll name actually paints glyphs into the
title — the only assertion that catches a broken font-fallback chain.
`test/sample_sheet_test.dart` writes a full composed sheet to `build/samples/`
for eyeballing.

### Windows build prerequisites

`flutter build windows` additionally needs, beyond the Flutter SDK:

- **Visual Studio** with the *Desktop development with C++* workload
- **Developer Mode** enabled (`start ms-settings:developers`) — Flutter requires
  symlink support to build projects that use plugins

Both are machine-level setup, not repo configuration. CI on `windows-latest`
has them already.

## Installer

```powershell
flutter build windows --release     # the installer packages this output
.\installer\build-installer.ps1
```

Produces `installer\Output\negadice-setup-<version>.exe` (~14 MB), where the
version comes from `pubspec.yaml`.

It is a **per-user** install: no UAC prompt, no administrator rights, and it
lands in `%LOCALAPPDATA%\Programs\negadice` with a Start Menu entry, an optional
desktop icon, and an uninstaller.

The script also copies `msvcp140.dll`, `vcruntime140.dll` and
`vcruntime140_1.dll` in beside the executable. `negadice.exe` imports these, and
they are absent on a Windows machine that has never had Visual Studio or a C++
application — so shipping them app-local means **the end user installs no
prerequisite**. Their location is discovered through `vswhere` rather than
hardcoded, because the folder is named after the toolset (`Microsoft.VC145.CRT`
on VS 2026, `Microsoft.VC143.CRT` on the VS 2022 that CI runs).

Building the installer locally needs Inno Setup 6:

```powershell
winget install JRSoftware.InnoSetup
```

The script finds `ISCC.exe` whether that install was machine-wide or per-user.
CI builds the installer on every run and uploads it as the `negadice-installer`
artifact.

The installer is **unsigned**, so Windows SmartScreen shows an "unrecognized
app" warning on first run until it accrues reputation. Only a code-signing
certificate removes that.

## Fonts

Bundles two families from Google Fonts, both under the SIL Open Font License
1.1:

- **Google Sans Flex** — primary, carrying Latin, digits and punctuation. One
  file per weight at 400, 500 and 600, the weights the design uses.
  See `assets/fonts/OFL-GoogleSansFlex.txt`.
- **Noto Sans JP** — the fallback, as a **variable** font: its weight is an axis
  rather than a file, set through `fontVariations`. Google Sans Flex has no CJK
  coverage, so Japanese resolves through this.
  See `assets/fonts/OFL-NotoSansJP.txt`.

Both are embedded, so there is no runtime font lookup and a sheet renders
identically on every machine. A mixed run like `テストロール 2024` draws its
digits from the primary and its kana from the fallback.
