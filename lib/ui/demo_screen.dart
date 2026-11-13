import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../demo/demo_radio.dart';
import '../store/mesh_store.dart';
import 'app.dart';
import 'common.dart';

/// The whole app, running on a pretend radio with its own throwaway
/// database, so nothing touches real messages and nothing is transmitted.
class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key, this.links});

  /// Replaceable in tests.
  final DemoLinks? links;

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  late final AppController _app = AppController(
    store: MeshStore.memory(),
    links: widget.links ?? DemoLinks(),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_app.connect(demoTarget));
  }

  @override
  void dispose() {
    final app = _app;
    unawaited(app.shutdown().whenComplete(app.store.close));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: s.tertiaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.demoBanner,
                      style: TextStyle(color: s.onTertiaryContainer),
                    ),
                  ),
                  TextButton(
                    key: const Key('demo-exit'),
                    style: TextButton.styleFrom(
                      foregroundColor: s.onTertiaryContainer,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.demoExit),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: HomeShell(app: _app),
          ),
        ),
      ],
    );
  }
}
