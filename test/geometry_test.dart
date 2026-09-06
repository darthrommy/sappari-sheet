// Grid arithmetic — spec §2, tier [EXACT].
//
// These pin the Swiss layout's numbers. Cells take their real film aspect and
// frame numbers sit below each cell, so both the dimensions and the origin
// arithmetic differ deliberately from the Tauri original; see
// `docs/DEVIATIONS.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:negadice/core/geometry.dart';

void main() {
  group('film mode parsing and orientation', () {
    test('parses known ids and rejects unknown ones', () {
      expect(FilmMode.parse('35mm'), FilmMode.full35);
      expect(FilmMode.parse('half'), FilmMode.half);
      expect(FilmMode.parse('645'), FilmMode.f645);
      expect(FilmMode.parse('66'), FilmMode.f66);
      expect(FilmMode.parse('67'), FilmMode.f67);
      expect(() => FilmMode.parse('nope'), throwsFormatException);
    });

    test('unknown mode message matches the Rust original', () {
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

    test('half is the only portrait format', () {
      expect(FilmMode.half.cellLandscape, isFalse);
      expect(FilmMode.full35.cellLandscape, isTrue);
      // 6x6 is square, which counts as landscape for the rotation rule.
      expect(FilmMode.f66.cellLandscape, isTrue);
    });
  });

  group('grid geometry', () {
    test('capacities match the spec table', () {
      expect(FilmMode.half.capacity, 72);
      expect(FilmMode.full35.capacity, 42);
      expect(FilmMode.f645.capacity, 16);
      expect(FilmMode.f66.capacity, 12);
      expect(FilmMode.f67.capacity, 12);
    });

    test('cell dimensions match the spec table exactly', () {
      expect((FilmMode.half.cellWidth, FilmMode.half.cellHeight), (174, 232));
      expect(
        (FilmMode.full35.cellWidth, FilmMode.full35.cellHeight),
        (348, 232),
      );
      expect((FilmMode.f645.cellWidth, FilmMode.f645.cellHeight), (497, 368));
      expect((FilmMode.f66.cellWidth, FilmMode.f66.cellHeight), (504, 504));
      expect((FilmMode.f67.cellWidth, FilmMode.f67.cellHeight), (630, 504));
    });

    test('every cell renders at its true film aspect', () {
      for (final mode in FilmMode.values) {
        final actual = mode.cellWidth / mode.cellHeight;
        expect(
          actual,
          closeTo(mode.aspect, 0.005),
          reason: '${mode.id}: cell aspect should be the film aspect',
        );
      }
      // 6x6 is genuinely square, not merely close.
      expect(FilmMode.f66.cellWidth, FilmMode.f66.cellHeight);
    });

    test('every mode grid fits inside the sheet', () {
      for (final mode in FilmMode.values) {
        expect(mode.cellWidth, greaterThan(0), reason: '${mode.id}: width');
        expect(mode.cellHeight, greaterThan(0), reason: '${mode.id}: height');

        final (x, y) = mode.cellOrigin(mode.capacity - 1);
        expect(
          x + mode.cellWidth,
          lessThanOrEqualTo(sheetWidth - margin),
          reason: '${mode.id}: last cell within right margin',
        );
        expect(
          y,
          greaterThanOrEqualTo(margin + headerH),
          reason: '${mode.id}: grid starts below the header',
        );

        // The number sits below the cell, so it is the number — not the cell —
        // that has to clear the bottom margin.
        final (_, baseline) = mode.numberBaseline(mode.capacity - 1);
        expect(
          baseline,
          lessThanOrEqualTo(sheetHeight - margin),
          reason: '${mode.id}: last frame number within bottom margin',
        );
      }
    });

    test('the grid is centred horizontally', () {
      for (final mode in FilmMode.values) {
        final leftGap = mode.gridLeft;
        final rightGap = sheetWidth - (mode.gridLeft + mode.gridWidth);
        expect(
          (leftGap - rightGap).abs(),
          lessThanOrEqualTo(1),
          reason: '${mode.id}: equal margins either side (rounding aside)',
        );
        expect(
          leftGap,
          greaterThanOrEqualTo(margin),
          reason: '${mode.id}: never narrower than the page margin',
        );
      }
    });

    test('35mm fills the content width exactly', () {
      // Both constraints bind at once for 35mm, which is what makes 42 frames
      // at 3:2 fit a 3000x2100 sheet at all.
      expect(FilmMode.full35.gridWidth, contentWidth);
      expect(FilmMode.full35.gridLeft, margin);
    });

    test('cell origin advances by cell size plus gutter', () {
      const mode = FilmMode.full35;
      expect(mode.cellOrigin(0), (mode.gridLeft, margin + headerH));
      expect(mode.cellOrigin(1), (
        mode.gridLeft + mode.cellWidth + gutter,
        margin + headerH,
      ));
      // Index 7 wraps to the second row (7 columns), one row pitch down.
      expect(mode.cellOrigin(7), (
        mode.gridLeft,
        margin + headerH + mode.rowPitch,
      ));
    });

    test('row pitch leaves room for the number under each cell', () {
      for (final mode in FilmMode.values) {
        expect(mode.rowPitch, mode.cellHeight + numberBlock + rowGap);
        final (_, y) = mode.cellOrigin(0);
        final (_, baseline) = mode.numberBaseline(0);
        expect(
          baseline,
          greaterThan(y + mode.cellHeight),
          reason: '${mode.id}: the number sits below the cell, never over it',
        );
        expect(baseline - (y + mode.cellHeight), numberBaselineOffset);
      }
    });

    test('the frame number is flush with its cell', () {
      const mode = FilmMode.full35;
      for (final i in [0, 1, 7, 41]) {
        final (cx, _) = mode.cellOrigin(i);
        final (nx, _) = mode.numberBaseline(i);
        expect(nx, cx, reason: 'number $i is left-aligned to its cell');
      }
    });
  });
}
