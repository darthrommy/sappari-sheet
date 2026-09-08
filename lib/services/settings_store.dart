/// The handful of sidebar values the app carries across runs, and the JSON
/// file they live in.
///
/// Opting in is the user's call: the file exists only while 「入力内容を記憶する」
/// is checked, so an absent file means "remember nothing" and unchecking the
/// box leaves nothing behind on disk.
library;

import 'dart:convert';
import 'dart:io';

import '../core/geometry.dart';

/// The remembered fields. Roll name, description and date are deliberately
/// absent — those are per-roll, and a stale date would print on a sheet.
class AppSettings {
  const AppSettings({
    this.author = '',
    this.fileName = 'index_sheet',
    this.mode = FilmMode.full35,
  });

  /// Reading is lenient by design: a file from an older build, or one edited
  /// by hand, should still start the app rather than cost every field.
  factory AppSettings.fromJson(Map<String, Object?> json) {
    final author = json['author'];
    final fileName = json['fileName'];
    final mode = json['mode'];
    return AppSettings(
      author: author is String ? author : defaults.author,
      fileName: fileName is String ? fileName : defaults.fileName,
      mode: mode is String ? _parseMode(mode) : defaults.mode,
    );
  }

  /// 撮影者 — the one the user actually asked to keep.
  final String author;

  /// The output file name base, without the `.jpg` the service appends.
  final String fileName;

  final FilmMode mode;

  static const AppSettings defaults = AppSettings();

  static FilmMode _parseMode(String id) {
    try {
      return FilmMode.parse(id);
    } on FormatException {
      return defaults.mode;
    }
  }

  Map<String, Object?> toJson() => {
    'author': author,
    'fileName': fileName,
    // The enum's own id, not its Dart name — renaming a value must not
    // orphan a file someone already has.
    'mode': mode.id,
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.author == author &&
      other.fileName == fileName &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(author, fileName, mode);

  @override
  String toString() =>
      'AppSettings(author: $author, fileName: $fileName, mode: ${mode.id})';
}

/// Somewhere to keep [AppSettings] between runs.
///
/// The shell depends on this rather than on the file-backed implementation, so
/// a widget test can hand it an in-memory one: real file I/O never completes
/// inside the fake-async zone `testWidgets` runs its body in.
abstract interface class SettingsStore {
  /// The saved settings, or null when there is nothing to restore.
  Future<AppSettings?> load();

  Future<void> save(AppSettings settings);

  /// Forgets everything, leaving nothing behind.
  Future<void> clear();
}

/// The real one: a single JSON file in the OS's per-user application data
/// directory.
class FileSettingsStore implements SettingsStore {
  /// Takes the directory rather than finding it, so tests can hand it a
  /// temporary one.
  FileSettingsStore(this.directory);

  FileSettingsStore.forPlatform()
    : directory = resolveDirectory(
        isWindows: Platform.isWindows,
        environment: Platform.environment,
      );

  final Directory directory;

  static const String _appDirName = 'sappari_sheet';
  static const String _fileName = 'settings.json';

  /// `%APPDATA%\sappari_sheet` on Windows, `~/Library/Application
  /// Support/sappari_sheet` elsewhere. Under the macOS sandbox `HOME` already
  /// points inside the app container, so this stays writable.
  ///
  /// The separator follows [isWindows] rather than the host, which is what
  /// lets this be tested from either platform.
  static Directory resolveDirectory({
    required bool isWindows,
    required Map<String, String> environment,
  }) {
    if (isWindows) {
      final roaming = environment['APPDATA'];
      if (roaming == null || roaming.isEmpty) return Directory(_appDirName);
      return Directory('$roaming\\$_appDirName');
    }
    final home = environment['HOME'];
    if (home == null || home.isEmpty) return Directory(_appDirName);
    return Directory('$home/Library/Application Support/$_appDirName');
  }

  File get _file =>
      File('${directory.path}${Platform.pathSeparator}$_fileName');

  /// The saved settings, or null when there are none to restore — the file is
  /// missing, unreadable, or not the JSON object we wrote. Startup must never
  /// fail over this, so every error reads as "nothing remembered"; the next
  /// save replaces the bad file.
  @override
  Future<AppSettings?> load() async {
    try {
      final file = _file;
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return null;
      return AppSettings.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    await directory.create(recursive: true);
    await _file.writeAsString(jsonEncode(settings.toJson()));
  }

  @override
  Future<void> clear() async {
    final file = _file;
    if (await file.exists()) await file.delete();
  }
}
