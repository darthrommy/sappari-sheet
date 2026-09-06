/// Sheet composition: cover-fit cropping, the title block, frame numbers,
/// JPEG encoding and preview thumbnails.
///
/// The layout is the Figma design (negadice-sheet, node 1:2) — every position,
/// size, weight, letter spacing and colour comes from `core/geometry.dart`,
/// which transcribes it. Nothing here is inherited from the Tauri original
/// except cover-fit itself.
///
/// Composition runs through `dart:ui`: a [ui.PictureRecorder] plus [ui.Canvas],
/// rasterized with `Picture.toImage`, then JPEG-encoded by `package:image`.
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

const ui.Color ink = ui.Color(inkValue);
const ui.Color ground = ui.Color(groundValue);

/// A cell with no photograph in it: an empty slot, or a file that could not be
/// read. The design has only the first case, so both share its block.
const ui.Color blank = ui.Color(blankValue);

/// Preview height for [mode] — half the sheet, which is per-format now.
int previewHeightFor(FilmMode mode) =>
    (previewWidth * mode.sheetHeight / sheetWidth).round();

/// Source rectangle on [image] that, drawn into a [cw] x [ch] cell, reproduces
/// a scale-then-center-crop (CSS `object-fit: cover`, as the design's photos
/// use).
///
/// When the image's orientation does not match the cell's it is rotated 90°
/// first, so the rectangle is computed against the post-rotation dimensions and
/// mapped back — a centered rect under a 90° rotation is the same centered rect
/// with its sides swapped.
ui.Rect coverSourceRect(
  ui.Image image,
  double cw,
  double ch,
  bool cellLandscape,
) {
  final iw = image.width.toDouble();
  final ih = image.height.toDouble();
  final imgLandscape = image.width >= image.height;
  final rotated = imgLandscape != cellLandscape;

  final bw = rotated ? ih : iw;
  final bh = rotated ? iw : ih;

  final scale = math.max(cw / bw, ch / bh);
  var srcW = math.min(cw / scale, bw);
  var srcH = math.min(ch / scale, bh);

  final w = rotated ? srcH : srcW;
  final h = rotated ? srcW : srcH;
  return ui.Rect.fromLTWH((iw - w) / 2, (ih - h) / 2, w, h);
}

/// Draw one decoded frame cover-fitted into the rect at ([x], [y]).
void drawCoverCell(
  ui.Canvas canvas,
  ui.Image image,
  double x,
  double y,
  double cw,
  double ch,
  bool cellLandscape,
) {
  final src = coverSourceRect(image, cw, ch, cellLandscape);
  final rotated = (image.width >= image.height) != cellLandscape;
  final paint = ui.Paint()
    ..filterQuality = ui.FilterQuality.high
    ..isAntiAlias = true;

  canvas.save();
  if (rotated) {
    // Rotate 90° clockwise about the cell's top-right corner; in the rotated
    // frame the cell is ch x cw.
    canvas.translate(x + cw, y);
    canvas.rotate(math.pi / 2);
    canvas.drawImageRect(image, src, ui.Rect.fromLTWH(0, 0, ch, cw), paint);
  } else {
    canvas.drawImageRect(image, src, ui.Rect.fromLTWH(x, y, cw, ch), paint);
  }
  canvas.restore();
}

/// Cover-fit one source into a standalone cell image for [mode].
///
/// Rasterized at the rounded cell size; the composer draws it into the exact
/// fractional rect the design specifies. [SheetService] caches these so that
/// editing the header, reordering frames or exporting never re-reads a source.
/// The caller owns the result and must dispose it.
Future<ui.Image> renderCell(ui.Image source, FilmMode mode) async {
  final w = mode.cellWidth.round();
  final h = mode.cellHeight.round();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
  );
  drawCoverCell(
    canvas,
    source,
    0,
    0,
    w.toDouble(),
    h.toDouble(),
    mode.cellLandscape,
  );
  final picture = recorder.endRecording();
  final cell = await picture.toImage(w, h);
  picture.dispose();
  return cell;
}

