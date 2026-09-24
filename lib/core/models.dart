import '../protocol/remote_protocol.dart';

/// Typed views over the PC's wire values.
///
/// The snapshot shape is owned by the PC (`remote.md` §6.3 + §17.5). Everything
/// here is read-only, tolerant, and total: a missing block or a renamed field
/// gives a sane default rather than an exception, because the phone must never
/// show a red screen for a field it has not learned about yet. Unknown JSON keys
/// are ignored on purpose — that is the protocol's forward-compatibility rule.

// ── small readers ───────────────────────────────────────────────────────────

double _d(Object? value) => value is num ? value.toDouble() : 0;
int _i(Object? value) => value is num ? value.toInt() : 0;
bool _b(Object? value) => value == true;
String _s(Object? value, [String fallback = '']) => value is String ? value : fallback;
String? _sn(Object? value) => value is String && value.isNotEmpty ? value : null;

Map<String, Object?> _map(Object? value) {
  if (value is! Map) return const <String, Object?>{};
  final Map<String, Object?> out = <String, Object?>{};
  value.forEach((Object? key, Object? item) {
    if (key is String) out[key] = item;
  });
  return out;
}

List<Map<String, Object?>> _maps(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  return value.map(_map).where((Map<String, Object?> m) => m.isNotEmpty).toList();
}

List<double> _gains(Object? value) {
  if (value is! List) return const <double>[];
  return value.map(_d).toList();
}

// ── enums, parsed from the PC's own names ───────────────────────────────────

enum TransportState { idle, stopped, paused, playing }
enum RepeatMode { off, all, one }
enum MediaKind { video, audio, channel }
enum QueueKind { empty, files, channels }
enum SaluMode { player, web }
enum WindowMode { full, mini }
enum TuneFileKind { audio, video }
enum UrlHealth { unknown, alive, dead }

T _enumOf<T>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final T value in values) {
    if (value.toString().split('.').last == raw) return value;
  }
  return fallback;
}

// ── the snapshot ────────────────────────────────────────────────────────────

class SaluWindow {
  const SaluWindow({this.mode = WindowMode.full, this.fullscreen = false});

  factory SaluWindow.from(Object? raw) {
    final Map<String, Object?> map = _map(raw);
    return SaluWindow(
      mode: _enumOf<WindowMode>(WindowMode.values, map['mode'], WindowMode.full),
      fullscreen: _b(map['fullscreen']),
    );
  }

  final WindowMode mode;
  final bool fullscreen;
}

class SaluPlayback {
  const SaluPlayback({
    this.state = TransportState.idle,
    this.hasMedia = false,
    this.title,
    this.kind,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffering = false,
    this.seekable = false,
    this.volume = 100,
    this.muted = false,
    this.shuffle = false,
    this.repeat = RepeatMode.off,
    this.resumePositionMs,
  });

  factory SaluPlayback.from(Object? raw) {
    final Map<String, Object?> map = _map(raw);
    // `playback.resume` — the PC's Resume toast, mirrored
    // (`remote.md` §17.4/§17.5). `null` when no toast is up, else
    // `{"position": 754000}` — presence *is* the offer.
    final Object? resumeRaw = map['resume'];
    final int? resumeMs;
    if (resumeRaw is Map && resumeRaw['position'] is num) {
      resumeMs = (resumeRaw['position'] as num).toInt();
    } else {
      resumeMs = null;
    }
    return SaluPlayback(
      state: _enumOf<TransportState>(TransportState.values, map['state'], TransportState.idle),
      hasMedia: _b(map['hasMedia']),
      title: _sn(map['title']),
      kind: map['kind'] == null
          ? null
          : _enumOf<MediaKind>(MediaKind.values, map['kind'], MediaKind.video),
      position: Duration(milliseconds: _i(map['position'])),
      duration: Duration(milliseconds: _i(map['duration'])),
      buffering: _b(map['buffering']),
      seekable: _b(map['seekable']),
      volume: _i(map['volume']).clamp(0, 100).toInt(),
      muted: _b(map['muted']),
      shuffle: _b(map['shuffle']),
      repeat: _enumOf<RepeatMode>(RepeatMode.values, map['repeat'], RepeatMode.off),
      resumePositionMs: resumeMs,
    );
  }

  final TransportState state;
  final bool hasMedia;
  final String? title;
  final MediaKind? kind;
  final Duration position;
  final Duration duration;
  final bool buffering;

  /// `duration > 0 && kind != channel` on the PC (`remote.md` §6.3) — the phone
  /// greys its seek controls on this flag alone, and never computes it itself.
  final bool seekable;
  final int volume;
  final bool muted;
  final bool shuffle;
  final RepeatMode repeat;

  /// The PC's Resume toast, mirrored (`remote.md` §17.4/§17.5).
  /// `null` when no toast is up; the resumed-at position in ms while it is.
  /// Presence *is* the offer — it makes and unmakes the phone's "Start over"
  /// seat, and the phone draws no other conclusion from it.
  final int? resumePositionMs;

  /// Whether the PC's Resume toast is currently showing — the Start over
  /// button appears on screen exactly when this is true.
  bool get hasResume => resumePositionMs != null;

  bool get isPlaying => state == TransportState.playing;
  bool get isPaused => state == TransportState.paused;
  bool get isIdle => state == TransportState.idle;

  /// SALU's Stop parks the queue: `stopped` still has media, and Play resumes it
  /// (the PC's own semantics — the phone must not re-implement this).
  bool get hasSomething => hasMedia || state != TransportState.idle;
}

enum QueueGroupingMode { flat, category, language, country }

QueueGroupingMode _groupingModeFrom(Object? raw) {
  if (raw is! String) return QueueGroupingMode.flat;
  switch (raw) {
    case 'category':
      return QueueGroupingMode.category;
    case 'language':
      return QueueGroupingMode.language;
    case 'country':
      return QueueGroupingMode.country;
    case 'flat':
    default:
      return QueueGroupingMode.flat;
  }
}

class SaluQueueGrouping {
  const SaluQueueGrouping({
    this.mode = QueueGroupingMode.flat,
    this.available = const <QueueGroupingMode>[],
  });

