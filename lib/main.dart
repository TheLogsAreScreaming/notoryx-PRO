import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app_controller.dart';
import 'store/mesh_store.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final store = MeshStore.open(File('${dir.path}/notoryx_pro.sqlite'));
  runApp(NotoryxProApp(app: AppController(store: store)));
}
