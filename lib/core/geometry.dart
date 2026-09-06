/// Sheet geometry and film modes.
///
/// Spec §2, tier [EXACT] — against this port's own spec. The sheet design was
/// deliberately forked from the Tauri original's toward an International
/// Typographic ("Swiss") layout: a title block carrying the roll name and
/// ruled metadata columns, then a centred grid whose frame numbers sit *below*
/// each cell rather than painted over it. See `docs/DEVIATIONS.md`.
///
/// Cells take their real film aspect rather than whatever the grid division
/// happened to produce, so a 6x6 negative renders square. Derived values use
/// truncating integer division, so every constant below is exact.
library;

const int sheetWidth = 3000;
const int sheetHeight = 2100;
const int margin = 120;

/// Title block: roll name plus the ruled Date / Frames / Film columns. The
/// closing rule is drawn at its lower edge.
const int headerH = 240;

/// Horizontal space between columns of the grid.
const int gutter = 54;

/// Vertical space between a frame number and the next row of cells.
const int rowGap = 14;

/// Vertical space reserved under each cell for its frame number.
const int numberBlock = 26;

/// Distance from a cell's bottom edge down to the frame number's baseline.
const int numberBaselineOffset = 20;

/// Content box the grid is fitted into, below the header and inside the margins.
const int contentWidth = sheetWidth - margin * 2;
const int contentHeight = sheetHeight - margin * 2 - headerH;

/// Each mode picks a grid sized to hold roughly one roll, and the true aspect
/// of that film format. Half-frame is the only portrait format.
enum FilmMode {
  half('half', '35mm ハーフ', 12, 6, 18 / 24),
  full35('35mm', '35mm', 7, 6, 36 / 24),
  f645('645', '645', 4, 4, 56 / 41.5),
  f66('66', '6×6', 4, 3, 1.0),
  f67('67', '6×7', 4, 3, 70 / 56);

  const FilmMode(this.id, this.label, this.cols, this.rows, this.aspect);

  /// Wire identifier, matching `FilmMode::parse` in the Rust original.
  final String id;

  /// Human-facing label shown in the film selector and in the sheet header.
  final String label;

  final int cols;
  final int rows;

  /// Frame aspect (width / height) of the film format itself.
  final double aspect;

  /// Throws [FormatException] on an unknown id, mirroring the Rust
  /// `Err(format!("unknown film mode: {other}"))`.
  static FilmMode parse(String s) {
    for (final mode in FilmMode.values) {
      if (mode.id == s) return mode;
    }
    throw FormatException('unknown film mode: $s');
  }

  int get capacity => cols * rows;

  bool get cellLandscape => aspect >= 1.0;

  /// Tallest cell the rows fit into, before the aspect is applied.
  int get _heightLimitedCellHeight =>
      (contentHeight - numberBlock * rows - rowGap * (rows - 1)) ~/ rows;

  /// Widest cell the columns fit into.
  int get _widthLimitedCellWidth =>
      (contentWidth - gutter * (cols - 1)) ~/ cols;

  /// Cell width, taking whichever of the two constraints binds first.
  ///
  /// Height binds for 35mm and half-frame; width would bind for a very wide
  /// format. Taking the minimum keeps the aspect exact either way, and the
  /// leftover space becomes margin rather than distorted cells.
  int get cellWidth {
    final fromHeight = (_heightLimitedCellHeight * aspect).round();
    final fromWidth = _widthLimitedCellWidth;
    return fromHeight <= fromWidth ? fromHeight : fromWidth;
  }

  int get cellHeight {
    final fromHeight = (_heightLimitedCellHeight * aspect).round();
    return fromHeight <= _widthLimitedCellWidth
        ? _heightLimitedCellHeight
        : (_widthLimitedCellWidth / aspect).round();
  }

  /// Total width the laid-out grid occupies.
  int get gridWidth => cols * cellWidth + gutter * (cols - 1);

  /// Left edge of the grid — centred, so formats that do not fill the content
  /// box get symmetric white space instead of oversized gutters.
  int get gridLeft => (sheetWidth - gridWidth) ~/ 2;

  /// Top edge of the grid: directly under the header's closing rule.
  int get gridTop => margin + headerH;

  /// Vertical distance from one row's cell top to the next.
  int get rowPitch => cellHeight + numberBlock + rowGap;

  /// Top-left corner of cell [index], laid out left-to-right, top-to-bottom.
  (int, int) cellOrigin(int index) {
    final row = index ~/ cols;
    final col = index % cols;
    final x = gridLeft + col * (cellWidth + gutter);
    final y = gridTop + row * rowPitch;
    return (x, y);
  }

  /// Baseline for the frame number under cell [index], flush with its left edge.
  (int, int) numberBaseline(int index) {
    final (x, y) = cellOrigin(index);
    return (x, y + cellHeight + numberBaselineOffset);
  }

  /// Aspect ratio (w / h) for an on-screen preview cell. Same value the sheet
  /// uses, so the reorder grid previews the real framing.
  double get cellAspect => aspect;
}
