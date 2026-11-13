import 'dart:async';

import 'package:flutter/material.dart';

import '../app/sentinel.dart';
import '../l10n/app_localizations.dart';
import '../mesh/model.dart';
import '../radio/radio_link.dart';

String sentinelReasonLabel(AppLocalizations l, SentinelReason r) => switch (r) {
  SentinelReason.spam => l.sntReasonSpam,
  SentinelReason.flooding => l.sntReasonFlooding,
  SentinelReason.abuse => l.sntReasonAbuse,
  SentinelReason.impersonation => l.sntReasonImpersonation,
  SentinelReason.other => l.sntReasonOther,
};

/// Asks to turn community moderation on. Returns whether it is on now.
Future<bool> ensureSentinelEnabled(
  BuildContext context,
  SentinelService sentinel,
) async {
  if (sentinel.enabled) return true;
  final l = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.sntOffPrompt),
      content: Text('${l.sntIntro}\n\n${l.sntEnableSub}'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(
            MaterialLocalizations.of(dialogContext).cancelButtonLabel,
          ),
        ),
        FilledButton(
          key: const ValueKey('sentinel-turn-on'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l.sntTurnOn),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await sentinel.setEnabled(true);
  return true;
}

/// Reports a node to NOTORYX moderators.
Future<void> showSentinelReportSheet(
  BuildContext context, {
  required SentinelService sentinel,
  required RadioProtocol network,
  required String nodeId,
  required String nodeName,
  String? messageExcerpt,
}) async {
  if (!await ensureSentinelEnabled(context, sentinel)) return;
  if (!context.mounted) return;
  final outcome = await showModalBottomSheet<SentinelReportOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: _ReportSheet(
        sentinel: sentinel,
        network: network,
        nodeId: nodeId,
        nodeName: nodeName,
        messageExcerpt: messageExcerpt,
      ),
    ),
  );
  if (outcome == null || !context.mounted) return;
  final l = AppLocalizations.of(context);
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(switch (outcome) {
        SentinelReportSent(:final caseRef) => l.sntSent(caseRef),
        SentinelReportQueued() => l.sntQueuedOne,
        SentinelReportRejected(:final message) => l.sntRejected(message),
      }),
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.sentinel,
    required this.network,
    required this.nodeId,
    required this.nodeName,
    this.messageExcerpt,
  });

  final SentinelService sentinel;
  final RadioProtocol network;
  final String nodeId;
  final String nodeName;
  final String? messageExcerpt;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  SentinelReason _reason = SentinelReason.spam;
  final _note = TextEditingController();
  bool _includeMessage = true;
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final outcome = await widget.sentinel.report(
      network: widget.network,
      nodeId: widget.nodeId,
      nodeName: widget.nodeName,
      reason: _reason,
      note: _note.text,
      messageExcerpt: _includeMessage ? widget.messageExcerpt : null,
    );
    if (!mounted) return;
    Navigator.pop(context, outcome);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final excerpt = widget.messageExcerpt?.trim();
    final hasExcerpt = excerpt != null && excerpt.isNotEmpty;
    final type = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 16, bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Semantics(
                header: true,
                child: Text(
                  l.sntReportTitle(widget.nodeName),
                  style: type.titleMedium,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
              child: Text(
                '${widget.network.label} · ${widget.nodeId.length > 20 ? '${widget.nodeId.substring(0, 16)}…' : widget.nodeId}',
                style: type.bodySmall,
              ),
            ),
            RadioGroup<SentinelReason>(
              groupValue: _reason,
              onChanged: (r) {
                if (r != null && !_sending) setState(() => _reason = r);
              },
              child: Column(
                children: [
                  for (final r in SentinelReason.values)
                    RadioListTile<SentinelReason>(
                      key: ValueKey('sentinel-reason-${r.name}'),
                      value: r,
                      dense: true,
                      title: Text(sentinelReasonLabel(l, r)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const ValueKey('sentinel-note'),
                controller: _note,
                enabled: !_sending,
                maxLength: SentinelService.maxNote,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(labelText: l.sntNote),
              ),
            ),
            if (hasExcerpt)
              CheckboxListTile(
                key: const ValueKey('sentinel-include-message'),
                value: _includeMessage,
                onChanged: _sending
                    ? null
                    : (v) => setState(() => _includeMessage = v ?? false),
                title: Text(l.sntIncludeMessage),
                subtitle: Text(
                  excerpt,
                  maxLines: 3,
                  overflow: TextOverflow.fade,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(l.sntSends, style: type.bodySmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                key: const ValueKey('sentinel-send-report'),
                onPressed: _sending ? null : () => unawaited(_send()),
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.flag_outlined),
                label: Text(l.sntSend),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small "Flagged" label for a node on the moderators' ban list.
class SentinelFlag extends StatelessWidget {
  const SentinelFlag(this.ban, {super.key});

  final SentinelBan ban;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme.error;
    final hint = l.sntFlaggedHint(ban.caseRef);
    return Tooltip(
      message: hint,
      child: Semantics(
        label: hint,
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flag, size: 11, color: color),
              const SizedBox(width: 3),
              Text(
                l.sntFlagged,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Community moderation: the opt-in switch, the advisory ban lists'
/// status, whether this phone's own radios are flagged, and appeals.
class SentinelPage extends StatelessWidget {
  const SentinelPage({
    super.key,
    required this.sentinel,
    this.ownRadios = const [],
  });

  final SentinelService sentinel;

  /// The radios connected now; their own nodes are checked for bans.
  final List<RadioId> ownRadios;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ml = MaterialLocalizations.of(context);
    String when(DateTime t) {
      final local = t.toLocal();
      return '${ml.formatShortDate(local)} ${ml.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.sntTitle)),
      body: ListenableBuilder(
        listenable: sentinel,
        builder: (context, _) {
          final synced = sentinel.syncedAt;
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(l.sntIntro),
              ),
              SwitchListTile(
                key: const ValueKey('sentinel-enabled'),
                secondary: const Icon(Icons.shield_outlined),
                title: Text(l.sntEnable),
                subtitle: Text(l.sntEnableSub),
                value: sentinel.enabled,
                onChanged: (v) => unawaited(sentinel.setEnabled(v)),
              ),
              if (sentinel.enabled) ...[
                SwitchListTile(
                  key: const ValueKey('sentinel-hide'),
                  secondary: const Icon(Icons.visibility_off_outlined),
                  title: Text(l.sntHide),
                  subtitle: Text(l.sntHideSub),
                  value: sentinel.hideFlagged,
                  onChanged: (v) => unawaited(sentinel.setHideFlagged(v)),
                ),
                const Divider(),
                for (final p in RadioProtocol.values)
                  ListTile(
                    leading: const Icon(Icons.list_alt_outlined),
                    title: Text(
                      '${p.label}: ${l.sntFlaggedCount(sentinel.flaggedCount(p))}',
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: Text(
                    synced == null
                        ? l.sntNeverSynced
                        : l.sntSynced(when(synced)),
                  ),
                  subtitle: sentinel.queuedCount > 0
                      ? Text(l.sntQueued(sentinel.queuedCount))
                      : null,
                  trailing: sentinel.syncing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          key: const ValueKey('sentinel-refresh'),
                          onPressed: () =>
                              unawaited(sentinel.refresh(force: true)),
                          child: Text(l.sntRefresh),
                        ),
                ),
                const Divider(),
                if (ownRadios.isEmpty)
                  ListTile(
                    leading: const Icon(Icons.verified_outlined),
                    title: Text(l.sntYourNode),
                    subtitle: Text(l.sntYourNodeUnknown),
                  ),
                for (final r in ownRadios)
                  Builder(
                    builder: (context) {
                      final ban = sentinel.banForId(r.protocol, r.native);
                      return ListTile(
                        leading: Icon(
                          ban == null ? Icons.verified_outlined : Icons.flag,
                          color: ban == null ? scheme.primary : scheme.error,
                        ),
                        title: Text('${l.sntYourNode} · ${r.protocol.label}'),
                        subtitle: Text(
                          ban == null
                              ? l.sntYourNodeClear
                              : ban.appealPending
                              ? '${l.sntYourNodeFlagged(ban.caseRef)}\n${l.sntAppealPending}'
                              : l.sntYourNodeFlagged(ban.caseRef),
                        ),
                        trailing: ban != null && !ban.appealPending
                            ? FilledButton(
                                onPressed: () => unawaited(
                                  showSentinelAppealDialog(
                                    context,
                                    sentinel: sentinel,
                                    network: r.protocol,
                                    caseRef: ban.caseRef,
                                  ),
                                ),
                                child: Text(l.sntAppeal),
                              )
                            : null,
                      );
                    },
                  ),
                ListTile(
                  key: const ValueKey('sentinel-appeal-other'),
                  leading: const Icon(Icons.gavel_outlined),
                  title: Text(l.sntAppealOther),
                  onTap: () => unawaited(
                    showSentinelAppealDialog(context, sentinel: sentinel),
                  ),
                ),
                if (sentinel.sentReports.isNotEmpty) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Semantics(
                      header: true,
                      child: Text(
                        l.sntYourReports,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
                  for (final r in sentinel.sentReports)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.flag_outlined),
                      title: Text(r.nodeName ?? r.caseRef),
                      subtitle: Text('${r.caseRef} · ${when(r.at)}'),
                    ),
                ],
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  l.sntSends,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Asks for an appeal statement and sends it. Without [network], the user
/// picks which mesh the case is on.
Future<void> showSentinelAppealDialog(
  BuildContext context, {
  required SentinelService sentinel,
  RadioProtocol? network,
  String? caseRef,
}) async {
  final l = AppLocalizations.of(context);
  final caseCtl = TextEditingController(text: caseRef ?? '');
  final statementCtl = TextEditingController();
  final contactCtl = TextEditingController();
  final caseRe = RegExp(r'^SNT-\d{1,10}$', caseSensitive: false);
  var chosen = network ?? RadioProtocol.meshcore;
  try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final valid =
              caseRe.hasMatch(caseCtl.text.trim()) &&
              statementCtl.text.trim().length >= 3;
          return AlertDialog(
            title: Text(l.sntAppeal),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (network == null)
                    SegmentedButton<RadioProtocol>(
                      key: const ValueKey('sentinel-appeal-network'),
                      segments: [
                        for (final p in RadioProtocol.values)
                          ButtonSegment(value: p, label: Text(p.label)),
                      ],
                      selected: {chosen},
                      onSelectionChanged: (s) =>
                          setState(() => chosen = s.first),
                    ),
                  TextField(
                    key: const ValueKey('sentinel-appeal-case'),
                    controller: caseCtl,
                    readOnly: caseRef != null,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(labelText: l.sntCaseRef),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    key: const ValueKey('sentinel-appeal-statement'),
                    controller: statementCtl,
                    maxLength: 2000,
                    minLines: 2,
                    maxLines: 6,
                    decoration: InputDecoration(labelText: l.sntStatement),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    key: const ValueKey('sentinel-appeal-contact'),
                    controller: contactCtl,
                    maxLength: 200,
                    decoration: InputDecoration(labelText: l.sntContact),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  MaterialLocalizations.of(dialogContext).cancelButtonLabel,
                ),
              ),
              FilledButton(
                key: const ValueKey('sentinel-appeal-send'),
                onPressed: valid
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: Text(l.sntAppealSend),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final outcome = await sentinel.appeal(
      network: chosen,
      caseRef: caseCtl.text,
      statement: statementCtl.text,
      contact: contactCtl.text,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(switch (outcome) {
          SentinelAppealOutcome.received => l.sntAppealReceived,
          SentinelAppealOutcome.unknownCase => l.sntAppealUnknown,
          SentinelAppealOutcome.notAppealable => l.sntAppealNotOpen,
          SentinelAppealOutcome.tooMany => l.sntAppealTooMany,
          SentinelAppealOutcome.failed => l.sntFailed,
        }),
      ),
    );
  } finally {
    caseCtl.dispose();
    statementCtl.dispose();
    contactCtl.dispose();
  }
}