  factory SaluQueueGrouping.from(Object? raw) {
    if (raw is! Map) {
      return const SaluQueueGrouping();
    }
    final Map<String, Object?> map = _map(raw);
    final Object? availableRaw = map['available'];
    final List<QueueGroupingMode> available = <QueueGroupingMode>[];
    if (availableRaw is List) {
      for (final Object? item in availableRaw) {
        if (item is! String) continue;
        switch (item) {
          case 'category':
            available.add(QueueGroupingMode.category);
            break;
          case 'language':
            available.add(QueueGroupingMode.language);
            break;
          case 'country':
            available.add(QueueGroupingMode.country);
            break;
        }
      }
    }
    return SaluQueueGrouping(
      mode: _groupingModeFrom(map['mode']),
      available: List<QueueGroupingMode>.unmodifiable(available),
    );
  }

  final QueueGroupingMode mode;
  final List<QueueGroupingMode> available;

  bool get isFlat => mode == QueueGroupingMode.flat;
  bool get isGrouped => mode != QueueGroupingMode.flat;

  bool isAvailable(QueueGroupingMode m) {
    if (m == QueueGroupingMode.flat) return true;
    return available.contains(m);
  }

  String get modeWire {
    switch (mode) {
      case QueueGroupingMode.flat:
        return 'flat';
      case QueueGroupingMode.category:
        return 'category';
      case QueueGroupingMode.language:
        return 'language';
      case QueueGroupingMode.country:
        return 'country';
    }
  }
}

class SaluQueueInfo {
  const SaluQueueInfo({
    this.kind = QueueKind.empty,
    this.count = 0,
    this.index = -1,
    this.grouping = const SaluQueueGrouping(),
  });

  factory SaluQueueInfo.from(Object? raw) {
    final Map<String, Object?> map = _map(raw);
    return SaluQueueInfo(
      kind: _enumOf<QueueKind>(QueueKind.values, map['kind'], QueueKind.empty),
      count: _i(map['count']),
      index: _i(map['index']),
      grouping: SaluQueueGrouping.from(map['grouping']),
    );
  }

  final QueueKind kind;
  final int count;
  final int index;
  final SaluQueueGrouping grouping;

  bool get hasRows => count > 0;
  bool get isChannels => kind == QueueKind.channels;
}

class QueueGroup {
  const QueueGroup({
    required this.key,
    required this.name,
    required this.count,
    required this.start,
  });

  factory QueueGroup.from(Map<String, Object?> raw) => QueueGroup(
        key: _s(raw['key']),
        name: _s(raw['name'], 'Unknown'),
        count: _i(raw['count']),
        start: _i(raw['start']),
      );

  final String key;
  final String name;
  final int count;
  final int start;
}

class QueueGroupsResult {
  const QueueGroupsResult({required this.groups});

  factory QueueGroupsResult.from(Map<String, Object?> raw) {
    final Object? groupsRaw = raw['groups'];
    final List<QueueGroup> groups = <QueueGroup>[];
    if (groupsRaw is List) {
      for (final Object? item in groupsRaw) {
        if (item is Map) {
          final Map<String, Object?> map = _map(item);
          if (map.isNotEmpty) groups.add(QueueGroup.from(map));
        }
      }
    }
    return QueueGroupsResult(groups: List<QueueGroup>.unmodifiable(groups));
  }

  final List<QueueGroup> groups;
}

class SaluControl {
  const SaluControl({this.deviceId, this.name});

  factory SaluControl.from(Object? raw) {
    final Map<String, Object?> map = _map(raw);
    return SaluControl(deviceId: _sn(map['deviceId']), name: _sn(map['name']));
  }

  final String? deviceId;
  final String? name;

  bool get isEmpty => deviceId == null;
}

class SaluDevice {
  const SaluDevice({
    required this.id,
    required this.name,
    this.online = false,
    this.control = false,
  });

  factory SaluDevice.from(Object? raw) {
    final Map<String, Object?> map = _map(raw);
    return SaluDevice(
      id: _s(map['id']),
      name: _s(map['name'], 'Phone'),
      online: _b(map['online']),
      control: _b(map['control']),
    );
  }

  final String id;
  final String name;
  final bool online;
  final bool control;
}

/// The PC browser's mirror (`remote.md` §17.7). Read-only in v1.
class SaluWeb {
  const SaluWeb({
    this.title,
    this.url,
    this.canBack = false,
    this.canForward = false,
    this.loading = false,
    this.tabs = 0,
    this.tabsKnown = false,
    this.fullscreen = false,
    this.hasMedia = false,
  });

  factory SaluWeb.from(Object? raw) {
    final Map<String, Object?> map = _map(raw);
    final bool hasTabsField = map.containsKey('tabs');
    return SaluWeb(
      title: _sn(map['title']),
      url: _sn(map['url']),
      canBack: _b(map['canBack']),
      canForward: _b(map['canForward']),
      loading: _b(map['loading']),
      tabs: _i(map['tabs']),
      tabsKnown: hasTabsField,
      fullscreen: _b(map['fullscreen']),
      hasMedia: _b(map['hasMedia']),
    );
  }

  final String? title;
  final String? url;
  final bool canBack;
  final bool canForward;
  final bool loading;
  final int tabs;

  /// Whether the snapshot explicitly reported the browser's tab count.
  /// When true, [tabs] == 0 confirms there are no open tabs on the PC.
  final bool tabsKnown;

  final bool fullscreen;

  /// A boolean only — the page player's position never rides the snapshot
  /// (`remote.md` §17.5). The phone asks with `web_media_get` when it wants it.
  final bool hasMedia;

  /// Whether any tabs are open on the PC browser. When [tabsKnown] is true,
  /// [tabs] > 0 is authoritative. Otherwise falls back to whether a title or
  /// URL is present.
  bool get hasTabs => tabsKnown ? tabs > 0 : (title != null || url != null);
}

class SaluTracks {
  const SaluTracks({this.audio = 0, this.subs = 0, this.subSelected = false});

  factory SaluTracks.from(Object? raw) {
    final Map<String, Object?> map = _map(raw);
    return SaluTracks(
      audio: _i(map['audio']),
      subs: _i(map['subs']),
      subSelected: _b(map['subSelected']),
    );
  }

  final int audio;
  final int subs;
  final bool subSelected;
}

