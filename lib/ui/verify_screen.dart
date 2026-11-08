import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/app_controller.dart';
import '../mesh/mesh.dart';
import 'common.dart';

/// Badge for a node's trust status; nothing when unverified.
class TrustBadge extends StatelessWidget {
  const TrustBadge(this.status, {super.key, this.size = 16});

  final TrustStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      TrustStatus.unverified => const SizedBox.shrink(),
      TrustStatus.verified => Tooltip(
        message: l.trustVerified,
        child: Icon(
          Icons.verified,
          size: size,
          color: scheme.primary,
          semanticLabel: l.trustVerified,
        ),
      ),
      TrustStatus.keyChanged => Tooltip(
        message: l.trustKeyChanged,
        child: Icon(
          Icons.gpp_maybe,
          size: size,
          color: scheme.error,
          semanticLabel: l.trustKeyChanged,
        ),
      ),
    };
  }
}

/// Confirm that a node's key belongs to who you think it does.
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({
    super.key,
    required this.app,
    required this.node,
    this.scan,
  });

  final AppController app;
  final Node node;

  /// Opens a scanner and returns what it read; replaceable in tests.
  final Future<String?> Function(BuildContext context)? scan;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  late final Stream<Map<NodeKey, Verification>> _verifications = widget
      .app
      .store
      .watchVerifications();

  Node get node => widget.node;

  ContactCard? get _ownCard =>
      widget.app.connectionForRadio(node.radioId)?.ownCard;

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _check(String? text) async {
    if (text == null || !mounted) return;
    final l = context.l10n;
    final card = ContactCard.parse(text);
    if (card == null) return _say(l.verifyNotALink);
    if (!cardMatches(card, node)) return _say(l.verifyMismatch);
    await widget.app.store.verify(
      node.key,
      node.publicKey,
      VerificationMethod.qr,
    );
    if (mounted) _say(l.verifyDone(node.displayName));
  }

  Future<void> _paste() async {
    final l = context.l10n;
    final text = await showTextPrompt(
      context,
      title: l.verifyPaste,
      confirm: l.verifyConfirm,
      hint: l.verifyPasteHint,
    );
    await _check(text);
  }

  Future<void> _compared() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.verifyMatchConfirm(node.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.radiosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.verifyConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.app.store.verify(
      node.key,
      node.publicKey,
      VerificationMethod.compared,
    );
    if (mounted) _say(l.verifyDone(node.displayName));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final own = _ownCard;
    return Scaffold(
      appBar: AppBar(title: Text(l.verifyTitle(node.displayName))),
      body: StreamBuilder<Map<NodeKey, Verification>>(
        stream: _verifications,
        builder: (context, snap) {
          final v = snap.data?[node.key];
          final status = trustOf(node, v);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l.verifyIntro),
              const SizedBox(height: 16),
              if (status != TrustStatus.unverified)
                ListTile(
                  leading: TrustBadge(status, size: 28),
                  title: Text(
                    status == TrustStatus.verified
                        ? l.trustVerified
                        : l.trustKeyChanged,
                  ),
                ),
              _Fingerprint(
                label: l.verifyTheirCode,
                value: node.publicKey.isEmpty
                    ? null
                    : keyFingerprint(node.publicKey),
                missing: l.verifyNoKey,
              ),
              _Fingerprint(
                label: l.verifyYourCode,
                value: own == null || own.publicKey.isEmpty
                    ? null
                    : keyFingerprint(own.publicKey),
                missing: l.verifyNoOwnRadio,
              ),
              const SizedBox(height: 16),
              if (node.publicKey.isNotEmpty) ...[
                FilledButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(l.verifyScan),
                  onPressed: () async =>
                      _check(await (widget.scan ?? openScanner)(context)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.content_paste),
                  label: Text(l.verifyPaste),
                  onPressed: _paste,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.compare_arrows),
                  label: Text(l.verifyMatch),
                  onPressed: _compared,
                ),
              ],
              if (own != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.qr_code),
                  label: Text(l.verifyShowMine),
                  onPressed: () => showMyCode(context, own),
                ),
              ],
              if (v != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => widget.app.store.unverify(node.key),
                  child: Text(l.verifyRemove),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Fingerprint extends StatelessWidget {
  const _Fingerprint({
    required this.label,
    required this.value,
    required this.missing,
  });

  final String label;
  final String? value;
  final String missing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        value == null
            ? Text(missing)
            : SelectableText(
                value!,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 1.5,
                ),
              ),
      ],
    ),
  );
}

/// Shows this radio's contact code as a QR code, link and fingerprint.
Future<void> showMyCode(BuildContext context, ContactCard card) {
  final l = context.l10n;
  final link = card.toLink();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.myCodeTitle(card.name),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                data: link,
                size: 240,
                semanticsLabel: l.myCodeTitle(card.name),
              ),
            ),
            const SizedBox(height: 12),
            if (card.publicKey.isNotEmpty)
              Text(
                keyFingerprint(card.publicKey),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontFamily: 'monospace'),
              ),
            const SizedBox(height: 8),
            Text(l.myCodeHelp, textAlign: TextAlign.center),
            TextButton.icon(
              icon: const Icon(Icons.copy),
              label: Text(l.verifyCopy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l.verifyCopied)));
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Opens the camera and returns the first QR code it reads.
Future<String?> openScanner(BuildContext context) => Navigator.of(
  context,
).push<String>(MaterialPageRoute(builder: (_) => const _ScanScreen()));

class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.scanTitle)),
    body: MobileScanner(
      onDetect: (capture) {
        final value = capture.barcodes.firstOrNull?.rawValue;
        if (value == null || _done) return;
        _done = true;
        Navigator.pop(context, value);
      },
    ),
  );
}
