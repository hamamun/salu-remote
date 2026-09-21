import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/client.dart';
import '../core/models.dart';
import '../core/reply.dart';
import 'theme.dart';
import 'widgets.dart';

/// Browse → Streams (`remote_apk_ui.md` §5.2): saved M3U URLs and a URL box.
///
/// The list is **the PC's own library, mirrored** — never a second list on
/// the phone. Add from the phone and it appears on the PC; the health dot is
/// the PC's verdict on each URL.
class StreamsPane extends StatefulWidget {
  const StreamsPane({super.key, required this.activeTab, required this.myIndex});

  /// The root's active-tab notifier; the list refreshes whenever this pane
  /// comes back on screen, so the health dots are never stale.
  final ValueListenable<int> activeTab;
  final int myIndex;

  @override
  State<StreamsPane> createState() => _StreamsPaneState();
}

class _StreamsPaneState extends State<StreamsPane> {
  final SaluClient _client = SaluClient.instance;
  LibraryInfo? _info;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.activeTab.addListener(_onActive);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    widget.activeTab.removeListener(_onActive);
    super.dispose();
  }

  void _onActive() {
    if (widget.activeTab.value == widget.myIndex) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (mounted) setState(() {
      _loading = _info == null;
      _error = null;
    });
    final RemoteReply reply = await _client.libraryGet();
    if (!mounted) return;
    if (reply.ok && reply['entries'] is List) {
      setState(() {
        _info = LibraryInfo.from(reply.data);
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = reply.message;
      });
    }
  }

  // ── add / play / rename / delete ─────────────────────────────────────────

  Future<void> _addDialog() async {
    final TextEditingController url = TextEditingController();
    final TextEditingController name = TextEditingController();
    bool save = true;
    // The one-keyboard rule (§12): the clipboard is checked first.
    Clipboard.getData(Clipboard.kTextPlain).then((ClipboardData? data) {
      if (data?.text case final String? clip when looksLikeUrl(clip ?? '')) {
        url.text = clip!;
      }
    });
    try {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => StatefulBuilder(
          builder: (BuildContext dialogContext, StateSetter setDialogState) =>
              AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Add a URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: url,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'http://… · a YouTube link · an .m3u',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(labelText: 'Name (optional)'),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Save on the PC too',
                  style: TextStyle(fontSize: 13.5)),
              value: save,
              onChanged: (bool? v) => setDialogState(() => save = v ?? false),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            child: Text(looksLikeUrl(url.text) ? 'Play this link' : 'Add stream'),
            onPressed: () {
              final String trimmedUrl = url.text.trim();
              if (trimmedUrl.isEmpty) return;
              final String? nameText =
                  name.text.trim().isEmpty ? null : name.text.trim();
              final bool play = looksLikeUrl(trimmedUrl);
              Navigator.of(dialogContext).pop();
              unawaited(_addAndMaybePlay(trimmedUrl, nameText, save, play));
            },
          ),
        ],
      ),
        ),
      );
    } finally {
      url.dispose();
      name.dispose();
    }
  }

  Future<void> _addAndMaybePlay(String url, String? name, bool save, bool play) async {
    if (save) {
      final RemoteReply saved =
          await runRemote(context, () => _client.libraryAdd(url, name: name, save: true));
      if (!saved.ok) return;
    }
    if (play && mounted) {
      await runRemote(context, () => _client.libraryPlay(url));
    }
    await _refresh();
  }

  Future<void> _rename(LibraryEntryInfo entry) async {
    final TextEditingController name =
        TextEditingController(text: entry.name);
    try {
      final String? result = await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Rename'),
          content: TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(name.text.trim().isEmpty ? null : name.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (result == null || !mounted) return;
      // `library_add` with the same URL is the PC's update door (§17.4).
      await runRemote(context, () => _client.libraryAdd(entry.url, name: result, save: true));
      await _refresh();
    } finally {
      name.dispose();
    }
  }

  Future<void> _rowSheet(LibraryEntryInfo entry) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 10),
            _sheetRow(
              icon: Icons.play_arrow,
              label: 'Play now',
              onTap: () => Navigator.of(sheetContext).pop('play'),
            ),
            _sheetRow(
              icon: Icons.edit_outlined,
              label: 'Rename',
              onTap: () => Navigator.of(sheetContext).pop('rename'),
            ),
            _sheetRow(
              icon: Icons.delete_outline,
              label: 'Delete',
              danger: true,
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'play':
        await runRemote(context, () => _client.libraryPlay(entry.url));
        break;
      case 'rename':
        await _rename(entry);
        break;
      case 'delete':
        // Deletion is allowed here — it is the user's own list, not a file.
        await runRemote(context, () => _client.libraryRemove(entry.url));
        await _refresh();
        break;
      default:
        break;
    }
  }

  Widget _sheetRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final Color colour = danger ? AppColors.statusDead : AppColors.textPrimary;
    return ListTile(
      leading: Icon(icon, color: colour),
      title: Text(label, style: TextStyle(color: colour)),
      onTap: onTap,
    );
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final LibraryInfo? info = _info;
    if (_error != null && info == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          EmptyState(
            message: _error ?? "Could not read the PC's stream list.",
            actionLabel: 'Try again',
            onAction: () => unawaited(_refresh()),
          ),
        ],
      );
    }
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add a URL'),
              onPressed: _error != null ? null : _addDialog,
            ),
          ),
        ),
        Expanded(
          child: info == null
              ? (_loading
                  ? const Center(child: CircularProgressIndicator())
                  : Center(
                      child: Text('No streams saved on the PC yet',
                          style: Theme.of(context).textTheme.bodySmall),
                    ))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: info.entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int i) =>
                        _row(info.entries[i]),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            info == null
                ? 'This is the PC\'s own list.'
                : 'This is the PC\'s own list — currently capped at ${info.maxEntries}.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _row(LibraryEntryInfo entry) {
    return InkWell(
      onTap: () => unawaited(runRemote(context, () => _client.libraryPlay(entry.url))),
      onLongPress: () => unawaited(_rowSheet(entry)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 10),
            HealthDot(health: entry.health),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  Text(
                    entry.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.play_arrow, size: 20, color: AppColors.iconIdle),
          ],
        ),
      ),
    );
  }
}
