import 'package:flutter/material.dart';

import 'home_screen.dart';

class LiveBridgeApp extends StatelessWidget {
  const LiveBridgeApp({super.key});

  static ThemeData _theme(Brightness b) =>
      ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal, brightness: b, visualDensity: VisualDensity.compact);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LiveBridge AI',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
