import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
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

/// What happened to an outgoing frame.
enum _WriteStatus {
  /// Bytes handed to the socket.
  sent,

  /// Refused before the wire: over the 8 KB cap (`remote.md` §6).
  tooLarge,

  /// The socket would not take the bytes — it is dead even if it still
  /// claims to be open.
  failed,
}

/// One in-flight `cmd`: its future, plus what it was, so a connection cut
/// can decide whether the command may be replayed after the reconnect.
class _PendingCommand {
  _PendingCommand({
    required this.completer,
    required this.verb,
    this.args,
    required this.safeRetry,
  });

  final Completer<RemoteReply> completer;
  final String verb;
  final Map<String, Object?>? args;
  final bool safeRetry;
}

/// A safe command parked for one replay after the next `auth_ok`.
class _QueuedCommand {
  _QueuedCommand({required this.verb, this.args})
      : at = DateTime.now();

  final String verb;
  final Map<String, Object?>? args;
  final DateTime at;
}

/// The one connection to the PC (`remote.md` §4, §7).
///
/// Responsibilities, and deliberately nothing else:
///   * one WebSocket, opened to `ws://host:port`, `hello` → `auth` → `auth_ok`;
///   * the reconnect loop (backoff, and *no* loop when the PC refused us);
///   * the keepalive split — socket-level `pingInterval` (+ close events +
///     network changes) declare the link dead; the app-level `ping` command
///     only measures latency for the Connect sheet;
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
  bool _authenticated = false;

  /// Generation of a dial still in flight (past the guard in [_open], before
  /// a socket is adopted). One dial at a time: a second `_open()` — resume
  /// racing the backoff timer — must wait its turn, or it stacks an
  /// unauthenticated ghost socket against the PC's max-4 budget
  /// (`remote.md` §6.4, close code 4005).
  int? _dialing;
  bool _netWatchStarted = false;

  /// When the last full snapshot frame arrived — the stall nudge's clock.
  /// Never used to declare the link dead (transport keepalive owns that).
  DateTime? _lastSnapshotAt;
  bool _stallProbeInFlight = false;

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
  final Map<int, _PendingCommand> _pending = <int, _PendingCommand>{};

  /// Absolute commands that failed while the link was down, parked for one
  /// replay on the next `auth_ok`. Repeating them cannot double-apply (a
  /// seek *to* 5:32 twice is still 5:32); toggles are deliberately absent.
  final List<_QueuedCommand> _retryQueue = <_QueuedCommand>[];

  /// How long a parked command stays replayable. A normal blip recovers in
  /// well under this; a tap from minutes ago must never fire late.
  static const Duration _retryWindow = Duration(seconds: 20);
  static const int _retryCap = 5;

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

  /// Verbs whose effect is an **absolute value**, so replaying after a
  /// dropped link lands on the same result (seek *to* 5:32, volume *at*
  /// 40). Toggles and relative steps (`play_pause`, `next`, `seek_by`,
  /// `mute_toggle`, …) are excluded on purpose — a blind replay would
  /// apply the action twice, which is worse than losing it once.
  static const Set<String> _safeRetryVerbs = <String>{
    'seek_to',
    'set_volume',
    'queue_jump',
    'mode_set',
    'fullscreen_set',
    'sub_select',
    'sub_delay',
    'sub_delay_reset',
    'subs_auto',
    'subs_lang',
    'eq_set',
    'eq_preset',
    'eq_reset',
    'speed_set',
    'auto_eq',
    'take_control',
  };

  // ── lifecycle ─────────────────────────────────────────────────────────────

  /// Called once from `main()` after prefs are loaded. Reconnects to the
  /// remembered PC if there is one; otherwise stays idle and the Connect sheet
  /// takes over.
  Future<void> autoConnect() async {
    _startNetWatch();
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
  /// When the PC closes, the remote must return to the initial connect screen
  /// — no stale title, no old queue. So every disconnect clears the snapshot.
  Future<void> disconnect({bool forget = false}) async {
    _wanted = false;
    await _teardown();
    // After the teardown: `_teardown` fails every pending command with
    // `offline`, and the queue refuses new entries while `_wanted` is false —
    // so nothing from this session can survive into the next one.
    _retryQueue.clear();
    link.value = LinkState.off;
    snapshot.value = null;
    if (forget) {
      await RemotePrefs.instance.forgetPc();
      server.value = null;
      address.value = null;
      _host = null;
      _port = null;
    }
  }

  /// Android lifecycle resume (and the app's own "the phone just woke up"
  /// path). Never *assume* the socket survived: after a screen-off it can be
  /// a zombie that still claims to be open. Prove the link with a short
  /// `state_get`; if it does not answer, tear down and redial at once —
  /// no waiting out a backoff on a connection that is already gone.
  Future<void> onResume() async {
    _startNetWatch();
    if (_socket != null && _authenticated) {
      final RemoteReply reply =
          await send('state_get', timeout: const Duration(seconds: 3));
      if (reply.ok) return;
      if (reply.code == 'timeout' || reply.code == 'offline') {
        debugPrint(
            '[SALU remote] resume health check failed (${reply.code}) — redialing');
        final int generation = _generation;
        await _teardown();
        // Only redial if nothing else (network watcher, user) already took
        // over while this socket was being closed.
        if (_generation != generation + 1 || !_wanted) return;
        _attempt = 0;
        _reconnectTimer?.cancel();
        link.value = LinkState.connecting;
        await _open();
      }
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
    _dialing = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _stopPing();
    _authenticated = false;
    _stallProbeInFlight = false;
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
    if (_dialing != null) return; // And one dial in flight, always.
    if (link.value != LinkState.online) link.value = LinkState.connecting;
    final String host = _host!;
    final int port = _port!;
    final int generation = ++_generation;
    _dialing = generation;
    debugPrint('[SALU remote] connecting to ws://$host:$port/ (attempt ${_attempt + 1})');
    final Future<WebSocket> opening = WebSocket.connect('ws://$host:$port/');
    final WebSocket socket;
    try {
      socket = await opening.timeout(_connectTimeout);
    } catch (error) {
      if (_dialing == generation) _dialing = null;
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
      if (_dialing == generation) _dialing = null;
      unawaited(socket.close().catchError((Object _) {}));
      return;
    }
    // **Who declares the link dead — and who does not.**
    // This socket-level keepalive is the authority: dart:io pings the peer
    // and closes the socket when the pong is late, entirely at the I/O
    // layer — it never waits on the PC's command queue, so a busy PC can
    // never look like a dead link. Together with the close event itself and
    // the network listener, that is the whole death-detection set. The
    // app-level `ping` command is a speedometer for the Connect sheet, and
    // the stall nudge is a freshness request; neither one kills a socket.
    socket.pingInterval = const Duration(seconds: 10);
    _dialing = null;
    _socket = socket;
    _sawHello = false;
    _lastSnapshotAt = null;
    _stallProbeInFlight = false;
    _events = socket.listen(
      _onFrame,
      onDone: _onClosed,
      onError: (Object error, StackTrace stack) => _onClosed(),
      cancelOnError: true,
    );
    // NOTE: the backoff counter is *not* reset here — only a successful
    // `auth_ok` earns that. A socket that opens and then fails the handshake
    // must keep backing off instead of retrying every second forever.
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
    final int generation = _generation;
    _handshakeTimer = Timer(_handshakeTimeout, () {
      _handshakeTimer = null;
      if (generation != _generation) return; // A newer connection owns the link now.
      if (_authenticated || _socket == null) return;
      final bool sawHello = _sawHello;
      debugPrint('[SALU remote] handshake timed out (hello seen: $sawHello)');
      unawaited(_teardown().then((_) {
        // `_teardown` itself bumps the generation, so "mine plus one" means
        // nobody took over while we were closing. (A plain `!= generation`
        // would compare against the post-teardown value and *always* trip;
        // a fresh connect during the close bumps it even further — that
        // connection's own flow owns the link now.)
        if (_generation != generation + 1 || !_wanted) return;
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

  /// Returns what actually happened to the frame. A frame that is too large
  /// is refused *before* it reaches the socket, on purpose: the PC answers an
  /// oversized frame by closing the connection (`remote.md` §6 — 8 KB
  /// maximum), so sending one would cost the whole link rather than one
  /// command. [_WriteStatus.failed] is different — the socket itself refused
  /// the bytes, which means the link is already dead and the caller must
  /// treat it as a connection problem, never as "too big".
  _WriteStatus _write(Map<String, Object?> message) {
    final WebSocket? socket = _socket;
    if (socket == null) return _WriteStatus.failed;
    try {
      socket.add(RemoteProtocol.encode(message));
      return _WriteStatus.sent;
    } on RemoteProtocolException catch (error) {
      debugPrint('[SALU remote] refused to send: ${error.message}');
      return _WriteStatus.tooLarge;
    } catch (error) {
      debugPrint('[SALU remote] write failed: $error');
      return _WriteStatus.failed;
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
    // A new PC — or a restarted one — gets its units measured again: the
    // contract until its first `web_media_get` reply says otherwise.
    _webDialect = WebMediaDialect.contract;
    debugPrint('[SALU remote] hello from ${info.name} (PC ${info.version}, proto ${info.proto})');
    if (info.proto != protocolVersion) {
      // D7: a mismatched protocol is a clear error, never a half-working app.
      problemCode.value = RemoteErrorCode.versionMismatch;
      problemMessage.value = 'This app and SALU speak different versions. '
          'Update SALU Remote (PC ${info.version}).';
      link.value = LinkState.needsPairing;
      snapshot.value = null;
      _wanted = false; // Same stop rule as every other "user must fix this" path.
      unawaited(_teardown());
      return;
    }
    final Object? state = message['state'];
    if (state is Map) {
      // `hello` already carries a full snapshot, so a reconnecting phone paints
      // the right screen in its first frame (`remote.md` §6.1).
      //
      // **Force-apply:** `hello` is the authority for a (re)opened socket.
      // The last snapshot may have been kept across a blip, and the PC may
      // since have restarted and reset `rev` — a kept picture must never
      // block the fresh one.
      _applySnapshot(_stringKeyed(state), force: true);
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
    // Absolute taps that failed during the gap get their one fresh replay
    // now, against a connection that has just proven itself.
    _flushRetryQueue();
  }

  void _applySnapshot(Map<String, Object?> raw, {bool force = false}) {
    // A snapshot frame arriving at all means the PC is pushing — record it
    // for the stall nudge even when the frame itself is about to be dropped.
    _lastSnapshotAt = DateTime.now();
    final SaluSnapshot next = SaluSnapshot.from(raw);
    final SaluSnapshot? current = snapshot.value;
    // Out-of-order frames are dropped: the phone only ever moves forward.
    // `force` (the `hello` snapshot) overrides this — a restarted PC starts
    // its `rev` over, and the authority of a fresh socket outranks history.
    if (!force && current != null && next.rev <= current.rev) return;
    snapshot.value = next;
  }

  void _onPong(Map<String, Object?> message) {
    final int? at = message['at'] is num ? (message['at'] as num).toInt() : null;
    if (at == null) return;
    // Latency display only. A late pong never kills the link — death is
    // declared by the socket-level pingInterval and the close event.
    latencyMs.value = DateTime.now().millisecondsSinceEpoch - at;
  }

  void _onResult(Map<String, Object?> message) {
    final Object? rawId = message['id'];
    if (rawId is! num) return;
    final _PendingCommand? pending = _pending.remove(rawId.toInt());
    if (pending == null) return;
    final Completer<RemoteReply> completer = pending.completer;
    if (completer.isCompleted) return;
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
    final _PendingCommand? pending = id == null ? null : _pending.remove(id);
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(RemoteReply.failure(code, text));
      return;
    }
    // No one was waiting: this is an authentication failure, i.e. about the
    // link itself rather than about one command.
    if (code != null && _noRetryCodes.contains(code)) {
      debugPrint('[SALU remote] auth failed: $code — $text');
      problemCode.value = code;
      problemMessage.value = text;
      link.value = LinkState.needsPairing;
      snapshot.value = null;
      _wanted = false;
      _retryQueue.clear(); // A new pairing must not inherit the old session's taps.
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
      snapshot.value = null;
      return;
    }
    switch (closeCode) {
      case RemoteCloseCode.versionMismatch:
        problemCode.value = RemoteErrorCode.versionMismatch;
        problemMessage.value = 'Update SALU Remote — the PC speaks another version.';
        link.value = LinkState.needsPairing;
        snapshot.value = null;
        _wanted = false;
        return;
      case RemoteCloseCode.notPrivateLan:
        problemCode.value = 'not_private_lan';
        problemMessage.value = 'The PC only accepts phones on its own local network.';
        link.value = LinkState.needsPairing;
        snapshot.value = null;
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
      snapshot.value = null;
      _wanted = false;
      return;
    }
    // PC closed / network lost. The last picture **stays on screen** — only
    // the header dot tells the truth while we retry, and `hello` repaints
    // with the fresh state the moment the link is back. Wiping here is what
    // made every blip flash the Connect sheet over a blank Play tab.
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

  /// Android's own "does a network exist" feed (`connectivity_plus`).
  /// Two jobs, both about *speed of recovery*, not about declaring death
  /// (the socket keepalive and the close event still own that):
  ///
  ///  * network **vanishes** → drop the socket at once so the reconnect
  ///    loop and its backoff start immediately, instead of waiting out the
  ///    keepalive clock on a link that is obviously gone;
  ///  * network **returns** → redial now with a fresh budget. The moment
  ///    Wi-Fi comes back is exactly when a remote must snap to, not sit in
  ///    an 11 s backoff that started while the air was down.
  ///
  /// Android only delivers these broadcasts while the app is in the
  /// foreground — that is fine: the resume path ([onResume]) re-checks the
  /// world every time the app comes back.
  void _startNetWatch() {
    if (_netWatchStarted) return;
    _netWatchStarted = true;
    // The subscription is never cancelled on purpose: the watcher lives for
    // the whole app (the client is a singleton) and starts exactly once.
    Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final bool up = results.any((ConnectivityResult r) =>
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.ethernet ||
            r == ConnectivityResult.vpn ||
            r == ConnectivityResult.other);
        if (!up) {
          if (_socket != null || _dialing != null) {
            debugPrint('[SALU remote] network gone — dropping the socket now');
            final int generation = _generation;
            unawaited(_teardown().then((_) {
              // Teardown bumps the generation itself: "mine plus one" means
              // no newer connection took over during the close (e.g. the
              // network bounced back and a dial already started).
              if (_generation != generation + 1 || !_wanted) return;
              link.value = LinkState.unreachable;
              _scheduleReconnect();
            }));
          }
          return;
        }
        // Network is up (or just came back). If we should be connected and
        // are not — and nothing is already dialing — go now.
        if (_wanted && !isOnline && _socket == null && _dialing == null) {
          debugPrint('[SALU remote] network up — reconnecting immediately');
          _attempt = 0;
          _reconnectTimer?.cancel();
          unawaited(_open());
        }
      },
      onError: (Object _) {},
    );
  }

  /// The 5-second house clock. Two jobs, and **killing the link is not one
  /// of them**:
  ///
  ///  * **latency** — one `ping` command, answered by the PC with a `pong`
  ///    and shown in the Connect sheet. A late pong means the PC is busy;
  ///    death is declared by the socket-level `pingInterval`, the close
  ///    event, and the network listener — never by this clock. (The old
  ///    rule — tear the socket down after 12 s without an app-level pong —
  ///    made every PC-side stall look like a dead network, and contradicted
  ///    the 15–30 s grace the phone gives its own slow commands.)
  ///  * **stall nudge** — while the PC reports it is *playing*, snapshots
  ///    arrive every ~250 ms (`remote.md` §7.2). If they stop for a few
  ///    seconds, one `state_get` asks for a fresh picture instead of
  ///    letting the screen freeze under a green dot (`remote.md` §6.3's
  ///    "detect a stalled link", made real).
  void _startPing() {
    _stopPing();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (!_authenticated) return;
      final DateTime now = DateTime.now();
      _write(<String, Object?>{
        'type': 'cmd',
        'id': _nextId++,
        'proto': protocolVersion,
        'verb': 'ping',
        'args': <String, Object?>{'at': now.millisecondsSinceEpoch},
      });
      _stallNudge(now);
    });
  }

  /// Playing means a snapshot every ~250 ms. A few seconds of silence while
  /// the position should be moving is a stall — ask for the picture. If the
  /// PC is merely busy, the ask waits its turn and the link stays up; a
  /// genuinely dead socket is already handled by `pingInterval`.
  void _stallNudge(DateTime now) {
    final SaluSnapshot? snap = snapshot.value;
    if (snap == null || snap.playback.state != TransportState.playing) return;
    final DateTime? last = _lastSnapshotAt;
    if (last == null || now.difference(last) < const Duration(seconds: 4)) {
      return;
    }
    if (_stallProbeInFlight) return;
    _stallProbeInFlight = true;
    debugPrint('[SALU remote] snapshots stalled while playing — nudging with state_get');
    unawaited(
      send('state_get', timeout: const Duration(seconds: 4)).whenComplete(() {
        _stallProbeInFlight = false;
      }),
    );
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _failPending(RemoteReply reply) {
    final bool offline = reply.code == 'offline';
    for (final _PendingCommand pending in _pending.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.complete(reply);
      }
      // The cut may have eaten a command that never reached the PC (or its
      // reply). If it is safe to apply twice, park it for one replay on the
      // next `auth_ok` — this is the sync hole a dropped blip used to open.
      if (offline && pending.safeRetry) {
        _enqueueRetry(pending.verb, pending.args);
      }
    }
    _pending.clear();
  }

  void _enqueueRetry(String verb, Map<String, Object?>? args) {
    // Nothing is parked once the user (or a pairing refusal) has stopped the
    // link on purpose — teardown fails every pending command with `offline`,
    // and those must not outlive the session they came from.
    if (!_wanted) return;
    if (_retryQueue.length >= _retryCap) _retryQueue.removeAt(0);
    _retryQueue.add(_QueuedCommand(verb: verb, args: args));
    debugPrint(
        '[SALU remote] parked $verb for replay after reconnect (${_retryQueue.length} queued)');
  }

  /// Replay what is still fresh after a successful `auth_ok`. Anything
  /// parked longer than [_retryWindow] is dropped on purpose: a tap from
  /// minutes ago must never fire late against a changed screen.
  void _flushRetryQueue() {
    if (_retryQueue.isEmpty) return;
    final DateTime cutoff = DateTime.now().subtract(_retryWindow);
    final List<_QueuedCommand> fresh = _retryQueue
        .where((_QueuedCommand c) => c.at.isAfter(cutoff))
        .toList(growable: false);
    _retryQueue.clear();
    for (final _QueuedCommand cmd in fresh) {
      debugPrint('[SALU remote] replaying ${cmd.verb} after reconnect');
      unawaited(send(cmd.verb, args: cmd.args));
    }
  }

  /// A write failed on a socket that still claimed to be open (or a health
  /// check came back empty). Rebuild at once instead of waiting out the
  /// keepalive clock. The last snapshot stays on screen — only the dot moves.
  Future<void> _noteDeadSocket() async {
    if (_socket == null) return;
    debugPrint('[SALU remote] write failed on an open socket — rebuilding it now');
    final int generation = _generation;
    await _teardown();
    // Teardown bumps the generation itself: "mine plus one" means no newer
    // connection took over during the close — do not clobber its state.
    if (_generation != generation + 1 || !_wanted) return;
    link.value = LinkState.unreachable;
    _scheduleReconnect();
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
      // The frame never went anywhere. Park absolute commands so the next
      // connection applies them once instead of silently losing the tap.
      if (_safeRetryVerbs.contains(verb)) _enqueueRetry(verb, args);
      return RemoteReply.offline();
    }
    final int id = _nextId++;
    final _PendingCommand pending = _PendingCommand(
      completer: Completer<RemoteReply>(),
      verb: verb,
      args: args,
      safeRetry: _safeRetryVerbs.contains(verb),
    );
    _pending[id] = pending;
    inFlight.value = inFlight.value + 1;
    try {
      final _WriteStatus status = _write(<String, Object?>{
        'type': 'cmd',
        'id': id,
        'proto': protocolVersion,
        'verb': verb,
        if (args != null && args.isNotEmpty) 'args': args,
      });
      if (status != _WriteStatus.sent) {
        _pending.remove(id);
        if (status == _WriteStatus.failed) {
          // The socket claimed to be open but would not take the bytes —
          // it is a corpse. Say "not connected" (never "too big") and
          // rebuild the connection now instead of after the keepalive clock.
          unawaited(_noteDeadSocket());
          if (pending.safeRetry) _enqueueRetry(verb, args);
          return RemoteReply.offline();
        }
        return const RemoteReply(
          ok: false,
          type: 'error',
          code: 'too_large',
          message: 'That request is too big to send in one message.',
        );
      }
      return await pending.completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      // Deliberately **not** queued: a timeout is ambiguous (the PC may
      // still execute it late), and the replay window is for real offline
      // gaps only. The caller shows the timeout; the next snapshot tells
      // the truth either way.
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

  // PC power (`remote.md` §17.15). The PC owns these system actions; the
  // phone offers them only after `hello.features` advertises `pc_power`.
  Future<RemoteReply> sleepPc() => send('pc_sleep');
  Future<RemoteReply> shutDownPc() => send('pc_shutdown');

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
  /// The toast's own Restart word-action (`remote.md` §17.4): jump to 0:00
  /// and play, which also closes the PC's Resume toast so the phone's
  /// "Start over" seat disappears on the next snapshot.
  Future<RemoteReply> restart() => send('restart');
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

  // Channel grouping (`pc_part.md` §11).
  // Old PCs answer `unknown_command` → the phone hides the chips row entirely,
  // no error shown (that code is already in the silent set).
  Future<RemoteReply> queueGroups() => send('queue_groups');
  Future<RemoteReply> queueGroupSet(String by) =>
      send('queue_group_set', args: <String, Object?>{'by': by});

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

  /// **Home** (§17.14): the loaded page goes to its own site's front page, in
  /// the same tab. The PC knows what "home" means for its browser (its own
  /// home setting, else the current URL's origin); the phone only presses it.
  Future<RemoteReply> browserHome() =>
      send('browser_nav', args: <String, Object?>{'action': 'home'});

  Future<RemoteReply> browserOpen(String url) =>
      send('browser_open', args: <String, Object?>{'url': url});

  /// **One fullscreen button, and the PC decides** (§17.14) — the page's own
  /// player when it has one, the SALU window when it has not. This replaces the
  /// phone's old split (`web_media_fullscreen` vs `fullscreen_toggle`), which
  /// is exactly what made YouTube do nothing while other streams fullscreened
  /// the whole application.
  Future<RemoteReply> webFullscreen() => send('web_fullscreen');

  // ── the trackpad (`remote.md` §17.14) ─────────────────────────────────────
  //
  // Relative pointer movement and clicks on the **PC's own pointer**, so the
  // user watches the real cursor cross the real screen. The phone sends the
  // thumb's travel already in the PC's units (CSS pixels), batched to ~25
  // commands a second by `MousePad`; the PC moves the cursor by exactly that.
  // Movement is fire-and-forget — a lost 20 ms of travel is invisible, and an
  // answer per packet would double the traffic for nothing.

  Future<RemoteReply> webMouseMove(double dx, double dy) => send(
        'web_mouse_move',
        args: <String, Object?>{'dx': dx.round(), 'dy': dy.round()},
        timeout: const Duration(seconds: 4),
      );

  Future<RemoteReply> webMouseClick({String button = 'left', int count = 1}) =>
      send(
        'web_mouse_click',
        args: <String, Object?>{
          'button': button,
          'count': count.clamp(1, 2).toInt(),
        },
        timeout: const Duration(seconds: 4),
      );

  // ── the page's own player (`remote.md` §17.11) ────────────────────────────
  //
  // Never mpv, never the Windows volume: these drive the `<video>` element the
  // PC's browser is showing.
  //
  // **Units.** Every screen speaks the house units — milliseconds and integer
  // percent. The page player's own bridge does not always: JavaScript's
  // `currentTime` is seconds and its `volume` is 0–1, and §17.11 was written
  // from the JavaScript side without stating the wire unit. So the client
  // measures what the PC actually said on the way in ([_webDialect], refreshed
  // by every `web_media_get`) and answers in the same voice on the way out.
  // That is this file's one rule — "the conversion from what a thumb did to
  // what the PC wants happens here and nowhere else" — applied to the one
  // place the protocol left a unit unstated.

  WebMediaDialect _webDialect = WebMediaDialect.contract;

  /// The units the PC's page-player bridge is speaking. The Web body's
  /// diagnostics sheet shows it; nothing else needs to know.
  WebMediaDialect get webDialect => _webDialect;

  Future<RemoteReply> webMediaGet() async {
    final RemoteReply reply =
        await send('web_media_get', timeout: const Duration(seconds: 6));
    if (reply.ok) {
      final WebMediaInfo info =
          WebMediaInfo.from(reply.data, contractUnits: supportsWebMediaUnit);
      // `found:false` carries no times to judge, so it teaches nothing — keep
      // the last dialect the page's real player spoke in.
      if (info.found) _webDialect = info.dialect;
    }
    return reply;
  }

  /// `web_media_get`, already read into the phone's own units — `null` when the
  /// PC did not answer. The Web body polls this once a second and draws it; it
  /// never touches the wire shape.
  ///
  /// When the PC explicitly answers `no_web_media`, that is an affirmative
  /// "no reachable media on this page/tab" rather than a dropped connection or
  /// a missed beat. This returns [WebMediaInfo.none] so the body clears stale
  /// controls instead of leaving dead buttons on screen (`remote.md` §17.4).
  Future<WebMediaInfo?> webMediaRead() async {
    final RemoteReply reply = await webMediaGet();
    if (reply.ok) {
      return WebMediaInfo.from(reply.data, contractUnits: supportsWebMediaUnit);
    }
    if (reply.code == 'no_web_media') {
      return WebMediaInfo.none;
    }
    return null;
  }

  Future<RemoteReply> webMediaToggle() => send('web_media_toggle');

  /// One of [to] or [delta] — an absolute seat or a nudge. Both go out in the
  /// unit the PC's own last read used, so a seek lands where the thumb was.
  Future<RemoteReply> webMediaSeek({Duration? to, Duration? delta}) => send(
        'web_media_seek',
        args: <String, Object?>{
          if (to != null) 'to': _webDialect.timeValue(to),
          if (delta != null) 'delta': _webDialect.timeValue(delta),
        },
      );

  /// The page player's own volume, in **percent** — the write side of §17.11 is
  /// `element.volume = percent/100` even on a PC that reports a fraction on the
  /// read side, so this one is deliberately not dialect-converted.
  Future<RemoteReply> webMediaVolume(int percent) => send(
        'web_media_volume',
        args: <String, Object?>{'percent': percent.clamp(0, 100).toInt()},
      );

  Future<RemoteReply> webMediaMute(bool on) =>
      send('web_media_mute', args: <String, Object?>{'on': on});
  Future<RemoteReply> webMediaFullscreen() => send('web_media_fullscreen');

  // ── the browser's tabs and bookmarks (`remote.md` §17.7, §17.13) ──────────
  //
  // The lists never ride the snapshot — a strip of 40 tabs would eat the whole
  // 8 KB frame budget — so each is one request, answered from the PC's own tab
  // strip. Both families sit behind `web_tabs` / `web_bookmarks`, and an older
  // PC still gets useful doors rather than dead buttons (`web_tabs_card.dart`).

  Future<RemoteReply> webTabsGet() => send('web_tabs_get');

  Future<RemoteReply> webTabActivate(int index) =>
      send('web_tab_activate', args: <String, Object?>{'index': index});

  Future<RemoteReply> webTabClose(int index) =>
      send('web_tab_close', args: <String, Object?>{'index': index});

  /// A new tab. With [url] it opens that page; without, the PC's own new-tab
  /// page. On a PC that has not been updated the phone falls back to
  /// `open_url`, which already routes a link into the browser in Web mode.
  Future<RemoteReply> webTabNew({String? url}) => send(
        'web_tab_new',
        args: <String, Object?>{if (url != null && url.isNotEmpty) 'url': url},
      );

  Future<RemoteReply> webBookmarksGet() => send('web_bookmarks_get');

  /// **Add-only** bookmarking (§17.13.4, §17.14): append the page being looked
  /// at to the PC browser's bookmarks so it shows up in ☆ Saved pages itself.
  /// There is deliberately no rename and no delete — the phone can add to the
  /// PC's bookmark bar, never rewrite or empty it.
  Future<RemoteReply> webBookmarkAdd(String url, {String? name}) => send(
        'web_bookmark_add',
        args: <String, Object?>{
          'url': url,
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        },
        timeout: const Duration(seconds: 12),
      );

  /// Keys into the page (`remote_apk_ui.md` §6.0, `remote.md` §17.14).
  ///
  /// The Tune tab's **double tap** sends `Enter`; its two scroll seats send
  /// `ArrowUp` and `ArrowDown`. Those arrows reuse the old D-pad keys, which
  /// remain in the protocol and are still answered by the PC. `Escape` also
  /// remains available to PC-side callers, but has no Tune-tab seat.
  ///
  /// `web_key` is specified but **not implemented on every PC** — an older
  /// `remote_command_handler.dart` answers `unknown_command`. The pad checks
  /// `supportsWebKey` before relying on it: double tap becomes a double click
  /// when the promise is missing, and the scroll seats are disabled.
  ///
  /// A PC that implements it answers with the page's focus in the ack —
  /// `{focus:{label, tag, index, count, editable}}` — which is what keeps the
  /// keys honest, and what `webFocusGet` re-reads without moving it.
  Future<RemoteReply> webKey(String key) =>
      send('web_key', args: <String, Object?>{'key': key});

  /// Re-read the page's focus without moving it (`web_focus_get`).
  Future<RemoteReply> webFocusGet() => send('web_focus_get');

  // ── what this PC promised in `hello` ──────────────────────────────────────

  bool supports(String feature) => server.value?.features.contains(feature) ?? false;

  bool get supportsWebMediaUnit => supports(RemoteFeature.webMediaUnit);
  bool get supportsWebKey => supports(RemoteFeature.webKey);
  bool get supportsWebTabs => supports(RemoteFeature.webTabs);
  bool get supportsWebBookmarks => supports(RemoteFeature.webBookmarks);
  bool get supportsWebHome => supports(RemoteFeature.webHome);
  bool get supportsWebFullscreen => supports(RemoteFeature.webFullscreen);
  bool get supportsWebMouse => supports(RemoteFeature.webMouse);
  bool get supportsWebBookmarkAdd => supports(RemoteFeature.webBookmarkAdd);
  bool get supportsPcPower => supports(RemoteFeature.pcPower);
}
