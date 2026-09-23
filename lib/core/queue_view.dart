import 'models.dart';

/// The queue card's paint list — pure, so the accordion, the search and the
/// favourites filter are unit-testable without a widget (`test/queue_view_test.dart`).
///
/// The rules are the PC panel's rules (Salu `lib/core/channel_grouping.dart`
/// + `lib/ui/panels/playlist_panel.dart`), adapted to what the phone holds:
/// row titles and the PC's pre-computed `queue_groups` — never URLs or m3u
/// metadata (`remote.md` privacy rule).
///
///   * **Flat** (or an old PC, or a file queue): one row per queue entry.
///   * **Grouped**: the accordion — every group head paints, but only the
///     open group's channels do; the other groups' channels stay hidden
///     (autohide) until their head is tapped. A head tap toggles, it never
///     plays (PC §10.5).
///   * **A search flattens the list** whatever the mode is (PC §10.3): the
///     grouping is suspended, not forgotten — clear the search and the
///     accordion is back.
///   * **Favourites-only** thins the rows to bookmarks. Two honest
///     divergences from the PC, both forced by the privacy rule: the key is
///     the title (the same last-resort key the PC's own
///     `ChannelFavouritesService.channelKey` falls back to), and heads stay
///     put while their rows thin out — the phone cannot recompute groups,
///     so empty groups cannot vanish the way they do on the PC.
///
/// Rows and groups arrive in separate calls and can disagree for a moment
/// (a fetch racing a queue edit). A row no head owns is an **orphan**: it is
/// kept visible as a plain row after the heads, so a stale moment never
/// hides a channel instead of showing it.

/// One paintable row of the queue list: either a group head or one queue row
/// ([QueueRow.index] is the real queue index — a tap, Prev/Next and the
/// now-row all speak queue indexes, never view positions).
class QueueDisplayItem {
  const QueueDisplayItem.group(this.group) : row = null;
  const QueueDisplayItem.row(this.row) : group = null;

  final QueueGroup? group;
  final QueueRow? row;

  bool get isGroup => group != null;
  bool get isRow => row != null;
}

/// Builds the paint list for [rows] (the whole queue, any order).
///
/// [grouped] is true only when the accordion applies: a grouped mode on a
/// channel list whose PC answered `queue_groups`. [openGroupKey] is the
/// accordion's one open head (its stable PC key), or null while every group
/// is collapsed — a stale key simply opens nothing.
List<QueueDisplayItem> buildQueueDisplay({
  required List<QueueRow> rows,
  required List<QueueGroup> groups,
  required bool grouped,
  required String? openGroupKey,
  required String query,
  required bool favouritesOnly,
  required Set<String> favourites,
}) {
  final String needle = query.trim().toLowerCase();
  final bool searching = needle.isNotEmpty;

  bool visible(QueueRow row) {
    // The PC matches `name + group` for channels; the phone holds titles
    // only, so the title match is the honest subset.
    if (searching && !row.title.toLowerCase().contains(needle)) return false;
    if (favouritesOnly && !favourites.contains(row.title)) return false;
    return true;
  }

  final List<QueueRow> sorted = List<QueueRow>.from(rows)
    ..sort((QueueRow a, QueueRow b) => a.index.compareTo(b.index));
  // No rows, no list — heads without rows are a stale-groups moment, and
  // showing bare heads for an empty queue would read as a broken load.
  if (sorted.isEmpty) return const <QueueDisplayItem>[];

  // Flat — or a search, which flattens whatever the mode is.
  if (!grouped || searching) {
    return <QueueDisplayItem>[
      for (final QueueRow row in sorted)
        if (visible(row)) QueueDisplayItem.row(row),
    ];
  }

  final List<QueueGroup> heads = List<QueueGroup>.from(groups)
    ..sort((QueueGroup a, QueueGroup b) => a.start.compareTo(b.start));

  // Ownership in one pass: both lists are sorted, so each head's members
  // are the rows in [start, start+count), clipped at the next head so a
  // stale group can never swallow its neighbour's rows.
  final List<List<QueueRow>> members =
      List<List<QueueRow>>.generate(heads.length, (_) => <QueueRow>[]);
  final List<QueueRow> orphans = <QueueRow>[];
  int head = 0;
  for (final QueueRow row in sorted) {
    bool placed = false;
    while (head < heads.length && !placed) {
      if (row.index < heads[head].start) {
        break; // Before this head, and all later ones — an orphan.
      } else if (_owns(heads, head, row.index)) {
        members[head].add(row);
        placed = true;
      } else {
        head++; // Past this head's end — try the next one.
      }
    }
    if (!placed) orphans.add(row);
  }

  final List<QueueDisplayItem> out = <QueueDisplayItem>[];
  for (int h = 0; h < heads.length; h++) {
    out.add(QueueDisplayItem.group(heads[h]));
    if (heads[h].key == openGroupKey) {
      for (final QueueRow row in members[h]) {
        if (visible(row)) out.add(QueueDisplayItem.row(row));
      }
    }
  }
  for (final QueueRow row in orphans) {
    if (visible(row)) out.add(QueueDisplayItem.row(row));
  }
  return out;
}

/// The key of the group holding queue [index] — what selecting a grouped
/// mode opens (the PC's `_chooseMode`), and what a track change re-opens
/// when the playing channel sits in another group. Null when no head
/// covers the index (including [index] < 0, "nothing playing").
String? groupKeyForIndex(List<QueueGroup> groups, int index) {
  if (index < 0) return null;
  final List<QueueGroup> heads = List<QueueGroup>.from(groups)
    ..sort((QueueGroup a, QueueGroup b) => a.start.compareTo(b.start));
  for (int h = 0; h < heads.length; h++) {
    if (_owns(heads, h, index)) return heads[h].key;
  }
  return null;
}

/// Whether head [h] owns queue [index]: [start, start+count), clipped at
/// the next head's start so overlapping groups resolve to the earlier one.
bool _owns(List<QueueGroup> heads, int h, int index) {
  final QueueGroup group = heads[h];
  final int nextStart =
      h + 1 < heads.length ? heads[h + 1].start : (1 << 30);
  int end = group.start + group.count;
  if (end > nextStart) end = nextStart;
  return index >= group.start && index < end;
}
