import 'package:flutter/services.dart';

/// Screen-awake while the app is open (D6 — "keep-screen-awake").
///
/// Deliberately **not** a plugin. A whole package for one window flag is a
/// liability on every SDK bump, and `android/APP_EDITS.md` shows the seven lines
/// of Kotlin in `MainActivity` that back this channel. On any other platform the
/// call is a no-op, so tests and desktop runs never trip over it.
class ScreenAwake {
  ScreenAwake._();

  static const MethodChannel _channel = MethodChannel('app.salu.remote/screen');
  static bool _on = false;

  static bool get isOn => _on;

  /// Called with `true` while the remote is on screen, `false` when the app goes
  /// to the background. Failure is swallowed: a phone that dims is an annoyance,
  /// a crash here would be a bug.
  static Future<void> set(bool on) async {
    if (_on == on) return;
    _on = on;
    try {
      await _channel.invokeMethod<bool>('keepAwake', on);
    } catch (_) {
      // No native side (unit test, desktop, an unedited MainActivity).
    }
  }
}
