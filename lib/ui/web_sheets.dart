import 'dart:async';

import 'package:flutter/material.dart';

import '../core/client.dart';
import '../core/error_copy.dart';
import '../core/models.dart';
import '../core/reply.dart';
import 'theme.dart';
import 'widgets.dart';

/// The three doors the Web body's nav row has no room for: the PC's **open
/// tabs**, the **pages it has saved**, and — behind a long-press on the page
/// card — **what the page player actually said**.
///
/// Every one of them degrades instead of dying. A PC that has not been updated
/// yet (no `web_tabs` / `web_bookmarks` in `hello.features`) still gets a
/// useful sheet, because opening a page and SALU's URL library are v1.1 verbs
/// that every PC has: the parts that need new plumbing say so in one plain
/// line instead of sitting there dead (`remote_apk_ui.md` §4.2, §7).
///
/// Nothing here rides the snapshot. A strip of 40 tabs is bigger than the whole
/// 8 KB frame budget, so each list is one request, fetched when the sheet opens
/// (`remote.md` §17.7).

// ── shared sheet furniture ──────────────────────────────────────────────────

const RoundedRectangleBorder _sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
);

/// The little bar at the top of every sheet — the "you can pull me down" mark.
Widget _sheetHandle() {
  return Center(
    child: Container(
      width: 38,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.divider,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

Widget _sheetTitle(BuildContext context, String title, {String? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
    child: Row(
      children: <Widget>[
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        if (trailing != null)
          Text(trailing, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

Widget _sheetNote(BuildContext context, String text) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

// ── the open tabs ───────────────────────────────────────────────────────────

/// The PC's tab strip: switch, close, open new.
///
/// Closing asks nothing — a browser is the mental model here, and the PC keeps
/// its own session history. Switching closes the sheet, because the whole point
/// was to look at the other tab.
class WebTabsSheet extends StatefulWidget {
  const WebTabsSheet._();

  /// Resolves `true` when the user asked for a **new tab**. The caller keeps
  /// the URL box (and the clipboard rule that goes with it, §12).
  static Future<bool> show(BuildContext context) async {
    final bool? wantNew = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: _sheetShape,
      builder: (BuildContext sheetContext) => const WebTabsSheet._(),
    );
    return wantNew ?? false;
  }

  @override
  State<WebTabsSheet> createState() => _WebTabsSheetState();
}

class _WebTabsSheetState extends State<WebTabsSheet> {
  final SaluClient _client = SaluClient.instance;
  WebTabPage? _page;
  bool _loading = false;
  String? _error;

  bool get _supported => _client.supportsWebTabs;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!_supported) return;
    if (mounted) {
      setState(() {
        _loading = _page == null;
        _error = null;
      });
    }
    final RemoteReply reply = await _client.webTabsGet();
    if (!mounted) return;
    if (reply.ok) {
      setState(() {
        _page = WebTabPage.from(reply.data);
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = RemoteErrorCopy.text(reply.code, reply.message);
      });
    }
  }

  Future<void> _activate(WebTabInfo tab) async {
    await runRemote(context, () => _client.webTabActivate(tab.index));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _close(WebTabInfo tab) async {
    final RemoteReply reply =
        await runRemote(context, () => _client.webTabClose(tab.index));
    if (!mounted) return;
    if (reply.ok) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final WebTabPage? page = _page;
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _sheetHandle(),
            _sheetTitle(
              context,
              'Open tabs',
              trailing: _supported && page != null
                  ? '${page.count} ${page.count == 1 ? 'tab' : 'tabs'}'
                  : null,
            ),
            Flexible(child: _body(page)),
            const Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('New tab'),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(WebTabPage? page) {
    if (!_supported) {
      // Not a dead door: the button below still opens a page on this PC, which
      // is the only tab command an un-updated SALU can honour.
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        children: const <Widget>[
          EmptyState(
            message: 'This PC does not report its tabs yet.',
          ),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Listing, switching and closing tabs needs an updated SALU on the '
              'PC. Opening a page already works — use New tab below.',
            ),
          ),
        ],
      );
    }
    final String? error = _error;
    if (error != null && page == null) {
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        children: <Widget>[
          EmptyState(
            message: error,
            actionLabel: 'Try again',
            onAction: () => unawaited(_refresh()),
          ),
        ],
      );
    }
    if (page == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (page.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Text(
          'No tabs open on the PC right now.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        itemCount: page.tabs.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.divider),
        itemBuilder: (BuildContext context, int i) =>
            _tabRow(page.tabs[i], page.isActive(page.tabs[i])),
      ),
    );
  }

  Widget _tabRow(WebTabInfo tab, bool active) {
    return InkWell(
      onTap: active ? null : () => unawaited(_activate(tab)),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6, right: 2),
        child: Row(
          children: <Widget>[
            Icon(
              active ? Icons.play_arrow : Icons.web_asset,
              size: 18,
              color: active ? AppColors.accent : AppColors.statusUnknown,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (tab.url.isNotEmpty)
                    Text(
                      tab.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (tab.loading)
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            IconButton(
              tooltip: 'Close tab',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              onPressed: () => unawaited(_close(tab)),
              icon: const Icon(Icons.close, color: AppColors.iconIdle),
            ),
          ],
        ),
      ),
    );
  }
}

// ── the saved pages ─────────────────────────────────────────────────────────

/// The pages worth keeping, in two piles:
///
///   * **the PC browser's own bookmarks** — read-only, and only when the PC
///     advertises `web_bookmarks` (`remote.md` §17.13);
///   * **SALU's URL library** — the same list Browse → Streams shows, which
///     every PC already has. This is the pile that works today, and "Save this
///     page" writes into it, so a page found on the couch is one tap away from
///     being permanent.
///
/// Tapping any row opens it in the PC's browser (`open_url` in Web mode) and
/// closes the sheet.
class SavedPagesSheet extends StatefulWidget {
  const SavedPagesSheet._({this.currentUrl, this.currentTitle});

  final String? currentUrl;
  final String? currentTitle;

  static Future<void> show(
    BuildContext context, {
    String? currentUrl,
    String? currentTitle,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.surface,
        isScrollControlled: true,
        shape: _sheetShape,
        builder: (BuildContext sheetContext) => SavedPagesSheet._(
          currentUrl: currentUrl,
          currentTitle: currentTitle,
        ),
      );

  @override
  State<SavedPagesSheet> createState() => _SavedPagesSheetState();
}

class _SavedPagesSheetState extends State<SavedPagesSheet> {
  final SaluClient _client = SaluClient.instance;
  LibraryInfo? _library;
  List<WebBookmarkInfo>? _bookmarks;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  String? get _page => widget.currentUrl?.trim().isEmpty == true
      ? null
      : widget.currentUrl?.trim();

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = _library == null;
        _error = null;
      });
    }
    // Both reads at once: the library is always there to fetch, the browser's
    // own bookmarks only when the PC promised them.
    final Future<RemoteReply> library = _client.libraryGet();
    final Future<RemoteReply>? bookmarks =
        _client.supportsWebBookmarks ? _client.webBookmarksGet() : null;

    final RemoteReply libraryReply = await library;
    if (!mounted) return;
    if (libraryReply.ok) {
      setState(() {
        _library = LibraryInfo.from(libraryReply.data);
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = RemoteErrorCopy.text(libraryReply.code, libraryReply.message);
      });
    }

    if (bookmarks == null) return;
    final RemoteReply bookmarkReply = await bookmarks;
    if (!mounted || !bookmarkReply.ok) return;
    setState(() => _bookmarks = webBookmarksFrom(bookmarkReply.data));
  }

  Future<void> _saveThisPage() async {
    final String? url = _page;
    if (url == null || _saving) return;
    setState(() => _saving = true);
    // `library_add` with a URL that is already there is the PC's own update
    // door, so saving twice renames rather than duplicates.
    final RemoteReply reply = await runRemote(
      context,
      () => _client.libraryAdd(url, name: widget.currentTitle, save: true),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!reply.ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Saved to the PC's list.")),
    );
    await _refresh();
  }

  Future<void> _open(String url) async {
    await runRemote(context, () => _client.openUrl(url));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _remove(LibraryEntryInfo entry) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Remove this page?'),
        content: Text(
          '${entry.name} will go from the PC\'s saved list.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await runRemote(context, () => _client.libraryRemove(entry.url));
    if (!mounted) return;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final List<WebBookmarkInfo> bookmarks = _bookmarks ?? const <WebBookmarkInfo>[];
    final List<LibraryEntryInfo> entries = _library?.entries ?? const <LibraryEntryInfo>[];
    final String? page = _page;
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _sheetHandle(),
            _sheetTitle(context, 'Saved pages'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bookmark),
                  label: Text(page == null ? 'Nothing to save yet' : 'Save this page'),
                  onPressed: page == null || _saving ? null : _saveThisPage,
                ),
              ),
            ),
            if (page != null)
              _sheetNote(context, 'Saves ${widget.currentTitle ?? page} on the PC.'),
            Flexible(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  children: <Widget>[
                    if (_client.supportsWebBookmarks) ...<Widget>[
                      _sectionHead('Bookmarked in the PC browser'),
                      ..._bookmarkRows(bookmarks),
                    ],
                    _sectionHead("SALU's saved list"),
                    ..._libraryRows(entries),
                  ],
                ),
              ),
            ),
            _sheetNote(
              context,
              'Tap a page to open it in the PC browser · long-press a saved row to remove it.',
            ),
          ],
        ),
      ),
    );
  }

  /// The PC browser's own bookmarks — a pile that only exists when the PC
  /// advertised `web_bookmarks`, and an honest line when it is empty.
  List<Widget> _bookmarkRows(List<WebBookmarkInfo> bookmarks) {
    if (bookmarks.isEmpty) {
      return <Widget>[_emptyLine('No bookmarked pages on the PC.')];
    }
    return <Widget>[
      for (final WebBookmarkInfo mark in bookmarks)
        _pageRow(
          icon: Icons.bookmark_border,
          title: mark.name,
          subtitle:
              mark.folder.isEmpty ? mark.url : '${mark.folder} · ${mark.url}',
          onTap: () => unawaited(_open(mark.url)),
        ),
    ];
  }

  /// SALU's URL library — the same list Browse → Streams shows, so a page
  /// saved from the couch is already waiting there in the morning.
  List<Widget> _libraryRows(List<LibraryEntryInfo> entries) {
    if (_error != null && _library == null) {
      return <Widget>[_emptyLine(_error!)];
    }
    if (_loading && _library == null) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (entries.isEmpty) {
      return <Widget>[
        _emptyLine("Nothing saved yet — Browse → Streams is the same list."),
      ];
    }
    return <Widget>[
      for (final LibraryEntryInfo entry in entries)
        _pageRow(
          icon: Icons.link,
          title: entry.name,
          subtitle: entry.url,
          leading: HealthDot(health: entry.health),
          onTap: () => unawaited(_open(entry.url)),
          onLongPress: () => unawaited(_remove(entry)),
        ),
    ];
  }

  Widget _sectionHead(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 0.8,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _emptyLine(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }

  Widget _pageRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? leading,
    VoidCallback? onLongPress,
  }) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading,
              const SizedBox(width: 12),
            ] else ...<Widget>[
              Icon(icon, size: 18, color: AppColors.iconIdle),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.open_in_new, size: 16, color: AppColors.statusUnknown),
          ],
        ),
      ),
    );
  }
}

