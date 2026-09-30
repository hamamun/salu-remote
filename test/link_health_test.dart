import 'package:flutter_test/flutter_test.dart';
import 'package:salu_remote/core/link_health.dart';

/// A PC that keeps pushing snapshots while it cannot answer a single
/// command — the exact shape of the stalls Part B §1 measured (a
/// disconnected mapped drive blocking the PC for 10–30 seconds).
void main() {
  final DateTime t0 = DateTime(2026, 9, 30, 12);

  test('a late answer never makes the link dead', () {
    const LinkHealth health = LinkHealth();
    // The PC has not answered a ping in 20 seconds, but it is still talking.
    final DateTime now = t0.add(const Duration(seconds: 20));
    final DateTime lastInbound = t0.add(const Duration(seconds: 19, milliseconds: 750));
    expect(health.isDead(now, lastInbound), isFalse);
    expect(health.isBusy(now, t0), isTrue); // …and it is flagged busy, not dead.
  });

  test('silence is the only thing that kills a link', () {
    const LinkHealth health = LinkHealth();
    // 20 s of silence: still inside the grace a stalled PC needs.
    expect(health.isDead(t0.add(const Duration(seconds: 20)), t0), isFalse);
    // Past the limit: dead.
    expect(health.isDead(t0.add(const Duration(seconds: 26)), t0), isTrue);
  });

  test('a socket that has never received a frame is not judged yet', () {
    const LinkHealth health = LinkHealth();
    // The handshake clock owns that case, not the silence rule.
    expect(health.isDead(t0.add(const Duration(minutes: 5)), null), isFalse);
  });

  test('a PC that never stops pushing snapshots is never killed', () {
    const LinkHealth health = LinkHealth();
    DateTime lastInbound = t0;
    // 10 minutes of snapshots at 4/s with every ping going unanswered.
    for (int second = 1; second <= 600; second++) {
      final DateTime now = t0.add(Duration(seconds: second));
      lastInbound = now.subtract(const Duration(milliseconds: 100));
      expect(health.isDead(now, lastInbound), isFalse);
    }
  });

  test('the tolerances cover the worst PC stall Part B measured', () {
    const LinkHealth health = LinkHealth();
    // Part B §1: 10–30 s per disconnected mapped drive letter.
    expect(health.silenceLimit, greaterThanOrEqualTo(const Duration(seconds: 20)));
    expect(health.transportPing, greaterThanOrEqualTo(const Duration(seconds: 20)));
    // dart:io closes after two intervals (ping, then the pong deadline), so
    // the transport backstop alone must never be tighter than the stall.
    expect(health.transportPing * 2, greaterThan(const Duration(seconds: 30)));
  });

  test('a ping is only "busy" once it is genuinely late', () {
    const LinkHealth health = LinkHealth();
    expect(health.isBusy(t0.add(const Duration(seconds: 1)), t0), isFalse);
    expect(health.isBusy(t0.add(const Duration(seconds: 2)), t0), isTrue);
    expect(health.isBusy(t0, null), isFalse); // no ping outstanding
  });

  test('the busy hold lets go, so the read lanes come back', () {
    const LinkHealth health = LinkHealth();
    expect(health.isHolding(t0.add(const Duration(seconds: 4)), t0), isTrue);
    expect(health.isHolding(t0.add(const Duration(seconds: 6)), t0), isFalse);
    expect(health.isHolding(t0, null), isFalse);
  });

  test('the PC asking for room is not the link failing', () {
    const LinkHealth health = LinkHealth();
    for (final String code in <String>['busy', 'too_fast', 'timeout']) {
      expect(health.isBusyAnswer(code), isTrue, reason: code);
    }
    for (final String? code in <String?>[
      null,
      'nothing_playing',
      'no_web_media',
      'unknown_command',
      'offline',
    ]) {
      expect(health.isBusyAnswer(code), isFalse, reason: '$code');
    }
  });

  test('dial backoff is quick at first and calm later', () {
    const LinkHealth health = LinkHealth();
    expect(health.retryDelay(0), const Duration(seconds: 1));
    expect(health.retryDelay(1), const Duration(seconds: 1));
    expect(health.retryDelay(2), const Duration(seconds: 2));
    expect(health.retryDelay(500), const Duration(seconds: 12));
  });

  test('a busy PC gets more than one chance at the handshake', () {
    const LinkHealth health = LinkHealth();
    // Three tries, not one: the PC's own 5 s auth clock (§7.1.6) reaps a
    // socket it was too busy to finish, over and over, on a stalled machine.
    expect(health.authFailuresBeforePairing, greaterThan(1));
  });
}
