import 'package:flutter_test/flutter_test.dart';

import 'package:salu_remote/core/web_url.dart';

/// The two pieces of arithmetic behind the user's 2026-09-24 fixes:
///
/// * [webAddress] — the **blank new tab**. "youtube.com" typed into the URL box
///   went to the PC with no scheme and came back as an empty tab, because a page
///   loader cannot guess what kind of address it is looking at. It gets the
///   scheme it obviously wants before it reaches the wire.
/// * [siteHome] — the **Home button's** fallback for a PC that does not answer
///   `browser_nav {action:"home"}`: the origin of whatever is loaded.
void main() {
  group('webAddress — a typed address gets the scheme it needs', () {
    test('a bare host becomes https', () {
      expect(webAddress('youtube.com'), 'https://youtube.com');
      expect(
        webAddress('www.example.org/watch?v=1'),
        'https://www.example.org/watch?v=1',
      );
      expect(webAddress('example.co.uk'), 'https://example.co.uk');
      expect(webAddress('192.168.1.10'), 'https://192.168.1.10');
    });

    test('a host with a port is a host, not a scheme', () {
      // `localhost:3000` reads as scheme `localhost` to a naive parser, and
      // `host.com:8080` is a host whatever the parser thinks. Both keep their
      // meaning here — the port included.
      expect(webAddress('localhost:3000'), 'https://localhost:3000');
      expect(webAddress('youtube.com:8443'), 'https://youtube.com:8443');
      expect(webAddress('192.168.1.10:8096'), 'https://192.168.1.10:8096');
    });

    test('text that is already addressed is left exactly as it is', () {
      expect(webAddress('https://youtube.com'), 'https://youtube.com');
      expect(webAddress('http://youtube.com/watch?v=1'),
          'http://youtube.com/watch?v=1');
      expect(webAddress('about:blank'), 'about:blank');
      expect(webAddress('mailto:someone@example.com'),
          'mailto:someone@example.com');
      expect(webAddress('salu://pair?code=1234'), 'salu://pair?code=1234');
    });

    test('whitespace is trimmed and nothing stays nothing', () {
      expect(webAddress('   '), isNull);
      expect(webAddress(''), isNull);
      expect(webAddress('  youtube.com  '), 'https://youtube.com');
    });

    test('a search phrase is left for the PC to classify', () {
      // Guessing twice is how a phrase becomes a broken page: the PC's own
      // `open_url` has the last word on anything that is not an address.
      expect(webAddress('dune part two trailer'), 'dune part two trailer');
      expect(webAddress('youtube'), 'youtube');
      expect(webAddress('C:\\Videos\\film.mkv'), 'C:\\Videos\\film.mkv');
    });
  });

  group('siteHome — the front page of what is loaded', () {
    test('the origin, with port, no path and no query', () {
      expect(
        siteHome('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'https://www.youtube.com',
      );
      expect(
        siteHome('http://192.168.1.10:8096/web/index.html?x=1#top'),
        'http://192.168.1.10:8096',
      );
      expect(siteHome('https://example.com/'), 'https://example.com');
      expect(siteHome('https://example.com'), 'https://example.com');
    });

    test('pages with nowhere to go home to answer null', () {
      expect(siteHome(null), isNull);
      expect(siteHome(''), isNull);
      expect(siteHome('   '), isNull);
      expect(siteHome('about:blank'), isNull);
      expect(siteHome('file:///C:/Videos/film.html'), isNull);
      expect(siteHome('not a url'), isNull);
    });
  });
}
