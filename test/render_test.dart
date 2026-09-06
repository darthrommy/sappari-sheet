// Translation of the `#[cfg(test)] mod tests` in
// `negadice/src-tauri/src/render.rs` and `text.rs` — spec §8.
//
// These exercise the real dart:ui raster path, including the bundled CJK font,
// so they are the acceptance criteria for the port's visual output.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:negadice/core/geometry.dart';
import 'package:negadice/render/sheet_renderer.dart';
import 'package:negadice/render/text_metrics.dart';

/// Load the bundled UDEV Gothic faces so text tests exercise the real font
/// rather than the test harness's placeholder.
Future<void> loadFonts() async {
  final loader = FontLoader(fontFamily)
    ..addFont(rootBundle.load('assets/fonts/UDEVGothic35JPDOC-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/UDEVGothic35JPDOC-Bold.ttf'));
  await loader.load();
}

Future<ui.Image> solid(int w, int h, int r, int g, int b) {
  final pixels = Uint8List(w * h * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = r;
    pixels[i + 1] = g;
    pixels[i + 2] = b;
    pixels[i + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

class Pixels {
  Pixels(this.bytes, this.width);
  final Uint8List bytes;
  final int width;

  (int, int, int) at(int x, int y) {
    final i = (y * width + x) * 4;
    return (bytes[i], bytes[i + 1], bytes[i + 2]);
  }
}

Future<Pixels> pixelsOf(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return Pixels(data!.buffer.asUint8List(), image.width);
}

int darkPixelsInHeader(Pixels p) {
  var count = 0;
  for (var y = margin; y < margin + headerH - 1; y++) {
    for (var x = margin; x < sheetWidth - margin; x++) {
      final (r, g, b) = p.at(x, y);
      if (r < 128 && g < 128 && b < 128) count++;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadFonts);

  group('text', () {
    test('fonts load and advance for Latin and Japanese', () {
      expect(textWidth('42', 30, bold: true), greaterThan(0));
      // The bundled JPDOC face covers Japanese glyphs.
      expect(textWidth('テスト', 40), greaterThan(0));
    });

    test(
      'inked bounds sit above the baseline and fall back on blanks',
      () async {
        final (top, bottom) = await visualVBounds('NOTE', 26);
        expect(top, lessThan(0), reason: 'ink extends above the baseline');
        expect(bottom, greaterThan(top));
        // All-space input has nothing drawable and uses the nominal band.
        final (ftop, fbot) = await visualVBounds('   ', 26);
        expect(ftop, closeTo(-26 * 0.7, 0.001));
        expect(fbot, 0.0);
      },
    );

    test('Japanese and Latin both produce ink', () async {
      final (jtop, jbot) = await visualVBounds('テスト', 56);
      expect(jbot - jtop, greaterThan(0));
      final (ltop, lbot) = await visualVBounds('Roll', 56);
      expect(lbot - ltop, greaterThan(0));
    });
  });

  group('clipToWidth', () {
    test('truncates with an ellipsis only when needed', () {
      const text = 'Kodak ProImage 100 Extra Long Roll Name';
      final full = textWidth(text, memoPx);
      // Fits: returned unchanged.
      expect(clipToWidth(text, memoPx, full + 10), text);
      // Does not fit: shorter, ellipsized, and within the budget.
      final clipped = clipToWidth(text, memoPx, full / 2);
      expect(clipped.endsWith('…'), isTrue);
      expect(clipped.runes.length, lessThan(text.runes.length));
      expect(textWidth(clipped, memoPx), lessThanOrEqualTo(full / 2));
    });
  });

  group('cover fit', () {
    test('output matches the cell size and orientation', () async {
      const landscape = FilmMode.full35;
      final portraitSource = await solid(300, 400, 0, 255, 0);
      final thumbBytes = await makeThumb(portraitSource, landscape);
      final decoded = img.decodeJpg(thumbBytes)!;
      expect(decoded.width, landscape.cellWidth);
      expect(decoded.height, landscape.cellHeight);
      portraitSource.dispose();

      const portrait = FilmMode.half;
      final landscapeSource = await solid(400, 300, 255, 0, 0);
      final halfBytes = await makeThumb(landscapeSource, portrait);
      final halfDecoded = img.decodeJpg(halfBytes)!;
      expect(halfDecoded.width, portrait.cellWidth);
      expect(halfDecoded.height, portrait.cellHeight);
      landscapeSource.dispose();
    });

    test('source rect is centered and respects the cover scale', () async {
      // 400x300 into a 380x272 landscape cell: cover scale is height-driven.
      final image = await solid(400, 300, 0, 0, 0);
      final rect = coverSourceRect(image, 380, 272, true);
      expect(rect.center.dx, closeTo(200, 0.001));
      expect(rect.center.dy, closeTo(150, 0.001));
      expect(rect.width, lessThanOrEqualTo(400.001));
      expect(rect.height, lessThanOrEqualTo(300.001));
      image.dispose();
    });
  });

  group('compose', () {
    test('places cells and leaves unfilled slots white', () async {
      final images = <ui.Image?>[
        await solid(400, 300, 255, 0, 0),
        await solid(400, 300, 0, 255, 0),
        await solid(400, 300, 0, 0, 255),
      ];
      final sheet = await composeSheet(images, FilmMode.full35, '');
      expect(sheet.width, sheetWidth);
      expect(sheet.height, sheetHeight);

      final p = await pixelsOf(sheet);
      expect(p.at(0, 0), (255, 255, 255), reason: 'sheet corner is white');

      const mode = FilmMode.full35;
      final expected = [(255, 0, 0), (0, 255, 0), (0, 0, 255)];
      for (var i = 0; i < expected.length; i++) {
        final (x, y) = mode.cellOrigin(i);
        final center = p.at(x + mode.cellWidth ~/ 2, y + mode.cellHeight ~/ 2);
        expect(center, expected[i], reason: 'cell $i center color');
      }

      final (ux, uy) = mode.cellOrigin(10);
      expect(p.at(ux + mode.cellWidth ~/ 2, uy + mode.cellHeight ~/ 2), (
        255,
        255,
        255,
      ), reason: 'unfilled cell stays white');

      for (final image in images) {
        image?.dispose();
      }
      sheet.dispose();
    });

    test('a missing image draws a gray placeholder', () async {
      final sheet = await composeSheet(<ui.Image?>[null], FilmMode.full35, '');
      const mode = FilmMode.full35;
      final (x, y) = mode.cellOrigin(0);
      final p = await pixelsOf(sheet);
      expect(p.at(x + mode.cellWidth ~/ 2, y + mode.cellHeight ~/ 2), (
        204,
        204,
        204,
      ));
      sheet.dispose();
    });

    test('the label paints over the image', () async {
      final image = await solid(400, 300, 200, 0, 0);
      final sheet = await composeSheet(<ui.Image?>[image], FilmMode.full35, '');
      const mode = FilmMode.full35;
      final (x, y) = mode.cellOrigin(0);
      final p = await pixelsOf(sheet);

      var bright = false;
      for (var yy = y + mode.cellHeight - 40; yy < y + mode.cellHeight; yy++) {
        for (var xx = x + mode.cellWidth - 60; xx < x + mode.cellWidth; xx++) {
          final (r, g, b) = p.at(xx, yy);
          if (r > 220 && g > 220 && b > 220) bright = true;
        }
      }
      expect(
        bright,
        isTrue,
        reason: 'label draws a white box over the red cell',
      );
      image.dispose();
      sheet.dispose();
    });

    test('the label box sits in the bottom-right corner of the cell', () async {
      final image = await solid(400, 300, 0, 0, 0);
      final sheet = await composeSheet(<ui.Image?>[image], FilmMode.full35, '');
      const mode = FilmMode.full35;
      final (x, y) = mode.cellOrigin(0);
      final p = await pixelsOf(sheet);
      // Top-left of the same cell must still be the black image, proving the
      // label is corner-anchored rather than filling the cell.
      expect(p.at(x + 4, y + 4), (0, 0, 0));
      sheet.dispose();
      image.dispose();
    });
  });

  group('memo header', () {
    test('renders Japanese text in the header band', () async {
      final blank = await composeSheet(
        const <ui.Image?>[],
        FilmMode.full35,
        '',
      );
      expect(darkPixelsInHeader(await pixelsOf(blank)), 0);
      blank.dispose();

      final noted = await composeSheet(
        const <ui.Image?>[],
        FilmMode.full35,
        'テストロール 2024',
      );
      expect(
        darkPixelsInHeader(await pixelsOf(noted)),
        greaterThan(100),
        reason: 'memo text should paint dark glyph pixels in the header band',
      );
      noted.dispose();
    });

    test('the hairline is drawn even with an empty memo', () async {
      final sheet = await composeSheet(
        const <ui.Image?>[],
        FilmMode.full35,
        '',
      );
      final p = await pixelsOf(sheet);
      final (r, g, b) = p.at(sheetWidth ~/ 2, margin + headerH - 1);
      expect(r, closeTo(210, 2));
      expect(g, closeTo(210, 2));
      expect(b, closeTo(210, 2));
      sheet.dispose();
    });

    test('the NOTE border outlines without filling the interior', () async {
      final sheet = await composeSheet(
        const <ui.Image?>[],
        FilmMode.full35,
        'roll',
      );
      final p = await pixelsOf(sheet);
      const boxX = margin;
      const boxY = margin + (headerH - 96) ~/ 2;
      const boxW = (sheetWidth - margin * 2) ~/ 2;

      // Left border is inked; a point inside the field but clear of the value
      // text remains white.
      final (lr, lg, lb) = p.at(boxX + 1, boxY + 48);
      expect(
        lr < 128 && lg < 128 && lb < 128,
        isTrue,
        reason: 'left border inked',
      );
      expect(p.at(boxX + boxW - 40, boxY + 90), (
        255,
        255,
        255,
      ), reason: 'field interior untouched');
      sheet.dispose();
    });
  });

  group('encoding', () {
    test('the encoded sheet round-trips its dimensions', () async {
      final image = await solid(400, 300, 123, 222, 64);
      final sheet = await composeSheet(
        <ui.Image?>[image],
        FilmMode.f66,
        'roll',
      );
      final jpeg = await encodeSheet(sheet);
      final decoded = img.decodeJpg(jpeg)!;
      expect(decoded.width, sheetWidth);
      expect(decoded.height, sheetHeight);
      image.dispose();
      sheet.dispose();
    });

    test('the preview is a half-size JPEG', () async {
      final image = await solid(400, 300, 80, 120, 160);
      final sheet = await composeSheet(<ui.Image?>[image], FilmMode.full35, '');
      final bytes = await makePreview(sheet);
      final decoded = img.decodeJpg(bytes)!;
      expect(
        (decoded.width, decoded.height),
        (1500, 1050),
        reason: 'half-size preview',
      );
      image.dispose();
      sheet.dispose();
    });

    test('the thumbnail matches the mode cell size', () async {
      final image = await solid(400, 300, 10, 10, 10);
      final bytes = await makeThumb(image, FilmMode.half);
      final decoded = img.decodeJpg(bytes)!;
      expect(decoded.width, FilmMode.half.cellWidth);
      expect(decoded.height, FilmMode.half.cellHeight);
      image.dispose();
    });
  });
}
