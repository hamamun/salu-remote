import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/client.dart';
import '../core/error_copy.dart';
import '../core/models.dart';
import '../core/reply.dart';
import 'theme.dart';
import 'widgets.dart';

/// The playlist (`remote_apk_ui.md` §4.1): a collapsible card, **at most 5
/// rows visible**, scrolling inside whenever there are more than 5 items
/// (user, 2026-09-22), **auto-scrolls so the now-playing row stays in view**
/// the moment the track changes, a row tap jumps to it, and a clear button
/// in the header empties the whole playlist.
///
/// Row titles come from `queue_get` (titles only, never paths —
/// `remote.md` §17.4), fetched as the **whole queue** in pages of 100 so the
/// list really scrolls from end to end; the auto-scroll position comes from
/// the snapshot's `queue.index`, so the phone never computes playback order
/// itself.
class QueueCard extends StatefulWidget {
  const QueueCard({super.key, required this.snapshot});

  final SaluSnapshot snapshot;

  @override
  State<QueueCard> createState() => _QueueCardState();
}

class _QueueCardState extends State<QueueCard> {
  static const double _rowHeight = 44;
  static const int _visibleRows = 5;

  /// The protocol's per-call cap for `queue_get` (`remote.md` §17.4).
  static const int _pageSize = 100;

  final SaluClient _client = SaluClient.instance;
  final ScrollController _scroll = ScrollController();
  List<QueueRow> _rows = const <QueueRow>[];
  bool _loading = false;
  String? _error;

  /// Bumped by every fetch, so a late reply from an older fetch can never
  /// overwrite a newer one.
  int _fetchGeneration = 0;

