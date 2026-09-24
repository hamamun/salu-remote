import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salu_remote/core/client.dart';
import 'package:salu_remote/core/models.dart';
import 'package:salu_remote/core/prefs.dart';
import 'package:salu_remote/protocol/remote_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('power requests use the authenticated socket and two distinct verbs',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pc_token': 'remembered-token',
    });
    await RemotePrefs.instance.load();

    // flutter_test may install an HttpClient override that returns HTTP 400
    // for every request. This test only talks to its own loopback PC fixture.
    final HttpOverrides? originalHttpOverrides = HttpOverrides.global;
    HttpOverrides.global = null;
    final HttpServer pc = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
    pc.listen((HttpRequest request) async {
      final WebSocket socket = await WebSocketTransformer.upgrade(request);
      socket.add(RemoteProtocol.encode(RemoteProtocol.hello(
        name: 'Desk PC',
        version: '1',
        state: <String, Object?>{'rev': 1, 'mode': 'player'},
        features: const <String>[RemoteFeature.pcPower],
      )));
      socket.listen((Object? raw) {
        if (raw is! String) return;
        final Map<String, Object?> frame = RemoteProtocol.decode(raw);
        if (frame['type'] == 'auth') {
          socket.add(RemoteProtocol.encode(RemoteProtocol.authOk(
            id: 1,
            deviceId: RemotePrefs.instance.deviceId,
            token: 'remembered-token',
            serverName: 'Desk PC',
            version: '1',
          )));
        } else if (frame['type'] == 'cmd' && frame['verb'] != 'ping') {
          commands.add(frame);
          socket.add(RemoteProtocol.encode(
            RemoteProtocol.ack((frame['id'] as num).toInt()),
          ));
        }
      });
    });

    final SaluClient client = SaluClient.instance;
    final Completer<void> online = Completer<void>();
    void onLink() {
      if (client.isOnline && !online.isCompleted) online.complete();
    }
    client.link.addListener(onLink);
    try {
      await client.connect(host: '127.0.0.1', port: pc.port);
      await online.future.timeout(const Duration(seconds: 5));
      expect(client.supportsPcPower, isTrue);
      expect((await client.sleepPc()).ok, isTrue);
      expect((await client.shutDownPc()).ok, isTrue);
      expect(commands.map((Map<String, Object?> cmd) => cmd['verb']),
          <String>['pc_sleep', 'pc_shutdown']);
      expect(commands.every((Map<String, Object?> cmd) => !cmd.containsKey('args')),
          isTrue);
    } finally {
      client.link.removeListener(onLink);
      await client.disconnect();
      await pc.close(force: true);
      HttpOverrides.global = originalHttpOverrides;
    }
  });
}
