import 'package:flutter_test/flutter_test.dart';

import 'package:salu_remote/core/models.dart';

/// The web-media read is the one place the protocol left a unit unstated
/// (`remote.md` §17.4 / §17.11): JavaScript's `currentTime` is seconds, the
/// house unit everywhere else is milliseconds, and a phone that guesses wrong
/// shows a clock 1000× off and lands every seek 1000× off. These tests are the
/// whole argument for reading the unit instead of assuming it.
void main() {
  group('web_media_get — time units', () {
    test('milliseconds (the contract) read as milliseconds', () {
      final WebMediaInfo info = WebMediaInfo.from(<String, Object?>{
        'found': true,
        'playing': true,
        'position': 754000,
        'duration': 2712000,
      });

      expect(info.position, const Duration(milliseconds: 754000));
      expect(info.duration, const Duration(minutes: 45, seconds: 12));
      expect(info.dialect.time, WebTimeUnit.milliseconds);
      expect(info.seekable, isTrue);
    });

    test('a fractional number can only be seconds, and reads as seconds', () {
      final WebMediaInfo info = WebMediaInfo.from(<String, Object?>{
        'found': true,
        'position': 754.418,
        'duration': 2712.5,
      });

      expect(info.dialect.time, WebTimeUnit.seconds);
      expect(info.position.inMilliseconds, 754418);
      expect(info.duration.inMilliseconds, 2712500);
    });

    test('the PC saying `unit` outranks everything else', () {
      // Whole numbers that *look* like milliseconds, from a PC that says they
      // are not: the size of a number is never the evidence.
      final WebMediaInfo seconds = WebMediaInfo.from(<String, Object?>{
        'unit': 's',
        'position': 754,
        'duration': 2712,
      });
      final WebMediaInfo millis = WebMediaInfo.from(<String, Object?>{
        'unit': 'ms',
        'position': 754.4,
        'duration': 2712.4,
      });

      expect(seconds.dialect.time, WebTimeUnit.seconds);
      expect(seconds.duration, const Duration(seconds: 2712));
      expect(millis.dialect.time, WebTimeUnit.milliseconds);
      expect(millis.duration, const Duration(milliseconds: 2712));
    });

    test('the `web_media_unit` promise means milliseconds without a read', () {
      final WebMediaInfo info = WebMediaInfo.from(
        <String, Object?>{'found': true, 'position': 754, 'duration': 2712},
        contractUnits: true,
      );

      expect(info.dialect.time, WebTimeUnit.milliseconds);
      expect(info.position, const Duration(milliseconds: 754));
    });

    test('the JavaScript field names still read instead of reporting 0:00', () {
      final WebMediaInfo info = WebMediaInfo.from(<String, Object?>{
        'found': true,
        'currentTime': 12.5,
        'length': 60.25,
      });

      expect(info.dialect.time, WebTimeUnit.seconds);
      expect(info.position, const Duration(milliseconds: 12500));
      expect(info.duration, const Duration(milliseconds: 60250));
    });

    test('a number that arrives as a string still reads as a number', () {
      // `executeScript` returns whatever the page's JavaScript gave back; one
      // stray `toString()` must not cost the user a seek bar.
      final WebMediaInfo info = WebMediaInfo.from(<String, Object?>{
        'found': true,
        'position': '754418',
        'duration': '2712000',
        'volume': '45',
      });

      expect(info.position, const Duration(milliseconds: 754418));
      expect(info.duration, const Duration(milliseconds: 2712000));
      expect(info.volume, 45);
      expect(info.seekable, isTrue);
      expect(info.dialect.time, WebTimeUnit.milliseconds);
    });

    test('a live stream or an unloaded element is unknown, not enormous', () {
      for (final Object? duration in <Object?>[double.nan, double.infinity, 0, null]) {
        final WebMediaInfo info = WebMediaInfo.from(<String, Object?>{
          'found': true,
          'position': 0,
          'duration': duration,
        });
        expect(info.duration, Duration.zero, reason: 'duration was $duration');
        expect(info.seekable, isFalse, reason: 'duration was $duration');
      }
    });

    test('the PC may state seekable outright', () {
      final WebMediaInfo info = WebMediaInfo.from(<String, Object?>{
        'found': true,
        'position': 1000,
        'duration': 0,
        'seekable': true,
      });

      expect(info.seekable, isTrue);
    });
  });

  group('web_media_get — volume units', () {
    test('a fraction reads as a percent', () {
      final WebMediaInfo info = WebMediaInfo.from(<String, Object?>{
        'found': true,
        'volume': 0.45,
      });

      expect(info.dialect.volume, WebVolumeUnit.fraction);
      expect(info.volume, 45);
    });

    test('a whole number above one reads as the percent it is', () {
      final WebMediaInfo info = WebMediaInfo.from(<String, Object?>{
        'found': true,
        'volume': 45,
        'volumeUnit': 'percent',
      });

      expect(info.dialect.volume, WebVolumeUnit.percent);
      expect(info.volume, 45);
    });

    test('exactly one is every page default — 100%, not 1%', () {
      expect(WebMediaInfo.from(<String, Object?>{'volume': 1}).volume, 100);
      expect(WebMediaInfo.from(<String, Object?>{'volume': 1.0}).volume, 100);
      expect(WebMediaInfo.from(<String, Object?>{'volume': 0}).volume, 0);
    });

    test('an out-of-range number is clamped, never thrown', () {
      expect(WebMediaInfo.from(<String, Object?>{'volume': 4500}).volume, 100);
      expect(WebMediaInfo.from(<String, Object?>{'volume': -3}).volume, 0);
      expect(WebMediaInfo.from(<String, Object?>{}).volume, 100);
    });
  });

  group('WebMediaDialect — the write side answers in the same voice', () {
    test('milliseconds go out as milliseconds', () {
      const WebMediaDialect dialect =
          WebMediaDialect(time: WebTimeUnit.milliseconds);

      expect(dialect.timeValue(const Duration(seconds: 12)), 12000);
    });

    test('seconds go out as seconds, fraction kept', () {
      const WebMediaDialect dialect = WebMediaDialect(time: WebTimeUnit.seconds);

      expect(dialect.timeValue(const Duration(milliseconds: 12345)), 12.345);
      expect(dialect.timeValue(Duration.zero), 0);
    });

    test('the dialect a reply was read in is the dialect it is written in', () {
      final WebMediaInfo info = WebMediaInfo.from(<String, Object?>{
        'found': true,
        'position': 12.5,
        'duration': 60.0,
      });

      expect(info.dialect.timeIsSeconds, isTrue);
      // The round trip is the whole point: read 12.5 s, seek back to 12.5 s.
      expect(info.dialect.timeValue(info.position), 12.5);
    });
  });

  group('WebMediaInfo — equality', () {
    test('the same reading twice is equal, so the 1/s poll does not repaint', () {
      final Map<String, Object?> raw = <String, Object?>{
        'found': true,
        'playing': true,
        'position': 1200,
        'duration': 60000,
        'volume': 0.4,
        'muted': false,
        'canFull': true,
      };

      expect(WebMediaInfo.from(raw), WebMediaInfo.from(raw));
      expect(WebMediaInfo.from(raw).hashCode, WebMediaInfo.from(raw).hashCode);
    });

    test('a moved playhead is not equal', () {
      expect(
        WebMediaInfo.from(<String, Object?>{'found': true, 'position': 1200}),
        isNot(WebMediaInfo.from(<String, Object?>{'found': true, 'position': 2200})),
      );
    });

    test('the raw reply is kept for the diagnostics sheet', () {
      final WebMediaInfo info = WebMediaInfo.from(<String, Object?>{
        'found': true,
        'currentTime': 12.5,
      });

      expect(info.raw['currentTime'], 12.5);
    });
  });

  group('the tab strip', () {
    test('reads the rows, the active index and the honest total', () {
      final WebTabPage page = WebTabPage.from(<String, Object?>{
        'active': 1,
        'count': 3,
        'tabs': <Object?>[
          <String, Object?>{'index': 0, 'title': 'YouTube', 'url': 'https://a'},
          <String, Object?>{
            'index': 1,
            'title': 'Dune',
            'url': 'https://b',
            'loading': true,
            'hasMedia': true,
          },
        ],
      });

      expect(page.tabs.length, 2);
      expect(page.activeIndex, 1);
      expect(page.count, 3); // the PC says three; two fit the reply
      expect(page.isEmpty, isFalse);
      expect(page.tabs[1].loading, isTrue);
      expect(page.tabs[1].hasMedia, isTrue);
      expect(page.isActive(page.tabs[1]), isTrue);
      expect(page.isActive(page.tabs[0]), isFalse);
    });

    test('an unmarked strip falls back to the row the PC flagged active', () {
      final WebTabPage page = WebTabPage.from(<String, Object?>{
        'tabs': <Object?>[
          <String, Object?>{'index': 0, 'title': 'One'},
          <String, Object?>{'index': 1, 'title': 'Two', 'active': true},
        ],
      });

      expect(page.activeIndex, 1);
      expect(page.count, 2);
    });

    test('a titleless tab is still a readable row', () {
      final WebTabPage page = WebTabPage.from(<String, Object?>{
        'tabs': <Object?>[
          <String, Object?>{'index': 0, 'url': 'https://example.com'},
          <String, Object?>{'index': 1},
        ],
      });

      expect(page.tabs[0].title, 'https://example.com');
      expect(page.tabs[1].title, 'Untitled tab');
    });

    test('nothing there reads as an empty strip, not an exception', () {
      expect(WebTabPage.from(<String, Object?>{}).isEmpty, isTrue);
      expect(WebTabPage.from(<String, Object?>{}).activeIndex, -1);
    });
  });

  group('bookmarks and focus', () {
    test('either key the PC chooses carries the list', () {
      final List<WebBookmarkInfo> entries =
          webBookmarksFrom(<String, Object?>{
        'entries': <Object?>[
          <String, Object?>{'name': 'News', 'url': 'https://n', 'folder': 'Daily'},
        ],
      });
      final List<WebBookmarkInfo> bookmarks =
          webBookmarksFrom(<String, Object?>{
        'bookmarks': <Object?>[
          <String, Object?>{'title': 'News', 'url': 'https://n'},
        ],
      });

      expect(entries.single.folder, 'Daily');
      expect(bookmarks.single.name, 'News');
      expect(webBookmarksFrom(<String, Object?>{}), isEmpty);
    });

    test('the focus line says what the pad is about to click', () {
      final WebFocusInfo focus = WebFocusInfo.from(<String, Object?>{
        'label': 'Subscribe',
        'tag': 'button',
        'index': 3,
        'count': 120,
      });

      expect(focus.line, 'Subscribe · BUTTON · 4 of 120');
      expect(focus.known, isTrue);
      expect(focus.editable, isFalse);
    });

    test('a text field changes what the arrows mean', () {
      final WebFocusInfo focus = WebFocusInfo.from(<String, Object?>{
        'tag': 'input',
        'editable': true,
      });

      expect(focus.editable, isTrue);
      expect(focus.known, isTrue);
    });

    test('no focus reported reads as one honest line', () {
      expect(WebFocusInfo.from(null).known, isFalse);
      expect(WebFocusInfo.from(null).line, 'Nothing focused yet');
    });
  });

  group('the feature promises', () {
    test('the phone draws only what the PC advertised', () {
      final ServerInfo full = ServerInfo.from(<String, Object?>{
        'name': 'PC',
        'version': '1.0',
        'features': <Object?>['web', 'web_key', 'web_tabs'],
      });
      final ServerInfo old = ServerInfo.from(<String, Object?>{
        'name': 'PC',
        'version': '0.9',
        'features': <Object?>['web'],
      });

      expect(full.features.contains(RemoteFeature.webTabs), isTrue);
      expect(full.features.contains(RemoteFeature.webBookmarks), isFalse);
      expect(old.features.contains(RemoteFeature.webKey), isFalse);
      expect(RemoteFeature.all, contains(RemoteFeature.webMediaUnit));
    });

    test('the 2026-09-24 promises are in the list', () {
      // Home, the one fullscreen seat, the trackpad and add-only bookmarking:
      // a PC that implements them says so, and the phone draws accordingly.
      expect(RemoteFeature.all, contains(RemoteFeature.webHome));
      expect(RemoteFeature.all, contains(RemoteFeature.webFullscreen));
      expect(RemoteFeature.all, contains(RemoteFeature.webMouse));
      expect(RemoteFeature.all, contains(RemoteFeature.webBookmarkAdd));
    });
  });

  group('the element\'s own fullscreen state', () {
    test('a PC that reports it is believed — the seat\'s mark reads it', () {
      final WebMediaInfo info = WebMediaInfo.from(<String, Object?>{
        'found': true,
        'canFull': true,
        'fullscreen': true,
      });

      expect(info.fullscreen, isTrue);
      expect(info.canFullscreen, isTrue);
    });

    test('a PC that does not is not guessed at', () {
      // Without the field the mark falls back to the snapshot's own
      // `web.fullscreen`; a false here is "not told", never "not full".
      final WebMediaInfo info = WebMediaInfo.from(<String, Object?>{
        'found': true,
        'canFull': true,
      });

      expect(info.fullscreen, isFalse);
      expect(info.canFullscreen, isTrue);
    });

    test('the dialect spelling is accepted too', () {
      expect(
        WebMediaInfo.from(<String, Object?>{'isFullscreen': true}).fullscreen,
        isTrue,
      );
    });
  });
}
