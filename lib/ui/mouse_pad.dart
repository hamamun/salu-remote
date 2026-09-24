import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/client.dart';
import '../core/reply.dart';
import 'theme.dart';

/// The Tune tab in Web mode (user, 2026-09-24): **a trackpad, two arrows, and
/// one line**.
///
/// The old D-pad that used to live here is gone — its cross, OK, Esc, focus
/// card and every line of explanation with them. What replaces it is the thing
/// a person actually wants in front of a web page they cannot reach: the PC's own
/// pointer, under a thumb — and, since the user asked for it the same day, two
/// seats that scroll the page without moving the pointer at all.
///
/// | Gesture | Does | Verb |
/// |---|---|---|
/// | drag | the PC's pointer follows the thumb, live | `web_mouse_move {dx, dy}` |
/// | single tap | left click, where the pointer already is | `web_mouse_click {button:"left", count:1}` |
/// | double tap | **Enter** — activates whatever the page has focused | `web_key {key:"Enter"}` |
/// | ▲ / ▼ under the pad | the page's arrow key, once per tap | `web_key {key:"ArrowUp"\|"ArrowDown"}` |
///
/// **Why the arrows reuse `web_key` instead of asking for a new verb** (user,
/// 2026-09-24: *"is there no easy way"*). There is — it was already here. The
/// old D-pad's ▲▼ stayed in the protocol and stayed implemented on the PC when
/// the D-pad was deleted; only their seat on the phone went away
/// (`lib/core/client.dart` says so at the `webKey` seat). Giving them a seat
/// again costs **nothing on the PC**. Builds that implement and advertise
/// `web_key` already accept these arrows with the same focus-walk behavior as
/// the old D-pad. A real mouse-wheel verb would scroll
/// more evenly, and it is the right next step if these feel jumpy on real
/// sites — but it is a change in a second repository, and this one is not.
///
/// **What that honestly means.** The PC's `ArrowDown` is a *focus walk* — "next
/// focusable element, `scrollIntoView`, `focus()`" (`remote.md` §17.13.5), not
/// a measured scroll step. On an ordinary page it reads as scrolling, because
/// the page scrolls to keep the focused element centred; in a text field the
/// arrows move the caret, and a page with nothing focusable may not move. The
/// PC's own focus ring is what shows where the walk landed.
///
/// So: **one tap is one key, and deliberately no hold-to-repeat.** Repeated
/// focus walks can race through a page's tab order, rather than giving the user
/// a measured scroll step. Hold-to-repeat becomes worth having with a wheel
/// verb, where a step is a step.
///
/// Three rules make it feel like hardware rather than a remote:
///
/// * **Batched, never queued.** Travel is accumulated and flushed every 40 ms
///   (25 commands a second — the PC's budget is 30, and the web-media poll and
///   a ping have to fit beside it). Two packets may be in flight; a third waits
///   in the accumulator, so a laggy PC slows the pointer instead of stacking
///   stale movement behind it.
/// * **Nothing is drawn while the finger works.** No trail, no ripple, no
///   coordinates. The feedback is the PC's own cursor, which is the whole point.
/// * **One line, and only one.** Under the arrows it says *Mouse*. Each half of
///   this tab has its own promise from the PC (`web_mouse`, `web_key`), and if
///   one of them is missing that same line is the only thing that changes — the
///   pad stays exactly where it is, because the box is the tab.
class MousePad extends StatefulWidget {
  const MousePad({super.key});

  /// Thumb travel → pointer travel. A ~360 px pad against a 1920 px screen
  /// needs roughly this much gain for one comfortable swipe to cross the page,
  /// and it matches a laptop trackpad's feel. Multiplying here (rather than on
  /// the PC) keeps the one house rule: the phone converts what a thumb did into
  /// the PC's units, and the PC obeys (`lib/core/client.dart`).
  static const double gain = 2.5;

  /// One packet per 40 ms — see the class comment.
  static const Duration gap = Duration(milliseconds: 40);

  /// A single packet never carries more than this, so a flick across the pad
  /// arrives as several sane steps instead of one teleport the PC may reject.
  static const double maxStep = 320;

  /// The pad's share of the phone's screen height.
  ///
  /// **60%, down from 70%** (user, 2026-09-24). Separately, the layout
  /// reserves 100 dp under the pad for the 18 dp gap, 56 dp arrow row, and 26 dp
  /// caption allowance; the pad shrinks if the tab has less room.
  static const double heightFactor = 0.60;

  /// The two scroll seats under the pad: 56 dp thumb targets, 18 dp apart, in
  /// the pad's own surface and hairline so they read as part of the trackpad
  /// rather than as a toolbar that wandered in.
  static const double arrowSize = 56;
  static const double arrowGap = 18;

