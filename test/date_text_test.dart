// Date masking and validation for the 日付 field.

import 'package:flutter_test/flutter_test.dart';
import 'package:sappari_sheet/core/date_text.dart';

void main() {
  group('maskDate', () {
    test('inserts hyphens as digits arrive', () {
      expect(maskDate(''), '');
      expect(maskDate('2'), '2');
      expect(maskDate('2026'), '2026');
      expect(maskDate('20260'), '2026-0');
      expect(maskDate('202609'), '2026-09');
      expect(maskDate('2026090'), '2026-09-0');
      expect(maskDate('20260906'), '2026-09-06');
    });

    test('discards everything that is not a digit', () {
      expect(maskDate('abc'), '');
      expect(maskDate('2026年09月06日'), '2026-09-06');
      expect(maskDate('2026/09/06'), '2026-09-06');
      expect(maskDate('  2026-09-06  '), '2026-09-06');
    });

    test('is idempotent, so re-masking its own output is stable', () {
      const typed = '2026-09-06';
      expect(maskDate(typed), typed);
      expect(maskDate(maskDate(typed)), typed);
    });

    test('caps at eight digits', () {
      expect(maskDate('202609061234'), '2026-09-06');
    });

    test('backspacing shortens without corrupting the shape', () {
      // The field text after a backspace, re-masked.
      expect(maskDate('2026-09-0'), '2026-09-0');
      expect(maskDate('2026-09-'), '2026-09');
      expect(maskDate('2026-09'), '2026-09');
      expect(maskDate('2026-0'), '2026-0');
      expect(maskDate('2026-'), '2026');
    });
  });

  group('parseIsoDate', () {
    test('accepts a real date', () {
      final d = parseIsoDate('2026-09-06');
      expect(d, isNotNull);
      expect((d!.year, d.month, d.day), (2026, 9, 6));
    });

    test('rejects incomplete or malformed input', () {
      expect(parseIsoDate(''), isNull);
      expect(parseIsoDate('2026'), isNull);
      expect(parseIsoDate('2026-09'), isNull);
      expect(parseIsoDate('2026-9-6'), isNull);
      expect(parseIsoDate('not a date'), isNull);
    });

    // DateTime.tryParse accepts all of these by rolling over — which is exactly
    // why this function exists.
    test('rejects impossible dates instead of rolling them over', () {
      expect(parseIsoDate('2026-13-01'), isNull, reason: 'month 13');
      expect(parseIsoDate('2026-00-10'), isNull, reason: 'month 0');
      expect(parseIsoDate('2026-02-30'), isNull, reason: 'February 30th');
      expect(parseIsoDate('2026-04-31'), isNull, reason: 'April 31st');
      expect(parseIsoDate('2026-01-00'), isNull, reason: 'day 0');

      // Proof of the hazard: the stdlib parser happily accepts one of them.
      expect(
        DateTime.tryParse('2026-02-30'),
        isNotNull,
        reason: 'DateTime.tryParse rolls over rather than failing',
      );
    });

    test('handles leap years', () {
      expect(parseIsoDate('2024-02-29'), isNotNull, reason: '2024 is leap');
      expect(parseIsoDate('2026-02-29'), isNull, reason: '2026 is not');
      expect(parseIsoDate('2000-02-29'), isNotNull, reason: '400-year rule');
      expect(parseIsoDate('1900-02-29'), isNull, reason: '100-year rule');
    });
  });

  group('formatIsoDate', () {
    test('zero-pads month and day', () {
      expect(formatIsoDate(DateTime(2026, 1, 2)), '2026-01-02');
      expect(formatIsoDate(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('round-trips through parseIsoDate', () {
      final d = DateTime(2026, 9, 6);
      expect(parseIsoDate(formatIsoDate(d)), d);
    });
  });
}
