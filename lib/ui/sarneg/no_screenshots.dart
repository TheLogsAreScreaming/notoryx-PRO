// Blocks screenshots and screen recording while a SARNEG screen is showing.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Turns the platform's screenshot block on or off for the whole window.
abstract interface class ScreenCaptureBlocker {
  /// Blocks screenshots and recording when [blocked] is true; allows them
  /// again when false.
  Future<void> setBlocked(bool blocked);
}

/// The real block, through the "notoryx/screen_capture" channel.
///
/// Android sets FLAG_SECURE (screenshots and recordings come out black, and
/// the app is blank in Recents). Windows excludes the window from capture.
/// macOS hides the window from screen sharing and capture where the system
/// allows it. iOS has no way to block screenshots, so nothing happens there.
class PlatformScreenCaptureBlocker implements ScreenCaptureBlocker {
  /// Creates the blocker.
  const PlatformScreenCaptureBlocker();

  static const _channel = MethodChannel('notoryx/screen_capture');

  @override
  Future<void> setBlocked(bool blocked) async {
    if (kIsWeb ||
        !(Platform.isAndroid || Platform.isMacOS || Platform.isWindows)) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setBlocked', blocked);
    } on MissingPluginException {
      // Older native build without the channel: nothing to block with.
    } on PlatformException catch (e, s) {
      debugPrint('Screen capture block failed: $e\n$s');
    }
  }
}

/// Counts the [NoScreenshots] widgets on screen and blocks capture while
/// there is at least one, so two overlapping SARNEG screens don't unblock
/// each other.
class ScreenCaptureGuard {
  /// Creates a guard that drives [blocker].
  ScreenCaptureGuard(this.blocker);

  /// What actually turns the block on and off.
  ScreenCaptureBlocker blocker;

  int _holders = 0;

  /// Whether capture is blocked right now.
  bool get blocked => _holders > 0;

  /// One more screen needs the block.
  void acquire() {
    _holders++;
    if (_holders == 1) unawaited(blocker.setBlocked(true));
  }

  /// One screen no longer needs it.
  void release() {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) unawaited(blocker.setBlocked(false));
  }
}

/// The app-wide guard. Tests may swap its [ScreenCaptureGuard.blocker].
final ScreenCaptureGuard screenCaptureGuard = ScreenCaptureGuard(
  const PlatformScreenCaptureBlocker(),
);

/// Blocks screenshots and screen recording while this widget is on screen
/// and [enabled] is true.
class NoScreenshots extends StatefulWidget {
  /// Wraps [child].
  const NoScreenshots({required this.child, this.enabled = true, super.key});

  /// What to show.
  final Widget child;

  /// Whether to block right now.
  final bool enabled;

  @override
  State<NoScreenshots> createState() => _NoScreenshotsState();
}

class _NoScreenshotsState extends State<NoScreenshots> {
  bool _holding = false;

  void _sync() {
    if (widget.enabled && !_holding) {
      _holding = true;
      screenCaptureGuard.acquire();
    } else if (!widget.enabled && _holding) {
      _holding = false;
      screenCaptureGuard.release();
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(NoScreenshots oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    if (_holding) screenCaptureGuard.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
