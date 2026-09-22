import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../protocol/remote_protocol.dart';
import 'connect_failure.dart';
import 'models.dart';
import 'prefs.dart';
import 'reply.dart';

/// What the phone believes about the link. One notifier, so the header dot, the
/// Connect sheet and the offline bodies can never disagree.
enum LinkState {
  /// Nothing has been tried yet.
  idle,

  /// Opening the socket, or waiting for `auth_ok`.
  connecting,

  /// Authenticated: snapshots are flowing.
  online,

  /// The PC refused our credentials (`bad_code` / `bad_token`). Only the user
  /// can fix this — reconnecting in a loop would just hide the problem.
  needsPairing,

  /// Socket down, retrying with backoff. This is the normal state when the PC
  /// sleeps or the phone changes network.
  unreachable,

  /// Deliberately disconnected by the user.
  off,
}

extension LinkStateCopy on LinkState {
  bool get isLive => this == LinkState.online;

  /// The header dot's own line.
  String get label {
    switch (this) {
      case LinkState.idle:
        return 'Not connected';
      case LinkState.connecting:
        return 'Connecting…';
      case LinkState.online:
        return 'Connected';
      case LinkState.needsPairing:
        return 'Not paired';
      case LinkState.unreachable:
        return 'Reconnecting…';
      case LinkState.off:
        return 'Disconnected';
    }
  }
}

/// The one connection to the PC (`remote.md` §4, §7).
///
/// Responsibilities, and deliberately nothing else:
///   * one WebSocket, opened to `ws://host:port`, `hello` → `auth` → `auth_ok`;
///   * the reconnect loop (backoff, and *no* loop when the PC refused us);
///   * the ping/pong clock that measures latency and notices a dead link;
///   * a request/reply table so `cmd` ids never leak into the UI;
///   * the latest [SaluSnapshot], with `rev` monotonicity enforced.
///
/// The UI reads notifiers and calls verbs. It never touches a socket, never
/// builds JSON, and never decides what a verb means.
class SaluClient {
  SaluClient._();

  static final SaluClient instance = SaluClient._();

  // ── what the UI watches ───────────────────────────────────────────────────

  final ValueNotifier<LinkState> link = ValueNotifier<LinkState>(LinkState.idle);
  final ValueNotifier<ServerInfo?> server = ValueNotifier<ServerInfo?>(null);
  final ValueNotifier<SaluSnapshot?> snapshot = ValueNotifier<SaluSnapshot?>(null);

  /// The PC's own error code and sentence when the link itself failed
  /// (`bad_token`, `version_mismatch`, …). Command failures never land here —
  /// they come back as the failed [RemoteReply] of that one call.
  final ValueNotifier<String?> problemCode = ValueNotifier<String?>(null);
  final ValueNotifier<String?> problemMessage = ValueNotifier<String?>(null);

  /// Round-trip time from the last ping, for the Connect sheet's diagnostics.
  final ValueNotifier<int?> latencyMs = ValueNotifier<int?>(null);

  /// Commands in flight — the Play header's activity dot (`remote_apk_ui.md`
  /// §4.1). It appears only after 300 ms, so a fast call never flickers.
  final ValueNotifier<int> inFlight = ValueNotifier<int>(0);

  /// The address we are using, for the header's subtitle.
  final ValueNotifier<String?> address = ValueNotifier<String?>(null);

  // ── socket plumbing ───────────────────────────────────────────────────────

  WebSocket? _socket;
  StreamSubscription<Object?>? _events;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _handshakeTimer;
  DateTime? _pingSentAt;
  bool _authenticated = false;

  /// Whether *this* socket has received `hello` yet — [server] keeps the last
  /// PC's details across reconnects for the header, so it cannot answer that.
  bool _sawHello = false;
  bool _wanted = false;
  String? _host;
  int? _port;
  String? _pairingCode;
  int _attempt = 0;

  /// Bumped by every `_open()` and `_teardown()`. A socket that finishes
  /// opening after the user has moved on (Connect pressed twice, the address
  /// changed, Disconnect tapped) belongs to an older generation and is closed
  /// instead of adopted — otherwise two live sockets would fight over
  /// [_socket] and the loser's `onDone` would clobber the winner's state.
  int _generation = 0;

