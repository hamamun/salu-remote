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
  final SaluClient _client = SaluClient.instance;
  SubsInfo? _info;
  bool _loading = false;
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

  void _onActive() {
    if (widget.activeTab.value == widget.myIndex) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = _info == null;
      _error = null;
    });
    final RemoteReply reply = await _client.subsGet();
    if (!mounted) return;
    if (reply.ok) {
      setState(() {
        _info = SubsInfo.from(reply.data);
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = reply.message;
      });
    }
  }

  Future<void> _select(TrackInfo track) async {
    // The row highlights immediately, the PC catches up (§8).
    final RemoteReply reply =
        await runRemote(context, () => _client.subSelect(kind: 'audio', id: track.id));
    if (reply.ok && mounted && _info != null) {
      setState(() {
        _info = SubsInfo(
          delay: _info!.delay,
          lang: _info!.lang,
          autoDownload: _info!.autoDownload,
          engine: _info!.engine,
          audioTracks: _info!
              .audioTracks
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
    }
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
            child: Column(
              children: <Widget>[
                for (final TrackInfo track in tracks)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => unawaited(_select(track)),
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
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
