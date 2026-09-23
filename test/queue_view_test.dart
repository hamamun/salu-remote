import 'package:flutter_test/flutter_test.dart';

import 'package:salu_remote/core/models.dart';
import 'package:salu_remote/core/queue_view.dart';

QueueRow row(int index, String title) => QueueRow(index: index, title: title);

QueueGroup mkGroup(String key, String name, int start, int count) =>
    QueueGroup(key: key, name: name, start: start, count: count);

/// A 6-channel list in two groups: Sports (0–2), News (3–5).
List<QueueRow> rows() => <QueueRow>[
      row(0, 'Sports One'),
      row(1, 'Sports Two'),
      row(2, 'Match Day'),
      row(3, 'Morning News'),
      row(4, 'Evening News'),
      row(5, 'Sports News Hour'),
    ];

List<QueueGroup> groups() => <QueueGroup>[
      mkGroup('g-sports', 'Sports', 0, 3),
      mkGroup('g-news', 'News', 3, 3),
    ];

List<String> titles(List<QueueDisplayItem> display) => display
    .map((QueueDisplayItem d) => d.isGroup ? 'H:${d.group!.name}' : d.row!.title)
    .toList();

void main() {
  group('buildQueueDisplay', () {
    test('flat: every row, in queue order whatever the input order', () {
      final List<QueueDisplayItem> display = buildQueueDisplay(
        rows: rows().reversed.toList(),
        groups: groups(),
        grouped: false,
        openGroupKey: null,
        query: '',
        favouritesOnly: false,
        favourites: const <String>{},
      );
      expect(display.every((QueueDisplayItem d) => d.isRow), isTrue);
      expect(
        titles(display),
        <String>[
          'Sports One',
          'Sports Two',
          'Match Day',
          'Morning News',
          'Evening News',
          'Sports News Hour',
        ],
      );
    });

    test('grouped accordion: every head paints, only the open group rows do', () {
      final List<QueueDisplayItem> display = buildQueueDisplay(
        rows: rows(),
        groups: groups(),
        grouped: true,
        openGroupKey: 'g-news',
        query: '',
        favouritesOnly: false,
        favourites: const <String>{},
      );
      // Sports autohides — its head stays, its channels do not.
      expect(
        titles(display),
        <String>[
          'H:Sports',
          'H:News',
          'Morning News',
          'Evening News',
          'Sports News Hour',
        ],
      );
    });

    test('grouped with nothing open: heads only', () {
      final List<QueueDisplayItem> display = buildQueueDisplay(
        rows: rows(),
        groups: groups(),
        grouped: true,
        openGroupKey: null,
        query: '',
        favouritesOnly: false,
        favourites: const <String>{},
      );
      expect(titles(display), <String>['H:Sports', 'H:News']);
    });

    test('a stale open key opens nothing', () {
      final List<QueueDisplayItem> display = buildQueueDisplay(
        rows: rows(),
        groups: groups(),
        grouped: true,
        openGroupKey: 'g-gone',
        query: '',
        favouritesOnly: false,
        favourites: const <String>{},
      );
      expect(titles(display), <String>['H:Sports', 'H:News']);
    });

    test('a search flattens the list whatever the mode is', () {
      final List<QueueDisplayItem> display = buildQueueDisplay(
        rows: rows(),
        groups: groups(),
        grouped: true,
        openGroupKey: 'g-sports',
        query: 'news',
        favouritesOnly: false,
        favourites: const <String>{},
      );
      expect(display.every((QueueDisplayItem d) => d.isRow), isTrue);
      expect(
        titles(display),
        <String>['Morning News', 'Evening News', 'Sports News Hour'],
      );
    });

    test('the search is case-insensitive and trims', () {
      final List<QueueDisplayItem> display = buildQueueDisplay(
        rows: rows(),
        groups: const <QueueGroup>[],
        grouped: false,
        openGroupKey: null,
        query: '  SPORTS ',
        favouritesOnly: false,
        favourites: const <String>{},
      );
      expect(
        titles(display),
        <String>['Sports One', 'Sports Two', 'Sports News Hour'],
      );
    });

    test('favourites-only thins rows but keeps the heads', () {
      final List<QueueDisplayItem> display = buildQueueDisplay(
        rows: rows(),
        groups: groups(),
        grouped: true,
        openGroupKey: 'g-news',
        query: '',
        favouritesOnly: true,
        favourites: const <String>{'Evening News', 'Sports One'},
      );
      expect(
        titles(display),
        <String>['H:Sports', 'H:News', 'Evening News'],
      );
    });

    test('favourites-only flat: bookmarks in queue order', () {
      final List<QueueDisplayItem> display = buildQueueDisplay(
        rows: rows(),
        groups: const <QueueGroup>[],
        grouped: false,
        openGroupKey: null,
        query: '',
        favouritesOnly: true,
        favourites: const <String>{'Sports One', 'Match Day'},
      );
      expect(titles(display), <String>['Sports One', 'Match Day']);
    });

    test('search and favourites-only combine', () {
      final List<QueueDisplayItem> display = buildQueueDisplay(
        rows: rows(),
        groups: groups(),
        grouped: true,
        openGroupKey: 'g-sports',
        query: 'sports',
        favouritesOnly: true,
        favourites: const <String>{'Sports Two', 'Morning News'},
      );
      expect(titles(display), <String>['Sports Two']);
    });

    test('rows no head owns stay visible after the heads', () {
      final List<QueueDisplayItem> display = buildQueueDisplay(
        rows: <QueueRow>[...rows(), row(9, 'Late Arrival')],
        groups: groups(),
        grouped: true,
        openGroupKey: 'g-sports',
        query: '',
        favouritesOnly: false,
        favourites: const <String>{},
      );
      expect(
        titles(display),
        <String>[
          'H:Sports',
          'Sports One',
          'Sports Two',
          'Match Day',
          'H:News',
          'Late Arrival',
        ],
      );
    });

    test('overlapping groups resolve to the earlier head', () {
      final List<QueueDisplayItem> display = buildQueueDisplay(
        rows: rows(),
        groups: <QueueGroup>[
          mkGroup('g-a', 'A', 0, 6), // claims everything…
          mkGroup('g-b', 'B', 3, 3), // …but B starts at 3
        ],
        grouped: true,
        openGroupKey: 'g-a',
        query: '',
        favouritesOnly: false,
        favourites: const <String>{},
      );
      // A is clipped at B's start: rows 0–2 only.
      expect(
        titles(display),
        <String>['H:A', 'Sports One', 'Sports Two', 'Match Day', 'H:B'],
      );
    });

    test('empty rows: empty display, even grouped', () {
      expect(
        buildQueueDisplay(
          rows: const <QueueRow>[],
          groups: groups(),
          grouped: true,
          openGroupKey: 'g-sports',
          query: '',
          favouritesOnly: false,
          favourites: const <String>{},
        ),
        isEmpty,
      );
    });
  });

  group('groupKeyForIndex', () {
    test('names the holding group', () {
      expect(groupKeyForIndex(groups(), 0), 'g-sports');
      expect(groupKeyForIndex(groups(), 2), 'g-sports');
      expect(groupKeyForIndex(groups(), 3), 'g-news');
      expect(groupKeyForIndex(groups(), 5), 'g-news');
    });

    test('null outside every head and for nothing-playing', () {
      expect(groupKeyForIndex(groups(), 6), isNull);
      expect(groupKeyForIndex(groups(), -1), isNull);
      expect(groupKeyForIndex(const <QueueGroup>[], 0), isNull);
    });
  });
}
