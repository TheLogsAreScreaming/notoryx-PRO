import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app_controller.dart';
import 'app/message_alerts.dart';
import 'store/mesh_store.dart';
import 'ui/app.dart';
import 'ui/map_tiles.dart';
import 'ui/themes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final store = MeshStore.open(File('${dir.path}/notoryx_pro.sqlite'));
  final tiles = await MapTiles.create();
  final notifier = SystemNotifier();
  await notifier.init();
  final theme = await ThemeChoice.load(store);
  runApp(
    NotoryxProApp(
      app: AppController(store: store, notifier: notifier),
      tiles: tiles,
      initialTheme: theme,
    ),
  );
}