class SaluTune {
  const SaluTune({
    this.kind = TuneFileKind.video,
    this.preset,
    this.custom = false,
    this.autoEq = false,
    this.speed = 'x1',
  });

  factory SaluTune.from(Object? raw) {
    final Map<String, Object?> map = _map(raw);
    return SaluTune(
      kind: _enumOf<TuneFileKind>(TuneFileKind.values, map['kind'], TuneFileKind.video),
      preset: _sn(map['preset']),
      custom: _b(map['custom']),
      autoEq: _b(map['autoEq']),
      speed: _s(map['speed'], 'x1'),
    );
  }

  final TuneFileKind kind;
  final String? preset;
  final bool custom;
  final bool autoEq;
  final String speed;
}

class SubtitleEngine {
  const SubtitleEngine({this.key = false, this.signedIn = false, this.quotaPaused = false});

  factory SubtitleEngine.from(Object? raw) {
    final Map<String, Object?> map = _map(raw);
    return SubtitleEngine(
      key: _b(map['key']),
      signedIn: _b(map['signedIn']),
      quotaPaused: _b(map['quotaPaused']),
    );
  }

  /// The PC's own facts, so the phone can say "sign in on the PC" instead of
  /// failing silently (`remote.md` §17.3).
  final bool key;
  final bool signedIn;
  final bool quotaPaused;

  bool get ready => key && signedIn && !quotaPaused;

  String? get blocker {
    if (!key) return 'Add an OpenSubtitles key on the PC to search.';
    if (!signedIn) return 'Sign in to OpenSubtitles on the PC to download subtitles.';
    if (quotaPaused) return 'OpenSubtitles download limit reached. Try again tomorrow.';
    return null;
  }
}

class SaluSubs {
  const SaluSubs({
    this.delay = 0,
    this.lang = 'en',
    this.autoDownload = false,
    this.engine = const SubtitleEngine(),
  });

  factory SaluSubs.from(Object? raw) {
    final Map<String, Object?> map = _map(raw);
    return SaluSubs(
      delay: _d(map['delay']),
      lang: _s(map['lang'], 'en'),
      autoDownload: _b(map['autoDownload']),
      engine: SubtitleEngine.from(map['engine']),
    );
  }

  final double delay;
  final String lang;
  final bool autoDownload;
  final SubtitleEngine engine;
}

/// One pushed snapshot. Immutable; the client replaces it wholesale and ignores
/// any frame whose `rev` is not newer than the one already applied.
class SaluSnapshot {
  const SaluSnapshot({
    required this.rev,
    required this.at,
    required this.mode,
    required this.window,
    required this.playback,
    required this.queue,
    required this.control,
    required this.devices,
    required this.web,
    required this.tracks,
    required this.tune,
    required this.subs,
    this.filesEnabled = true,
    this.libraryCount = 0,
  });

  factory SaluSnapshot.from(Map<String, Object?> raw) => SaluSnapshot(
        rev: _i(raw['rev']),
        at: _i(raw['at']),
        mode: _enumOf<SaluMode>(SaluMode.values, raw['mode'], SaluMode.player),
        window: SaluWindow.from(raw['window']),
        playback: SaluPlayback.from(raw['playback']),
        queue: SaluQueueInfo.from(raw['queue']),
        control: SaluControl.from(raw['control']),
        devices: _maps(raw['devices']).map(SaluDevice.from).toList(),
        web: SaluWeb.from(raw['web']),
        tracks: SaluTracks.from(raw['tracks']),
        tune: SaluTune.from(raw['tune']),
        subs: SaluSubs.from(raw['subs']),
        filesEnabled: _map(raw['files'])['enabled'] != false,
        libraryCount: _i(_map(raw['library'])['count']),
      );

  final int rev;
  final int at;
  final SaluMode mode;
  final SaluWindow window;
  final SaluPlayback playback;
  final SaluQueueInfo queue;
  final SaluControl control;
  final List<SaluDevice> devices;
  final SaluWeb web;
  final SaluTracks tracks;
  final SaluTune tune;
  final SaluSubs subs;
  final bool filesEnabled;
  final int libraryCount;

  bool get isWeb => mode == SaluMode.web;

  /// True when nothing can be adjusted — every Tune row says the same sentence.
  bool get nothingPlaying => !playback.hasSomething;
}

// ── on-demand results (`remote.md` §17.2) ───────────────────────────────────

class QueueRow {
  const QueueRow({required this.index, required this.title, this.durationMs, this.now = false});

  factory QueueRow.from(Map<String, Object?> raw) => QueueRow(
        index: _i(raw['index']),
        title: _s(raw['title'], 'Untitled'),
        durationMs: raw['durationMs'] is num ? _i(raw['durationMs']) : null,
        now: _b(raw['now']),
      );

  final int index;
  final String title;
  final int? durationMs;
  final bool now;
}

class QueuePage {
  const QueuePage({
    required this.from,
    required this.total,
    required this.rows,
  });

  factory QueuePage.from(Map<String, Object?> raw) => QueuePage(
        from: _i(raw['from']),
        total: _i(raw['total']),
        rows: _maps(raw['rows']).map(QueueRow.from).toList(),
      );

  final int from;
  final int total;
  final List<QueueRow> rows;
}

class FsPlace {
  const FsPlace({
    required this.name,
    required this.path,
    required this.kind,
    this.medium = '',
    this.net = false,
  });

  factory FsPlace.from(Map<String, Object?> raw) => FsPlace(
        name: _s(raw['name'], '?'),
        path: _s(raw['path']),
        // drive · now_playing · downloads · videos · music · desktop
        kind: _s(raw['kind'], 'drive'),
        // drives only: fixed · removable · optical · ram ('' = older PC build)
        medium: _s(raw['medium']),
        net: _b(raw['net']),
      );

  final String name;
  final String path;
  final String kind;

  /// Drive medium the PC reported (`''` for quick places and older PCs).
  final String medium;

  /// PC flag for a network-backed place; network places are never shown.
  final bool net;

  bool get isDrive => kind == 'drive';
  bool get isNowPlaying => kind == 'now_playing';

  /// Belt-and-braces: hide anything network-backed even if a PC build sends
  /// it — an explicit `net` flag, a network kind, or a UNC path.
  bool get isNetwork =>
      net ||
      kind == 'network' ||
      kind == 'network_drive' ||
      path.startsWith(r'\\') ||
      path.startsWith('//');
}

