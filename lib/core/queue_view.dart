import 'models.dart';

/// The queue card's paint list — pure, so the accordion, the search and the
/// favourites filter are unit-testable without a widget (`test/queue_view_test.dart`).
///
/// The rules are the PC panel's rules (Salu `lib/core/channel_grouping.dart`
/// + `lib/ui/panels/playlist_panel.dart`), adapted to what the phone holds:
/// row titles and the PC's paged explicit group membership — never URLs or m3u
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
///   * **Favourites-only** shows only bookmarked channel rows, in a flat list
///     with no group heads. This also makes favourites in collapsed groups
///     visible. The phone keys favourites by title (the same last-resort key
///     the PC's own `ChannelFavouritesService.channelKey` falls back to).
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
/// channel list whose PC answered `queue_groups_page`. [openGroupKey] is the
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
  bool hideUnassigned = false,
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
  // Headers may arrive before row pages; paint them progressively too.
  if (sorted.isEmpty && !grouped) return const <QueueDisplayItem>[];

  // Flat, searching, or favourites-only — searches and favourites both
  // flatten grouped modes so a collapsed group cannot hide a matching row.
  if (!grouped || searching || favouritesOnly) {
    return <QueueDisplayItem>[
      for (final QueueRow row in sorted)
        if (visible(row)) QueueDisplayItem.row(row),
    ];
  }

  // Preserve PC descriptor order (country/language need not follow queue order).
  // Legacy start+count cannot describe scattered members: never guess.
  final List<QueueGroup> heads = groups;
  final Map<int, int> owner = <int, int>{};
  for (int h = 0; h < heads.length; h++) {
    for (final int index in heads[h].indexes ?? const <int>{}) {
      owner.putIfAbsent(index, () => h);
    }
  }
  final List<List<QueueRow>> members =
      List<List<QueueRow>>.generate(heads.length, (_) => <QueueRow>[]);
  final List<QueueRow> orphans = <QueueRow>[];
  for (final QueueRow row in sorted) {
    final int? h = owner[row.index];
    if (h == null) {
      orphans.add(row);
    } else {
      members[h].add(row);
    }
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
  for (final QueueRow row in hideUnassigned ? const <QueueRow>[] : orphans) {
    if (visible(row)) out.add(QueueDisplayItem.row(row));
  }
  return out;
}

/// Whether [row] is the current queue row. The snapshot's [queueIndex] is
/// authoritative; `queue_get`'s per-row `now` flag can be stale after the
/// queue was fetched, so it must not drive live highlighting.
bool isCurrentQueueRow(QueueRow row, int queueIndex) =>
    queueIndex >= 0 && row.index == queueIndex;

/// Finds the displayed position for the snapshot's current queue index.
/// If the row is hidden inside a collapsed group, returns that group's head;
/// stale `QueueRow.now` flags are deliberately ignored.
int findQueueCurrentDisplayIndex(
  List<QueueDisplayItem> display,
  int queueIndex,
) {
  for (int i = 0; i < display.length; i++) {
    final QueueDisplayItem item = display[i];
    if (item.isRow && isCurrentQueueRow(item.row!, queueIndex)) return i;
  }

  final List<QueueGroup> displayedGroups = <QueueGroup>[
    for (final QueueDisplayItem item in display)
      if (item.isGroup) item.group!,
  ];
  final String? key = groupKeyForIndex(displayedGroups, queueIndex);
  if (key == null) return -1;
  for (int i = 0; i < display.length; i++) {
    final QueueDisplayItem item = display[i];
    if (item.isGroup && item.group!.key == key) return i;
  }
  return -1;
}

/// The key of the group holding queue [index] — what selecting a grouped
/// mode opens (the PC's `_chooseMode`), and what a track change re-opens
/// when the playing channel sits in another group. Null when no head
/// covers the index (including [index] < 0, "nothing playing").
String? groupKeyForIndex(List<QueueGroup> groups, int index) {
  if (index < 0) return null;
  for (final QueueGroup group in groups) {
    if (group.indexes?.contains(index) ?? false) return group.key;
  }
  return null;
}
