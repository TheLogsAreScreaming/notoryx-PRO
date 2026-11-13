import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_lock.dart';
import '../store/database_vault.dart';
import '../app/message_alerts.dart';
import '../l10n/app_localizations.dart';
import 'about_screen.dart';
import 'beacon_sheet.dart';
import 'common.dart';
import 'conversation_screen.dart';
import 'export_sheet.dart';
import 'inbox_screen.dart';
import 'lock_gate.dart';
import 'map_screen.dart';
import 'map_tiles.dart';
import 'mute_menu.dart';
import 'nodes_screen.dart';
import 'notification_settings.dart';
import 'radios_screen.dart';
import 'restore_sheet.dart';
import 'search_screen.dart';
import 'sentinel_screen.dart';
import 'theme_screen.dart';
import 'themes.dart';

/// The app: localisation, theme and the three tabs.
class NotoryxProApp extends StatelessWidget {
  NotoryxProApp({
    super.key,
    required this.app,
    this.tiles,
    this.initialTheme = const ThemeChoice(),
    this.auth,
    this.vault,
    this.startLocked = false,
  });

  final AppController app;

  /// Used to open a conversation from a tapped notification.
  final navigatorKey = GlobalKey<NavigatorState>();

  /// Map tiles; null leaves the map without a background (tests).
  final MapTiles? tiles;

  /// The saved theme, read before the first frame so it doesn't flash.
  final ThemeChoice initialTheme;

  /// The phone's unlock check; null leaves the lock out (tests).
  final DeviceAuth? auth;

  /// Saved-message encryption; null leaves it out (tests).
  final DatabaseVault? vault;

  /// Whether to open locked, read before the first frame.
  final bool startLocked;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: app.store.watchPreference(ThemeChoice.prefName),
      builder: (context, snap) =>
          _build(snap.hasData ? ThemeChoice.decode(snap.data) : initialTheme),
    );
  }

  Widget _build(ThemeChoice choice) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      builder: auth == null
          ? null
          : (context, child) => LockGate(
              store: app.store,
              auth: auth!,
              startLocked: startLocked,
              child: child!,
            ),
      onGenerateTitle: (context) => context.l10n.appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(choice, Brightness.light),
      darkTheme: buildTheme(choice, Brightness.dark),
      home: HomeShell(
        app: app,
        tiles: tiles,
        navigatorKey: navigatorKey,
        auth: auth,
        vault: vault,
      ),
    );
  }
}

enum _MenuAction { markRead, export, restore, theme, lock, moderation, about }

/// Inbox, nodes and radios, with a bottom navigation bar.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.app,
    this.tiles,
    this.navigatorKey,
    this.auth,
    this.vault,
  });

  final AppController app;
  final MapTiles? tiles;
  final GlobalKey<NavigatorState>? navigatorKey;
  final DeviceAuth? auth;
  final DatabaseVault? vault;

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
    widget.app.scheduler.start();
    widget.app.responder.start();
    unawaited(widget.app.sentinel.start());
    widget.app.geofences?.start();
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
    widget.app.scheduler.stop();
    widget.app.responder.stop();
    widget.app.geofences?.stop();
    unawaited(_bgPref?.cancel());
    _lifecycle.dispose();
    unawaited(_taps?.cancel());
    super.dispose();
  }

  Future<void> _openFromNotification(String payload) async {
    if (payload == 'geofence') return;
    if (payload == stopPayload) {
      await widget.app.beacon.value?.stop();
      return;
    }
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
    if (app.geofences case final g?) {
      g.describe = (node, fence, entered) => entered
          ? l.geofenceEntered(node, fence)
          : l.geofenceLeft(node, fence);
      g.describeOffRoute = (node, route, metres) =>
          l.offRouteAlert(node, route, metres);
    }
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
          IconButton(
            tooltip: l.notifyTitle,
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (_) => NotificationSettingsSheet(app: app),
            ),
          ),
          PopupMenuButton<_MenuAction>(
            key: const Key('inbox-menu'),
            onSelected: (action) => switch (action) {
              _MenuAction.markRead => app.store.markAllRead(),
              _MenuAction.export => showExportSheet(context, store: app.store),
              _MenuAction.restore => restoreFromExport(
                context,
                store: app.store,
              ),
              _MenuAction.lock => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LockSettingsScreen(
                    store: app.store,
                    auth: widget.auth!,
                    vault: widget.vault,
                  ),
                ),
              ),
              _MenuAction.moderation => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SentinelPage(
                    sentinel: app.sentinel,
                    ownRadios: [for (final c in app.connections) ?c.radio?.id],
                  ),
                ),
              ),
              _MenuAction.about => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
              ),
              _MenuAction.theme => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ThemeScreen(store: app.store),
                ),
              ),
            },
            itemBuilder: (context) => [
              if (_tab == 0) ...[
                PopupMenuItem(
                  value: _MenuAction.markRead,
                  child: Text(context.l10n.markAllRead),
                ),
                PopupMenuItem(
                  value: _MenuAction.export,
                  child: Text(context.l10n.exportAll),
                ),
                PopupMenuItem(
                  value: _MenuAction.restore,
                  child: Text(context.l10n.restoreTitle),
                ),
              ],
              PopupMenuItem(
                value: _MenuAction.theme,
                child: Text(context.l10n.themeTitle),
              ),
              if (widget.auth != null)
                PopupMenuItem(
                  value: _MenuAction.lock,
                  child: Text(context.l10n.lockTitle),
                ),
              PopupMenuItem(
                key: const Key('menu-moderation'),
                value: _MenuAction.moderation,
                child: Text(context.l10n.sntTitle),
              ),
              PopupMenuItem(
                value: _MenuAction.about,
                child: Text(context.l10n.aboutTitle),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          BeaconBanner(app: app),
          Expanded(
            child: switch (_tab) {
              0 => InboxScreen(app: app),
              1 => NodesScreen(app: app),
              2 => MapScreen(app: app, tiles: widget.tiles),
              _ => RadiosScreen(app: app),
            },
          ),
        ],
      ),
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
