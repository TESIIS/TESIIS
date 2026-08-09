import 'package:flutter/material.dart';

import 'presentation/pages/home_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '臺北市避難設施查詢',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green[700]),
      home: const Scaffold(body: MapScreen()),
    );
  }
}