// ── what the page player actually said ──────────────────────────────────────

/// The Web body's diagnostics, behind a long-press on the page card.
///
/// One screen answers the only question that matters when a web control
/// misbehaves: **what did the PC send?** The seek bar and the volume bar are
/// the two controls that carry a number with a unit, and the unit is the one
/// thing the phone cannot see from the armchair — so here it is, in the PC's
/// own words, next to what the phone made of it (`remote.md` §17.11).
class WebDiagnosticsSheet extends StatelessWidget {
  const WebDiagnosticsSheet._({required this.snapshot, this.media});

  final SaluSnapshot snapshot;
  final WebMediaInfo? media;

  static Future<void> show(
    BuildContext context, {
    required SaluSnapshot snapshot,
    WebMediaInfo? media,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.surface,
        isScrollControlled: true,
        shape: _sheetShape,
        builder: (BuildContext sheetContext) =>
            WebDiagnosticsSheet._(snapshot: snapshot, media: media),
      );

  @override
  Widget build(BuildContext context) {
    final SaluClient client = SaluClient.instance;
    final SaluWeb web = snapshot.web;
    final WebMediaInfo? info = media;
    final ServerInfo? server = client.server.value;
    final List<String> promised =
        RemoteFeature.all.where(client.supports).toList(growable: false);

    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          children: <Widget>[
            _sheetHandle(),
            _sheetTitle(context, 'Web diagnostics'),
            _sheetNote(
              context,
              'What the PC reported about this page — long-press the page card '
              'any time to come back here.',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FactRow(
                    label: 'PC',
                    value: '${server?.name ?? 'unknown'} · v${server?.version ?? '?'} '
                        '· proto ${server?.proto ?? '?'}',
                  ),
                  FactRow(
                    label: 'Latency',
                    value: client.latencyMs.value == null
                        ? '—'
                        : '${client.latencyMs.value} ms',
                  ),
                  FactRow(label: 'Mode', value: snapshot.isWeb ? 'web' : 'player'),
                  FactRow(label: 'Page', value: web.title ?? '—'),
                  FactRow(label: 'URL', value: web.url ?? '—'),
                  FactRow(
                    label: 'Nav',
                    value: 'tabs ${web.tabs} · back ${_yesNo(web.canBack)} '
                        '· forward ${_yesNo(web.canForward)} '
                        '· loading ${_yesNo(web.loading)} '
                        '· page fullscreen ${_yesNo(web.fullscreen)}',
                  ),
                  FactRow(
                    label: 'Snapshot',
                    value: 'web.hasMedia ${_yesNo(web.hasMedia)} '
                        '· window fullscreen ${_yesNo(snapshot.window.fullscreen)}',
                  ),
                  const Divider(height: 22, color: AppColors.divider),
                  FactRow(
                    label: 'Page player',
                    value: info == null
                        ? 'no answer yet'
                        : 'found ${_yesNo(info.found)} · playing ${_yesNo(info.playing)} '
                            '· seekable ${_yesNo(info.seekable)} '
                            '· fullscreen ${_yesNo(info.canFullscreen)}',
                  ),
                  if (info != null) ...<Widget>[
                    FactRow(
                      label: 'Clock',
                      value: '${SaluTheme.clock(info.position)} / '
                          '${SaluTheme.clock(info.duration)}',
                    ),
                    FactRow(
                      label: 'Volume',
                      value: '${info.volume}% · muted ${_yesNo(info.muted)}',
                    ),
                    FactRow(
                      label: 'Units read',
                      value: '${info.dialect} · PC promises web_media_unit: '
                          '${_yesNo(client.supportsWebMediaUnit)}',
                    ),
                  ] else
                    FactRow(
                      label: 'Units read',
                      value: '${client.webDialect} (last known) · PC promises '
                          'web_media_unit: ${_yesNo(client.supportsWebMediaUnit)}',
                    ),
                  FactRow(
                    label: 'Promised',
                    value: promised.isEmpty
                        ? 'none of the web extras'
                        : promised.join(', '),
                  ),
                  if (info != null && info.raw.isNotEmpty) ...<Widget>[
                    const Divider(height: 22, color: AppColors.divider),
                    Text(
                      'The reply itself (web_media_get)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    for (final MapEntry<String, Object?> entry in info.raw.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          '${entry.key} = ${entry.value}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _yesNo(bool value) => value ? 'yes' : 'no';
}
