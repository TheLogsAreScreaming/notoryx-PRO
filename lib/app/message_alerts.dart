import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Message;

import '../mesh/model.dart';
import '../store/mesh_store.dart';

/// Shows system notifications; replaceable in tests.
abstract interface class Notifier {
  /// Sets up the platform; false where notifications aren't available.
  Future<bool> init();

  /// Asks the person for permission; true if granted.
  Future<bool> requestPermission();

  /// Shows (or replaces) notification [id].
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  });

  /// Removes notification [id].
  Future<void> cancel(int id);

  /// Payloads of notifications the person tapped.
  Stream<String> get taps;
}

/// [Notifier] on Android, iPhone and Mac.
class SystemNotifier implements Notifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'messages',
    'Messages',
    channelDescription: 'New mesh messages',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
  );

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  Future<bool> init() async {
    if (!_supported) return false;
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwin,
        macOS: darwin,
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload case final p? when !_taps.isClosed) _taps.add(p);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final p = launch?.notificationResponse?.payload;
      if (p != null) scheduleMicrotask(() => _taps.add(p));
    }
    return _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    final mac = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    return await mac?.requestPermissions(alert: true, sound: true) ?? false;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (!_ready) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: const NotificationDetails(
        android: _channel,
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (_ready) await _plugin.cancel(id: id);
  }

  @override
  Stream<String> get taps => _taps.stream;
}

/// Which messages notify.
abstract final class AlertPrefs {
  /// Preference names in the store.
  static const direct = 'notify.direct';
  static const channels = 'notify.channels';
}

/// Turns newly received messages into notifications: one per
/// conversation, showing the newest message and how many are unread.
///
/// Nothing is shown for muted conversations, for reactions, for the
/// conversation on screen while the app is in front, or for kinds of
/// conversation the person turned off.
class MessageAlerts {
  MessageAlerts({
    required this.store,
    required this.notifier,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _sub = store.incoming.listen((m) => unawaited(_onMessage(m)));
  }

  final MeshStore store;
  final Notifier notifier;
  final DateTime Function() _now;
  late final StreamSubscription<StoredMessage> _sub;

  /// The conversation on screen, if any.
  Conversation? open;

  /// Whether the app is in front.
  bool foreground = true;

  /// Unread counts per conversation since its last notification was
  /// cleared.
  final Map<String, int> _counts = {};

  /// Notification ID for a conversation (stable across launches).
  static int idFor(Conversation c) {
    var h = 0;
    for (final u in c.key.codeUnits) {
      h = (h * 31 + u) & 0x3fffffff;
    }
    return h;
  }

  /// The conversation a tapped notification refers to.
  static Conversation? conversationFor(String payload) =>
      Conversation.tryParse(payload);

  /// Whether a kind of conversation notifies (on unless turned off).
  Future<bool> enabled(Conversation c) async {
    final name = c is DirectConversation
        ? AlertPrefs.direct
        : AlertPrefs.channels;
    return await store.preference(name) != 'off';
  }

  Future<void> _onMessage(StoredMessage stored) async {
    final m = stored.message;
    final c = m.conversation;
    if (m.isReaction) return;
    if (foreground && open == c) return;
    if (!await enabled(c)) return;
    if (await store.isMuted(c, _now())) return;
    final count = _counts[c.key] = (_counts[c.key] ?? 0) + 1;
    final title = await _title(c, m);
    final text = c is ChannelConversation && m.senderName != null
        ? '${m.senderName}: ${m.text}'
        : m.text;
    await notifier.show(
      id: idFor(c),
      title: count > 1 ? '$title ($count)' : title,
      body: text,
      payload: c.key,
    );
  }

  Future<String> _title(Conversation c, Message m) async {
    final title = await store.conversationTitle(c);
    if (c is DirectConversation && title == c.node.short) {
      return m.senderName ?? title;
    }
    return title;
  }

  /// Clears [c]'s notification, e.g. when it is opened.
  Future<void> clear(Conversation c) async {
    _counts.remove(c.key);
    await notifier.cancel(idFor(c));
  }

  Future<void> dispose() => _sub.cancel();
}