/// Frame number: a white box in the cell's bottom-left corner, `px-12 py-6`
/// around the zero-padded index.
void drawNumber(
  ui.Canvas canvas,
  int frameNum,
  double cellX,
  double cellY,
  double cellHeight,
) {
  final text = frameNum.toString().padLeft(2, '0');
  final w =
      textWidth(
        text,
        px: numberFontSize,
        weight: numberWeight,
        letterSpacing: numberTracking,
      ) +
      numberPadX * 2;
  final top = cellY + cellHeight - numberBoxHeight;

  canvas.drawRect(
    ui.Rect.fromLTWH(cellX, top, w, numberBoxHeight),
    ui.Paint()..color = ground,
  );
  drawText(
    canvas,
    text,
    x: cellX + numberPadX,
    y: top + numberPadY,
    px: numberFontSize,
    weight: numberWeight,
    letterSpacing: numberTracking,
    color: ink,
  );
}

/// One metadata column: a 2px left border, then the label over its value.
///
/// Returns the column's width, which the design sizes to its content:
/// `max(label, value) + border + 50 either side`.
double _metaColumnWidth(String label, String value, {required bool bordered}) {
  final labelW = textWidth(
    label,
    px: metaLabelFontSize,
    weight: metaLabelWeight,
    letterSpacing: metaLabelTracking,
  );
  final valueW = textWidth(
    value,
    px: metaValueFontSize,
    weight: metaValueWeight,
    letterSpacing: metaValueTracking,
  );
  return math.max(labelW, valueW) +
      metaPadX * 2 +
      (bordered ? metaBorderWidth : 0);
}

void _drawMetaColumn(
  ui.Canvas canvas,
  FilmMode mode,
  double x,
  String label,
  String value, {
  required bool bordered,
}) {
  // The design gives every column but the first a 2px left border.
  if (bordered) {
    canvas.drawRect(
      ui.Rect.fromLTWH(x, mode.metaTop, metaBorderWidth, metaHeight),
      ui.Paint()..color = ink,
    );
  }
  final textX = x + (bordered ? metaBorderWidth : 0) + metaPadX;
  drawText(
    canvas,
    label,
    x: textX,
    y: mode.metaLabelTop,
    px: metaLabelFontSize,
    weight: metaLabelWeight,
    letterSpacing: metaLabelTracking,
    color: ink,
  );
  drawText(
    canvas,
    value,
    x: textX,
    y: mode.metaValueTop,
    px: metaValueFontSize,
    weight: metaValueWeight,
    letterSpacing: metaValueTracking,
    color: ink,
  );
}

/// Title block and metadata columns, then the rule that closes the header.
///
/// `frameCount` and `mode` are derived, never typed.
void drawHeader(
  ui.Canvas canvas,
  SheetMeta meta,
  FilmMode mode,
  int frameCount,
) {
  final columns = <(String, String)>[
    ('Photographer', meta.author.trim()),
    ('Date', meta.date.trim()),
    ('Frames', frameCount.toString()),
    ('Format', mode.label),
  ];
  final widths = [
    for (var i = 0; i < columns.length; i++)
      _metaColumnWidth(columns[i].$1, columns[i].$2, bordered: i > 0),
  ];
  final metaWidth =
      widths.reduce((a, b) => a + b) + metaColumnGap * (columns.length - 1);

  // The metadata sizes to its own content, so the title gets whatever is left.
  final titleWidth = sheetWidth - headerPadding * 2 - metaWidth - titleMetaGap;

  drawText(
    canvas,
    meta.name.trim(),
    x: headerPadding,
    y: mode.titleTop,
    px: mode.titleFontSize,
    weight: titleWeight,
    letterSpacing: mode.titleTracking,
    color: ink,
    maxWidth: titleWidth,
    maxLines: 1,
    ellipsis: '…',
  );
  drawText(
    canvas,
    meta.description.trim(),
    x: headerPadding,
    y: mode.descriptionTop,
    px: mode.descriptionFontSize,
    weight: descriptionWeight,
    letterSpacing: mode.descriptionTracking,
    color: ink,
    maxWidth: titleWidth,
    maxLines: 1,
    ellipsis: '…',
  );

  // Right-aligned to x=2900.
  var x = metaRight - metaWidth;
  for (var i = 0; i < columns.length; i++) {
    _drawMetaColumn(
      canvas,
      mode,
      x,
      columns[i].$1,
      columns[i].$2,
      bordered: i > 0,
    );
    x += widths[i] + metaColumnGap;
  }
}

