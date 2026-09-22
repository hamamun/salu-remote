import 'dart:async';

import 'package:flutter/foundation.dart';
// `RepeatMode` below is the protocol enum from core/models.dart,
// not Flutter's animation one.
import 'package:flutter/material.dart' hide RepeatMode;

import '../core/client.dart';
import '../core/models.dart';
import '../core/prefs.dart';
import 'connect_sheet.dart';
import 'queue_card.dart';
import 'theme.dart';
import 'web_body.dart';
import 'widgets.dart';

/// Tab 1 — Play (`remote_apk_ui.md` §4): 90% of all use. In Player mode it is
/// the everyday remote (now playing, transport, chips, volume, playlist); in
/// Web mode the same tab transforms into the web body. One 200 ms cross-fade
/// between the two, so a mode flip never looks like a crash.
class PlayTab extends StatefulWidget {
  const PlayTab({
    super.key,
    required this.focusMode,
    required this.activeTab,
  });

  /// Focus mode (header chevron): the Play tab collapsed to the bare
  /// essentials — the remote you can use with your eyes closed.
  final bool focusMode;

  /// The root's active-tab notifier. The web body's ~1/s media poll runs
  /// only while this tab is on screen (`remote_apk_ui.md` §8).
  final ValueListenable<int> activeTab;

  @override
  State<PlayTab> createState() => _PlayTabState();
}

