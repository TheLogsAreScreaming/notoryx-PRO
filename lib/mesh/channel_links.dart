import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../meshtastic/protobuf.dart';
import '../radio/radio_link.dart';
import 'identity.dart';

/// A channel someone can join: its name and key, in either mesh's terms.
class ChannelInvite {
  const ChannelInvite({
    required this.protocol,
    required this.name,
    required this.secret,
  });

  /// A MeshCore hashtag channel: anyone who knows the name can join, since
  /// its secret is the first 16 bytes of SHA-256 of the name with its `#`.
  factory ChannelInvite.hashtag(String name) {
    final n = name.trim();
    final tagged = n.startsWith('#') ? n : '#$n';
    return ChannelInvite(
      protocol: RadioProtocol.meshcore,
      name: tagged,
      secret: Uint8List.fromList(
        sha256.convert(utf8.encode(tagged)).bytes.sublist(0, 16),
      ),
    );
  }

  /// A new private channel with a random key: 16 bytes for MeshCore,
  /// 32 (AES-256) for Meshtastic.
  factory ChannelInvite.private(
    RadioProtocol protocol,
    String name, {
    Random? random,
  }) {
    final r = random ?? Random.secure();
    final n = protocol == RadioProtocol.meshcore ? 16 : 32;
    return ChannelInvite(
      protocol: protocol,
      name: name.trim(),
      secret: Uint8List.fromList(List.generate(n, (_) => r.nextInt(256))),
    );
  }

  final RadioProtocol protocol;
  final String name;

  /// MeshCore: the 16-byte channel secret. Meshtastic: the PSK (empty for
  /// none, one byte for a default key, 16 or 32 bytes for AES).
  final Uint8List secret;

  /// The link to share, in each mesh's own format so the official apps can
  /// read it too.
  String toLink() {
    switch (protocol) {
      case RadioProtocol.meshcore:
        final q = Uri(
          queryParameters: {'name': name, 'secret': hexOf(secret)},
        ).query;
        return 'meshcore://channel/add?$q';
      case RadioProtocol.meshtastic:
        final settings = ProtoWriter()
          ..bytes(2, secret)
          ..string(3, name);
        final set = ProtoWriter()..bytes(1, settings.toBytes(), always: true);
        final b64 = base64Url.encode(set.toBytes()).replaceAll('=', '');
        return 'https://meshtastic.org/e/?add=true#$b64';
    }
  }

  /// Reads channel links: MeshCore `meshcore://channel/add?...` (one
  /// channel) or Meshtastic `meshtastic.org/e/#...` (possibly several).
  /// Empty for anything else.
  static List<ChannelInvite> parse(String text) {
    final s = text.trim();
    if (s.startsWith('meshcore://')) {
      final uri = Uri.tryParse(s);
      final secret = bytesOfHex(uri?.queryParameters['secret'] ?? '');
      final name = uri?.queryParameters['name'] ?? '';
      if (uri == null || secret.length != 16 || name.isEmpty) return const [];
      return [
        ChannelInvite(
          protocol: RadioProtocol.meshcore,
          name: name,
          secret: secret,
        ),
      ];
    }
    final at = s.indexOf('meshtastic.org/e/');
    if (at < 0) return const [];
    final hash = s.indexOf('#', at);
    if (hash < 0) return const [];
    var b64 = s.substring(hash + 1).split(RegExp(r'\s')).first;
    b64 = b64.padRight((b64.length + 3) ~/ 4 * 4, '=');
    try {
      final out = <ChannelInvite>[];
      for (final f in readFields(base64Url.decode(b64))) {
        if (f.number != 1) continue;
        var name = '';
        var psk = Uint8List(0);
        for (final c in readFields(f.asBytes)) {
          if (c.number == 2) psk = c.asBytes;
          if (c.number == 3) name = c.asString;
        }
        out.add(
          ChannelInvite(
            protocol: RadioProtocol.meshtastic,
            name: name,
            secret: psk,
          ),
        );
      }
      return out;
    } on FormatException {
      return const [];
    } on ProtobufException {
      return const [];
    }
  }

  /// Whether this is a MeshCore hashtag channel (its secret follows from
  /// its name).
  bool get isHashtag =>
      protocol == RadioProtocol.meshcore &&
      name.startsWith('#') &&
      hexOf(ChannelInvite.hashtag(name).secret) == hexOf(secret);
}
