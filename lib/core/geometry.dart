/// Sheet geometry and film modes.
///
/// Port of `negadice/src-tauri/src/geometry.rs` — spec §2, tier [EXACT].
///
/// The output is a fixed 3000x2100 landscape sheet with a header band for the
/// memo; the grid below it changes per film mode. Every derived value uses
/// truncating integer division (`~/`), matching Rust's `u32` arithmetic.
library;

const int sheetWidth = 3000;
const int sheetHeight = 2100;
const int margin = 144;
const int gap = 8;

/// Memo band at the top of the sheet.
const int headerH = 140;

/// Each mode picks a grid sized to hold roughly one roll, and a cell
/// orientation. Half-frame is the only portrait-cell mode; scanners emit every
/// other format landscape, so those cells are landscape too.
enum FilmMode {
  half('half', '35mm ハーフ', 12, 6),
  full35('35mm', '35mm', 7, 6),
  f645('645', '645', 4, 4),
  f66('66', '6×6', 4, 3),
  f67('67', '6×7', 4, 3);

  const FilmMode(this.id, this.label, this.cols, this.rows);

  /// Wire identifier, matching `FilmMode::parse` in the Rust original.
  final String id;

  /// Human-facing label shown in the film selector.
  final String label;

  final int cols;
  final int rows;

  /// Throws [FormatException] on an unknown id, mirroring the Rust
  /// `Err(format!("unknown film mode: {other}"))`.
  static FilmMode parse(String s) {
    for (final mode in FilmMode.values) {
      if (mode.id == s) return mode;
    }
    throw FormatException('unknown film mode: $s');
  }

  int get capacity => cols * rows;

  bool get cellLandscape => this != FilmMode.half;

  int get cellWidth {
    const availW = sheetWidth - margin * 2;
    return (availW - gap * (cols - 1)) ~/ cols;
  }

  int get cellHeight {
    const availH = sheetHeight - margin * 2 - headerH;
    return (availH - gap * (rows - 1)) ~/ rows;
  }

  /// Top-left corner of cell [index], laid out left-to-right, top-to-bottom.
  (int, int) cellOrigin(int index) {
    final row = index ~/ cols;
    final col = index % cols;
    final x = margin + col * (cellWidth + gap);
    final y = margin + headerH + row * (cellHeight + gap);
    return (x, y);
  }

  /// Aspect ratio (w / h) of a preview cell, matching the sheet cell
  /// orientation: 2/3 for half-frame, 3/2 for everything else.
  double get cellAspect => cellLandscape ? 3 / 2 : 2 / 3;
}
