import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/client.dart';
import '../core/models.dart';
import '../core/reply.dart';
import '../core/web_url.dart';
import 'theme.dart';
import 'web_sheets.dart';
import 'web_tabs_card.dart';
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
/// Both shapes carry the **page doors** — new tab, the saved pages — because
/// those are navigation, not playback, and the couch user needs them whichever
/// shape is up. Each door degrades instead of dying on a PC that has not been
/// updated (`web_sheets.dart`).
///
/// The media controls drive the *page's own player* (JavaScript on the PC side,
/// `remote.md` §17.11) — never mpv, never the Windows volume.
///
/// **The user's five fixes, 2026-09-24** (`remote.md` §17.14):
///
/// 1. **One fullscreen button.** `web_fullscreen` lets the PC pick — the page's
///    own player when the page has one, the SALU window when it has not — and
///    the icon follows what actually happened. The old split (media found →
///    `web_media_fullscreen`, else → `fullscreen_toggle`) is kept only as the
///    fallback for a PC that has not been updated; it is what made YouTube do
///    nothing while every other stream fullscreened the whole application.
/// 2. **Home** sits at the left of the nav row: the loaded page goes to its own
///    site's front page, same tab (`browser_nav {action:"home"}`). An older PC
///    gets the origin of the current URL through `browser_open` instead.
/// 3. **The open tabs are a section, not a button.** They live in
///    [WebTabsCard] at the foot of the body — heading, count, chevron,
///    remembered open/closed, exactly like the queue card. The `▢ 3 tabs` door
///    that used to sit in the nav row is gone.
/// 4. **A typed address gets a scheme** before it goes out (`web_url.dart`), so
///    "youtube.com" stops arriving at the PC as a blank new tab.
/// 5. **☆ Saved pages is bookmarks only** (`web_sheets.dart`) — SALU's own m3u
///    list belongs to the player half of the app, not here.
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
  int _pollGeneration = 0;

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

  // ── the fullscreen seat ───────────────────────────────────────────────────
  //
  // One button, and the PC decides what goes fullscreen (§17.14). The flip is
  // optimistic like the sliders: the mark turns the moment the thumb lands, and
  // the PC's own state takes it back as soon as the snapshot agrees — or after
  // [_holdFor] if it never does.

  bool? _fullscreenHold;
  DateTime? _fullscreenHoldUntil;

  /// The PC answered `unknown_command` for `browser_nav {action:"home"}`: it
  /// advertised nothing, it refuses the verb, so the phone stops asking and
  /// uses the URL fallback from then on.
  bool _homeRefused = false;

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
    final SaluWeb web = widget.snapshot.web;
    final SaluWeb oldWeb = oldWidget.snapshot.web;

    if (web.url != oldWeb.url || web.tabs != oldWeb.tabs || !web.hasTabs) {
      _pollGeneration++;
    }
    if (!web.hasTabs) {
      // No tabs are open on the PC: clear the media controls, holds, and any
      // unreachable flag immediately so no previous tab's status stays visible.
      if (_media != null ||
          _unreachable ||
          _heldPosition != null ||
          _heldVolume != null) {
        setState(() {
          _media = null;
          _unreachable = false;
          _heldPosition = null;
          _positionHoldUntil = null;
          _heldVolume = null;
          _volumeHoldUntil = null;
        });
      }
    } else if (web.url != oldWeb.url || web.tabs != oldWeb.tabs) {
      // The page changed under us — a URL change, a tab switch, or tab close.
      // Clear holds and previous media immediately; the new page gets a fresh poll.
      setState(() {
        _unreachable = false;
        _media = null;
        _heldPosition = null;
        _positionHoldUntil = null;
        _heldVolume = null;
        _volumeHoldUntil = null;
      });
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
    if (!_client.isOnline) _pollGeneration++;
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
    if (_polling || !mounted || !_client.isOnline ||
        widget.activeTab.value != WebBody.tabIndex ||
        !widget.snapshot.web.hasTabs) return;
    final int generation = _pollGeneration;
    _polling = true;
    try {
      final WebMediaInfo? info = await _client.webMediaRead();
      if (!mounted || generation != _pollGeneration || info == null ||
          !_client.isOnline || widget.activeTab.value != WebBody.tabIndex) return;
      if (!info.found) {
        // The PC confirmed there is no media right now: clear holds and
        // reset media controls so nothing stale stays on screen.
        final bool hadMedia = _media?.found == true;
        _heldPosition = null;
        _positionHoldUntil = null;
        _heldVolume = null;
        _volumeHoldUntil = null;
        _unreachable = false;
        if (hadMedia || _media != null) {
          setState(() => _media = null);
        }
        return;
      }
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

    // The fullscreen hold lets go the moment the PC agrees with it — either
    // half of the PC, because `web_fullscreen` may have chosen *either* the
    // page's player or the SALU window — and always after [_holdFor].
    final bool? heldFullscreen = _fullscreenHold;
    if (heldFullscreen != null) {
      final bool agreed = heldFullscreen == info.fullscreen ||
          heldFullscreen == widget.snapshot.window.fullscreen;
      final DateTime? until = _fullscreenHoldUntil;
      final bool expired = until == null || !now.isBefore(until);
      if (agreed || expired) {
        _fullscreenHold = null;
        _fullscreenHoldUntil = null;
        settled = true;
      }
    }

    return settled;
  }

  /// Fullscreen is on if **either** half of the PC says so: the page's own
  /// player (`web_media_get`), or the SALU window (the snapshot) — which is
  /// exactly the pair `web_fullscreen` chooses between.
  bool get _fullscreenOn =>
      _fullscreenHold ?? (_pageFullscreen || widget.snapshot.window.fullscreen);

  bool get _pageFullscreen =>
      (_media?.fullscreen ?? false) || widget.snapshot.web.fullscreen;

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

  // ── fullscreen, home: the two seats the PC now answers ────────────────────

  /// **One button** (§17.14). The PC decides what goes fullscreen: the page's
  /// own player when the page has one, the SALU window when it has not, and its
  /// ack says which. Until a PC advertises `web_fullscreen` the phone keeps the
  /// old split — which is the behaviour this fix exists to remove, so it is a
  /// fallback, not the design.
  Future<void> _toggleFullscreen() async {
    if (_client.supportsWebFullscreen) {
      final bool wantOn = !_fullscreenOn;
      setState(() {
        _fullscreenHold = wantOn;
        _fullscreenHoldUntil = DateTime.now().add(_holdFor);
      });
      final RemoteReply reply = await runRemote(context, _client.webFullscreen);
      if (!mounted) return;
      if (reply.ok) return;
      if (reply.code == 'unknown_command' || reply.code == 'invalid_arguments') {
        // A promise the PC could not keep — keep this press useful anyway.
        setState(() {
          _fullscreenHold = null;
          _fullscreenHoldUntil = null;
        });
        await _legacyFullscreen();
        return;
      }
      // Any other error: put the icon back where the PC says it is.
      setState(() {
        _fullscreenHold = null;
        _fullscreenHoldUntil = null;
      });
      return;
    }
    await _legacyFullscreen();
  }

  /// The pre-§17.14 split, kept for an older PC: the page player when the page
  /// has a reachable one, the SALU window otherwise.
  Future<void> _legacyFullscreen() async {
    final WebMediaInfo? media = _media;
    if (media?.found == true && !_unreachable) {
      await _guarded(_client.webMediaFullscreen);
      return;
    }
    await runRemote(context, _client.fullscreenToggle);
  }

  /// Whether the fullscreen seat can do anything at all. With `web_fullscreen`
  /// the PC always answers (it chooses the target itself, and the window can
  /// always go fullscreen). Without it, the old rule stands: the page player
  /// only when the PC said it could, the window otherwise — a mark that cannot
  /// act is grey, as it was before.
  bool get _fullscreenEnabled {
    if (_client.supportsWebFullscreen) return true;
    final WebMediaInfo? media = _media;
    if (media?.found == true && !_unreachable) return media!.canFullscreen;
    return true;
  }

  /// **Home** (§17.14): the loaded page goes to its own site's front page, in
  /// the same tab — SALU's own home button, from the couch. A PC that does not
  /// answer the action gets the site's origin through `browser_open`, so the
  /// seat is never dead; `about:` pages and local files simply have no home to
  /// go to, and the mark is grey there.
  Future<void> _goHome() async {
    if (_client.supportsWebHome && !_homeRefused) {
      final RemoteReply reply = await runRemote(context, _client.browserHome);
      if (!mounted) return;
      if (reply.ok ||
          (reply.code != 'unknown_command' &&
              reply.code != 'invalid_arguments')) {
        return;
      }
      _homeRefused = true;
    }
    final String? home = siteHome(widget.snapshot.web.url);
    if (home == null) return;
    unawaited(runRemote(context, () => _client.browserOpen(home)));
  }

  // ── the page doors ────────────────────────────────────────────────────────

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
    final bool showMedia = _client.isOnline &&
        web.hasTabs &&
        media?.found == true &&
        !_unreachable;
    final bool canGoHome = _client.supportsWebHome ||
        siteHome(web.url) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _navRow(web, canGoHome: canGoHome),
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
        const SizedBox(height: 14),
        // The open tabs, at the foot of the body — a section with a heading and
        // a chevron, like the queue card (§17.14). It sits in the body rather
        // than in a sheet because a couch user switching tabs wants to see the
        // page they are switching *to*, and a sheet covers exactly that.
        WebTabsCard(
          snapshot: widget.snapshot,
          onNewTab: () => unawaited(_urlDialog(newTab: true)),
          // Another tab is in front now: reset holds and media immediately,
          // then poll the new tab's media.
          onTabChanged: () {
            setState(() {
              _media = null;
              _unreachable = false;
              _heldPosition = null;
              _positionHoldUntil = null;
              _heldVolume = null;
              _volumeHoldUntil = null;
            });
            unawaited(_pollOnce());
          },
        ),
      ],
    );
  }

  // ── nav row ──────────────────────────────────────────────────────────────

  /// One quiet row of page navigation (user, 2026-09-24): **Home · Back ·
  /// Forward · Reload · Fullscreen**, left to right, exactly as a browser's own
  /// row reads. The `▢ 3 tabs` door that used to end this row has moved into
  /// [WebTabsCard] at the foot of the body, and the fullscreen mark is now one
  /// seat instead of two different ones.
  ///
  /// Home is an *addition*, not a replacement (user's own words): nothing that
  /// worked here before has been taken away.
  Widget _navRow(SaluWeb web, {required bool canGoHome}) {
    final bool hasTabs = web.hasTabs;
    final bool canBack = hasTabs && web.canBack;
    final bool canForward = hasTabs && web.canForward;
    final bool canReload = hasTabs;
    final bool homeActive = hasTabs && canGoHome;
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: 'Home',
          onPressed: homeActive ? () => unawaited(_goHome()) : null,
          icon: Icon(
            Icons.home_outlined,
            color: homeActive ? AppColors.iconIdle : AppColors.statusUnknown,
          ),
        ),
        IconButton(
          tooltip: 'Back',
          onPressed: canBack
              ? () => unawaited(runRemote(context, () => _client.browserNav('back')))
              : null,
          icon: Icon(Icons.arrow_back,
              color: canBack ? AppColors.iconIdle : AppColors.statusUnknown),
        ),
        IconButton(
          tooltip: 'Forward',
          onPressed: canForward
              ? () =>
                  unawaited(runRemote(context, () => _client.browserNav('forward')))
              : null,
          icon: Icon(Icons.arrow_forward,
              color:
                  canForward ? AppColors.iconIdle : AppColors.statusUnknown),
        ),
        IconButton(
          tooltip: !hasTabs
              ? 'Reload'
              : (web.loading ? 'Stop' : 'Reload'),
          onPressed: canReload
              ? () => unawaited(
                  runRemote(
                    context,
                    () => _client.browserNav(web.loading ? 'stop' : 'reload'),
                  ),
                )
              : null,
          icon: Icon(
            web.loading && hasTabs ? Icons.stop : Icons.refresh,
            color: canReload ? AppColors.iconIdle : AppColors.statusUnknown,
          ),
        ),
        IconButton(
          tooltip: _fullscreenOn ? 'Exit fullscreen' : 'Fullscreen',
          onPressed: _fullscreenEnabled
              ? () => unawaited(_toggleFullscreen())
              : null,
          icon: Icon(
            _fullscreenOn ? Icons.fullscreen_exit : Icons.fullscreen,
            color: _fullscreenEnabled
                ? AppColors.iconIdle
                : AppColors.statusUnknown,
          ),
        ),
        const Spacer(),
        if (web.loading && hasTabs)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  /// The two doors the nav row has no room for. Both work against a PC that has
  /// not been updated: "New tab" is the URL box (which becomes a real new tab
  /// the moment the PC offers `web_tab_new`), and "Saved pages" is the PC
  /// browser's own bookmarks (`web_bookmarks`). The open-tab list has moved out
  /// of this row and into [WebTabsCard] below; this chip stays because it is the
  /// one new-tab door that works on *every* PC — the card's own ＋ is a bonus,
  /// not a replacement.
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
  /// When no tab is open on the PC, shows "No tab open" and omits the URL.
  Widget _pageCard(SaluWeb web) {
    final bool hasTabs = web.hasTabs;
    final String titleText = hasTabs ? (web.title ?? 'Loading…') : 'No tab open';
    final String? urlText = hasTabs ? web.url : null;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => unawaited(_urlDialog(newTab: !hasTabs && _client.supportsWebTabs)),
      onLongPress: () => unawaited(_openDiagnostics()),
      child: SaluCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              titleText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (urlText != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  urlText,
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
  ///
  /// **The text is normalised before it goes out** (`web_url.dart`, the
  /// 2026-09-24 blank-tab fix): "youtube.com" is sent as
  /// "https://youtube.com", because an address with no scheme is the one thing
  /// a page loader cannot guess at — it opens a tab and then sits there empty.
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
            final String? url = webAddress(_textController.text);
            if (url == null) return;
            Navigator.of(context).pop(url);
          },
          child: Text(widget.newTab ? 'Open tab' : 'Open'),
        ),
      ],
    );
  }
}
