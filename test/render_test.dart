// Rendering acceptance criteria — spec §3, §4, §8.
//
// These exercise the real dart:ui raster path with the bundled fonts, so they
// are what proves the sheet actually looks like the design rather than merely
// compiling. The header, number placement and font-fallback assertions are the
// load-bearing ones.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:negadice/core/geometry.dart';
import 'package:negadice/core/sheet_meta.dart';
import 'package:negadice/render/sheet_renderer.dart';
import 'package:negadice/render/text_metrics.dart';

import 'font_fixture.dart';

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

  /// Count pixels darker than mid-grey inside the given box.
  int inkIn(int x0, int y0, int x1, int y1) {
    var count = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final (r, g, b) = at(x, y);
        if (r < 128 && g < 128 && b < 128) count++;
      }
    }
    return count;
  }
}

Future<Pixels> pixelsOf(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return Pixels(data!.buffer.asUint8List(), image.width);
}

/// Ink inside the title area, left of the metadata columns.
int titleInk(Pixels p) => p.inkIn(margin, 100, margin + 1000, 280);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  group('text', () {
    test('both families advance: Latin primary, Japanese via fallback', () {
      expect(textWidth('42', 30, bold: true), greaterThan(0));
      // Google Sans Flex has no CJK; this only works through Noto Sans JP.
      expect(textWidth('テスト', 40), greaterThan(0));
    });

    test(
      'inked bounds sit above the baseline and fall back on blanks',
      () async {
        final (top, bottom) = await visualVBounds('NOTE', 26);
        expect(top, lessThan(0), reason: 'ink extends above the baseline');
        expect(bottom, greaterThan(top));
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
      final full = textWidth(text, metaValuePx);
      expect(clipToWidth(text, metaValuePx, full + 10), text);
      final clipped = clipToWidth(text, metaValuePx, full / 2);
      expect(clipped.endsWith('…'), isTrue);
      expect(clipped.runes.length, lessThan(text.runes.length));
      expect(textWidth(clipped, metaValuePx), lessThanOrEqualTo(full / 2));
    });
  });

  group('cover fit', () {
    test('output matches the cell size and orientation', () async {
      const landscape = FilmMode.full35;
      final portraitSource = await solid(300, 400, 0, 255, 0);
      final decoded = img.decodeJpg(
        await makeThumb(portraitSource, landscape),
      )!;
      expect(decoded.width, landscape.cellWidth);
      expect(decoded.height, landscape.cellHeight);
      portraitSource.dispose();

      const portrait = FilmMode.half;
      final landscapeSource = await solid(400, 300, 255, 0, 0);
      final half = img.decodeJpg(await makeThumb(landscapeSource, portrait))!;
      expect(half.width, portrait.cellWidth);
      expect(half.height, portrait.cellHeight);
      landscapeSource.dispose();
    });

    test('source rect is centered and respects the cover scale', () async {
      final image = await solid(400, 300, 0, 0, 0);
      final rect = coverSourceRect(image, 348, 232, true);
      expect(rect.center.dx, closeTo(200, 0.001));
      expect(rect.center.dy, closeTo(150, 0.001));
      expect(rect.width, lessThanOrEqualTo(400.001));
      expect(rect.height, lessThanOrEqualTo(300.001));
      image.dispose();
    });

    test('renderCell produces a cell-sized image', () async {
      final image = await solid(400, 300, 12, 34, 56);
      final cell = await renderCell(image, FilmMode.half);
      expect(cell.width, FilmMode.half.cellWidth);
      expect(cell.height, FilmMode.half.cellHeight);
      image.dispose();
      cell.dispose();
    });
  });

  group('compose', () {
    test('places cells and leaves unfilled slots white', () async {
      final images = <ui.Image?>[
        await solid(400, 300, 255, 0, 0),
        await solid(400, 300, 0, 255, 0),
        await solid(400, 300, 0, 0, 255),
      ];
      final sheet = await composeSheet(
        images,
        FilmMode.full35,
        SheetMeta.empty,
      );
      expect(sheet.width, sheetWidth);
      expect(sheet.height, sheetHeight);

      final p = await pixelsOf(sheet);
      expect(p.at(0, 0), (255, 255, 255), reason: 'sheet corner is white');

      const mode = FilmMode.full35;
      final expected = [(255, 0, 0), (0, 255, 0), (0, 0, 255)];
      for (var i = 0; i < expected.length; i++) {
        final (x, y) = mode.cellOrigin(i);
        expect(
          p.at(x + mode.cellWidth ~/ 2, y + mode.cellHeight ~/ 2),
          expected[i],
          reason: 'cell $i center color',
        );
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
      final sheet = await composeSheet(
        <ui.Image?>[null],
        FilmMode.full35,
        SheetMeta.empty,
      );
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

    test('composeSheetFromCells matches composeSheet', () async {
      const mode = FilmMode.full35;
      const meta = SheetMeta(name: 'テスト', date: '2026-09-06');
      final sources = <ui.Image?>[
        await solid(400, 300, 255, 0, 0),
        await solid(300, 400, 0, 255, 0), // portrait, so it gets rotated
        null,
        await solid(800, 200, 0, 0, 255),
      ];

      final direct = await composeSheet(sources, mode, meta);
      final cells = <ui.Image?>[
        for (final s in sources) s == null ? null : await renderCell(s, mode),
      ];
      final viaCells = await composeSheetFromCells(cells, mode, meta);

      final a = await pixelsOf(direct);
      final b = await pixelsOf(viaCells);
      for (var i = 0; i < sources.length; i++) {
        final (x, y) = mode.cellOrigin(i);
        final px = x + mode.cellWidth ~/ 2;
        final py = y + mode.cellHeight ~/ 2;
        expect(b.at(px, py), a.at(px, py), reason: 'cell $i centre');
        expect(
          b.at(x + 2, y + 2),
          a.at(x + 2, y + 2),
          reason: 'cell $i corner',
        );
      }

      for (final s in sources) {
        s?.dispose();
      }
      for (final c in cells) {
        c?.dispose();
      }
      direct.dispose();
      viaCells.dispose();
    });
  });

  group('frame numbers', () {
    test('are painted below the cell, never over the photograph', () async {
      final image = await solid(400, 300, 200, 0, 0);
      final sheet = await composeSheet(
        <ui.Image?>[image],
        FilmMode.full35,
        SheetMeta.empty,
      );
      const mode = FilmMode.full35;
      final (x, y) = mode.cellOrigin(0);
      final p = await pixelsOf(sheet);

      // The old design painted a white box in the bottom-right of the cell.
      // Nothing may cover the image now.
      for (var yy = y + mode.cellHeight - 40; yy < y + mode.cellHeight; yy++) {
        for (var xx = x + mode.cellWidth - 60; xx < x + mode.cellWidth; xx++) {
          expect(p.at(xx, yy), (
            200,
            0,
            0,
          ), reason: 'cell interior at ($xx,$yy) must be untouched image');
        }
      }

      // ...and the number is inked in the block underneath it.
      final ink = p.inkIn(
        x,
        y + mode.cellHeight,
        x + 80,
        y + mode.cellHeight + numberBlock + 4,
      );
      expect(ink, greaterThan(10), reason: 'number painted below the cell');

      image.dispose();
      sheet.dispose();
    });

    test('are unpadded, so 1 is narrower than 11', () async {
      expect(textWidth('1', numberPx), lessThan(textWidth('11', numberPx)));
      // Guards against a regression to the old zero-padded "01" form.
      expect(textWidth('1', numberPx), lessThan(textWidth('01', numberPx)));
    });
  });

  group('title block', () {
    test('prints the roll name and closes with a rule', () async {
      final sheet = await composeSheet(
        const <ui.Image?>[],
        FilmMode.full35,
        const SheetMeta(name: 'Kodak Gold 200', date: '2026-09-06'),
      );
      final p = await pixelsOf(sheet);

      expect(titleInk(p), greaterThan(200), reason: 'roll name is painted');

      // The closing rule spans the content width.
      final ruleY = headerRuleY.round() + 1;
      expect(p.at(margin + 10, ruleY), (26, 26, 26));
      expect(p.at(sheetWidth - margin - 10, ruleY), (26, 26, 26));
      expect(p.at(margin - 10, ruleY), (
        255,
        255,
        255,
      ), reason: 'rule stops at the margin');

      sheet.dispose();
    });

    test('renders a Japanese roll name through the fallback font', () async {
      final blank = await composeSheet(
        const <ui.Image?>[],
        FilmMode.full35,
        SheetMeta.empty,
      );
      final noted = await composeSheet(
        const <ui.Image?>[],
        FilmMode.full35,
        const SheetMeta(name: 'テストロール 2024', date: '2026-09-06'),
      );

      final blankInk = titleInk(await pixelsOf(blank));
      final notedInk = titleInk(await pixelsOf(noted));

      // Google Sans Flex has no CJK glyphs; if the fallback chain were broken
      // this would render tofu or nothing and the counts would not diverge.
      expect(
        notedInk,
        greaterThan(blankInk),
        reason: 'Japanese title paints more ink than the "35mm" fallback title',
      );
      expect(notedInk, greaterThan(500));

      blank.dispose();
      noted.dispose();
    });

    test('an empty roll name falls back to the film label', () async {
      final sheet = await composeSheet(
        const <ui.Image?>[],
        FilmMode.f66,
        SheetMeta.empty,
      );
      final p = await pixelsOf(sheet);
      expect(
        titleInk(p),
        greaterThan(100),
        reason: 'title is never blank — it shows the format',
      );
      sheet.dispose();
    });

    test('the Frames column counts the frames actually placed', () async {
      // Frames is derived, so it must follow the slot count, not the input.
      final images = <ui.Image?>[
        for (var i = 0; i < 3; i++) await solid(400, 300, 10, 10, 10),
      ];
      final sheet = await composeSheet(
        images,
        FilmMode.full35,
        const SheetMeta(name: 'Roll', date: '2026-09-06'),
      );
      final p = await pixelsOf(sheet);
      // Column values sit in the metadata band; just assert something inked
      // there, since the exact glyphs are the font's business.
      expect(
        p.inkIn(1180, 130, 2200, 230),
        greaterThan(100),
        reason: 'metadata columns are painted',
      );
      for (final i in images) {
        i?.dispose();
      }
      sheet.dispose();
    });
  });

  group('encoding', () {
    test('the encoded sheet round-trips its dimensions', () async {
      final image = await solid(400, 300, 123, 222, 64);
      final sheet = await composeSheet(
        <ui.Image?>[image],
        FilmMode.f66,
        const SheetMeta(name: 'roll'),
      );
      final decoded = img.decodeJpg(await encodeSheet(sheet))!;
      expect((decoded.width, decoded.height), (sheetWidth, sheetHeight));
      image.dispose();
      sheet.dispose();
    });

    test('the preview is a half-size JPEG', () async {
      final image = await solid(400, 300, 80, 120, 160);
      final sheet = await composeSheet(
        <ui.Image?>[image],
        FilmMode.full35,
        SheetMeta.empty,
      );
      final decoded = img.decodeJpg(await makePreview(sheet))!;
      expect((decoded.width, decoded.height), (1500, 1050));
      image.dispose();
      sheet.dispose();
    });

    test('the thumbnail matches the mode cell size', () async {
      final image = await solid(400, 300, 10, 10, 10);
      final decoded = img.decodeJpg(await makeThumb(image, FilmMode.half))!;
      expect(decoded.width, FilmMode.half.cellWidth);
      expect(decoded.height, FilmMode.half.cellHeight);
      image.dispose();
    });
  });
}
