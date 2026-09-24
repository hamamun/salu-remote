import 'dart:async';

import 'package:flutter/material.dart';

import '../core/client.dart';
import '../core/error_copy.dart';
import '../core/models.dart';
import '../core/reply.dart';
import 'theme.dart';
import 'widgets.dart';

/// The two sheets of the Web body: the **saved pages** the browser keeps, and —
/// behind a long-press on the page card — **what the page player actually
/// said**.
///
/// The **open tabs** used to be a third sheet here. Since 2026-09-24 they are a
/// section of the body itself (`web_tabs_card.dart`, the user's own request):
/// switching tabs means looking at another page, and a sheet covers the page
/// you are switching *to*.
///
/// Both remaining sheets degrade instead of dying. A PC that has not been
/// updated (no `web_bookmarks` in `hello.features`) still gets a useful sheet —
/// the parts that need new plumbing say so in one plain line instead of sitting
/// there dead (`remote_apk_ui.md` §4.2, §7).
///
/// Nothing here rides the snapshot. A list of 200 bookmarks is bigger than the
/// whole 8 KB frame budget, so it is one request, fetched when the sheet opens
/// (`remote.md` §17.7, §17.13.3).

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

// ── the saved pages ─────────────────────────────────────────────────────────

/// The pages worth keeping — **the PC browser's own bookmarks, and nothing
/// else** (user, 2026-09-24).
///
/// This sheet used to list two piles: the browser's bookmarks *and* SALU's own
/// saved URL list — the very same m3u list that Browse → Streams shows for the
/// player. The user's verdict was blunt and right: *"those m3u should not show
/// as we are in web section here m3u which is player part should not appear in
/// that list."* The player's list belongs to the player; a sheet reached from
/// the browser's own row is about the browser.
///
/// Tapping a row opens it in the PC browser (`open_url` in Web mode) and closes
/// the sheet.
///
/// **Save this page** stays, and where it writes depends on the PC. With
/// `web_bookmark_add` (§17.14) it appends to the browser's own bookmarks, so the
/// page is in this list a second later. Without it the page still gets saved —
/// into SALU's list — and the snackbar says where it went, because a save the
/// user cannot find again is worse than no save at all.
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

  List<WebBookmarkInfo>? _bookmarks;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  /// The PC promised `web_bookmark_add` and then refused it. The sheet stops
  /// offering it and says where the save actually goes instead.
  bool _addRefused = false;

  /// The page on screen, when there is one worth saving.
  String? get _page => widget.currentUrl?.trim().isEmpty == true
      ? null
      : widget.currentUrl?.trim();

  bool get _reported => _client.supportsWebBookmarks;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!_reported) return;
    if (mounted) {
      setState(() {
        _loading = _bookmarks == null;
        _error = null;
      });
    }
    final RemoteReply reply = await _client.webBookmarksGet();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (reply.ok) {
        _bookmarks = webBookmarksFrom(reply.data);
      } else {
        _error = RemoteErrorCopy.text(reply.code, reply.message);
      }
    });
  }

  /// Save the page being looked at. **Add-only, always**: the browser's own
  /// bookmarks when the PC can take a line (`web_bookmark_add`), SALU's list
  /// otherwise — and the snackbar names which, every time.
  ///
  /// The fallback is the point. `unknown_command` is a *silent* code (the user
  /// never sees it), so a promised-but-missing `web_bookmark_add` would swallow
  /// the save and leave the user believing the page was kept. One press, one
  /// saved page: if the bookmark store says no, the page goes to SALU's list and
  /// the snackbar tells the user where to find it.
  Future<void> _saveThisPage() async {
    final String? url = _page;
    if (url == null || _saving) return;
    setState(() => _saving = true);
    bool toBookmarks = _client.supportsWebBookmarkAdd && !_addRefused;
    RemoteReply reply = await runRemote(
      context,
      () => toBookmarks
          ? _client.webBookmarkAdd(url, name: widget.currentTitle)
          : _client.libraryAdd(url, name: widget.currentTitle, save: true),
    );
    if (!mounted) return;
    if (!reply.ok &&
        toBookmarks &&
        (reply.code == 'unknown_command' || reply.code == 'invalid_arguments')) {
      toBookmarks = false;
      setState(() => _addRefused = true);
      reply = await runRemote(
        context,
        () => _client.libraryAdd(url, name: widget.currentTitle, save: true),
      );
      if (!mounted) return;
    }
    setState(() => _saving = false);
    if (!reply.ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          toBookmarks
              ? "Bookmarked in the PC's browser."
              : "Saved to SALU's list — find it in Browse → Streams.",
        ),
      ),
    );
    if (toBookmarks) await _refresh();
  }

  Future<void> _open(String url) async {
    await runRemote(context, () => _client.openUrl(url));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final List<WebBookmarkInfo> bookmarks =
        _bookmarks ?? const <WebBookmarkInfo>[];
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
                  label:
                      Text(page == null ? 'Nothing to save yet' : 'Save this page'),
                  onPressed: page == null || _saving ? null : _saveThisPage,
                ),
              ),
            ),
            if (page != null)
              _sheetNote(
                context,
                _client.supportsWebBookmarkAdd && !_addRefused
                    ? 'Adds ${widget.currentTitle ?? page} to the PC browser\'s bookmarks.'
                    : 'Adds ${widget.currentTitle ?? page} to SALU\'s saved list.',
              ),
            Flexible(child: _body(bookmarks)),
            _sheetNote(context, 'Tap a page to open it in the PC browser.'),
          ],
        ),
      ),
    );
  }

  Widget _body(List<WebBookmarkInfo> bookmarks) {
    if (!_reported) {
      // Not a dead sheet: the Save button above still works, and the browser's
      // own pile needs an updated SALU — which is all this says.
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text(
          'This PC does not report its browser bookmarks yet. Saving still works '
          '— the page goes to SALU\'s list.',
        ),
      );
    }
    if (_error != null && _bookmarks == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            ),
            TextButton(
              onPressed: () => unawaited(_refresh()),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (_bookmarks == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: <Widget>[
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (bookmarks.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
              child: Text(
                'No bookmarked pages on the PC.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            for (final WebBookmarkInfo mark in bookmarks)
              _pageRow(
                title: mark.name,
                subtitle:
                    mark.folder.isEmpty ? mark.url : '${mark.folder} · ${mark.url}',
                onTap: () => unawaited(_open(mark.url)),
              ),
        ],
      ),
    );
  }

  Widget _pageRow({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: <Widget>[
            const Icon(Icons.bookmark_border, size: 18, color: AppColors.iconIdle),
            const SizedBox(width: 12),
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
                  // The fullscreen seat's whole story in one row (§17.14): the
                  // two halves it chooses between, and which one is on.
                  FactRow(
                    label: 'Fullscreen',
                    value: 'page ${_yesNo(web.fullscreen)} '
                        '· element ${_yesNo(media?.fullscreen ?? false)} '
                        '· window ${_yesNo(snapshot.window.fullscreen)} '
                        '· web_fullscreen promised '
                        '${_yesNo(client.supportsWebFullscreen)}',
                  ),
                  const Divider(height: 22, color: AppColors.divider),
                  FactRow(
                    label: 'Page player',
                    value: info == null
                        ? 'no answer yet'
                        : 'found ${_yesNo(info.found)} · playing ${_yesNo(info.playing)} '
                            '· seekable ${_yesNo(info.seekable)} '
                            '· can go full ${_yesNo(info.canFullscreen)}',
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
