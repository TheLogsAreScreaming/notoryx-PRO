import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import '../store/mesh_store.dart';

/// How an unlock attempt ended.
enum UnlockResult {
  unlocked,
  failed,

  /// The phone no longer has any screen lock, so there is nothing to check.
  unavailable,
}

/// The phone's own fingerprint, face or passcode check.
abstract interface class DeviceAuth {
  /// Whether this device has a screen lock the app can use.
  Future<bool> available();

  /// Asks the person, saying [reason].
  Future<UnlockResult> unlock(String reason);
}

/// [DeviceAuth] through the system. The phone's passcode is accepted as
/// well as biometrics, so a failed fingerprint reader can't lock anyone out.
class SystemDeviceAuth implements DeviceAuth {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object catch (e) {
      debugPrint('lock: $e');
      return false;
    }
  }

  @override
  Future<UnlockResult> unlock(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        sensitiveTransaction: false,
        persistAcrossBackgrounding: true,
      );
      return ok ? UnlockResult.unlocked : UnlockResult.failed;
    } on LocalAuthException catch (e) {
      debugPrint('lock: ${e.code}');
      return switch (e.code) {
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricHardware => UnlockResult.unavailable,
        _ => UnlockResult.failed,
      };
    }
  }
}

/// The saved lock settings.
@immutable
class LockSettings {
  const LockSettings({this.on = false, this.graceSeconds = 60});

  static const prefName = 'lock';

  final bool on;

  /// How long the app can be away before it locks again. The default
  /// leaves room for the share sheet and file picker.
  final int graceSeconds;

  String encode() => '${on ? 'on' : 'off'};$graceSeconds';

  static LockSettings decode(String? saved) {
    final p = (saved ?? '').split(';');
    return LockSettings(
      on: p.first == 'on',
      graceSeconds: p.length > 1 ? int.tryParse(p[1]) ?? 60 : 60,
    );
  }

  Future<void> save(MeshStore store) => store.setPreference(prefName, encode());

  static Future<LockSettings> load(MeshStore store) async =>
      decode(await store.preference(prefName));
}
