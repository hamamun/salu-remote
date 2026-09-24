import 'models.dart';
import 'reply.dart';

/// Every failure the PC can send, in words a person can act on.
///
/// The copy is lifted verbatim from `remote.md` §6.4 + §17.8 and
/// `remote_apk_ui.md` §7 — those tables exist precisely so no screen invents its
/// own wording for the same fact. A code the PC adds later still produces
/// something readable (the PC's own `message`, or a neutral fallback), because
/// an unknown error is not an excuse for a blank row.
abstract final class RemoteErrorCopy {
  /// Errors the user should never see: they are either self-evident from the
  /// control that was touched, or noise from a client bug (`remote.md` §17.8
  /// marks these "(silent, logged)").
  static const Set<String> silent = <String>{
    'unknown_command',
    'too_fast',
    'no_preset',
  };

  static bool isSilent(String? code) => code != null && silent.contains(code);

  static String of(RemoteReply reply) => text(reply.code, reply.message);

  static String text(String? code, String? fromPc) {
    switch (code) {
      case null:
        return fromPc ?? 'Something went wrong.';
      case 'bad_code':
        return 'That pairing code is not valid.';
      case 'bad_token':
        return 'This phone is no longer paired.';
      case 'version_mismatch':
        return 'Update SALU Remote — the PC speaks a different version.';
      case 'nothing_playing':
      case 'no_media':
        return 'Nothing is playing on the PC.';
      case 'not_seekable':
        return "This stream can't be seeked.";
      case 'file_access_off':
        return 'File browsing is turned off on the PC.';
      case 'path_not_found':
        return 'That folder or file is no longer there.';
      case 'not_a_directory':
        return 'That path is not a folder.';
      case 'no_key':
        return 'Add an OpenSubtitles key on the PC to search.';
      case 'signed_out':
        return 'Sign in to OpenSubtitles on the PC to download subtitles.';
      case 'quota':
        return 'OpenSubtitles download limit reached. Try again tomorrow.';
      case 'no_web_media':
        return "This site's player can't be controlled from outside.";
      case 'tab_not_found':
        return 'That tab is no longer open.';
      case 'no_web_tabs':
        return 'Tab control needs an updated SALU on the PC.';
      case 'no_web_bookmarks':
        return 'The PC\'s browser has no bookmarked pages.';
      case 'busy':
        return 'The PC is busy — try again in a moment.';
      case 'library_full':
        return 'The saved stream list is full.';
      case 'invalid_arguments':
        return "The PC didn't understand that request.";
      case 'too_large':
        return 'That request is too big to send in one message.';
      case 'offline':
        return 'Not connected to your PC.';
      case 'timeout':
        return 'The PC did not answer in time.';
      case 'remote_off':
        return 'Remote control is switched off in SALU on the PC.';
      case 'not_private_lan':
        return 'The PC only accepts phones on its own local network.';
      case 'too_many':
        return 'The PC has too many remote connections already.';
      case 'auth_failed':
        return 'The PC did not accept this phone.';
      case 'unreachable':
        return "Can't reach the PC.";
      case 'refused':
        return 'That address is not a SALU Remote.';
      case 'not_paired':
        return 'This phone is not paired with the PC yet.';
      default:
        return fromPc ?? 'Something went wrong.';
    }
  }

  /// The empty-state line for each dead-end screen (§7's table, as a function).
  ///
  /// Web mode has no empty state any more (2026-09-23): the Tune tab becomes a
  /// D-pad that draws only the keys the PC answers, so the honest line lives in
  /// the pad itself rather than here.
  static String emptyTune(SaluSnapshot? snapshot) {
    if (snapshot == null) return 'Waiting for your PC…';
    if (!snapshot.playback.hasSomething) return 'Nothing is playing';
    return 'Nothing to adjust yet.';
  }
}
