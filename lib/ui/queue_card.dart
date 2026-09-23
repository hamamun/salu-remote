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
///
/// Channel grouping (`pc_part.md` §11):
/// - `queue.grouping` from snapshot: available modes + current mode.
/// - Chips row above the list: Flat / Category / Country / Language.
/// - `queue_groups` + `queue_group_set` behind the `unknown_command` hide.
/// - Group header rows inserted inside the queue list; tapping a group
///   jumps to its first channel via existing `queue_jump`.
class QueueCard extends StatefulWidget {
  const QueueCard({super.key, required this.snapshot});

  final SaluSnapshot snapshot;

  @override
  State<QueueCard> createState() => _QueueCardState();
}

class _DisplayItem {
  const _DisplayItem.group(this.group) : row = null;
  const _DisplayItem.row(this.row) : group = null;

  final QueueGroup? group;
  final QueueRow? row;

  bool get isGroup => group != null;
  bool get isRow => row != null;
}

class _QueueCardState extends State<QueueCard> {
  static const double _rowHeight = 44;
  static const int _visibleRows = 5;

  /// The protocol's per-call cap for `queue_get` (`remote.md` §17.4).
  static const int _pageSize = 100;

  /// Delay between paged `queue_get` calls: ~22 pages/s keeps the phone
  /// comfortably under the PC's per-connection budget of 30 commands/s
  /// (which also has to carry pings and live-position traffic).
  static const Duration _pageGap = Duration(milliseconds: 45);

  final SaluClient _client = SaluClient.instance;
  final ScrollController _scroll = ScrollController();
  List<QueueRow> _rows = const <QueueRow>[];
  bool _loading = false;
  String? _error;

  /// Bumped by every fetch, so a late reply from an older fetch can never
  /// overwrite a newer one.
  int _fetchGeneration = 0;

  // ── grouping ───────────────────────────────────────────────────────────────
  // null = unknown yet (haven't probed the PC), true = supported, false = old
  // PC that answered `unknown_command` → chips row hidden entirely.
  bool? _groupingSupported;
  List<QueueGroup> _groups = const <QueueGroup>[];
  bool _groupsLoading = false;
  String? _groupsError;
  int _groupsGeneration = 0;

  late QueueGroupingMode _currentMode = widget.snapshot.queue.grouping.mode;
  late List<QueueGroupingMode> _availableModes =
      widget.snapshot.queue.grouping.available;

  static const List<QueueGroupingMode> _chipOrder = <QueueGroupingMode>[
    QueueGroupingMode.flat,
    QueueGroupingMode.category,
    QueueGroupingMode.country,
    QueueGroupingMode.language,
  ];

  String _modeWire(QueueGroupingMode mode) {
    switch (mode) {
      case QueueGroupingMode.flat:
        return 'flat';
      case QueueGroupingMode.category:
        return 'category';
      case QueueGroupingMode.language:
        return 'language';
      case QueueGroupingMode.country:
        return 'country';
    }
  }

  String _modeLabel(QueueGroupingMode mode) {
    switch (mode) {
      case QueueGroupingMode.flat:
        return 'Flat';
      case QueueGroupingMode.category:
        return 'Category';
      case QueueGroupingMode.country:
        return 'Country';
      case QueueGroupingMode.language:
        return 'Language';
    }
  }

  IconData _modeIcon(QueueGroupingMode mode) {
    switch (mode) {
      case QueueGroupingMode.flat:
        return Icons.view_list;
      case QueueGroupingMode.category:
        return Icons.category;
      case QueueGroupingMode.country:
        return Icons.public;
      case QueueGroupingMode.language:
        return Icons.language;
    }
  }

