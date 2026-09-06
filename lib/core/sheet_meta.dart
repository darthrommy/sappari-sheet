/// What the sheet's title block prints.
///
/// Replaces the Tauri original's single free-text `memo`. That field's own
/// placeholder was 「ロール名・日付・現像所など」, so this is the same information
/// given structure rather than a new concept: the roll name becomes the sheet's
/// title, the date its own column. Frame count and film format are derived at
/// render time and never typed.
library;

class SheetMeta {
  const SheetMeta({this.name = '', this.author = '', this.date = ''});

  /// Roll name — the large title. May be empty.
  final String name;

  /// Photographer, printed in the first metadata column. May be empty.
  final String author;

  /// Date as it should print, e.g. `2026-09-06`. May be empty.
  final String date;

  static const SheetMeta empty = SheetMeta();

  SheetMeta copyWith({String? name, String? author, String? date}) => SheetMeta(
    name: name ?? this.name,
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
      other.author == author &&
      other.date == date;

  @override
  int get hashCode => Object.hash(name, author, date);

  // Not used as a cache key — see PreviewKey in ui/preview_pane.dart, which
  // relies on the value equality above rather than on this string.
  @override
  String toString() => 'SheetMeta(name: $name, author: $author, date: $date)';
}