  /// `auth` uses id 1 (`remote.md` §6.1); commands start above it so an
  /// auth error can never be mistaken for a command reply.
  int _nextId = 2;
  final Map<int, Completer<RemoteReply>> _pending = <int, Completer<RemoteReply>>{};

  /// How long the TCP + WebSocket upgrade may take. On a LAN a live PC
  /// answers in milliseconds; a *silently dropped* SYN (Windows Firewall, AP
  /// isolation, wrong subnet) is the one case that runs the full clock.
  static const Duration _connectTimeout = Duration(seconds: 8);

  /// How long after the upgrade the PC has to say `hello` and answer `auth`.
  /// The PC sends `hello` in the same breath as the upgrade and closes an
  /// unauthenticated socket after 5 s, so anything slower than this is not a
  /// SALU we can talk to — a half-open socket, or another program on the port.
  static const Duration _handshakeTimeout = Duration(seconds: 6);

  bool get isOnline => link.value == LinkState.online;
  bool get hasControl =>
      snapshot.value?.control.deviceId != null &&
      snapshot.value!.control.deviceId == RemotePrefs.instance.deviceId;
  String? get host => _host;
  int? get port => _port;

  /// Codes that mean "the user has to do something", not "try again".
  static const Set<String> _noRetryCodes = <String>{
    'bad_code',
    'bad_token',
    'version_mismatch',
    'auth_timeout',
    'auth_required',
    'auth_failed',
    'not_paired',
  };

  // ── lifecycle ─────────────────────────────────────────────────────────────

  /// Called once from `main()` after prefs are loaded. Reconnects to the
  /// remembered PC if there is one; otherwise stays idle and the Connect sheet
  /// takes over.
  Future<void> autoConnect() async {
    final RemotePrefs prefs = RemotePrefs.instance;
    if (!prefs.isPaired) return;
    await connect(host: prefs.host!, port: prefs.port!);
  }

  /// Opens the socket. [code] is only needed for the very first pairing.
  ///
  /// A code typed (or scanned) always goes on the wire, even when this phone
  /// still holds a token: the person in front of the PC's panel knows better
  /// than a stored credential. The token itself is left alone until the PC
  /// says it is dead (`bad_token`) or replaces it (`auth_ok`), so a mistyped
  /// code never costs a pairing that was still good.
  Future<void> connect({
    required String host,
    required int port,
    String? code,
  }) async {
    await _teardown();
    _host = host.trim();
    _port = port;
    final String? normalized = code == null ? null : _normalizeCode(code);
    _pairingCode = normalized == null || normalized.isEmpty ? null : normalized;
    _wanted = true;
    _attempt = 0;
    _clearProblem();
    address.value = '$_host:$_port';
    final RemotePrefs prefs = RemotePrefs.instance;
    await prefs.rememberAddress(_host!, port);
    if (_pairingCode == null && prefs.token == null) {
      // Nothing to authenticate with. Dialling anyway would only earn a
      // `bad_code` from the PC — a confusing answer to a code nobody typed.
      problemCode.value = 'not_paired';
      problemMessage.value = 'This phone is not paired yet. Scan the QR in the '
          "PC's Remote panel, or type the pairing code shown under it.";
      link.value = LinkState.needsPairing;
      _wanted = false;
      return;
    }
    link.value = LinkState.connecting;
    await _open();
  }

  /// Reconnect to whatever `prefs` remembers — the header's refresh button.
  ///
  /// A pairing code that is still in hand (the token never arrived, so the
  /// code was not consumed) is reused; once `auth_ok` has replaced it with a
  /// token the code is gone and the token is what goes on the wire.
  Future<void> reconnectRemembered() async {
    final RemotePrefs prefs = RemotePrefs.instance;
    final String? code = prefs.token == null ? _pairingCode : null;
    if (_host != null && _port != null) {
      await connect(host: _host!, port: _port!, code: code);
      return;
    }
    if (prefs.isPaired) {
      await connect(host: prefs.host!, port: prefs.port!);
    }
  }

  /// The user's own off switch. [forget] also drops the token.
  Future<void> disconnect({bool forget = false}) async {
    _wanted = false;
    await _teardown();
    link.value = LinkState.off;
    if (forget) {
      await RemotePrefs.instance.forgetPc();
      snapshot.value = null;
      server.value = null;
      address.value = null;
      _host = null;
      _port = null;
    }
  }