  @override
  void initState() {
    super.initState();
    _currentMode = widget.snapshot.queue.grouping.mode;
    _availableModes = widget.snapshot.queue.grouping.available;
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

    // Grouping mode / availability changed (e.g. PC pill changed it, or
    // phone's own `queue_group_set` round-tripped via snapshot).
    final QueueGroupingMode newMode = queue.grouping.mode;
    final List<QueueGroupingMode> newAvailable = queue.grouping.available;
    bool groupingChanged = false;
    if (newMode != _currentMode) {
      _currentMode = newMode;
      groupingChanged = true;
    }
    if (!_listEquals(newAvailable, _availableModes)) {
      _availableModes = newAvailable;
      groupingChanged = true;
    }

    if (queue.count != old.count) {
      // The playlist itself changed (tracks added, queue cleared): refetch.
      unawaited(_fetch(autoscroll: true));
    } else if (groupingChanged) {
      // Mode flipped — need new groups, and the list layout changed.
      if (_currentMode == QueueGroupingMode.flat) {
        if (mounted) {
          setState(() {
            _groups = const <QueueGroup>[];
            _groupsLoading = false;
            _groupsError = null;
          });
        }
        SchedulerBinding.instance
            .addPostFrameCallback((_) => _scrollToCurrent());
      } else {
        unawaited(_fetchGroups());
      }
      // Even when flattening, the display list changed, so scroll again.
      if (_currentMode == QueueGroupingMode.flat) {
        SchedulerBinding.instance
            .addPostFrameCallback((_) => _scrollToCurrent());
      }
    } else if (queue.index != old.index) {
      // Only the track moved. The whole list is already here, so this is
      // pure local work — bring the new row into view, no network (§8).
      SchedulerBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    } else if (groupingChanged) {
      // Availability changed without mode change — rebuild chips.
      if (mounted) setState(() {});
    }
  }

