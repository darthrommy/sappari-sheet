// The preview's cache key.
//
// Regression guard. The key was once built by interpolating SheetMeta into a
// string; SheetMeta has no `toString` override, so it rendered as the constant
// "Instance of 'SheetMeta'" and the key never changed when the roll name or
// date did — the preview silently stopped re-rendering.

import 'package:flutter_test/flutter_test.dart';
import 'package:negadice/core/geometry.dart';
import 'package:negadice/core/sheet_meta.dart';
import 'package:negadice/services/sheet_service.dart';
import 'package:negadice/ui/preview_pane.dart';

void main() {
  const a = Frame(path: 'a.jpg', fileName: 'a.jpg');
  const b = Frame(path: 'b.jpg', fileName: 'b.jpg');
  const mode = FilmMode.full35;

  test('identical inputs produce an equal key', () {
    expect(
      previewKey(
        [a, b],
        mode,
        const SheetMeta(name: 'Roll', date: '2026-01-01'),
      ),
      previewKey(
        [a, b],
        mode,
        const SheetMeta(name: 'Roll', date: '2026-01-01'),
      ),
    );
  });

  test('the roll name is part of the key', () {
    expect(
      previewKey([a], mode, const SheetMeta(name: 'One')),
      isNot(previewKey([a], mode, const SheetMeta(name: 'Two'))),
    );
  });

  test('the date is part of the key', () {
    expect(
      previewKey([a], mode, const SheetMeta(name: 'Roll', date: '2026-01-01')),
      isNot(
        previewKey(
          [a],
          mode,
          const SheetMeta(name: 'Roll', date: '2026-01-02'),
        ),
      ),
    );
  });

  test('the photographer is part of the key', () {
    expect(
      previewKey([a], mode, const SheetMeta(author: 'One')),
      isNot(previewKey([a], mode, const SheetMeta(author: 'Two'))),
    );
  });

  test('frame order is part of the key', () {
    expect(
      previewKey([a, b], mode, SheetMeta.empty),
      isNot(previewKey([b, a], mode, SheetMeta.empty)),
    );
  });

  test('the film mode is part of the key', () {
    expect(
      previewKey([a], mode, SheetMeta.empty),
      isNot(previewKey([a], FilmMode.f66, SheetMeta.empty)),
    );
  });

  // The original bug: the key interpolated SheetMeta, whose *default* toString
  // is the constant "Instance of 'SheetMeta'", so the key never changed. The
  // key now uses value equality, and SheetMeta carries an explicit toString as
  // well — closing the footgun at both ends. Both are asserted here so neither
  // can quietly regress.
  test('SheetMeta distinguishes values by equality and by toString', () {
    const one = SheetMeta(name: 'One', author: 'A', date: '2026-01-01');
    const two = SheetMeta(name: 'Two', author: 'B', date: '2026-12-31');

    expect(one, isNot(two), reason: 'value equality distinguishes them');
    expect(one, SheetMeta(name: 'One', author: 'A', date: '2026-01-01'));

    expect(
      '$one',
      isNot('$two'),
      reason: 'toString is identity-bearing, not the default constant',
    );
    expect('$one', contains('One'));
    expect('$one', contains('A'));
  });
}
