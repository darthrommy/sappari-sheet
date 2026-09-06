// Grid arithmetic, checked against the Figma design.
//
// Expected values are read from the design's frames — 4:143 (half), 1:2 (35mm),
// 2:88 (645), 2:228 (6x6), 2:301 (6x7) — and their header instances. Figma
// stores coordinates as float32, so its reported numbers carry rounding these
// doubles do not; comparisons allow a thousandth of a pixel.

import 'package:flutter_test/flutter_test.dart';
import 'package:sappari_sheet/core/geometry.dart';

const double eps = 0.001;

/// What each frame measures, straight off the design.
typedef Frame = ({
  int cols,
  int rows,
  double sheetHeight,
  double cellWidth,
  double cellHeight,
  double headerHeight,
  double titleTop,
  double metaTop,
  double titleFontSize,
});

const Map<String, Frame> designed = {
  'half': (
    cols: 13,
    rows: 6,
    sheetHeight: 2250,
    cellWidth: 228.9231,
    cellHeight: 305.2308,
    headerHeight: 408.6154,
    titleTop: 132.3077,
    metaTop: 130.8077,
    titleFontSize: 96,
  ),
  '35mm': (
    cols: 7,
    rows: 6,
    sheetHeight: 2000,
    cellWidth: 426.8571,
    cellHeight: 284.5714,
    headerHeight: 282.5714,
    titleTop: 69.2857,
    metaTop: 67.7857,
    titleFontSize: 96,
  ),
  '645': (
    cols: 6,
    rows: 3,
    sheetHeight: 2250,
    cellWidth: 498.3333,
    cellHeight: 664.4444,
    headerHeight: 252.6667,
    titleTop: 64.3333,
    metaTop: 52.8333,
    titleFontSize: 80,
  ),
  '66': (
    cols: 4,
    rows: 3,
    sheetHeight: 3000,
    cellWidth: 748.5,
    cellHeight: 748.5,
    headerHeight: 750.5,
    titleTop: 281.25,
    metaTop: 301.75,
    titleFontSize: 128,
  ),
  '67': (
    cols: 3,
    rows: 3,
    sheetHeight: 3500,
    cellWidth: 998.6667,
    cellHeight: 856,
    headerHeight: 928,
    titleTop: 370,
    metaTop: 390.5,
    titleFontSize: 128,
  ),
};

