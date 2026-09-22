import 'dart:async';

import 'package:flutter/material.dart';

import '../core/client.dart';
import '../core/error_copy.dart';
import '../core/models.dart';
import '../core/reply.dart';
import 'theme.dart';
import 'widgets.dart';

/// One crumb in the breadcrumb trail.
class _Crumb {
  const _Crumb(this.label, this.path);

  final String label;
  final String path;
}

/// A directory listing kept in RAM so going back is instant
/// (`remote_apk_ui.md` §8: "paged, 200 rows, cached by path in RAM").
class _DirCache {
  _DirCache(this.entries, this.total, this.truncated);

  final List<FsEntry> entries;
  final int total;
  final bool truncated;
}

/// Browse → Files (`remote_apk_ui.md` §5.1): the PC's drives, read-only.
///
/// Hard rules, in order of importance:
///   * **Read-only. Forever.** No delete, rename, move — the UI cannot
///     express destruction, so it cannot perform it.
///   * **The file never travels.** `fs_open` sends paths; the PC opens them
///     locally. A 40 GB movie plays in one byte of network traffic.
///   * **Media-only filter on by default**, system folders hidden.
///   * **Paged: 200 rows, then "load more".**
///
/// The same screen doubles as the **subtitle picker** (`subtitleMode`):
/// one browser, two jobs — listing `.srt/.ass/.sub/.vtt` and returning a
/// loaded subtitle instead of playing it (`remote_apk_ui.md` §6.2).
class FilesBrowser extends StatefulWidget {
  const FilesBrowser({
    super.key,
    required this.snapshot,
    this.subtitleMode = false,
  });

  final SaluSnapshot snapshot;

  /// Subtitle-picker mode: subtitle filter, no quick marks, a row tap loads
  /// the subtitle on the PC and pops `true`.
  final bool subtitleMode;

  @override
  State<FilesBrowser> createState() => _FilesBrowserState();
}

class _FilesBrowserState extends State<FilesBrowser> {
  static const int _pageSize = 200;

  final SaluClient _client = SaluClient.instance;

  // Where we are: the breadcrumb stack (empty = the pinned-places landing).
  List<_Crumb> _crumbs = const <_Crumb>[];
  final Map<String, _DirCache> _cache = <String, _DirCache>{};

  // The current listing.
  List<FsEntry> _entries = const <FsEntry>[];
  int _from = 0;
  int _total = 0;
  bool _truncated = false;
  bool _loading = false;
  String? _error;

  // The landing view.
  List<FsPlace> _places = const <FsPlace>[];
  bool _placesLoading = false;
  String? _placesError;

  // The filter row (collapsed behind the tune icon — set once, never touched).
  bool _showAll = false;
  bool _showSystem = false;
  bool _filtersOpen = false;

  // Select mode (long-press anywhere → checkboxes, select-all, bottom bar).
  bool _selecting = false;
  Set<String> _selected = <String>{};

  String get _filter => widget.subtitleMode ? 'subs' : _showAll ? 'all' : 'media';
  String get _path => _crumbs.isEmpty ? '' : _crumbs.last.path;
  bool get _inPlaces => _crumbs.isEmpty;

  String _key(String path) => '$path|$_filter|$_showSystem';

  @override
  void initState() {
    super.initState();
    unawaited(_loadPlaces());
  }

  @override
  void didUpdateWidget(FilesBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The PC's switch flipped while we were here — follow it live (§17.9.14).
    final bool wasOn = oldWidget.snapshot.filesEnabled;
    final bool nowOn = widget.snapshot.filesEnabled;
    if (wasOn && !nowOn) {
      setState(() {
        _crumbs = const <_Crumb>[];
        _error = null;
        _loading = false;
      });
    } else if (!wasOn && nowOn) {
      unawaited(_inPlaces ? _loadPlaces() : _loadFirstPage());
    }
  }

  // ── loading ──────────────────────────────────────────────────────────────

