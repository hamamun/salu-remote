import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salu_remote/core/client.dart';
import 'package:salu_remote/core/models.dart';
import 'package:salu_remote/core/prefs.dart';
import 'package:salu_remote/main.dart';

/// The menu stays in the app bar in Player, Web and Focus mode; unlike the
/// playback controls, these actions never depend on the current media.
void main() {
  final SaluClient client = SaluClient.instance;

  Finder menuItem(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((Widget widget) => widget is PopupMenuItem),
      );

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String label) =>
      tester.widget<PopupMenuItem<dynamic>>(menuItem(label)).enabled;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pc_host': '192.168.0.10',
      'pc_port': 7258,
      'pc_token': 'remembered-token',
    });
    await RemotePrefs.instance.load();
  });

  setUp(() async {
    await client.disconnect();
    await RemotePrefs.instance.setLastTab(0);
    await RemotePrefs.instance.setFocusMode(false);
    client.server.value = null;
    client.snapshot.value = null;
  });

  test('PC power is not a web diagnostics feature', () {
    expect(RemoteFeature.all, isNot(contains(RemoteFeature.pcPower)));
  });

  testWidgets('offline: both actions are shown but disabled; existing menu remains',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SaluRemoteApp());
    await openMenu(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Forget this PC'), findsOneWidget);
    expect(find.text('Sleep PC'), findsOneWidget);
    expect(find.text('Shut down PC'), findsOneWidget);
    expect(enabled(tester, 'Sleep PC'), isFalse);
    expect(enabled(tester, 'Shut down PC'), isFalse);
  });

  testWidgets('a stale power feature cannot be used after disconnect',
      (WidgetTester tester) async {
    client.server.value = const ServerInfo(
      name: 'Desk PC',
      version: '1',
      features: <String>[RemoteFeature.pcPower],
    );
    await tester.pumpWidget(const SaluRemoteApp());
    await openMenu(tester);

    expect(enabled(tester, 'Sleep PC'), isFalse);
    expect(enabled(tester, 'Shut down PC'), isFalse);
  });

  testWidgets('an old PC never exposes a working power action',
      (WidgetTester tester) async {
    client.server.value = const ServerInfo(name: 'Desk PC', version: '1');
    client.link.value = LinkState.online;
    await tester.pumpWidget(const SaluRemoteApp());
    await openMenu(tester);

    expect(enabled(tester, 'Sleep PC'), isFalse);
    expect(enabled(tester, 'Shut down PC'), isFalse);
    expect(find.text('Power controls need an updated SALU on the PC.'),
        findsOneWidget);
  });

  testWidgets('a supported PC requires confirmation for each action',
      (WidgetTester tester) async {
    client.server.value = const ServerInfo(
      name: 'Desk PC',
      version: '1',
      features: <String>[RemoteFeature.pcPower],
    );
    client.link.value = LinkState.online;
    await tester.pumpWidget(const SaluRemoteApp());

    await openMenu(tester);
    expect(enabled(tester, 'Sleep PC'), isTrue);
    expect(enabled(tester, 'Shut down PC'), isTrue);
    await tester.tap(find.text('Sleep PC'));
    await tester.pumpAndSettle();
    expect(find.text('Put Desk PC to sleep?'), findsOneWidget);
    expect(find.textContaining('reconnect when the PC wakes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    await openMenu(tester);
    await tester.tap(find.text('Shut down PC'));
    await tester.pumpAndSettle();
    expect(find.text('Shut down Desk PC?'), findsOneWidget);
    expect(find.textContaining('Save your work on the PC first'), findsOneWidget);
    expect(find.textContaining('cannot be turned back on from this remote'),
        findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a different PC during confirmation cannot receive the command',
      (WidgetTester tester) async {
    client.server.value = const ServerInfo(
      name: 'Desk PC',
      version: '1',
      features: <String>[RemoteFeature.pcPower],
    );
    client.link.value = LinkState.online;
    await tester.pumpWidget(const SaluRemoteApp());
    await openMenu(tester);
    await tester.tap(find.text('Sleep PC'));
    await tester.pumpAndSettle();

    // The dialog still names Desk PC, but `hello` now belongs to another PC.
    client.server.value = const ServerInfo(
      name: 'Other PC',
      version: '1',
      features: <String>[RemoteFeature.pcPower],
    );
    await tester.tap(find.text('Sleep PC'));
    await tester.pumpAndSettle();
    expect(find.text('The PC connection changed. Open the menu and try again.'),
        findsOneWidget);
    expect(find.textContaining('did not confirm the request'), findsNothing);
  });

  testWidgets('the same menu is available in Web mode',
      (WidgetTester tester) async {
    client.server.value = const ServerInfo(
      name: 'Desk PC',
      version: '1',
      features: <String>[RemoteFeature.pcPower],
    );
    client.snapshot.value = SaluSnapshot.from(<String, Object?>{
      'rev': 1,
      'mode': 'web',
    });
    client.link.value = LinkState.online;
    await tester.pumpWidget(const SaluRemoteApp());
    await openMenu(tester);
    expect(enabled(tester, 'Sleep PC'), isTrue);
    expect(enabled(tester, 'Shut down PC'), isTrue);
  });

  testWidgets('the power menu works in Focus mode without a new Play card',
      (WidgetTester tester) async {
    client.server.value = const ServerInfo(
      name: 'Desk PC',
      version: '1',
      features: <String>[RemoteFeature.pcPower],
    );
    client.link.value = LinkState.online;
    await RemotePrefs.instance.setFocusMode(true);
    await tester.pumpWidget(const SaluRemoteApp());
    expect(find.text('Sleep PC'), findsNothing);
    await openMenu(tester);
    expect(enabled(tester, 'Sleep PC'), isTrue);
    expect(enabled(tester, 'Shut down PC'), isTrue);
  });
}
