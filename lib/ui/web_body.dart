import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/client.dart';
import '../core/models.dart';
import '../core/reply.dart';
import 'theme.dart';
import 'widgets.dart';

/// The Play tab in Web mode (`remote_apk_ui.md` §4.2): the same tab,
/// transformed — because the mode *is* the same remote pointed at a
/// different thing.
///
/// Two shapes, per the user's rule: **when the page is playing media, only
/// the basics** (play/pause, seek, volume, mute, fullscreen), because that is
/// all most online players expose. When the page has no reachable media, the
/// nav body. The controls drive the *page's own player* (JavaScript on the
/// PC side, `remote.md` §17.11) — never mpv, never the Windows volume.
class WebBody extends StatefulWidget {
  const WebBody({super.key, required this.snapshot, required this.activeTab});

  final SaluSnapshot snapshot;

  /// The root's active-tab notifier. The ~1/s `web_media_get` poll runs only
  /// while this tab is on screen (`remote_apk_ui.md` §8).
  final ValueListenable<int> activeTab;

  static const int tabIndex = 0;

  @override
  State<WebBody> createState() => _WebBodyState();
}

class _WebBodyState extends State<WebBody> {
  final SaluClient _client = SaluClient.instance;
  Timer? _poll;
  WebMediaInfo? _media;

  /// A failed write (`no_web_media`) means the player is behind a
  /// cross-origin iframe or DRM — drop back to the nav shape and say so in
  /// one plain line, instead of leaving dead buttons.
  bool _unreachable = false;

