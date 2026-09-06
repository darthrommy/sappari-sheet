# negadice — Flutter desktop port

Generates a photo index sheet (contact sheet) as a JPEG, laid out on a grid
chosen by film format. One sheet, one roll.

This is a Flutter desktop port of [negadice](../negadice), which is a Tauri 2
app with the rendering core in Rust. The port reimplements that core natively in
Dart rather than binding to it — see `docs/PORTING-SPEC.md` for the contract it
holds to, and `docs/DEVIATIONS.md` for everywhere it departs from the original.

Output is a fixed **3000 x 2100** landscape sheet in an International
Typographic ("Swiss") layout: the roll name as a flush-left title, ruled
`Date` / `Frames` / `Film` columns beside it, a rule closing the header, then a
centred grid with each frame's number set below its cell.

Cells take the **true aspect of the film format** rather than a division of the
available space, so a 6x6 negative renders square.

| Film mode     | Grid   | Frames | Aspect | Cell    |
| ------------- | ------ | ------ | ------ | ------- |
| `35mm ハーフ` | 12 x 6 | 72     | 3:4    | 174x232 |
| `35mm`        | 7 x 6  | 42     | 3:2    | 348x232 |
| `645`         | 4 x 4  | 16     | 1.35   | 497x368 |
| `6×6`         | 4 x 3  | 12     | 1:1    | 504x504 |
| `6×7`         | 4 x 3  | 12     | 5:4    | 630x504 |

The sheet design is a **deliberate fork** from the Tauri original's, which uses
grid-derived cell sizes and paints frame numbers over the photographs. See
`docs/DEVIATIONS.md` §0.

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
**[EXACT]**: sheet constants, per-mode grids and cell arithmetic (all integer
division), filename acceptance, natural ordering, sanitization, output paths.
The naming tests are 1:1 translations of the Rust `#[cfg(test)]` assertions; the
geometry tests pin this port's own forked layout instead.

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
1.1, both Regular and Bold:

- **Google Sans Flex** — primary, carrying Latin, digits and punctuation.
  See `assets/fonts/OFL-GoogleSansFlex.txt`.
- **Noto Sans JP** — the fallback. Google Sans Flex has no CJK coverage, so a
  Japanese roll name resolves through this. See `assets/fonts/OFL-NotoSansJP.txt`.

Both are embedded, so there is no runtime font lookup and a sheet renders
identically on every machine. A mixed run like `テストロール 2024` draws its
digits from the primary and its kana from the fallback.
