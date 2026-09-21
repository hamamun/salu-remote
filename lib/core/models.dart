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
  });

  factory SaluPlayback.from(Object? raw) {
    final Map<String, Object?> map = _map(raw);
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
      volume: _i(map['volume']).clamp(0, 100),
      muted: _b(map['muted']),
      shuffle: _b(map['shuffle']),
      repeat: _enumOf<RepeatMode>(RepeatMode.values, map['repeat'], RepeatMode.off),
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

  bool get isPlaying => state == TransportState.playing;
  bool get isPaused => state == TransportState.paused;
  bool get isIdle => state == TransportState.idle;

  /// SALU's Stop parks the queue: `stopped` still has media, and Play resumes it
  /// (the PC's own semantics — the phone must not re-implement this).
  bool get hasSomething => hasMedia || state != TransportState.idle;
}

class SaluQueueInfo {
  const SaluQueueInfo({this.kind = QueueKind.empty, this.count = 0, this.index = -1});

  factory SaluQueueInfo.from(Object? raw) {
    final Map<String, Object?> map = _map(raw);
    return SaluQueueInfo(
      kind: _enumOf<QueueKind>(QueueKind.values, map['kind'], QueueKind.empty),
      count: _i(map['count']),
      index: _i(map['index']),
    );
  }

  final QueueKind kind;
  final int count;
  final int index;

  bool get hasRows => count > 0;
  bool get isChannels => kind == QueueKind.channels;
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
    this.fullscreen = false,
    this.hasMedia = false,
  });

  factory SaluWeb.from(Object? raw) {
    final Map<String, Object?> map = _map(raw);
    return SaluWeb(
      title: _sn(map['title']),
      url: _sn(map['url']),
      canBack: _b(map['canBack']),
      canForward: _b(map['canForward']),
      loading: _b(map['loading']),
      tabs: _i(map['tabs']),
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
  final bool fullscreen;

  /// A boolean only — the page player's position never rides the snapshot
  /// (`remote.md` §17.5). The phone asks with `web_media_get` when it wants it.
  final bool hasMedia;
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
  const FsPlace({required this.name, required this.path, required this.kind});

  factory FsPlace.from(Map<String, Object?> raw) => FsPlace(
        name: _s(raw['name'], '?'),
        path: _s(raw['path']),
        // drive · now_playing · downloads · videos · music · desktop
        kind: _s(raw['kind'], 'drive'),
      );

  final String name;
  final String path;
  final String kind;

  bool get isDrive => kind == 'drive';
  bool get isNowPlaying => kind == 'now_playing';
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

  factory TrackInfo.from(Map<String, Object?> raw) => TrackInfo(
        id: _s(raw['id']),
        title: _s(raw['title'], 'Track'),
        lang: _sn(raw['lang']),
        codec: _sn(raw['codec']),
        channels: _sn(raw['channels']),
        external: _b(raw['external']),
        selected: _b(raw['selected']),
      );

  final String id;
  final String title;
  final String? lang;
  final String? codec;
  final String? channels;
  final bool external;
  final bool selected;

  /// "English · 5.1 AC3 (external)" — the row's one honest line.
  String get detail {
    final List<String> parts = <String>[];
    if (lang != null && lang!.isNotEmpty) parts.add(lang!);
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

class WebMediaInfo {
  const WebMediaInfo({
    this.found = false,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 100,
    this.muted = false,
    this.canFullscreen = false,
  });

  factory WebMediaInfo.from(Map<String, Object?> raw) => WebMediaInfo(
        found: _b(raw['found']),
        playing: _b(raw['playing']),
        position: Duration(milliseconds: (_d(raw['position']) * 1000).round()),
        duration: Duration(milliseconds: (_d(raw['duration']) * 1000).round()),
        volume: (_d(raw['volume']) * 100).round().clamp(0, 100),
        muted: _b(raw['muted']),
        canFullscreen: _b(raw['canFull']),
      );

  final bool found;
  final bool playing;
  final Duration position;
  final Duration duration;
  final int volume;
  final bool muted;
  final bool canFullscreen;
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
