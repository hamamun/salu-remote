// ─────────────────────────────────────────────────────────────────────────────
// COPIED FROM THE SALU PC REPO — DO NOT EDIT SEPARATELY.
//
// Source of truth:  Salu/lib/core/remote/remote_protocol.dart
// Mirrored on:      2026-09-20  (SALU remote.md v1.1, protocol version 1)
//
// This file is pure Dart by design (no Flutter, no dart:io), so both halves of
// SALU can share the exact same message rules. When the PC's copy changes, this
// copy changes in the same sitting — a drifting protocol is the one bug that
// looks like a dead Wi-Fi network.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

/// SALU Remote's wire protocol. This file deliberately has no Flutter or
/// SALU imports: the Android client and small command-line probes can copy
/// the same message rules without pulling in the desktop application.
const int protocolVersion = 1;
const int maxRemoteMessageBytes = 8192;

/// WebSocket close codes used by the PC server.
abstract final class RemoteCloseCode {
  static const int unauthorized = 4001;
  static const int versionMismatch = 4002;
  static const int notPrivateLan = 4003;
  static const int disabled = 4004;
  static const int tooManyConnections = 4005;
}

/// Error codes are strings on the wire so a newer client can still display a
/// useful fallback for an error it does not know yet.
abstract final class RemoteErrorCode {
  static const String badCode = 'bad_code';
  static const String badToken = 'bad_token';
  static const String versionMismatch = 'version_mismatch';
  static const String nothingPlaying = 'nothing_playing';
  static const String notSeekable = 'not_seekable';
  static const String unknownCommand = 'unknown_command';
  static const String tooFast = 'too_fast';
  static const String fileAccessOff = 'file_access_off';
  static const String pathNotFound = 'path_not_found';
  static const String notADirectory = 'not_a_directory';
  static const String noMedia = 'no_media';
  static const String noKey = 'no_key';
  static const String signedOut = 'signed_out';
  static const String quota = 'quota';
  static const String noPreset = 'no_preset';
  static const String noWebMedia = 'no_web_media';
  static const String busy = 'busy';
  static const String invalidArguments = 'invalid_arguments';
}

/// The one exception a protocol parser exposes to its caller.
class RemoteProtocolException implements Exception {
  const RemoteProtocolException(this.message, {this.closeCode});

  final String message;
  final int? closeCode;

  @override
  String toString() => 'RemoteProtocolException($message)';
}

/// A decoded command. Unknown fields are intentionally ignored.
class RemoteCommand {
  const RemoteCommand({
    required this.id,
    required this.verb,
    this.args = const <String, Object?>{},
  });

  final int id;
  final String verb;
  final Map<String, Object?> args;

  static RemoteCommand? tryParse(Object? raw) {
    if (raw is! Map) return null;
    if (raw['type'] != 'cmd') return null;
    final Object? rawId = raw['id'];
    final Object? rawVerb = raw['verb'];
    if (rawId is! num || rawVerb is! String || rawVerb.isEmpty) return null;
    final Object? rawArgs = raw['args'];
    final Map<String, Object?> args = <String, Object?>{};
    if (rawArgs is Map) {
      rawArgs.forEach((Object? key, Object? value) {
        if (key is String) args[key] = value;
      });
    }
    return RemoteCommand(
      id: rawId.toInt(),
      verb: rawVerb,
      args: Map<String, Object?>.unmodifiable(args),
    );
  }
}

/// Pure builders/parser for all message envelopes.
abstract final class RemoteProtocol {
  static Map<String, Object?> hello({
    required String version,
    required String name,
    required Map<String, Object?> state,
    int proto = protocolVersion,
    List<String> auth = const <String>['token', 'pair'],
    List<String> features = const <String>[
      'state',
      'queue',
      'files',
      'library',
      'tune',
      'subtitles',
      'web',
    ],
  }) => <String, Object?>{
        'type': 'hello',
        'proto': proto,
        'server': 'SALU',
        'version': version,
        'name': name,
        'auth': auth,
        'features': features,
        'state': state,
      };

  static Map<String, Object?> authByToken({
    required int id,
    required String token,
    required String deviceId,
    required String deviceName,
    String platform = 'unknown',
    int proto = protocolVersion,
  }) => _auth(
        id: id,
        proto: proto,
        credentials: <String, Object?>{'token': token},
        deviceId: deviceId,
        deviceName: deviceName,
        platform: platform,
      );

  static Map<String, Object?> authByPairingCode({
    required int id,
    required String pair,
    required String deviceId,
    required String deviceName,
    String platform = 'unknown',
    int proto = protocolVersion,
  }) => _auth(
        id: id,
        proto: proto,
        credentials: <String, Object?>{'pair': pair},
        deviceId: deviceId,
        deviceName: deviceName,
        platform: platform,
      );

  static Map<String, Object?> _auth({
    required int id,
    required int proto,
    required Map<String, Object?> credentials,
    required String deviceId,
    required String deviceName,
    required String platform,
  }) => <String, Object?>{
        'type': 'auth',
        'id': id,
        'proto': proto,
        ...credentials,
        'device': <String, Object?>{
          'id': deviceId,
          'name': deviceName,
          'platform': platform,
        },
      };

  static Map<String, Object?> authOk({
    required int id,
    required String deviceId,
    required String token,
    required String serverName,
    required String version,
    bool control = true,
    int proto = protocolVersion,
  }) => <String, Object?>{
        'type': 'auth_ok',
        'proto': proto,
        'id': id,
        'deviceId': deviceId,
        'token': token,
        'control': control,
        'server': <String, Object?>{
          'name': serverName,
          'version': version,
          'proto': proto,
        },
      };

