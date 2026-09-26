import 'dart:async';

import 'models.dart';
import 'reply.dart';

/// Only read-only queue requests use this lane. Playback and heartbeats never
/// wait behind it. Shared by row and group loads, including superseded loads.
class QueueReader {
  QueueReader(this.send, {Future<void> Function(Duration)? delay})
      : delay = delay ?? Future<void>.delayed;

  final Future<RemoteReply> Function(String, Map<String, Object?>) send;
  final Future<void> Function(Duration) delay;
  Future<void> _tail = Future<void>.value();

  Future<RemoteReply> _read(String verb, Map<String, Object?> args,
      bool Function() current) async {
    for (int attempt = 0; ; attempt++) {
      final Future<void> previous = _tail;
      final Completer<void> done = Completer<void>();
      _tail = done.future;
      await previous;
      late RemoteReply reply;
      try {
        if (!current()) throw const QueueReadCancelled();
        reply = await send(verb, args);
        // At most ten queue reads/sec across both loaders. Leave ample room
        // in the PC's 30 commands/sec budget for interactive controls.
        await delay(const Duration(milliseconds: 100));
      } finally {
        done.complete();
      }
      if (!current()) throw const QueueReadCancelled();
      if (reply.ok) return reply;
      if (_oversized(reply)) {
        throw QueueReadFailure(RemoteReply.failure(
            'too_large', 'The response is too large.'));
      }
      if (attempt >= 2 ||
          !const <String>{'busy', 'too_fast', 'timeout'}.contains(reply.code)) {
        throw QueueReadFailure(reply);
      }
      await delay(Duration(milliseconds: 500 * (attempt + 1)));
    }
  }

  static bool _oversized(RemoteReply reply) =>
      reply.code == 'too_large' ||
      (reply.code == 'busy' &&
          (reply.message?.contains('response is too large') ?? false));

  static Never _invalid() => throw QueueReadFailure(
      RemoteReply.failure('invalid_response', 'Invalid playlist response.'));

  static void _revision(RemoteReply reply, String? expected) {
    if (expected != null && reply['revision'] != expected) {
      throw QueueReadFailure(RemoteReply.failure('stale_queue', null));
    }
  }

  /// Current track's page first, then the rest. Each successful page is visible
  /// immediately; an error never discards pages already on screen.
  Future<void> rows({
    required int count,
    required int currentIndex,
    required String? revision,
    required bool Function() current,
    required void Function(List<QueueRow>) onPage,
  }) async {
    final int first = currentIndex >= 0 && currentIndex < count
        ? (currentIndex ~/ 100) * 100
        : 0;
    final List<int> starts = <int>[
      if (count > 0) first,
      for (int i = 0; i < count; i += 100) if (i != first) i,
    ];
    final Map<int, QueueRow> loaded = <int, QueueRow>{};
    int pageSize = 100;
    for (final int start in starts) {
      final int end = (start + 100).clamp(0, count).toInt();
      int from = start;
      while (from < end) {
        final int requested = pageSize.clamp(1, end - from).toInt();
        late RemoteReply reply;
        try {
          reply = await _read('queue_get', <String, Object?>{
            'from': from, 'count': requested,
            if (revision != null) 'revision': revision,
          }, current);
        } on QueueReadFailure catch (error) {
          if (_oversized(error.reply) && requested > 1) {
            pageSize = requested ~/ 2;
            continue;
          }
          rethrow;
        }
        _revision(reply, revision);
        if (reply['rows'] is! List) _invalid();
        final QueuePage page = QueuePage.from(reply.data);
        if (page.total != count) {
          throw QueueReadFailure(RemoteReply.failure('stale_queue', null));
        }
        if (page.from != from || page.rows.isEmpty || page.rows.length > requested) _invalid();
        for (int i = 0; i < page.rows.length; i++) {
          final QueueRow row = page.rows[i];
          if (row.index != from + i) _invalid();
          loaded[row.index] = row;
        }
        from += page.rows.length;
        final List<QueueRow> rows = loaded.values.toList()
          ..sort((a, b) => a.index.compareTo(b.index));
        onPage(List<QueueRow>.unmodifiable(rows));
      }
    }
  }

  /// Capability-gated v2: byte-bounded pages of explicit membership fragments.
  /// A large group can span pages; fragments are merged by stable group key.
  Future<void> groups({
    required String by,
    required String revision,
    required int queueCount,
    required bool Function() current,
    required void Function(List<QueueGroup>) onPage,
  }) async {
    final Map<String, QueueGroup> loaded = <String, QueueGroup>{};
    final Map<int, String> owners = <int, String>{};
    int from = 0;
    int pageSize = 20;
    int pages = 0;
    while (true) {
      if (++pages > queueCount + 1) _invalid();
      late RemoteReply reply;
      try {
        reply = await _read('queue_groups_page', <String, Object?>{
          'by': by, 'revision': revision, 'from': from, 'count': pageSize,
        }, current);
      } on QueueReadFailure catch (error) {
        if (_oversized(error.reply) && pageSize > 1) {
          pageSize = (pageSize ~/ 2).clamp(1, 20).toInt();
          pages--;
          continue;
        }
        rethrow;
      }
      _revision(reply, revision);
      if (reply['by'] != by || reply['groups'] is! List ||
          !reply.has('next')) _invalid();
      // Models are deliberately tolerant for old protocol fields; paged
      // membership is not. Never silently drop malformed or repeated indexes.
      final List rawGroups = reply['groups'] as List;
      if (rawGroups.length > pageSize) _invalid();
      for (final Object? raw in rawGroups) {
        if (raw is! Map || raw['indexes'] is! List ||
            raw['count'] is! int || raw['start'] is! int ||
            raw['key'] is! String || raw['name'] is! String) _invalid();
        final List indexes = raw['indexes'] as List;
        if (indexes.any((index) => index is! int || index < 0) ||
            indexes.toSet().length != indexes.length) _invalid();
      }
      final List<QueueGroup> parts = QueueGroupsResult.from(reply.data).groups;
      for (final QueueGroup part in parts) {
        final Set<int>? indexes = part.indexes;
        if (part.key.isEmpty || indexes == null || indexes.isEmpty ||
            part.count < indexes.length) _invalid();
        for (final int index in indexes) {
          if (index >= queueCount ||
              owners.containsKey(index)) _invalid();
          owners[index] = part.key;
        }
        final QueueGroup? old = loaded[part.key];
        if (old != null && (old.name != part.name || old.count != part.count || old.start != part.start)) {
          _invalid();
        }
        final Set<int> members = <int>{...?old?.indexes, ...indexes};
        if (members.length > part.count) _invalid();
        loaded[part.key] = QueueGroup(key: part.key, name: part.name,
            count: part.count, start: part.start,
            indexes: Set<int>.unmodifiable(members));
      }
      final Object? next = reply['next'];
      if (next != null && (next is! int || next != from + parts.length || parts.isEmpty)) {
        _invalid();
      }
      if (next == null && (owners.length != queueCount ||
          loaded.values.any((g) => g.indexes!.length != g.count))) _invalid();
      onPage(List<QueueGroup>.unmodifiable(loaded.values));
      if (next == null) return;
      from = next as int;
    }
  }
}

class QueueReadCancelled implements Exception {
  const QueueReadCancelled();
}

class QueueReadFailure implements Exception {
  const QueueReadFailure(this.reply);
  final RemoteReply reply;
}