  bool _listEquals(List<QueueGroupingMode> a, List<QueueGroupingMode> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Fetches the whole queue, [_pageSize] rows per call (the protocol's
  /// cap). For the everyday queue of ≤ 100 items this stays exactly the one
  /// call it always was.
  ///
  /// Two rules make it channel-list-proof (a 10 000-channel m3u needs ~100
  /// pages, i.e. ~100 commands inside a second):
  /// 1. Pages are paced under the PC's per-phone budget of ~30 commands/s —
  ///    the socket also carries pings and position traffic, so headroom matters.
  /// 2. `too_fast` is never shown on screen (a silent code,
  ///    `error_copy.dart`): the phone waits out the one-second window and
  ///    retries the same page instead. Only if even the retries fail does
  ///    the card fall back to the ordinary "busy" wording — never the
  ///    limiter's raw "Too many commands." text.
  Future<void> _fetch({bool autoscroll = false}) async {
    final int generation = ++_fetchGeneration;
    final int count = widget.snapshot.queue.count;
    if (count == 0) {
      if (mounted) {
        setState(() {
          _rows = const <QueueRow>[];
          _groups = const <QueueGroup>[];
          _loading = false;
          _error = null;
          _groupsLoading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _loading = true);
    final List<QueueRow> all = <QueueRow>[];
    for (int from = 0; from < count; from += _pageSize) {
      RemoteReply reply = await _client.queueGet(from: from, count: _pageSize);
      if (!mounted || generation != _fetchGeneration) return;
      for (int attempt = 0;
          !reply.ok && reply.code == 'too_fast' && attempt < 2;
          attempt++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted || generation != _fetchGeneration) return;
        reply = await _client.queueGet(from: from, count: _pageSize);
        if (!mounted || generation != _fetchGeneration) return;
      }
      if (!reply.ok || reply['rows'] is! List) {
        if (!mounted || generation != _fetchGeneration) return;
        setState(() {
          _loading = false;
          _error = reply.code == 'too_fast'
              ? RemoteErrorCopy.text('busy', null)
              : RemoteErrorCopy.text(reply.code, reply.message);
        });
        return;
      }
      final List<QueueRow> rows = QueuePage.from(reply.data).rows;
      // An empty page means the PC's queue is shorter than the snapshot
      // claimed (it changed mid-fetch) — show what we have, not a hole.
      if (rows.isEmpty) break;
      all.addAll(rows);
      if (from + _pageSize < count) {
        await Future<void>.delayed(_pageGap);
        if (!mounted || generation != _fetchGeneration) return;
      }
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
    // After rows are in, fetch groups if we are in grouped mode.
    unawaited(_fetchGroupsIfNeeded());
  }

  Future<void> _fetchGroupsIfNeeded() async {
    if (_groupingSupported == false) return;
    if (!widget.snapshot.queue.isChannels) return;
    if (_currentMode == QueueGroupingMode.flat) {
      if (_groups.isNotEmpty && mounted) {
        setState(() {
          _groups = const <QueueGroup>[];
          _groupsLoading = false;
        });
      }
      // Probe support even in flat mode when we haven't yet learned whether
      // the PC understands grouping at all (old PC → unknown_command → hide).
      if (_groupingSupported == null) {
        await _fetchGroups(allowFlatProbe: true);
      }
      return;
    }
    await _fetchGroups();
  }

  Future<void> _fetchGroups({bool allowFlatProbe = false}) async {
    if (_groupingSupported == false) return;
    if (!widget.snapshot.queue.isChannels) return;
    if (_currentMode == QueueGroupingMode.flat && !allowFlatProbe) return;

    final int gen = ++_groupsGeneration;
    if (mounted) {
      setState(() {
        _groupsLoading = true;
        _groupsError = null;
      });
    }
    final RemoteReply reply = await _client.queueGroups();
    if (!mounted || gen != _groupsGeneration) return;

    if (reply.ok) {
      // Old PCs answer `unknown_command` → hide chips row entirely.
      final QueueGroupsResult result = QueueGroupsResult.from(reply.data);
      setState(() {
        _groups = result.groups;
        _groupsLoading = false;
        _groupingSupported = true;
        _groupsError = null;
      });
      SchedulerBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
      return;
    }

    if (reply.code == 'unknown_command') {
      // PC doesn't know grouping yet — hide the whole grouping UI, no error.
      setState(() {
        _groupingSupported = false;
        _groups = const <QueueGroup>[];
        _groupsLoading = false;
        _groupsError = null;
      });
      return;
    }

    // Other errors (busy, etc.) — keep previous groups if any, show error.
    setState(() {
      _groupsLoading = false;
      _groupsError = RemoteErrorCopy.text(reply.code, reply.message);
      // Don't mark as unsupported for transient errors.
      if (_groups.isEmpty) {
        // If we had no groups before, treat as empty rather than crash.
        _groups = const <QueueGroup>[];
      }
    });
  }

  Future<void> _setGrouping(QueueGroupingMode mode) async {
    if (mode == _currentMode) return;
    if (mode != QueueGroupingMode.flat && !_availableModes.contains(mode)) {
      // Dimmed chip — unavailable.
      return;
    }
    final QueueGroupingMode previous = _currentMode;
    // Optimistic local update so the chip lights instantly.
    setState(() {
      _currentMode = mode;
      if (mode == QueueGroupingMode.flat) {
        _groups = const <QueueGroup>[];
        _groupsLoading = false;
        _groupsError = null;
      } else {
        _groupsLoading = true;
        _groupsError = null;
      }
    });

    final RemoteReply reply = await _client.queueGroupSet(_modeWire(mode));
    if (!mounted) return;

    if (reply.ok) {
      _groupingSupported = true;
      if (mode != QueueGroupingMode.flat) {
        // The snapshot will soon carry the new mode; fetch groups now too
        // so the list updates without waiting for the next snapshot tick.
        unawaited(_fetchGroups());
      }
      return;
    }

    if (reply.code == 'unknown_command') {
      setState(() {
        _groupingSupported = false;
        _groups = const <QueueGroup>[];
        _groupsLoading = false;
        _currentMode = previous;
      });
      return;
    }

    // Failure — revert and show why.
    setState(() {
      _currentMode = previous;
      _groupsLoading = false;
    });
    if (context.mounted && !RemoteErrorCopy.isSilent(reply.code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RemoteErrorCopy.text(reply.code, reply.message))),
      );
    }
  }

  List<_DisplayItem> _buildDisplayItems() {
    if (_rows.isEmpty) return const <_DisplayItem>[];

    // Flat mode or no groups or unsupported or not a channel list → plain rows.
    if (_currentMode == QueueGroupingMode.flat ||
        _groupingSupported == false ||
        !widget.snapshot.queue.isChannels ||
        _groups.isEmpty) {
      return _rows.map((QueueRow r) => _DisplayItem.row(r)).toList();
    }

    // Grouped: merge groups + rows.
    final List<QueueRow> sortedRows = List<QueueRow>.from(_rows)
      ..sort((QueueRow a, QueueRow b) => a.index.compareTo(b.index));
    final List<QueueGroup> sortedGroups = List<QueueGroup>.from(_groups)
      ..sort((QueueGroup a, QueueGroup b) => a.start.compareTo(b.start));

    final List<_DisplayItem> out = <_DisplayItem>[];
    int rowPtr = 0;

    for (int gIdx = 0; gIdx < sortedGroups.length; gIdx++) {
      final QueueGroup group = sortedGroups[gIdx];
      final int nextStart = gIdx + 1 < sortedGroups.length
          ? sortedGroups[gIdx + 1].start
          : 1 << 30;
      int groupEnd = group.start + group.count;
      if (groupEnd > nextStart) groupEnd = nextStart;

      // Orphan rows before this group's start (shouldn't happen in grouped
      // mode, but keep them rather than dropping).
      while (rowPtr < sortedRows.length &&
          sortedRows[rowPtr].index < group.start) {
        out.add(_DisplayItem.row(sortedRows[rowPtr]));
        rowPtr++;
      }

      // Group header.
      out.add(_DisplayItem.group(group));

      // Rows belonging to this group.
      while (rowPtr < sortedRows.length &&
          sortedRows[rowPtr].index < groupEnd) {
        if (sortedRows[rowPtr].index >= group.start) {
          out.add(_DisplayItem.row(sortedRows[rowPtr]));
        }
        rowPtr++;
      }
    }

    // Any remaining rows after last group.
    while (rowPtr < sortedRows.length) {
      out.add(_DisplayItem.row(sortedRows[rowPtr]));
      rowPtr++;
    }

    return out;
  }

  int _findCurrentDisplayIndex(List<_DisplayItem> display) {
    final int queueIndex = widget.snapshot.queue.index;
    // Prefer the row marked `now`, fallback to queue.index.
    int targetRowIndex = -1;
    for (final _DisplayItem item in display) {
      if (item.isRow) {
        if (item.row!.now) {
          targetRowIndex = display.indexOf(item);
          break;
        }
      }
    }
    if (targetRowIndex < 0) {
      for (int i = 0; i < display.length; i++) {
        final _DisplayItem item = display[i];
        if (item.isRow && item.row!.index == queueIndex) {
          targetRowIndex = i;
          break;
        }
      }
    }
    // If still not found, try to find the group containing the current index.
    if (targetRowIndex < 0 && display.isNotEmpty) {
      for (int i = 0; i < display.length; i++) {
        final _DisplayItem item = display[i];
        if (item.isGroup) {
          final QueueGroup g = item.group!;
          if (queueIndex >= g.start && queueIndex < g.start + g.count) {
            targetRowIndex = i;
            break;
          }
        }
      }
    }
    return targetRowIndex;
  }

  void _scrollToCurrent() {
    if (!mounted || !_scroll.hasClients) return;
    if (_rows.isEmpty) return;
    final List<_DisplayItem> display = _buildDisplayItems();
    if (display.isEmpty) return;
    final int position = _findCurrentDisplayIndex(display);
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
    final RemoteReply reply =
        await runRemote(context, () => _client.queueJump(row.index));
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

  Future<void> _jumpGroup(QueueGroup group) async {
    final RemoteReply reply =
        await runRemote(context, () => _client.queueJump(group.start));
    if (reply.ok && mounted) {
      setState(() {
        _rows = _rows
            .map((QueueRow r) => QueueRow(
                  index: r.index,
                  title: r.title,
                  durationMs: r.durationMs,
                  now: r.index == group.start,
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
      _groupsGeneration++; // Groups are stale too.
      setState(() {
        _rows = const <QueueRow>[];
        _groups = const <QueueGroup>[];
      });
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
    final List<_DisplayItem> display = _buildDisplayItems();
    // Five rows at most; fewer when the queue is shorter. The +1 px per
    // separator keeps the last row from being clipped by its own divider.
    final int shown = display.length < _visibleRows ? display.length : _visibleRows;
    final double listHeight =
        shown * _rowHeight + (shown > 1 ? shown - 1 : 0).toDouble();

    final bool showGroupingChips =
        queue.isChannels && _groupingSupported != false;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (showGroupingChips) ...<Widget>[
            _groupingChips(),
            const SizedBox(height: 8),
          ],
          if (_loading)
            const _SkeletonRows()
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            )
          else if (display.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Nothing in the queue',
                  style: Theme.of(context).textTheme.bodySmall),
            )
          else
            SizedBox(
              height: listHeight,
              child: Stack(
                children: <Widget>[
                  ListView.separated(
                    controller: _scroll,
                    itemCount: display.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int i) {
                      final _DisplayItem item = display[i];
                      if (item.isGroup) {
                        return _groupHeader(context, item.group!);
                      } else {
                        return _row(context, item.row!);
                      }
                    },
                  ),
                  if (_groupsLoading)
                    Positioned(
                      right: 4,
                      top: 2,
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (_groupsError != null && !_loading)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _groupsError!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _groupingChips() {
    // Same look-grammar as the PC pill: icon chips row above the queue list —
    // Flat / Category / Country / Language, selected one bright, unavailable
    // ones dim.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final QueueGroupingMode mode in _chipOrder) ...<Widget>[
            _groupingChip(mode),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _groupingChip(QueueGroupingMode mode) {
    final bool isSelected = _currentMode == mode;
    final bool isAvailable = mode == QueueGroupingMode.flat ||
        _availableModes.contains(mode);
    // Unavailable ones dim — same as PC pill.
    final bool enabled = isAvailable;

    return Material(
      color: isSelected ? AppColors.surfaceHighlight : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? AppColors.accent : AppColors.surfaceOutline,
          width: isSelected ? 1.4 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: enabled ? () => unawaited(_setGrouping(mode)) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                _modeIcon(mode),
                size: 16,
                color: isSelected
                    ? AppColors.accent
                    : enabled
                        ? AppColors.iconIdle
                        : AppColors.statusUnknown,
              ),
              const SizedBox(width: 6),
              Text(
                _modeLabel(mode),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? AppColors.textPrimary
                      : enabled
                          ? AppColors.textSecondary
                          : AppColors.statusUnknown,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupHeader(BuildContext context, QueueGroup group) {
    final int currentIndex = widget.snapshot.queue.index;
    final bool containsNow =
        currentIndex >= group.start && currentIndex < group.start + group.count;
    return InkWell(
      onTap: () => unawaited(_jumpGroup(group)),
      child: Container(
        height: _rowHeight,
        color: containsNow
            ? AppColors.surfaceHighlight
            : AppColors.videoBackdrop,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.folder_special,
              size: 18,
              color: containsNow ? AppColors.accent : AppColors.iconIdle,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: containsNow ? FontWeight.w700 : FontWeight.w600,
                  color: containsNow
                      ? AppColors.textPrimary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.surfaceOutline, width: 0.8),
              ),
              child: Text(
                '${group.count}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                    ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.play_arrow,
              size: 18,
              color: containsNow ? AppColors.accent : AppColors.iconIdle,
            ),
          ],
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