  /// Android lifecycle resume (and the app's own "the phone just woke up"
  /// path): ask for a fresh snapshot immediately and nudge a dead socket.
  Future<void> onResume() async {
    if (_socket != null && _authenticated) {
      // Cheap, and it makes the first frame after a wake correct instead of
      // stale for up to 250 ms (`remote.md` §9 `state_get`).
      await send('state_get', timeout: const Duration(seconds: 4));
      return;
    }
    if (_wanted) {
      _attempt = 0;
      _reconnectTimer?.cancel();
      await _open();
    }
  }

  Future<void> _teardown() async {
    _generation++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _stopPing();
    _authenticated = false;
    final StreamSubscription<Object?>? events = _events;
    _events = null;
    final WebSocket? socket = _socket;
    _socket = null;
    _failPending(RemoteReply.offline());
    try {
      await events?.cancel();
      await socket?.close();
    } catch (_) {
      // A socket that is already gone is not an error worth surfacing.
    }
  }

  // ── the socket itself ─────────────────────────────────────────────────────

  Future<void> _open() async {
    if (!_wanted || _host == null || _port == null) return;
    if (_socket != null) return; // One socket at a time, always.
    if (link.value != LinkState.online) link.value = LinkState.connecting;
    final String host = _host!;
    final int port = _port!;
    final int generation = ++_generation;
    debugPrint('[SALU remote] connecting to ws://$host:$port/ (attempt ${_attempt + 1})');
    final Future<WebSocket> opening = WebSocket.connect('ws://$host:$port/');
    final WebSocket socket;
    try {
      socket = await opening.timeout(_connectTimeout);
    } catch (error) {
      if (error is TimeoutException) {
        // `timeout` gives up waiting but the connect itself carries on. If it
        // lands later, close it — an orphan that never sends `auth` would sit
        // in the PC's connection budget until its 5 s timer reaps it.
        unawaited(opening.then<void>(
          (WebSocket orphan) => orphan.close().catchError((Object _) {}),
          onError: (Object _) {},
        ));
      }
      if (generation != _generation || !_wanted) return; // Nobody wants it.
      final ConnectFailure failure = ConnectFailure.classify(error, host: host, port: port);
      debugPrint('[SALU remote] connect failed: ${failure.code} — $error');
      _failLink(failure.code, failure.message);
      return;
    }
    if (generation != _generation || !_wanted) {
      // The user disconnected, or pointed the app elsewhere, while this
      // socket was still opening. It is nobody's socket now.
      unawaited(socket.close().catchError((Object _) {}));
      return;
    }
    // Reaps a socket whose peer vanished (PC slept) instead of believing it
    // is alive until the next write fails (`remote.md` §11).
    socket.pingInterval = const Duration(seconds: 20);
    _socket = socket;
    _sawHello = false;
    _events = socket.listen(
      _onFrame,
      onDone: _onClosed,
      onError: (Object error, StackTrace stack) => _onClosed(),
      cancelOnError: true,
    );
    _attempt = 0;
    debugPrint('[SALU remote] socket open, sending auth');
    _sendAuth();
    _startHandshakeClock();
    _startPing();
  }

  /// The PC sends `hello` the instant the upgrade completes and `auth_ok`
  /// within a moment of our `auth`. If neither shows up, the socket is not
  /// talking to a SALU we understand — tear it down and say so, instead of
  /// sitting on "Connecting…" until the PC's own 5 s auth timer closes us
  /// (or forever, when it is not SALU at all).
  void _startHandshakeClock() {
    _handshakeTimer?.cancel();
    _handshakeTimer = Timer(_handshakeTimeout, () {
      _handshakeTimer = null;
      if (_authenticated || _socket == null) return;
      final bool sawHello = _sawHello;
      debugPrint('[SALU remote] handshake timed out (hello seen: $sawHello)');
      unawaited(_teardown().then((_) {
        if (!_wanted) return;
        _failLink(
          'unreachable',
          sawHello
              ? 'SALU answered but never accepted the pairing. Try again; if '
                  'it repeats, restart Remote in SALU\'s Settings.'
              : 'Connected to $_host:$_port, but it did not speak SALU Remote. '
                  'Check the port in the PC\'s Remote panel.',
        );
      }));
    });
  }

