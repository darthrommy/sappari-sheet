/// Palette and metrics for the two-pane shell. Spec §7.
library;

import 'package:flutter/material.dart';

import '../render/text_metrics.dart';

class Palette {
  const Palette._();

  static const Color shell = Color(0xFF1A1A1A);
  static const Color sidebar = Color(0xFF232323);
  static const Color border = Color(0xFF333333);
  static const Color control = Color(0xFF2A2A2A);
  static const Color controlBorder = Color(0xFF444444);
  static const Color controlHover = Color(0xFF333333);
  static const Color focusBorder = Color(0xFF777777);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFAAAAAA);
  static const Color textMuted = Color(0xFF888888);
  static const Color textFaint = Color(0xFF666666);
  static const Color textFainter = Color(0xFF555555);
  static const Color textFaintest = Color(0xFF444444);
  static const Color previewBackdrop = Color(0xFF151515);
  static const Color thumbPlaceholder = Color(0xFFCCCCCC);
  static const Color thumbEmpty = Color(0xFF333333);
  static const Color error = Color(0xFFF87171);
}

const double sidebarWidth = 280;

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Palette.shell,
    canvasColor: Palette.sidebar,
    colorScheme: base.colorScheme.copyWith(
      surface: Palette.shell,
      primary: Palette.textPrimary,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: fontFamily,
      bodyColor: Palette.textPrimary,
      displayColor: Palette.textPrimary,
    ),
  );
}
