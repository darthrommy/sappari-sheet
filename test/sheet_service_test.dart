// Cell caching in SheetService.
//
// The point of the cache is that changing the memo, reordering frames, or
// exporting must not re-read the source files. These tests prove that by
// deleting the sources after analyze: if anything still hit the disk, the
// frames would come back as gray placeholders or the call would fail.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:negadice/core/geometry.dart';
import 'package:negadice/core/sheet_meta.dart';
import 'package:negadice/services/sheet_service.dart';

import 'font_fixture.dart';

/// Write [count] distinct solid-colour JPEGs into [dir] and return their paths.
List<String> writeSources(Directory dir, int count) {
  final paths = <String>[];
  for (var i = 0; i < count; i++) {
    final frame = img.Image(width: 400, height: 300);
    img.fill(frame, color: img.ColorRgb8(10 + i * 30, 60, 200 - i * 20));
    final path = '${dir.path}${Platform.pathSeparator}img${i + 1}.jpg';
    File(path).writeAsBytesSync(img.encodeJpg(frame, quality: 90));
    paths.add(path);
  }
  return paths;
}

/// The colour at the centre of cell [index] on a composed sheet.
///
/// Cell origins are in full-sheet coordinates, so scale them for the half-size
/// preview (1500x1050) rather than the full 3000x2100 export.
(int, int, int) cellCentre(img.Image sheet, FilmMode mode, int index) {
  final scale = sheet.width / sheetWidth;
  final (x, y) = mode.cellOrigin(index);
  final cx = ((x + mode.cellWidth / 2) * scale).round();
  final cy = ((y + mode.cellHeight / 2) * scale).round();
  final p = sheet.getPixel(cx, cy);
  return (p.r.toInt(), p.g.toInt(), p.b.toInt());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  late Directory dir;
  late SheetService service;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('negadice_cache_test');
    service = SheetService();
  });

  tearDown(() {
    service.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('analyze caches one cell per kept frame', () async {
    final paths = writeSources(dir, 3);
    final result = await service.analyze(paths, FilmMode.full35, sort: true);

    expect(result.frames, hasLength(3));
    expect(service.cachedCellCount, 3);
    expect(
      result.frames.every((f) => f.thumb != null),
      isTrue,
      reason: 'every source decoded',
    );
  });

  test('preview reuses cached cells and never re-reads the sources', () async {
    final paths = writeSources(dir, 3);
    await service.analyze(paths, FilmMode.full35, sort: true);

    // If preview re-read the files this would fail or produce placeholders.
    for (final path in paths) {
      File(path).deleteSync();
    }

    final bytes = await service.preview(
      paths,
      FilmMode.full35,
      const SheetMeta(name: 'メモ'),
    );
    final sheet = img.decodeJpg(bytes)!;

    expect((sheet.width, sheet.height), (1500, 1050));
    expect(
      service.cachedCellCount,
      3,
      reason: 'preview neither dropped nor added cells',
    );
  });

  test('render reuses cached cells and never re-reads the sources', () async {
    final paths = writeSources(dir, 2);
    await service.analyze(paths, FilmMode.full35, sort: true);
    for (final path in paths) {
      File(path).deleteSync();
    }

    final out = await service.render(
      paths,
      dir.path,
      'from_cache',
      FilmMode.full35,
      SheetMeta.empty,
    );
    final sheet = img.decodeJpg(File(out).readAsBytesSync())!;

    expect((sheet.width, sheet.height), (sheetWidth, sheetHeight));
    // Not the gray placeholder — the real frames came from the cache.
    final (r, g, b) = cellCentre(sheet, FilmMode.full35, 0);
    expect(
      (r - 204).abs() < 12 && (g - 204).abs() < 12 && (b - 204).abs() < 12,
      isFalse,
      reason: 'cell 0 should hold a decoded frame, not the placeholder',
    );
  });

  test('reordering changes the sheet without re-reading sources', () async {
    final paths = writeSources(dir, 3);
    await service.analyze(paths, FilmMode.full35, sort: true);
    for (final path in paths) {
      File(path).deleteSync();
    }

    const mode = FilmMode.full35;
    final before = img.decodeJpg(
      await service.preview(paths, mode, SheetMeta.empty),
    )!;
    final swapped = [paths[1], paths[0], paths[2]];
    final after = img.decodeJpg(
      await service.preview(swapped, mode, SheetMeta.empty),
    )!;

    // Slot 0 and slot 1 traded contents; the cache served both orders.
    expect(cellCentre(after, mode, 0), isNot(cellCentre(before, mode, 0)));
    expect(service.cachedCellCount, 3);
  });

  test('switching mode rebuilds cells and prunes the old ones', () async {
    final paths = writeSources(dir, 3);
    await service.analyze(paths, FilmMode.full35, sort: true);
    expect(service.cachedCellCount, 3);

    // Re-analyze under a different mode, as the UI does on a mode change.
    await service.analyze(paths, FilmMode.f66, sort: false);

    expect(
      service.cachedCellCount,
      3,
      reason: 'cells for the previous mode are disposed, not accumulated',
    );
  });

  test('an undecodable file yields a null thumb and is not cached', () async {
    final broken = '${dir.path}${Platform.pathSeparator}broken.jpg';
    File(broken).writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));
    final good = writeSources(dir, 1);

    final result = await service.analyze(
      [broken, ...good],
      FilmMode.full35,
      sort: false,
    );

    expect(result.frames, hasLength(2));
    expect(result.frames[0].thumb, isNull, reason: 'broken file');
    expect(result.frames[1].thumb, isNotNull);
    expect(service.cachedCellCount, 1, reason: 'only the decodable one cached');
  });

  test('disposing the service releases cached cells', () async {
    final paths = writeSources(dir, 2);
    await service.analyze(paths, FilmMode.full35, sort: true);
    expect(service.cachedCellCount, 2);

    service.dispose();
    expect(service.cachedCellCount, 0);

    // tearDown disposes again; make that a no-op rather than a double-dispose.
    service = SheetService();
  });

  test('unsupported extensions are filtered before caching', () async {
    final txt = '${dir.path}${Platform.pathSeparator}notes.txt';
    File(txt).writeAsStringSync('not an image');
    final good = writeSources(dir, 2);

    final result = await service.analyze(
      [txt, ...good],
      FilmMode.full35,
      sort: true,
    );

    expect(result.total, 2, reason: 'the .txt is rejected by extension');
    expect(service.cachedCellCount, 2);
  });
}
