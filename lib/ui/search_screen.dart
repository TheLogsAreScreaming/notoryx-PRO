import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../store/mesh_store.dart';
import 'common.dart';
import 'conversation_screen.dart';

/// Finds messages across every conversation on both meshes.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.app});

  final AppController app;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _field = TextEditingController();
  String _query = '';
  List<(StoredMessage, String)> _results = const [];
  bool _searched = false;

  MeshStore get _store => widget.app.store;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _search(String text) async {
    final query = text.trim();
    _query = query;
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
      });
      return;
    }
    final found = await _store.searchMessages(query);
    final titles = <String, String>{};
    for (final s in found) {
      final c = s.message.conversation;
      titles[c.key] ??= await _store.conversationTitle(c);
    }
    // A newer search has started; its results are the ones to show.
    if (!mounted || query != _query) return;
    setState(() {
      _results = [
        for (final s in found) (s, titles[s.message.conversation.key]!),
      ];
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const Key('search-field'),
          controller: _field,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l.searchHint,
            border: InputBorder.none,
          ),
          onChanged: _search,
        ),
      ),
      body: _searched && _results.isEmpty
          ? EmptyState(l.searchNone, icon: Icons.search_off)
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final (stored, title) = _results[i];
                final m = stored.message;
                return ListTile(
                  leading: ProtocolBadge(m.conversation.radioId.protocol),
                  title: Text(title),
                  subtitle: Text(m.text),
                  trailing: Text(ago(context, m.receivedAt)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ConversationScreen(
                        app: widget.app,
                        conversation: m.conversation,
                        title: title,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
