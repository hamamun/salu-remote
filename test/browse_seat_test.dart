import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salu_remote/core/client.dart';
import 'package:salu_remote/core/models.dart';
import 'package:salu_remote/core/prefs.dart';
import 'package:salu_remote/main.dart';
import 'package:salu_remote/ui/theme.dart';

/// **Browse is Player-only** (`remote_apk_ui.md` §2.1): the seat greys out in
/// Web mode rather than vanishing, and tapping it says why.
///
/// The greying used to be a one-way door (user, 2026-09-24: *"salu switched to
/// player but browse button still remain grayed out … its telling pc player is
/// in web mode which is not right"*). `_bottomBar` read
/// `_client.snapshot.value` while `_RootPageState.build` ran, so the bar only
/// ever refreshed when something *else* rebuilt the page — a tab change, the
/// focus toggle, the checklist. Entering Web mode while Browse was up did
/// rebuild it, because the §2.1 bounce to Play calls `setState`, so the seat
/// greyed and looked correct. Leaving Web mode from the Play tab rebuilt
/// nothing at all: the body cross-faded back to the player, the PC was in
/// Player mode, and the seat stayed grey with the Web-mode sentence on it.
///
/// So these tests drive the one thing the PC drives — the snapshot's `mode` —
/// and watch the seat, in both directions and from a tab that never bounces.
/// Nothing here needs a socket: the mode arrives through the same
/// `ValueNotifier` a real push lands in, and the link is left idle on purpose
/// (an online link would start the web body's 1/s poll, which is another
/// test's business).
void main() {
  /// The sentence the greyed seat owes the user. Kept in step with the copy in
  /// `lib/ui/root.dart`; if the wording changes, this has to change with it.
  const String reason =
      'Files and Streams are Player-only — the PC is in Web mode.';

  /// A snapshot carrying only what the seat reads. Everything else in
  /// `SaluSnapshot.from` falls back to its own tolerant default, exactly as it
  /// does for a half-populated frame from an older PC.
  SaluSnapshot snapshot(String mode, int rev) =>
      SaluSnapshot.from(<String, Object?>{'rev': rev, 'mode': mode});

  /// The Browse seat's own icon colour: `statusUnknown` is the grey of a
  /// disabled seat, `iconIdle` an ordinary one, `accent` the tab you are on.
  Color browseColour(WidgetTester tester) {
    final Finder seat = find
        .ancestor(of: find.text('Browse'), matching: find.byType(InkWell))
        .first;
    final Icon icon = tester.widget<Icon>(
      find.descendant(of: seat, matching: find.byType(Icon)),
    );
    return icon.color!;
  }

  /// Paired, so the first frame does not raise the Connect sheet over the bar
  /// (`remote_apk_ui.md` §2.1), and on the Play tab, so no bounce can be what
  /// repaints it.
  Future<void> pumpRoot(WidgetTester tester, SaluSnapshot first) async {
    SaluClient.instance.snapshot.value = first;
    await tester.pumpWidget(const SaluRemoteApp());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pc_host': '192.168.0.10',
      'pc_port': 8765,
      'pc_token': 'a-remembered-token',
    });
    await RemotePrefs.instance.load();
  });

  setUp(() async {
    // Tapping a seat in one test remembers it as the last tab; the next test
    // has to start on Play for the same reason the pump does.
    await RemotePrefs.instance.setLastTab(0);
    SaluClient.instance.snapshot.value = null;
  });

  testWidgets('Web → Player: the seat un-greys with the snapshot, not with a '
      'tab change', (WidgetTester tester) async {
    // Web mode, Play tab up. Nothing bounces, nothing else rebuilds the root —
    // this is the frame where the old bar simply did not hear the news.
    await pumpRoot(tester, snapshot('web', 1));
    expect(browseColour(tester), AppColors.statusUnknown);

    // The PC comes back to Player (the mode pill's Player seat, or any
    // transport command — D8 pulls SALU out of the browser either way).
    SaluClient.instance.snapshot.value = snapshot('player', 2);
    await tester.pump();

    // The regression: this stayed `statusUnknown` until some unrelated
    // `setState` happened to repaint the bar.
    expect(browseColour(tester), AppColors.iconIdle);
  });

  testWidgets('Player → Web → Player: the seat follows in both directions',
      (WidgetTester tester) async {
    await pumpRoot(tester, snapshot('player', 1));
    expect(browseColour(tester), AppColors.iconIdle);

    SaluClient.instance.snapshot.value = snapshot('web', 2);
    await tester.pump();
    expect(browseColour(tester), AppColors.statusUnknown);

    SaluClient.instance.snapshot.value = snapshot('player', 3);
    await tester.pump();
    expect(browseColour(tester), AppColors.iconIdle);
  });

  testWidgets('the reason on tap is true when it is shown, and the seat opens '
      'once it is not', (WidgetTester tester) async {
    await pumpRoot(tester, snapshot('web', 1));

    // Greyed, and honest about why.
    await tester.tap(find.text('Browse'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(reason), findsOneWidget);
    expect(browseColour(tester), AppColors.statusUnknown);

    // The PC comes back to Player. Let the first snackbar leave on its own
    // clock (4 s up, then its exit animation) so the next tap is a clean one.
    SaluClient.instance.snapshot.value = snapshot('player', 2);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(reason), findsNothing);

    // The same tap now does the thing a seat is for: it opens Browse. The
    // accent is the proof — `_bottomItem` colours only the tab you are on.
    await tester.tap(find.text('Browse'));
    await tester.pump();
    expect(browseColour(tester), AppColors.accent);
    expect(find.text(reason), findsNothing);
  });
}
