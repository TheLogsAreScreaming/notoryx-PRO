import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../mesh/diagnostics.dart';
import '../mesh/model.dart';
import '../radio/radio.dart';

/// Shortcut to the generated strings.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Colours that tell the two meshes apart. Each badge also shows the
/// protocol's name, so colour is never the only signal.
///
/// Light mode uses darker shades so badge text stays readable on white.
Color protocolColor(RadioProtocol p, ColorScheme scheme) {
  final light = scheme.brightness == Brightness.light;
  return switch (p) {
    RadioProtocol.meshcore =>
      light ? const Color(0xFFA84A05) : const Color(0xFFE0782A),
    RadioProtocol.meshtastic =>
      light ? const Color(0xFF2F6B12) : const Color(0xFF67C23A),
  };
}

String protocolName(BuildContext context, RadioProtocol p) => switch (p) {
  RadioProtocol.meshcore => context.l10n.protocolMeshCore,
  RadioProtocol.meshtastic => context.l10n.protocolMeshtastic,
};

/// A small labelled chip naming the mesh something came from.
class ProtocolBadge extends StatelessWidget {
  const ProtocolBadge(this.protocol, {super.key});

  final RadioProtocol protocol;

  @override
  Widget build(BuildContext context) {
    final color = protocolColor(protocol, Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        protocolName(context, protocol),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

/// "2 hops · SNR 6.5 dB · -97 dBm · via internet".
String pathSummary(BuildContext context, PathFacts p) {
  final l = context.l10n;
  final parts = <String>[
    if (p.hops != null) l.pathHops(p.hops!),
    if (p.hops == null && p.route == RouteKind.direct) l.pathDirect,
    if (p.snr != null) l.pathSnr(p.snr!.toStringAsFixed(1)),
    if (p.rssi != null) l.pathRssi(p.rssi!),
    if (p.viaMqtt) l.pathMqtt,
  ];
  return parts.join(' · ');
}

/// "5 min ago" style time.
String ago(BuildContext context, DateTime when, {DateTime? now}) {
  final l = context.l10n;
  final d = (now ?? DateTime.now()).difference(when);
  if (d.inMinutes < 1) return l.agoNow;
  if (d.inHours < 1) return l.agoMinutes(d.inMinutes);
  if (d.inDays < 1) return l.agoHours(d.inHours);
  return l.agoDays(d.inDays);
}

IconData nodeKindIcon(NodeKind kind) => switch (kind) {
  NodeKind.person => Icons.person_outline,
  NodeKind.relay => Icons.cell_tower,
  NodeKind.room => Icons.forum_outlined,
  NodeKind.sensor => Icons.sensors,
  NodeKind.unknown => Icons.radio_button_unchecked,
};

String nodeKindName(BuildContext context, NodeKind kind) {
  final l = context.l10n;
  return switch (kind) {
    NodeKind.person => l.nodeKindPerson,
    NodeKind.relay => l.nodeKindRelay,
    NodeKind.room => l.nodeKindRoom,
    NodeKind.sensor => l.nodeKindSensor,
    NodeKind.unknown => l.nodeKindUnknown,
  };
}

/// An icon and label for a message's delivery.
(IconData, String) deliveryLook(BuildContext context, DeliveryState s) {
  final l = context.l10n;
  return switch (s) {
    Pending() => (Icons.schedule, l.deliveryPending),
    Sent() => (Icons.check, l.deliverySent),
    Relayed() => (Icons.repeat, l.deliveryRelayed),
    Delivered() => (Icons.done_all, l.deliveryDelivered),
    Failed(:final reason) => (Icons.error_outline, l.deliveryFailed(reason)),
    Received() => (Icons.call_received, ''),
  };
}

/// A centred message for empty lists.
class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

/// 0–4 signal bars with a spoken label; shows a dash when unknown.
class SignalBars extends StatelessWidget {
  const SignalBars(this.bars, {super.key, this.size = 16});

  /// 0–4, or null when the signal isn't known.
  final int? bars;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = bars == null
        ? context.l10n.signalUnknown
        : context.l10n.signalBars(bars!);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          child: SizedBox(
            width: size,
            height: size,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0.75),
                      child: FractionallySizedBox(
                        heightFactor: (i + 1) / 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: bars != null && i < bars!
                                ? scheme.primary
                                : scheme.outlineVariant,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Text for a delivery hint.
String hintText(BuildContext context, DeliveryHint h) {
  final l = context.l10n;
  return switch (h) {
    DeliveryHint.notHeardRecently => l.hintNotHeardRecently,
    DeliveryHint.noRoute => l.hintNoRoute,
    DeliveryHint.longRoute => l.hintLongRoute,
    DeliveryHint.weakSignal => l.hintWeakSignal,
    DeliveryHint.needsYourContact => l.hintNeedsYourContact,
    DeliveryHint.unknownKey => l.hintUnknownKey,
    DeliveryHint.radioBusy => l.hintRadioBusy,
  };
}

/// Asks for one line of text in a dialog; null when cancelled. The dialog
/// owns its text field, so nothing is disposed while it is still closing.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  required String confirm,
  String initial = '',
  String? label,
  String? hint,
  String? Function(String text)? validate,
  Key? fieldKey,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextPrompt(
    title: title,
    confirm: confirm,
    initial: initial,
    label: label,
    hint: hint,
    validate: validate,
    fieldKey: fieldKey,
  ),
);

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.confirm,
    required this.initial,
    this.label,
    this.hint,
    this.validate,
    this.fieldKey,
  });

  final String title;
  final String confirm;
  final String initial;
  final String? label;
  final String? hint;
  final String? Function(String text)? validate;
  final Key? fieldKey;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final _controller = TextEditingController(text: widget.initial);
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: TextFormField(
        key: widget.fieldKey,
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
        ),
        validator: widget.validate == null
            ? null
            : (v) => widget.validate!((v ?? '').trim()),
        onFieldSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.radiosCancel),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.confirm)),
    ],
  );
}
