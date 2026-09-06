// Translation of the `#[cfg(test)] mod tests` in
// `negadice/src-tauri/src/geometry.rs`, plus the exact cell dimensions
// tabulated in spec §2.

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

    test('half is the only portrait-cell mode', () {
      expect(FilmMode.half.cellLandscape, isFalse);
      expect(FilmMode.full35.cellLandscape, isTrue);
      expect(FilmMode.f66.cellLandscape, isTrue);
    });
  });

  group('grid geometry', () {
    test('every mode grid fits inside the sheet', () {
      for (final mode in FilmMode.values) {
        final cw = mode.cellWidth;
        final ch = mode.cellHeight;
        expect(cw, greaterThan(0), reason: '${mode.id}: positive cell width');
        expect(ch, greaterThan(0), reason: '${mode.id}: positive cell height');

        final (x, y) = mode.cellOrigin(mode.capacity - 1);
        expect(
          x + cw,
          lessThanOrEqualTo(sheetWidth - margin),
          reason: '${mode.id}: last cell within right margin',
        );
        expect(
          y + ch,
          lessThanOrEqualTo(sheetHeight - margin),
          reason: '${mode.id}: last cell within bottom margin',
        );
        expect(
          y,
          greaterThanOrEqualTo(margin + headerH),
          reason: '${mode.id}: grid starts below the header band',
        );
      }
    });

    test('cell orientation matches the mode', () {
      expect(
        FilmMode.half.cellHeight,
        greaterThan(FilmMode.half.cellWidth),
        reason: 'half-frame cells are portrait',
      );
      expect(
        FilmMode.full35.cellWidth,
        greaterThan(FilmMode.full35.cellHeight),
        reason: '35mm cells are landscape',
      );
    });

    test('capacities match the spec table', () {
      expect(FilmMode.half.capacity, 72);
      expect(FilmMode.full35.capacity, 42);
      expect(FilmMode.f645.capacity, 16);
      expect(FilmMode.f66.capacity, 12);
      expect(FilmMode.f67.capacity, 12);
    });

    test('cell dimensions match the spec table exactly', () {
      expect((FilmMode.half.cellWidth, FilmMode.half.cellHeight), (218, 272));
      expect(
        (FilmMode.full35.cellWidth, FilmMode.full35.cellHeight),
        (380, 272),
      );
      expect((FilmMode.f645.cellWidth, FilmMode.f645.cellHeight), (672, 412));
      expect((FilmMode.f66.cellWidth, FilmMode.f66.cellHeight), (672, 552));
      expect((FilmMode.f67.cellWidth, FilmMode.f67.cellHeight), (672, 552));
    });

    test('cell origin advances by cell size plus gap', () {
      const mode = FilmMode.full35;
      expect(mode.cellOrigin(0), (margin, margin + headerH));
      expect(mode.cellOrigin(1), (
        margin + mode.cellWidth + gap,
        margin + headerH,
      ));
      // Index 7 wraps to the second row (7 columns).
      expect(mode.cellOrigin(7), (
        margin,
        margin + headerH + mode.cellHeight + gap,
      ));
    });

    test('the last cell of every mode lands on the margin bounds', () {
      for (final mode in FilmMode.values) {
        final (x, y) = mode.cellOrigin(mode.capacity - 1);
        expect(y + mode.cellHeight, 1956, reason: '${mode.id}: bottom bound');
        expect(x + mode.cellWidth, lessThanOrEqualTo(2856));
      }
    });
  });
}
