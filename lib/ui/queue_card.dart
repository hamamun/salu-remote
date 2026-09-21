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
/// rows**, scrolling inside, **auto-scrolls so the now-playing row stays in
/// view** the moment the track changes, and a row tap jumps to it.
///
/// Row titles come from `queue_get` (titles only, never paths —
/// `remote.md` §17.4); the auto-scroll position comes from the snapshot's
/// `queue.index`, so the phone never computes playback order itself.
class QueueCard extends StatefulWidget {
  const QueueCard({super.key, required this.snapshot});

  final SaluSnapshot snapshot;

  @override
  State<QueueCard> createState() => _QueueCardState();
}

class _QueueCardState extends State<QueueCard> {
  static const double _rowHeight = 44;
  static const int _visibleRows = 5;

  final SaluClient _client = SaluClient.instance;
  final ScrollController _scroll = ScrollController();
  List<QueueRow> _rows = const <QueueRow>[];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(QueueCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The track changed under us: refetch a window around the new row and
    // bring it into view.
    final bool moved = widget.snapshot.queue.index != oldWidget.snapshot.queue.index ||
        widget.snapshot.queue.count != oldWidget.snapshot.queue.count;
    if (moved) {
      unawaited(_fetch(autoscroll: true));
    }
  }

  Future<void> _fetch({bool autoscroll = false}) async {
    final int count = widget.snapshot.queue.count;
    if (count == 0) {
      if (mounted) setState(() => _rows = const <QueueRow>[]);
      return;
    }
    if (mounted) setState(() => _loading = true);
    // A window around the current row: enough for five visible rows plus a
    // hand's reach on either side. The PC pages and clamps (§17.2).
    final int index = widget.snapshot.queue.index;
    final int from = (index < 2 ? 0 : index - 2).clamp(0, count);
    final reply = await _client.queueGet(from: from, count: 100);
    if (!mounted) return;
    if (reply.ok && reply['rows'] is List) {
      setState(() {
        _rows = QueuePage.from(reply.data).rows;
        _loading = false;
        _error = null;
      });
      if (autoscroll) {
        // Wait for the new rows to lay out, then bring the current one to
        // the middle of the visible window.
        SchedulerBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
      }
    } else {
      setState(() {
        _loading = false;
        _error = RemoteErrorCopy.text(reply.code, reply.message);
      });
    }
  }

  void _scrollToCurrent() {
    if (!_scroll.hasClients) return;
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

  @override
  Widget build(BuildContext context) {
    final SaluQueueInfo queue = widget.snapshot.queue;
    return SectionCard(
      title: 'Queue',
      trailing: '${queue.count} ${queue.count == 1 ? 'item' : 'items'}',
      memoryKey: 'queue',
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
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
                      height: _visibleRows * _rowHeight,
                      child: ListView.separated(
                        controller: _scroll,
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
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
