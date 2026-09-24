import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/client.dart';
import '../core/models.dart';
import '../core/reply.dart';
import 'theme.dart';
import 'web_sheets.dart';
import 'widgets.dart';

/// The Play tab in Web mode (`remote_apk_ui.md` §4.2): the same tab,
/// transformed — because the mode *is* the same remote pointed at a
/// different thing.
///
/// Two shapes, per the user's rule: **when the page is playing media, the
/// basics** (play/pause, seek, −10 s / +10 s, volume, mute, fullscreen),
/// because that is all most online players expose. When the page has no
/// reachable media, the nav body.
///
/// Both shapes carry the **page doors** — new tab, the open-tab list, the saved
/// pages — because those are navigation, not playback, and the couch user needs
/// them whichever shape is up. Each door degrades instead of dying on a PC that
/// has not been updated (`web_sheets.dart`).
///
/// The media controls drive the *page's own player* (JavaScript on the PC side,
/// `remote.md` §17.11) — never mpv, never the Windows volume.
class WebBody extends StatefulWidget {
  const WebBody({super.key, required this.snapshot, required this.activeTab});

  final SaluSnapshot snapshot;

  /// The root's active-tab notifier. The ~1/s `web_media_get` poll runs only
  /// while this tab is on screen (`remote_apk_ui.md` §8).
  final ValueListenable<int> activeTab;

  static const int tabIndex = 0;

  @override
  State<WebBody> createState() => _WebBodyState();
}

class _WebBodyState extends State<WebBody> {
  final SaluClient _client = SaluClient.instance;
  Timer? _poll;
  WebMediaInfo? _media;

  /// One read at a time. The poll is on a 1 s clock but a reply may take up to
  /// 6 s (the PC injects JavaScript with a 2 s budget of its own), and stacked
  /// reads are how a slider starts answering a quarter-second late: they queue
  /// behind each other on the PC's command isolate and can trip its 30/s guard.
  bool _polling = false;

  /// A failed write (`no_web_media`) means the player is behind a
  /// cross-origin iframe or DRM — drop back to the nav shape and say so in
  /// one plain line, instead of leaving dead buttons.
  bool _unreachable = false;

  // ── the optimistic hold ────────────────────────────────────────────────────
  //
  // The page's position is read once a second, and a page player takes a beat
  // to obey a seek. A reply that lands right after the finger lifts therefore
  // still carries the *old* position — without a hold the thumb snaps back and
  // then jumps forward, which is exactly the "seek bar fights me" feeling. So a
  // write parks its value here until the PC's own reading agrees with it, or
  // [_holdFor] passes and the PC's word wins anyway. Optimistic, then honest.

  static const Duration _holdFor = Duration(milliseconds: 1500);
  static const Duration _agreeWithin = Duration(seconds: 2);

  Duration? _heldPosition;
  DateTime? _positionHoldUntil;
  int? _heldVolume;
  DateTime? _volumeHoldUntil;