  void _sendAuth() {
    final RemotePrefs prefs = RemotePrefs.instance;
    final bool byCode = _pairingCode != null;
    debugPrint('[SALU remote] auth by ${byCode ? 'pairing code' : 'token'}');
    final Map<String, Object?> auth = byCode
        ? RemoteProtocol.authByPairingCode(
            id: 1,
            pair: _pairingCode!,
            deviceId: prefs.deviceId,
            deviceName: prefs.deviceName,
            platform: 'android',
          )
        : RemoteProtocol.authByToken(
            id: 1,
            token: prefs.token ?? '',
            deviceId: prefs.deviceId,
            deviceName: prefs.deviceName,
            platform: 'android',
          );
    _write(auth);
  }

  /// Returns whether the frame actually went out. A frame that is too large is
  /// refused *before* it reaches the socket, on purpose: the PC answers an
  /// oversized frame by closing the connection (`remote.md` §6 — 8 KB maximum),
  /// so sending one would cost the whole link rather than one command.
  bool _write(Map<String, Object?> message) {
    final WebSocket? socket = _socket;
    if (socket == null) return false;
    try {
      socket.add(RemoteProtocol.encode(message));
      return true;
    } on RemoteProtocolException catch (error) {
      debugPrint('[SALU remote] refused to send: ${error.message}');
      return false;
    } catch (error) {
      debugPrint('[SALU remote] write failed: $error');
      return false;
    }
  }

  void _onFrame(Object? event) {
    if (event is! String) return; // The protocol is text-only, one object per frame.
    Map<String, Object?> message;
    try {
      message = RemoteProtocol.decode(event);
    } on RemoteProtocolException catch (error) {
      debugPrint('[SALU remote] bad frame: ${error.message}');
      return;
    }
    switch (message['type']) {
      case 'hello':
        _onHello(message);
        break;
      case 'auth_ok':
        unawaited(_onAuthOk(message));
        break;
      case 'state':
        _applySnapshot(message);
        break;
      case 'pong':
        _onPong(message);
        break;
      case 'error':
        _onError(message);
        break;
      default:
        _onResult(message);
        break;
    }
  }

  void _onHello(Map<String, Object?> message) {
    final ServerInfo info = ServerInfo.from(message);
    server.value = info;
    _sawHello = true;
    debugPrint('[SALU remote] hello from ${info.name} (PC ${info.version}, proto ${info.proto})');
    if (info.proto != protocolVersion) {
      // D7: a mismatched protocol is a clear error, never a half-working app.
      problemCode.value = RemoteErrorCode.versionMismatch;
      problemMessage.value = 'This app and SALU speak different versions. '
          'Update SALU Remote (PC ${info.version}).';
      link.value = LinkState.needsPairing;
      unawaited(_teardown());
      return;
    }
    final Object? state = message['state'];
    if (state is Map) {
      // `hello` already carries a full snapshot, so a reconnecting phone paints
      // the right screen in its first frame (`remote.md` §6.1).
      _applySnapshot(_stringKeyed(state));
    }
  }

  Future<void> _onAuthOk(Map<String, Object?> message) async {
    _authenticated = true;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    final Object? token = message['token'];
    if (token is String && token.isNotEmpty) {
      // Always returned, even for a token the PC already knew — idempotent, so
      // the client stores whatever it receives and never branches.
      await RemotePrefs.instance.rememberToken(
        token,
        serverName: server.value?.name,
      );
    }
    _pairingCode = null;
    _clearProblem();
    _attempt = 0;
    link.value = LinkState.online;
    debugPrint('[SALU remote] online with ${server.value?.name ?? 'PC'}');
  }

  void _applySnapshot(Map<String, Object?> raw) {
    final SaluSnapshot next = SaluSnapshot.from(raw);
    final SaluSnapshot? current = snapshot.value;
    // Out-of-order frames are dropped: the phone only ever moves forward.
    if (current != null && next.rev <= current.rev) return;
    snapshot.value = next;
  }

  void _onPong(Map<String, Object?> message) {
    final int? at = message['at'] is num ? (message['at'] as num).toInt() : null;
    if (at == null) return;
    _pingSentAt = null;
    latencyMs.value = DateTime.now().millisecondsSinceEpoch - at;
  }

