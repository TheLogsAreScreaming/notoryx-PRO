import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/message_alerts.dart';
import '../l10n/app_localizations.dart';
import 'common.dart';
import 'conversation_screen.dart';
import 'export_sheet.dart';
import 'inbox_screen.dart';
import 'map_screen.dart';
import 'map_tiles.dart';
import 'mute_menu.dart';
import 'nodes_screen.dart';
import 'notification_settings.dart';
import 'radios_screen.dart';
import 'search_screen.dart';

/// Blue from the NOTORYX PRO icon.
const notoryxBlue = Color(0xFF2AA7E0);

/// The app: localisation, theme and the three tabs.
class NotoryxProApp extends StatelessWidget {
  NotoryxProApp({super.key, required this.app, this.tiles});

  final AppController app;

  /// Used to open a conversation from a tapped notification.
  final navigatorKey = GlobalKey<NavigatorState>();

  /// Map tiles; null leaves the map without a background (tests).
  final MapTiles? tiles;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
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
      home: HomeShell(app: app, tiles: tiles, navigatorKey: navigatorKey),
    );
  }
}

/// Inbox, nodes and radios, with a bottom navigation bar.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.app,
    this.tiles,
    this.navigatorKey,
  });

  final AppController app;
  final MapTiles? tiles;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  StreamSubscription<String>? _taps;
  late final AppLifecycleListener _lifecycle;
  late final Stream<Map<String, int>> _unread = widget.app.store.watchUnread();
  late final Stream<Map<String, DateTime>> _mutes = widget.app.store
      .watchMutes();

  StreamSubscription<String?>? _bgPref;
  bool _bgAllowed = true;
  (bool, int)? _kept;

  /// Keeps radios connected in the background while any are connected
  /// (unless the person turned it off).
  void _syncKeepAlive() {
    final alerts = widget.app.alerts;
    if (alerts == null || !mounted) return;
    final n = widget.app.connections.length;
    final want = (_bgAllowed && n > 0, n);
    // Nothing to stop before anything was started.
    if (want == _kept || (_kept == null && !want.$1)) return;
    _kept = want;
    final l = context.l10n;
    unawaited(
      alerts.notifier.keepAlive(
        want.$1,
        title: l.keepAliveTitle,
        body: l.keepAliveBody(n),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_syncKeepAlive);
    _bgPref = widget.app.store.watchPreference(AlertPrefs.background).listen((
      v,
    ) {
      _bgAllowed = v != 'off';
      _syncKeepAlive();
    });
    final alerts = widget.app.alerts;
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) => alerts?.foreground = s == AppLifecycleState.resumed,
    );
    _taps = alerts?.notifier.taps.listen(_openFromNotification);
  }

  @override
  void dispose() {
    widget.app.removeListener(_syncKeepAlive);
    unawaited(_bgPref?.cancel());
    _lifecycle.dispose();
    unawaited(_taps?.cancel());
    super.dispose();
  }

  Future<void> _openFromNotification(String payload) async {
    final c = MessageAlerts.conversationFor(payload);
    if (c == null) return;
    final title = await widget.app.store.conversationTitle(c);
    final nav = widget.navigatorKey?.currentState;
    if (nav == null || !mounted) return;
    setState(() => _tab = 0);
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ConversationScreen(app: widget.app, conversation: c, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final app = widget.app;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          if (_tab == 0)
            IconButton(
              tooltip: l.searchTitle,
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => SearchScreen(app: app)),
              ),
            ),
          if (_tab == 0)
            IconButton(
              tooltip: l.markAllRead,
              icon: const Icon(Icons.done_all),
              onPressed: () => app.store.markAllRead(),
            ),
          IconButton(
            tooltip: l.notifyTitle,
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (_) => NotificationSettingsSheet(app: app),
            ),
          ),
          if (_tab == 0)
            PopupMenuButton<bool>(
              key: const Key('inbox-menu'),
              onSelected: (_) => showExportSheet(context, store: app.store),
              itemBuilder: (context) => [
                PopupMenuItem(value: true, child: Text(context.l10n.exportAll)),
              ],
            ),
        ],
      ),
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
            icon: _UnreadBadge(
              unread: _unread,
              mutes: _mutes,
              child: const Icon(Icons.chat_bubble_outline),
            ),
            selectedIcon: _UnreadBadge(
              unread: _unread,
              mutes: _mutes,
              child: const Icon(Icons.chat_bubble),
            ),
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

/// The inbox icon with the number of unread messages outside muted
/// conversations.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({
    required this.unread,
    required this.mutes,
    required this.child,
  });

  final Stream<Map<String, int>> unread;
  final Stream<Map<String, DateTime>> mutes;
  final Widget child;

  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, int>>(
    stream: unread,
    builder: (context, u) => StreamBuilder<Map<String, DateTime>>(
      stream: mutes,
      builder: (context, m) {
        final now = DateTime.now();
        final muted = m.data ?? const {};
        var total = 0;
        for (final MapEntry(key: k, value: n) in (u.data ?? const {}).entries) {
          if (!mutedAt(muted[k], now)) total += n;
        }
        return Badge(
          isLabelVisible: total > 0,
          label: Text(total > 99 ? '99+' : '$total'),
          child: child,
        );
      },
    ),
  );
}
