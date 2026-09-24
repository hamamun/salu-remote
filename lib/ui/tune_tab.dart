import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/client.dart';
import '../core/models.dart';
import '../core/prefs.dart';
import 'audio_tracks.dart';
import 'connect_sheet.dart';
import 'equalizer.dart';
import 'mouse_pad.dart';
import 'subtitles.dart';
import 'widgets.dart';

/// Tab 3 — Tune (`remote_apk_ui.md` §6): Equalizer, Subtitles and Audio are
/// all "change what is happening right now", so they share a tab with a
/// segmented switch — and all three are meaningless when nothing is playing,
/// so the tab says *"Nothing is playing"* in one place, with a Play shortcut.
///
/// **In Web mode the tab becomes a mouse pad** (user, 2026-09-24, replacing the
/// D-pad of §6.0). There is no equalizer, no subtitle track and no audio track
/// when what is playing is a web page — what there is, is a page the user
/// cannot reach from the couch, and the honest answer to that is the PC's own
/// pointer under a thumb. The tab is one trackpad, two scroll arrows and one
/// line; everything that used to explain itself here is gone
/// (`remote.md` §17.14).
class TuneTab extends StatefulWidget {
  const TuneTab({
    super.key,
    required this.snapshot,
    required this.isWeb,
    required this.activeTab,
    required this.onGoPlay,
  });

  static const int tabIndex = 2;

  final SaluSnapshot? snapshot;
  final bool isWeb;
  final ValueListenable<int> activeTab;
  final VoidCallback onGoPlay;

  @override
  State<TuneTab> createState() => _TuneTabState();
}

enum _TuneSegment { equalizer, subtitles, audio }

class _TuneTabState extends State<TuneTab> {
  _TuneSegment _segment = _TuneSegment.equalizer;

  /// The visible options, in order. The Subtitles segment is hidden by the
  /// Settings checklist (`remote_apk_ui.md` §3).
  List<_TuneSegment> get _options => <_TuneSegment>[
        _TuneSegment.equalizer,
        if (RemotePrefs.instance.isShown(PlaySection.subtitlesCard))
          _TuneSegment.subtitles,
        _TuneSegment.audio,
      ];

  String _label(_TuneSegment segment) => switch (segment) {
        _TuneSegment.equalizer => 'Equalizer',
        _TuneSegment.subtitles => 'Subtitles',
        _TuneSegment.audio => 'Audio',
      };

  @override
  Widget build(BuildContext context) {
    final SaluSnapshot? snapshot = widget.snapshot;
    if (snapshot == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          EmptyState(
            message: SaluClient.instance.isOnline
                ? 'Waiting for your PC…'
                : 'Tune needs a connection. Connect to your PC first.',
            actionLabel: SaluClient.instance.isOnline ? null : 'Connect',
            onAction: () => ConnectSheet.show(context),
          ),
        ],
      );
    }
    if (widget.isWeb) {
      // mpv is not in the picture in Web mode: no equalizer, no subtitle
      // track, no audio track. What there is, is a page — and a pointer for it.
      //
      // No scroll view: the tab holds one thing — the pad, which sizes itself
      // dynamically to 100% screen width and 60% screen height with the arrow
      // row's room reserved underneath it (`MousePad`) — and a scrolling parent
      // would only fight the pad's own drag for the gesture arena.
      return const MousePad();
    }
    if (snapshot.nothingPlaying) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          EmptyState(
            message: 'Nothing is playing.',
            actionLabel: 'Go to Play',
            onAction: widget.onGoPlay,
          ),
        ],
      );
    }
    final List<_TuneSegment> options = _options;
    // The segment was hidden in Settings while selected — fall back to EQ.
    final _TuneSegment segment =
        options.contains(_segment) ? _segment : _TuneSegment.equalizer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SaluSegments(
            options: [for (final _TuneSegment s in options) SegmentOption(_label(s))],
            selectedIndex: options.indexOf(segment),
            onSelect: (int i) => setState(() => _segment = options[i]),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: switch (segment) {
            _TuneSegment.equalizer => EqualizerPane(
                snapshot: snapshot,
                activeTab: widget.activeTab,
                myIndex: TuneTab.tabIndex,
              ),
            _TuneSegment.subtitles => SubtitlesPane(
                snapshot: snapshot,
                activeTab: widget.activeTab,
                myIndex: TuneTab.tabIndex,
              ),
            _TuneSegment.audio => AudioTracksPane(
                snapshot: snapshot,
                activeTab: widget.activeTab,
                myIndex: TuneTab.tabIndex,
              ),
          },
        ),
      ],
    );
  }
}