  Future<void> _loadPlaces() async {
    setState(() {
      _placesLoading = true;
      _placesError = null;
    });
    final RemoteReply reply = await _client.fsPlaces();
    if (!mounted) return;
    if (reply.ok) {
      setState(() {
        _places = _parsePlaces(reply);
        _placesLoading = false;
      });
    } else {
      setState(() {
        _placesLoading = false;
        _placesError = RemoteErrorCopy.text(reply.code, reply.message);
      });
    }
  }

  List<FsPlace> _parsePlaces(RemoteReply reply) {
    final Object? raw = reply['places'] ?? reply['entries'];
    if (raw is! List) return const <FsPlace>[];
    return raw
        .whereType<Map>()
        .map((Map m) => FsPlace.from(m.cast<String, Object?>()))
        // Network drives never render — even if a PC build sends one.
        .where((FsPlace p) => !p.isNetwork)
        .toList();
  }

  Future<void> _loadFirstPage() async {
    final String key = _key(_path);
    final _DirCache? cached = _cache[key];
    if (cached != null) {
      setState(() {
        _entries = cached.entries;
        _total = cached.total;
        _truncated = cached.truncated;
        _from = cached.entries.length;
        _error = null;
        _loading = false;
      });
      return;
    }
    await _fetchPage(0, append: false);
  }

  Future<void> _fetchPage(int from, {required bool append}) async {
    final String path = _path;
    setState(() {
      _loading = true;
      _error = null;
    });
    final RemoteReply reply = await _client.fsList(
      path,
      from: from,
      count: _pageSize,
      filter: _filter,
      showSystem: _showSystem,
    );
    if (!mounted) return;
    // The user moved on while this was in flight: a stale answer must not
    // paint the new folder.
    if (path != _path) return;
    if (reply.ok && reply['entries'] is List) {
      final FsPage page = FsPage.from(reply.data);
      final String key = _key(path);
      final _DirCache? old = _cache[key];
      _cache[key] = _DirCache(
        append && old != null ? <FsEntry>[...old.entries, ...page.entries] : page.entries,
        page.total,
        page.truncated,
      );
      setState(() {
        _entries = _cache[key]!.entries;
        _total = page.total;
        _truncated = page.truncated;
        _from = from + page.entries.length;
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = RemoteErrorCopy.text(reply.code, reply.message);
      });
    }
  }

  // ── navigation ───────────────────────────────────────────────────────────

  void _enterFolder(FsEntry entry) {
    setState(() {
      _crumbs = <_Crumb>[..._crumbs, _Crumb(entry.name, entry.path)];
      _entries = const <FsEntry>[];
      _from = 0;
      _total = 0;
      _truncated = false;
      _error = null;
    });
    unawaited(_loadFirstPage());
  }

  void _gotoCrumb(int index) {
    if (index >= _crumbs.length) return;
    setState(() {
      _crumbs = _crumbs.sublist(0, index + 1);
      _entries = const <FsEntry>[];
      _from = 0;
      _total = 0;
      _truncated = false;
      _error = null;
    });
    unawaited(_loadFirstPage());
  }

  void _goPlaces() {
    setState(() {
      _crumbs = const <_Crumb>[];
      _entries = const <FsEntry>[];
      _from = 0;
      _total = 0;
      _error = null;
      _exitSelect();
    });
    unawaited(_loadPlaces());
  }

  void _toggleFilter(bool showAll, bool showSystem) {
    setState(() {
      _showAll = showAll;
      _showSystem = showSystem;
    });
    unawaited(_inPlaces ? _loadPlaces() : _loadFirstPage());
  }

  // ── select mode ──────────────────────────────────────────────────────────

  List<FsEntry> get _selectable => _entries
      .where((FsEntry e) =>
          widget.subtitleMode ? !e.directory : e.directory || e.isMedia)
      .toList();

