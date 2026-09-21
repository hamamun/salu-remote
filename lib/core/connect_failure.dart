import 'dart:async';
import 'dart:io';

/// Why `WebSocket.connect` failed, in words the person can act on.
///
/// The old client said *"The PC did not answer"* for every failure, which is
/// true and useless: a firewall drop, a wrong Wi-Fi, a closed port and a
/// wrong port all read the same, yet each has a different fix. The socket
/// layer actually tells them apart — this turns that into copy. Pure, so it
/// is tested without a network (`test/connect_failure_test.dart`).
class ConnectFailure {
  const ConnectFailure({required this.code, required this.message});

  /// `unreachable` retries with backoff; `refused` means the address is
  /// wrong and retrying will not help — the [SaluClient] treats both as
  /// retryable today, but the code is kept honest for the UI's sake.
  final String code;
  final String message;

  static ConnectFailure classify(Object error, {required String host, required int port}) {
    if (error is TimeoutException) {
      // Nothing came back at all — not even a refusal. On a home LAN that is
      // almost never "SALU is off" (a closed port refuses instantly); it is
      // a firewall silently dropping the packets, or two different networks.
      return ConnectFailure(
        code: 'unreachable',
        message: 'No answer from $host:$port. Windows Firewall is usually the '
            'cause: allow SALU on Private networks (the PC\'s Remote panel has '
            'an "Open firewall settings" button). Also check that the phone '
            'is on the same Wi-Fi as the PC, not mobile data.',
      );
    }
    if (error is HandshakeException) {
      // TLS was attempted against a plain ws:// port — cannot happen with the
      // URL the client builds, but a stray "wss://" would land here.
      return const ConnectFailure(
        code: 'refused',
        message: 'The PC refused this connection.',
      );
    }
    if (error is WebSocketException) {
      // TCP connected, but the upgrade did not happen: the PC answered with a
      // plain HTTP status (its own §7.1 rejects come back as 403), or the port
      // belongs to some other program entirely.
      return ConnectFailure(
        code: 'refused',
        message: 'Something answered at $host:$port, but it was not SALU '
            'Remote. Check the port in the PC\'s Remote panel.',
      );
    }
    if (error is SocketException) {
      final int? errno = error.osError?.errorCode;
      final String detail = (error.osError?.message ?? error.message).trim();
      final String lower = detail.toLowerCase();
      if (errno == 111 || lower.contains('refused')) {
        // ECONNREFUSED: the PC is reachable and actively said "nothing is
        // listening here" — Remote is off, SALU is closed, or the port differs.
        return ConnectFailure(
          code: 'unreachable',
          message: '$host answered, but nothing is listening on port $port. '
              'Is SALU running with Remote switched on, and is this the port '
              'shown in its Remote panel?',
        );
      }
      if (errno == 113 ||
          errno == 101 ||
          errno == 51 ||
          errno == 65 ||
          lower.contains('unreachable')) {
        // EHOSTUNREACH / ENETUNREACH: no route at all — wrong network.
        return ConnectFailure(
          code: 'unreachable',
          message: "Can't reach $host from this phone. Check that the phone is "
              'on the same Wi-Fi as the PC (not mobile data or a guest network).',
        );
      }
      if (errno == 7 || errno == -2 || lower.contains('failed host lookup')) {
        // A name, not an address, and the phone cannot resolve it. SALU's
        // panel shows the numeric address for exactly this reason.
        return ConnectFailure(
          code: 'refused',
          message: "This phone can't find \"$host\". Type the numeric address "
              'from the PC\'s Remote panel instead (for example 192.168.0.12).',
        );
      }
      return ConnectFailure(
        code: 'unreachable',
        message: "Can't reach $host${detail.isEmpty ? '' : ' ($detail)'}. "
            'Check that the phone is on the same Wi-Fi as the PC.',
      );
    }
    return ConnectFailure(code: 'unreachable', message: 'Connection failed: $error');
  }
}
