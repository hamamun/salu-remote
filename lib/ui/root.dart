import 'dart:async';

import 'package:flutter/material.dart';

import '../core/client.dart';
import '../core/deep_link.dart';
import '../core/models.dart';
import '../core/prefs.dart';
import '../core/screen.dart';
import 'browse_tab.dart';
import 'connect_sheet.dart';
import 'play_tab.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'tune_tab.dart';
import 'widgets.dart';

/// The app shell: header (dot · name · focus · overflow), three tabs
/// (Play · Browse · Tune), the mini now-playing strip, and the connect sheet
/// (`remote_apk_ui.md` §2).
///
/// Connect stops being a screen most of the time: it is a **sheet** that
/// slides up only when a connection is missing or the user taps the header.
/// First launch = the Connect sheet; every launch after that = straight to
/// Play, already connected.
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

enum _MenuItem { settings, forget }

class _RootPageState extends State<RootPage> with WidgetsBindingObserver {
  final SaluClient _client = SaluClient.instance;
  final RemotePrefs _prefs = RemotePrefs.instance;

  /// The tabs watch this to know when they are on screen (the Web body's
  /// 1/s poll, the stream list's refresh).
  final ValueNotifier<int> _activeTab = ValueNotifier<int>(0);
  int _tab = 0;
  bool _focus = false;