  /// Pad → arrow row.
  static const double controlsGap = 18;

  /// Arrow row → the one line: the gap (10) and the line itself (16).
  static const double caption = 26;

  @override
  State<MousePad> createState() => _MousePadState();
}

class _MousePadState extends State<MousePad> {
  final SaluClient _client = SaluClient.instance;

  Timer? _flush;
  double _dx = 0;
  double _dy = 0;
  bool _finger = false;

  /// Packets sent and not yet answered. Two is plenty: the pointer is only
  /// ever as smooth as the next packet, and a deeper queue is lag with extra
  /// steps.
  int _inFlight = 0;

  /// The PC advertised a feature and then answered `unknown_command` — say so
  /// in the one line instead of pressing into the dark.
  ///
  /// **One flag per feature, not one for the tab.** They used to share a flag,
  /// which meant a `web_key` refusal also silenced the trackpad: a PC with a
  /// working pointer and no key handler lost both.
  bool _mouseRefused = false;
  bool _keyRefused = false;

  bool get _mouse => _client.supportsWebMouse && !_mouseRefused;

  /// The arrows' own promise. `web_key` and `web_mouse` are separate entries in
  /// `hello.features` and a PC may have either without the other, so each half
  /// of this tab greys on its own and the line names the half that is missing.
  bool get _key => _client.supportsWebKey && !_keyRefused;

  @override
  void dispose() {
    _flush?.cancel();
    super.dispose();
  }

  // ── movement ──────────────────────────────────────────────────────────────

  void _start(DragStartDetails _) {
    _finger = true;
    _dx = 0;
    _dy = 0;
    _flush ??= Timer.periodic(MousePad.gap, (_) => _send());
  }

  void _move(DragUpdateDetails details) {
    _dx += details.delta.dx * MousePad.gain;
    _dy += details.delta.dy * MousePad.gain;
  }

  void _stop(DragEndDetails _) {
    _finger = false;
    _send(); // whatever the last 40 ms held, now.
    if (_dx == 0 && _dy == 0) _stopFlush();
  }

  void _stopFlush() {
    _flush?.cancel();
    _flush = null;
  }

  /// Send one packet: the accumulated travel, clamped, with the remainder kept
  /// for the next one. Fire-and-forget — a lost 40 ms of travel is invisible,
  /// and the PC's own cursor is the only feedback worth having.
  void _send() {
    if (!_mouse) {
      _dx = 0;
      _dy = 0;
      if (!_finger) _stopFlush();
      return;
    }
    if (_dx.abs() < 0.5 && _dy.abs() < 0.5) {
      if (!_finger) _stopFlush();
      return;
    }
    if (_inFlight >= 2) return; // the PC is behind: keep accumulating.
    final double sx =
        _dx.clamp(-MousePad.maxStep, MousePad.maxStep).toDouble();
    final double sy =
        _dy.clamp(-MousePad.maxStep, MousePad.maxStep).toDouble();
    _dx -= sx;
    _dy -= sy;
    _inFlight++;
    unawaited(
      _client
          .webMouseMove(sx, sy)
          .then(_noteMouseRefusal)
          .whenComplete(() => _inFlight--),
    );
  }

  // ── clicks ────────────────────────────────────────────────────────────────

  /// A tap is a left click where the pointer already stands — no move, exactly
  /// like a trackpad's tap-to-click.
  void _click() {
    if (!_mouse) return;
    unawaited(HapticFeedback.lightImpact());
    unawaited(_client.webMouseClick().then(_noteMouseRefusal));
  }

  /// A double tap is **Enter** (the user's own gesture list). Enter is the one
  /// key the page's focus model understands everywhere, and `web_key` already
  /// answers with what the page clicked — so this seat needs nothing new on the
  /// PC. A PC without `web_key` gets a double click instead, which lands the
  /// same way on most pages.
  void _enter() {
    unawaited(HapticFeedback.lightImpact());
    if (_key) {
      unawaited(_client.webKey('Enter').then(_noteKeyRefusal));
      return;
    }
    if (!_mouse) return;
    unawaited(_client.webMouseClick(count: 2).then(_noteMouseRefusal));
  }

  // ── scrolling ─────────────────────────────────────────────────────────────

  /// One press of one arrow: the page's own arrow key, once.
  ///
  /// Fire-and-forget like the moves, but with **no batching and no queue** —
  /// these arrive at a human's tapping rate (a frantic thumb is still a handful
  /// a second against the PC's 30/s budget), and a swallowed tap is something a
  /// thumb notices, where a swallowed 40 ms of travel is not.
  void _arrow(String key) {
    if (!_key) return;
    unawaited(HapticFeedback.lightImpact());
    unawaited(_client.webKey(key).then(_noteKeyRefusal));
  }

