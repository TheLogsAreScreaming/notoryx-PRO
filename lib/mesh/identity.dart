import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../meshtastic/protobuf.dart';
import '../radio/radio_link.dart';
import 'model.dart';

/// A short, human-comparable form of a public key: six groups of four hex
/// digits from its SHA-256, e.g. `a1b2 c3d4 e5f6 0718 9abc def0`.
///
/// Two people compare these out loud or side by side; matching groups mean
/// both phones see the same key.
String keyFingerprint(List<int> publicKey) {
  final digest = sha256.convert(publicKey).bytes.sublist(0, 12);
  final hex = digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return [
    for (var i = 0; i < hex.length; i += 4) hex.substring(i, i + 4),
  ].join(' ');
}

/// Hex of [bytes].
String hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Bytes of [hex]; empty if it isn't valid hex.
Uint8List bytesOfHex(String hex) {
  if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) {
    return Uint8List(0);
  }
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

/// A confirmed key.
class Verification {
  const Verification({
    required this.node,
    required this.publicKey,
    required this.at,
    required this.method,
  });

  final NodeKey node;
  final Uint8List publicKey;
  final DateTime at;
  final VerificationMethod method;
}

/// How a key was confirmed.
enum VerificationMethod {
  /// Scanned the other person's code.
  qr,

  /// Compared fingerprints in person.
  compared,
}

/// Where a node stands.
enum TrustStatus {
  /// Not confirmed.
  unverified,

  /// Confirmed, and the key hasn't changed since.
  verified,

  /// Confirmed once, but the node now shows a different key.
  keyChanged,
}

/// The trust status of [node] given its stored [verification].
TrustStatus trustOf(Node node, Verification? verification) {
  if (verification == null) return TrustStatus.unverified;
  final key = node.publicKey;
  if (key.isEmpty) return TrustStatus.verified;
  return hexOf(key) == hexOf(verification.publicKey)
      ? TrustStatus.verified
      : TrustStatus.keyChanged;
}

/// Display names used by more than one node on the same radio, lower-cased
/// and keyed by radio, so a post under such a name can be flagged.
Map<RadioId, Set<String>> nameClashes(Iterable<Node> nodes) {
  final seen = <RadioId, Map<String, Set<NodeKey>>>{};
  for (final n in nodes) {
    final name = n.name.trim().toLowerCase();
    if (name.isEmpty) continue;
    seen
        .putIfAbsent(n.radioId, () => {})
        .putIfAbsent(name, () => {})
        .add(n.key);
  }
  return {
    for (final MapEntry(key: radio, value: names) in seen.entries)
      radio: {
        for (final MapEntry(key: name, value: keys) in names.entries)
          if (keys.length > 1) name,
      },
  };
}

/// Someone's contact details as shared in a QR code or link.
class ContactCard {
  const ContactCard({
    required this.protocol,
    required this.name,
    required this.publicKey,
    this.nodeNum,
    this.shortName = '',
    this.meshCoreType = 1,
  });

  final RadioProtocol protocol;
  final String name;

  /// MeshCore identity key, or Meshtastic encryption key (may be empty for
  /// Meshtastic nodes without one).
  final Uint8List publicKey;

  /// Meshtastic node number.
  final int? nodeNum;
  final String shortName;

  /// MeshCore contact type: 1 companion, 2 repeater, 3 room, 4 sensor.
  final int meshCoreType;

  /// The node this card describes.
  NodeKey get key => protocol == RadioProtocol.meshcore
      ? NodeKey.meshcore(hexOf(publicKey))
      : NodeKey.meshtastic(nodeNum!);

  /// The link to put in a QR code, in each mesh's own format so the
  /// official apps can read it too.
  String toLink() {
    switch (protocol) {
      case RadioProtocol.meshcore:
        final q = Uri(
          queryParameters: {
            'name': name,
            'public_key': hexOf(publicKey),
            'type': '$meshCoreType',
          },
        ).query;
        return 'meshcore://contact/add?$q';
      case RadioProtocol.meshtastic:
        final user = ProtoWriter()
          ..string(1, meshtasticNodeId(nodeNum!))
          ..string(2, name)
          ..string(3, shortName)
          ..bytes(8, publicKey);
        final contact = ProtoWriter()
          ..uint(1, nodeNum!, always: true)
          ..bytes(2, user.toBytes(), always: true);
        final b64 = base64Url.encode(contact.toBytes()).replaceAll('=', '');
        return 'https://meshtastic.org/v/#$b64';
    }
  }

  /// Reads a MeshCore `meshcore://contact/add` link or a Meshtastic
  /// `meshtastic.org/v/#` link; null for anything else.
  static ContactCard? parse(String text) {
    final s = text.trim();
    if (s.startsWith('meshcore://contact/add')) {
      final uri = Uri.tryParse(s);
      final key = bytesOfHex(uri?.queryParameters['public_key'] ?? '');
      if (uri == null || key.length != 32) return null;
      return ContactCard(
        protocol: RadioProtocol.meshcore,
        name: uri.queryParameters['name'] ?? '',
        publicKey: key,
        meshCoreType: int.tryParse(uri.queryParameters['type'] ?? '') ?? 1,
      );
    }
    final hash = s.indexOf('meshtastic.org/v/#');
    if (hash >= 0) {
      var b64 = s.substring(hash + 'meshtastic.org/v/#'.length);
      b64 = b64.padRight((b64.length + 3) ~/ 4 * 4, '=');
      try {
        final bytes = base64Url.decode(b64);
        int? num;
        var name = '', short = '';
        var key = Uint8List(0);
        for (final f in readFields(bytes)) {
          if (f.number == 1) num = f.asInt;
          if (f.number == 2) {
            for (final u in readFields(f.asBytes)) {
              switch (u.number) {
                case 2:
                  name = u.asString;
                case 3:
                  short = u.asString;
                case 8:
                  key = u.asBytes;
              }
            }
          }
        }
        if (num == null) return null;
        return ContactCard(
          protocol: RadioProtocol.meshtastic,
          name: name,
          publicKey: key,
          nodeNum: num,
          shortName: short,
        );
      } on FormatException {
        return null;
      } on ProtobufException {
        return null;
      }
    }
    return null;
  }
}

/// Whether a scanned [card] confirms [node]: same node and, when both
/// sides have one, the same key.
bool cardMatches(ContactCard card, Node node) {
  if (card.key != node.key) return false;
  // A node number alone proves nothing; a key must be compared.
  if (card.publicKey.isEmpty || node.publicKey.isEmpty) return false;
  return hexOf(card.publicKey) == hexOf(node.publicKey);
}
