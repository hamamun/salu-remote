import 'package:flutter/material.dart';

import '../core/prefs.dart';
import 'theme.dart';

/// The phone's own settings (`remote_apk_ui.md` §3, mechanisms 1 and 2):
/// the name the PC shows in its Phones list, and the permanent version of
/// show/hide — a checkbox list of every optional element.
///
/// Defaults: everything on. Ship complete, let people subtract.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.onChanged});

  /// Called after any change, so the shell (bottom bar, Play sections)
  /// re-reads the preferences immediately.
  final VoidCallback onChanged;

  static void show(BuildContext context, {required VoidCallback onChanged}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) => SettingsSheet(onChanged: onChanged),
    );
  }

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: RemotePrefs.instance.deviceName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    await RemotePrefs.instance.setDeviceName(_name.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name saved.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> sections = PlaySection.all;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceOutline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 14),
            Text('This phone', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name shown on the PC'),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _saveName,
                  child: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text('Play screen', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            // The spec's two-column checklist, in the spec's own order.
            for (int i = 0; i < sections.length; i += 2)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: <Widget>[
                    Expanded(child: _check(sections[i])),
                    Expanded(
                      child: i + 1 < sections.length ? _check(sections[i + 1]) : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _check(String key) {
    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        PlaySectionLabel.of(key),
        style: const TextStyle(fontSize: 13.5),
      ),
      value: RemotePrefs.instance.isShown(key),
      onChanged: (bool? value) {
        if (value == null) return;
        RemotePrefs.instance.setShown(key, value);
        widget.onChanged();
      },
    );
  }
}

/// The words for each [PlaySection] key, straight from `remote_apk_ui.md` §3.
abstract final class PlaySectionLabel {
  static String of(String key) {
    switch (key) {
      case PlaySection.volume:
        return 'Volume row';
      case PlaySection.modePill:
        return 'Mode pill (Player/Web)';
      case PlaySection.chips:
        // Was "Secondary chips"; the text chips became the icon-only
        // repeat · shuffle row (user, 2026-09-22). Same settings key.
        return 'Shuffle & repeat row';
      case PlaySection.queue:
        return 'Queue card';
      case PlaySection.miniStrip:
        return 'Mini now-playing strip on Browse / Tune';
      case PlaySection.tuneTab:
        return 'Tune tab';
      case PlaySection.streamsSegment:
        return 'Streams segment';
      case PlaySection.subtitlesCard:
        return 'Subtitles segment (in Tune)';
      case PlaySection.speedChips:
        return 'Speed chips (in Tune → Equalizer)';
      default:
        return key;
    }
  }
}
