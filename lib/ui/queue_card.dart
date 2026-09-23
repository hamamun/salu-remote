import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/client.dart';
import '../core/error_copy.dart';
import '../core/models.dart';
import '../core/prefs.dart';
import '../core/queue_view.dart';
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
/// The header mirrors the PC panel's header (Salu
/// `lib/ui/panels/playlist_panel.dart`): the search bar sits beside Queue
/// with its count and its clear button inside it, and the favourites
/// bookmark sits beside the clear button (channels only).
///
/// Channel grouping (`pc_part.md` §11):
/// - `queue.grouping` from snapshot: available modes + current mode.
/// - Chips row above the list: Flat / Category / Country / Language.
/// - `queue_groups` + `queue_group_set` behind the `unknown_command` hide.
/// - Grouped modes are the PC's accordion: by default every head stays
///   collapsed and only the played channel's group is expanded (autohide)
///   — a head tap toggles, it never plays, and the group holding the
///   playing channel opens on its own at every mode choice and track
///   change. While the PC's heads load, the list waits (skeleton) instead
///   of flashing the full flat list the PC never shows.
/// - A search flattens the list whatever the mode is (PC §10.3) — the
///   grouping is suspended, not forgotten.
/// - Favourites are chosen on this phone (titles only — the phone never
///   holds URLs or m3u metadata) and thin the rows when the header
///   bookmark is on, exactly like the PC's favourites-only filter.
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

  /// Delay between paged `queue_get` calls: ~22 pages/s keeps the phone
  /// comfortably under the PC's per-connection budget of 30 commands/s
  /// (which also has to carry pings and live-position traffic).
  static const Duration _pageGap = Duration(milliseconds: 45);

  final SaluClient _client = SaluClient.instance;
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtl = TextEditingController();
  List<QueueRow> _rows = const <QueueRow>[];
  bool _loading = false;
  String? _error;

  /// Collapsed/expanded, remembered per section (`remote_apk_ui.md` §3).
  late bool _expanded;

  /// The search bar's trimmed query. Filters rows by title; while
  /// non-empty the grouping is suspended and the list is flat (PC §10.3).
  String _query = '';

  /// Favourites-only filter (the header bookmark, channels only) + the
  /// favourite titles themselves, persisted on this phone.
  bool _favOnly = false;
  Set<String> _favs = const <String>{};

  /// The accordion's one open head (its stable PC key), or null while
  /// every group is collapsed. A head tap toggles it; a mode choice and a
  /// track change open the group holding the playing channel.
  String? _openGroupKey;

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
    _expanded = !RemotePrefs.instance.isCollapsed('queue');
    _favs = RemotePrefs.instance.channelFavourites;
    // First paint scrolls straight to the now-playing row: with the whole
    // queue in the list, "5 visible rows" must be the *right* 5.
    unawaited(_fetch(autoscroll: true));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtl.dispose();
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
    final bool modeChanged = newMode != _currentMode;
    final bool availChanged = !_listEquals(newAvailable, _availableModes);

    if (queue.count != old.count || queue.kind != old.kind) {
      // The playlist itself changed (tracks added, queue cleared, a new
      // channel load): refetch. A channel load starts blank (the PC's
      // `_onLoadGeneration`) — no search, no favourites filter, accordion
      // closed — and the old heads belong to the old list either way.
      setState(() {
        if (modeChanged) _currentMode = newMode;
        if (availChanged) _availableModes = newAvailable;
        if (queue.isChannels) {
          _searchCtl.clear();
          _query = '';
          _favOnly = false;
        }
        _groups = const <QueueGroup>[];
        _groupsLoading = false;
        _groupsError = null;
        _openGroupKey = null;
      });
      unawaited(_fetch(autoscroll: true));
    } else if (modeChanged || availChanged) {
      if (modeChanged) {
        // Mode flipped — the old heads belong to the old mode. The fetch
        // below re-opens the group holding the playing channel.
        setState(() {
          _currentMode = newMode;
          _availableModes = newAvailable;
          _groups = const <QueueGroup>[];
          _groupsError = null;
          _openGroupKey = null;
          _groupsLoading = newMode != QueueGroupingMode.flat;
        });
        if (newMode != QueueGroupingMode.flat) {
          unawaited(_fetchGroups());
        }
        SchedulerBinding.instance
            .addPostFrameCallback((_) => _scrollToCurrent());
      } else if (mounted) {
        // Availability only — chips need rebuild.
        setState(() => _availableModes = newAvailable);
      }
    } else if (queue.index != old.index) {
      // Only the track moved. The whole list is already here, so this is
      // pure local work — open the destination group when the playing
      // channel sits in another one (the PC's `_revealOnChannelIndex`),
      // then bring the new row into view, no network (§8).
      _openPlayingGroup();
      SchedulerBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
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
      // Fresh heads open the group holding the playing channel (the PC's
      // `_chooseMode` rule) — a head the phone never had to ask for.
      final String? autoOpen = _currentMode == QueueGroupingMode.flat
          ? null
          : groupKeyForIndex(result.groups, widget.snapshot.queue.index);
      setState(() {
        _groups = result.groups;
        _groupsLoading = false;
        _groupingSupported = true;
        _groupsError = null;
        _openGroupKey = autoOpen;
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
    // Optimistic local update so the chip lights instantly. The old heads
    // belong to the old mode, so the list falls back to flat rows until
    // the new heads arrive — never wrong-mode heads.
    setState(() {
      _currentMode = mode;
      _groups = const <QueueGroup>[];
      _openGroupKey = null;
      _groupsError = null;
      _groupsLoading = mode != QueueGroupingMode.flat;
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

    // Failure — revert and show why. The previous mode's heads were
    // cleared above, so they are fetched back.
    setState(() {
      _currentMode = previous;
      _groupsLoading = false;
    });
    if (previous != QueueGroupingMode.flat) unawaited(_fetchGroups());
    if (context.mounted && !RemoteErrorCopy.isSilent(reply.code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RemoteErrorCopy.text(reply.code, reply.message))),
      );
    }
  }

  /// Opens the accordion group holding the playing channel (the PC's
  /// `_chooseMode` / `_revealOnChannelIndex` rule). A no-op in Flat and
  /// while the heads are still loading.
  void _openPlayingGroup() {
    if (_currentMode == QueueGroupingMode.flat) return;
    if (!widget.snapshot.queue.isChannels) return;
    final String? key = groupKeyForIndex(_groups, widget.snapshot.queue.index);
    if (key != null && key != _openGroupKey && mounted) {
      setState(() => _openGroupKey = key);
    }
  }

  /// A head tap toggles the accordion — it never plays (PC §10.5). The
  /// now-hidden channels come back on the next tap, and the playing
  /// channel's group re-opens on its own at the next track change.
  void _toggleGroup(QueueGroup group) {
    setState(
      () => _openGroupKey = _openGroupKey == group.key ? null : group.key,
    );
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    unawaited(RemotePrefs.instance.setCollapsed('queue', !_expanded));
  }

  void _clearSearch() {
    _searchCtl.clear();
    setState(() => _query = '');
    // The accordion is back — bring the playing row into view.
    SchedulerBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  /// Saves or unsaves a channel as a favourite of this phone. Titles only —
  /// the phone never holds the stable channel keys the PC uses, so the
  /// title is the key (the PC's own last resort).
  void _toggleFav(String title) {
    final Set<String> next = Set<String>.of(_favs);
    if (!next.remove(title)) next.add(title);
    setState(() => _favs = Set<String>.unmodifiable(next));
    unawaited(RemotePrefs.instance.setChannelFavourites(next));
  }

  List<QueueDisplayItem> _buildDisplayItems() {
    if (_rows.isEmpty) return const <QueueDisplayItem>[];

    // The accordion applies only in a grouped mode on a channel list whose
    // PC answered `queue_groups` — while the heads load, the list stays
    // flat rows rather than wrong-mode heads.
    final bool grouped = _currentMode != QueueGroupingMode.flat &&
        _groupingSupported != false &&
        widget.snapshot.queue.isChannels &&
        _groups.isNotEmpty;
    return buildQueueDisplay(
      rows: _rows,
      groups: _groups,
      grouped: grouped,
      openGroupKey: _openGroupKey,
      query: _query,
      favouritesOnly: _favOnly && widget.snapshot.queue.isChannels,
      favourites: _favs,
    );
  }

  int _findCurrentDisplayIndex(List<QueueDisplayItem> display) {
    final int queueIndex = widget.snapshot.queue.index;
    // Prefer the row marked `now`, fallback to queue.index.
    for (int i = 0; i < display.length; i++) {
      final QueueDisplayItem item = display[i];
      if (item.isRow && item.row!.now) return i;
    }
    for (int i = 0; i < display.length; i++) {
      final QueueDisplayItem item = display[i];
      if (item.isRow && item.row!.index == queueIndex) return i;
    }
    // The playing channel hides inside a collapsed group — scroll to its
    // head instead (the PC's reveal target rule).
    for (int i = 0; i < display.length; i++) {
      final QueueDisplayItem item = display[i];
      if (item.isGroup) {
        final QueueGroup g = item.group!;
        if (queueIndex >= g.start && queueIndex < g.start + g.count) return i;
      }
    }
    return -1;
  }

  void _scrollToCurrent() {
    if (!mounted || !_scroll.hasClients) return;
    if (_rows.isEmpty) return;
    final List<QueueDisplayItem> display = _buildDisplayItems();
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
      // A zap also opens the destination group (the PC's reveal rule).
      final String? dest = groupKeyForIndex(_groups, row.index);
      setState(() {
        if (dest != null &&
            _currentMode != QueueGroupingMode.flat &&
            widget.snapshot.queue.isChannels) {
          _openGroupKey = dest;
        }
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
      _groupsGeneration++; // Groups are stale too.
      setState(() {
        _rows = const <QueueRow>[];
        _groups = const <QueueGroup>[];
        _openGroupKey = null;
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

  String _emptyLine(SaluQueueInfo queue) {
    if (_query.isNotEmpty) return 'No matches for "$_query".';
    if (_favOnly && queue.isChannels) {
      return 'No favourites yet — tap the bookmark on a channel to save it here.';
    }
    return 'Nothing in the queue';
  }

  @override
  Widget build(BuildContext context) {
    final SaluQueueInfo queue = widget.snapshot.queue;
    final List<QueueDisplayItem> display = _buildDisplayItems();
    int shown = 0;
    for (final QueueDisplayItem item in display) {
      if (item.isRow) shown++;
    }
    // Five rows at most; fewer when the queue is shorter. The +1 px per
    // separator keeps the last row from being clipped by its own divider.
    // Group heads count as rows — the window is a height, not a kind.
    final int windowed =
        display.length < _visibleRows ? display.length : _visibleRows;
    final double listHeight =
        windowed * _rowHeight + (windowed > 1 ? windowed - 1 : 0).toDouble();

    final bool showGroupingChips =
        queue.isChannels && _groupingSupported != false;

    // Grouped mode never shows the full flat list: until the PC's heads
    // arrive the list waits instead of flashing every channel (the PC
    // computes its heads synchronously — the phone waits one round-trip
    // rather than showing an "everything expanded" moment that the PC
    // never has). A search still flattens immediately: it needs no heads.
    final bool awaitingHeads = _currentMode != QueueGroupingMode.flat &&
        queue.isChannels &&
        _groupingSupported != false &&
        _groups.isEmpty &&
        _query.isEmpty;

    // The header mirrors the PC panel's header: the search bar sits beside
    // Queue with its count and its clear button inside it, and the
    // favourites bookmark sits beside the clear button (channels only).
    return SaluCard(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _toggleExpanded,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: 20,
                        color: AppColors.iconIdle,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'Queue',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 6),
                      // The total count lives here beside Queue — named
                      // "channels" on a channel list so the total channel
                      // count is unmistakable — and again inside the
                      // search bar (`14`, or `9 / 14` while filtered).
                      Text(
                        queue.isChannels
                            ? '${queue.count} ${queue.count == 1 ? 'channel' : 'channels'}'
                            : '${queue.count} ${queue.count == 1 ? 'item' : 'items'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _searchField(shown)),
              if (queue.isChannels)
                IconButton(
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  tooltip: _favOnly
                      ? 'Showing favourites — tap to show all channels'
                      : 'Show favourites only',
                  color: _favOnly ? AppColors.accent : AppColors.iconIdle,
                  onPressed: () => setState(() => _favOnly = !_favOnly),
                  icon: Icon(
                    _favOnly ? Icons.bookmark : Icons.bookmark_border,
                  ),
                ),
              IconButton(
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                tooltip: 'Clear playlist',
                color: AppColors.iconIdle,
                onPressed:
                    queue.hasRows && !_loading ? () => unawaited(_clear()) : null,
                icon: const Icon(Icons.playlist_remove),
              ),
            ],
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
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
                      child: Text(_error!,
                          style: Theme.of(context).textTheme.bodySmall),
                    )
                  else if (awaitingHeads && _groupsLoading)
                    const _SkeletonRows()
                  else if (awaitingHeads)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _groupsError ?? 'No groups found.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  else if (display.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_emptyLine(queue),
                          style: Theme.of(context).textTheme.bodySmall),
                    )
                  else
                    SizedBox(
                      height: listHeight,
                      child: Stack(
                        children: <Widget>[
                          ListView.separated(
                            controller: _scroll,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: display.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (BuildContext context, int i) {
                              final QueueDisplayItem item = display[i];
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
                  // The groups error line stays out while the list area
                  // itself is already showing it (the failed-heads case
                  // above) — one sentence, never two.
                  if (_groupsError != null && !_loading && !awaitingHeads)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _groupsError!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The search bar beside Queue (the PC header's field, phone scale): the
  /// magnifier names it — no placeholder text — the count lives inside it
  /// (`14`, or `9 / 14` while a filter thins the list), and the ✕ clears
  /// the text — only while there is some.
  Widget _searchField(int shown) {
    final int total = _rows.length;
    // `_favOnly` is channels-only (the header bookmark hides on file
    // queues), so it counts as filtering only there.
    final bool filtering =
        _query.isNotEmpty || (_favOnly && widget.snapshot.queue.isChannels);
    final bool noMatch = filtering && shown == 0;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: noMatch
              ? AppColors.iconIdle.withAlpha(120)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.search,
            size: 16,
            color: noMatch
                ? AppColors.iconIdle.withAlpha(95)
                : AppColors.iconIdle,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _searchCtl,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
              cursorColor: AppColors.textPrimary,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
              ),
              onChanged: (String value) {
                setState(() {
                  _query = value.trim();
                  // Typing into a collapsed card opens it — a filter must
                  // be seen to be believed.
                  if (!_expanded) {
                    _expanded = true;
                    unawaited(
                      RemotePrefs.instance.setCollapsed('queue', false),
                    );
                  }
                });
                if (_query.isEmpty) {
                  // The accordion is back — bring the playing row into view.
                  SchedulerBinding.instance
                      .addPostFrameCallback((_) => _scrollToCurrent());
                }
              },
            ),
          ),
          Text(
            filtering ? '$shown / $total' : '$total',
            style: const TextStyle(
              color: Color(0xFF7C7C80),
              fontSize: 10,
            ),
          ),
          // ✕ clears the text — only while there is some.
          if (_query.isNotEmpty) ...<Widget>[
            const SizedBox(width: 2),
            Tooltip(
              message: 'Clear search',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _clearSearch,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    size: 15,
                    color: AppColors.iconIdle,
                  ),
                ),
              ),
            ),
          ],
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

  /// One group head (PC §10.5): `twist · name · count`. A tap toggles the
  /// accordion — heads never play, so there is no play affordance here.
  /// The head holding the playing channel keeps the accent twist.
  Widget _groupHeader(BuildContext context, QueueGroup group) {
    final bool open = group.key == _openGroupKey;
    final int currentIndex = widget.snapshot.queue.index;
    final bool containsNow =
        currentIndex >= group.start && currentIndex < group.start + group.count;
    return Tooltip(
      message: open ? 'Hide these channels' : 'Show these channels',
      child: InkWell(
        onTap: () => _toggleGroup(group),
        child: Container(
          height: _rowHeight,
          color: containsNow
              ? AppColors.surfaceHighlight
              : AppColors.videoBackdrop,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: <Widget>[
              Icon(
                open
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 20,
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
                    fontWeight:
                        containsNow ? FontWeight.w700 : FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: AppColors.surfaceOutline, width: 0.8),
                ),
                child: Text(
                  '${group.count}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, QueueRow row) {
    final bool now = row.now || row.index == widget.snapshot.queue.index;
    // Channels carry the PC's bookmark: saved = solid accent, always
    // visible; unsaved = dim outline (the phone has no hover to fade it
    // in on, so it stays put). File rows have neither.
    final bool channels = widget.snapshot.queue.isChannels;
    final bool fav = channels && _favs.contains(row.title);
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
            if (channels)
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip:
                    fav ? 'Remove from favourites' : 'Save as favourite',
                onPressed: () => _toggleFav(row.title),
                icon: Icon(
                  fav ? Icons.bookmark : Icons.bookmark_border,
                  color: fav ? AppColors.accent : AppColors.statusUnknown,
                ),
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
