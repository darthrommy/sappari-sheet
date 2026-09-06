// End-to-end smoke test: composes a representative sheet through the real
// pipeline and writes it to `build/samples/` so the output can be eyeballed
// against the Tauri original. Also asserts the file is a valid JPEG of the
// right size, so it earns its place in CI as well.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:negadice/core/geometry.dart';
import 'package:negadice/render/sheet_renderer.dart';
import 'package:negadice/render/text_metrics.dart';

Future<void> loadFonts() async {
  final loader = FontLoader(fontFamily)
    ..addFont(rootBundle.load('assets/fonts/UDEVGothic35JPDOC-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/UDEVGothic35JPDOC-Bold.ttf'));
  await loader.load();
}

/// A frame with visible structure, so cover-fit cropping and rotation are
/// obvious in the rendered sheet.
Future<ui.Image> patterned(int w, int h, int seed) {
  final pixels = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final band = ((x ~/ 24) + (y ~/ 24) + seed) % 3;
      final edge = x < 8 || y < 8 || x > w - 9 || y > h - 9;
      pixels[i] = edge ? 20 : (band == 0 ? 200 : (band == 1 ? 120 : 60));
      pixels[i + 1] = edge ? 20 : (band == 0 ? 90 : (band == 1 ? 150 : 90));
      pixels[i + 2] = edge ? 20 : (band == 0 ? 70 : (band == 1 ? 90 : 170));
      pixels[i + 3] = 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  test('composes a full 35mm sheet and writes a sample JPEG', () async {
    final images = <ui.Image?>[
      for (var i = 0; i < 20; i++)
        // Mix landscape and portrait sources to exercise the rotation path.
        await patterned(i.isEven ? 600 : 400, i.isEven ? 400 : 600, i),
      null, // an undecodable file -> gray placeholder
      for (var i = 0; i < 5; i++) await patterned(600, 400, i + 7),
    ];

    final sheet = await composeSheet(
      images,
      FilmMode.full35,
      'テストロール 2024 · Kodak ProImage 100',
    );
    final jpeg = await encodeSheet(sheet);

    final decoded = img.decodeJpg(jpeg)!;
    expect(decoded.width, sheetWidth);
    expect(decoded.height, sheetHeight);

    final outDir = Directory('build/samples')..createSync(recursive: true);
    File('${outDir.path}/sheet_35mm.jpg').writeAsBytesSync(jpeg);

    // A downscaled copy, easier to inspect.
    final preview = await makePreview(sheet);
    File('${outDir.path}/sheet_35mm_preview.jpg').writeAsBytesSync(preview);

    for (final image in images) {
      image?.dispose();
    }
    sheet.dispose();
  });
}
