import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sappari_sheet/core/geometry.dart';
import 'package:sappari_sheet/services/settings_store.dart';
import 'package:sappari_sheet/ui/app_shell.dart';

/// The shell only needs somewhere to put settings, so tests give it memory
/// instead of a disk. Real file I/O never completes inside the fake-async zone
/// a widget test runs in; an in-memory store settles on a pump like any other
/// Future, which keeps these tests fast and hang-proof.
class InMemorySettingsStore implements SettingsStore {
  AppSettings? stored;
  int saves = 0;
  int clears = 0;

  @override
  Future<AppSettings?> load() async => stored;

  @override
  Future<void> save(AppSettings settings) async {
    stored = settings;
    saves++;
  }

  @override
  Future<void> clear() async {
    stored = null;
    clears++;
  }
}

void main() {
  late InMemorySettingsStore store;

  setUp(() => store = InMemorySettingsStore());

  Future<void> pumpShell(WidgetTester tester, AppSettings? initial) async {
    await tester.pumpWidget(
      MaterialApp(home: AppShell(store: store, initialSettings: initial)),
    );
    await tester.pump();
  }

  /// Positional finders are brittle here — the film DropdownMenu contributes a
  /// TextField of its own — so fields are addressed by their hint.
  Finder fieldWithHint(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint,
  );

  Finder authorField() => fieldWithHint('あなたの名前');
  Finder fileNameField() => fieldWithHint('index_sheet');
  Finder toggle() => find.text('入力内容を記憶する');

  /// The toggle sits at the foot of a scrolling sidebar, below the fold of the
  /// default 800x600 test surface — without scrolling to it first the tap
  /// lands outside the render tree.
  Future<void> tapToggle(WidgetTester tester) async {
    await tester.ensureVisible(toggle());
    await tester.pump();
    await tester.tap(toggle());
    await tester.pump();
  }

  String textOf(WidgetTester tester, Finder field) =>
      tester.widget<TextField>(field).controller!.text;

  bool isChecked(WidgetTester tester) =>
      tester.widget<Checkbox>(find.byType(Checkbox)).value ?? false;

  testWidgets('restored settings fill the fields on the first frame', (
    tester,
  ) async {
    await pumpShell(
      tester,
      const AppSettings(
        author: '山田 太郎',
        fileName: 'roll_index',
        mode: FilmMode.f66,
      ),
    );

    expect(textOf(tester, authorField()), '山田 太郎');
    expect(textOf(tester, fieldWithHint('index_sheet')), 'roll_index');
    expect(isChecked(tester), isTrue);
  });

  testWidgets('without saved settings the box is off and fields default', (
    tester,
  ) async {
    await pumpShell(tester, null);

    expect(isChecked(tester), isFalse);
    expect(textOf(tester, authorField()), isEmpty);
    expect(textOf(tester, fileNameField()), 'index_sheet');
  });

  testWidgets('checking the box writes the current fields', (tester) async {
    await pumpShell(tester, null);
    await tester.enterText(fileNameField(), 'my_sheet');
    await tester.enterText(authorField(), '佐藤');
    await tester.pump();
    expect(store.stored, isNull, reason: 'nothing saved before opting in');

    await tapToggle(tester);

    expect(store.stored?.fileName, 'my_sheet');
    expect(store.stored?.author, '佐藤');
    expect(isChecked(tester), isTrue);
  });

  testWidgets('typing while remembering coalesces into one delayed write', (
    tester,
  ) async {
    await pumpShell(tester, const AppSettings());

    await tester.enterText(authorField(), '佐');
    await tester.enterText(authorField(), '佐藤');
    await tester.pump(const Duration(milliseconds: 200));
    expect(store.saves, 0, reason: 'still inside the debounce window');

    await tester.pump(const Duration(milliseconds: 400));
    expect(store.saves, 1, reason: 'two keystrokes, one write');
    expect(store.stored?.author, '佐藤');
  });

  testWidgets('the restored film mode is carried into later writes', (
    tester,
  ) async {
    await pumpShell(tester, const AppSettings(mode: FilmMode.f67));

    await tester.enterText(authorField(), '佐藤');
    await tester.pump(const Duration(milliseconds: 600));

    expect(store.stored?.mode, FilmMode.f67);
  });

  testWidgets('unchecking the box clears the stored settings', (tester) async {
    await pumpShell(tester, const AppSettings(author: '山田'));

    await tapToggle(tester);

    expect(store.stored, isNull);
    expect(store.clears, 1);
    expect(isChecked(tester), isFalse);
  });

  testWidgets('nothing is written while the box is unchecked', (tester) async {
    await pumpShell(tester, null);

    await tester.enterText(authorField(), '佐藤');
    await tester.pump(const Duration(seconds: 1));

    expect(store.saves, 0);
    expect(store.stored, isNull);
  });
}
