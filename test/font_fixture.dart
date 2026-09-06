// Shared font loading for tests.
//
// Both families must be registered. Google Sans Flex has no CJK coverage, so
// Japanese text resolves through Noto Sans JP; loading only the primary would
// let Japanese fall through to the test harness's placeholder font and hide a
// broken fallback chain — exactly the bug the CJK assertions exist to catch.
//
// Google Sans Flex ships one file per weight; Noto Sans JP is a variable font,
// so one file serves every weight via its `wght` axis.

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:negadice/render/text_metrics.dart';

Future<void> loadFonts() async {
  final primary = FontLoader(fontFamily)
    ..addFont(rootBundle.load('assets/fonts/GoogleSansFlex-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/GoogleSansFlex-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/GoogleSansFlex-SemiBold.ttf'));
  await primary.load();

  final fallback = FontLoader(fontFallback.first)
    ..addFont(rootBundle.load('assets/fonts/NotoSansJP-VariableFont_wght.ttf'));
  await fallback.load();
}
