import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sappari_sheet/core/geometry.dart';
import 'package:sappari_sheet/services/settings_store.dart';

void main() {
  late Directory dir;
  late FileSettingsStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sappari_settings_test');
    store = FileSettingsStore(dir);
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  File settingsFile() => File('${dir.path}${Platform.pathSeparator}settings.json');

  test('load returns null when nothing was ever saved', () async {
    expect(await store.load(), isNull);
  });

  test('save then load round-trips every remembered field', () async {
    const saved = AppSettings(
      author: '山田 太郎',
      fileName: 'roll_index',
      mode: FilmMode.f67,
    );
    await store.save(saved);

    expect(await store.load(), saved);
  });

  test('save creates the directory when it is missing', () async {
    final nested = Directory('${dir.path}${Platform.pathSeparator}deep');
    await FileSettingsStore(nested).save(const AppSettings(author: 'A'));

    expect(await FileSettingsStore(nested).load(), const AppSettings(author: 'A'));
  });

  test('load returns null when the file is not valid json', () async {
    await settingsFile().writeAsString('{ this is not json');

    expect(await store.load(), isNull);
  });

  test('load returns null when the json is not an object', () async {
    await settingsFile().writeAsString('["author"]');

    expect(await store.load(), isNull);
  });

  test('load falls back to the default film mode for an unknown id', () async {
    await settingsFile().writeAsString(
      jsonEncode({'author': 'A', 'fileName': 'x', 'mode': 'super8'}),
    );

    final loaded = await store.load();
    expect(loaded?.mode, FilmMode.full35);
    expect(loaded?.author, 'A');
  });

  test('load uses field defaults for keys the file does not carry', () async {
    await settingsFile().writeAsString(jsonEncode({'author': 'A'}));

    expect(await store.load(), const AppSettings(author: 'A'));
  });

  test('load ignores values of the wrong type', () async {
    await settingsFile().writeAsString(
      jsonEncode({'author': 42, 'fileName': null, 'mode': 7}),
    );

    expect(await store.load(), AppSettings.defaults);
  });

  test('clear removes the stored settings so nothing lingers on disk', () async {
    await store.save(const AppSettings(author: 'A'));
    expect(settingsFile().existsSync(), isTrue);

    await store.clear();

    expect(settingsFile().existsSync(), isFalse);
    expect(await store.load(), isNull);
  });

  test('clear is a no-op when there is nothing stored', () async {
    await store.clear();

    expect(await store.load(), isNull);
  });

  test('the settings directory sits under APPDATA on Windows', () {
    final resolved = FileSettingsStore.resolveDirectory(
      isWindows: true,
      environment: {'APPDATA': r'C:\Users\u\AppData\Roaming'},
    );

    expect(resolved.path, r'C:\Users\u\AppData\Roaming\sappari_sheet');
  });

  test('the settings directory sits under Application Support elsewhere', () {
    final resolved = FileSettingsStore.resolveDirectory(
      isWindows: false,
      environment: {'HOME': '/Users/u'},
    );

    expect(
      resolved.path,
      '/Users/u/Library/Application Support/sappari_sheet',
    );
  });

  test('resolveDirectory falls back to the current directory without env', () {
    final resolved = FileSettingsStore.resolveDirectory(
      isWindows: true,
      environment: const {},
    );

    expect(resolved.path, endsWith('sappari_sheet'));
  });
}