  void _onResult(Map<String, Object?> message) {
    final Object? rawId = message['id'];
    if (rawId is! num) return;
    final Completer<RemoteReply>? completer = _pending.remove(rawId.toInt());
    if (completer == null || completer.isCompleted) return;
    final Map<String, Object?> data = Map<String, Object?>.of(message)
      ..remove('type')
      ..remove('proto')
      ..remove('id')
      ..remove('ok');
    completer.complete(
      RemoteReply.success(message['type'] as String?, data),
    );
  }

  void _onError(Map<String, Object?> message) {
    final String? code = message['code'] as String?;
    final String? text = message['message'] as String?;
    final Object? rawId = message['id'];
    final int? id = rawId is num ? rawId.toInt() : null;
    final Completer<RemoteReply>? completer =
        id == null ? null : _pending.remove(id);
    if (completer != null && !completer.isCompleted) {
      completer.complete(RemoteReply.failure(code, text));
      return;
    }
    // No one was waiting: this is an authentication failure, i.e. about the
    // link itself rather than about one command.
    if (code != null && _noRetryCodes.contains(code)) {
      debugPrint('[SALU remote] auth failed: $code — $text');
      problemCode.value = code;
      problemMessage.value = text;
      link.value = LinkState.needsPairing;
      _wanted = false;
      if (code == RemoteErrorCode.badToken) {
        // The PC forgot this phone. Keeping the token would make every later
        // attempt fail the same way; dropping it lets the next code pair.
        unawaited(RemotePrefs.instance.forgetToken());
      }
      unawaited(_teardown());
    }
  }

  void _onClosed() {
    final int? closeCode = _socket?.closeCode;
    final String? closeReason = _socket?.closeReason;
    final bool wasAuthenticated = _authenticated;
    _socket = null;
    _events = null;
    _authenticated = false;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _stopPing();
    _failPending(RemoteReply.offline());
    debugPrint('[SALU remote] socket closed (code $closeCode'
        '${closeReason == null || closeReason.isEmpty ? '' : ', "$closeReason"'}'
        ', authenticated: $wasAuthenticated)');
    if (!_wanted) {
      if (link.value != LinkState.needsPairing) link.value = LinkState.off;
      return;
    }
    switch (closeCode) {
      case RemoteCloseCode.versionMismatch:
        problemCode.value = RemoteErrorCode.versionMismatch;
        problemMessage.value = 'Update SALU Remote — the PC speaks another version.';
        link.value = LinkState.needsPairing;
        _wanted = false;
        return;
      case RemoteCloseCode.notPrivateLan:
        problemCode.value = 'not_private_lan';
        problemMessage.value = 'The PC only accepts phones on its own local network.';
        link.value = LinkState.needsPairing;
        _wanted = false;
        return;
      case RemoteCloseCode.disabled:
        problemCode.value = 'remote_off';
        problemMessage.value = 'Remote control is switched off in SALU on the PC.';
        break;
      case RemoteCloseCode.tooManyConnections:
        problemCode.value = 'too_many';
        problemMessage.value = 'The PC has too many remote connections already.';
        break;
      case RemoteCloseCode.unauthorized:
        if (problemCode.value == null) {
          problemCode.value = 'auth_failed';
          problemMessage.value = 'The PC did not accept this phone.';
        }
        break;
      default:
        if (!wasAuthenticated && problemCode.value == null) {
          // Dropped mid-handshake with no code at all. The PC always says
          // why when *it* closes (an `error` frame, or a 4xxx code), so this
          // is the network or the PC process going away — retryable, but
          // worth a line so the sheet is not blank while we retry.
          problemCode.value = 'unreachable';
          problemMessage.value =
              'The connection dropped before the PC finished the handshake. '
              'Trying again… (if this repeats, restart Remote in SALU\'s Settings).';
        }
        break;
    }
    if (problemCode.value != null && _noRetryCodes.contains(problemCode.value)) {
      link.value = LinkState.needsPairing;
      _wanted = false;
      return;
    }
    link.value = LinkState.unreachable;
    _scheduleReconnect();
  }

  void _failLink(String code, String message) {
    problemCode.value = code;
    problemMessage.value = message;
    link.value = LinkState.unreachable;
    if (_wanted) _scheduleReconnect();
  }