  @override
  void initState() {
    super.initState();
    // First paint scrolls straight to the now-playing row: with the whole
    // queue in the list, "5 visible rows" must be the *right* 5.
    unawaited(_fetch(autoscroll: true));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(QueueCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final SaluQueueInfo queue = widget.snapshot.queue;
    final SaluQueueInfo old = oldWidget.snapshot.queue;
    if (queue.count != old.count) {
      // The playlist itself changed (tracks added, queue cleared): refetch.
      unawaited(_fetch(autoscroll: true));
    } else if (queue.index != old.index) {
      // Only the track moved. The whole list is already here, so this is
      // pure local work — bring the new row into view, no network (§8).
      SchedulerBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  /// Fetches the whole queue, [_pageSize] rows per call (the protocol's
  /// cap). For the everyday queue of ≤ 100 items this stays exactly the one
  /// call it always was.
  Future<void> _fetch({bool autoscroll = false}) async {
    final int generation = ++_fetchGeneration;
    final int count = widget.snapshot.queue.count;
    if (count == 0) {
      if (mounted) {
        setState(() {
          _rows = const <QueueRow>[];
          _loading = false;
          _error = null;
        });
      }
      return;
    }
    if (mounted) setState(() => _loading = true);
    final List<QueueRow> all = <QueueRow>[];
    for (int from = 0; from < count; from += _pageSize) {
      final RemoteReply reply =
          await _client.queueGet(from: from, count: _pageSize);
      if (!mounted || generation != _fetchGeneration) return;
      if (!reply.ok || reply['rows'] is! List) {
        setState(() {
          _loading = false;
          _error = RemoteErrorCopy.text(reply.code, reply.message);
        });
        return;
      }
      final List<QueueRow> rows = QueuePage.from(reply.data).rows;
      // An empty page means the PC's queue is shorter than the snapshot
      // claimed (it changed mid-fetch) — show what we have, not a hole.
      if (rows.isEmpty) break;
      all.addAll(rows);
    }
    if (!mounted || generation != _fetchGeneration) return;
    setState(() {
      _rows = all;
      _loading = false;
      _error = null;
    });
    if (autoscroll) {
      // Wait for the new rows to lay out, then bring the current one to
      // the middle of the visible window.
      SchedulerBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  void _scrollToCurrent() {
    if (!mounted || !_scroll.hasClients) return;
    final int position = _rows.indexWhere(
      (QueueRow row) => row.now || row.index == widget.snapshot.queue.index,
    );
    if (position < 0) return;
    final double window = _visibleRows * _rowHeight;
    final double target =
        (position * _rowHeight - window / 2 + _rowHeight / 2).clamp(
              0.0,
              _scroll.position.maxScrollExtent,
            );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _jump(QueueRow row) async {
    final RemoteReply reply = await runRemote(context, () => _client.queueJump(row.index));
    if (reply.ok && mounted) {
      // The PC catches up in the next snapshot; mark the row now so the
      // thumb is not left waiting for it (`remote_apk_ui.md` §8).
      setState(() {
        _rows = _rows
            .map((QueueRow r) => QueueRow(
                  index: r.index,
                  title: r.title,
                  durationMs: r.durationMs,
                  now: r.index == row.index,
                ))
            .toList();
      });
    }
  }

  /// The playlist's clear button (user, 2026-09-22). Destructive, so it asks
  /// first; then one `queue_clear` to the PC. A PC that has not caught up
  /// with the new verb answers `unknown_command` — a code the app otherwise
  /// keeps silent — so the card says the one useful sentence itself instead
  /// of doing invisibly nothing.
  Future<void> _clear() async {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Clear the playlist?'),
        content: const Text('SALU on the PC stops playback and empties the queue.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final RemoteReply reply = await runRemote(context, _client.queueClear);
    if (!mounted) return;
    if (reply.ok) {
      // Optimistic: the next snapshot confirms with `queue.count = 0` and
      // the card steps out of the page on its own.
      _fetchGeneration++; // Any in-flight fetch is now stale.
      setState(() => _rows = const <QueueRow>[]);
      return;
    }
    if (reply.code == 'unknown_command') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clearing the playlist needs a newer SALU on the PC.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final SaluQueueInfo queue = widget.snapshot.queue;
    // Five rows at most; fewer when the queue is shorter. The +1 px per
    // separator keeps the last row from being clipped by its own divider.
    final int shown = _rows.length < _visibleRows ? _rows.length : _visibleRows;
    final double listHeight = shown * _rowHeight + (shown > 1 ? shown - 1 : 0);
    return SectionCard(
      title: 'Queue',
      trailing: '${queue.count} ${queue.count == 1 ? 'item' : 'items'}',
      memoryKey: 'queue',
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      action: IconButton(
        iconSize: 20,
        visualDensity: VisualDensity.compact,
        tooltip: 'Clear playlist',
        color: AppColors.iconIdle,
        onPressed: queue.hasRows && !_loading ? () => unawaited(_clear()) : null,
        icon: const Icon(Icons.playlist_remove),
      ),
      child: _loading
          ? const _SkeletonRows()
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_error!, style: Theme.of(context).textTheme.bodySmall),
                )
              : _rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Nothing in the queue',
                          style: Theme.of(context).textTheme.bodySmall),
                    )
                  : SizedBox(
                      height: listHeight,
                      child: ListView.separated(
                        controller: _scroll,
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (BuildContext context, int i) =>
                            _row(context, _rows[i]),
                      ),
                    ),
    );
  }

  Widget _row(BuildContext context, QueueRow row) {
    final bool now = row.now || row.index == widget.snapshot.queue.index;
    return InkWell(
      onTap: () => unawaited(_jump(row)),
      child: SizedBox(
        height: _rowHeight,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 30,
              child: now
                  ? const Icon(Icons.play_arrow, size: 18, color: AppColors.accent)
                  : Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${row.index + 1}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                row.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: now ? FontWeight.w600 : FontWeight.w400,
                  color: now ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (row.durationMs != null)
              Text(
                SaluTheme.clock(Duration(milliseconds: row.durationMs!)),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 5 * _QueueCardState._rowHeight,
      child: ListView.builder(
        itemCount: 5,
        itemBuilder: (BuildContext context, int i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Container(
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.surfaceHighlight,
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ),
      ),
    );
  }
}
