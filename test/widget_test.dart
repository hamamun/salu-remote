import 'package:flutter_test/flutter_test.dart';

import 'package:salu_remote/main.dart';

void main() {
  testWidgets(
      'first launch: header, the three tabs and the connect sheet',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SaluRemoteApp());
    // The post-frame callback opens the Connect sheet on a fresh device,
    // and the sheet's route needs a frame to build.
    await tester.pumpAndSettle();

    // The header before a first connection.
    expect(find.text('SALU Remote'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);

    // The connect sheet is up (first launch rule).
    expect(find.text('Connect to your PC'), findsOneWidget);
    expect(find.text('Scan the QR code'), findsOneWidget);
    expect(find.text('PC address'), findsOneWidget);
    expect(find.text('Pairing code (only the first time)'), findsOneWidget);

    // The three tabs, in order.
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('Tune'), findsOneWidget);

    // The Play tab shows the not-connected body with its own Connect door.
    expect(find.text('Not connected yet.'), findsOneWidget);
  });
}
