import 'package:flutter/material.dart';

import '../core/client.dart';
import '../core/models.dart';
import '../core/prefs.dart';
import 'connect_sheet.dart';
import 'files_browser.dart';
import 'streams.dart';
import 'widgets.dart';

/// Tab 2 — Browse (`remote_apk_ui.md` §5): "Files" and "Streams" are the same
/// user intention (find something to play), so they share a tab with a
/// segmented switch.
///
/// **Browse is Player-only** (§2.1): opening a PC file pulls the PC back to
/// Player mode anyway (D8), so the tab greys out in Web mode instead of
/// bouncing the user. The root moves the user to Play on a mode flip; this
/// guard covers the one frame in between.
class BrowseTab extends StatefulWidget {
  const BrowseTab({
    super.key,
    required this.snapshot,
    required this.isWeb,
    required this.activeTab,
  });

  static const int tabIndex = 1;

  final SaluSnapshot? snapshot;
  final bool isWeb;
  final ValueListenable<int> activeTab;

  @override
  State<BrowseTab> createState() => _BrowseTabState();
}

class _BrowseTabState extends State<BrowseTab> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final SaluSnapshot? snapshot = widget.snapshot;
    if (snapshot == null) {
      return const _Offline();
    }
    if (widget.isWeb) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const EmptyState(
            message: 'Files and Streams are Player-only — the PC is in Web mode '
                'right now, so there are no files to browse and the stream list '
                'would pull the PC out of the browser.',
          ),
        ],
      );
    }
    final bool streamsShown = RemotePrefs.instance.isShown(PlaySection.streamsSegment);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: streamsShown
              ? SaluSegments(
                  options: const <SegmentOption>[
                    SegmentOption('Files'),
                    SegmentOption('Streams'),
                  ],
                  selectedIndex: _segment,
                  onSelect: (int i) => setState(() => _segment = i),
                )
              : const SizedBox.shrink(),
        ),
        if (streamsShown) const SizedBox(height: 14),
        Expanded(
          child: _segment == 1 && streamsShown
              ? StreamsPane(activeTab: widget.activeTab, myIndex: BrowseTab.tabIndex)
              : FilesBrowser(snapshot: snapshot, subtitleMode: false),
        ),
      ],
    );
  }
}

class _Offline extends StatelessWidget {
  const _Offline();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        EmptyState(
          message: SaluClient.instance.isOnline
              ? 'Waiting for your PC…'
              : 'Browse needs a connection. Connect to your PC first.',
          actionLabel: SaluClient.instance.isOnline ? null : 'Connect',
          onAction: () => ConnectSheet.show(context),
        ),
      ],
    );
  }
}
