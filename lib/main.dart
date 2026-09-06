import 'package:flutter/material.dart';

import 'ui/app_shell.dart';
import 'ui/theme.dart';

void main() {
  runApp(const NegadiceApp());
}

class NegadiceApp extends StatelessWidget {
  const NegadiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'negadice',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AppShell(),
    );
  }
}
