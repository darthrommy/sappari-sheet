/// Cell fitting and full-sheet composition: cover-fit cropping, the Swiss
/// title block, frame numbers, JPEG encoding, and preview thumbnails.
///
/// Spec §3. Cover-fit follows the Rust original; the sheet's design does not —
/// see `docs/DEVIATIONS.md` for the deliberate fork.
///
/// Composition runs through `dart:ui`: a [ui.PictureRecorder] plus [ui.Canvas],
/// rasterized with `Picture.toImage`, then JPEG-encoded by `package:image`.
/// `Canvas.drawImageRect` performs the cover-fit resample directly, so the
/// explicit resize-then-crop of the Rust original becomes a source rectangle.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import '../core/geometry.dart';
import '../core/sheet_meta.dart';
import 'text_metrics.dart';

const int outputQuality = 92;
const int thumbQuality = 72;
const int previewQuality = 82;

/// On-screen preview; half the real sheet.
const int previewWidth = 1500;
const int previewHeight = previewWidth * sheetHeight ~/ sheetWidth;

/// Double-typed sheet bounds, for the const `Rect`s below.
const double sheetWidthF = sheetWidth * 1.0;
const double sheetHeightF = sheetHeight * 1.0;
const double previewWidthF = previewWidth * 1.0;
const double previewHeightF = previewHeight * 1.0;

/// Frame number set below each cell.
const double numberPx = 24.0;

/// Roll name — the sheet's title.
const double titlePx = 68.0;

/// Column captions ("Date", "Frames", "Film").
const double metaLabelPx = 24.0;

/// Column values.
const double metaValuePx = 34.0;

/// Width the title wraps within, before the first metadata column.
const double titleMaxWidth = 1000.0;

/// Left edge of the first metadata column.
const double columnsLeft = 1180.0;
const double columnWidth = 300.0;
const double columnSpacing = 40.0;

/// How far left of a column the divider rule sits.
const double columnRuleInset = 20.0;

const double titleFirstBaseline = 190.0;
const double metaLabelBaseline = 168.0;
const double metaValueBaseline = 214.0;
const double columnRuleTop = 134.0;
const double columnRuleBottom = 232.0;
const double columnRuleWidth = 2.0;

/// The rule closing the title block, set above the grid.
const double headerRuleY = margin + headerH - 32.0;
const double headerRuleWidth = 3.0;

/// A single near-black grey carries the title, captions, values, numbers and
/// rules — the layout gets its hierarchy from weight and size, not colour.
const ui.Color ink = ui.Color(0xFF1A1A1A);
const ui.Color white = ui.Color(0xFFFFFFFF);
const ui.Color placeholderGray = ui.Color(0xFFCCCCCC);

/// Source rectangle on [image] that, drawn into a [cw] x [ch] cell, reproduces
/// the Rust scale-then-center-crop.
///
/// Spec §3.1. When the image orientation does not match the cell's, the Rust
/// original rotates the *image* 90° first; here the caller applies the rotation
/// as a canvas transform, so the source rectangle is computed against the
/// post-rotation dimensions and then mapped back (a centered rect under a 90°
/// rotation is the same centered rect with its sides swapped).
ui.Rect coverSourceRect(ui.Image image, int cw, int ch, bool cellLandscape) {
  final iw = image.width.toDouble();
  final ih = image.height.toDouble();
  final imgLandscape = image.width >= image.height;
  final rotated = imgLandscape != cellLandscape;

  // Dimensions the Rust `base` would have after any rotate90.
  final bw = rotated ? ih : iw;
  final bh = rotated ? iw : ih;

  final scale = math.max(cw / bw, ch / bh);
  var srcW = cw / scale;
  var srcH = ch / scale;
  srcW = math.min(srcW, bw);
  srcH = math.min(srcH, bh);

  // Map back into the original image's axes.
  final w = rotated ? srcH : srcW;
  final h = rotated ? srcW : srcH;
  return ui.Rect.fromLTWH((iw - w) / 2, (ih - h) / 2, w, h);
}

/// Draw one decoded frame cover-fitted into the cell at ([x], [y]).
void drawCoverCell(
  ui.Canvas canvas,
  ui.Image image,
  int x,
  int y,
  int cw,
  int ch,
  bool cellLandscape,
) {
  final src = coverSourceRect(image, cw, ch, cellLandscape);
  final imgLandscape = image.width >= image.height;
  final rotated = imgLandscape != cellLandscape;
  final paint = ui.Paint()
    ..filterQuality = ui.FilterQuality.high
    ..isAntiAlias = true;

  canvas.save();
  if (rotated) {
    // Rotate 90° clockwise about the cell's top-right corner, matching
    // `DynamicImage::rotate90`. In the rotated frame the cell is ch x cw.
    canvas.translate((x + cw).toDouble(), y.toDouble());
    canvas.rotate(math.pi / 2);
    canvas.drawImageRect(
      image,
      src,
      ui.Rect.fromLTWH(0, 0, ch.toDouble(), cw.toDouble()),
      paint,
    );
  } else {
    canvas.drawImageRect(
      image,
      src,
      ui.Rect.fromLTWH(
        x.toDouble(),
        y.toDouble(),
        cw.toDouble(),
        ch.toDouble(),
      ),
      paint,
    );
  }
  canvas.restore();
}