void main() {
  group('film mode parsing', () {
    test('parses known ids and rejects unknown ones', () {
      expect(FilmMode.parse('35mm'), FilmMode.full35);
      expect(FilmMode.parse('half'), FilmMode.half);
      expect(FilmMode.parse('645'), FilmMode.f645);
      expect(FilmMode.parse('66'), FilmMode.f66);
      expect(FilmMode.parse('67'), FilmMode.f67);
      expect(
        () => FilmMode.parse('nope'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'unknown film mode: nope',
          ),
        ),
      );
    });

    test('half-frame and 645 are the portrait formats', () {
      expect(FilmMode.half.cellLandscape, isFalse);
      expect(FilmMode.f645.cellLandscape, isFalse);
      expect(FilmMode.full35.cellLandscape, isTrue);
      expect(FilmMode.f66.cellLandscape, isTrue, reason: 'square counts');
      expect(FilmMode.f67.cellLandscape, isTrue);
    });
  });

  group('every format matches its frame', () {
    test('grid, cell and sheet', () {
      for (final mode in FilmMode.values) {
        final w = designed[mode.id]!;
        expect((mode.cols, mode.rows), (w.cols, w.rows), reason: mode.id);
        expect(mode.sheetHeight, w.sheetHeight, reason: mode.id);
        expect(mode.cellWidth, closeTo(w.cellWidth, eps), reason: mode.id);
        expect(mode.cellHeight, closeTo(w.cellHeight, eps), reason: mode.id);
      }
    });

    test('the header is whatever the grid leaves', () {
      for (final mode in FilmMode.values) {
        final w = designed[mode.id]!;
        expect(
          mode.headerHeight,
          closeTo(w.headerHeight, eps),
          reason: mode.id,
        );
        expect(
          mode.headerHeight + mode.gridHeight,
          closeTo(mode.sheetHeight, eps),
          reason: '${mode.id}: header plus grid is the whole sheet',
        );
      }
    });

    test('both header blocks are vertically centred', () {
      for (final mode in FilmMode.values) {
        final w = designed[mode.id]!;
        expect(mode.titleTop, closeTo(w.titleTop, eps), reason: mode.id);
        expect(mode.metaTop, closeTo(w.metaTop, eps), reason: mode.id);
      }
    });

    test('the title scales per format, the metadata does not', () {
      for (final mode in FilmMode.values) {
        final w = designed[mode.id]!;
        expect(mode.titleFontSize, w.titleFontSize, reason: mode.id);
      }
      // 645's short header takes the smallest type, 6x6 and 6x7 the largest.
      expect(FilmMode.f645.titleFontSize, 80);
      expect(FilmMode.full35.titleFontSize, 96);
      expect(FilmMode.f66.titleFontSize, 128);
      // The metadata block is identical everywhere.
      expect(metaHeight, 147);
      expect(metaLabelFontSize, 32);
      expect(metaValueFontSize, 40);
    });

    test('capacities', () {
      expect(FilmMode.half.capacity, 78);
      expect(FilmMode.full35.capacity, 42);
      expect(FilmMode.f645.capacity, 18);
      expect(FilmMode.f66.capacity, 12);
      expect(FilmMode.f67.capacity, 9);
    });
  });

  group('type', () {
    test('tracking is proportional to size', () {
      // -3% on the title, +1% on the description.
      expect(FilmMode.f66.titleTracking, closeTo(-3.84, eps));
      expect(FilmMode.full35.titleTracking, closeTo(-2.88, eps));
      expect(FilmMode.f645.titleTracking, closeTo(-2.4, eps));
      expect(FilmMode.f66.descriptionTracking, closeTo(0.48, eps));
      expect(FilmMode.f645.descriptionTracking, closeTo(0.32, eps));
    });

    test('the title block is title, a 12 gap, then the description', () {
      for (final mode in FilmMode.values) {
        expect(
          mode.titleBlockHeight,
          mode.titleFontSize + 12 + mode.descriptionFontSize,
          reason: mode.id,
        );
        expect(
          mode.descriptionTop - mode.titleTop,
          closeTo(mode.titleFontSize + titleDescriptionGap, eps),
          reason: mode.id,
        );
      }
    });

    test('the number badge is the same at every format', () {
      expect((numberFontSize, numberWeight, numberTracking), (32, 500, -0.96));
      expect((numberPadX, numberPadY), (12, 8));
      expect(numberBoxHeight, 48, reason: '8 + 32 + 8');
    });

    test('the dark palette', () {
      expect(groundValue, 0xFF151515);
      expect(inkValue, 0xFFF0F0F0);
      expect(blankValue, 0xFF242424);
    });
  });

  group('full-bleed grid', () {
    test('cells span the whole sheet width', () {
      for (final mode in FilmMode.values) {
        expect(
          mode.cols * mode.cellWidth + gridGap * (mode.cols - 1),
          closeTo(sheetWidth, eps),
          reason: '${mode.id}: no page padding, cells reach both edges',
        );
      }
    });

    test('the first cell sits at the sheet edge, under the header', () {
      for (final mode in FilmMode.values) {
        final (x, y) = mode.cellOrigin(0);
        expect(x, 0, reason: mode.id);
        expect(y, mode.headerHeight, reason: mode.id);
      }
    });

    test('the last cell ends on the sheet edges', () {
      for (final mode in FilmMode.values) {
        final (x, y) = mode.cellOrigin(mode.capacity - 1);
        expect(x + mode.cellWidth, closeTo(sheetWidth, eps), reason: mode.id);
        expect(
          y + mode.cellHeight,
          closeTo(mode.sheetHeight, eps),
          reason: mode.id,
        );
      }
    });

    test('cell origins step by cell size plus a 2px gutter', () {
      expect(gridGap, 2);
      const mode = FilmMode.full35;
      final (x0, y0) = mode.cellOrigin(0);
      final (x1, _) = mode.cellOrigin(1);
      expect(x1 - x0, closeTo(mode.cellWidth + gridGap, eps));
      // Index 7 wraps to the second row of seven columns.
      final (x7, y7) = mode.cellOrigin(7);
      expect(x7, closeTo(x0, eps));
      expect(y7 - y0, closeTo(mode.cellHeight + gridGap, eps));
    });

    test('cells keep their format aspect', () {
      for (final mode in FilmMode.values) {
        expect(
          mode.cellWidth / mode.cellHeight,
          closeTo(mode.aspect, eps),
          reason: mode.id,
        );
      }
      expect(FilmMode.f66.cellWidth, closeTo(FilmMode.f66.cellHeight, eps));
    });
  });
}
