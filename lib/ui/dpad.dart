import 'dart:async';

import 'package:flutter/material.dart';

import '../core/client.dart';
import 'theme.dart';
import 'widgets.dart';

/// The D-pad — the Tune tab in Web mode (`remote_apk_ui.md` §6.0). In Web
/// mode there is no equalizer, no subtitle track and no audio track to
/// choose; what there is is a web page the user cannot reach from the couch.
///
/// | Key  | Does                                        | Verb |
/// |------|---------------------------------------------|------|
/// | ▲ ▼  | walk the page's focusable elements          | `web_key {key:"ArrowUp"|"ArrowDown"}` |
/// | ◀ ▶  | history back / forward — the escape hatch   | `browser_nav {action:"back"|"forward"}` |
/// | OK   | activate the focused element                | `web_key {key:"Enter"}` |
///
/// The PC must draw a ring on whatever the phone has focused — without it
/// the user is steering the browser blind. (That ring is the PC's job; this
/// widget is only the pad.)
class DPad extends StatelessWidget {
  const DPad({super.key});

  static final SaluClient client = SaluClient.instance;

  @override
  Widget build(BuildContext context) {
    final double s = 64;
    return Column(
      children: <Widget>[
        const SizedBox(height: 8),
        // ▲
        _pad(
          icon: Icons.keyboard_arrow_up,
          tooltip: 'Focus up',
          onPressed: () => unawaited(runRemote(context, () => client.webKey('ArrowUp'))),
          size: s,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // ◀ history back
            _pad(
              icon: Icons.keyboard_arrow_left,
              tooltip: 'Back',
              onPressed: () =>
                  unawaited(runRemote(context, () => client.browserNav('back'))),
              size: s,
            ),
            const SizedBox(width: 8),
            // OK
            _pad(
              icon: Icons.check,
              tooltip: 'Activate (Enter)',
              filled: true,
              onPressed: () => unawaited(runRemote(context, () => client.webKey('Enter'))),
              size: s + 12,
            ),
            const SizedBox(width: 8),
            // ▶ history forward
            _pad(
              icon: Icons.keyboard_arrow_right,
              tooltip: 'Forward',
              onPressed: () =>
                  unawaited(runRemote(context, () => client.browserNav('forward'))),
              size: s,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // ▼
        _pad(
          icon: Icons.keyboard_arrow_down,
          tooltip: 'Focus down',
          onPressed: () => unawaited(runRemote(context, () => client.webKey('ArrowDown'))),
          size: s,
        ),
        const SizedBox(height: 20),
        Text(
          '▲▼ move the focus · ◀▶ back and forward · OK clicks',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Text(
          'The PC draws a ring around what is focused — if you see no ring '
          'after a press, the page may not expose a focus order.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _pad({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    double size = 64,
    bool filled = false,
  }) {
    return filled
        ? IconButton.filled(
            iconSize: size * 0.5,
            tooltip: tooltip,
            onPressed: onPressed,
            style: IconButton.styleFrom(
              minimumSize: Size(size, size),
              shape: const CircleBorder(),
            ),
            icon: Icon(icon, size: size * 0.5),
          )
        : IconButton(
            iconSize: size * 0.5,
            tooltip: tooltip,
            onPressed: onPressed,
            style: IconButton.styleFrom(
              minimumSize: Size(size, size),
              shape: const CircleBorder(),
              backgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.surfaceOutline, width: 1.2),
            ),
            icon: Icon(icon, size: size * 0.5, color: AppColors.iconIdle),
          );
  }
}
