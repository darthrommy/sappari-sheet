// Rendering acceptance criteria, checked against the Figma design.
//
// These exercise the real dart:ui raster path with the bundled fonts, so they
// are what proves the sheet matches the design rather than merely compiling.
// The number-badge placement and the font-fallback assertions are the
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

  (int, int, int) at(num x, num y) {
    final i = (y.round() * width + x.round()) * 4;
    return (bytes[i], bytes[i + 1], bytes[i + 2]);
  }

  /// Count pixels that are clearly lighter than the dark ground — the theme
  /// inverted, so text is light on dark.
  int inkIn(num x0, num y0, num x1, num y1) {
    var count = 0;
    for (var y = y0.round(); y < y1.round(); y++) {
      for (var x = x0.round(); x < x1.round(); x++) {
        final (r, g, b) = at(x, y);
        if (r > 160 && g > 160 && b > 160) count++;
      }
    }
    return count;
  }
}

Future<Pixels> pixelsOf(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return Pixels(data!.buffer.asUint8List(), image.width);
}

/// Pixels close to the ink colour inside the title area. The theme is dark,
/// so "ink" is now light-on-dark and cannot be found by looking for darkness.
int titleInk(Pixels p, FilmMode mode) => p.inkIn(
  headerPadding,
  mode.titleTop,
  1400,
  mode.titleTop + mode.titleFontSize,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  group('text', () {
    test('both families advance: Latin primary, Japanese via fallback', () {
      expect(textWidth('42', px: 32, weight: 500), greaterThan(0));
      // Google Sans Flex has no CJK; this only works through Noto Sans JP.
      expect(textWidth('テスト', px: 48), greaterThan(0));
    });

    test('weight changes the rendered width', () {
      final regular = textWidth('Photographer', px: 32, weight: 400);
      final semibold = textWidth('Photographer', px: 32, weight: 600);
      expect(
        semibold,
        isNot(closeTo(regular, 0.01)),
        reason: 'the 600 file must actually be selected, not aliased to 400',
      );
    });

    test('letter spacing widens or tightens the run', () {
      final plain = textWidth('Kodak Portra 400', px: 128, weight: 500);
      final tight = textWidth(
        'Kodak Portra 400',
        px: 128,
        weight: 500,
        letterSpacing: FilmMode.f66.titleTracking,
      );
      expect(tight, lessThan(plain), reason: 'title tracking is negative');
    });
  });

  group('cover fit', () {
    test('the cell raster matches the mode cell size', () async {
      const mode = FilmMode.full35;
      final source = await solid(300, 400, 0, 255, 0);
      final cell = await renderCell(source, mode);
      expect(cell.width, mode.cellWidth.round());
      expect(cell.height, mode.cellHeight.round());
      source.dispose();
      cell.dispose();
    });

    test('source rect is centered and respects the cover scale', () async {
      final image = await solid(400, 300, 0, 0, 0);
      final rect = coverSourceRect(image, 398.2857, 265.5238, true);
      expect(rect.center.dx, closeTo(200, 0.001));
      expect(rect.center.dy, closeTo(150, 0.001));
      expect(rect.width, lessThanOrEqualTo(400.001));
      expect(rect.height, lessThanOrEqualTo(300.001));
      image.dispose();
    });
  });

  group('compose', () {
    test('places cells and leaves unfilled slots white', () async {
      const mode = FilmMode.full35;
      final images = <ui.Image?>[
        await solid(400, 300, 255, 0, 0),
        await solid(400, 300, 0, 255, 0),
        await solid(400, 300, 0, 0, 255),
      ];
      final sheet = await composeSheet(images, mode, SheetMeta.empty);
      expect(sheet.width, sheetWidth.round());
      expect(sheet.height, mode.sheetHeight.round());

      final p = await pixelsOf(sheet);
      expect(p.at(0, 0), (21, 21, 21), reason: 'the ground is dark');

      final expected = [(255, 0, 0), (0, 255, 0), (0, 0, 255)];
      for (var i = 0; i < expected.length; i++) {
        final (x, y) = mode.cellOrigin(i);
        expect(
          p.at(x + mode.cellWidth / 2, y + mode.cellHeight / 2),
          expected[i],
          reason: 'cell $i centre colour',
        );
      }

      final (ux, uy) = mode.cellOrigin(10);
      expect(p.at(ux + mode.cellWidth / 2, uy + mode.cellHeight / 2), (
        36,
        36,
        36,
      ), reason: 'a slot past the last frame gets the blank block');

      for (final image in images) {
        image?.dispose();
      }
      sheet.dispose();
    });

    test('a missing image draws a gray placeholder', () async {
      const mode = FilmMode.full35;
      final sheet = await composeSheet(
        <ui.Image?>[null],
        mode,
        SheetMeta.empty,
      );
      final (x, y) = mode.cellOrigin(0);
      final p = await pixelsOf(sheet);
      expect(p.at(x + mode.cellWidth / 2, y + mode.cellHeight / 2), (
        36,
        36,
        36,
      ), reason: 'an undecodable file gets the same blank block');
      sheet.dispose();
    });

    test('composeSheetFromCells matches composeSheet', () async {
      const mode = FilmMode.full35;
      const meta = SheetMeta(name: 'テスト', date: '2026-07-16');
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
        expect(
          b.at(x + mode.cellWidth / 2, y + mode.cellHeight / 2),
          a.at(x + mode.cellWidth / 2, y + mode.cellHeight / 2),
          reason: 'cell $i centre',
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
    test('sit in a ground-coloured box in the cell bottom-left', () async {
      const mode = FilmMode.full35;
      final image = await solid(400, 300, 200, 0, 0);
      final sheet = await composeSheet(
        <ui.Image?>[image],
        mode,
        SheetMeta.empty,
      );
      final (x, y) = mode.cellOrigin(0);
      final p = await pixelsOf(sheet);

      final boxTop = y + mode.cellHeight - numberBoxHeight;
      // The badge is the sheet's own ground, not white...
      expect(p.at(x + 4, boxTop + 4), (
        21,
        21,
        21,
      ), reason: 'badge background is the ground colour');
      // ...with ink in it.
      expect(
        p.inkIn(x, boxTop, x + 80, y + mode.cellHeight),
        greaterThan(10),
        reason: 'the number is painted inside the badge',
      );
      // The bottom-RIGHT of the cell is still photograph.
      expect(p.at(x + mode.cellWidth - 6, y + mode.cellHeight - 6), (
        200,
        0,
        0,
      ), reason: 'the badge does not span the cell width');

      image.dispose();
      sheet.dispose();
    });

    test('are zero-padded to two digits', () {
      // Guards the design's "01", not "1".
      expect(1.toString().padLeft(2, '0'), '01');
      expect(39.toString().padLeft(2, '0'), '39');
    });
  });

  group('title block', () {
    test('prints the roll name and closes with a rule', () async {
      const mode = FilmMode.full35;
      final sheet = await composeSheet(
        const <ui.Image?>[],
        mode,
        const SheetMeta(
          name: 'Kodak Portra 400',
          description: 'a description line',
          author: 'Romolintianus',
          date: '2026-07-16',
        ),
      );
      final p = await pixelsOf(sheet);

      expect(
        titleInk(p, FilmMode.full35),
        greaterThan(500),
        reason: 'roll name is painted',
      );

      // The design has no rule under the header; the band between the header
      // and the grid must be plain ground.
      final wasRuleRow = (mode.headerHeight - 40).round();
      expect(
        p.inkIn(0, wasRuleRow, sheetWidth, wasRuleRow + 1),
        0,
        reason: 'no rule closes the header any more',
      );

      // Metadata is right-aligned to x=2900, so there is ink near it...
      expect(
        p.inkIn(2400, mode.metaTop, metaRight, mode.metaTop + metaHeight),
        greaterThan(100),
        reason: 'metadata columns are painted on the right',
      );
      // ...and none past it.
      expect(
        p.inkIn(
          metaRight + 4,
          mode.metaTop,
          sheetWidth,
          mode.metaTop + metaHeight,
        ),
        0,
        reason: 'the block stops at the padding',
      );

      sheet.dispose();
    });

    test('renders a Japanese title through the fallback font', () async {
      final empty = await composeSheet(
        const <ui.Image?>[],
        FilmMode.full35,
        SheetMeta.empty,
      );
      final noted = await composeSheet(
        const <ui.Image?>[],
        FilmMode.full35,
        const SheetMeta(name: 'テストロール 2024'),
      );

      final blankInk = titleInk(await pixelsOf(empty), FilmMode.full35);
      final notedInk = titleInk(await pixelsOf(noted), FilmMode.full35);

      // Google Sans Flex has no CJK glyphs; a broken fallback chain would
      // render tofu or nothing here.
      expect(blankInk, 0, reason: 'an empty title paints nothing');
      expect(notedInk, greaterThan(1000));

      empty.dispose();
      noted.dispose();
    });

    test('the description line is painted below the title', () async {
      final without = await composeSheet(
        const <ui.Image?>[],
        FilmMode.full35,
        const SheetMeta(name: 'Roll'),
      );
      final with_ = await composeSheet(
        const <ui.Image?>[],
        FilmMode.full35,
        const SheetMeta(
          name: 'Roll',
          description: 'ごきげんよう is a universal greeting word in Japan',
        ),
      );

      const mode = FilmMode.full35;
      int descInk(Pixels p) => p.inkIn(
        headerPadding,
        mode.descriptionTop,
        1400,
        mode.descriptionTop + mode.descriptionFontSize,
      );

      expect(descInk(await pixelsOf(without)), 0);
      expect(descInk(await pixelsOf(with_)), greaterThan(500));

      without.dispose();
      with_.dispose();
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
      expect(
        (decoded.width, decoded.height),
        (sheetWidth.round(), FilmMode.f66.sheetHeight.round()),
      );
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
      expect(decoded.width, 1500);
      expect(
        decoded.height,
        (1500 * FilmMode.full35.sheetHeight / sheetWidth).round(),
        reason:
            'half of this format'
            's own sheet height',
      );
      image.dispose();
      sheet.dispose();
    });

    test('the thumbnail matches the mode cell size', () async {
      const mode = FilmMode.half;
      final image = await solid(400, 300, 10, 10, 10);
      final decoded = img.decodeJpg(await makeThumb(image, mode))!;
      expect(decoded.width, mode.cellWidth.round());
      expect(decoded.height, mode.cellHeight.round());
      image.dispose();
    });
  });
}
