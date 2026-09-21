import 'dart:async';

import 'package:flutter/material.dart';

import 'core/client.dart';
import 'core/deep_link.dart';
import 'core/prefs.dart';
import 'ui/root.dart';
import 'ui/theme.dart';

/// SALU Remote — the phone half of SALU (`remote.md`, `remote_apk_ui.md`).
///
/// **Where the app is right now.** The full v2 scope: QR pairing (in-app
/// camera scan plus the `salu://pair` deep link), and the three-tab
/// interface — Play (player + web bodies), Browse (files + streams),
/// Tune (equalizer + subtitles + audio, D-pad in web mode) — with the
/// focus mode, the Play-screen checklist and the connect sheet.
/// Everything under `lib/core/` and `lib/protocol/` keeps its original
/// shape: one WebSocket client, tolerant models, the shared protocol.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RemotePrefs.instance.load();
  // Before the first frame: a QR that opened the app cold must not be lost
  // to the engine race.
  await DeepLink.init();
  runApp(const SaluRemoteApp());
  // After the first frame, never before it: a cold start must not wait on a
  // socket (`remote.md` §11).
  unawaited(SaluClient.instance.autoConnect());
}

class SaluRemoteApp extends StatelessWidget {
  const SaluRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SALU Remote',
      debugShowCheckedModeBanner: false,
      theme: SaluTheme.build(),
      home: const RootPage(),
    );
  }
}
