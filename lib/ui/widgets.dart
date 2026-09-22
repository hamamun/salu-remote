import 'dart:async';

import 'package:flutter/material.dart';

import '../core/client.dart';
import '../core/error_copy.dart';
import '../core/models.dart';
import '../core/prefs.dart';
import '../core/reply.dart';
import 'theme.dart';

/// Fire a verb, and if the PC refused it, say why in its own words — unless
/// the code is one the specs deliberately keep silent (`remote.md` §17.8,
/// where `too_fast` and `no_preset` are "(silent, logged)").
///
/// Every screen funnels its verbs through this one function, so the snackbar
/// wording can never drift from `RemoteErrorCopy`.
Future<RemoteReply> runRemote(BuildContext context, Future<RemoteReply> Function() action) async {
  final RemoteReply reply = await action();
  if (!reply.ok && !RemoteErrorCopy.isSilent(reply.code) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(RemoteErrorCopy.text(reply.code, reply.message))),
    );
  }
  return reply;
}

/// A SALU chip: hairline pill, icon + label, accent when active.
/// (The Play chip row, the EQ presets and the speed stops all use this.)
class SaluChip extends StatelessWidget {
  const SaluChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.onLongPress,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final VoidCallback? onLongPress;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.surfaceHighlight : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: active ? AppColors.accent : AppColors.surfaceOutline,
          width: 1.2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 18,
                color: active
                    ? AppColors.accent
                    : enabled
                        ? AppColors.iconIdle
                        : AppColors.statusUnknown,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: enabled ? AppColors.textPrimary : AppColors.statusUnknown,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One option in a [SaluSegments] switch.
class SegmentOption {
  const SegmentOption(this.label, {this.enabled = true});

  final String label;
  final bool enabled;
}

/// The segmented switch used at the top of Browse (Files · Streams) and Tune
/// (Equalizer · Subtitles · Audio). One hairline track, the active seat
/// filled — the phone scale of the PC's own segments.
class SaluSegments extends StatelessWidget {
  const SaluSegments({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<SegmentOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.videoBackdrop,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceOutline, width: 1.2),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < options.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: options[i].enabled ? () => onSelect(i) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: i == selectedIndex
                        ? AppColors.surfaceHighlight
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: i == selectedIndex ? AppColors.accent : Colors.transparent,
                      width: 1.2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    options[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: i == selectedIndex ? FontWeight.w600 : FontWeight.w400,
                      color: i == selectedIndex
                          ? AppColors.textPrimary
                          : options[i].enabled
                              ? AppColors.textSecondary
                              : AppColors.statusUnknown,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A card with a tap-to-collapse header (`Queue · 12 items ⌄`, `Presets ⌄`,
/// `Sync ⌄` — `remote_apk_ui.md` §3). The collapsed/expanded state is
/// remembered per section in `RemotePrefs`. An optional [action] sits at the
/// far end of the header row (the Queue card's clear button).
class SectionCard extends StatefulWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.action,
    this.memoryKey,
    this.expandedByDefault = true,
    this.padding = const EdgeInsets.fromLTRB(16, 6, 16, 14),
  });

  final String title;
  final Widget child;
  final String? trailing;

  /// A button at the end of the header row. It lives **outside** the
  /// collapse InkWell, so tapping it never collapses the card.
  final Widget? action;
  final String? memoryKey;
  final bool expandedByDefault;
  final EdgeInsets padding;

  @override
  State<SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<SectionCard> {
  late bool _expanded =
      widget.memoryKey == null
          ? widget.expandedByDefault
          : !RemotePrefs.instance.isCollapsed(widget.memoryKey!);

  @override
  Widget build(BuildContext context) {
    return SaluCard(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          size: 20,
                          color: AppColors.iconIdle,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (widget.trailing != null)
                          Text(
                            widget.trailing!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.action != null) widget.action!,
            ],
          ),
          if (_expanded) ...<Widget>[
            Padding(
              padding: widget.padding.copyWith(top: 4),
              child: widget.child,
            ),
          ],
        ],
      ),
    );
  }
}

/// The header's second dot (`remote_apk_ui.md` §4.1 "Activity dot"): it
/// appears only after 300 ms of a command in flight, so a fast call never
/// makes it flicker. One dot, no text.
class ActivityDot extends StatefulWidget {
  const ActivityDot({super.key});

  @override
  State<ActivityDot> createState() => _ActivityDotState();
}

class _ActivityDotState extends State<ActivityDot> {
  Timer? _timer;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    SaluClient.instance.inFlight.addListener(_onInFlight);
    _onInFlight();
  }

  @override
  void dispose() {
    _timer?.cancel();
    SaluClient.instance.inFlight.removeListener(_onInFlight);
    super.dispose();
  }

  void _onInFlight() {
    final int count = SaluClient.instance.inFlight.value;
    if (count > 0) {
      _timer ??= Timer(const Duration(milliseconds: 300), () {
        _timer = null;
        if (SaluClient.instance.inFlight.value > 0 && mounted) {
          setState(() => _show = true);
        }
      });
    } else {
      _timer?.cancel();
      _timer = null;
      if (_show) setState(() => _show = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Container(
      width: 6,
      height: 6,
      margin: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
    );
  }
}

/// One `label · value` line — the Connect sheet's diagnostics, the Settings
/// sheet's phone facts.
class FactRow extends StatelessWidget {
  const FactRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 108,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// The plain-words dead end (`remote_apk_ui.md` §7): one honest line, and
/// optionally the one action that gets the user out.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SaluCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(message, style: Theme.of(context).textTheme.titleMedium),
          if (actionLabel != null) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// The PC's verdict on a saved stream's URL, as a dot — never the phone's
/// guess (`remote_apk_ui.md` §5.2).
class HealthDot extends StatelessWidget {
  const HealthDot({super.key, required this.health});

  final UrlHealth health;

  @override
  Widget build(BuildContext context) {
    final Color colour;
    switch (health) {
      case UrlHealth.alive:
        colour = AppColors.statusAlive;
      case UrlHealth.dead:
        colour = AppColors.statusDead;
      case UrlHealth.unknown:
        colour = AppColors.statusUnknown;
    }
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
    );
  }
}

/// True when the text reads as something the PC's `open_url` can classify —
/// a direct stream, a YouTube link, an `.m3u` URL or a plain web link. Used
/// for the paste detection that pre-fills the URL boxes
/// (`remote_apk_ui.md` §12 rule 6).
bool looksLikeUrl(String text) {
  final String t = text.trim();
  if (t.isEmpty) return false;
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').hasMatch(t)) return true;
  return t.startsWith('www.');
}
