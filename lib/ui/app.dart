import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/app_localizations.dart';
import 'common.dart';
import 'inbox_screen.dart';
import 'map_screen.dart';
import 'map_tiles.dart';
import 'nodes_screen.dart';
import 'radios_screen.dart';

/// Blue from the NOTORYX PRO icon.
const notoryxBlue = Color(0xFF2AA7E0);

/// The app: localisation, theme and the three tabs.
class NotoryxProApp extends StatelessWidget {
  const NotoryxProApp({super.key, required this.app, this.tiles});

  final AppController app;

  /// Map tiles; null leaves the map without a background (tests).
  final MapTiles? tiles;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorSchemeSeed: notoryxBlue,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: notoryxBlue,
        brightness: Brightness.dark,
      ),
      home: HomeShell(app: app, tiles: tiles),
    );
  }
}

/// Inbox, nodes and radios, with a bottom navigation bar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.app, this.tiles});

  final AppController app;
  final MapTiles? tiles;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final app = widget.app;
    return Scaffold(
      appBar: AppBar(title: Text(l.appTitle)),
      body: switch (_tab) {
        0 => InboxScreen(app: app),
        1 => NodesScreen(app: app),
        2 => MapScreen(app: app, tiles: widget.tiles),
        _ => RadiosScreen(app: app),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: l.tabInbox,
          ),
          NavigationDestination(
            icon: const Icon(Icons.hub_outlined),
            selectedIcon: const Icon(Icons.hub),
            label: l.tabNodes,
          ),
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map),
            label: l.tabMap,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_input_antenna),
            label: l.tabRadios,
          ),
        ],
      ),
    );
  }
}
