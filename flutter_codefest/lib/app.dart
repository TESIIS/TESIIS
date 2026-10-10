import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/theme/app_theme.dart';
import 'package:flutter_codefest/presentation/pages/map_page.dart';
import 'package:flutter_codefest/data/repositories/preparedness_store.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final _store = PreparednessStore();
  @override
  void initState() {
    super.initState();
    _store.load();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) => MaterialApp(
        title: '臺灣避難收容所資訊整合系統',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _store.themeMode,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: _store.largeText
                  ? TextScaler.linear(media.textScaler.scale(1) * 1.25)
                  : media.textScaler,
            ),
            child: child!,
          );
        },
        // MapPage builds its own Scaffold; no need to wrap it in another.
        home: _store.ready
            ? MapPage(store: _store)
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
  }
}