/// Frame number, set below the cell and flush with its left edge. Spec §3.3.
///
/// Unpadded — `1`, not `01` — and never painted over the photograph, so no
/// frame is obscured by its own number.
void drawNumber(ui.Canvas canvas, int frameNum, int x, int baselineY) {
  drawTextAtBaseline(
    canvas,
    frameNum.toString(),
    numberPx,
    x.toDouble(),
    baselineY.toDouble(),
    ink,
  );
}

/// One metadata column: a small bold caption over its value.
void _drawColumn(ui.Canvas canvas, int index, String label, String value) {
  final left = columnsLeft + index * (columnWidth + columnSpacing);

  // Divider rule to the column's left, as tall as the caption/value block.
  canvas.drawRect(
    ui.Rect.fromLTWH(
      left - columnRuleInset,
      columnRuleTop,
      columnRuleWidth,
      columnRuleBottom - columnRuleTop,
    ),
    ui.Paint()..color = ink,
  );

  drawTextAtBaseline(
    canvas,
    label,
    metaLabelPx,
    left,
    metaLabelBaseline,
    ink,
    bold: true,
  );
  drawTextAtBaseline(
    canvas,
    clipToWidth(value, metaValuePx, columnWidth),
    metaValuePx,
    left,
    metaValueBaseline,
    ink,
  );
}

/// Title block: the roll name as a large flush-left title, the ruled
/// Date / Frames / Film columns beside it, and the rule that closes the header
/// above the grid. Spec §3.4.
///
/// [frameCount] and [mode] are derived, never typed. An empty roll name falls
/// back to the film format's label so the title is never blank.
void drawHeader(
  ui.Canvas canvas,
  SheetMeta meta,
  FilmMode mode,
  int frameCount,
) {
  final name = meta.name.trim();
  final title = name.isEmpty ? mode.label : name;

  final paragraph = layoutWrapped(
    title,
    titlePx,
    titleMaxWidth,
    bold: true,
    color: ink,
  );
  // layoutWrapped positions by the box top; place it so the first line's
  // baseline lands on titleFirstBaseline.
  canvas.drawParagraph(
    paragraph,
    ui.Offset(
      margin.toDouble(),
      titleFirstBaseline - paragraph.alphabeticBaseline,
    ),
  );
  paragraph.dispose();

  // Photographer leads, as Customer does in a lab index sheet; the derived
  // values follow. Four columns run x=1180..2500, leaving the right edge open.
  _drawColumn(canvas, 0, 'Photographer', meta.author.trim());
  _drawColumn(canvas, 1, 'Date', meta.date.trim());
  _drawColumn(canvas, 2, 'Frames', frameCount.toString());
  _drawColumn(canvas, 3, 'Film', mode.label);

  canvas.drawRect(
    ui.Rect.fromLTWH(
      margin.toDouble(),
      headerRuleY,
      (sheetWidth - margin * 2).toDouble(),
      headerRuleWidth,
    ),
    ui.Paint()..color = ink,
  );
}

/// The sheet body shared by [composeSheet] and [composeSheetFromCells]: white
/// ground, title block, then [slotCount] cells each with its number below.
///
/// [drawSlot] paints the frame at slot `i` whose cell origin is ([x], [y]); it
/// is not called for null slots, which get the gray placeholder instead.
Future<ui.Image> _composeWith(
  int slotCount,
  FilmMode mode,
  SheetMeta meta, {
  required bool Function(int i) hasFrame,
  required void Function(ui.Canvas canvas, int i, int x, int y) drawSlot,
}) async {
  final cw = mode.cellWidth;
  final ch = mode.cellHeight;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    const ui.Rect.fromLTWH(0, 0, sheetWidthF, sheetHeightF),
  );

  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, sheetWidthF, sheetHeightF),
    ui.Paint()..color = white,
  );

  final count = math.min(slotCount, mode.capacity);
  drawHeader(canvas, meta, mode, count);

  for (var i = 0; i < count; i++) {
    final (x, y) = mode.cellOrigin(i);
    if (hasFrame(i)) {
      drawSlot(canvas, i, x, y);
    } else {
      canvas.drawRect(
        ui.Rect.fromLTWH(
          x.toDouble(),
          y.toDouble(),
          cw.toDouble(),
          ch.toDouble(),
        ),
        ui.Paint()..color = placeholderGray,
      );
    }
    final (nx, ny) = mode.numberBaseline(i);
    drawNumber(canvas, i + 1, nx, ny);
  }

  final picture = recorder.endRecording();
  final sheet = await picture.toImage(sheetWidth, sheetHeight);
  picture.dispose();
  return sheet;
}

