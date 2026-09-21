import 'package:flutter_test/flutter_test.dart';

import 'package:salu_remote/core/pc_address.dart';

void main() {
  group('PcAddress.parse', () {
    test('host:port, the form the PC panel shows', () {
      final PcAddress? a = PcAddress.parse('192.168.0.12:7258');
      expect(a, isNotNull);
      expect(a!.host, '192.168.0.12');
      expect(a.port, 7258);
      expect(a.toString(), '192.168.0.12:7258');
    });

    test('a bare host takes the default port', () {
      final PcAddress? a = PcAddress.parse('192.168.0.12');
      expect(a!.host, '192.168.0.12');
      expect(a.port, PcAddress.defaultPort);
    });

    test('a non-default port is kept', () {
      expect(PcAddress.parse('10.0.0.5:7261')!.port, 7261);
    });

    test('tolerates surrounding whitespace and spaces around the colon', () {
      final PcAddress? a = PcAddress.parse('  192.168.0.12 : 7258  ');
      expect(a!.host, '192.168.0.12');
      expect(a.port, 7258);
    });

    test('a space instead of a colon still works', () {
      final PcAddress? a = PcAddress.parse('192.168.0.12 7258');
      expect(a!.host, '192.168.0.12');
      expect(a.port, 7258);
    });

    test('a pasted ws:// or http:// URL is stripped to its authority', () {
      expect(PcAddress.parse('ws://192.168.0.12:7258/')!.toString(), '192.168.0.12:7258');
      expect(PcAddress.parse('http://192.168.0.12:7258')!.toString(), '192.168.0.12:7258');
      expect(PcAddress.parse('ws://192.168.0.12/')!.port, PcAddress.defaultPort);
    });

    test('a trailing colon means the default port', () {
      expect(PcAddress.parse('192.168.0.12:')!.port, PcAddress.defaultPort);
    });

    test('hostnames are allowed (the OS resolves them)', () {
      final PcAddress? a = PcAddress.parse('DESKTOP-ABC:7258');
      expect(a!.host, 'DESKTOP-ABC');
      expect(a.port, 7258);
    });

    test('rejects an empty box', () {
      expect(PcAddress.parse(''), isNull);
      expect(PcAddress.parse('   '), isNull);
      expect(PcAddress.parse('ws://'), isNull);
    });

    test('rejects a port that is not a number or out of range', () {
      expect(PcAddress.parse('192.168.0.12:abc'), isNull);
      expect(PcAddress.parse('192.168.0.12:0'), isNull);
      expect(PcAddress.parse('192.168.0.12:70000'), isNull);
    });

    test('rejects a host with inner whitespace', () {
      expect(PcAddress.parse('192.168 .0.12:7258'), isNull);
      expect(PcAddress.parse('one two three'), isNull);
    });
  });
}
