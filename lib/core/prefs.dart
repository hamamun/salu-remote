import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Everything the phone remembers between launches.
///
/// Two kinds of fact live here and they are not the same thing:
///   * the **remembered PC** — address, port, device id and the token the PC
///     handed us (`remote.md` §7.1). Forgetting it is the only way to un-pair;
///   * **UI preferences** — Focus mode, the Play-screen checklist, collapsed
///     cards (`remote_apk_ui.md` §3). Losing these costs nothing.
///
/// The token is stored in plain `shared_preferences`. That is deliberate and
/// matches the threat model: the token is only useful to a device already on
/// this LAN, and the PC can forget it in one tap.
class RemotePrefs {
  RemotePrefs._();

  static final RemotePrefs instance = RemotePrefs._();

  static const String _kHost = 'pc_host';
  static const String _kPort = 'pc_port';
  static const String _kToken = 'pc_token';
  static const String _kDeviceId = 'device_id';
  static const String _kDeviceName = 'device_name';
  static const String _kServerName = 'server_name';
  static const String _kFocus = 'ui_focus_mode';
  static const String _kTab = 'ui_last_tab';
  static const String _kHidden = 'ui_hidden:';

  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    // Give the PC's Phones list something to show before the user names this
    // device themselves (Settings → This phone).
    if (!(_store?.containsKey(_kDeviceName) ?? false)) {
      await _store?.setString(_kDeviceName, 'My phone');
    }
  }

  SharedPreferences? get _store => _prefs;

  // ── the remembered PC ─────────────────────────────────────────────────────

  String? get host {
    final String? value = _store?.getString(_kHost);
    return value == null || value.isEmpty ? null : value;
  }

  int? get port {
    final int? value = _store?.getInt(_kPort);
    return value == null || value <= 0 ? null : value;
  }

  String? get token {
    final String? value = _store?.getString(_kToken);
    return value == null || value.isEmpty ? null : value;
  }

  String get serverName => _store?.getString(_kServerName) ?? 'Your PC';

  bool get isPaired => token != null && host != null && port != null;

  Future<void> rememberAddress(String host, int port) async {
    await _store?.setString(_kHost, host);
    await _store?.setInt(_kPort, port);
  }

  Future<void> rememberToken(String token, {String? serverName}) async {
    await _store?.setString(_kToken, token);
    if (serverName != null && serverName.isNotEmpty) {
      await _store?.setString(_kServerName, serverName);
    }
  }

  /// Drop only the token, keeping the address: the PC forgot this phone
  /// (`bad_token`), or the user typed a fresh pairing code for the same PC.
  /// Either way the next `auth` must carry the code, not a dead token.
  Future<void> forgetToken() async {
    await _store?.remove(_kToken);
  }

  /// Forget the PC. The token dies here and the PC still believes it is paired —
  /// but its next `auth` with that token fails `bad_token` and it re-pairs.
  Future<void> forgetPc() async {
    await _store?.remove(_kToken);
    await _store?.remove(_kHost);
    await _store?.remove(_kPort);
    await _store?.remove(_kServerName);
  }

  // ── this phone's identity, sent to the PC in `auth` ───────────────────────

  String get deviceId {
    final String? existing = _store?.getString(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final String fresh = _randomId();
    _store?.setString(_kDeviceId, fresh);
    return fresh;
  }

  String get deviceName => _store?.getString(_kDeviceName) ?? 'My phone';

  Future<void> setDeviceName(String name) async {
    final String trimmed = name.trim();
    await _store?.setString(_kDeviceName, trimmed.isEmpty ? 'My phone' : trimmed);
  }

  static String _randomId() {
    const String alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final Random random = Random.secure();
    return List<String>.generate(
      10,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  // ── UI preferences ────────────────────────────────────────────────────────

  /// Focus mode is remembered per device (`remote_apk_ui.md` §3).
  bool get focusMode => _store?.getBool(_kFocus) ?? false;

  Future<void> setFocusMode(bool value) async {
    await _store?.setBool(_kFocus, value);
  }

  int get lastTab => _store?.getInt(_kTab) ?? 0;

  Future<void> setLastTab(int index) async {
    await _store?.setInt(_kTab, index);
  }

  /// The Play-screen checklist. Default: everything visible — ship complete,
  /// let people subtract (`remote_apk_ui.md` §3).
  bool isShown(String key) => _store?.getBool('$_kHidden$key') ?? true;

  Future<void> setShown(String key, bool value) async {
    await _store?.setBool('$_kHidden$key', value);
  }

  bool isCollapsed(String key) => _store?.getBool('$_kHidden collapsed:$key') ?? false;

  Future<void> setCollapsed(String key, bool value) async {
    await _store?.setBool('$_kHidden collapsed:$key', value);
  }
}

/// The keys the Play-screen checklist understands (`remote_apk_ui.md` §3).
abstract final class PlaySection {
  static const String volume = 'volume';
  static const String modePill = 'mode_pill';
  static const String chips = 'chips';
  static const String queue = 'queue';
  static const String miniStrip = 'mini_strip';
  static const String tuneTab = 'tune_tab';
  static const String streamsSegment = 'streams_segment';
  static const String subtitlesCard = 'subtitles_card';
  static const String speedChips = 'speed_chips';

  static const List<String> all = <String>[
    volume,
    modePill,
    chips,
    queue,
    miniStrip,
    subtitlesCard,
    speedChips,
    tuneTab,
    streamsSegment,
  ];
}