  void _noteMouseRefusal(RemoteReply reply) {
    if (!mounted || reply.ok || reply.code != 'unknown_command') return;
    setState(() => _mouseRefused = true);
  }

  void _noteKeyRefusal(RemoteReply reply) {
    if (!mounted || reply.ok || reply.code != 'unknown_command') return;
    setState(() => _keyRefused = true);
  }

  // ── the pad ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Dynamic sizing:
        // Height = 60% of the phone's full screen height, clamped to the room
        //          left once the arrow row and the caption have taken theirs
        // Width  = 100% of the screen width
        //
        // The row's room is subtracted *before* the clamp rather than taken out
        // of whatever the pad left over, so a short screen (landscape, a small
        // phone) shrinks the pad instead of pushing the arrows off the tab —
        // and the tab still never scrolls, because a scrolling parent would
        // fight the pad's own drag for the gesture arena.
        final Size screen = MediaQuery.sizeOf(context);
        final double reserved =
            MousePad.arrowSize + MousePad.controlsGap + MousePad.caption;
        final double targetHeight = screen.height > 0
            ? screen.height * MousePad.heightFactor
            : 260.0;
        final double maxRoom = constraints.maxHeight.isFinite
            ? (constraints.maxHeight - reserved)
                .clamp(60.0, double.infinity)
                .toDouble()
            : targetHeight;
        final double padHeight =
            targetHeight > maxRoom ? maxRoom : targetHeight;
        final double padWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : (screen.width > 0 ? screen.width : 320.0);

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: padWidth,
              height: padHeight,
              child: _pad(),
            ),
            const SizedBox(height: MousePad.controlsGap),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _arrowButton(
                  icon: Icons.keyboard_arrow_up,
                  label: 'Scroll up',
                  keyName: 'ArrowUp',
                ),
                const SizedBox(width: MousePad.arrowGap),
                _arrowButton(
                  icon: Icons.keyboard_arrow_down,
                  label: 'Scroll down',
                  keyName: 'ArrowDown',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(_line, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }

  Widget _pad() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _start,
      onPanUpdate: _move,
      onPanEnd: _stop,
      onPanCancel: () {
        _finger = false;
        _stopFlush();
      },
      // Tap and double tap are both registered, so a single tap is confirmed
      // after the double-tap window (~300 ms) — the price of having both, and
      // the reason the pad never pretends to have clicked before it has.
      onTap: _click,
      onDoubleTap: _enter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[AppColors.surfaceHighlight, AppColors.surface],
          ),
          border: Border.all(
            color: _mouse ? AppColors.surfaceOutline : AppColors.statusUnknown,
            width: 1.4,
          ),
        ),
      ),
    );
  }

  /// One scroll seat. Round, hairline-bordered, the pad's own gradient — a
  /// thumb target that belongs to the trackpad, not a toolbar glyph.
  ///
  /// When the PC has no `web_key` the seat is greyed rather than hidden, and
  /// the line under it says why: a button that vanishes is a button the user
  /// keeps looking for, and one that silently does nothing is worse than both.
  Widget _arrowButton({
    required IconData icon,
    required String label,
    required String keyName,
  }) {
    final bool live = _key;
    return Semantics(
      button: true,
      enabled: live,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onTap: live ? () => _arrow(keyName) : null,
          child: Container(
            width: MousePad.arrowSize,
            height: MousePad.arrowSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: live
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        AppColors.surfaceHighlight,
                        AppColors.surface,
                      ],
                    )
                  : null,
              color: live ? null : AppColors.surface,
              border: Border.all(
                color:
                    live ? AppColors.surfaceOutline : AppColors.statusUnknown,
                width: 1.4,
              ),
            ),
            child: Icon(
              icon,
              size: 32,
              color: live ? AppColors.iconIdle : AppColors.statusUnknown,
            ),
          ),
        ),
      ),
    );
  }

  /// The one line. It names the thing, and — only when the PC cannot do it —
  /// says so, because a pad that silently does nothing is the one outcome worth
  /// a sentence. Each half of the tab is promised separately, so the sentence
  /// names the half that is missing.
  String get _line {
    if (_mouse && _key) return 'Mouse';
    if (!_mouse) {
      return _key
          ? 'Mouse needs an updated SALU on the PC'
          : 'Mouse and scroll need an updated SALU on the PC';
    }
    return 'Scroll needs an updated SALU on the PC';
  }
}
