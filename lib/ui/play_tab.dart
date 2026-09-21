import 'dart:async';

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
    final LinkState state = _client.link.value;
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

/// The Player-mode body: now playing → transport → chips → volume → queue.
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
        _nowPlaying(),
        const SizedBox(height: 14),
        _transport(),
        if (!focusMode && RemotePrefs.instance.isShown(PlaySection.chips)) ...<Widget>[
          const SizedBox(height: 14),
          _chips(),
        ],
        // Focus mode keeps the volume row (it is part of "eyes closed") —
        // only the chips and the queue card hide.
        if (RemotePrefs.instance.isShown(PlaySection.volume)) ...<Widget>[
          const SizedBox(height: 14),
          _volume(),
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

  Widget _nowPlaying() {
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
            // Optimistic locally, one `seek_to` on release. The PC clamps it.
            CommitSlider(
              value: playback.position.inMilliseconds.toDouble(),
              max: playback.duration.inMilliseconds.toDouble(),
              onCommit: (double value) =>
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

  Widget _transport() {
    final bool playing = snapshot.playback.isPlaying;
    return SaluCard(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          IconButton(
            iconSize: 30,
            tooltip: 'Previous',
            onPressed: () => unawaited(runRemote(context, client.previous)),
            icon: const Icon(Icons.skip_previous),
          ),
          IconButton(
            iconSize: 30,
            tooltip: 'Back 10 seconds',
            onPressed: () => unawaited(runRemote(context, () => client.seekBy(-10000))),
            icon: const Icon(Icons.replay_10),
          ),
          IconButton.filled(
            iconSize: 40,
            tooltip: playing ? 'Pause' : 'Play',
            onPressed: () => unawaited(runRemote(context, client.playPause)),
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          ),
          IconButton(
            iconSize: 30,
            tooltip: 'Forward 10 seconds',
            onPressed: () => unawaited(runRemote(context, () => client.seekBy(10000))),
            icon: const Icon(Icons.forward_10),
          ),
          IconButton(
            iconSize: 30,
            tooltip: 'Next',
            onPressed: () => unawaited(runRemote(context, client.next)),
            icon: const Icon(Icons.skip_next),
          ),
        ],
      ),
    );
  }

  Widget _chips() {
    final SaluPlayback playback = snapshot.playback;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        SaluChip(
          icon: Icons.stop,
          label: 'Stop',
          onTap: () => unawaited(runRemote(context, client.stop)),
        ),
        SaluChip(
          icon: Icons.shuffle,
          label: 'Shuffle',
          active: playback.shuffle,
          onTap: () => unawaited(runRemote(context, client.shuffleToggle)),
        ),
        SaluChip(
          icon: Icons.repeat,
          label: switch (playback.repeat) {
            RepeatMode.off => 'Repeat',
            RepeatMode.all => 'Repeat all',
            RepeatMode.one => 'Repeat one',
          },
          active: playback.repeat != RepeatMode.off,
          onTap: () => unawaited(runRemote(context, client.repeatCycle)),
        ),
        SaluChip(
          icon: playback.muted ? Icons.volume_off : Icons.volume_up,
          label: playback.muted ? 'Unmute' : 'Mute',
          active: playback.muted,
          onTap: () => unawaited(runRemote(context, client.muteToggle)),
        ),
        SaluChip(
          icon: Icons.fullscreen,
          label: snapshot.window.fullscreen ? 'Exit fullscreen' : 'Fullscreen',
          active: snapshot.window.fullscreen,
          onTap: () => unawaited(runRemote(context, client.fullscreenToggle)),
        ),
      ],
    );
  }

  Widget _volume() {
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
            child: CommitSlider(
              value: playback.volume.toDouble(),
              max: 100,
              onCommit: (double value) =>
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
