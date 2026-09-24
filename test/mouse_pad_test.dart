import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salu_remote/ui/mouse_pad.dart';

/// The Tune tab in Web mode: **a trackpad, two scroll arrows and one line**
/// (`remote_apk_ui.md` §6.0).
///
/// None of this needs a PC. With no connection there is no `hello`, so neither
/// `web_mouse` nor `web_key` is promised and the pad sits in its honest degraded
/// state — the state most worth pinning down, along with the two numbers the
/// user asked for on 2026-09-24: the pad at **60%** of screen height (it was
/// 70%) and the arrow row's room *reserved* underneath it rather than taken out
/// of whatever the pad happened to leave behind.
void main() {
  // A mid-size phone, in logical pixels: 1080x2400 @ 3.0.
  const Size phone = Size(360, 800);

  Future<void> pumpPad(WidgetTester tester) async {
    tester.view.physicalSize = Size(phone.width * 3, phone.height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MousePad())));
  }

  /// The pad is the tab's first gesture detector; the two arrow seats follow it
  /// down the column.
  Finder pad() => find.byType(GestureDetector).first;

  Finder arrowSeat(String label) => find.descendant(
        of: find.byTooltip(label),
        matching: find.byType(GestureDetector),
      );

  testWidgets('the pad is 60% of screen height, full width',
      (WidgetTester tester) async {
    await pumpPad(tester);

    expect(MousePad.heightFactor, 0.60); // was 0.70 before the arrow row
    final Size size = tester.getSize(pad());
    expect(size.width, phone.width);
    expect(size.height, phone.height * MousePad.heightFactor); // 480 of 800
  });

  testWidgets('the two scroll seats sit under the pad, on screen',
      (WidgetTester tester) async {
    await pumpPad(tester);

    expect(find.byTooltip('Scroll up'), findsOneWidget);
    expect(find.byTooltip('Scroll down'), findsOneWidget);

    final Rect padBounds = tester.getRect(pad());
    final Rect up = tester.getRect(find.byTooltip('Scroll up'));
    final Rect down = tester.getRect(find.byTooltip('Scroll down'));
    expect(up.top, greaterThanOrEqualTo(padBounds.bottom));
    expect(down.top, up.top);
    expect(down.height, MousePad.arrowSize);
    // Pad + gap + row + gap + caption have to fit in the tab: it has no scroll
    // view, so anything pushed past the bottom edge would simply be lost.
    expect(down.bottom, lessThanOrEqualTo(phone.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no PC: the seats stay put, greyed, and the line says why',
      (WidgetTester tester) async {
    await pumpPad(tester);

    // No `hello`, so `web_key` is not promised: the seats are disabled rather
    // than hidden — a button that vanishes is a button the user keeps looking
    // for, and one that silently does nothing is worse than both.
    expect(tester.widget<GestureDetector>(arrowSeat('Scroll up')).onTap, isNull);
    expect(
      tester.widget<GestureDetector>(arrowSeat('Scroll down')).onTap,
      isNull,
    );

    expect(
      find.text('Mouse and scroll need an updated SALU on the PC'),
      findsOneWidget,
    );
    expect(find.text('Mouse'), findsNothing);
  });
}
