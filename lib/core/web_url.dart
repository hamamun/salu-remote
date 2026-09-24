/// The Web body's own address arithmetic — two pure functions, no Flutter, so
/// both are testable on their own (`test/web_url_test.dart`).
///
/// Why they exist (2026-09-24):
///
/// * **The URL box sent the text exactly as it was typed.** "youtube.com" went
///   out with no scheme, the PC's `web_tab_new {url}` could not resolve it, and
///   the user got a **blank tab** — the reported bug. A typed address that names
///   a host is given `https://` here, once, before it reaches the wire. Text
///   that is not obviously an address is left alone: the PC classifies it
///   (`open_url`'s own rules), and guessing twice is how a search phrase becomes
///   a broken page.
/// * **The Home button has an older-PC fallback.** A PC that does not answer
///   `browser_nav {action:"home"}` still gets sent to the site's own front page
///   — which is the origin of whatever is loaded — instead of nothing.
library;

/// The URL box's text, ready for the wire: trimmed, and with a scheme added
/// when the text names a host and nothing else. `null` when there is nothing
/// to open.
String? webAddress(String input) {
  final String text = input.trim();
  if (text.isEmpty) return null;
  if (_hasScheme(text)) return text;
  return _looksLikeHost(text) ? 'https://$text' : text;
}

/// The front page of whatever site is loaded: scheme, host and port of [url],
/// with no path, query or fragment. `null` when there is no site to go home to
/// (an empty URL, an `about:` page, a local file).
String? siteHome(String? url) {
  final String text = url?.trim() ?? '';
  if (text.isEmpty) return null;
  final Uri? parsed = Uri.tryParse(text);
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) return null;
  final String scheme = parsed.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  final String port = parsed.hasPort ? ':${parsed.port}' : '';
  return '$scheme://${parsed.host}$port';
}

/// The schemes that are complete without `//` — everything else must show it
/// before the colon is read as a scheme. `localhost:3000` and `host.com:8080`
/// are hosts with ports; `about:blank` is not a host called `about`.
const Set<String> _schemeOnly = <String>{
  'about',
  'mailto',
  'data',
  'tel',
  'javascript',
  'chrome',
  'blob',
  'file',
  'view-source',
};

/// `https://…`, `about:blank`, `mailto:…` — already addressed.
bool _hasScheme(String text) {
  final int colon = text.indexOf(':');
  if (colon <= 0) return false;
  final String head = text.substring(0, colon);
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*$').hasMatch(head)) return false;
  if (text.startsWith('//', colon + 1)) return true;
  return _schemeOnly.contains(head.toLowerCase());
}

/// True for the text a browser would treat as a bare host: `youtube.com`,
/// `www.example.org/path`, `192.168.1.10:8080`, `localhost:3000`.
bool _looksLikeHost(String text) {
  if (text.contains(RegExp(r'\s'))) return false;
  final String host = text.split('/').first.split(':').first;
  if (host.isEmpty) return false;
  if (host == 'localhost') return true;
  if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) return true;
  // A dotted name whose last label is a plausible TLD (two or more letters).
  return RegExp(
    r'^[A-Za-z0-9]([A-Za-z0-9\-]*[A-Za-z0-9])?'
    r'(\.[A-Za-z0-9]([A-Za-z0-9\-]*[A-Za-z0-9])?)*'
    r'\.[A-Za-z]{2,}$',
  ).hasMatch(host);
}