  LinkState _lastLink = LinkState.idle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keep the screen awake while the remote is open (D6).
    unawaited(ScreenAwake.set(true));
    _tab = _prefs.lastTab.clamp(0, 2);
    _activeTab.value = _tab;
    _focus = _prefs.focusMode;
    _lastLink = _client.link.value;
    _client.snapshot.addListener(_onSnapshot);
    _client.link.addListener(_onLinkState);
    DeepLink.pending.addListener(_onDeepLink);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // First launch: nothing remembered, nothing connected = the Connect
      // sheet (`remote_apk_ui.md` §2.1).
      if (!_prefs.isPaired && !_client.isOnline) _openConnectSheet();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ScreenAwake.set(false));
    _client.snapshot.removeListener(_onSnapshot);
    _client.link.removeListener(_onLinkState);
    DeepLink.pending.removeListener(_onDeepLink);
    _activeTab.dispose();
    super.dispose();
  }

  void _onLinkState() {
    final LinkState current = _client.link.value;
    final LinkState previous = _lastLink;
    _lastLink = current;
    // PC closed / connection lost — return to initial stage (user request).
    // Snapshot is already cleared in SaluClient so PlayTab shows waiting.
    // Jump to Play and open the Connect sheet, same as first launch.
    if (previous == LinkState.online && current != LinkState.online) {
      if (_tab != 0) _setTab(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_client.snapshot.value == null) {
          _openConnectSheet();
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the lock screen: ask for a fresh picture of the PC
    // instead of showing something stale.
    if (state == AppLifecycleState.resumed) {
      unawaited(ScreenAwake.set(true));
      unawaited(_client.onResume());
    } else if (state == AppLifecycleState.paused) {
      unawaited(ScreenAwake.set(false));
    }
  }

  void _onSnapshot() {
    // Switching into Web mode while Browse is up moves the user to Play
    // (§2.1) — the tab greys out rather than vanishing, but a bounce is worse
    // than a move.
    final SaluSnapshot? snapshot = _client.snapshot.value;
    if (snapshot != null && snapshot.isWeb && _tab == BrowseTab.tabIndex) {
      _setTab(0);
    }
  }

  void _onDeepLink() {
    final PairLink? link = DeepLink.pending.value;
    if (link == null) return;
    DeepLink.pending.value = null;
    // A scanned QR (in-app or system camera) opens the sheet pre-filled and
    // connects at once — scanning *is* the pairing.
    _openConnectSheet(prefill: link);
  }

  void _setTab(int index) {
    if (index == _tab) return;
    setState(() => _tab = index);
    _activeTab.value = index;
    unawaited(_prefs.setLastTab(index));
  }

  void _toggleFocus() {
    setState(() => _focus = !_focus);
    unawaited(_prefs.setFocusMode(_focus));
  }

  void _openConnectSheet({PairLink? prefill}) {
    if (ModalRoute.of(context)?.isCurrent != true && prefill == null) return;
    ConnectSheet.show(context, prefill: prefill);
  }

  Future<void> _forget() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Forget this PC?'),
        content: const Text(
          'The app will forget the address and the pairing. You will need the '
          'code from the PC again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _client.disconnect(forget: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(titleSpacing: 16, title: _header(), actions: _headerActions()),
      body: ValueListenableBuilder<SaluSnapshot?>(
        valueListenable: _client.snapshot,
        builder: (BuildContext context, SaluSnapshot? snapshot, _) {
          final bool web = snapshot?.isWeb ?? false;
          return Column(
            children: <Widget>[
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: <Widget>[
                    PlayTab(focusMode: _focus, activeTab: _activeTab),
                    BrowseTab(
                      snapshot: snapshot,
                      isWeb: web,
                      activeTab: _activeTab,
                    ),
                    TuneTab(
                      snapshot: snapshot,
                      isWeb: web,
                      activeTab: _activeTab,
                      onGoPlay: () => _setTab(0),
                    ),
                  ],
                ),
              ),
              // The mini now-playing strip: Browse and Tune only, player
              // mode only (§2). Tap it → jump to Play; the pause button
              // works without leaving the screen.
              if (_tab != 0 &&
                  !web &&
                  snapshot != null &&
                  _prefs.isShown(PlaySection.miniStrip))
                _miniStrip(snapshot),
            ],
          );
        },
      ),
      // The bar listens to the snapshot in its own right (2026-09-24 bug fix):
      // it used to read `_client.snapshot.value` once, inside `_bottomBar`, and
      // so only ever refreshed when something *else* rebuilt this page. A mode
      // flip that did not move the tab left the Browse seat stuck in the state
      // it was built with — greyed, and still claiming the PC was in Web mode
      // after the PC had come back to Player.
      bottomNavigationBar: ValueListenableBuilder<SaluSnapshot?>(
        valueListenable: _client.snapshot,
        builder: (BuildContext context, SaluSnapshot? snapshot, _) =>
            _bottomBar(web: snapshot?.isWeb ?? false),
      ),
    );
  }

  // ── header ───────────────────────────────────────────────────────────────

  Widget _header() {
    return ValueListenableBuilder<LinkState>(
      valueListenable: _client.link,
      builder: (BuildContext context, LinkState state, _) {
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          // Tapping the header opens the connect sheet (§2.1).
          onTap: () => _openConnectSheet(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: <Widget>[
                _dot(state),
                const ActivityDot(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _client.server.value?.shortName ?? 'SALU Remote',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        state.label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _headerActions() {
    return <Widget>[
      if (_tab == 0)
        IconButton(
          tooltip: _focus ? 'Expand the remote' : 'Focus mode',
          onPressed: _toggleFocus,
          icon: Icon(_focus ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
        ),
      ValueListenableBuilder<LinkState>(
        valueListenable: _client.link,
        builder: (BuildContext context, LinkState state, _) => IconButton(
          tooltip: 'Reconnect',
          onPressed: state == LinkState.online
              ? null
              : () => unawaited(_client.reconnectRemembered()),
          icon: const Icon(Icons.refresh),
        ),
      ),
      PopupMenuButton<_MenuItem>(
        tooltip: 'Menu',
        onSelected: (_MenuItem item) {
          switch (item) {
            case _MenuItem.settings:
              SettingsSheet.show(context, onChanged: () => setState(() {}));
              break;
            case _MenuItem.forget:
              unawaited(_forget());
              break;
          }
        },
        itemBuilder: (BuildContext context) => const <PopupMenuEntry<_MenuItem>>[
          PopupMenuItem<_MenuItem>(
            value: _MenuItem.settings,
            child: ListTile(
              leading: Icon(Icons.settings_outlined),
              title: Text('Settings'),
            ),
          ),
          PopupMenuItem<_MenuItem>(
            value: _MenuItem.forget,
            child: ListTile(
              leading: Icon(Icons.link_off),
              title: Text('Forget this PC'),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _dot(LinkState state) {
    final Color colour;
    switch (state) {
      case LinkState.online:
        colour = AppColors.statusAlive;
      case LinkState.connecting:
        colour = AppColors.accent;
      case LinkState.needsPairing:
        colour = AppColors.statusDead;
      case LinkState.idle:
      case LinkState.unreachable:
      case LinkState.off:
        colour = AppColors.statusUnknown;
    }
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
    );
  }

  // ── bottom bar ───────────────────────────────────────────────────────────

  /// The bottom bar. [web] is handed in by the snapshot listener in [build] —
  /// **never read `_client.snapshot.value` in here.** A value read during
  /// `build` is a photograph of the last rebuild, and the bar rebuilds only
  /// when the tab, the focus mode or the checklist changes; the PC's mode
  /// changes whenever the PC likes. That mismatch is what kept the Browse seat
  /// greyed after SALU had already come back to Player mode.
  Widget _bottomBar({required bool web}) {
    final bool tuneShown = _prefs.isShown(PlaySection.tuneTab);
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            _bottomItem(
              index: 0,
              label: 'Play',
              icon: Icons.play_circle_outline,
              enabled: true,
            ),
            _bottomItem(
              index: BrowseTab.tabIndex,
              label: 'Browse',
              icon: Icons.folder_outlined,
              enabled: !web,
              disabledReason: 'Files and Streams are Player-only — the PC is in Web mode.',
            ),
            if (tuneShown)
              _bottomItem(
                index: TuneTab.tabIndex,
                label: 'Tune',
                icon: Icons.tune,
                enabled: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomItem({
    required int index,
    required String label,
    required IconData icon,
    required bool enabled,
    String? disabledReason,
  }) {
    final bool active = _tab == index;
    final Color colour = !enabled
        ? AppColors.statusUnknown
        : active
            ? AppColors.accent
            : AppColors.iconIdle;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? () => _setTab(index) : () {
          if (disabledReason != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(disabledReason)));
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 22, color: colour),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: colour,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── mini strip ───────────────────────────────────────────────────────────

  Widget _miniStrip(SaluSnapshot snapshot) {
    final SaluPlayback playback = snapshot.playback;
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: () => _setTab(0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: playback.isPlaying ? 'Pause' : 'Play',
                iconSize: 20,
                onPressed: () => unawaited(runRemote(context, _client.playPause)),
                icon: Icon(
                  playback.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: AppColors.iconIdle,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  playback.title ?? 'Nothing playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${SaluTheme.clock(playback.position)} / ${SaluTheme.clock(playback.duration)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
