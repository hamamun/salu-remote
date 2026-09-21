import 'package:flutter_test/flutter_test.dart';

import 'package:salu_remote/main.dart';

void main() {
  testWidgets('shows the connection screen before pairing',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SaluRemoteApp());

    expect(find.text('SALU Remote'), findsOneWidget);
    expect(find.text('Connect to your PC'), findsOneWidget);
    expect(find.text('PC address'), findsOneWidget);
    expect(find.text('Pairing code (only the first time)'), findsOneWidget);
  });
}
