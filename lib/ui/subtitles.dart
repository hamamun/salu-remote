import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/client.dart';
import '../core/models.dart';
import '../core/reply.dart';
import 'files_browser.dart';
import 'subs_search.dart';
import 'theme.dart';
import 'widgets.dart';

/// Tune → Subtitles (`remote_apk_ui.md` §6.2): the PC's subtitle engine,
/// driven from the couch. The PC does all the work — download, apply, name
/// the file; the phone only asks and watches.
class SubtitlesPane extends StatefulWidget {
  const SubtitlesPane({
    super.key,
    required this.snapshot,
    required this.activeTab,
    required this.myIndex,
  });

  final SaluSnapshot snapshot;
  final ValueListenable<int> activeTab;
  final int myIndex;

  @override
  State<SubtitlesPane> createState() => _SubtitlesPaneState();
}

class _SubtitlesPaneState extends State<SubtitlesPane> {
  final SaluClient _client = SaluClient.instance;
  SubsInfo? _info;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.activeTab.addListener(_onActive);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.activeTab.removeListener(_onActive);
    super.dispose();
  }

  @override
  void didUpdateWidget(SubtitlesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new file started on the PC: the track list of the old one is now a
    // lie.
    if (oldWidget.snapshot.playback.title != widget.snapshot.playback.title) {
      unawaited(_load());
    }
  }

  void _onActive() {
    if (widget.activeTab.value == widget.myIndex) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
    });
    final RemoteReply reply = await _client.subsGet();
    if (!mounted) return;
    if (reply.ok) {
      setState(() {
        _info = SubsInfo.from(reply.data);
      });
    } else {
      setState(() {
        _error = reply.message;
      });
    }
  }

  // ── actions ──────────────────────────────────────────────────────────────

  Future<void> _selectSub(String id) async {
    final bool ok =
        (await runRemote(context, () => _client.subSelect(kind: 'sub', id: id))).ok;
    if (ok && mounted && _info != null) {
      setState(() {
        _info = SubsInfo(
          delay: _info!.delay,
          lang: _info!.lang,
          autoDownload: _info!.autoDownload,
          engine: _info!.engine,
          audioTracks: _info!.audioTracks,
          subTracks: _info!
              .subTracks
              .map((TrackInfo t) => TrackInfo(
                    id: t.id,
                    title: t.title,
                    lang: t.lang,
                    codec: t.codec,
                    channels: t.channels,
                    external: t.external,
                    // `id == 'no'` (off) selects nothing.
                    selected: t.id == id,
                  ))
              .toList(),
        );
      });
    }
  }

  Future<void> _delayStep(double delta) async {
    final bool ok =
        (await runRemote(context, () => _client.subDelayStep(delta))).ok;
    if (ok && mounted && _info != null) {
      setState(() {
        _info = SubsInfo(
          delay: _info!.delay + delta,
          lang: _info!.lang,
          autoDownload: _info!.autoDownload,
          engine: _info!.engine,
          audioTracks: _info!.audioTracks,
          subTracks: _info!.subTracks,
        );
      });
    }
  }

  Future<void> _delayReset() async {
    final bool ok =
        (await runRemote(context, () => _client.subDelayReset())).ok;
    if (ok && mounted && _info != null) {
      setState(() {
        _info = SubsInfo(
          delay: 0,
          lang: _info!.lang,
          autoDownload: _info!.autoDownload,
          engine: _info!.engine,
          audioTracks: _info!.audioTracks,
          subTracks: _info!.subTracks,
        );
      });
    }
  }

  Future<void> _autoDownload(bool on) async {
    final bool ok = (await runRemote(context, () => _client.subsAuto(on))).ok;
    if (ok && mounted && _info != null) {
      setState(() {
        _info = SubsInfo(
          delay: _info!.delay,
          lang: _info!.lang,
          autoDownload: on,
          engine: _info!.engine,
          audioTracks: _info!.audioTracks,
          subTracks: _info!.subTracks,
        );
      });
    }
  }

  Future<void> _picker() async {
    // One browser, two jobs: the Files screen in subtitle mode
    // (`remote_apk_ui.md` §6.2).
    final bool? loaded = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => FilesBrowser(
          snapshot: widget.snapshot,
          subtitleMode: true,
        ),
      ),
    );
    if (loaded == true) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Subtitle loaded on the PC')));
      }
      await _load();
    }
  }

  Future<void> _search() async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => SubsSearchScreen(
          snapshot: widget.snapshot,
          initialQuery: widget.snapshot.playback.title ?? '',
          initialLang: _info?.lang ?? widget.snapshot.subs.lang,
          onLoaded: () => unawaited(_load()),
        ),
      ),
    );
    if (changed == true) await _load();
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final SubsInfo? info = _info;
    if (info == null) {
      if (_error != null) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            EmptyState(
              message: _error ?? "The PC didn't answer.",
              actionLabel: 'Try again',
              onAction: () => unawaited(_load()),
            ),
          ],
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final bool anySelected =
        info.subTracks.any((TrackInfo t) => t.selected);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        // ── tracks ────────────────────────────────────────────────────────
        SectionCard(
          title: 'Tracks',
          trailing: '${info.subTracks.length}',
          memoryKey: 'subs_tracks',
          padding: const EdgeInsets.all(8),
          child: info.subTracks.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No subtitle tracks in this file.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : Column(
                  children: <Widget>[
                    for (final TrackInfo track in info.subTracks) _trackRow(track),
                    _offRow(selected: !anySelected, onTap: () => unawaited(_selectSub('no'))),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        // ── sync ──────────────────────────────────────────────────────────
        SectionCard(
          title: 'Sync',
          memoryKey: 'subs_sync',
          padding: const EdgeInsets.all(8),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  _HoldButton(
                    label: '−0.5s',
                    onStep: () => unawaited(_delayStep(-0.5)),
                  ),
                  const Spacer(),
                  Text(
                    _fmtDelay(info.delay),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  _HoldButton(
                    label: '+0.5s',
                    onStep: () => unawaited(_delayStep(0.5)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => unawaited(_delayReset()),
                  child: const Text('Reset'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // ── search + file + auto ──────────────────────────────────────────
        // No key blocks *searching*; being signed out or quota-paused blocks
        // *downloading* — the PC tells the difference and the phone shows
        // each in its own words (`remote_apk_ui.md` §7).
        if (!info.engine.key)
          _warning('Add an OpenSubtitles key on the PC to search.')
        else
          FilledButton.icon(
            icon: const Icon(Icons.search),
            label: const Text('Search online…'),
            onPressed: _search,
          ),
        if (info.engine.key && (info.engine.quotaPaused || !info.engine.signedIn))
          _warning(
            info.engine.quotaPaused
                ? 'OpenSubtitles download limit reached — try again tomorrow.'
                : 'Search works, but signing in on the PC is needed to download.',
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.insert_drive_file_outlined),
          label: const Text('Add a subtitle file'),
          onPressed: () => unawaited(_picker()),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          dense: true,
          title: const Text('Auto-download on play', style: TextStyle(fontSize: 13.5)),
          value: info.autoDownload,
          onChanged: (bool v) => unawaited(_autoDownload(v)),
        ),
      ],
    );
  }

  Widget _trackRow(TrackInfo track) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => unawaited(_selectSub(track.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              track.selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 18,
              color: track.selected ? AppColors.accent : AppColors.statusUnknown,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: track.selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (track.detail.isNotEmpty)
                    Text(
                      track.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _offRow({required bool selected, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 18,
              color: selected ? AppColors.accent : AppColors.statusUnknown,
            ),
            const SizedBox(width: 10),
            const Text('off', style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  static String _fmtDelay(double d) {
    if (d == 0) return '0.0 s';
    final String s = d.toStringAsFixed(1);
    return d > 0 ? '+$s s' : '$s s';
  }

  Widget _warning(String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.info_outline, size: 16, color: AppColors.statusDead),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: AppColors.statusDead, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

/// A −/+ button with hold-to-repeat: one tap = one 0.5 s step, holding
/// repeats every 250 ms (`remote_apk_ui.md` §6.2).
class _HoldButton extends StatefulWidget {
  const _HoldButton({required this.label, required this.onStep});

  final String label;
  final VoidCallback onStep;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  Timer? _repeat;

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  void _start() {
    widget.onStep();
    _repeat?.cancel();
    _repeat = Timer.periodic(const Duration(milliseconds: 250), (Timer t) {
      widget.onStep();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onStep,
      onLongPressStart: (LongPressStartDetails d) => _start(),
      onLongPressEnd: (LongPressEndDetails d) => _stop(),
      onLongPressCancel: _stop,
      child: Material(
        color: AppColors.surfaceHighlight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.surfaceOutline, width: 1.2),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            widget.label,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
