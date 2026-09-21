import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One parsed `salu://pair` link — everything the QR code carries
/// (`remote.md` §10.2: `v` protocol · `n` PC name · `h` host · `p` port ·
/// `c` pairing code).
class PairLink {
  const PairLink({
    required this.host,
    required this.port,
    required this.code,
    this.name,
  });

  final String host;
  final int port;
  final String code;
  final String? name;

  /// What the Connect sheet pre-fills into the address field.
  String get address => '$host:$port';
}

/// The door from the outside world: a `salu://pair` URI handed to the app,
/// either by the Android system (the phone camera scanned the QR and chose
/// "Open with SALU Remote") or by the in-app scanner (`lib/ui/qr_scan.dart`).
///
/// Both sources land in the same [pending] notifier, so the UI never has to
/// know how the link arrived. The URI shape is owned by the PC's QR panel;
/// parsing is pure and tested (`test/deep_link_test.dart`).
abstract final class DeepLink {
  static const MethodChannel _channel = MethodChannel('app.salu.remote/deep_link');

  /// Set once per received link, cleared by the UI after it has been used.
  /// `null` means "nothing is waiting".
  static final ValueNotifier<PairLink?> pending = ValueNotifier<PairLink?>(null);

  static bool _initialized = false;

  /// Called once from `main()` before the first frame. Registers the push
  /// handler and asks the platform for a link that arrived before Dart was
  /// ready (cold start from a QR). Without a native side (tests, desktop)
  /// everything is a silent no-op.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onLink') {
        _deliver(call.arguments is String ? call.arguments as String : null);
      }
      return null;
    });
    try {
      final String? initial = await _channel.invokeMethod<String>('getInitial');
      _deliver(initial);
    } on MissingPluginException {
      // No MainActivity channel (unit test / desktop run) — the in-app
      // scanner still works, so nothing to do.
    } catch (_) {
      // A channel that throws for any other reason must not take the app
      // down before its first frame.
    }
  }

  static void _deliver(String? raw) {
    final PairLink? link = parse(raw);
    if (link != null) pending.value = link;
  }

  /// Parses `salu://pair?v=1&n=DESKTOP-ABC&h=192.168.0.12&p=7258&c=7K4MQP2X`.
  ///
  /// Returns `null` for anything that is not a SALU pairing link (a different
  /// scheme, a missing host, an empty code) — the caller shows the manual
  /// entry instead of a half-pairing.
  static PairLink? parse(String? raw) {
    if (raw == null) return null;
    final Uri? uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'salu' || uri.host != 'pair') return null;
    final String host = uri.queryParameters['h'] ?? '';
    if (host.isEmpty) return null;
    // The PC displays the code dashed (`7K4M-QP2X`); a QR reader and a human
    // may each deliver it differently, so strip to the same canonical form
    // the `auth` frame uses (`remote.md` §7.1 — Crockford-style, upper case).
    final String code =
        (uri.queryParameters['c'] ?? '').toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    if (code.isEmpty) return null;
    final int port = int.tryParse(uri.queryParameters['p'] ?? '') ?? 7258;
    final String? name = uri.queryParameters['n'];
    return PairLink(
      host: host,
      port: port,
      code: code,
      name: (name == null || name.isEmpty) ? null : name,
    );
  }
}
