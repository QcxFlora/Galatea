import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'theme.dart';

void main() {
  runApp(const GalateaApp());
}

class GalateaApp extends StatelessWidget {
  const GalateaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Galatea Studio',
      debugShowCheckedModeBanner: false,
      theme: buildGalateaTheme(Brightness.dark),
      home: const HomePage(),
    );
  }
}