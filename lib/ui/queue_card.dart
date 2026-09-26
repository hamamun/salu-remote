import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/client.dart';
import '../core/error_copy.dart';
import '../core/models.dart';
import '../core/prefs.dart';
import '../core/queue_reader.dart';
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
/// `remote.md` §17.4), progressively fetched in pages of at most 100, with
/// the current channel's page first; the auto-scroll position comes from
/// the snapshot's `queue.index`, so the phone never computes playback order
/// itself.
///
/// The header mirrors the PC panel's header (Salu
/// `lib/ui/panels/playlist_panel.dart`): the search bar sits beside Queue
/// with its count and its clear button inside it, and the favourites
/// bookmark sits beside the clear button (channels only).
///
/// Channel grouping (`pc_part.md` Part F):
/// - `queue.grouping` from snapshot: available modes + current mode.
/// - Chips row above the list: Flat / Category / Country / Language.
/// - Capability-gated, byte-bounded `queue_groups_page` with explicit members.
///   Legacy PCs show a safe flat view; `queue_group_set` still changes the PC.
/// - Grouped modes are the PC's accordion: by default every head stays
///   collapsed and only the played channel's group is expanded (autohide)
///   — a head tap toggles, it never plays, and the group holding the
///   playing channel opens on its own at every mode choice and track
///   change. While the PC's heads load, the list waits (skeleton) instead
///   of flashing the full flat list the PC never shows.
/// - A search flattens the list whatever the mode is (PC §10.3) — the
///   grouping is suspended, not forgotten.
/// - Favourites are chosen on this phone (titles only — the phone never
///   holds URLs or m3u metadata). Favourites-only shows bookmarked channels
///   as a flat list, without group heads or collapsed-group hiding.
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
  late final QueueReader _reader = QueueReader(
      (verb, args) => _client.send(verb, args: args));
  bool _settingGrouping = false;
  bool _followCurrent = true;
  bool get _pagedGroups => _client.supports(RemoteFeature.queueGroupsPaged);
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

  /// A successful row tap may arrive before its state snapshot. This temporary
  /// index keeps that tap responsive; any newer snapshot index clears it.
  int? _optimisticQueueIndex;
  int _jumpGeneration = 0;

  int get _currentQueueIndex =>
      _optimisticQueueIndex ?? widget.snapshot.queue.index;

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
    _client.link.addListener(_onLink);
    unawaited(_fetch(autoscroll: true));
  }

  @override
  void dispose() {
    _client.link.removeListener(_onLink);
    _fetchGeneration++;
    _groupsGeneration++;
    _scroll.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  void _onLink() {
    if (!mounted) return;
    if (!_client.isOnline) {
      _fetchGeneration++;
      _groupsGeneration++;
      setState(() {
        _loading = false;
        _groupsLoading = false;
        _error = 'Not connected to your PC.';
      });
      return;
    }
    // Let the reconnect's hello snapshot reach this widget first.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _client.isOnline) unawaited(_fetch(autoscroll: true));
    });
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
    final bool indexChanged = queue.index != old.index;
    if (indexChanged) {
      // The newer snapshot supersedes any temporary queue-jump highlight.
      _optimisticQueueIndex = null;
      _followCurrent = true;
    }

    if (queue.count != old.count || queue.kind != old.kind ||
        queue.revision != old.revision) {
      // Invalidate row jumps from the previous playlist as well as its marker.
      _jumpGeneration++;
      _groupsGeneration++;
      // The playlist itself changed (tracks added, queue cleared, a new
      // channel load): refetch. A channel load starts blank (the PC's
      // `_onLoadGeneration`) — no search, no favourites filter, accordion
      // closed — and the old heads belong to the old list either way.
      setState(() {
        _optimisticQueueIndex = null;
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
        _groupsGeneration++;
        _followCurrent = true;
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
      // pure local work — the snapshot index drives the single playing-row
      // marker (never the queue_get `now` hint, which may now be stale),
      // open the destination group, then bring the new row into view.
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

  /// Render each page as it arrives; prioritize the now-playing page.
  Future<void> _fetch({bool autoscroll = false}) async {
    final int generation = ++_fetchGeneration;
    final SaluQueueInfo queue = widget.snapshot.queue;
    bool current() => mounted && generation == _fetchGeneration;
    _groupsGeneration++;
    _followCurrent = autoscroll;
    setState(() {
      _groups = const <QueueGroup>[];
      _groupsError = null;
      _groupsLoading = false;
      _rows = const <QueueRow>[];
      _loading = queue.count > 0;
      _error = null;
    });
    unawaited(_fetchGroupsIfNeeded());
    if (queue.count == 0) return;
    try {
      await _reader.rows(count: queue.count, currentIndex: queue.index,
          revision: queue.revision, current: current, onPage: (rows) {
        if (!current()) return;
        setState(() => _rows = rows);
        // Earlier pages shift the current row down. Keep it in view until the
        // user deliberately scrolls or opens a different group.
        if (_followCurrent) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (current() && _followCurrent) _scrollToCurrent();
          });
        }
      });
    } on QueueReadCancelled {
      return;
    } on QueueReadFailure catch (error) {
      if (!current()) return;
      setState(() => _error = _readError(error.reply));
      if (error.reply.code == 'stale_queue') unawaited(_client.stateGet());
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  String _readError(RemoteReply reply) => RemoteErrorCopy.text(
      reply.code == 'too_fast' ? 'busy' : reply.code, reply.message);

  Future<void> _fetchGroupsIfNeeded() async {
    if (!widget.snapshot.queue.isChannels ||
        _currentMode == QueueGroupingMode.flat ||
        widget.snapshot.queue.count == 0) {
      return;
    }
    await _fetchGroups();
  }

  Future<void> _fetchGroups() async {
    final int generation = ++_groupsGeneration;
    final SaluQueueInfo queue = widget.snapshot.queue;
    final QueueGroupingMode mode = _currentMode;
    if (!queue.isChannels || queue.count == 0 || mode == QueueGroupingMode.flat) {
      return;
    }
    bool current() => mounted && generation == _groupsGeneration;
    // Old descriptors describe only start+count, not actual membership.
    // Don't send the unbounded legacy request or invent incorrect groups.
    if (!_pagedGroups || queue.revision == null) {
      setState(() {
        _groupsLoading = false;
        _groupsError = 'Grouped view unavailable on this PC version.';
      });
      return;
    }
    setState(() {
      _groupsLoading = true;
      _groupsError = null;
    });
    bool revealedPlaying = false;
    try {
      await _reader.groups(by: _modeWire(mode), revision: queue.revision!,
          queueCount: queue.count, current: current, onPage: (groups) {
        if (!current()) return;
        final String? playing = groupKeyForIndex(groups, widget.snapshot.queue.index);
        setState(() {
          _groups = groups;
          if (!revealedPlaying && playing != null && _followCurrent) {
            _openGroupKey = playing;
            revealedPlaying = true;
          }
        });
        if (playing != null && _openGroupKey == playing && _followCurrent) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (current() && _followCurrent) _scrollToCurrent();
          });
        }
      });
    } on QueueReadCancelled {
      return;
    } on QueueReadFailure catch (error) {
      if (!current()) return;
      setState(() => _groupsError = _readError(error.reply));
      if (error.reply.code == 'stale_queue') unawaited(_client.stateGet());
    } finally {
      if (current()) setState(() => _groupsLoading = false);
    }
  }

  Future<void> _setGrouping(QueueGroupingMode mode) async {
    if (_settingGrouping || mode == _currentMode) return;
    if (mode != QueueGroupingMode.flat && !_availableModes.contains(mode)) return;
    // One change at a time; the authoritative snapshot drives the selection.
    // An unrelated snapshot can no longer roll back an optimistic choice.
    setState(() => _settingGrouping = true);
    try {
      final RemoteReply reply = await _client.queueGroupSet(_modeWire(mode));
      if (!mounted) return;
      if (reply.ok) {
        _groupingSupported = true;
        await _client.stateGet();
      } else if (reply.code == 'unknown_command') {
        setState(() => _groupingSupported = false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_readError(reply))),
        );
      }
    } finally {
      if (mounted) setState(() => _settingGrouping = false);
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
    _followCurrent = false;
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

  Object? _displayKey;
  List<QueueDisplayItem> _displayCache = const <QueueDisplayItem>[];

  List<QueueDisplayItem> _buildDisplayItems() {
    if (_rows.isEmpty && _groups.isEmpty) return const <QueueDisplayItem>[];

    // The accordion applies only in a grouped mode on a channel list whose
    // PC answered `queue_groups_page`. Unknown members stay hidden while
    // descriptors are still arriving; search/favourites use loaded rows.
    final bool grouped = _currentMode != QueueGroupingMode.flat &&
        _groupingSupported != false &&
        widget.snapshot.queue.isChannels &&
        _groups.isNotEmpty;
    final Object key = (_rows, _groups, grouped, _openGroupKey, _query,
        _favOnly, _favs, _groupsLoading, widget.snapshot.queue.isChannels);
    if (key == _displayKey) return _displayCache;
    _displayKey = key;
    return _displayCache = buildQueueDisplay(
      rows: _rows,
      groups: _groups,
      grouped: grouped,
      openGroupKey: _openGroupKey,
      query: _query,
      favouritesOnly: _favOnly && widget.snapshot.queue.isChannels,
      favourites: _favs,
      hideUnassigned: _groupsLoading,
    );
  }

  int _findCurrentDisplayIndex(List<QueueDisplayItem> display) =>
      findQueueCurrentDisplayIndex(display, _currentQueueIndex);

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
    final int indexWhenSent = widget.snapshot.queue.index;
    final int generation = ++_jumpGeneration;
    final RemoteReply reply =
        await runRemote(context, () => _client.queueJump(row.index));
    if (!reply.ok || !mounted || generation != _jumpGeneration) return;

    // Keep the tapped row responsive while its snapshot is on the way, but do
    // not let a late reply overwrite a newer playback position.
    final int snapshotIndex = widget.snapshot.queue.index;
    if (snapshotIndex != indexWhenSent && snapshotIndex != row.index) return;

    final String? dest = groupKeyForIndex(_groups, row.index);
    setState(() {
      _optimisticQueueIndex = row.index;
      if (dest != null &&
          _currentMode != QueueGroupingMode.flat &&
          widget.snapshot.queue.isChannels) {
        _openGroupKey = dest;
      }
    });
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
      _jumpGeneration++; // A pending row jump belongs to the cleared playlist.
      setState(() {
        _optimisticQueueIndex = null;
        _rows = const <QueueRow>[];
        _groups = const <QueueGroup>[];
        _loading = false;
        _groupsLoading = false;
        _error = null;
        _groupsError = null;
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
      return 'No favourites yet';
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
    // never has). Search and favourites both flatten immediately: neither
    // needs group heads.
    final bool awaitingHeads = _currentMode != QueueGroupingMode.flat &&
        queue.isChannels &&
        _pagedGroups &&
        _groupingSupported != false &&
        _groups.isEmpty &&
        _query.isEmpty &&
        !_favOnly;

    // The total belongs only inside the search bar; the header stays compact.
    // The favourites bookmark sits beside the clear button (channels only).
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
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _searchField(shown, total: queue.count)),
              if (queue.isChannels)
                IconButton(
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  tooltip: _favOnly
                      ? 'Show all channels'
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
                    queue.hasRows ? () => unawaited(_clear()) : null,
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
                  if ((_loading && display.isEmpty) || (_groupsLoading && awaitingHeads))
                    const _SkeletonRows()
                  else if (awaitingHeads)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No groups loaded',
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
                          NotificationListener<ScrollStartNotification>(
                            onNotification: (notification) {
                              if (notification.dragDetails != null) _followCurrent = false;
                              return false;
                            },
                            child: ListView.separated(
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
                          ),
                          if (_groupsLoading || _loading)
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
                  if (_error != null || _groupsError != null)
                    Row(children: <Widget>[
                      Expanded(child: Text(_error ?? _groupsError!,
                          style: Theme.of(context).textTheme.bodySmall)),
                      if (!_loading && !_groupsLoading &&
                          (_error != null || _pagedGroups))
                        TextButton(onPressed: () {
                          if (_error != null) {
                            unawaited(_fetch());
                          } else {
                            unawaited(_fetchGroups());
                          }
                        }, child: const Text('Retry')),
                    ]),

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
  Widget _searchField(int shown, {required int total}) {
    // `_favOnly` is channels-only (the header bookmark hides on file
    // queues), so it counts as filtering only there. Use the snapshot total
    // so the count remains correct while queue rows are loading.
    final bool filtering =
        _query.isNotEmpty || (_favOnly && widget.snapshot.queue.isChannels);
    final bool noMatch = filtering && shown == 0 && !_loading;
    final String countLabel;
    if (!filtering) {
      countLabel = '$total';
    } else if (_loading) {
      countLabel = '… / $total';
    } else {
      countLabel = '$shown / $total';
    }
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
              cursorColor: AppColors.accent,
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
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
            countLabel,
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
    final bool enabled = isAvailable && !_settingGrouping;

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
    final int currentIndex = _currentQueueIndex;
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
    final bool now = isCurrentQueueRow(row, _currentQueueIndex);
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
