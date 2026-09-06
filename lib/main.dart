import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'ui/app_shell.dart';
import 'ui/theme.dart';

void main() {
  runApp(const SappariSheetApp());
}

class SappariSheetApp extends StatelessWidget {
  const SappariSheetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sappari Sheet',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // The UI is Japanese; without these the date picker comes up in English.
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AppShell(),
    );
  }
}
