/// Sheet geometry — every value transcribed from the Figma design.
///
/// Source: `negadice-sheet`, one frame per format, all sharing the `2:87`
/// header component:
///
/// | format | node    | sheet       | grid   | cell                |
/// |--------|---------|-------------|--------|---------------------|
/// | `half` | `4:143` | 3000 x 2250 | 13 x 6 | 228.9231 x 305.2308 |
/// | `35mm` | `1:2`   | 3000 x 2000 | 7 x 6  | 426.8571 x 284.5714 |
/// | `645`  | `2:88`  | 3000 x 2250 | 6 x 3  | 498.3333 x 664.4444 |
/// | `66`   | `2:228` | 3000 x 3000 | 4 x 3  | 748.5 x 748.5       |
/// | `67`   | `2:301` | 3000 x 3500 | 3 x 3  | 998.6667 x 856      |
///
/// Each format's sheet takes the proportions of its own negative — 35mm 3:2,
/// 6x6 square, 6x7 a 6:7 portrait — so **the sheet height is a per-format
/// value, and the header is whatever the grid leaves**. That swings from
/// 252.67 for 645 to 928 for 6x7, which is why the title and description have a
/// per-format type scale while the metadata block stays a fixed 147 tall.
///
/// Half-frame is the exception to the negative-proportions rule: 18x24 would
/// give a 3000x4000 sheet its grid could not fill, so its frame is 4:3 like
/// 645's.
///
/// Positions are doubles because the design's are: 3000 across seven columns
/// does not land on integers.
library;

const double sheetWidth = 3000;

/// Left and right padding inside the header. The grid below has none — it runs
/// full bleed to the sheet's edges.
const double headerPadding = 100;

/// Gap between a title and its description, at every type scale.
const double titleDescriptionGap = 12;

/// Tracking is proportional to size: the title tightens by 3%, the description
/// opens by 1%.
const double titleTrackingRatio = -0.03;
const double descriptionTrackingRatio = 0.01;

const int titleWeight = 500;
const int descriptionWeight = 400;

/// Space between the title block and the metadata block.
const double titleMetaGap = 50;

/// The metadata block is the same at every format: four columns, 147 tall.
const double metaHeight = 147;
const double metaRight = sheetWidth - headerPadding;
const double metaColumnGap = 50;
const double metaPadX = 50;

/// Every column but the first carries a 2px left border.
const double metaBorderWidth = 2;

const double metaLabelFontSize = 32;
const double metaLabelTracking = -0.96;
const int metaLabelWeight = 600;

/// Label baseline sits 25 into the block, its value 82.
const double metaLabelOffset = 25;
const double metaValueOffset = 82;

const double metaValueFontSize = 40;
const double metaValueTracking = 0;
const int metaValueWeight = 400;

/// Gap between cells, both axes.
const double gridGap = 2;

/// Frame-number badge, bottom-left inside each cell: `px-[12px] py-[8px]`
/// around 32px text on the sheet's own ground colour.
const double numberFontSize = 32;
const double numberTracking = -0.96;
const int numberWeight = 500;
const double numberPadX = 12;
const double numberPadY = 8;
const double numberBoxHeight = numberFontSize + numberPadY * 2; // 48

/// Dark theme: ground behind everything, ink for text and borders, and a
/// slightly lighter block for a cell holding no photograph.
const int groundValue = 0xFF151515;
const int inkValue = 0xFFF0F0F0;
const int blankValue = 0xFF242424;

/// Film formats, each transcribed from its own frame.
enum FilmMode {
  half('half', '35mm ハーフ', 13, 6, 3 / 4, 2250, 96, 36),
  full35('35mm', '35mm', 7, 6, 3 / 2, 2000, 96, 36),
  f645('645', '645', 6, 3, 3 / 4, 2250, 80, 32),
  f66('66', '6x6', 4, 3, 1, 3000, 128, 48),
  f67('67', '6x7', 3, 3, 7 / 6, 3500, 128, 48);

  const FilmMode(
    this.id,
    this.label,
    this.cols,
    this.rows,
    this.aspect,
    this.sheetHeight,
    this.titleFontSize,
    this.descriptionFontSize,
  );

  final String id;

  /// Shown in the film selector and printed as the sheet's `Format` value.
  final String label;

  final int cols;
  final int rows;

  /// Cell aspect (width / height) — the negative's shooting orientation.
  final double aspect;

  /// The sheet takes its own proportions, so this is per-format.
  final double sheetHeight;

  /// The title and description scale with the room the header has.
  final double titleFontSize;
  final double descriptionFontSize;

  static FilmMode parse(String s) {
    for (final mode in FilmMode.values) {
      if (mode.id == s) return mode;
    }
    throw FormatException('unknown film mode: $s');
  }

  int get capacity => cols * rows;

  bool get cellLandscape => aspect >= 1.0;

  /// Cells fill the full sheet width, with [gridGap] between them.
  double get cellWidth => (sheetWidth - gridGap * (cols - 1)) / cols;

  double get cellHeight => cellWidth / aspect;

  double get gridHeight => rows * cellHeight + gridGap * (rows - 1);

  /// The header is whatever height the grid leaves above it.
  double get headerHeight => sheetHeight - gridHeight;

  double get gridTop => headerHeight;

  double get titleTracking => titleFontSize * titleTrackingRatio;
  double get descriptionTracking =>
      descriptionFontSize * descriptionTrackingRatio;

  /// Title plus its gap plus the description.
  double get titleBlockHeight =>
      titleFontSize + titleDescriptionGap + descriptionFontSize;

  /// Both header blocks are vertically centred in the header.
  double get titleTop => (headerHeight - titleBlockHeight) / 2;
  double get descriptionTop => titleTop + titleFontSize + titleDescriptionGap;

  double get metaTop => (headerHeight - metaHeight) / 2;
  double get metaLabelTop => metaTop + metaLabelOffset;
  double get metaValueTop => metaTop + metaValueOffset;

  /// Top-left of cell [index], left to right then top to bottom.
  ///
  /// Every cell of the grid is drawn, whether or not a frame occupies it; the
  /// empty ones get the blank block, as the design shows.
  (double, double) cellOrigin(int index) {
    final row = index ~/ cols;
    final col = index % cols;
    return (
      col * (cellWidth + gridGap),
      gridTop + row * (cellHeight + gridGap),
    );
  }

  /// Aspect for an on-screen preview cell — the same the sheet uses.
  double get cellAspect => aspect;
}
