import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/theme/app_theme.dart';
import 'package:flutter_codefest/presentation/pages/map_page.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '臺灣避難收容處所資訊整合系統',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Default to light regardless of system setting. AppTheme.dark() stays
      // wired up for whenever a manual theme toggle gets added.
      themeMode: ThemeMode.light,
      // MapPage builds its own Scaffold; no need to wrap it in another.
      home: const MapPage(),
    );
  }
}