class _PlayTabState extends State<PlayTab> {
  final SaluClient _client = SaluClient.instance;
  final RemotePrefs _prefs = RemotePrefs.instance;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SaluSnapshot?>(
      valueListenable: _client.snapshot,
      builder: (BuildContext context, SaluSnapshot? snapshot, _) {
        if (snapshot == null) return _waiting();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: <Widget>[
            if (_prefs.isShown(PlaySection.modePill)) ...<Widget>[
              _modePill(snapshot),
              const SizedBox(height: 14),
            ],
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: snapshot.isWeb
                  ? WebBody(
                      key: const ValueKey('web'),
                      snapshot: snapshot,
                      activeTab: widget.activeTab,
                    )
                  : _PlayerBody(
                      key: const ValueKey('player'),
                      snapshot: snapshot,
                      focusMode: widget.focusMode,
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _waiting() {
    // Both notifiers feed this card: the state picks the title, and the
    // client's own diagnosis (firewall, wrong port, code rejected…) replaces
    // the generic hint the moment there is one.
    return ValueListenableBuilder<LinkState>(
      valueListenable: _client.link,
      builder: (BuildContext context, LinkState state, _) {
        return ValueListenableBuilder<String?>(
          valueListenable: _client.problemMessage,
          builder: (BuildContext context, String? problem, _) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                SaluCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        state == LinkState.connecting
                            ? 'Reaching your PC…'
                            : state == LinkState.unreachable
                                ? 'Trying to reach your PC again…'
                                : 'Not connected yet.',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        problem ??
                            'Make sure SALU is running with Remote switched on, and that this '
                                'phone is on the same Wi-Fi as the PC.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text('Connect'),
                        onPressed: () => ConnectSheet.show(context),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// The mode pill — a label *and* a switch. It always shows the PC's real
  /// mode (the PC drives it); both seats are visible so the user sees where
  /// they are going before they go (`remote_apk_ui.md` §2.1, §4.1).
  Widget _modePill(SaluSnapshot snapshot) {
    final bool web = snapshot.isWeb;
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _seat(
            icon: Icons.play_circle_outline,
            label: 'Player',
            active: !web,
            onTap: web
                ? () => unawaited(runRemote(context, () => _client.modeSet('player')))
                : null,
          ),
          const SizedBox(width: 8),
          _seat(
            icon: Icons.public,
            label: 'Web',
            active: web,
            onTap: !web
                ? () => unawaited(runRemote(context, () => _client.modeSet('web')))
                : null,
          ),
        ],
      ),
    );
  }

  Widget _seat({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: active ? AppColors.surfaceHighlight : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: active ? AppColors.accent : AppColors.surfaceOutline,
          width: 1.2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: active ? AppColors.accent : AppColors.iconIdle),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Player-mode body (layout per user, 2026-09-22):
/// now playing (title + seek bar) → one transport row (play/pause · stop ·
/// previous · next · −10 s · +10 s · fullscreen, all one style and one size)
/// → repeat · shuffle (icon-only row) → mute + volume slider → queue.
/// Focus mode keeps only now playing, transport and volume
/// (`remote_apk_ui.md` §3, mechanism 1).
class _PlayerBody extends StatelessWidget {
  const _PlayerBody({super.key, required this.snapshot, required this.focusMode});

  final SaluSnapshot snapshot;
  final bool focusMode;

  static final SaluClient client = SaluClient.instance;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _nowPlaying(context),
        const SizedBox(height: 14),
        _transport(context),
        // The old text chips are gone (user, 2026-09-22): stop and fullscreen
        // moved into the transport row as icons, mute lives with the volume
        // slider, and repeat + shuffle keep their own icon-only row — still
        // behind the "secondary chips" setting and hidden in focus mode.
        if (!focusMode && RemotePrefs.instance.isShown(PlaySection.chips)) ...<Widget>[
          const SizedBox(height: 14),
          _toggles(context),
        ],
        // Focus mode keeps the volume row (it is part of "eyes closed") —
        // only the toggles row and the queue card hide.
        if (RemotePrefs.instance.isShown(PlaySection.volume)) ...<Widget>[
          const SizedBox(height: 14),
          _volume(context),
        ],
        if (!focusMode &&
            RemotePrefs.instance.isShown(PlaySection.queue) &&
            snapshot.queue.hasRows) ...<Widget>[
          const SizedBox(height: 14),
          QueueCard(snapshot: snapshot),
        ],
      ],
    );
  }

  Widget _nowPlaying(BuildContext context) {
    final SaluPlayback playback = snapshot.playback;
    return SaluCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            playback.title ?? 'Nothing playing',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (playback.seekable)
            // Realtime while dragging (user, 2026-09-22): throttled `seek_to`
            // updates as the thumb moves, final value on release. Optimistic
            // locally; the PC clamps.
            LiveSlider(
              value: playback.position.inMilliseconds.toDouble(),
              max: playback.duration.inMilliseconds.toDouble(),
              onLive: (double value) =>
                  unawaited(runRemote(context, () => client.seekTo(value.round()))),
            )
          else
            Text(
              playback.hasSomething ? 'Live / not seekable' : '—',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (playback.seekable)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(SaluTheme.clock(playback.position),
                    style: Theme.of(context).textTheme.bodySmall),
                Text(
                  <String>[
                    playback.state.name,
                    if (snapshot.queue.hasRows)
                      '${snapshot.queue.index + 1}/${snapshot.queue.count}'
                    else
                      'no queue',
                    if (snapshot.queue.isChannels) 'channels',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(SaluTheme.clock(playback.duration),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          if (playback.buffering)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(minHeight: 3),
            ),
        ],
      ),
    );
  }

  /// One row, one style, one size (user, 2026-09-22):
  /// play/pause · stop · previous · next · −10 s · +10 s · fullscreen.
  /// No filled play button anymore and no text chips — every seat is the
  /// same plain icon at the same size.
  Widget _transport(BuildContext context) {
    final bool playing = snapshot.playback.isPlaying;
    final bool fullscreen = snapshot.window.fullscreen;
    return SaluCard(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _control(
            icon: playing ? Icons.pause : Icons.play_arrow,
            tooltip: playing ? 'Pause' : 'Play',
            onPressed: () => unawaited(runRemote(context, client.playPause)),
          ),
          _control(
            icon: Icons.stop,
            tooltip: 'Stop',
            onPressed: () => unawaited(runRemote(context, client.stop)),
          ),
          _control(
            icon: Icons.skip_previous,
            tooltip: 'Previous',
            onPressed: () => unawaited(runRemote(context, client.previous)),
          ),
          _control(
            icon: Icons.skip_next,
            tooltip: 'Next',
            onPressed: () => unawaited(runRemote(context, client.next)),
          ),
          _control(
            icon: Icons.replay_10,
            tooltip: 'Back 10 seconds',
            onPressed: () => unawaited(runRemote(context, () => client.seekBy(-10000))),
          ),
          _control(
            icon: Icons.forward_10,
            tooltip: 'Forward 10 seconds',
            onPressed: () => unawaited(runRemote(context, () => client.seekBy(10000))),
          ),
          _control(
            icon: fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            tooltip: fullscreen ? 'Exit fullscreen' : 'Fullscreen',
            active: fullscreen,
            onPressed: () => unawaited(runRemote(context, client.fullscreenToggle)),
          ),
        ],
      ),
    );
  }

  /// Repeat · shuffle · start over — icon-only, on their own row (user,
  /// 2026-09-22: "shuffle repeat mute fullscreen all should be icon based").
  /// The repeat icon itself says which mode is on: `repeat` for all,
  /// `repeat_one` for one, accent-coloured whenever it is not off.
  ///
  /// **Start over** `⟲` is a conditional third seat (`remote_apk_ui.md` §4.1):
  /// it mirrors the PC's Resume toast — appears when `playback.resume` is
  /// non-null, disappears when the toast closes. Tap = `restart` (0:00 and
  /// play, which also closes the toast). The seat never outlives the toast
  /// and never appears without one, on either screen.
  Widget _toggles(BuildContext context) {
    final SaluPlayback playback = snapshot.playback;
    return SaluCard(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _control(
            icon: playback.repeat == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
            tooltip: switch (playback.repeat) {
              RepeatMode.off => 'Repeat off',
              RepeatMode.all => 'Repeat all',
              RepeatMode.one => 'Repeat one',
            },
            active: playback.repeat != RepeatMode.off,
            onPressed: () => unawaited(runRemote(context, client.repeatCycle)),
          ),
          _control(
            icon: Icons.shuffle,
            tooltip: playback.shuffle ? 'Shuffle on' : 'Shuffle off',
            active: playback.shuffle,
            onPressed: () => unawaited(runRemote(context, client.shuffleToggle)),
          ),
          // Start over — only while the PC's Resume toast is up.
          // Plain `Icons.replay`; `replay_10` beside it in the transport
          // row already owns the "−10 s" reading. Accent tint marks it as
          // live rather than decorative.
          if (playback.hasResume)
            _control(
              icon: Icons.replay,
              tooltip:
                  'Start over from ${SaluTheme.clock(Duration(milliseconds: playback.resumePositionMs!))}',
              active: true,
              onPressed: () => unawaited(runRemote(context, client.restart)),
            ),
        ],
      ),
    );
  }

  /// The one control-button shape — every transport and toggle seat uses it,
  /// so the whole block is the same style at the same size. [active] tints
  /// the icon with the accent.
  Widget _control({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool active = false,
  }) {
    return IconButton(
      iconSize: 26,
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: active ? AppColors.accent : AppColors.iconIdle),
    );
  }

  /// Mute + volume (user, 2026-09-22): the **one** mute button lives at the
  /// left of the slider — the second copy that used to sit in the chip row is
  /// gone. The slider fires live while dragging, like the seek bar.
  Widget _volume(BuildContext context) {
    final SaluPlayback playback = snapshot.playback;
    return SaluCard(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: playback.muted ? 'Unmute' : 'Mute',
            onPressed: () => unawaited(runRemote(context, client.muteToggle)),
            icon: Icon(playback.muted ? Icons.volume_off : Icons.volume_up,
                color: playback.muted ? AppColors.statusDead : AppColors.iconIdle),
          ),
          Expanded(
            child: LiveSlider(
              value: playback.volume.toDouble(),
              max: 100,
              onLive: (double value) =>
                  unawaited(runRemote(context, () => client.setVolume(value.round()))),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${playback.volume}',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
