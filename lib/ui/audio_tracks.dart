import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/client.dart';
import '../core/models.dart';
import '../core/reply.dart';
import 'theme.dart';
import 'widgets.dart';

/// Tune → Audio (`remote_apk_ui.md` §6.3): a humble list, included because
/// multi-track files are common and this is one screen of work. A tap
/// switches the track — no confirmation.
class AudioTracksPane extends StatefulWidget {
  const AudioTracksPane({
    super.key,
    required this.snapshot,
    required this.activeTab,
    required this.myIndex,
  });

  final SaluSnapshot snapshot;
  final ValueListenable<int> activeTab;
  final int myIndex;

  @override
  State<AudioTracksPane> createState() => _AudioTracksPaneState();
}

class _AudioTracksPaneState extends State<AudioTracksPane> {
  static const int _visibleTrackRows = 5;
  static const double _trackRowExtent = 64;

  final SaluClient _client = SaluClient.instance;
  final ScrollController _tracksScroll = ScrollController();
  SubsInfo? _info;
  bool _loading = false;
  bool _requestInFlight = false;
  bool _reloadPending = false;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    widget.activeTab.addListener(_onActive);
    if (widget.activeTab.value == widget.myIndex) _startPolling();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(AudioTracksPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTab != widget.activeTab) {
      oldWidget.activeTab.removeListener(_onActive);
      widget.activeTab.addListener(_onActive);
      _syncPolling();
    }

    final SaluSnapshot old = oldWidget.snapshot;
    final SaluSnapshot current = widget.snapshot;
    if (old.playback.title != current.playback.title ||
        old.tracks.audio != current.tracks.audio ||
        old.tracks.subs != current.tracks.subs) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    widget.activeTab.removeListener(_onActive);
    _refreshTimer?.cancel();
    _tracksScroll.dispose();
    super.dispose();
  }

  void _onActive() {
    if (widget.activeTab.value == widget.myIndex) {
      unawaited(_load());
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  void _syncPolling() {
    if (widget.activeTab.value == widget.myIndex) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  void _startPolling() {
    _refreshTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_load()),
    );
  }

  void _stopPolling() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _load() async {
    if (_requestInFlight) {
      _reloadPending = true;
      return;
    }
    _requestInFlight = true;
    if (mounted) {
      setState(() {
        _loading = _info == null;
        _error = null;
      });
    }

    try {
      final RemoteReply reply = await _client.subsGet();
      if (!mounted) return;
      if (reply.ok) {
        final SubsInfo next = SubsInfo.from(reply.data);
        final List<TrackInfo> previousTracks =
            _info?.audioTracks ?? const <TrackInfo>[];
        final bool selectionChanged =
            _info == null ||
            _selectedIndex(previousTracks) != _selectedIndex(next.audioTracks) ||
            _selectedId(previousTracks) != _selectedId(next.audioTracks);
        setState(() {
          _info = next;
          _loading = false;
          _error = null;
        });
        if (selectionChanged) _scheduleScrollToSelected();
      } else {
        setState(() {
          _loading = false;
          _error = reply.message;
        });
      }
    } finally {
      _requestInFlight = false;
      if (mounted && _reloadPending) {
        _reloadPending = false;
        unawaited(_load());
      }
    }
  }

  int _selectedIndex(List<TrackInfo> tracks) =>
      tracks.indexWhere((TrackInfo track) => track.selected);

  String? _selectedId(List<TrackInfo> tracks) {
    final int index = _selectedIndex(tracks);
    return index < 0 ? null : tracks[index].id;
  }

  void _scheduleScrollToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tracksScroll.hasClients) return;
      final int selected = _selectedIndex(_info?.audioTracks ?? const <TrackInfo>[]);
      if (selected < 0) return;
      final double target =
          (selected * _trackRowExtent -
                  (_visibleTrackRows - 1) * _trackRowExtent / 2)
              .clamp(0.0, _tracksScroll.position.maxScrollExtent)
              .toDouble();
      _tracksScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _select(TrackInfo track) async {
    final RemoteReply reply =
        await runRemote(context, () => _client.subSelect(kind: 'audio', id: track.id));
    if (!reply.ok || !mounted || _info == null) return;

    setState(() {
      _info = SubsInfo(
        delay: _info!.delay,
        lang: _info!.lang,
        autoDownload: _info!.autoDownload,
        engine: _info!.engine,
        audioTracks: _info!.audioTracks
            .map((TrackInfo t) => TrackInfo(
                  id: t.id,
                  title: t.title,
                  lang: t.lang,
                  codec: t.codec,
                  channels: t.channels,
                  external: t.external,
                  selected: t.id == track.id,
                ))
            .toList(),
        subTracks: _info!.subTracks,
      );
    });
    _scheduleScrollToSelected();
    // Replace the optimistic highlight with the PC's returned track state.
    unawaited(_load());
  }

  double _viewportHeight(int rowCount) {
    final int visible = rowCount < _visibleTrackRows ? rowCount : _visibleTrackRows;
    return visible * _trackRowExtent;
  }

  @override
  Widget build(BuildContext context) {
    final SubsInfo? info = _info;
    if (_error != null && info == null) {
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
    final List<TrackInfo> tracks = info?.audioTracks ?? const <TrackInfo>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'This file has a single audio track — nothing to switch.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          SectionCard(
            title: 'Audio tracks',
            trailing: '${tracks.length}',
            memoryKey: 'audio_tracks',
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              height: _viewportHeight(tracks.length),
              child: Scrollbar(
                controller: _tracksScroll,
                thumbVisibility: tracks.length > _visibleTrackRows,
                child: ListView.builder(
                  controller: _tracksScroll,
                  itemCount: tracks.length,
                  itemExtent: _trackRowExtent,
                  padding: EdgeInsets.zero,
                  itemBuilder: (BuildContext context, int index) =>
                      _trackRow(tracks[index]),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _trackRow(TrackInfo track) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => unawaited(_select(track)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    track.displayTitle,
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
}