  static Map<String, Object?> state(Map<String, Object?> snapshot) =>
      <String, Object?>{'type': 'state', ...snapshot};

  static Map<String, Object?> ack(int id, {Map<String, Object?>? result}) =>
      <String, Object?>{
        'type': 'ack',
        'proto': protocolVersion,
        'id': id,
        'ok': true,
        ...?result,
      };

  static Map<String, Object?> error(
    int id,
    String code,
    String message, {
    int? proto,
  }) => <String, Object?>{
        'type': 'error',
        'proto': proto ?? protocolVersion,
        'id': id,
        'ok': false,
        'code': code,
        'message': message,
      };

  static Map<String, Object?> result(
    int id,
    String type,
    Map<String, Object?> value,
  ) => <String, Object?>{'type': type, 'proto': protocolVersion, 'id': id, ...value};

  static Map<String, Object?> pong({
    required Object? at,
    required int serverAt,
  }) => <String, Object?>{
        'type': 'pong',
        'proto': protocolVersion,
        'at': at,
        'serverAt': serverAt,
      };

  static Map<String, Object?> decode(String text) {
    if (utf8.encode(text).length > maxRemoteMessageBytes) {
      throw const RemoteProtocolException('message exceeds 8 KB');
    }
    final Object? value;
    try {
      value = jsonDecode(text);
    } catch (_) {
      throw const RemoteProtocolException('message is not valid JSON');
    }
    if (value is! Map) {
      throw const RemoteProtocolException('message must be a JSON object');
    }
    final Map<String, Object?> out = <String, Object?>{};
    value.forEach((Object? key, Object? item) {
      if (key is String) out[key] = item;
    });
    return out;
  }

  static String encode(Map<String, Object?> message) {
    final String text = jsonEncode(message);
    if (utf8.encode(text).length > maxRemoteMessageBytes) {
      throw const RemoteProtocolException('message exceeds 8 KB');
    }
    return text;
  }

  static bool isVersion(Object? raw) => raw is num && raw.toInt() == protocolVersion;
}

/// Pure snapshot value. The server owns the values; this class only makes
/// the shape deterministic and gives tests/APK tooling a small dependency.
class RemoteSnapshot {
  RemoteSnapshot._(this._json);

  final Map<String, Object?> _json;

  /// Builds a snapshot from the named protocol fields. Unknown values are
  /// ignored and absent optional blocks remain absent. Values are copied so
  /// a notifier changing immediately after a build cannot mutate a frame.
  factory RemoteSnapshot.fromValues(Map<String, Object?> values) {
    final Map<String, Object?> out = <String, Object?>{
      'proto': protocolVersion,
      'rev': _asInt(values['rev']) ?? 0,
      'at': _asInt(values['at']) ?? DateTime.now().millisecondsSinceEpoch,
      'mode': values['mode'] == 'web' ? 'web' : 'player',
      'window': _copyMap(values['window']) ??
          <String, Object?>{
            'mode': 'full',
            'fullscreen': false,
          },
      'playback': _copyMap(values['playback']) ??
          <String, Object?>{
            'state': 'idle',
            'hasMedia': false,
            'title': null,
            'position': 0,
            'duration': 0,
            'buffering': false,
            'seekable': false,
            'volume': 100,
            'muted': false,
            'shuffle': false,
            'repeat': 'off',
          },
      'queue': _copyMap(values['queue']) ??
          <String, Object?>{
            'kind': 'empty',
            'count': 0,
            'index': -1,
          },
      'control': _copyMap(values['control']),
      'devices': _copyListOfMaps(values['devices']) ?? const <Object?>[],
    };
    for (final String key in const <String>[
      'web',
      'tracks',
      'tune',
      'subs',
      'files',
      'library',
    ]) {
      final Map<String, Object?>? block = _copyMap(values[key]);
      if (block != null) out[key] = block;
    }
    return RemoteSnapshot._(Map<String, Object?>.unmodifiable(out));
  }

  Map<String, Object?> toJson() => _json;

  String encode() => RemoteProtocol.encode(RemoteProtocol.state(_json));

  int get revision => (_json['rev'] as num?)?.toInt() ?? 0;

  static int? _asInt(Object? value) => value is num ? value.toInt() : null;

  static Map<String, Object?>? _copyMap(Object? value) {
    if (value is! Map) return null;
    final Map<String, Object?> result = <String, Object?>{};
    value.forEach((Object? key, Object? item) {
      if (key is String) result[key] = _copyValue(item);
    });
    return result;
  }

  static List<Object?>? _copyListOfMaps(Object? value) {
    if (value is! List) return null;
    return value.map<Object?>(_copyValue).toList(growable: false);
  }

  static Object? _copyValue(Object? value) {
    final Map<String, Object?>? map = _copyMap(value);
    if (map != null) return map;
    final List<Object?>? list = _copyListOfMaps(value);
    if (list != null) return list;
    return value;
  }
}

/// Returns true only for an on-wire snapshot with a strictly newer revision.
bool isNewerRemoteRevision(int revision, int lastRevision) =>
    revision > lastRevision;

String remoteJsonEncode(Map<String, Object?> message) =>
    RemoteProtocol.encode(message);

Map<String, Object?> remoteJsonDecode(String text) =>
    RemoteProtocol.decode(text);
