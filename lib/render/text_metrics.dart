/// Text measurement and drawing on top of `dart:ui`.
///
/// Port of `negadice/src-tauri/src/text.rs` — spec §4.
///
/// The Rust original drives `ab_glyph` directly: it sums per-codepoint
/// horizontal advances with no shaping, and derives an *inked* vertical extent
/// by walking glyph outlines. Flutter has no glyph-outline API, so
/// [visualVBounds] recovers the same quantity by rasterizing the string once
/// and scanning for covered rows. See `docs/DEVIATIONS.md`.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

/// Primary family: Google Sans Flex carries Latin, digits and punctuation.
const String fontFamily = 'Google Sans Flex';

/// Fallback chain. Google Sans Flex has no CJK coverage, so Japanese roll names
/// resolve through Noto Sans JP. Both are bundled, so the chain never reaches
/// a system font and a sheet renders identically on every machine.
const List<String> fontFallback = <String>['Noto Sans JP'];

/// Build a laid-out painter for [text] at [px] pixels.
ui.Paragraph layoutText(
  String text,
  double px, {
  bool bold = false,
  ui.Color color = const ui.Color(0xFF000000),
}) {
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            // dart:ui's ParagraphStyle has no fallback list; the pushed
            // TextStyle below carries it, which is what shaping uses.
            fontFamily: fontFamily,
            fontSize: px,
            fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
            textDirection: ui.TextDirection.ltr,
            // Disable font-declared leading so the layout box hugs ascent+descent,
            // matching `line_height = ascent - descent` in the Rust original.
            textHeightBehavior: const ui.TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
          ),
        )
        ..pushStyle(
          ui.TextStyle(
            color: color,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontSize: px,
          ),
        )
        ..addText(text);
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: double.infinity));
  return paragraph;
}

/// Lay out [text] wrapped to [maxWidth], capped at [maxLines] with an ellipsis.
///
/// Used for the sheet title, where a long roll name should wrap to a second
/// line and then be truncated rather than overrun the metadata columns.
ui.Paragraph layoutWrapped(
  String text,
  double px,
  double maxWidth, {
  int maxLines = 2,
  bool bold = false,
  ui.Color color = const ui.Color(0xFF000000),
}) {
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            // dart:ui's ParagraphStyle has no fallback list; the pushed
            // TextStyle below carries it, which is what shaping uses.
            fontFamily: fontFamily,
            fontSize: px,
            fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
            textDirection: ui.TextDirection.ltr,
            maxLines: maxLines,
            ellipsis: '…',
            height: 1.12,
          ),
        )
        ..pushStyle(
          ui.TextStyle(
            color: color,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontSize: px,
          ),
        )
        ..addText(text);
  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: maxWidth));
  return paragraph;
}

/// Advance width of [text] at [px]. Flutter shapes the run, so this can differ
/// slightly from the Rust naive per-codepoint advance sum.
double textWidth(String text, double px, {bool bold = false}) {
  if (text.isEmpty) return 0;
  final p = layoutText(text, px, bold: bold);
  final w = p.maxIntrinsicWidth;
  p.dispose();
  return w;
}

/// Distance from the top of a line to the baseline at [px].
double ascent(String probe, double px, {bool bold = false}) {
  final p = layoutText(probe.isEmpty ? 'A' : probe, px, bold: bold);
  final a = p.alphabeticBaseline;
  p.dispose();
  return a;
}

/// Height of a line at [px] (ascent to descent).
double lineHeight(String probe, double px, {bool bold = false}) {
  final p = layoutText(probe.isEmpty ? 'A' : probe, px, bold: bold);
  final h = p.height;
  p.dispose();
  return h;
}

/// Actual inked vertical extent of [text] at [px], relative to the baseline
/// (y = 0; `top` is negative, above the baseline).
///
/// Unlike [lineHeight] this ignores the font's ascent/descent padding, so
/// centering by the midpoint of this range balances the glyphs optically — CJK
/// and Latin alike. Falls back to a nominal band when nothing is drawable
/// (e.g. all spaces), exactly as the Rust `visual_v_bounds` does.
Future<(double, double)> visualVBounds(
  String text,
  double px, {
  bool bold = false,
}) async {
  final fallback = (-px * 0.7, 0.0);
  if (text.trim().isEmpty) return fallback;

  final paragraph = layoutText(text, px, bold: bold);
  final baseline = paragraph.alphabeticBaseline;
  final w = paragraph.maxIntrinsicWidth.ceil();
  final h = paragraph.height.ceil();
  if (w <= 0 || h <= 0) {
    paragraph.dispose();
    return fallback;
  }

  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawParagraph(paragraph, ui.Offset.zero);
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  paragraph.dispose();
  if (data == null) return fallback;

  final bytes = data.buffer.asUint8List();
  var top = -1;
  var bottom = -1;
  for (var y = 0; y < h; y++) {
    var inked = false;
    final rowStart = y * w * 4;
    for (var x = 0; x < w; x++) {
      if (bytes[rowStart + x * 4 + 3] != 0) {
        inked = true;
        break;
      }
    }
    if (inked) {
      if (top < 0) top = y;
      bottom = y;
    }
  }
  if (top < 0) return fallback;
  return (top - baseline, bottom + 1 - baseline);
}

/// Draw [text] so its alphabetic baseline sits at [baselineY].
///
/// The Rust original positions by top-left and derives
/// `baseline = y_top + ascent`; positioning by baseline directly is the same
/// placement expressed without the intermediate.
void drawTextAtBaseline(
  ui.Canvas canvas,
  String text,
  double px,
  double x,
  double baselineY,
  ui.Color color, {
  bool bold = false,
}) {
  if (text.isEmpty) return;
  final paragraph = layoutText(text, px, bold: bold, color: color);
  canvas.drawParagraph(
    paragraph,
    ui.Offset(x, baselineY - paragraph.alphabeticBaseline),
  );
  paragraph.dispose();
}

/// Truncate [text] (appending an ellipsis) so it renders no wider than [maxW]
/// at [px]. Returns the text unchanged when it already fits.
///
/// Port of `clip_to_width` — spec §3.5, tier [EXACT]. Note the loop *breaks* on
/// the first character that would overflow; it does not skip and continue.
String clipToWidth(String text, double px, double maxW, {bool bold = false}) {
  if (textWidth(text, px, bold: bold) <= maxW) return text;
  const ellipsis = '…';
  final ellW = textWidth(ellipsis, px, bold: bold);
  final out = StringBuffer();
  var w = 0.0;
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    final cw = textWidth(ch, px, bold: bold);
    if (w + cw + ellW > maxW) break;
    out.write(ch);
    w += cw;
  }
  out.write(ellipsis);
  return out.toString();
}

/// Convert a raw RGBA buffer to RGB, dropping alpha over white.
///
/// The sheet is composed on an opaque white ground, so alpha is always 255;
/// this is a straight repack for the JPEG encoder.
Uint8List rgbaToRgb(Uint8List rgba, int width, int height) {
  final out = Uint8List(width * height * 3);
  for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
    out[j] = rgba[i];
    out[j + 1] = rgba[i + 1];
    out[j + 2] = rgba[i + 2];
  }
  return out;
}