  @override
  void initState() {
    super.initState();
    _client.link.addListener(_onLink);
    widget.activeTab.addListener(_onActive);
    _onActive();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_pollOnce()));
  }

  @override
  void dispose() {
    _client.link.removeListener(_onLink);
    widget.activeTab.removeListener(_onActive);
    _poll?.cancel();
    super.dispose();
  }

  void _onLink() {
    // The link dropped: a stale "playing" dot would be a lie.
    if (!_client.isOnline && _media != null) {
      setState(() => _media = null);
    }
    _onActive();
  }

  void _onActive() {
    final bool should =
        widget.activeTab.value == WebBody.tabIndex && _client.isOnline;
    if (should) {
      _poll ??= Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_pollOnce()));
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _pollOnce() async {
    final RemoteReply reply = await _client.webMediaGet();
    if (!mounted || !reply.ok) return;
    final WebMediaInfo info = WebMediaInfo.from(reply.data);
    if (!identical(info, _media)) {
      setState(() => _media = info);
    }
  }

  Future<void> _guarded(Future<RemoteReply> Function() action) async {
    final RemoteReply reply = await runRemote(context, action);
    if (!reply.ok && reply.code == 'no_web_media') {
      setState(() {
        _unreachable = true;
        _media = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final SaluWeb web = widget.snapshot.web;
    final WebMediaInfo? media = _media;
    final bool showMedia = _client.isOnline && media?.found == true && !_unreachable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _navRow(web, pageFullscreen: showMedia),
        const SizedBox(height: 12),
        if (showMedia)
          _mediaShape(web, media!)
        else ...<Widget>[
          _navShape(web),
          if (_unreachable) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.lock_outline, size: 16, color: AppColors.statusDead),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "This site's player can't be controlled from outside.",
                    style: const TextStyle(color: AppColors.statusDead, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  // ── nav row ──────────────────────────────────────────────────────────────

  /// One quiet row of page navigation. In the media shape the fullscreen
  /// mark drives the page's player; in the nav shape it drives the SALU
  /// window.
  Widget _navRow(SaluWeb web, {required bool pageFullscreen}) {
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: 'Back',
          onPressed: web.canBack
              ? () => unawaited(runRemote(context, () => _client.browserNav('back')))
              : null,
          icon: Icon(Icons.arrow_back, color: web.canBack ? AppColors.iconIdle : AppColors.statusUnknown),
        ),
        IconButton(
          tooltip: 'Forward',
          onPressed: web.canForward
              ? () => unawaited(runRemote(context, () => _client.browserNav('forward')))
              : null,
          icon: Icon(Icons.arrow_forward, color: web.canForward ? AppColors.iconIdle : AppColors.statusUnknown),
        ),
        IconButton(
          tooltip: web.loading ? 'Stop' : 'Reload',
          onPressed: () => unawaited(
            runRemote(
              context,
              () => _client.browserNav(web.loading ? 'stop' : 'reload'),
            ),
          ),
          icon: Icon(
            web.loading ? Icons.stop : Icons.refresh,
            color: AppColors.iconIdle,
          ),
        ),
        IconButton(
          tooltip: pageFullscreen ? 'Page fullscreen' : 'Fullscreen',
          onPressed: pageFullscreen
              ? (_media?.canFullscreen ?? false)
                  ? () => unawaited(_guarded(_client.webMediaFullscreen))
                  : null
              : () => unawaited(runRemote(context, _client.fullscreenToggle)),
          icon: Icon(
            pageFullscreen
                ? (web.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen)
                : (widget.snapshot.window.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
            color: AppColors.iconIdle,
          ),
        ),
        const Spacer(),
        if (web.loading)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        Text(
          '${web.tabs} ${web.tabs == 1 ? 'tab' : 'tabs'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  // ── shape 1: the page has a player ───────────────────────────────────────

  Widget _mediaShape(SaluWeb web, WebMediaInfo media) {
    final bool seekable = media.duration > Duration.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => unawaited(_urlDialog()),
          child: SaluCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  web.title ?? 'Loading…',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (web.url != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      web.url!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (seekable)
          SaluCard(
            margin: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CommitSlider(
                  value: media.position.inMilliseconds.toDouble(),
                  max: media.duration.inMilliseconds.toDouble(),
                  onCommit: (double value) => unawaited(
                    _guarded(() => _client.webMediaSeek(to: value.round())),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(SaluTheme.clock(media.position),
                        style: Theme.of(context).textTheme.bodySmall),
                    Text(SaluTheme.clock(media.duration),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        // The big play/pause — the one button.
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: IconButton.filled(
              iconSize: 52,
              tooltip: media.playing ? 'Pause' : 'Play',
              onPressed: () => unawaited(_guarded(_client.webMediaToggle)),
              icon: Icon(media.playing ? Icons.pause : Icons.play_arrow,
                  size: 46),
            ),
          ),
        ),
        // The page player's own volume — it never touches the Windows volume.
        SaluCard(
          padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: media.muted ? 'Unmute' : 'Mute',
                onPressed: () =>
                    unawaited(_guarded(() => _client.webMediaMute(!media.muted))),
                icon: Icon(
                  media.muted ? Icons.volume_off : Icons.volume_up,
                  color: media.muted ? AppColors.statusDead : AppColors.iconIdle,
                ),
              ),
              Expanded(
                child: CommitSlider(
                  value: media.volume.toDouble(),
                  max: 100,
                  onCommit: (double value) => unawaited(
                    _guarded(() => _client.webMediaVolume(value.round())),
                  ),
                ),
              ),
              SizedBox(
                width: 38,
                child: Text(
                  '${media.volume}',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── shape 2: no media on the page ────────────────────────────────────────

  Widget _navShape(SaluWeb web) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SaluCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                web.title ?? 'Loading…',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (web.url != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    web.url!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.link),
          label: const Text('Open a URL on the PC'),
          onPressed: () => unawaited(_urlDialog()),
        ),
      ],
    );
  }

  // ── the URL box ──────────────────────────────────────────────────────────

  /// "Open a URL on the PC" — the sleeper feature (`remote_apk_ui.md` §4.2):
  /// type or paste on the phone, the PC browser goes there. The field is
  /// pre-filled with the clipboard when it holds a URL (the one-keyboard
  /// rule, §12).
  ///
  /// Uses the State's own [context] rather than a caller-supplied one: the
  /// clipboard read is an async gap, and only `State.mounted` can vouch for
  /// `State.context` afterwards (`use_build_context_synchronously`).
  Future<void> _urlDialog() async {
    final TextEditingController text = TextEditingController();
    final String current = widget.snapshot.web.url ?? '';
    // Check the clipboard before the dialog opens, so the field is
    // pre-filled in the first frame.
    final ClipboardData? clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboard?.text case final String? clip when looksLikeUrl(clip ?? '')) {
      text.text = clip!;
    }
    if (!mounted) return;
    try {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Open a URL on the PC'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (current.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Current: $current',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ),
              TextField(
                controller: text,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Address or link',
                  hintText: 'https://…',
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                unawaited(runRemote(context, () => _client.browserNav('reload')));
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Reload'),
            ),
            FilledButton(
              onPressed: () {
                final String url = text.text.trim();
                if (url.isEmpty) return;
                unawaited(runRemote(context, () => _client.openUrl(url)));
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Open'),
            ),
          ],
        ),
      );
    } finally {
      text.dispose();
    }
  }
}
