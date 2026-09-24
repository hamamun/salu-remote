import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/client.dart';
import '../core/reply.dart';
import 'theme.dart';

/// The Tune tab in Web mode (user, 2026-09-24): **a trackpad, and one line**.
///
/// The D-pad that used to live here is gone — arrows, OK, Esc, the focus card
/// and every line of explanation with them. What replaces it is the thing a
/// person actually wants in front of a web page they cannot reach: the PC's own
/// pointer, under a thumb.
///
/// | Gesture | Does | Verb |
/// |---|---|---|
/// | drag | the PC's pointer follows the thumb, live | `web_mouse_move {dx, dy}` |
/// | single tap | left click, where the pointer already is | `web_mouse_click {button:"left", count:1}` |
/// | double tap | **Enter** — activates whatever the page has focused | `web_key {key:"Enter"}` |
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
/// * **One line, and only one.** Under the pad it says *Mouse*. If the PC has
///   not advertised `web_mouse`, that same line is the only thing that changes
///   — the pad itself stays exactly where it is, because the box is the tab.
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

  /// The PC advertised `web_mouse` and then answered `unknown_command` — say so
  /// in the one line instead of pressing into the dark.
  bool _refused = false;

  /// The pad's own shape — a laptop trackpad's proportion. Its *size* comes
  /// from whatever room the tab has left (see [build]), so the box is as large
  /// as the screen allows and never scrolls.
  static const double _aspect = 1.5;

  bool get _mouse => _client.supportsWebMouse && !_refused;

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
    final double sx = _dx.clamp(-MousePad.maxStep, MousePad.maxStep);
    final double sy = _dy.clamp(-MousePad.maxStep, MousePad.maxStep);
    _dx -= sx;
    _dy -= sy;
    _inFlight++;
    unawaited(
      _client.webMouseMove(sx, sy).whenComplete(() => _inFlight--),
    );
  }

  // ── clicks ────────────────────────────────────────────────────────────────

  /// A tap is a left click where the pointer already stands — no move, exactly
  /// like a trackpad's tap-to-click.
  void _click() {
    if (!_mouse) return;
    unawaited(HapticFeedback.lightImpact());
    unawaited(_client.webMouseClick().then(_noteRefusal));
  }

  /// A double tap is **Enter** (the user's own gesture list). Enter is the one
  /// key the page's focus model understands everywhere, and `web_key` already
  /// answers with what the page clicked — so this seat needs nothing new on the
  /// PC. A PC without `web_key` gets a double click instead, which lands the
  /// same way on most pages.
  void _enter() {
    unawaited(HapticFeedback.lightImpact());
    if (_client.supportsWebKey) {
      unawaited(_client.webKey('Enter').then(_noteRefusal));
      return;
    }
    if (!_mouse) return;
    unawaited(_client.webMouseClick(count: 2).then(_noteRefusal));
  }

  void _noteRefusal(RemoteReply reply) {
    if (!mounted || reply.ok) return;
    if (reply.code == 'unknown_command') setState(() => _refused = true);
  }

  // ── the pad ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The line under the pad plus its gap, reserved before the box is
        // sized — so the pad always fits the tab without anything scrolling.
        const double caption = 26;
        final double room = constraints.maxHeight.isFinite
            ? (constraints.maxHeight - caption).clamp(60.0, double.infinity)
            : 260.0;
        final double width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        double padWidth = width;
        double padHeight = padWidth / _aspect;
        if (padHeight > room) {
          padHeight = room;
          padWidth = padHeight * _aspect;
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: padWidth,
              height: padHeight,
              child: _pad(),
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

  /// The one line. It names the thing, and — only when the PC cannot do it —
  /// says so, because a pad that silently does nothing is the one outcome worth
  /// a sentence.
  String get _line =>
      _mouse ? 'Mouse' : 'Mouse needs an updated SALU on the PC';
}
