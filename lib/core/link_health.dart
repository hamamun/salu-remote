import '../protocol/remote_protocol.dart';

/// The phone's liveness policy, in one pure place
/// (`salu_remote.md` Part 7 — connection reliability, round two).
///
/// Round one (Part E) fixed *who declares death*: the transport, not a
/// command that came back late. It left two timings that are still wrong for
/// the user's PC, and both are about a **busy** PC rather than a dead one:
///
///   * dart:io's `WebSocket.pingInterval` is a *deadline*, not a cadence.
///     Dart sends a ping after `pingInterval` and then closes the socket with
///     `1001 going away` if the peer's pong is more than another
///     `pingInterval` late (`sdk/lib/_http/websocket_impl.dart`). Ten seconds
///     is inside the window a PC that is blocked for tens of seconds
///     (Part B §1 measured 10–30 s per disconnected mapped drive) simply
///     cannot meet — so the phone tore down a link that was only slow.
///   * A pause in *answers* is not a pause in *frames*. While the PC pushes
///     snapshots it is demonstrably alive, however late its `ack`s are.
///
/// So the rule this class encodes, in one sentence each:
///
///   * **Dead = silence.** Not one frame of *any* kind — `state`, `ack`,
///     `pong`, even an `error` — for [silenceLimit].
///   * **Busy = slow answers.** A `ping` past [busyAfter], or a command the
///     PC refused with `busy` / `too_fast` / `timeout`. Nothing is ever
///     killed for this; the read lanes simply stop volunteering work.
///
/// Everything here is a pure function of clocks and counters, so the policy
/// is unit-testable without a socket (`test/link_health_test.dart`).
class LinkHealth {
  const LinkHealth({
    this.probeInterval = const Duration(seconds: 5),
    this.transportPing = const Duration(seconds: 25),
    this.silenceLimit = const Duration(seconds: 25),
    this.busyAfter = const Duration(seconds: 2),
    this.busyHold = const Duration(seconds: 5),
    this.authFailuresBeforePairing = 3,
  });

  /// How often the phone sends the app-level `ping` verb. The PC answers it
  /// inline on the socket path (Part E1), so this is both the latency
  /// readout and the proof of life while nothing is playing.
  final Duration probeInterval;

  /// dart:io's `pingInterval`. Deliberately generous: it is the backstop for
  /// a link the PC can no longer answer *at all*, and [silenceLimit] below
  /// notices such a link sooner anyway. A busy PC must never hit it.
  final Duration transportPing;

  /// How long the PC may be completely silent before the link is declared
  /// dead. Any inbound frame resets the clock.
  ///
  /// Twenty-five seconds is a deliberate compromise: it is a little slower
  /// to admit a dead link than the old rule (dart:io's 10-second
  /// `pingInterval` closed the socket at ~20 s) and a lot more forgiving of
  /// the 10–30 s stalls Part B §1 measured on this PC. A PC that is still
  /// pushing snapshots never reaches it at all.
  final Duration silenceLimit;

  /// A `ping` still unanswered after this means "the PC is busy" — never
  /// "the link is dead".
  final Duration busyAfter;

  /// How long [SaluClient.busy] stays on after the last slow or missing
  /// answer, so the read lanes give the PC one breath instead of stampeding
  /// the moment a single reply lands.
  final Duration busyHold;

  /// How many consecutive *retryable* handshake failures before the phone
  /// stops and asks the user to pair again. A credential refusal
  /// (`bad_code`, `bad_token`, …) never gets this grace — it stops on the
  /// first one.
  final int authFailuresBeforePairing;

  /// Backoff between dials: quick at first, calm once the PC has been gone
  /// a while. A PC that comes back is picked up within a second or two; a
  /// phone that has been off the network for an hour must not hammer it.
  Duration retryDelay(int attempt) {
    const List<int> seconds = <int>[1, 1, 2, 3, 5, 8, 12];
    return Duration(
      seconds: seconds[attempt < seconds.length ? attempt : seconds.length - 1],
    );
  }

  /// True when the link has gone quiet long enough to be dead.
  ///
  /// `null` (no frame has ever arrived on this socket) is **not** dead —
  /// that is the handshake clock's business, not this rule's.
  bool isDead(DateTime now, DateTime? lastInboundAt) {
    if (lastInboundAt == null) return false;
    return now.difference(lastInboundAt) >= silenceLimit;
  }

  /// True while an unanswered `ping` is old enough to mean "busy".
  bool isBusy(DateTime now, DateTime? pingSentAt) {
    if (pingSentAt == null) return false;
    return now.difference(pingSentAt) >= busyAfter;
  }

  /// True while the PC still has to be given room — the hold has not run
  /// out since the last slow or missing answer.
  bool isHolding(DateTime now, DateTime? lastBusyAt) {
    if (lastBusyAt == null) return false;
    return now.difference(lastBusyAt) < busyHold;
  }

  /// Does this command answer mean "the PC cannot keep up right now"?
  ///
  /// `timeout` belongs here as well as the PC's own `busy` (its 3-second
  /// handler guard — Part 3 §17.8) and `too_fast` (its 30 commands/second
  /// budget — §7.3): all three are the PC asking for room, not a link that
  /// has gone away.
  bool isBusyAnswer(String? code) =>
      code == RemoteErrorCode.busy ||
      code == RemoteErrorCode.tooFast ||
      code == 'timeout';

  /// The floor between two voluntary reads on a healthy link. Ten reads a
  /// second (the old pace) spent a third of the PC's own command budget on
  /// work nobody was waiting for, and starved the commands the thumb was
  /// actually issuing.
  Duration get readPace => const Duration(milliseconds: 200);
}
