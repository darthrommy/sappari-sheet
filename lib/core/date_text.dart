/// Date text handling for the sidebar's 日付 field.
///
/// Pure Dart, no Flutter imports, so it is testable headlessly like the rest of
/// `core/`. The UI wraps [maskDate] in a `TextInputFormatter`.
library;

/// Format [date] as `YYYY-MM-DD`.
String formatIsoDate(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-$m-$d';
}

bool isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

int daysInMonth(int year, int month) => switch (month) {
  1 || 3 || 5 || 7 || 8 || 10 || 12 => 31,
  4 || 6 || 9 || 11 => 30,
  2 => isLeapYear(year) ? 29 : 28,
  _ => 0,
};

/// Coerce arbitrary typed input toward `YYYY-MM-DD`.
///
/// Everything that is not a digit is discarded — including hyphens, which are
/// re-inserted at the fixed positions — so the shape cannot drift no matter
/// what is typed or pasted. Input beyond eight digits is dropped.
String maskDate(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  final capped = digits.length > 8 ? digits.substring(0, 8) : digits;
  if (capped.length <= 4) return capped;
  if (capped.length <= 6) {
    return '${capped.substring(0, 4)}-${capped.substring(4)}';
  }
  return '${capped.substring(0, 4)}-${capped.substring(4, 6)}'
      '-${capped.substring(6)}';
}

/// Parse a complete `YYYY-MM-DD` string, or null if it is not a real date.
///
/// Deliberately not `DateTime.tryParse`, which **silently rolls over** rather
/// than failing: it turns `2026-02-30` into March 2nd and `2026-13-01` into
/// January 2027. Components are range-checked instead.
DateTime? parseIsoDate(String text) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
  if (match == null) return null;

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);

  if (month < 1 || month > 12) return null;
  if (day < 1 || day > daysInMonth(year, month)) return null;
  return DateTime(year, month, day);
}
