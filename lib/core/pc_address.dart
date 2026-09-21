/// What the user typed into the Connect sheet's address box, made sense of.
///
/// People paste whatever is in front of them: `192.168.0.12`,
/// `192.168.0.12:7258`, `ws://192.168.0.12:7258/`, `192.168.0.12 : 7258`,
/// `192.168.0.12 7258`. Every one of those means the same PC, so every one of
/// them must connect — a strict parser here looks exactly like a dead network
/// to the person holding the phone. Pure and tested
/// (`test/pc_address_test.dart`).
class PcAddress {
  const PcAddress({required this.host, required this.port});

  /// SALU's preferred port (`remote.md` §8.1), used when none was typed.
  static const int defaultPort = 7258;

  final String host;
  final int port;

  /// Returns `null` when nothing usable was typed: an empty box, a port that
  /// is not a number, or a host with a space in it.
  static PcAddress? parse(String raw) {
    String text = raw.trim();
    if (text.isEmpty) return null;
    // A pasted URL: drop the scheme and anything after the authority.
    text = text.replaceFirst(RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*://'), '');
    final int cut = text.indexOf(RegExp(r'[/?#]'));
    if (cut >= 0) text = text.substring(0, cut);
    text = text.trim();
    if (text.isEmpty) return null;

    String host = text;
    int port = defaultPort;
    final int colon = text.lastIndexOf(':');
    if (colon >= 0 && text.indexOf(':') == colon) {
      // `host:port`, tolerating spaces around the colon. A bare IPv6 literal
      // (several colons) is left alone — SALU listens on IPv4 only.
      host = text.substring(0, colon);
      final String portText = text.substring(colon + 1).trim();
      if (portText.isNotEmpty) {
        final int? parsed = int.tryParse(portText);
        if (parsed == null || parsed < 1 || parsed > 65535) return null;
        port = parsed;
      }
    } else if (colon < 0) {
      // `192.168.0.12 7258` — a space where the colon should be.
      final List<String> parts = text.split(RegExp(r'\s+'));
      if (parts.length == 2) {
        final int? parsed = int.tryParse(parts[1]);
        if (parsed == null || parsed < 1 || parsed > 65535) return null;
        host = parts[0];
        port = parsed;
      }
    }
    host = host.trim();
    if (host.isEmpty || RegExp(r'\s').hasMatch(host)) return null;
    return PcAddress(host: host, port: port);
  }

  @override
  String toString() => '$host:$port';
}