/// Compose the full index sheet for [mode]. A null entry in [images] renders a
/// gray placeholder (a file that could not be read/decoded). Spec §3.2.
Future<ui.Image> composeSheet(
  List<ui.Image?> images,
  FilmMode mode,
  SheetMeta meta,
) => _composeWith(
  images.length,
  mode,
  meta,
  hasFrame: (i) => images[i] != null,
  drawSlot: (canvas, i, x, y) => drawCoverCell(
    canvas,
    images[i]!,
    x,
    y,
    mode.cellWidth,
    mode.cellHeight,
    mode.cellLandscape,
  ),
);

/// Compose the sheet from cells already cover-fitted by [renderCell].
///
/// Equivalent to [composeSheet] — each cell is blitted at 1:1, so no second
/// resample happens and the output is identical. This is the path the app uses,
/// letting [SheetService] reuse cells across previews and the final export.
Future<ui.Image> composeSheetFromCells(
  List<ui.Image?> cells,
  FilmMode mode,
  SheetMeta meta,
) => _composeWith(
  cells.length,
  mode,
  meta,
  hasFrame: (i) => cells[i] != null,
  drawSlot: (canvas, i, x, y) => canvas.drawImage(
    cells[i]!,
    ui.Offset(x.toDouble(), y.toDouble()),
    ui.Paint(),
  ),
);

/// JPEG-encode a `dart:ui` image at [quality].
Future<Uint8List> encodeJpeg(ui.Image image, int quality) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw StateError('could not read image pixels');
  final rgb = rgbaToRgb(data.buffer.asUint8List(), image.width, image.height);
  final frame = img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: rgb.buffer,
    numChannels: 3,
  );
  return img.encodeJpg(frame, quality: quality);
}

/// Encode a composed sheet at the output quality.
Future<Uint8List> encodeSheet(ui.Image sheet) =>
    encodeJpeg(sheet, outputQuality);

/// Cover-fit one source image into a standalone `cellWidth` x `cellHeight`
/// image for [mode].
///
/// These are exactly the pixels [drawCoverCell] would paint into the sheet, so
/// a cell rendered once can be blitted 1:1 by [composeSheetFromCells] with no
/// second resample and no difference in output. [SheetService] caches these so
/// that changing the memo, reordering frames, or exporting never re-reads the
/// source files.
///
/// The caller owns the result and must dispose it.
Future<ui.Image> renderCell(ui.Image source, FilmMode mode) async {
  final cw = mode.cellWidth;
  final ch = mode.cellHeight;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
  );
  drawCoverCell(canvas, source, 0, 0, cw, ch, mode.cellLandscape);
  final picture = recorder.endRecording();
  final cell = await picture.toImage(cw, ch);
  picture.dispose();
  return cell;
}

/// Cover-fit one image into a cell and JPEG-encode it for the reorder grid.
Future<Uint8List> makeThumb(ui.Image image, FilmMode mode) async {
  final cell = await renderCell(image, mode);
  try {
    return await encodeJpeg(cell, thumbQuality);
  } finally {
    cell.dispose();
  }
}

/// Downscale a composed sheet for the on-screen preview (the full-size sheet
/// would be needlessly large to hold in the widget tree). Spec §3.6.
Future<Uint8List> makePreview(ui.Image sheet) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    const ui.Rect.fromLTWH(0, 0, previewWidthF, previewHeightF),
  );
  canvas.drawImageRect(
    sheet,
    ui.Rect.fromLTWH(0, 0, sheet.width.toDouble(), sheet.height.toDouble()),
    const ui.Rect.fromLTWH(0, 0, previewWidthF, previewHeightF),
    ui.Paint()
      // Bilinear, matching the Rust `Triangle` filter for the preview scale.
      ..filterQuality = ui.FilterQuality.low
      ..isAntiAlias = true,
  );
  final picture = recorder.endRecording();
  final scaled = await picture.toImage(previewWidth, previewHeight);
  picture.dispose();
  final bytes = await encodeJpeg(scaled, previewQuality);
  scaled.dispose();
  return bytes;
}