class FsEntry {
  const FsEntry({
    required this.name,
    required this.path,
    required this.directory,
    this.size,
    this.modified,
    this.ext,
  });

  factory FsEntry.from(Map<String, Object?> raw) => FsEntry(
        name: _s(raw['name'], '?'),
        path: _s(raw['path']),
        directory: _b(raw['directory']),
        size: raw['size'] is num ? _i(raw['size']) : null,
        modified: raw['modified'] is num
            ? DateTime.fromMillisecondsSinceEpoch(_i(raw['modified']))
            : null,
        ext: _sn(raw['ext']),
      );

  final String name;
  final String path;
  final bool directory;
  final int? size;
  final DateTime? modified;
  final String? ext;

  bool get isMedia {
    final String? suffix = ext?.toLowerCase();
    if (suffix == null) return false;
    return const <String>{
      'mkv', 'mp4', 'avi', 'mov', 'wmv', 'webm', 'm4v', 'ts', 'mpg', 'mpeg', 'flv', '3gp',
      'mp3', 'flac', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'wma', 'm3u', 'm3u8',
    }.contains(suffix);
  }

  bool get isPlaylist {
    final String? suffix = ext?.toLowerCase();
    return suffix == 'm3u' || suffix == 'm3u8';
  }

  String get readableSize {
    final int? bytes = size;
    if (bytes == null || bytes <= 0) return '';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}

class FsPage {
  const FsPage({
    required this.path,
    required this.from,
    required this.count,
    required this.total,
    required this.truncated,
    required this.entries,
  });

  factory FsPage.from(Map<String, Object?> raw) => FsPage(
        path: _s(raw['path']),
        from: _i(raw['from']),
        count: _i(raw['count']),
        total: _i(raw['total']),
        // The PC caps a listing at 2000 scanned entries (§17.2) — `truncated`
        // means "there is more", and the phone says so instead of pretending.
        truncated: _b(raw['truncated']),
        entries: _maps(raw['entries']).map(FsEntry.from).toList(),
      );

  final String path;
  final int from;
  final int count;
  final int total;
  final bool truncated;
  final List<FsEntry> entries;

  bool get hasMore => from + count < total;
}

class LibraryEntryInfo {
  const LibraryEntryInfo({required this.name, required this.url, required this.health});

  factory LibraryEntryInfo.from(Map<String, Object?> raw) => LibraryEntryInfo(
        name: _s(raw['name'], 'Stream'),
        url: _s(raw['url']),
        health: _enumOf<UrlHealth>(UrlHealth.values, raw['health'], UrlHealth.unknown),
      );

  final String name;
  final String url;

  /// The PC's verdict on the URL's health — never the phone's guess.
  final UrlHealth health;
}

class LibraryInfo {
  const LibraryInfo({required this.maxEntries, required this.entries});

  factory LibraryInfo.from(Map<String, Object?> raw) => LibraryInfo(
        maxEntries: _i(raw['maxEntries']),
        entries: _maps(raw['entries']).map(LibraryEntryInfo.from).toList(),
      );

  final int maxEntries;
  final List<LibraryEntryInfo> entries;

  bool get isFull => maxEntries > 0 && entries.length >= maxEntries;
}

class TunePresetInfo {
  const TunePresetInfo({required this.key, required this.label, required this.gains});

  factory TunePresetInfo.from(Map<String, Object?> raw) => TunePresetInfo(
        key: _s(raw['key']),
        label: _s(raw['label'], 'Preset'),
        gains: _gains(raw['gains']),
      );

  final String key;
  final String label;
  final List<double> gains;
}

class TuneStop {
  const TuneStop({required this.key, required this.label});

  factory TuneStop.from(Map<String, Object?> raw) =>
      TuneStop(key: _s(raw['key']), label: _s(raw['label']));

  final String key;
  final String label;
}

/// Everything the Equalizer screen needs — asked once, never guessed
/// (`remote.md` §17.4: "the phone never guesses a preset list").
class TuneInfo {
  const TuneInfo({
    required this.kind,
    required this.available,
    required this.eq,
    this.eqStop,
    required this.custom,
    this.my,
    required this.autoPick,
    required this.autoEq,
    required this.presets,
    required this.speed,
    required this.speedValue,
    required this.speedKeys,
  });

  factory TuneInfo.from(Map<String, Object?> raw) => TuneInfo(
        kind: _enumOf<TuneFileKind>(TuneFileKind.values, raw['kind'], TuneFileKind.video),
        available: _b(raw['available']),
        eq: _gains(raw['eq']),
        eqStop: _sn(raw['eqStop']),
        custom: _b(raw['custom']),
        my: raw['my'] is List ? _gains(raw['my']) : null,
        autoPick: _b(raw['autoPick']),
        autoEq: _b(raw['autoEq']),
        presets: _maps(raw['presets']).map(TunePresetInfo.from).toList(),
        speed: _s(raw['speed'], 'x1'),
        speedValue: _d(raw['speedValue']),
        speedKeys: _maps(raw['speedKeys']).map(TuneStop.from).toList(),
      );

  final TuneFileKind kind;
  final bool available;
  final List<double> eq;
  final String? eqStop;
  final bool custom;
  final List<double>? my;
  final bool autoPick;
  final bool autoEq;
  final List<TunePresetInfo> presets;
  final String speed;
  final double speedValue;
  final List<TuneStop> speedKeys;

  static const int bandCount = 10;