  void _enterSelect(FsEntry? first) {
    setState(() {
      _selecting = true;
      _selected = <String>{};
      if (first != null && _isSelectable(first)) _selected.add(first.path);
    });
  }

  void _exitSelect() {
    if (!_selecting && _selected.isEmpty) return;
    setState(() {
      _selecting = false;
      _selected = <String>{};
    });
  }

  void _toggleSelected(FsEntry entry) {
    setState(() {
      if (!_selected.remove(entry.path)) _selected.add(entry.path);
    });
  }

  bool _isSelectable(FsEntry entry) =>
      widget.subtitleMode ? !entry.directory : entry.directory || entry.isMedia;

  Future<void> _playSelected() async {
    final List<String> paths = _selected.toList();
    _exitSelect();
    await runRemote(context, () => _client.fsOpen(paths, mode: 'play'));
  }

  Future<void> _queueSelected() async {
    final List<String> paths = _selected.toList();
    _exitSelect();
    await runRemote(context, () => _client.fsOpen(paths, mode: 'queue'));
  }

  // ── row actions ──────────────────────────────────────────────────────────

  Future<void> _rowTap(FsEntry entry) async {
    if (entry.directory) {
      _enterFolder(entry);
      return;
    }
    if (widget.subtitleMode) {
      // One browser, two jobs: in picker mode a tap loads the subtitle on
      // the PC and reports back (`remote_apk_ui.md` §6.2).
      final RemoteReply reply =
          await runRemote(context, () => _client.fsLoadSubtitle(entry.path));
      if (reply.ok && mounted) Navigator.of(context).pop(true);
      return;
    }
    await runRemote(context, () => _client.fsOpen(<String>[entry.path], mode: 'play'));
  }

  Future<void> _rowQuick(FsEntry entry, String mode) async {
    await runRemote(context, () => _client.fsOpen(<String>[entry.path], mode: mode));
  }

  // ── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!widget.snapshot.filesEnabled) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const EmptyState(
            message: 'File browsing is turned off on the PC.',
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Turn it on in SALU → Settings → General → Remote → "Let phones '
              'browse PC files". The Files tab comes back as soon as it does.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _topBar(),
        if (_filtersOpen && !widget.subtitleMode) _filterRow(),
        if (_selecting && !widget.subtitleMode) _selectionHeader(),
        Expanded(child: _inPlaces ? _placesView() : _listView()),
        if (_selecting && !widget.subtitleMode) _selectionBar(),
      ],
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: widget.subtitleMode ? 'Close' : 'Up',
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.subtitleMode
                ? () => Navigator.of(context).pop()
                : (_inPlaces
                    ? null
                    : () {
                        if (_crumbs.length <= 1) {
                          _goPlaces();
                        } else {
                          _gotoCrumb(_crumbs.length - 2);
                        }
                      }),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _inPlaces
                ? Text(
                    widget.subtitleMode ? 'Choose a subtitle file' : 'Files',
                    style: Theme.of(context).textTheme.titleMedium,
                  )
                : _breadcrumb(),
          ),
          if (!widget.subtitleMode)
            IconButton(
              tooltip: 'Filters',
              icon: Icon(
                Icons.tune,
                color: _filtersOpen ? AppColors.accent : AppColors.iconIdle,
              ),
              onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
            ),
        ],
      ),
    );
  }

  Widget _breadcrumb() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < _crumbs.length; i++) ...<Widget>[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.chevron_right, size: 14, color: AppColors.statusUnknown),
              ),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _gotoCrumb(i),
              child: Text(
                _crumbs[i].label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: i == _crumbs.length - 1 ? FontWeight.w600 : FontWeight.w400,
                  color: i == _crumbs.length - 1
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: <Widget>[
          const Text('Media only', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Switch(
            value: !_showAll,
            onChanged: (bool v) => _toggleFilter(!v, _showSystem),
          ),
          const SizedBox(width: 16),
          const Text('Hidden folders', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Switch(
            value: _showSystem,
            onChanged: (bool v) => _toggleFilter(_showAll, v),
          ),
        ],
      ),
    );
  }

  // ── the pinned-places landing ────────────────────────────────────────────

  Widget _placesView() {
    if (_placesLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_placesError != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          EmptyState(
            message: _placesError!,
            actionLabel: 'Try again',
            onAction: () => unawaited(_loadPlaces()),
          ),
        ],
      );
    }
    final List<FsPlace> quick = _places
        .where((FsPlace p) => !p.isDrive)
        .toList();
    final List<FsPlace> drives = _places.where((FsPlace p) => p.isDrive).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        if (quick.isNotEmpty) ...<Widget>[
          Text('Quick places', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final FsPlace place in quick)
                SaluChip(
                  icon: _placeIcon(place.kind),
                  label: place.name,
                  onTap: () {
                    setState(() {
                      _crumbs = <_Crumb>[_Crumb(place.name, place.path)];
                      _entries = const <FsEntry>[];
                      _error = null;
                    });
                    unawaited(_loadFirstPage());
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (drives.isNotEmpty) ...<Widget>[
          Text('Drives', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final FsPlace place in drives)
                SaluChip(
                  icon: _driveIcon(place),
                  label: place.name,
                  onTap: () {
                    setState(() {
                      _crumbs = <_Crumb>[_Crumb(place.name, place.path)];
                      _entries = const <FsEntry>[];
                      _error = null;
                    });
                    unawaited(_loadFirstPage());
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (quick.isEmpty && drives.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'The PC reported no drives or places.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  /// Drive chips get an icon per medium once the PC reports it
  /// (`medium: fixed · removable · optical · ram`); older PC builds send
  /// nothing and keep the old sd-storage glyph.
  IconData _driveIcon(FsPlace place) {
    switch (place.medium) {
      case 'fixed':
        return Icons.storage;
      case 'removable':
        return Icons.usb;
      case 'optical':
        return Icons.album;
      case 'ram':
        return Icons.memory;
      default:
        return Icons.sd_storage;
    }
  }

  IconData _placeIcon(String kind) {
    switch (kind) {
      case 'now_playing':
        return Icons.play_circle_outline;
      case 'downloads':
        return Icons.download;
      case 'videos':
        return Icons.movie_outlined;
      case 'music':
        return Icons.music_note;
      case 'desktop':
        return Icons.desktop_windows;
      case 'drive':
        return Icons.sd_storage;
      default:
        return Icons.folder_outlined;
    }
  }

  // ── the listing ──────────────────────────────────────────────────────────

  Widget _listView() {
    if (_loading && _entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null && _entries.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          EmptyState(
            message: _error!,
            actionLabel: 'Try again',
            onAction: () => unawaited(_loadFirstPage()),
          ),
        ],
      );
    }
    return Column(
      children: <Widget>[
        if (_entries.isEmpty && !_loading)
          Expanded(
            child: Center(
              child: Text(
                widget.subtitleMode ? 'No subtitle files in this folder' : 'This folder is empty',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadFirstPage(),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                itemCount: _entries.length + (_hasMore ? 1 : 0),
                itemBuilder: (BuildContext context, int i) {
                  if (i == _entries.length) return _loadMoreRow();
                  return _row(_entries[i]);
                },
              ),
            ),
          ),
        if (_truncated)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Showing the first 2000 entries of this folder.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  bool get _hasMore => _from < _total;

  Widget _loadMoreRow() {
    final int remaining = (_total - _from).clamp(0, 999999);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: () => unawaited(_fetchPage(_from, append: true)),
                child: Text('⋯ $remaining more'),
              ),
      ),
    );
  }

  Widget _row(FsEntry entry) {
    final bool selectable = _isSelectable(entry);
    final bool selected = _selected.contains(entry.path);
    final bool isDir = entry.directory;
    final IconData icon;
    final Color iconColor;
    if (widget.subtitleMode) {
      icon = isDir ? Icons.folder : Icons.subtitles;
      iconColor = isDir ? AppColors.iconIdle : AppColors.accent;
    } else if (isDir) {
      icon = Icons.folder_outlined;
      iconColor = AppColors.iconIdle;
    } else if (entry.isMedia) {
      icon = entry.isPlaylist
          ? Icons.queue_music
          : (entry.ext == null ||
                  const <String>{
                    'mkv', 'mp4', 'avi', 'mov', 'wmv', 'webm', 'm4v', 'ts', 'mpg', 'mpeg',
                    'flv', '3gp',
                  }.contains(entry.ext!.toLowerCase())
              ? Icons.movie_outlined
              : Icons.music_note);
      iconColor = AppColors.iconIdle;
    } else {
      icon = Icons.insert_drive_file;
      iconColor = AppColors.statusUnknown;
    }

    return InkWell(
      onTap: _selecting ? (selectable ? () => _toggleSelected(entry) : null) : (selectable ? () => unawaited(_rowTap(entry)) : null),
      // Select mode is a browse-mode tool; the subtitle picker is one-tap.
      onLongPress:
          selectable && !widget.subtitleMode ? () => _selecting ? _toggleSelected(entry) : _enterSelect(entry) : null,
      child: Container(
        height: 48,
        color: selected ? AppColors.surfaceHighlight : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: <Widget>[
            if (_selecting)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  selected ? Icons.check_box : Icons.check_box_outline_blank,
                  color: selected ? AppColors.accent : AppColors.statusUnknown,
                  size: 20,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(icon, size: 20, color: iconColor),
              ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selectable ? AppColors.textPrimary : AppColors.statusUnknown,
                    ),
                  ),
                  if (!isDir && entry.readableSize.isNotEmpty)
                    Text(
                      entry.readableSize,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            // Quick marks: ▶ play now · ＋ add to queue. One item never
            // needs a long-press (`remote_apk_ui.md` §5.1, user answer #2).
            if (!_selecting && !widget.subtitleMode && selectable) ...<Widget>[
              _quickMark(
                icon: Icons.play_arrow,
                tooltip: 'Play now',
                onTap: () => unawaited(_rowQuick(entry, 'play')),
              ),
              _quickMark(
                icon: Icons.add,
                tooltip: 'Add to queue',
                onTap: () => unawaited(_rowQuick(entry, 'queue')),
              ),
            ],
            if (isDir && !_selecting)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.chevron_right, size: 18, color: AppColors.statusUnknown),
              ),
          ],
        ),
      ),
    );
  }

  Widget _quickMark({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: IconButton(
        tooltip: tooltip,
        iconSize: 20,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: AppColors.iconIdle),
      ),
    );
  }

  // ── select-mode chrome ───────────────────────────────────────────────────

  Widget _selectionHeader() {
    final int count = _selected.length;
    final int selectable = _selectable.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      color: AppColors.videoBackdrop,
      child: Row(
        children: <Widget>[
          Icon(Icons.check_box, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(
            '$count selected',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          TextButton(
            onPressed: count == selectable && count > 0
                ? () => setState(() => _selected = <String>{})
                : () => setState(() {
                    _selected = _selectable.map((FsEntry e) => e.path).toSet();
                  }),
            child: Text(count == selectable && count > 0 ? 'Deselect' : 'Select all'),
          ),
          IconButton(
            tooltip: 'Done',
            icon: const Icon(Icons.close, size: 20),
            onPressed: _exitSelect,
          ),
        ],
      ),
    );
  }

  Widget _selectionBar() {
    final int count = _selected.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      color: AppColors.videoBackdrop,
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: Text('Play $count'),
              onPressed: count == 0 ? null : () => unawaited(_playSelected()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: Text('Queue $count'),
              onPressed: count == 0 ? null : () => unawaited(_queueSelected()),
            ),
          ),
        ],
      ),
    );
  }
}
