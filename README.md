# negadice — Flutter desktop port

Generates a photo index sheet (contact sheet) as a JPEG, laid out on a grid
chosen by film format. One sheet, one roll.

This is a Flutter desktop port of [negadice](../negadice), which is a Tauri 2
app with the rendering core in Rust. The port reimplements that core natively in
Dart rather than binding to it — see `docs/PORTING-SPEC.md` for the contract it
holds to, and `docs/DEVIATIONS.md` for everywhere it departs from the original.

Output is a fixed **3000 x 2100** landscape sheet: a header band carrying an
optional "NOTE" memo, and below it a grid sized to hold roughly one roll.

| Film mode     | Grid   | Frames | Cell     |
| ------------- | ------ | ------ | -------- |
| `35mm ハーフ` | 12 x 6 | 72     | portrait |
| `35mm`        | 7 x 6  | 42     | landscape |
| `645`         | 4 x 4  | 16     | landscape |
| `6×6`         | 4 x 3  | 12     | landscape |
| `6×7`         | 4 x 3  | 12     | landscape |

Frames are ordered by natural filename sort and can be rearranged by dragging.
**EXIF is never read** — a frame's orientation is inferred from its pixel ratio
and rotated to match the cell, on the assumption that scanners emit landscape.

## Layout

```
lib/
  core/       geometry.dart, naming.dart   — pure Dart, no Flutter imports
  render/     text_metrics.dart, sheet_renderer.dart — dart:ui composition
  services/   sheet_service.dart           — analyze / render / preview
  ui/         app_shell.dart, sidebar.dart, preview_pane.dart, theme.dart
test/         geometry, naming, render, sample_sheet
```

`core/` is deliberately Flutter-free and holds everything the spec tags
**[EXACT]**: sheet constants, per-mode grids and cell arithmetic (all integer
division), filename acceptance, natural ordering, sanitization, output paths.
Its tests are 1:1 translations of the Rust `#[cfg(test)]` assertions.

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

`flutter test` exercises the real `dart:ui` raster path with the bundled font,
including a check that Japanese memo text actually paints glyphs into the header
band. `test/sample_sheet_test.dart` writes a full composed sheet to
`build/samples/` for eyeballing against the original.

### Windows build prerequisites

`flutter build windows` additionally needs, beyond the Flutter SDK:

- **Visual Studio** with the *Desktop development with C++* workload
- **Developer Mode** enabled (`start ms-settings:developers`) — Flutter requires
  symlink support to build projects that use plugins

Both are machine-level setup, not repo configuration. CI on `windows-latest`
has them already.

## Fonts

Bundles **UDEV Gothic 35JPDOC** (Regular and Bold) under the SIL Open Font
License 1.1 — see `assets/fonts/OFL.txt`. The font is embedded so there is no
runtime font lookup and Japanese memo text renders identically on every
machine.

UDEV Gothic is by Yuko Otawara. <https://github.com/yuru7/udev-gothic>
