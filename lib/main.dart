import 'dart:async';

import 'package:flutter/material.dart';

import 'core/client.dart';
import 'core/error_copy.dart';
import 'core/models.dart';
import 'core/prefs.dart';
import 'core/reply.dart';
import 'core/screen.dart';
import 'ui/theme.dart';

/// SALU Remote — the phone half of SALU (`remote.md`, `remote_apk_ui.md`).
///
/// **Where the app is right now.** This is the first working build: it pairs by
/// address + code and drives playback with live feedback from the PC. It is
/// deliberately plain — the three-tab SALU interface (Play · Browse · Tune),
/// the QR scanner and the drawn marks arrive next. Everything under `lib/core/`
/// and `lib/protocol/` is already in its final shape, so those steps only add
/// screens on top.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RemotePrefs.instance.load();
  runApp(const SaluRemoteApp());
  // After the first frame, never before it: a cold start must not wait on a
  // socket (`remote.md` §11).
  unawaited(SaluClient.instance.autoConnect());
}

class SaluRemoteApp extends StatelessWidget {
  const SaluRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SALU Remote',
      debugShowCheckedModeBanner: false,
      theme: SaluTheme.build(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final SaluClient _client = SaluClient.instance;
  final TextEditingController _address = TextEditingController();
  final TextEditingController _code = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keep the screen awake while the remote is open (D6).
    unawaited(ScreenAwake.set(true));
    final RemotePrefs prefs = RemotePrefs.instance;
    if (prefs.host != null) {
      _address.text = '${prefs.host}:${prefs.port ?? 7258}';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ScreenAwake.set(false));
    _address.dispose();
    _code.dispose();
    super.dispose();
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

  Future<void> _connect() async {
    final String raw = _address.text.trim();
    if (raw.isEmpty) {
      _say("Type the PC address first — the PC's Remote panel shows it.");
      return;
    }
    String host = raw;
    int port = 7258;
    final int colon = raw.lastIndexOf(':');
    if (colon > 0) {
      host = raw.substring(0, colon).trim();
      port = int.tryParse(raw.substring(colon + 1).trim()) ?? 7258;
    }
    setState(() => _busy = true);
    await _client.connect(
      host: host,
      port: port,
      code: _code.text.trim().isEmpty ? null : _code.text.trim(),
    );
    if (mounted) setState(() => _busy = false);
  }

  void _say(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  /// Fire a verb and, if the PC refused it, say why in its own words — unless
  /// the code is one the specs deliberately keep silent (`remote.md` §17.8,
  /// where `too_fast` and `no_preset` are "(silent, logged)").
  Future<void> _run(Future<RemoteReply> Function() action) async {
    final RemoteReply reply = await action();
    if (!reply.ok && !RemoteErrorCopy.isSilent(reply.code) && mounted) {
      _say(RemoteErrorCopy.text(reply.code, reply.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: ValueListenableBuilder<LinkState>(
          valueListenable: _client.link,
          builder: (BuildContext context, LinkState state, _) => _header(state),
        ),
        actions: <Widget>[
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
          IconButton(
            tooltip: 'Forget this PC',
            onPressed: _forget,
            icon: const Icon(Icons.link_off),
          ),
        ],
      ),
      // Two listeners on purpose: the link state decides which card is shown,
      // the snapshot redraws everything inside it as the PC talks.
      body: ValueListenableBuilder<LinkState>(
        valueListenable: _client.link,
        builder: (BuildContext context, LinkState state, _) =>
            ValueListenableBuilder<SaluSnapshot?>(
          valueListenable: _client.snapshot,
          builder: (BuildContext context, SaluSnapshot? snapshot, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: <Widget>[
                if (state != LinkState.online) ...<Widget>[
                  _pairCard(state),
                  const SizedBox(height: 16),
                ],
                if (snapshot != null) ...<Widget>[
                  _playingCard(snapshot),
                  const SizedBox(height: 14),
                  _controls(snapshot),
                  const SizedBox(height: 14),
                  _chips(snapshot),
                  const SizedBox(height: 14),
                  _volume(snapshot),
                ] else
                  _waitingCard(state),
                const SizedBox(height: 20),
                _aboutCard(snapshot),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── pieces ────────────────────────────────────────────────────────────────

  Widget _header(LinkState state) => Row(
        children: <Widget>[
          _dot(state),
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
                Text(state.label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      );

  Widget _dot(LinkState state) {
    final Color colour;
    switch (state) {
      case LinkState.online:
        colour = AppColors.statusAlive;
        break;
      case LinkState.connecting:
        colour = AppColors.accent;
        break;
      case LinkState.needsPairing:
        colour = AppColors.statusDead;
        break;
      case LinkState.idle:
      case LinkState.unreachable:
      case LinkState.off:
        colour = AppColors.statusUnknown;
        break;
    }
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
    );
  }

  Widget _pairCard(LinkState state) => SaluCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Connect to your PC', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'On the PC: right-click the picture → Remote → the panel shows the '
              'address and a code. Type them here once; after that this app '
              'remembers your PC forever.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'PC address',
                hintText: '192.168.0.12:7258',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _code,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Pairing code (only the first time)',
                hintText: '7K4M-QP2X',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _connect,
              child: Text(_busy ? 'Connecting…' : 'Connect'),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: _client.problemMessage,
              builder: (BuildContext context, String? message, _) {
                if (message == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(Icons.info_outline,
                          size: 16, color: AppColors.statusDead),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(
                              color: AppColors.statusDead, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      );

  Widget _waitingCard(LinkState state) => SaluCard(
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
          ],
        ),
      );

  Widget _playingCard(SaluSnapshot snapshot) {
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
                  unawaited(_run(() => _client.seekTo(value.round()))),
            )
          else
            Text(
              playback.hasSomething ? 'Live / not seekable' : '—',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
        ],
      ),
    );
  }

  Widget _controls(SaluSnapshot snapshot) {
    final bool playing = snapshot.playback.isPlaying;
    return SaluCard(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          IconButton(
            iconSize: 30,
            tooltip: 'Previous',
            onPressed: () => unawaited(_run(_client.previous)),
            icon: const Icon(Icons.skip_previous),
          ),
          IconButton(
            iconSize: 30,
            tooltip: 'Back 10 seconds',
            onPressed: () => unawaited(_run(() => _client.seekBy(-10000))),
            icon: const Icon(Icons.replay_10),
          ),
          IconButton.filled(
            iconSize: 40,
            tooltip: playing ? 'Pause' : 'Play',
            onPressed: () => unawaited(_run(_client.playPause)),
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          ),
          IconButton(
            iconSize: 30,
            tooltip: 'Forward 10 seconds',
            onPressed: () => unawaited(_run(() => _client.seekBy(10000))),
            icon: const Icon(Icons.forward_10),
          ),
          IconButton(
            iconSize: 30,
            tooltip: 'Next',
            onPressed: () => unawaited(_run(_client.next)),
            icon: const Icon(Icons.skip_next),
          ),
        ],
      ),
    );
  }

  Widget _chips(SaluSnapshot snapshot) {
    final SaluPlayback playback = snapshot.playback;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _chip(icon: Icons.stop, label: 'Stop', onTap: () => unawaited(_run(_client.stop))),
        _chip(
          icon: Icons.shuffle,
          label: 'Shuffle',
          active: playback.shuffle,
          onTap: () => unawaited(_run(_client.shuffleToggle)),
        ),
        _chip(
          icon: Icons.repeat,
          label: switch (playback.repeat) {
            RepeatMode.off => 'Repeat',
            RepeatMode.all => 'Repeat all',
            RepeatMode.one => 'Repeat one',
          },
          active: playback.repeat != RepeatMode.off,
          onTap: () => unawaited(_run(_client.repeatCycle)),
        ),
        _chip(
          icon: playback.muted ? Icons.volume_off : Icons.volume_up,
          label: playback.muted ? 'Unmute' : 'Mute',
          active: playback.muted,
          onTap: () => unawaited(_run(_client.muteToggle)),
        ),
        _chip(
          icon: snapshot.isWeb ? Icons.language : Icons.play_circle_outline,
          label: snapshot.isWeb ? 'Web mode' : 'Player mode',
          active: snapshot.isWeb,
          onTap: () => unawaited(
            _run(() => _client.modeSet(snapshot.isWeb ? 'player' : 'web')),
          ),
        ),
      ],
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) =>
      Material(
        color: active ? AppColors.surfaceHighlight : AppColors.surface,
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 18, color: active ? AppColors.accent : AppColors.iconIdle),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      );

  Widget _volume(SaluSnapshot snapshot) => SaluCard(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: 'Volume down',
              onPressed: () => unawaited(_run(() => _client.volumeStep(-5))),
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: CommitSlider(
                value: snapshot.playback.volume.toDouble(),
                max: 100,
                onCommit: (double value) =>
                    unawaited(_run(() => _client.setVolume(value.round()))),
              ),
            ),
            IconButton(
              tooltip: 'Volume up',
              onPressed: () => unawaited(_run(() => _client.volumeStep(5))),
              icon: const Icon(Icons.add),
            ),
            SizedBox(
              width: 38,
              child: Text(
                '${snapshot.playback.volume}',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );

  Widget _aboutCard(SaluSnapshot? snapshot) => SaluCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('This build', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'First working step: pairing and playback control. The QR scanner '
              'and the three tabs (Play · Browse · Tune) come next.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _fact('PC', _client.server.value?.name ?? '—'),
            _fact('Address', _client.address.value ?? '—'),
            _fact('PC version', _client.server.value?.version ?? '—'),
            _fact(
              'Round trip',
              _client.latencyMs.value == null ? '—' : '${_client.latencyMs.value} ms',
            ),
            _fact('Control', snapshot == null ? '—' : snapshot.control.name ?? 'free'),
            _fact('This phone', RemotePrefs.instance.deviceName),
            if (snapshot != null) _fact('Player', snapshot.playback.state.name),
            if (snapshot != null)
              _fact('Streams saved', '${snapshot.libraryCount} on the PC'),
          ],
        ),
      );

  Widget _fact(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 108,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
          ],
        ),
      );

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
      if (mounted) setState(() => _code.clear());
    }
  }
}
