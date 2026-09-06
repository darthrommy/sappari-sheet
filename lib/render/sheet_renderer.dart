/// Cell fitting and full-sheet composition: cover-fit cropping, frame-number
/// labels, the memo header, JPEG encoding, and preview thumbnails.
///
/// Port of `negadice/src-tauri/src/render.rs` — spec §3.
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

const double labelPx = 30.0;
const double memoPx = 56.0;

/// The "NOTE" caption.
const double memoCapPx = 26.0;

/// Fixed field height.
const double memoBoxH = 96.0;

/// Inner left/right padding for the value.
const double memoPadX = 22.0;
const double memoBorder = 3.0;

const ui.Color memoInk = ui.Color(0xFF3C3C3C);
const ui.Color memoValueInk = ui.Color(0xFF1E1E1E);
const ui.Color white = ui.Color(0xFFFFFFFF);
const ui.Color black = ui.Color(0xFF000000);
const ui.Color placeholderGray = ui.Color(0xFFCCCCCC);
const ui.Color hairline = ui.Color(0xFFD2D2D2);

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

/// Frame-number label, bottom-right of the cell. Spec §3.3.
Future<void> drawLabel(
  ui.Canvas canvas,
  int frameNum,
  int cx,
  int cy,
  int cw,
  int ch,
) async {
  final text = frameNum.toString().padLeft(2, '0');
  final textW = textWidth(text, labelPx, bold: true).ceilToDouble();
  final textH = lineHeight(text, labelPx, bold: true).ceilToDouble();
  const pad = 6.0;
  final boxW = textW + pad * 2;
  final boxH = textH + pad * 2;
  final bx = cx + cw - boxW - 4;
  final by = cy + ch - boxH - 4;

  // Semi-transparent white background (0.92 alpha) blended over the image.
  canvas.drawRect(
    ui.Rect.fromLTWH(bx, by, boxW, boxH),
    ui.Paint()..color = const ui.Color(0xEBFFFFFF), // 0.92 * 255 = 234.6 -> 235
  );

  final a = ascent(text, labelPx, bold: true);
  drawTextAtBaseline(
    canvas,
    text,
    labelPx,
    bx + pad,
    by + pad + a,
    black,
    bold: true,
  );
}

/// Memo header: the hairline, and when a memo is present the fixed "NOTE"
/// field. Spec §3.4.
Future<void> drawMemo(ui.Canvas canvas, String memoRaw) async {
  // Hairline under the header band to set the memo area apart from the grid.
  // Drawn even when the memo is empty.
  const lineY = margin + headerH - 1;
  canvas.drawRect(
    ui.Rect.fromLTWH(
      margin.toDouble(),
      lineY.toDouble(),
      (sheetWidth - margin * 2).toDouble(),
      1,
    ),
    ui.Paint()..color = hairline,
  );

  final memo = memoRaw.trim();
  if (memo.isEmpty) return;

  // Fixed-size "NOTE" field: a frame of constant width (half the content area)
  // and height, with the caption riding on the top border and the value clipped
  // to fit and centered by its actual glyph extent.
  const double boxX = margin * 1.0;
  const boxY = margin + (headerH - memoBoxH) / 2;
  const boxW = (sheetWidth - margin * 2) / 2;

  // Border: outline only, interior untouched.
  canvas.drawRect(
    ui.Rect.fromLTWH(
      boxX + memoBorder / 2,
      boxY + memoBorder / 2,
      boxW - memoBorder,
      memoBoxH - memoBorder,
    ),
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = memoBorder
      ..color = memoInk,
  );

  // Value: clipped to the inner width, left-aligned, optically centered.
  final value = clipToWidth(memo, memoPx, boxW - memoPadX * 2);
  final (vtop, vbot) = await visualVBounds(value, memoPx);
  final valueBaseline = boxY + memoBoxH / 2 - (vtop + vbot) / 2;
  drawTextAtBaseline(
    canvas,
    value,
    memoPx,
    boxX + memoPadX,
    valueBaseline,
    memoValueInk,
  );

  // "NOTE" caption straddling the top border: white it out, then draw.
  const cap = 'NOTE';
  final capW = textWidth(cap, memoCapPx);
  final capX = boxX + 16.0;
  final (ctop, cbot) = await visualVBounds(cap, memoCapPx);
  final notchX0 = math.max(capX - 8.0, 0.0);
  final notchX1 = math.min(capX + capW + 8.0, sheetWidth.toDouble());
  final notchY0 = math.max(boxY + ctop - 2.0, 0.0);
  final notchY1 = math.min(boxY + cbot + 4.0, sheetHeight.toDouble());
  canvas.drawRect(
    ui.Rect.fromLTRB(notchX0, notchY0, notchX1, notchY1),
    ui.Paint()..color = white,
  );
  final capBaseline = boxY - (ctop + cbot) / 2;
  drawTextAtBaseline(canvas, cap, memoCapPx, capX, capBaseline, memoInk);
}

/// Compose the full index sheet for [mode]. A null entry in [images] renders a
/// gray placeholder (a file that could not be read/decoded). Spec §3.2.
Future<ui.Image> composeSheet(
  List<ui.Image?> images,
  FilmMode mode,
  String memo,
) async {
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
  await drawMemo(canvas, memo);

  final count = math.min(images.length, mode.capacity);
  for (var i = 0; i < count; i++) {
    final (x, y) = mode.cellOrigin(i);
    final slot = images[i];
    if (slot != null) {
      drawCoverCell(canvas, slot, x, y, cw, ch, mode.cellLandscape);
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
    await drawLabel(canvas, i + 1, x, y, cw, ch);
  }

  final picture = recorder.endRecording();
  final sheet = await picture.toImage(sheetWidth, sheetHeight);
  picture.dispose();
  return sheet;
}

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

/// Cover-fit one image into a cell and JPEG-encode it for the reorder grid.
Future<Uint8List> makeThumb(ui.Image image, FilmMode mode) async {
  final cw = mode.cellWidth;
  final ch = mode.cellHeight;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
  );
  drawCoverCell(canvas, image, 0, 0, cw, ch, mode.cellLandscape);
  final picture = recorder.endRecording();
  final cell = await picture.toImage(cw, ch);
  picture.dispose();
  final bytes = await encodeJpeg(cell, thumbQuality);
  cell.dispose();
  return bytes;
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
