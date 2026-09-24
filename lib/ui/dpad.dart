import 'dart:async';

import 'package:flutter/material.dart';

import '../core/client.dart';
import '../core/models.dart';
import '../core/reply.dart';
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
/// | Esc  | leave page fullscreen, close a dialog       | `web_key {key:"Escape"}` |
///
/// **The pad draws only the keys this PC answers.** `web_key` is specified but
/// not implemented on every build, so an un-updated PC gets the ◀ ▶ pair —
/// plain `browser_nav`, which everything has — plus one line saying what is
/// missing. A dead button is the fastest way to make an app feel broken; a
/// smaller pad with a sentence is just an honest one.
///
/// The PC must draw a ring on whatever the phone has focused — without it the
/// user is steering the browser blind. That ring is the PC's job; this widget
/// is the pad, the focus line under it, and nothing else.
class DPad extends StatefulWidget {
  const DPad({super.key});

  @override
  State<DPad> createState() => _DPadState();
}

class _DPadState extends State<DPad> {
  final SaluClient _client = SaluClient.instance;

  WebFocusInfo _focus = const WebFocusInfo();
  bool _reading = false;

  /// The PC advertised `web_key` and then answered `unknown_command` — a
  /// promise it cannot keep. Say so once rather than pressing into the dark.
  bool _refused = false;

  bool get _supported => _client.supportsWebKey;

  @override
  void initState() {
    super.initState();
    if (_supported) unawaited(_readFocus());
  }

  /// Read the page's focus without moving it, so the pad opens already
  /// knowing where it is (`web_focus_get`).
  Future<void> _readFocus() async {
    if (!_supported || _reading) return;
    // Set, not setState: this runs from initState on the first pass, where
    // there is nothing on screen to rebuild yet. The `_reading` guard is what
    // stops a second read, and it is checked synchronously.
    _reading = true;
    final RemoteReply reply = await _client.webFocusGet();
    if (!mounted) return;
    setState(() {
      _reading = false;
      if (reply.ok) {
        // Either `{focus:{…}}` or the fields at the top level — the phone takes
        // whichever the PC sent.
        _focus = WebFocusInfo.from(reply.data['focus'] ?? reply.data);
      } else if (reply.code == 'unknown_command') {
        _refused = true;
      }
    });
  }

  Future<void> _key(String key) async {
    final RemoteReply reply = await runRemote(context, () => _client.webKey(key));
    if (!mounted) return;
    if (reply.ok) {
      // The PC answers with what the page has focused *now* — that line is the
      // whole difference between steering the browser and guessing at it.
      final Object? focus = reply.data['focus'];
      if (focus != null) setState(() => _focus = WebFocusInfo.from(focus));
      return;
    }
    if (reply.code == 'unknown_command') setState(() => _refused = true);
  }

  /// ◀ ▶ are plain history — `browser_nav`, which every PC answers, supported
  /// or not.
  Future<void> _nav(String action) async {
    await runRemote(context, () => _client.browserNav(action));
  }

  @override
  Widget build(BuildContext context) {
    final bool supported = _supported && !_refused;
    return Column(
      children: <Widget>[
        const SizedBox(height: 8),
        if (supported)
          _pad(
            icon: Icons.keyboard_arrow_up,
            tooltip: 'Focus up',
            onPressed: () => unawaited(_key('ArrowUp')),
          ),
        if (supported) const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // ◀ history back — the escape hatch when focus-walking lands
            // somewhere useless. Every PC has it.
            _pad(
              icon: Icons.keyboard_arrow_left,
              tooltip: 'Back',
              onPressed: () => unawaited(_nav('back')),
            ),
            if (supported) ...<Widget>[
              const SizedBox(width: 8),
              // OK
              _pad(
                icon: Icons.check,
                tooltip: 'Activate (Enter)',
                filled: true,
                onPressed: () => unawaited(_key('Enter')),
              ),
            ],
            const SizedBox(width: 8),
            // ▶ history forward
            _pad(
              icon: Icons.keyboard_arrow_right,
              tooltip: 'Forward',
              onPressed: () => unawaited(_nav('forward')),
            ),
          ],
        ),
        if (supported) ...<Widget>[
          const SizedBox(height: 8),
          _pad(
            icon: Icons.keyboard_arrow_down,
            tooltip: 'Focus down',
            onPressed: () => unawaited(_key('ArrowDown')),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: <Widget>[
              SaluChip(
                icon: Icons.close,
                label: 'Esc',
                onTap: () => unawaited(_key('Escape')),
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        _focusCard(supported),
      ],
    );
  }

  /// What the page has focused, and — when the pad is short — what is missing
  /// and why. One card, two sentences at most.
  Widget _focusCard(bool supported) {
    final String headline;
    final String hint;
    if (!supported) {
      headline = _refused ? 'The PC is not answering keys' : 'Focus walking is not on this PC';
      hint = _refused
          ? 'SALU on the PC advertised web_key but did not answer it. Update SALU and try again.'
          : 'Back and forward above work now. Moving the focus on the page (▲▼ and OK) '
              'needs an updated SALU on the PC.';
    } else {
      headline = _focus.known ? _focus.line : 'Nothing focused yet';
      hint = _focus.editable
          ? 'A text field has the focus: ▲▼ move the caret and OK submits.'
          : '▲▼ move the focus · ◀▶ back and forward · OK clicks';
    }
    return SaluCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(hint, style: Theme.of(context).textTheme.bodySmall),
                if (supported) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'The PC draws a ring around what is focused — no ring after a '
                    'press means the page keeps its own focus order.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (supported)
            IconButton(
              tooltip: 'Read the focus again',
              onPressed: _reading ? null : () => unawaited(_readFocus()),
              icon: const Icon(Icons.refresh, color: AppColors.iconIdle),
            ),
        ],
      ),
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
              minimumSize: Size(size + 12, size + 12),
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
