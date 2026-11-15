import 'package:flutter/foundation.dart';

/// How the person chose to show a node: a colour, a photo, or both (the
/// photo wins). Kept on this device only; never sent over the mesh.
@immutable
class NodeLook {
  const NodeLook({this.color, this.photo});

  /// ARGB.
  final int? color;

  /// A small PNG.
  final Uint8List? photo;

  bool get isEmpty => color == null && photo == null;
}