  /// Backoff: 1 s, 2 s, 3 s, 5 s, 8 s, then every 12 s. A phone that has been
  /// asleep for an hour must not hammer the PC, and a PC that comes back must
  /// be picked up within a few seconds.
  void _scheduleReconnect() {
    if (!_wanted) return;
    _reconnectTimer?.cancel();
    const List<int> steps = <int>[1, 2, 3, 5, 8, 12];
    final int seconds = steps[_attempt < steps.length ? _attempt : steps.length - 1];
    _attempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (_wanted) unawaited(_open());
    });
  }

  void _startPing() {
    _stopPing();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      final DateTime? sent = _pingSentAt;
      final DateTime now = DateTime.now();
      if (sent != null && now.difference(sent).inSeconds >= 12) {
        // Two missed pings: the socket is a ghost. Drop it; the reconnect loop
        // brings it back (`remote.md` §7.2's "detect a stalled link").
        _pingSentAt = null;
        unawaited(_teardown().then((_) {
          if (_wanted) {
            link.value = LinkState.unreachable;
            _scheduleReconnect();
          }
        }));
        return;
      }
      if (!_authenticated) return;
      _pingSentAt ??= now;
      _write(<String, Object?>{
        'type': 'cmd',
        'id': _nextId++,
        'proto': protocolVersion,
        'verb': 'ping',
        'args': <String, Object?>{'at': now.millisecondsSinceEpoch},
      });
    });
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _pingSentAt = null;
  }

  void _failPending(RemoteReply reply) {
    for (final Completer<RemoteReply> completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(reply);
    }
    _pending.clear();
  }

  void _clearProblem() {
    problemCode.value = null;
    problemMessage.value = null;
  }

  void clearProblem() => _clearProblem();

  /// Strips anything that is not a letter or digit — the PC does the same, so a
  /// code typed with dashes, spaces or lower case all pair.
  static String _normalizeCode(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');

  static Map<String, Object?> _stringKeyed(Map<Object?, Object?> raw) {
    final Map<String, Object?> out = <String, Object?>{};
    raw.forEach((Object? key, Object? value) {
      if (key is String) out[key] = value;
    });
    return out;
  }

  // ── verbs ─────────────────────────────────────────────────────────────────
  //
  // One thin wrapper per verb, so no screen ever types a verb string or builds
  // JSON. Args are in the PC's own units (milliseconds, percent, dB) — the
  // conversion from what a thumb did to what the PC wants happens here and
  // nowhere else.

  Future<RemoteReply> send(
    String verb, {
    Map<String, Object?>? args,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final WebSocket? socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open || !_authenticated) {
      return RemoteReply.offline();
    }
    final int id = _nextId++;
    final Completer<RemoteReply> completer = Completer<RemoteReply>();
    _pending[id] = completer;
    inFlight.value = inFlight.value + 1;
    try {
      final bool sent = _write(<String, Object?>{
        'type': 'cmd',
        'id': id,
        'proto': protocolVersion,
        'verb': verb,
        if (args != null && args.isNotEmpty) 'args': args,
      });
      if (!sent) {
        _pending.remove(id);
        return const RemoteReply(
          ok: false,
          type: 'error',
          code: 'too_large',
          message: 'That request is too big to send in one message.',
        );
      }
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      return const RemoteReply(
        ok: false,
        type: 'error',
        code: 'timeout',
        message: 'The PC did not answer in time.',
      );
    } finally {
      _pending.remove(id);
      inFlight.value = inFlight.value > 0 ? inFlight.value - 1 : 0;
    }
  }

  // Transport (`remote.md` §9). The PC clamps everything; the phone only sends
  // intent and lets the snapshot tell it what actually happened.
  Future<RemoteReply> playPause() => send('play_pause');
  Future<RemoteReply> stop() => send('stop');
  Future<RemoteReply> next() => send('next');
  Future<RemoteReply> previous() => send('previous');
  Future<RemoteReply> seekBy(int milliseconds) =>
      send('seek_by', args: <String, Object?>{'delta': milliseconds});
  Future<RemoteReply> seekTo(int milliseconds) =>
      send('seek_to', args: <String, Object?>{'position': milliseconds});
  Future<RemoteReply> setVolume(int percent) =>
      send('set_volume', args: <String, Object?>{'value': percent.clamp(0, 100)});
  Future<RemoteReply> volumeStep(int delta) =>
      send('volume_step', args: <String, Object?>{'delta': delta});
  Future<RemoteReply> muteToggle() => send('mute_toggle');
  Future<RemoteReply> shuffleToggle() => send('shuffle_toggle');
  Future<RemoteReply> repeatCycle() => send('repeat_cycle');
  Future<RemoteReply> takeControl() => send('take_control');
  Future<RemoteReply> stateGet() =>
      send('state_get', timeout: const Duration(seconds: 4));

  // Queue (`remote.md` §17.4 — titles only, never paths).
  Future<RemoteReply> queueGet({int from = 0, int count = 20}) =>
      send('queue_get', args: <String, Object?>{'from': from, 'count': count});
  Future<RemoteReply> queueJump(int index) =>
      send('queue_jump', args: <String, Object?>{'index': index});
  /// Empties the playlist and stops playback — the Queue card's clear button
  /// (user, 2026-09-22). New in `remote.md` §17.4: a PC that has not caught
  /// up yet answers `unknown_command`, which the card turns into its own
  /// plain sentence instead of a silent no-op.
  Future<RemoteReply> queueClear() => send('queue_clear');

  // Files — read-only, and only when the PC's `remote_file_access` is on.
  Future<RemoteReply> fsPlaces() => send('fs_places');
  Future<RemoteReply> fsList(
    String path, {
    int from = 0,
    int count = 200,
    String filter = 'media',
    bool showSystem = false,
  }) =>
      // The PC rate-limits this to one per 200 ms; the screen throttles too.
      send(
        'fs_list',
        args: <String, Object?>{
          'path': path,
          'from': from,
          'count': count,
          'filter': filter,
          'showSystem': showSystem,
        },
        timeout: const Duration(seconds: 10),
      );
  /// Opens files on the PC — the bytes never travel (`remote.md` §17.6).
  ///
  /// **Batched, and that is not an optimization.** The protocol caps a frame at
  /// 8 KB (`remote.md` §6) while `fs_open` accepts up to 500 paths (§17.4); an
  /// average Windows path is 50–70 characters, so a select-all of a season
  /// would build a ~30 KB frame — which the PC refuses by *closing the socket*,
  /// not by failing the command. Forty paths per frame stays comfortably inside
  /// the cap and inside the PC's 30 commands/second budget.
  Future<RemoteReply> fsOpen(List<String> paths, {String mode = 'play'}) async {
    if (paths.isEmpty) {
      return const RemoteReply(
        ok: false,
        type: 'error',
        code: 'invalid_arguments',
        message: 'Nothing was selected.',
      );
    }
    const int batch = 40;
    RemoteReply last = const RemoteReply(ok: true, type: 'ack');
    for (int start = 0; start < paths.length; start += batch) {
      final List<String> slice = paths.sublist(
        start,
        start + batch > paths.length ? paths.length : start + batch,
      );
      last = await send(
        'fs_open',
        args: <String, Object?>{'paths': slice, 'mode': mode},
        // The PC scans folders here; give a big folder the same grace it gives
        // itself in §17.2 rather than failing at 3 seconds.
        timeout: const Duration(seconds: 15),
      );
      // First failure wins: a half-queued batch must not look like success.
      if (!last.ok) return last;
    }
    return last;
  }
  Future<RemoteReply> fsLoadSubtitle(String path) =>
      send('fs_load_sub', args: <String, Object?>{'path': path});

  // Streams — the PC's own saved list, mirrored.
  Future<RemoteReply> libraryGet() => send('library_get');
  Future<RemoteReply> libraryPlay(String url) =>
      send('library_play', args: <String, Object?>{'url': url});
  Future<RemoteReply> libraryAdd(String url, {String? name, bool save = true}) =>
      send(
        'library_add',
        args: <String, Object?>{'url': url, 'name': ?name, 'save': save},
      );
  Future<RemoteReply> libraryRemove(String url) =>
      send('library_remove', args: <String, Object?>{'url': url});
  Future<RemoteReply> openUrl(String url) =>
      send('open_url', args: <String, Object?>{'url': url}, timeout: const Duration(seconds: 12));

  // Tune (`remote.md` §17.4). An EQ drag sends `eq_gesture begin`, the band
  // writes, then `eq_set` with the whole curve and `eq_gesture end` — so it is
  // one undoable edit on the PC, never sixty.
  Future<RemoteReply> tuneGet() => send('tune_get');
  Future<RemoteReply> eqGesture(String phase) =>
      send('eq_gesture', args: <String, Object?>{'phase': phase});
  Future<RemoteReply> eqBand(int index, double db) =>
      send('eq_band', args: <String, Object?>{'index': index, 'db': db});
  Future<RemoteReply> eqSet(List<double> gains) =>
      send('eq_set', args: <String, Object?>{'gains': gains});
  Future<RemoteReply> eqPreset(String key) =>
      send('eq_preset', args: <String, Object?>{'key': key});
  Future<RemoteReply> eqReset() => send('eq_reset');
  Future<RemoteReply> eqSaveMy() => send('eq_save_my');
  Future<RemoteReply> autoEq(bool on) =>
      send('auto_eq', args: <String, Object?>{'on': on});
  Future<RemoteReply> speedSet(String key) =>
      send('speed_set', args: <String, Object?>{'key': key});

  // Subtitles — the PC does all the work; the phone asks and watches.
  Future<RemoteReply> subsGet() => send('subs_get');
  Future<RemoteReply> subSelect({required String kind, required String id}) =>
      send('sub_select', args: <String, Object?>{'kind': kind, 'id': id});
  Future<RemoteReply> subDelay(double seconds) =>
      send('sub_delay', args: <String, Object?>{'seconds': seconds});
  Future<RemoteReply> subDelayStep(double delta) =>
      send('sub_delay_step', args: <String, Object?>{'delta': delta});
  Future<RemoteReply> subDelayReset() => send('sub_delay_reset');
  Future<RemoteReply> subsSearch(String query, {String? language}) => send(
        'subs_search',
        args: <String, Object?>{
          'query': query,
          if (language != null && language.isNotEmpty) 'language': language,
        },
        timeout: const Duration(seconds: 20),
      );
  Future<RemoteReply> subsDownload(int fileId) => send(
        'subs_download',
        args: <String, Object?>{'fileId': fileId},
        timeout: const Duration(seconds: 30),
      );
  Future<RemoteReply> subsAuto(bool on) =>
      send('subs_auto', args: <String, Object?>{'on': on});
  Future<RemoteReply> subsLang(String code) =>
      send('subs_lang', args: <String, Object?>{'code': code});

  // Mode, window, browser.
  Future<RemoteReply> modeSet(String mode) =>
      send('mode_set', args: <String, Object?>{'mode': mode});
  Future<RemoteReply> fullscreenToggle() => send('fullscreen_toggle');
  Future<RemoteReply> fullscreenSet(bool on) =>
      send('fullscreen_set', args: <String, Object?>{'on': on});
  Future<RemoteReply> browserNav(String action) =>
      send('browser_nav', args: <String, Object?>{'action': action});
  Future<RemoteReply> browserOpen(String url) =>
      send('browser_open', args: <String, Object?>{'url': url});

  // The page's own player (`remote.md` §17.11) — never mpv, never the Windows
  // volume.
  Future<RemoteReply> webMediaGet() =>
      send('web_media_get', timeout: const Duration(seconds: 6));
  Future<RemoteReply> webMediaToggle() => send('web_media_toggle');
  Future<RemoteReply> webMediaSeek({int? to, int? delta}) => send(
        'web_media_seek',
        args: <String, Object?>{
          'to': ?to,
          'delta': ?delta,
        },
      );
  Future<RemoteReply> webMediaVolume(int percent) =>
      send('web_media_volume', args: <String, Object?>{'percent': percent.clamp(0, 100)});
  Future<RemoteReply> webMediaMute(bool on) =>
      send('web_media_mute', args: <String, Object?>{'on': on});
  Future<RemoteReply> webMediaFullscreen() => send('web_media_fullscreen');

  /// The D-pad (`remote_apk_ui.md` §6.0).
  ///
  /// Note for the PC side: `web_key` is specified but **not implemented yet** —
  /// `remote_command_handler.dart` answers `unknown_command` until it is. The
  /// phone hides the D-pad until the PC advertises `web_key` in `hello.features`,
  /// so a half-built PC never shows a dead button.
  Future<RemoteReply> webKey(String key) =>
      send('web_key', args: <String, Object?>{'key': key});

  bool supports(String feature) => server.value?.features.contains(feature) ?? false;
}