  /// A seek bar being dragged scrubs the picture, so it streams slower than the
  /// Play tab's own bar: 4 sends a second is smooth enough to watch, is a third
  /// of the ≤20/s budget §8 allows, and spares the PC a JavaScript injection
  /// storm. Volume is cheaper over there and wants to feel instant, so it keeps
  /// the default ~8/s.
  static const Duration _seekGap = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    _client.link.addListener(_onLink);
    widget.activeTab.addListener(_onActive);
    _onActive();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_pollOnce()));
  }

  @override
  void didUpdateWidget(covariant WebBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The page changed under us — the URL box, a tab switch, or the PC user
    // clicking something. A player that was out of reach on the *last* page
    // says nothing about this one, so the new page gets a fair trial.
    if (widget.snapshot.web.url != oldWidget.snapshot.web.url && _unreachable) {
      _unreachable = false;
      _media = null;
      unawaited(_pollOnce());
    }
  }

  @override
  void dispose() {
    _client.link.removeListener(_onLink);
    widget.activeTab.removeListener(_onActive);
    _poll?.cancel();
    super.dispose();
  }

  void _onLink() {
    // The link dropped: a stale "playing" dot would be a lie.
    if (!_client.isOnline && _media != null) {
      setState(() => _media = null);
    }
    _onActive();
  }

  void _onActive() {
    final bool should =
        widget.activeTab.value == WebBody.tabIndex && _client.isOnline;
    if (should) {
      _poll ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_pollOnce()),
      );
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _pollOnce() async {
    if (_polling) return;
    _polling = true;
    try {
      final WebMediaInfo? info = await _client.webMediaRead();
      if (!mounted || info == null) return;
      // A missed beat is not news: keep the last good reading on screen.
      final bool settled = _settleHolds(info);
      if (settled || info != _media) setState(() => _media = info);
    } finally {
      _polling = false;
    }
  }

  /// Let go of a parked value as soon as the PC agrees with it — or after
  /// [_holdFor], whichever comes first. Returns true when something was
  /// dropped, so the caller knows a repaint is owed even if the reading itself
  /// did not change.
  bool _settleHolds(WebMediaInfo info) {
    final DateTime now = DateTime.now();
    bool settled = false;

    final Duration? heldPosition = _heldPosition;
    if (heldPosition != null) {
      final bool agreed = (info.position - heldPosition).abs() <= _agreeWithin;
      final DateTime? until = _positionHoldUntil;
      final bool expired = until == null || !now.isBefore(until);
      if (agreed || expired) {
        _heldPosition = null;
        _positionHoldUntil = null;
        settled = true;
      }
    }

    final int? heldVolume = _heldVolume;
    if (heldVolume != null) {
      // Two percent either way: a page player rounds its own volume.
      final bool agreed = (info.volume - heldVolume).abs() <= 2;
      final DateTime? until = _volumeHoldUntil;
      final bool expired = until == null || !now.isBefore(until);
      if (agreed || expired) {
        _heldVolume = null;
        _volumeHoldUntil = null;
        settled = true;
      }
    }

    return settled;
  }

  void _holdPosition(Duration value) {
    _heldPosition = value;
    _positionHoldUntil = DateTime.now().add(_holdFor);
    if (mounted) setState(() {});
  }

  void _holdVolume(int percent) {
    _heldVolume = percent;
    _volumeHoldUntil = DateTime.now().add(_holdFor);
    if (mounted) setState(() {});
  }

  // ── the page player's controls ────────────────────────────────────────────

  Future<void> _guarded(Future<RemoteReply> Function() action) async {
    final RemoteReply reply = await runRemote(context, action);
    if (!reply.ok && reply.code == 'no_web_media') {
      setState(() {
        _unreachable = true;
        _media = null;
      });
    }
  }

  /// The slider's thumb, in milliseconds — the client turns it into whatever
  /// unit the PC's own read used (`SaluClient.webMediaSeek`).
  void _seekTo(double valueMs) {
    final Duration to = Duration(milliseconds: valueMs.round());
    _holdPosition(to);
    unawaited(_guarded(() => _client.webMediaSeek(to: to)));
  }

  /// −10 s / +10 s. The same door as the slider rather than `web_media_seek`'s
  /// `delta` form, so the buttons are exactly as trustworthy as the bar next to
  /// them — and the nudge is optimistic, so pressing twice in a beat adds up.
  void _nudge(int seconds) {
    final WebMediaInfo? media = _media;
    if (media == null || !media.seekable) return;
    final Duration from = _heldPosition ?? media.position;
    Duration to = from + Duration(seconds: seconds);
    if (to < Duration.zero) to = Duration.zero;
    if (media.duration > Duration.zero && to > media.duration) to = media.duration;
    _holdPosition(to);
    unawaited(_guarded(() => _client.webMediaSeek(to: to)));
  }

  void _setVolume(double value) {
    final int percent = value.round().clamp(0, 100).toInt();
    _holdVolume(percent);
    unawaited(_guarded(() => _client.webMediaVolume(percent)));
  }

  // ── the page doors ────────────────────────────────────────────────────────

  Future<void> _openTabs() async {
    final bool wantNew = await WebTabsSheet.show(context);
    if (!mounted) return;
    if (wantNew) {
      await _urlDialog(newTab: true);
      return;
    }
    // The strip may have moved under us — a tab closed, another activated.
    unawaited(_pollOnce());
  }

  Future<void> _openPages() => SavedPagesSheet.show(
        context,
        currentUrl: widget.snapshot.web.url,
        currentTitle: widget.snapshot.web.title,
      );

  Future<void> _openDiagnostics() => WebDiagnosticsSheet.show(
        context,
        snapshot: widget.snapshot,
        media: _media,
      );

  @override
  Widget build(BuildContext context) {
    final SaluWeb web = widget.snapshot.web;
    final WebMediaInfo? media = _media;
    final bool showMedia =
        _client.isOnline && media?.found == true && !_unreachable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _navRow(web, pageFullscreen: showMedia),
        const SizedBox(height: 2),
        _doorsRow(),
        const SizedBox(height: 12),
        if (showMedia)
          _mediaShape(web, media!)
        else ...<Widget>[
          _navShape(web),
          if (_unreachable) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.lock_outline,
                    size: 16, color: AppColors.statusDead),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "This site's player can't be controlled from outside.",
                    style: const TextStyle(
                        color: AppColors.statusDead, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  // ── nav row ──────────────────────────────────────────────────────────────

  /// One quiet row of page navigation. In the media shape the fullscreen
  /// mark drives the page's player; in the nav shape it drives the SALU
  /// window. The tab count at the end is a door, not a label.
  Widget _navRow(SaluWeb web, {required bool pageFullscreen}) {
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: 'Back',
          onPressed: web.canBack
              ? () => unawaited(runRemote(context, () => _client.browserNav('back')))
              : null,
          icon: Icon(Icons.arrow_back,
              color: web.canBack ? AppColors.iconIdle : AppColors.statusUnknown),
        ),
        IconButton(
          tooltip: 'Forward',
          onPressed: web.canForward
              ? () =>
                  unawaited(runRemote(context, () => _client.browserNav('forward')))
              : null,
          icon: Icon(Icons.arrow_forward,
              color:
                  web.canForward ? AppColors.iconIdle : AppColors.statusUnknown),
        ),
        IconButton(
          tooltip: web.loading ? 'Stop' : 'Reload',
          onPressed: () => unawaited(
            runRemote(
              context,
              () => _client.browserNav(web.loading ? 'stop' : 'reload'),
            ),
          ),
          icon: Icon(
            web.loading ? Icons.stop : Icons.refresh,
            color: AppColors.iconIdle,
          ),
        ),
        IconButton(
          tooltip: pageFullscreen ? 'Page fullscreen' : 'Fullscreen',
          onPressed: pageFullscreen
              ? (_media?.canFullscreen ?? false)
                  ? () => unawaited(_guarded(_client.webMediaFullscreen))
                  : null
              : () => unawaited(runRemote(context, _client.fullscreenToggle)),
          icon: Icon(
            pageFullscreen
                ? (web.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen)
                : (widget.snapshot.window.fullscreen
                    ? Icons.fullscreen_exit
                    : Icons.fullscreen),
            color: AppColors.iconIdle,
          ),
        ),
        const Spacer(),
        if (web.loading)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        _tabsDoor(web),
      ],
    );
  }

  /// The tab count, and the way in to the strip behind it. It reads as a count
  /// because that is what the snapshot always carries, and it opens the list
  /// (switch · close · new) on a PC that advertises `web_tabs` — or the URL box
  /// on one that does not, which is the single tab door every PC can honour.
  Widget _tabsDoor(SaluWeb web) {
    return Tooltip(
      message: 'Open tabs',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => unawaited(_openTabs()),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 7, 10, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.web_asset, size: 16, color: AppColors.iconIdle),
              const SizedBox(width: 6),
              Text(
                '${web.tabs} ${web.tabs == 1 ? 'tab' : 'tabs'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The two doors the nav row has no room for. Both work against a PC that has
  /// not been updated: "New tab" is the URL box (which becomes a real new tab
  /// the moment the PC offers `web_tab_new`), and "Saved pages" is SALU's own
  /// URL library until the PC mirrors its bookmarks.
  Widget _doorsRow() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        SaluChip(
          icon: Icons.add,
          label: 'New tab',
          onTap: () => unawaited(_urlDialog(newTab: true)),
        ),
        SaluChip(
          icon: Icons.bookmark_border,
          label: 'Saved pages',
          onTap: () => unawaited(_openPages()),
        ),
      ],
    );
  }

  // ── the page card ────────────────────────────────────────────────────────

  /// The live page: title over URL. Tap = the URL box (§4.2's sleeper
  /// feature); long-press = the diagnostics sheet, which is where a question
  /// about what the PC actually sent gets answered by looking.
  Widget _pageCard(SaluWeb web) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => unawaited(_urlDialog()),
      onLongPress: () => unawaited(_openDiagnostics()),
      child: SaluCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              web.title ?? 'Loading…',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (web.url != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  web.url!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── shape 1: the page has a player ───────────────────────────────────────

  Widget _mediaShape(SaluWeb web, WebMediaInfo media) {
    final Duration position = _heldPosition ?? media.position;
    final int volume = _heldVolume ?? media.volume;
    final bool seekable = media.seekable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _pageCard(web),
        SaluCard(
          margin: const EdgeInsets.only(top: 14),
          child: seekable
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Live, like the Play tab's own bar: the page moves while
                    // the thumb does, and the final value lands on release.
                    LiveSlider(
                      value: position.inMilliseconds.toDouble(),
                      max: media.duration.inMilliseconds.toDouble(),
                      gap: _seekGap,
                      onLive: _seekTo,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(SaluTheme.clock(position),
                            style: Theme.of(context).textTheme.bodySmall),
                        Text(SaluTheme.clock(media.duration),
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ],
                )
              : Text(
                  // A live stream, or a page that has not reported its length:
                  // no bar, and one line saying why — the same rule the Play
                  // tab follows on `playback.seekable`.
                  'Live / not seekable — this page does not report a length.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
        ),
        _transportRow(media, seekable: seekable),
        // The page player's own volume — it never touches the Windows volume.
        SaluCard(
          padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: media.muted ? 'Unmute' : 'Mute',
                onPressed: () => unawaited(
                    _guarded(() => _client.webMediaMute(!media.muted))),
                icon: Icon(
                  media.muted ? Icons.volume_off : Icons.volume_up,
                  color: media.muted
                      ? AppColors.statusDead
                      : AppColors.iconIdle,
                ),
              ),
              Expanded(
                child: LiveSlider(
                  value: volume.toDouble(),
                  max: 100,
                  onLive: _setVolume,
                ),
              ),
              SizedBox(
                width: 38,
                child: Text(
                  '$volume',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// −10 s · the big play/pause · +10 s. §4.2 promised one button, and it is
  /// still the middle and the biggest thing here — the two nudges sit either
  /// side of it because a seek bar alone is a slow way to skip an advert.
  Widget _transportRow(WebMediaInfo media, {required bool seekable}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          IconButton(
            tooltip: 'Back 10 seconds',
            iconSize: 34,
            onPressed: seekable ? () => _nudge(-10) : null,
            icon: const Icon(Icons.replay_10),
          ),
          const SizedBox(width: 20),
          IconButton.filled(
            iconSize: 52,
            tooltip: media.playing ? 'Pause' : 'Play',
            onPressed: () => unawaited(_guarded(_client.webMediaToggle)),
            icon: Icon(media.playing ? Icons.pause : Icons.play_arrow, size: 46),
          ),
          const SizedBox(width: 20),
          IconButton(
            tooltip: 'Forward 10 seconds',
            iconSize: 34,
            onPressed: seekable ? () => _nudge(10) : null,
            icon: const Icon(Icons.forward_10),
          ),
        ],
      ),
    );
  }

  // ── shape 2: no media on the page ────────────────────────────────────────

  Widget _navShape(SaluWeb web) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _pageCard(web),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.link),
          label: const Text('Open a URL on the PC'),
          onPressed: () => unawaited(_urlDialog()),
        ),
      ],
    );
  }

  // ── the URL box ──────────────────────────────────────────────────────────

  /// "Open a URL on the PC" — the sleeper feature (`remote_apk_ui.md` §4.2):
  /// type or paste on the phone, the PC browser goes there. The field is
  /// pre-filled with the clipboard when it holds a URL (the one-keyboard
  /// rule, §12).
  ///
  /// [newTab] is the door's label, not a different door: on a PC that
  /// advertises `web_tabs` it becomes a real `web_tab_new`, and everywhere else
  /// it stays `open_url`, which the PC already routes into its browser in Web
  /// mode (§17.4).
  Future<void> _urlDialog({bool newTab = false}) async {
    final String current = widget.snapshot.web.url ?? '';
    String initial = '';
    try {
      final ClipboardData? clipboard =
          await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboard?.text case final String? clip when looksLikeUrl(clip ?? '')) {
        initial = clip!;
      }
    } catch (_) {}
    if (!mounted) return;
    final String? action = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _OpenUrlDialog(
        initialUrl: initial,
        currentUrl: current,
        newTab: newTab && _client.supportsWebTabs,
      ),
    );
    if (!mounted) return;
    if (action == 'reload') {
      unawaited(runRemote(context, () => _client.browserNav('reload')));
    } else if (action != null && action.isNotEmpty) {
      final String url = action;
      unawaited(
        runRemote(
          context,
          () => newTab && _client.supportsWebTabs
              ? _client.webTabNew(url: url)
              : _client.openUrl(url),
        ),
      );
    }
  }
}

class _OpenUrlDialog extends StatefulWidget {
  const _OpenUrlDialog({
    required this.initialUrl,
    required this.currentUrl,
    this.newTab = false,
  });

  final String initialUrl;
  final String currentUrl;
  final bool newTab;

  @override
  State<_OpenUrlDialog> createState() => _OpenUrlDialogState();
}

class _OpenUrlDialogState extends State<_OpenUrlDialog> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.newTab ? 'New tab on the PC' : 'Open a URL on the PC'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (widget.currentUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Current: ${widget.currentUrl}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            TextField(
              controller: _textController,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Address or link',
                hintText: 'https://…',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop('reload'),
          child: const Text('Reload'),
        ),
        FilledButton(
          onPressed: () {
            final String url = _textController.text.trim();
            if (url.isEmpty) return;
            Navigator.of(context).pop(url);
          },
          child: Text(widget.newTab ? 'Open tab' : 'Open'),
        ),
      ],
    );
  }
}
