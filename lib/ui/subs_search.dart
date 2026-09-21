import 'dart:async';

import 'package:flutter/material.dart';

import '../core/client.dart';
import '../core/error_copy.dart';
import '../core/models.dart';
import '../core/reply.dart';
import 'theme.dart';
import 'widgets.dart';

/// The OpenSubtitles search screen (`remote_apk_ui.md` §6.2) — the PC's own
/// engine, driven from the couch. The query is pre-filled with the PC's
/// current title and the language with the PC's saved preference
/// (the one-keyboard rule, §12).
///
/// Tapping *Download* is `saveAndLoad` on the PC: the file lands beside the
/// media with SALU's own naming rule and is loaded immediately — the
/// subtitle is on screen before your thumb leaves the phone.
class SubsSearchScreen extends StatefulWidget {
  const SubsSearchScreen({
    super.key,
    required this.snapshot,
    required this.initialQuery,
    required this.initialLang,
    this.onLoaded,
  });

  final SaluSnapshot snapshot;
  final String initialQuery;
  final String initialLang;
  final VoidCallback? onLoaded;

  @override
  State<SubsSearchScreen> createState() => _SubsSearchScreenState();
}

class _SubsSearchScreenState extends State<SubsSearchScreen> {
  final SaluClient _client = SaluClient.instance;
  late final TextEditingController _query;
  late final TextEditingController _lang;
  List<SubtitleRow> _results = const <SubtitleRow>[];
  bool _searched = false;
  bool _searching = false;
  String? _searchError;
  int? _downloadingFileId;
  int _loadedFileId = -1;

  SubtitleEngine get _engine => widget.snapshot.subs.engine;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialQuery);
    _lang = TextEditingController(text: widget.initialLang);
  }

  @override
  void dispose() {
    _query.dispose();
    _lang.dispose();
    super.dispose();
  }

  bool get _canDownload => _engine.signedIn && !_engine.quotaPaused;

  Future<void> _search() async {
    final String query = _query.text.trim();
    if (query.isEmpty || _searching) return;
    final String lang = _lang.text.trim();
    setState(() {
      _searching = true;
      _searchError = null;
    });
    final RemoteReply reply =
        await _client.subsSearch(query, language: lang.isEmpty ? null : lang);
    if (!mounted) return;
    if (reply.ok) {
      final Object? raw = reply['results'] ?? reply['rows'];
      final List<SubtitleRow> rows = raw is List
          ? raw
              .whereType<Map>()
              .map((Map m) => SubtitleRow.from(m.cast<String, Object?>()))
              .toList()
          : const <SubtitleRow>[];
      setState(() {
        _results = rows;
        _searched = true;
        _searching = false;
      });
    } else {
      setState(() {
        _searching = false;
        _searchError = RemoteErrorCopy.text(reply.code, reply.message);
      });
    }
  }

  Future<void> _download(SubtitleRow row) async {
    if (_downloadingFileId != null || !_canDownload) return;
    setState(() => _downloadingFileId = row.fileId);
    final RemoteReply reply =
        await runRemote(context, () => _client.subsDownload(row.fileId));
    if (!mounted) return;
    setState(() => _downloadingFileId = null);
    if (reply.ok) {
      setState(() => _loadedFileId = row.fileId);
      widget.onLoaded?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loaded — it is on the PC screen now.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text('Subtitles'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: <Widget>[
          // ── the ask ─────────────────────────────────────────────────────
          SaluCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: _query,
                  decoration: const InputDecoration(labelText: 'What to search for'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _lang,
                        textCapitalization: TextCapitalization.none,
                        decoration: const InputDecoration(
                          labelText: 'Language',
                          hintText: 'en',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed:
                          _engine.key && !_searching && _query.text.trim().isNotEmpty
                              ? () => unawaited(_search())
                              : null,
                      child: Text(_searching ? 'Searching…' : 'Search'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!_engine.key)
            _notice('Add an OpenSubtitles key on the PC to search.'),
          if (_engine.key && !_engine.signedIn)
            _notice('Search works, but signing in on the PC is needed to download.'),
          if (_engine.quotaPaused)
            _notice('OpenSubtitles download limit reached — try again tomorrow.'),
          const SizedBox(height: 14),
          // ── the results ─────────────────────────────────────────────────
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_searchError != null)
            EmptyState(
              message: _searchError!,
              actionLabel: 'Try again',
              onAction: () => unawaited(_search()),
            )
          else if (!_searched)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'The PC searches OpenSubtitles and downloads — the subtitle '
                'lands beside your media and loads immediately.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else if (_results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Nothing found on OpenSubtitles.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            for (final SubtitleRow row in _results) _resultCard(row),
        ],
      ),
    );
  }

  Widget _notice(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline, size: 16, color: AppColors.statusDead),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.statusDead, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(SubtitleRow row) {
    final bool downloading = _downloadingFileId == row.fileId;
    final bool loaded = _loadedFileId == row.fileId;
    final String meta = <String>[
      if (row.release != null && row.release!.isNotEmpty) row.release!,
      if (row.ext != null && row.ext!.isNotEmpty) row.ext!.toUpperCase(),
      if (row.downloads > 0) '${row.downloads} downloads',
    ].join(' · ');
    return SaluCard(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            row.language,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            row.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (row.subLine != null && row.subLine!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                row.subLine!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.statusUnknown,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: loaded
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.check_circle, size: 18, color: AppColors.statusAlive),
                      SizedBox(width: 6),
                      Text('Loaded', style: TextStyle(color: AppColors.statusAlive)),
                    ],
                  )
                : FilledButton(
                    onPressed: _canDownload && !downloading
                        ? () => unawaited(_download(row))
                        : null,
                    child: downloading
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('Downloading…'),
                            ],
                          )
                        : const Text('Download'),
                  ),
          ),
        ],
      ),
    );
  }
}
