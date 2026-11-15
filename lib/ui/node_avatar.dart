import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../mesh/node_look.dart';
import 'common.dart';
import 'themes.dart';

/// A node's chosen photo or colour, or [icon] when there's neither.
///
/// Decorative: the row or marker around it already names the node.
class NodeAvatar extends StatelessWidget {
  const NodeAvatar({
    super.key,
    required this.app,
    required this.nodeKey,
    required this.icon,
    this.size = 40,
    this.iconColor,
  });

  final AppController app;

  /// `NodeKey` text.
  final String nodeKey;
  final IconData icon;
  final double size;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, NodeLook>>(
        valueListenable: app.looks,
        builder: (context, looks, _) {
          final look = looks[nodeKey];
          final photo = look?.photo;
          final color = look?.color;
          Widget child;
          if (photo != null) {
            child = ClipOval(
              child: Image.memory(
                photo,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _circle(context, color),
              ),
            );
          } else if (color != null) {
            child = _circle(context, color);
          } else {
            child = SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: iconColor),
            );
          }
          return ExcludeSemantics(child: child);
        },
      );

  Widget _circle(BuildContext context, int? argb) {
    final fill = argb == null
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Color(argb);
    final onFill = onChosenColor(fill);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Icon(icon, color: onFill, size: size * 0.55),
    );
  }
}

/// Colours offered for a node, ARGB, with names for screen readers.
const nodeLookColors = [
  0xFFD32F2F,
  0xFFF57C00,
  0xFFFBC02D,
  0xFF388E3C,
  0xFF00897B,
  0xFF1976D2,
  0xFF7B1FA2,
  0xFFC2185B,
  0xFF5D4037,
  0xFF616161,
];

String _colorName(BuildContext context, int i) {
  final l = context.l10n;
  return [
    l.lookRed,
    l.lookOrange,
    l.lookYellow,
    l.lookGreen,
    l.lookTeal,
    l.lookBlue,
    l.lookPurple,
    l.lookPink,
    l.lookBrown,
    l.lookGrey,
  ][i];
}

/// Shrinks a picked photo to a 256-pixel square PNG, so it stays small in
/// the database and in backups.
Future<Uint8List> shrinkPhoto(Uint8List bytes, {int size = 256}) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: size,
    targetHeight: size,
  );
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  return data!.buffer.asUint8List();
}

/// Picks a photo file; null if cancelled.
Future<Uint8List?> pickNodePhoto() async {
  final picked = await FilePicker.pickFiles(type: FileType.image);
  final path = picked.firstOrNull?.path;
  if (path == null) return null;
  return File(path).readAsBytes();
}

/// Lets the person choose a colour or photo for a node, or clear it.
Future<void> showNodeLookSheet(
  BuildContext context, {
  required AppController app,
  required String nodeKey,
  required String name,
  Future<Uint8List?> Function() pick = pickNodePhoto,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (context) {
    final l = context.l10n;
    final current = app.looks.value[nodeKey];
    Future<void> set(NodeLook look) async {
      await app.store.setNodeLook(nodeKey, look);
      if (context.mounted) Navigator.pop(context);
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.lookTitle(name),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(l.lookHelp),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, c) in nodeLookColors.indexed)
                  Semantics(
                    button: true,
                    selected: current?.color == c && current?.photo == null,
                    label: _colorName(context, i),
                    excludeSemantics: true,
                    child: InkWell(
                      key: Key('look-color-$i'),
                      customBorder: const CircleBorder(),
                      onTap: () => set(NodeLook(color: c)),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: current?.color == c
                              ? Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  width: 3,
                                )
                              : null,
                        ),
                        child: current?.color == c && current?.photo == null
                            ? Icon(Icons.check, color: onChosenColor(Color(c)))
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              key: const Key('look-photo'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.photo_outlined),
              title: Text(l.lookPhoto),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final bytes = await pick();
                  if (bytes == null) return;
                  final photo = await shrinkPhoto(bytes);
                  await set(NodeLook(color: current?.color, photo: photo));
                } on Object {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l.lookPhotoFailed)),
                  );
                }
              },
            ),
            if (current != null && !current.isEmpty)
              ListTile(
                key: const Key('look-clear'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.clear),
                title: Text(l.lookClear),
                onTap: () => set(const NodeLook()),
              ),
          ],
        ),
      ),
    );
  },
);
