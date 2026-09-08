import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/settings_store.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  // Settings are read before the first frame so the sidebar fields come up
  // already filled rather than populating a frame late.
  WidgetsFlutterBinding.ensureInitialized();
  final store = FileSettingsStore.forPlatform();
  final settings = await store.load();
  runApp(SappariSheetApp(store: store, initialSettings: settings));
}

class SappariSheetApp extends StatelessWidget {
  const SappariSheetApp({
    super.key,
    required this.store,
    required this.initialSettings,
  });

  final SettingsStore store;
  final AppSettings? initialSettings;

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
      home: AppShell(store: store, initialSettings: initialSettings),
    );
  }
}
