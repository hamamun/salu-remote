import 'package:flutter_test/flutter_test.dart';

import 'package:salu_remote/core/deep_link.dart';

void main() {
  group('DeepLink.parse', () {
    test('parses a full pairing link (remote.md §10.2)', () {
      final PairLink? link = DeepLink.parse(
        'salu://pair?v=1&n=DESKTOP-ABC&h=192.168.0.12&p=7258&c=7K4MQP2X',
      );
      expect(link, isNotNull);
      expect(link!.host, '192.168.0.12');
      expect(link.port, 7258);
      expect(link.code, '7K4MQP2X');
      expect(link.name, 'DESKTOP-ABC');
      expect(link.address, '192.168.0.12:7258');
    });

    test('normalizes a dashed, lower-case code to the auth form', () {
      final PairLink? link =
          DeepLink.parse('salu://pair?h=10.0.0.5&c=7k4m-qp2x');
      expect(link, isNotNull);
      expect(link!.code, '7K4MQP2X');
      expect(link.port, 7258);
      expect(link.name, isNull);
    });

    test('honours a custom port', () {
      final PairLink? link = DeepLink.parse('salu://pair?h=10.0.0.5&p=7261&c=ABCD1234');
      expect(link, isNotNull);
      expect(link!.port, 7261);
    });

    test('rejects a non-salu scheme', () {
      expect(DeepLink.parse('https://pair?h=1.2.3.4&c=ABCD1234'), isNull);
      expect(DeepLink.parse('salu://other?h=1.2.3.4&c=ABCD1234'), isNull);
    });

    test('rejects a missing host or code', () {
      expect(DeepLink.parse('salu://pair?c=ABCD1234'), isNull);
      expect(DeepLink.parse('salu://pair?h=1.2.3.4'), isNull);
    });

    test('rejects null and unparseable input', () {
      expect(DeepLink.parse(null), isNull);
      expect(DeepLink.parse(''), isNull);
      expect(DeepLink.parse('not a uri at all'), isNull);
    });
  });
}
