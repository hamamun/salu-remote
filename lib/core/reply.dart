/// One reply for every verb on the wire (`remote.md` §6.2).
///
/// The PC answers a `cmd` with exactly one of:
///   * a success frame — `{ok:true, id, type:"ack"}` or a typed result frame such
///     as `{ok:true, id, type:"queue_result", rows:[…]}`;
///   * an error frame — `{type:"error", id, ok:false, code, message}`.
///
/// Both collapse into this class, so no caller ever branches on the envelope.
class RemoteReply {
  const RemoteReply({
    required this.ok,
    this.type,
    this.data = const <String, Object?>{},
    this.code,
    this.message,
  });

  factory RemoteReply.success(String? type, Map<String, Object?> data) =>
      RemoteReply(ok: true, type: type, data: data);

  factory RemoteReply.failure(String? code, String? message) =>
      RemoteReply(ok: false, type: 'error', code: code, message: message);

  /// Local, client-side failure — the request never reached the PC (socket
  /// down, or the reply did not arrive in time). The copy stays in the same
  /// family as the PC's own strings so the UI needs no second vocabulary.
  factory RemoteReply.offline() => const RemoteReply(
        ok: false,
        type: 'error',
        code: 'offline',
        message: 'Not connected to your PC.',
      );

  final bool ok;
  final String? type;
  final Map<String, Object?> data;
  final String? code;
  final String? message;

  bool has(String key) => data.containsKey(key);

  Object? operator [](String key) => data[key];

  @override
  String toString() =>
      ok ? 'RemoteReply(${type ?? 'ack'})' : 'RemoteReply.error($code: $message)';
}
