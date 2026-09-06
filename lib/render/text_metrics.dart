/// Text layout and drawing on top of `dart:ui`.
///
/// The sheet's typography comes from the Figma design: Google Sans Flex at
/// weights 400/500/600 with per-style letter spacing, every text box laid out
/// at `line-height: 1` so its height equals the font size — which is how the
/// design positions its boxes.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

/// Primary family — carries Latin, digits and punctuation.
const String fontFamily = 'Google Sans Flex';

/// Fallback chain. Google Sans Flex has no CJK coverage, so Japanese resolves
/// through Noto Sans JP. Both are bundled, so the chain never reaches a system
/// font and a sheet renders identically on every machine.
const List<String> fontFallback = <String>['Noto Sans JP'];

ui.FontWeight _weightOf(int weight) => switch (weight) {
  100 => ui.FontWeight.w100,
  200 => ui.FontWeight.w200,
  300 => ui.FontWeight.w300,
  400 => ui.FontWeight.w400,
  500 => ui.FontWeight.w500,
  600 => ui.FontWeight.w600,
  700 => ui.FontWeight.w700,
  800 => ui.FontWeight.w800,
  _ => ui.FontWeight.w900,
};

/// Lay out [text] the way the design specifies a text box.
///
/// `height: 1.0` makes the line box exactly [px] tall, matching the design's
/// `line-height: 1`, so a paragraph drawn at a box's top-left lands where the
/// design puts it.
///
/// `fontVariations` sets the `wght` axis explicitly. Noto Sans JP is bundled as
/// a variable font, where selecting a weight means moving that axis rather than
/// picking a file; Google Sans Flex ships one file per weight and is chosen by
/// [weight] instead. Setting both makes either path work.
ui.Paragraph layout(
  String text, {
  required double px,
  int weight = 400,
  double letterSpacing = 0,
  ui.Color color = const ui.Color(0xFF000000),
  double maxWidth = double.infinity,
  int? maxLines,
  String? ellipsis,
}) {
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            fontFamily: fontFamily,
            fontSize: px,
            fontWeight: _weightOf(weight),
            height: 1.0,
            maxLines: maxLines,
            ellipsis: ellipsis,
            textDirection: ui.TextDirection.ltr,
          ),
        )
        ..pushStyle(
          ui.TextStyle(
            color: color,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontSize: px,
            fontWeight: _weightOf(weight),
            letterSpacing: letterSpacing,
            height: 1.0,
            fontVariations: [ui.FontVariation('wght', weight.toDouble())],
          ),
        )
        ..addText(text);
  return builder.build()..layout(ui.ParagraphConstraints(width: maxWidth));
}

/// Width [text] occupies at these settings.
double textWidth(
  String text, {
  required double px,
  int weight = 400,
  double letterSpacing = 0,
}) {
  if (text.isEmpty) return 0;
  final p = layout(text, px: px, weight: weight, letterSpacing: letterSpacing);
  final w = p.maxIntrinsicWidth;
  p.dispose();
  return w;
}

/// Draw [text] with its box's top-left at ([x], [y]).
void drawText(
  ui.Canvas canvas,
  String text, {
  required double x,
  required double y,
  required double px,
  required ui.Color color,
  int weight = 400,
  double letterSpacing = 0,
  double maxWidth = double.infinity,
  int? maxLines,
  String? ellipsis,
}) {
  if (text.isEmpty) return;
  final paragraph = layout(
    text,
    px: px,
    weight: weight,
    letterSpacing: letterSpacing,
    color: color,
    maxWidth: maxWidth,
    maxLines: maxLines,
    ellipsis: ellipsis,
  );
  canvas.drawParagraph(paragraph, ui.Offset(x, y));
  paragraph.dispose();
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