/// The sheet body shared by [composeSheet] and [composeSheetFromCells].
Future<ui.Image> _composeWith(
  int slotCount,
  FilmMode mode,
  SheetMeta meta, {
  required bool Function(int i) hasFrame,
  required void Function(ui.Canvas canvas, int i, double x, double y) drawSlot,
}) async {
  final cw = mode.cellWidth;
  final ch = mode.cellHeight;
  final sheetRect = ui.Rect.fromLTWH(0, 0, sheetWidth, mode.sheetHeight);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, sheetRect);

  canvas.drawRect(sheetRect, ui.Paint()..color = ground);

  final count = math.min(slotCount, mode.capacity);
  drawHeader(canvas, meta, mode, count);

  // Every cell of the grid is drawn, so the sheet is always the format's full
  // height; slots past the last frame get the blank block.
  for (var i = 0; i < mode.capacity; i++) {
    final (x, y) = mode.cellOrigin(i);
    if (i < count && hasFrame(i)) {
      drawSlot(canvas, i, x, y);
      drawNumber(canvas, i + 1, x, y, ch);
    } else {
      canvas.drawRect(
        ui.Rect.fromLTWH(x, y, cw, ch),
        ui.Paint()..color = blank,
      );
      // A frame that failed to decode still holds its slot, so it keeps its
      // number; a slot past the end of the roll has none.
      if (i < count) drawNumber(canvas, i + 1, x, y, ch);
    }
  }

  final picture = recorder.endRecording();
  final sheet = await picture.toImage(
    sheetWidth.round(),
    mode.sheetHeight.round(),
  );
  picture.dispose();
  return sheet;
}

/// Compose the full index sheet. A null entry renders a gray placeholder.
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

/// Compose from cells already cover-fitted by [renderCell].
///
/// Equivalent to [composeSheet]; the cell was rasterized at the rounded size
/// and is drawn into the design's exact fractional rect, so the difference is
/// sub-pixel. This is the path the app uses, letting [SheetService] reuse cells
/// across previews and the final export.
Future<ui.Image> composeSheetFromCells(
  List<ui.Image?> cells,
  FilmMode mode,
  SheetMeta meta,
) => _composeWith(
  cells.length,
  mode,
  meta,
  hasFrame: (i) => cells[i] != null,
  drawSlot: (canvas, i, x, y) {
    final cell = cells[i]!;
    canvas.drawImageRect(
      cell,
      ui.Rect.fromLTWH(0, 0, cell.width.toDouble(), cell.height.toDouble()),
      ui.Rect.fromLTWH(x, y, mode.cellWidth, mode.cellHeight),
      ui.Paint()
        ..filterQuality = ui.FilterQuality.high
        ..isAntiAlias = true,
    );
  },
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

Future<Uint8List> encodeSheet(ui.Image sheet) =>
    encodeJpeg(sheet, outputQuality);

/// Cover-fit one image into a cell and JPEG-encode it for the reorder grid.
Future<Uint8List> makeThumb(ui.Image image, FilmMode mode) async {
  final cell = await renderCell(image, mode);
  try {
    return await encodeJpeg(cell, thumbQuality);
  } finally {
    cell.dispose();
  }
}

/// Downscale a composed sheet for the on-screen preview.
///
/// The sheet's height is per-format, so the preview's is too — it is always
/// half the sheet.
Future<Uint8List> makePreview(ui.Image sheet) async {
  final height = (previewWidth * sheet.height / sheet.width).round();
  final dest = ui.Rect.fromLTWH(
    0,
    0,
    previewWidth.toDouble(),
    height.toDouble(),
  );
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, dest);
  canvas.drawImageRect(
    sheet,
    ui.Rect.fromLTWH(0, 0, sheet.width.toDouble(), sheet.height.toDouble()),
    dest,
    ui.Paint()
      ..filterQuality = ui.FilterQuality.low
      ..isAntiAlias = true,
  );
  final picture = recorder.endRecording();
  final scaled = await picture.toImage(previewWidth, height);
  picture.dispose();
  final bytes = await encodeJpeg(scaled, previewQuality);
  scaled.dispose();
  return bytes;
}
