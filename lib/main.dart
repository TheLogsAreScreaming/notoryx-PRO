import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app_controller.dart';
import 'app/app_lock.dart';
import 'app/message_alerts.dart';
import 'store/database_vault.dart';
import 'store/mesh_store.dart';
import 'ui/app.dart';
import 'ui/encryption_tile.dart';
import 'ui/map_tiles.dart';
import 'ui/themes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/notoryx_pro.sqlite');
  final vault = DatabaseVault(file, SecureKeyVault());
  final String? key;
  try {
    key = await vault.prepare();
  } on DatabaseKeyMissing {
    runApp(KeyMissingApp(vault: vault));
    return;
  }
  final store = MeshStore.open(file, key: key);
  final tiles = await MapTiles.create();
  final notifier = SystemNotifier();
  await notifier.init();
  final theme = await ThemeChoice.load(store);
  final lock = await LockSettings.load(store);
  runApp(
    NotoryxProApp(
      app: AppController(store: store, notifier: notifier),
      tiles: tiles,
      initialTheme: theme,
      auth: SystemDeviceAuth(),
      vault: vault,
      startLocked: lock.on,
    ),
  );
}
