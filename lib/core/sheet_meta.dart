/// What the sheet's title block prints.
///
/// The roll name becomes the sheet's title; the date its own column. Frame
/// count and film format are derived at render time and never typed.
library;

class SheetMeta {
  const SheetMeta({
    this.name = '',
    this.description = '',
    this.author = '',
    this.date = '',
  });

  /// Roll name — the large title. May be empty.
  final String name;

  /// The line under the title. May be empty.
  final String description;

  /// Photographer, printed in the first metadata column. May be empty.
  final String author;

  /// Date as it should print, e.g. `2026-09-06`. May be empty.
  final String date;

  static const SheetMeta empty = SheetMeta();

  SheetMeta copyWith({
    String? name,
    String? description,
    String? author,
    String? date,
  }) => SheetMeta(
    name: name ?? this.name,
    description: description ?? this.description,
    author: author ?? this.author,
    date: date ?? this.date,
  );

  /// Today in `YYYY-MM-DD`, the default the sidebar starts with.
  static String today([DateTime? now]) {
    final d = now ?? DateTime.now();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  @override
  bool operator ==(Object other) =>
      other is SheetMeta &&
      other.name == name &&
      other.description == description &&
      other.author == author &&
      other.date == date;

  @override
  int get hashCode => Object.hash(name, description, author, date);

  // Not used as a cache key — see PreviewKey in ui/preview_pane.dart, which
  // relies on the value equality above rather than on this string.
  @override
  String toString() =>
      'SheetMeta(name: $name, description: $description, '
      'author: $author, date: $date)';
}
