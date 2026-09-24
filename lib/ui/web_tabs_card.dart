import 'dart:async';

import 'package:flutter/material.dart';

import '../core/client.dart';
import '../core/error_copy.dart';
import '../core/models.dart';
import '../core/prefs.dart';
import '../core/reply.dart';
import 'theme.dart';
import 'widgets.dart';

/// **The open tabs, as a section of the Web body** (user, 2026-09-24).
///
/// This replaces the `▢ 3 tabs` button that used to end the nav row and the
/// bottom sheet behind it. The user's ask, in their own words: *"i need that
/// thing will show below volume bar and there will be heading open tab just
/// like queue for normal player and will have collapse/expand option like
/// queue. under that label all open tabs will show."*
///
/// So it is built like [QueueCard] on purpose — same card, same chevron, same
/// remembered open/closed state (`RemotePrefs`), same *at most five rows, scroll
/// inside* window. A couch user learns one row-panel and it is the same row-panel
/// everywhere in the app.
///
/// Why a section and not a sheet: switching tabs is *looking at another page*,
/// and a sheet covers the page you are about to look at. The section leaves the
/// page card, the player controls and the new-tab door all visible, and it is
/// one tap away when the strip matters and zero pixels when it does not.
///
/// Nothing here rides the snapshot: a strip of 40 tabs would eat the whole 8 KB
/// frame budget, so the list is one `web_tabs_get` when the card opens, when the
/// PC's own tab count changes, and after every switch or close (`remote.md`
/// §17.13, §17.14). A PC that never advertises `web_tabs` gets one honest line
/// and a ＋ that still opens a URL.
class WebTabsCard extends StatefulWidget {
  const WebTabsCard({
    super.key,
    required this.snapshot,
    required this.onNewTab,
    this.onTabChanged,
  });

  final SaluSnapshot snapshot;

  /// The ＋ in the header — the same URL box as the "New tab" chip, so the door
  /// every PC can honour is always one tap from the list itself.
  final VoidCallback onNewTab;

  /// A tab was switched or closed: the body's page media poll should re-read,
  /// because the page under the controls has just changed.
  final VoidCallback? onTabChanged;

  /// The collapse key — its own section, remembered like the queue's.
  static const String collapseKey = 'web_tabs';

  @override
  State<WebTabsCard> createState() => _WebTabsCardState();
}

class _WebTabsCardState extends State<WebTabsCard> {
  static const double _rowHeight = 44;
  static const int _visibleRows = 5;

  /// A floor between reads: the snapshot's tab count can tick twice in a
  /// second while a page loads, and the strip is a list, not a scalar.
  static const Duration _minGap = Duration(milliseconds: 700);

  final SaluClient _client = SaluClient.instance;

  WebTabPage? _page;
  String? _error;
  bool _loading = false;

  /// Bumped by every fetch, so a late reply can never overwrite a newer one.
  int _generation = 0;
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);

  late bool _expanded;

  bool get _supported => _client.supportsWebTabs;

  /// What the header shows before (or without) a list: the snapshot's own
  /// scalar, which every PC has always sent.
  int get _count => _page?.count ?? widget.snapshot.web.tabs;

  @override
  void initState() {
    super.initState();
    _expanded = !RemotePrefs.instance.isCollapsed(WebTabsCard.collapseKey);
    if (_expanded) unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant WebTabsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The strip moved under us — a tab opened, closed, or the page navigated.
    // Only while the list is actually on screen: a collapsed card costs the PC
    // nothing.
    final SaluWeb web = widget.snapshot.web;
    final SaluWeb old = oldWidget.snapshot.web;
    if (web.tabs != old.tabs || web.url != old.url) {
      if (_expanded) unawaited(_refresh());
    }
  }

  Future<void> _refresh({bool force = false}) async {
    if (!_supported || _loading) return;
    if (!force && DateTime.now().difference(_lastFetch) < _minGap) return;
    _lastFetch = DateTime.now();
    final int generation = ++_generation;
    if (mounted) setState(() => _loading = true);
    final RemoteReply reply = await _client.webTabsGet();
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      if (reply.ok) {
        _page = WebTabPage.from(reply.data);
        _error = null;
      } else {
        _error = RemoteErrorCopy.text(reply.code, reply.message);
      }
    });
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    unawaited(RemotePrefs.instance.setCollapsed(
      WebTabsCard.collapseKey,
      !_expanded,
    ));
    if (_expanded) unawaited(_refresh(force: true));
  }

  Future<void> _activate(WebTabInfo tab) async {
    final RemoteReply reply =
        await runRemote(context, () => _client.webTabActivate(tab.index));
    if (!mounted || !reply.ok) return;
    widget.onTabChanged?.call();
    await _refresh(force: true);
  }

  Future<void> _close(WebTabInfo tab) async {
    final RemoteReply reply =
        await runRemote(context, () => _client.webTabClose(tab.index));
    if (!mounted || !reply.ok) return;
    widget.onTabChanged?.call();
    await _refresh(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return SaluCard(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _header(),
          if (_expanded) _body(),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 20,
                  color: AppColors.iconIdle,
                ),
                const SizedBox(width: 2),
                Text('Open tabs', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ),
        // The count only means something on a PC that reports its strip; a
        // "0 tabs" beside "does not report its tabs yet" would be a small lie.
        if (_supported) ...<Widget>[
          const SizedBox(width: 8),
          Text(
            '$_count ${_count == 1 ? 'tab' : 'tabs'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const Spacer(),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        IconButton(
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          tooltip: 'New tab',
          color: AppColors.iconIdle,
          onPressed: widget.onNewTab,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  Widget _body() {
    if (!_supported) {
      return _line(
        'This PC does not report its tabs yet — the ＋ above still opens a page.',
      );
    }
    final WebTabPage? page = _page;
    if (page == null) {
      if (_error != null) {
        return Row(
          children: <Widget>[
            Expanded(child: _line(_error!)),
            TextButton(
              onPressed: () => unawaited(_refresh(force: true)),
              child: const Text('Try again'),
            ),
          ],
        );
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (page.isEmpty) return _line('No tabs open on the PC right now.');
    // Five rows at most, fewer when the strip is shorter — the queue card's
    // own window rule, because this is the same kind of panel.
    final int windowed =
        page.tabs.length < _visibleRows ? page.tabs.length : _visibleRows;
    final double height =
        windowed * _rowHeight + (windowed > 1 ? windowed - 1 : 0);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: SizedBox(
        height: height,
        child: ListView.separated(
          padding: EdgeInsets.zero,
          physics: const ClampingScrollPhysics(),
          itemCount: page.tabs.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, color: AppColors.divider),
          itemBuilder: (BuildContext context, int i) =>
              _row(page.tabs[i], page.isActive(page.tabs[i])),
        ),
      ),
    );
  }

  Widget _row(WebTabInfo tab, bool active) {
    return InkWell(
      // The live tab is not a door to itself.
      onTap: active ? null : () => unawaited(_activate(tab)),
      child: SizedBox(
        height: _rowHeight,
        child: Row(
          children: <Widget>[
            Icon(
              active ? Icons.play_arrow : Icons.web_asset,
              size: 18,
              color: active ? AppColors.accent : AppColors.statusUnknown,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (tab.url.isNotEmpty)
                    Text(
                      tab.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (tab.loading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            IconButton(
              tooltip: 'Close tab',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              onPressed: () => unawaited(_close(tab)),
              icon: const Icon(Icons.close, color: AppColors.iconIdle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
