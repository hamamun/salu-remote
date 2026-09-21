import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:salu_remote/core/connect_failure.dart';

void main() {
  const String host = '192.168.0.12';
  const int port = 7258;

  ConnectFailure classify(Object error) =>
      ConnectFailure.classify(error, host: host, port: port);

  group('ConnectFailure.classify', () {
    test('a timeout points at the firewall first', () {
      final ConnectFailure f = classify(TimeoutException('x'));
      expect(f.code, 'unreachable');
      expect(f.message, contains('Firewall'));
      expect(f.message, contains('$host:$port'));
    });

    test('ECONNREFUSED means the PC is there but nothing listens on the port', () {
      final ConnectFailure f = classify(
        const SocketException('Connection refused', osError: OSError('Connection refused', 111)),
      );
      expect(f.code, 'unreachable');
      expect(f.message, contains('nothing is listening on port $port'));
      expect(f.message, contains('Remote switched on'));
    });

    test('a refusal is recognised by message when errno is missing', () {
      final ConnectFailure f = classify(
        const SocketException('Connection refused'),
      );
      expect(f.message, contains('nothing is listening'));
    });

    test('EHOSTUNREACH / ENETUNREACH mean the wrong network', () {
      for (final int errno in <int>[113, 101]) {
        final ConnectFailure f = classify(
          SocketException('No route to host', osError: OSError('No route to host', errno)),
        );
        expect(f.code, 'unreachable');
        expect(f.message, contains('same Wi-Fi'));
      }
    });

    test('a failed name lookup asks for the numeric address', () {
      final ConnectFailure f = ConnectFailure.classify(
        const SocketException(
          'Failed host lookup: \'desktop-abc\'',
          osError: OSError('No address associated with hostname', 7),
        ),
        host: 'desktop-abc',
        port: port,
      );
      expect(f.code, 'refused');
      expect(f.message, contains('numeric address'));
      expect(f.message, contains('desktop-abc'));
    });

    test('a WebSocketException means something else owns the port', () {
      final ConnectFailure f = classify(const WebSocketException("Connection to 'x' was not upgraded to websocket"));
      expect(f.code, 'refused');
      expect(f.message, contains('not SALU Remote'));
    });

    test('a TLS handshake error is a refusal', () {
      expect(classify(const HandshakeException('nope')).code, 'refused');
    });

    test('any other SocketException still names the host and the Wi-Fi rule', () {
      final ConnectFailure f = classify(
        const SocketException('Software caused connection abort', osError: OSError('abort', 103)),
      );
      expect(f.code, 'unreachable');
      expect(f.message, contains(host));
      expect(f.message, contains('same Wi-Fi'));
    });

    test('an unknown error falls back to a generic line', () {
      final ConnectFailure f = classify(StateError('weird'));
      expect(f.code, 'unreachable');
      expect(f.message, startsWith('Connection failed'));
    });
  });
}
