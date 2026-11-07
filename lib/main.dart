import 'package:flutter/material.dart';

void main() => runApp(const NotoryxProApp());

/// Root widget for NOTORYX PRO.
///
/// The radio layers for MeshCore and Meshtastic arrive in later pull
/// requests (see ROADMAP.md); for now the app only shows its name.
class NotoryxProApp extends StatelessWidget {
  const NotoryxProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NOTORYX PRO',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFE0782A),
        brightness: Brightness.dark,
      ),
      home: const Scaffold(
        body: Center(
          child: Text(
            'NOTORYX PRO\nMeshCore + Meshtastic',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