  List<double> get curve {
    if (eq.length == bandCount) return eq;
    return List<double>.filled(bandCount, 0);
  }
}

bool _isGenericTrackTitle(String value) => RegExp(
      r'^(?:(?:audio|subtitle)[\s_-]+)?track(?:[\s_-]*#?[\s_-]*\d+)?$',
      caseSensitive: false,
    ).hasMatch(value.trim());

String? _trackText(Map<String, Object?> raw, List<String> keys) {
  for (final String key in keys) {
    final Object? value = raw[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

String _bestTrackTitle(Map<String, Object?> raw) {
  String? generic;
  for (final String key in <String>[
    'title',
    'label',
    'name',
    'displayName',
    'display_name',
    'trackName',
    'track_name',
  ]) {
    final String? value = _trackText(raw, <String>[key]);
    if (value == null) continue;
    generic ??= value;
    if (!_isGenericTrackTitle(value)) return value;
  }
  return generic ?? 'Track';
}

String? _trackLanguageLabel(String? language) {
  if (language == null || language.trim().isEmpty) return null;
  final String value = language.trim();
  final String code = value.toLowerCase().split(RegExp(r'[-_]')).first;
  return switch (code) {
    'en' || 'eng' => 'English',
    'es' || 'spa' => 'Spanish',
    'hi' || 'hin' => 'Hindi',
    'cmn' => 'Mandarin',
    'zh' || 'zho' || 'chi' => 'Chinese',
    'bn' || 'ben' => 'Bengali',
    'ar' || 'ara' => 'Arabic',
    'de' || 'deu' || 'ger' => 'German',
    'fr' || 'fra' || 'fre' => 'French',
    'it' || 'ita' => 'Italian',
    'ja' || 'jpn' => 'Japanese',
    'ko' || 'kor' => 'Korean',
    'pt' || 'por' => 'Portuguese',
    'ru' || 'rus' => 'Russian',
    'ta' || 'tam' => 'Tamil',
    'te' || 'tel' => 'Telugu',
    'ur' || 'urd' => 'Urdu',
    _ => value,
  };
}

class TrackInfo {
  const TrackInfo({
    required this.id,
    required this.title,
    this.lang,
    this.codec,
    this.channels,
    this.external = false,
    this.selected = false,
  });

  factory TrackInfo.from(Map<String, Object?> raw) {
    final Object? rawId =
        raw['id'] ?? raw['trackId'] ?? raw['track_id'] ?? raw['key'];
    return TrackInfo(
      id: rawId is String
          ? rawId
          : rawId is num
              ? rawId.toString()
              : '',
      title: _bestTrackTitle(raw),
      lang: _trackText(raw, <String>[
        'lang',
        'language',
        'languageName',
        'language_name',
        'languageLabel',
        'languageCode',
        'language_code',
        'langCode',
        'lang_code',
      ]),
      codec: _trackText(raw, <String>['codec', 'codecName', 'codec_name']),
      channels: _trackText(
        raw,
        <String>['channels', 'channelLayout', 'channel_layout'],
      ),
      external: raw['external'] == true ||
          raw['isExternal'] == true ||
          raw['is_external'] == true,
      selected: raw['selected'] == true ||
          raw['isSelected'] == true ||
          raw['is_selected'] == true,
    );
  }

  final String id;
  final String title;
  final String? lang;
  final String? codec;
  final String? channels;
  final bool external;
  final bool selected;

  /// Use a human language label when the PC gives only a generic track name.
  String get displayTitle {
    final String candidate = title.trim();
    if (candidate.isNotEmpty && !_isGenericTrackTitle(candidate)) {
      return candidate;
    }
    return _trackLanguageLabel(lang) ?? (candidate.isEmpty ? 'Track' : candidate);
  }

  /// "5.1 · AC3 · external" — language is already shown in [displayTitle].
  String get detail {
    final List<String> parts = <String>[];
    final String? language = _trackLanguageLabel(lang);
    if (language != null && language.toLowerCase() != displayTitle.toLowerCase()) {
      parts.add(language);
    }
    if (channels != null && channels!.isNotEmpty) parts.add(channels!);
    if (codec != null && codec!.isNotEmpty) parts.add(codec!);
    if (external) parts.add('external');
    return parts.join(' · ');
  }
}

class SubsInfo {
  const SubsInfo({
    required this.delay,
    required this.lang,
    required this.autoDownload,
    required this.engine,
    required this.audioTracks,
    required this.subTracks,
  });

  factory SubsInfo.from(Map<String, Object?> raw) {
    final Map<String, Object?> tracks = _map(raw['tracks']);
    return SubsInfo(
      delay: _d(raw['delay']),
      lang: _s(raw['lang'], 'en'),
      autoDownload: _b(raw['autoDownload']),
      engine: SubtitleEngine.from(raw['engine']),
      audioTracks: _maps(tracks['audio']).map(TrackInfo.from).toList(),
      subTracks: _maps(tracks['subs']).map(TrackInfo.from).toList(),
    );
  }

  final double delay;
  final String lang;
  final bool autoDownload;
  final SubtitleEngine engine;
  final List<TrackInfo> audioTracks;
  final List<TrackInfo> subTracks;
}

class SubtitleRow {
  const SubtitleRow({
    required this.fileId,
    required this.language,
    required this.title,
    this.release,
    this.downloads = 0,
    this.ext,
    this.subLine,
  });

  factory SubtitleRow.from(Map<String, Object?> raw) => SubtitleRow(
        fileId: _i(raw['fileId']),
        language: _s(raw['language'], '?'),
        title: _s(raw['title'], 'Subtitle'),
        release: _sn(raw['release']),
        downloads: _i(raw['downloads']),
        ext: _sn(raw['ext']),
        subLine: _sn(raw['subLine']),
      );

  final int fileId;
  final String language;
  final String title;
  final String? release;
  final int downloads;
  final String? ext;

  /// The PC's own formatting (`SubtitleResult.subLine`), used verbatim.
  final String? subLine;
}

class SubtitleSaveResult {
  const SubtitleSaveResult({required this.loaded, this.fileName});

  factory SubtitleSaveResult.from(Map<String, Object?> raw) => SubtitleSaveResult(
        loaded: _b(raw['loaded']),
        fileName: _sn(raw['fileName']),
      );

  final bool loaded;
  final String? fileName;
}

// ── the page's own player (`remote.md` §17.11) ──────────────────────────────

/// The unit the PC's web-media bridge spoke in for a time value.
///
/// The contract (`remote.md` §17.4) is **milliseconds** — the house unit of
/// every other time on the wire (`playback.position`, `seek_to`, `seek_by`).
/// But §17.11's read is JavaScript's `el.currentTime`, which is **seconds**,
/// and a bridge that hands that straight back speaks seconds. Getting this
/// wrong is invisible in every other control and catastrophic in two: the
/// clock under the seek bar reads 1000× off, and a seek lands 1000× off.
///
/// So the phone never guesses from the *size* of a number — a 45-minute video
/// is `2700` in seconds and `2700000` in milliseconds, and both look like a
/// plausible duration. It takes the PC's word when the PC gives one (a `unit`
/// field in the reply, or `web_media_unit` in `hello.features`) and otherwise
/// uses the one reliable tell: **a fractional number can only be
/// `currentTime` in seconds**, because every millisecond count in this
/// protocol is an integer.
enum WebTimeUnit { milliseconds, seconds }

/// The unit the PC spoke for the page player's volume: the contract's integer
/// **percent** (0–100) or JavaScript's own **fraction** (0–1).
enum WebVolumeUnit { percent, fraction }

/// The units one `web_media_get` reply was spoken in, so a seek can be written
/// back in the same voice it was read in.
///
/// Volume is deliberately *not* written through this: §17.11 states the write
/// side as `element.volume = percent/100`, so `web_media_volume` carries a
/// percent even from a PC that reports a fraction on the way out.
class WebMediaDialect {
  const WebMediaDialect({
    this.time = WebTimeUnit.milliseconds,
    this.volume = WebVolumeUnit.percent,
  });

  /// The contract: milliseconds and integer percent (`remote.md` §17.4).
  static const WebMediaDialect contract = WebMediaDialect();

  final WebTimeUnit time;
  final WebVolumeUnit volume;

  bool get timeIsSeconds => time == WebTimeUnit.seconds;

  /// The wire number for a time. Seconds keep their fraction — `currentTime`
  /// is not a whole-second clock, and rounding it would make a live seek
  /// visibly step.
  num timeValue(Duration value) =>
      timeIsSeconds ? value.inMilliseconds / 1000 : value.inMilliseconds;

  @override
  bool operator ==(Object other) =>
      other is WebMediaDialect && other.time == time && other.volume == volume;

  @override
  int get hashCode => Object.hash(time, volume);

  @override
  String toString() =>
      'time ${timeIsSeconds ? 's' : 'ms'} · volume ${volume == WebVolumeUnit.fraction ? '0–1' : '%'}';
}

/// One `web_media_get` reply, in the phone's own units.
///
/// Times come out as [Duration]s and volume as an integer percent whatever the
/// PC spoke; [dialect] remembers what that was, because the seek has to go
/// back the same way. [raw] keeps the PC's own words for the Web body's
/// diagnostics sheet — the one place a unit question is answered by looking
/// rather than by guessing.
class WebMediaInfo {
  const WebMediaInfo({
    this.found = false,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 100,
    this.muted = false,
    this.canFullscreen = false,
    this.fullscreen = false,
    this.seekable = false,
    this.dialect = WebMediaDialect.contract,
    this.raw = const <String, Object?>{},
  });

  /// The empty reading — no media found on the active page or tab.
  static const WebMediaInfo none = WebMediaInfo(found: false);

  /// [contractUnits] is the PC's own promise — `web_media_unit` in
  /// `hello.features` — and outranks everything except an explicit `unit`
  /// field in the reply.
  factory WebMediaInfo.from(Map<String, Object?> raw, {bool contractUnits = false}) {
    final Object? rawPosition = _webNum(raw, 'position', 'time', 'currentTime');
    final Object? rawDuration = _webNum(raw, 'duration', 'length');
    final Object? rawVolume = _webNum(raw, 'volume', 'vol');
    final WebTimeUnit timeUnit =
        _webTimeUnit(raw, contractUnits, rawPosition, rawDuration);
    final WebVolumeUnit volumeUnit = _webVolumeUnit(raw, contractUnits, rawVolume);
    final Duration position = _webDuration(rawPosition, timeUnit);
    final Duration duration = _webDuration(rawDuration, timeUnit);
    final Object? rawSeekable = raw['seekable'];
    return WebMediaInfo(
      found: _b(raw['found']),
      playing: _b(raw['playing']),
      position: position,
      duration: duration,
      volume: _webPercent(rawVolume, volumeUnit),
      muted: _b(raw['muted']),
      canFullscreen: _b(raw['canFull']) || _b(raw['canFullscreen']),
      // The element's *current* fullscreen state, when the PC reports it: the
      // fullscreen seat's icon reads this (plus the snapshot's `web.fullscreen`
      // and `window.fullscreen`), so the mark is never a guess.
      fullscreen: _b(raw['fullscreen']) || _b(raw['isFullscreen']),
      // The PC may say so outright; otherwise a page player is seekable
      // exactly when it knows how long it is — a live stream never does.
      seekable: rawSeekable is bool ? rawSeekable : duration > Duration.zero,
      dialect: WebMediaDialect(time: timeUnit, volume: volumeUnit),
      raw: Map<String, Object?>.unmodifiable(raw),
    );
  }

  final bool found;
  final bool playing;
  final Duration position;
  final Duration duration;

  /// Integer percent, 0–100 — whatever the PC spoke.
  final int volume;
  final bool muted;
  final bool canFullscreen;

  /// Whether the page's player is in element fullscreen *right now*
  /// (`web_media_get`'s `fullscreen`). A PC that does not send it leaves this
  /// false and the phone falls back to the snapshot's `web.fullscreen`.
  final bool fullscreen;
  final bool seekable;
  final WebMediaDialect dialect;

  /// The PC's reply, verbatim, for the diagnostics sheet.
  final Map<String, Object?> raw;

  /// Equal when everything the *screen* draws is equal. [raw] is left out on
  /// purpose: the Web body polls once a second and must not rebuild for a
  /// reply that says the same thing in the same units.
  @override
  bool operator ==(Object other) =>
      other is WebMediaInfo &&
      other.found == found &&
      other.playing == playing &&
      other.position == position &&
      other.duration == duration &&
      other.volume == volume &&
      other.muted == muted &&
      other.canFullscreen == canFullscreen &&
      other.fullscreen == fullscreen &&
      other.seekable == seekable &&
      other.dialect == dialect;

  @override
  int get hashCode => Object.hash(
        found,
        playing,
        position,
        duration,
        volume,
        muted,
        canFullscreen,
        fullscreen,
        seekable,
        dialect,
      );
}

/// The first of the named keys that holds a number — the contract's own name
/// first, then the two a JavaScript-shaped reply might use instead. A bridge
/// that answers `{currentTime: 12.3}` rather than `{position: 12.3}` still
/// reads correctly instead of silently reporting `0:00`; the canonical names
/// remain the contract (`remote.md` §17.4).
///
/// A number that arrives as a *string* is parsed too. `executeScript` hands the
/// PC whatever the page's JavaScript returned, and one `toString()` on the way
/// through a plugin would otherwise cost the user a seek bar with nothing on
/// screen to explain why.
Object? _webNum(Map<String, Object?> raw, String key, String alt, [String? alt2]) {
  for (final String name in <String>[key, alt, ?alt2]) {
    final Object? value = raw[name];
    if (value is num) return value;
    if (value is String) {
      final double? parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return raw[key];
}

bool _webFractional(Object? value) {
  if (value is! num) return false;
  final double number = value.toDouble();
  return number.isFinite && number != number.truncateToDouble();
}

WebTimeUnit _webTimeUnit(
  Map<String, Object?> raw,
  bool contractUnits,
  Object? position,
  Object? duration,
) {
  final Object? stated = raw['unit'] ?? raw['timeUnit'];
  if (stated is String) {
    final String unit = stated.trim().toLowerCase();
    if (const <String>['s', 'sec', 'secs', 'second', 'seconds'].contains(unit)) {
      return WebTimeUnit.seconds;
    }
    if (const <String>['ms', 'milli', 'millis', 'millisecond', 'milliseconds']
        .contains(unit)) {
      return WebTimeUnit.milliseconds;
    }
  }
  if (contractUnits) return WebTimeUnit.milliseconds;
  if (_webFractional(duration) || _webFractional(position)) return WebTimeUnit.seconds;
  return WebTimeUnit.milliseconds;
}

Duration _webDuration(Object? value, WebTimeUnit unit) {
  if (value is! num) return Duration.zero;
  final double raw = value.toDouble();
  // A live stream reports `Infinity` and an unloaded element `NaN`. Neither
  // survives JSON, and neither means "seekable" — both read as "unknown".
  if (!raw.isFinite || raw <= 0) return Duration.zero;
  final int ms = unit == WebTimeUnit.seconds ? (raw * 1000).round() : raw.round();
  return Duration(milliseconds: ms);
}

WebVolumeUnit _webVolumeUnit(
  Map<String, Object?> raw,
  bool contractUnits,
  Object? volume,
) {
  final Object? stated = raw['volumeUnit'];
  if (stated is String) {
    final String unit = stated.trim().toLowerCase();
    if (const <String>['fraction', 'ratio', '0-1', '0..1'].contains(unit)) {
      return WebVolumeUnit.fraction;
    }
    if (const <String>['percent', '%', '0-100'].contains(unit)) {
      return WebVolumeUnit.percent;
    }
  }
  if (contractUnits) return WebVolumeUnit.percent;
  // Anything inside 0…1 is JavaScript's `el.volume`. That reads a contract
  // percent of exactly 1 as 100% — a trade worth making, because nobody sets
  // 1% and `el.volume === 1` is every page's default.
  if (volume is num) {
    final double raw = volume.toDouble();
    if (raw.isFinite && raw >= 0 && raw <= 1) return WebVolumeUnit.fraction;
  }
  return WebVolumeUnit.percent;
}

int _webPercent(Object? volume, WebVolumeUnit unit) {
  if (volume is! num) return 100;
  final double raw = volume.toDouble();
  if (!raw.isFinite) return 100;
  final double percent = unit == WebVolumeUnit.fraction ? raw * 100 : raw;
  return percent.round().clamp(0, 100).toInt();
}

// ── the browser's tabs, bookmarks and focus (`remote.md` §17.7, §17.13) ─────

/// One open tab in the PC's browser, as the PC reports it. The list never
/// rides the snapshot — it is one `web_tabs_get` away, because a strip of 40
/// tabs is bigger than the whole 8 KB frame budget.
class WebTabInfo {
  const WebTabInfo({
    required this.index,
    required this.title,
    required this.url,
    this.active = false,
    this.loading = false,
    this.hasMedia = false,
  });

  factory WebTabInfo.from(Map<String, Object?> raw) => WebTabInfo(
        index: _i(raw['index']),
        title: _sn(raw['title']) ?? _sn(raw['url']) ?? 'Untitled tab',
        url: _s(raw['url']),
        active: _b(raw['active']),
        loading: _b(raw['loading']),
        hasMedia: _b(raw['hasMedia']),
      );

  final int index;
  final String title;
  final String url;
  final bool active;
  final bool loading;

  /// The PC's own verdict on whether this tab has a reachable player.
  final bool hasMedia;
}

/// `web_tabs_get` — the whole strip plus which seat is live.
class WebTabPage {
  const WebTabPage({required this.tabs, this.activeIndex = -1, this.count = 0});

  factory WebTabPage.from(Map<String, Object?> raw) {
    final List<WebTabInfo> tabs =
        _maps(raw['tabs']).map(WebTabInfo.from).toList(growable: false);
    final Object? rawActive = raw['active'] ?? raw['activeIndex'];
    int active = rawActive is num ? rawActive.toInt() : -1;
    if (active < 0) {
      // No index from the PC: the row it marked active is the answer.
      for (final WebTabInfo tab in tabs) {
        if (tab.active) {
          active = tab.index;
          break;
        }
      }
    }
    return WebTabPage(
      tabs: tabs,
      activeIndex: active,
      count: raw['count'] is num ? _i(raw['count']) : tabs.length,
    );
  }

  final List<WebTabInfo> tabs;
  final int activeIndex;

  /// What the snapshot's `web.tabs` says — kept so a truncated list can still
  /// be honest about the real total.
  final int count;

  bool get isEmpty => tabs.isEmpty;

  bool isActive(WebTabInfo tab) => tab.active || tab.index == activeIndex;
}

/// One bookmarked page in the PC's browser (`web_bookmarks_get`, read-only).
class WebBookmarkInfo {
  const WebBookmarkInfo({required this.name, required this.url, this.folder = ''});

  factory WebBookmarkInfo.from(Map<String, Object?> raw) => WebBookmarkInfo(
        name: _sn(raw['name']) ?? _sn(raw['title']) ?? _sn(raw['url']) ?? 'Bookmark',
        url: _s(raw['url']),
        folder: _s(raw['folder']),
      );

  final String name;
  final String url;
  final String folder;
}

/// The bookmark list out of a `web_bookmarks_get` reply. The PC may key it
/// `entries` or `bookmarks`; either way a missing or malformed list reads as
/// an empty one, never as an exception.
List<WebBookmarkInfo> webBookmarksFrom(Map<String, Object?> raw) =>
    _maps(raw['entries'] ?? raw['bookmarks'])
        .map(WebBookmarkInfo.from)
        .toList(growable: false);

/// What the page has focused right now, so the keys the phone sends into the
/// page (`web_key` — the mouse pad's Enter, and the PC's own Esc path) are not
/// sent blind (`remote_apk_ui.md` §6.0, `remote.md` §17.14). Rides the
/// `web_key` ack and `web_focus_get`.
class WebFocusInfo {
  const WebFocusInfo({
    this.label,
    this.tag,
    this.index = 0,
    this.count = 0,
    this.editable = false,
  });

  factory WebFocusInfo.from(Object? raw) {
    final Map<String, Object?> map = _map(raw);
    if (map.isEmpty) return const WebFocusInfo();
    return WebFocusInfo(
      label: _sn(map['label']) ?? _sn(map['text']),
      tag: _sn(map['tag'])?.toUpperCase(),
      index: _i(map['index']),
      count: _i(map['count']),
      editable: _b(map['editable']) || _b(map['isInput']),
    );
  }

  final String? label;
  final String? tag;
  final int index;
  final int count;

  /// A text field has the focus: the arrows belong to the caret and OK
  /// submits rather than clicks (`remote_apk_ui.md` §6.0).
  final bool editable;

  bool get known => label != null || tag != null;

  /// The one line under the pad: `Subscribe · BUTTON · 4 of 120`.
  String get line {
    final List<String> parts = <String>[
      ?label,
      ?tag,
      if (count > 0) '${index + 1} of $count',
    ];
    if (parts.isEmpty) return 'Nothing focused yet';
    return parts.join(' · ');
  }
}

/// `hello` — the server's identity, sent before auth.
class ServerInfo {
  const ServerInfo({
    required this.name,
    required this.version,
    this.proto = protocolVersion,
    this.features = const <String>[],
  });

  factory ServerInfo.from(Map<String, Object?> raw) => ServerInfo(
        name: _s(raw['name'], 'Your PC'),
        version: _s(raw['version'], '0.1.0'),
        proto: _i(raw['proto']),
        features: raw['features'] is List
            ? (raw['features'] as List<Object?>).whereType<String>().toList()
            : const <String>[],
      );

  final String name;
  final String version;
  final int proto;
  final List<String> features;

  /// The PC's name, cleaned for a header: "DESKTOP-ABC" reads badly next to a
  /// green dot, so the tail after the last dash wins when it looks like a name.
  String get shortName {
    final String value = name.trim();
    if (value.isEmpty) return 'Your PC';
    return value;
  }
}

/// The `hello.features` names this build of the phone understands.
///
/// A feature is a **promise the PC makes about itself**, and the phone draws
/// only what has been promised: an unadvertised verb is a dead button, and a
/// dead button is the fastest way to make an app feel broken
/// (`remote_apk_ui.md` §4.2). Everything here is additive — `proto` stays 1 —
/// so an older PC and a newer phone still talk, with fewer buttons.
///
/// The PC side of each promise is a work package in `pc_part.md`.
abstract final class RemoteFeature {
  /// `web_media_get` speaks the contract — milliseconds and integer percent —
  /// and says so with a `unit` field. Without it the phone reads the units off
  /// the reply itself ([WebMediaInfo.from]).
  static const String webMediaUnit = 'web_media_unit';

  /// Keys into the page, with the ring drawn on whatever holds the focus:
  /// `web_key` and `web_focus_get` (`remote_apk_ui.md` §6.0). The D-pad that
  /// used these is gone (2026-09-24) — the mouse pad's double tap is still
  /// `Enter`, and the ring is still what makes the PC's focus visible.
  static const String webKey = 'web_key';

  /// The browser's tab strip, mirrored: `web_tabs_get`, `web_tab_activate`,
  /// `web_tab_close`, `web_tab_new` (`remote.md` §17.7).
  static const String webTabs = 'web_tabs';

  /// The browser's bookmarked pages, read-only: `web_bookmarks_get`
  /// (`remote.md` §17.13).
  static const String webBookmarks = 'web_bookmarks';

  // ── added 2026-09-24 (the user's five web complaints + the mouse) ─────────

  /// A working **Home** button: `browser_nav {action:"home"}` takes the loaded
  /// page to its own site's front page in the *same* tab (`remote.md` §17.14).
  /// Without it the phone falls back to the URL the site's origin implies.
  static const String webHome = 'web_home';

  /// **One fullscreen button, and the PC decides**: `web_fullscreen` puts the
  /// page's own player fullscreen when there is one, the SALU window when
  /// there is not, and answers which it did (§17.14). Without it the phone
  /// keeps choosing between `web_media_fullscreen` and `fullscreen_toggle`
  /// itself — the split that made YouTube do nothing and other streams
  /// fullscreen the whole app.
  static const String webFullscreen = 'web_fullscreen';

  /// The **trackpad**: `web_mouse_move` / `web_mouse_click` move and click the
  /// PC's own pointer (§17.14). Without it the Tune tab's pad is inert and
  /// says so in its one line.
  static const String webMouse = 'web_mouse';

  /// **Add-only bookmarking**: `web_bookmark_add` appends the page being looked
  /// at to the PC browser's bookmarks. Never a rename, never a delete — a phone
  /// that can rewrite the bookmark bar can lose it (§17.13.4). Without it
  /// "Save this page" writes into SALU's own saved list instead.
  static const String webBookmarkAdd = 'web_bookmark_add';

  /// Every name above, for the diagnostics sheet — the phone says which of
  /// its own doors the PC has opened.
  static const List<String> all = <String>[
    webMediaUnit,
    webKey,
    webTabs,
    webBookmarks,
    webHome,
    webFullscreen,
    webMouse,
    webBookmarkAdd,
  ];
}
