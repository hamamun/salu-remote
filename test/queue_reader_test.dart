import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:salu_remote/core/models.dart';
import 'package:salu_remote/core/queue_reader.dart';
import 'package:salu_remote/core/queue_view.dart';
import 'package:salu_remote/core/reply.dart';

Future<void> noDelay(Duration _) async {}
RemoteReply page(int from, int count, int total, {String revision = 'one'}) =>
    RemoteReply.success('queue_result', <String, Object?>{
      'from': from, 'total': total, 'revision': revision,
      'rows': <Object?>[
        for (int i = from; i < from + count; i++)
          <String, Object?>{'index': i, 'title': 'Channel $i'},
      ],
    });
Map<String, Object?> fragment(String key, List<int> indexes, int count) =>
    <String, Object?>{'key': key, 'name': key, 'start': indexes.first,
      'count': count, 'indexes': indexes};
RemoteReply groupPage(List<Map<String, Object?>> groups, int? next,
        {String revision = 'one', String by = 'country'}) =>
    RemoteReply.success('queue_groups_result', <String, Object?>{
      'revision': revision, 'by': by, 'groups': groups, 'next': next,
    });

void main() {
  test('10,000 rows display progressively, now-playing page first', () async {
    final List<int> requests = <int>[];
    final List<int> lengths = <int>[];
    final QueueReader reader = QueueReader((verb, args) async {
      requests.add(args['from']! as int);
      return page(args['from']! as int, args['count']! as int, 10000);
    }, delay: noDelay);
    await reader.rows(count: 10000, currentIndex: 9999, revision: 'one',
        current: () => true, onPage: (rows) {
      lengths.add(rows.length);
      if (lengths.length == 1) expect(rows.last.index, 9999);
    });
    expect(requests.first, 9900);
    expect(requests.toSet(), hasLength(100));
    expect(lengths.first, 100);
    expect(lengths.last, 10000);
  });

  test('byte-limited row pages advance by actual returned rows', () async {
    final QueueReader reader = QueueReader((verb, args) async =>
        page(args['from']! as int, 1, 3), delay: noDelay);
    List<QueueRow> result = <QueueRow>[];
    await reader.rows(count: 3, currentIndex: 0, revision: 'one',
        current: () => true, onPage: (rows) => result = rows);
    expect(result.map((r) => r.index), <int>[0, 1, 2]);
  });

  test('oversized legacy busy responses shrink the row request', () async {
    final List<int> sizes = <int>[];
    final QueueReader reader = QueueReader((verb, args) async {
      final int n = args['count']! as int;
      sizes.add(n);
      if (n > 1) return RemoteReply.failure('busy',
          'The response is too large; request a smaller page.');
      return page(args['from']! as int, n, 4);
    }, delay: noDelay);
    await reader.rows(count: 4, currentIndex: 0, revision: null,
        current: () => true, onPage: (_) {});
    expect(sizes.take(3), <int>[4, 2, 1]);
    expect(sizes.length, 6);
  });

  test('transient reads retry, without discarding successful pages', () async {
    int attempts = 0;
    final QueueReader reader = QueueReader((verb, args) async {
      if (attempts++ < 2) return RemoteReply.failure('too_fast', null);
      return page(0, 1, 1);
    }, delay: noDelay);
    await reader.rows(count: 1, currentIndex: 0, revision: 'one',
        current: () => true, onPage: (rows) => expect(rows, hasLength(1)));
    expect(attempts, 3);
  });

  test('busy retries are bounded', () async {
    int attempts = 0;
    final QueueReader reader = QueueReader((verb, args) async {
      attempts++;
      return RemoteReply.failure('busy', null);
    }, delay: noDelay);
    await expectLater(reader.rows(count: 1, currentIndex: 0, revision: null,
        current: () => true, onPage: (_) => fail('no successful page')),
        throwsA(isA<QueueReadFailure>()));
    expect(attempts, 3);
  });

  test('a failed later page leaves the earlier page published', () async {
    List<QueueRow> visible = <QueueRow>[];
    final QueueReader reader = QueueReader((verb, args) async {
      return args['from'] == 0 ? page(0, 100, 101)
          : RemoteReply.failure('busy', null);
    }, delay: noDelay);
    await expectLater(reader.rows(count: 101, currentIndex: 0, revision: 'one',
        current: () => true, onPage: (rows) => visible = rows),
        throwsA(isA<QueueReadFailure>()));
    expect(visible, hasLength(100));
    expect(visible.last.index, 99);
  });

  test('oversized group pages reduce their fragment count', () async {
    final List<int> sizes = <int>[];
    final QueueReader reader = QueueReader((verb, args) async {
      final int n = args['count']! as int;
      sizes.add(n);
      if (n > 1) return RemoteReply.failure('too_large', null);
      return groupPage(<Map<String, Object?>>[fragment('A', <int>[0], 1)], null);
    }, delay: noDelay);
    await reader.groups(by: 'country', revision: 'one', queueCount: 1,
        current: () => true, onPage: (_) {});
    expect(sizes, <int>[20, 10, 5, 2, 1]);
  });

  test('same-size replacement rejects old row revision', () async {
    final QueueReader reader = QueueReader((verb, args) async =>
        page(0, 1, 1, revision: 'two'), delay: noDelay);
    await expectLater(reader.rows(count: 1, currentIndex: 0, revision: 'one',
        current: () => true, onPage: (_) => fail('stale page published')),
        throwsA(isA<QueueReadFailure>().having(
            (e) => e.reply.code, 'code', 'stale_queue')));
  });

  test('cancelled in-flight read cannot publish or request next page', () async {
    bool current = true;
    int requests = 0;
    final Completer<RemoteReply> response = Completer<RemoteReply>();
    final QueueReader reader = QueueReader((verb, args) {
      requests++;
      return response.future;
    }, delay: noDelay);
    final Future<void> load = reader.rows(count: 101, currentIndex: 0,
        revision: 'one', current: () => current,
        onPage: (_) => fail('cancelled page published'));
    final Future<void> assertion = expectLater(load, throwsA(isA<QueueReadCancelled>()));
    await Future<void>.delayed(Duration.zero);
    current = false;
    response.complete(page(0, 100, 101));
    await assertion;
    expect(requests, 1);
  });

  test('row/group loads share one read lane', () async {
    int active = 0;
    int maxActive = 0;
    final QueueReader reader = QueueReader((verb, args) async {
      active++;
      if (active > maxActive) maxActive = active;
      await Future<void>.delayed(Duration.zero);
      active--;
      return verb == 'queue_get' ? page(0, 1, 1)
          : groupPage(<Map<String, Object?>>[fragment('A', <int>[0], 1)], null);
    }, delay: noDelay);
    await Future.wait(<Future<void>>[
      reader.rows(count: 1, currentIndex: 0, revision: 'one',
          current: () => true, onPage: (_) {}),
      reader.groups(by: 'country', revision: 'one', queueCount: 1,
          current: () => true, onPage: (_) {}),
    ]);
    expect(maxActive, 1);
  });

  test('group fragments merge scattered members and preserve PC order', () async {
    final QueueReader reader = QueueReader((verb, args) async {
      expect(verb, 'queue_groups_page');
      return args['from'] == 0
          ? groupPage(<Map<String, Object?>>[
              fragment('Alpha', <int>[1], 2),
            ], 1)
          : groupPage(<Map<String, Object?>>[
              <String, Object?>{...fragment('Alpha', <int>[3], 2), 'start': 1},
              fragment('Zulu', <int>[0, 2], 2),
            ], null);
    }, delay: noDelay);
    List<QueueGroup> result = <QueueGroup>[];
    await reader.groups(by: 'country', revision: 'one', queueCount: 4,
        current: () => true, onPage: (groups) => result = groups);
    expect(result.map((g) => g.key), <String>['Alpha', 'Zulu']);
    expect(result.first.indexes, <int>{1, 3});
    expect(groupKeyForIndex(result, 2), 'Zulu');
    final List<QueueDisplayItem> display = buildQueueDisplay(
        rows: <QueueRow>[for (int i = 0; i < 4; i++) QueueRow(index: i, title: '$i')],
        groups: result, grouped: true, openGroupKey: 'Alpha', query: '',
        favouritesOnly: false, favourites: <String>{});
    expect(display.map((d) => d.group?.key ?? d.row!.title),
        <String>['Alpha', '1', '3', 'Zulu']);
  });

  test('invalid or duplicate membership cannot be silently accepted', () async {
    for (final List<Object?> indexes in <List<Object?>>[
      <Object?>[0, -1], <Object?>[0, 0], <Object?>[0, 0.5],
    ]) {
      final QueueReader reader = QueueReader((verb, args) async => groupPage(
          <Map<String, Object?>>[
            <String, Object?>{...fragment('A', <int>[0], 1), 'indexes': indexes},
          ], null), delay: noDelay);
      await expectLater(reader.groups(by: 'country', revision: 'one', queueCount: 1,
          current: () => true, onPage: (_) => fail('invalid membership published')),
          throwsA(isA<QueueReadFailure>()));
    }
  });

  test('legacy descriptors never invent consecutive membership', () {
    const QueueGroup legacy = QueueGroup(key: 'g', name: 'G', start: 0, count: 3);
    expect(groupKeyForIndex(<QueueGroup>[legacy], 1), isNull);
  });

  test('stale grouping response and non-advancing cursors fail safely', () async {
    for (final RemoteReply response in <RemoteReply>[
      groupPage(<Map<String, Object?>>[fragment('A', <int>[0], 1)], null, by: 'language'),
      groupPage(<Map<String, Object?>>[fragment('A', <int>[0], 1)], 0),
      groupPage(<Map<String, Object?>>[fragment('A', <int>[0], 1)], null, revision: 'two'),
      groupPage(<Map<String, Object?>>[], null),
    ]) {
      final QueueReader reader = QueueReader((verb, args) async => response, delay: noDelay);
      await expectLater(reader.groups(by: 'country', revision: 'one', queueCount: 1,
          current: () => true, onPage: (_) => fail('invalid groups published')),
          throwsA(isA<QueueReadFailure>()));
    }
  });
}
