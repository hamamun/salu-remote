import 'dart:async';

import 'package:flutter/material.dart';

import '../core/client.dart';
import '../core/models.dart';
import '../core/prefs.dart';
import '../core/reply.dart';
import 'theme.dart';
import 'widgets.dart';

/// Tune → Equalizer (`remote_apk_ui.md` §6.1).
///
/// The PC's Tune panel has four lines — EQ, Picture, Aspect, Speed. v1 sends
/// the EQ line and the Speed line; the phone never guesses a preset list, it
/// renders whatever `tune_get` sends, in the PC's order.
///
/// **The drag protocol** (same as the PC's own panel): one drag is
/// `eq_gesture begin` → continuous `eq_band` writes (the PC coalesces at
/// 120 ms) → `eq_set` with the whole curve → `eq_gesture end`. So it is one
/// undoable edit on the PC, never sixty.
class EqualizerPane extends StatefulWidget {
  const EqualizerPane({
    super.key,
    required this.snapshot,
    required this.activeTab,
    required this.myIndex,
  });

  final SaluSnapshot snapshot;
  final ValueListenable<int> activeTab;
  final int myIndex;

  @override
  State<EqualizerPane> createState() => _EqualizerPaneState();
}

const List<String> _bandFreqs = <String>[
  '31', '63', '125', '250', '500', '1k', '2k', '4k', '8k', '16k',
];

class _EqualizerPaneState extends State<EqualizerPane> {
  static const double _minDb = -12;
  static const double _maxDb = 12;

  final SaluClient _client = SaluClient.instance;
  TuneInfo? _info;
  List<double> _gains = List<double>.filled(TuneInfo.bandCount, 0);
  int? _draggingBand;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.activeTab.addListener(_onActive);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.activeTab.removeListener(_onActive);
    super.dispose();
  }

  void _onActive() {
    // Coming back to the tab: the curve may have changed on the PC.
    if (widget.activeTab.value == widget.myIndex) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = _info == null;
      _error = null;
    });
    final RemoteReply reply = await _client.tuneGet();
    if (!mounted) return;
    if (reply.ok) {
      final TuneInfo info = TuneInfo.from(reply.data);
      setState(() {
        _info = info;
        _gains = info.curve;
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = reply.message;
      });
    }
  }

  // ── the drag protocol ────────────────────────────────────────────────────

  void _bandBegin(int band) {
    if (_draggingBand != null) return;
    _draggingBand = band;
    unawaited(_client.eqGesture('begin'));
  }

  void _bandChanged(int band, double db) {
    if (_draggingBand == null) return; // a stray drag outside a gesture
    final double clamped = db.clamp(_minDb, _maxDb);
    setState(() {
      _gains = List<double>.of(_gains)..[band] = clamped;
    });
    unawaited(_client.eqBand(band, clamped));
  }

  Future<void> _bandEnd() async {
    if (_draggingBand == null) return;
    _draggingBand = null;
    await _client.eqSet(_gains);
    await _client.eqGesture('end');
  }

  // ── discrete actions ─────────────────────────────────────────────────────

  Future<void> _preset(String key) async {
    final bool ok = (await runRemote(context, () => _client.eqPreset(key))).ok;
    if (ok) await _load();
  }

  Future<void> _saveMy() async {
    final bool ok = (await runRemote(context, () => _client.eqSaveMy())).ok;
    if (ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved as My')));
    }
  }

  Future<void> _reset() async {
    final bool ok = (await runRemote(context, () => _client.eqReset())).ok;
    if (ok && mounted) {
      setState(() => _gains = List<double>.filled(TuneInfo.bandCount, 0));
    }
    await _load();
  }

  Future<void> _autoEq(bool on) async {
    final bool ok = (await runRemote(context, () => _client.autoEq(on))).ok;
    if (ok) await _load();
  }

  Future<void> _speed(String key) async {
    final bool ok = (await runRemote(context, () => _client.speedSet(key))).ok;
    if (ok) await _load();
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TuneInfo? info = _info;
    if (info == null) {
      if (_error != null) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            EmptyState(
              message: _error ?? "The PC didn't answer.",
              actionLabel: 'Try again',
              onAction: () => unawaited(_load()),
            ),
          ],
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (!info.available) {
      return const ListView(
        padding: EdgeInsets.all(16),
        children: <Widget>[
          EmptyState(message: 'Nothing to adjust yet.'),
        ],
      );
    }
    // Landscape, decided: yes — but only here (§6.1). The equalizer becomes
    // a mixing desk: curve + presets in a left rail, all ten sliders
    // full-height on the right.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool landscape = constraints.maxWidth > constraints.maxHeight;
        return landscape
            ? _landscape(info, constraints)
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: _portrait(info),
              );
      },
    );
  }

  List<Widget> _portrait(TuneInfo info) => <Widget>[
        SaluCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CurvePreview(gains: _gains),
              const SizedBox(height: 12),
              _presets(info),
              const SizedBox(height: 10),
              _myChip(info),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              _SlidersRow(
                gains: _gains,
                trackHeight: 120,
                onBegin: _bandBegin,
                onChanged: _bandChanged,
                onEnd: () => unawaited(_bandEnd()),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  FilledButton.tonal(
                    onPressed: () => unawaited(_reset()),
                    child: const Text('Reset'),
                  ),
                  const Spacer(),
                  Switch(
                    value: info.autoEq,
                    onChanged: (bool v) => unawaited(_autoEq(v)),
                    title: const Text('Auto EQ', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Learned from what you keep',
                  style: TextStyle(fontSize: 11.5, color: AppColors.statusUnknown),
                ),
              ),
            ],
          ),
        ),
        if (RemotePrefs.instance.isShown(PlaySection.speedChips))
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: _speedSection(info),
          ),
      ];

  Widget _landscape(TuneInfo info, BoxConstraints constraints) {
    final double slidersHeight =
        (constraints.maxHeight - 90).clamp(140.0, 600.0);
    return Row(
      children: <Widget>[
        Expanded(
          flex: 5,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 24),
            children: <Widget>[
              SaluCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _CurvePreview(gains: _gains),
                    const SizedBox(height: 12),
                    _presets(info),
                    const SizedBox(height: 10),
                    _myChip(info),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        FilledButton.tonal(
                          onPressed: () => unawaited(_reset()),
                          child: const Text('Reset'),
                        ),
                        const Spacer(),
                        Switch(
                          value: info.autoEq,
                          onChanged: (bool v) => unawaited(_autoEq(v)),
                          title: const Text(
                              'Auto EQ',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Learned from what you keep',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.statusUnknown),
                      ),
                    ),
                  ],
                ),
              ),
              if (RemotePrefs.instance.isShown(PlaySection.speedChips))
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _speedSection(info),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 24),
            child: SaluCard(
              child: _SlidersRow(
                gains: _gains,
                trackHeight: slidersHeight,
                onBegin: _bandBegin,
                onChanged: _bandChanged,
                onEnd: () => unawaited(_bandEnd()),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _presets(TuneInfo info) {
    return SizedBox(
      height: 46,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final TunePresetInfo preset in info.presets)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SaluChip(
                  icon: Icons.bars,
                  label: preset.label,
                  active: info.eqStop == preset.key,
                  onTap: () => unawaited(_preset(preset.key)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The PC's "My" slot: tap applies it, a long-press overwrites it with the
  /// current curve (the only destructive-ish EQ act, and it is one tap to
  /// undo by re-saving).
  Widget _myChip(TuneInfo info) {
    return Row(
      children: <Widget>[
        SaluChip(
          icon: Icons.star,
          label: 'My',
          active: info.eqStop == 'my',
          onTap: () => unawaited(_preset('my')),
          onLongPress: () => unawaited(_saveMy()),
        ),
        if (info.custom) ...<Widget>[
          const SizedBox(width: 10),
          const Text('custom',
              style: TextStyle(fontSize: 11.5, color: AppColors.statusUnknown)),
        ],
      ],
    );
  }

  Widget _speedSection(TuneInfo info) {
    if (info.speedKeys.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('Speed', style: Theme.of(context).textTheme.titleMedium),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final TuneStop stop in info.speedKeys)
              SaluChip(
                icon: Icons.speed,
                label: stop.label,
                active: stop.key == info.speed,
                onTap: () => unawaited(_speed(stop.key)),
              ),
          ],
        ),
      ],
    );
  }
}

/// Ten vertical band sliders — they beat a draggable curve on a phone: fat
/// thumbs, no fine aiming, a slider can be grabbed anywhere along its height
/// (`remote_apk_ui.md` §6.1).
class _SlidersRow extends StatelessWidget {
  const _SlidersRow({
    required this.gains,
    required this.trackHeight,
    required this.onBegin,
    required this.onChanged,
    required this.onEnd,
  });

  final List<double> gains;
  final double trackHeight;
  final void Function(int band) onBegin;
  final void Function(int band, double db) onChanged;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: trackHeight + 40,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < gains.length; i++)
            Expanded(
              child: _BandSlider(
                label: _bandFreqs[i],
                value: gains[i],
                trackHeight: trackHeight,
                onBegin: () => onBegin(i),
                onChanged: (double db) => onChanged(i, db),
                onEnd: onEnd,
              ),
            ),
        ],
      ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    super.key,
    required this.label,
    required this.value,
    required this.trackHeight,
    required this.onBegin,
    required this.onChanged,
    required this.onEnd,
  });

  final String label;
  final double value;
  final double trackHeight;
  final VoidCallback onBegin;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  double _dbAt(double y) {
    final double clamped = y.clamp(0.0, trackHeight);
    return 12.0 - (clamped / trackHeight) * 24.0;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        // A raw [Listener], not a gesture: a pan recognizer would compete
        // with the surrounding ListView for the vertical drag (and a lost
        // gesture would leave the EQ in a half-open gesture), while pointer
        // events are ours the moment the finger touches the track. A tap
        // anywhere on the track sets the band to exactly that height.
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (PointerDownEvent e) {
            onBegin();
            onChanged(_dbAt(e.localPosition.dy));
          },
          onPointerMove: (PointerMoveEvent e) => onChanged(_dbAt(e.localPosition.dy)),
          onPointerUp: (PointerUpEvent e) => onEnd(),
          onPointerCancel: (_) => onEnd(),
          child: CustomPaint(
            size: Size(34, trackHeight),
            painter: _BandPainter(value: value, height: trackHeight),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.statusUnknown)),
        const SizedBox(height: 2),
        Text(
          value == 0 ? '0' : value.toStringAsFixed(1),
          style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _BandPainter extends CustomPainter {
  _BandPainter({required this.value, required this.height});

  final double value;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    // The track.
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.height),
      Paint()..color = AppColors.barTrack..strokeWidth = 2,
    );
    // The 0 dB mark.
    canvas.drawLine(
      Offset(cx - 6, size.height / 2),
      Offset(cx + 6, size.height / 2),
      Paint()..color = AppColors.statusUnknown..strokeWidth = 1.2,
    );
    // The thumb — a horizontal bar at the band's value.
    final double y = ((12.0 - value) / 24.0 * size.height).clamp(0.0, size.height);
    final RRect thumb = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - 11, y - 2.5, 22, 5),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(thumb, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(_BandPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.height != height;
}

/// The live curve above the sliders: a quiet hairline through the ten band
/// values, with the 0 dB line dashed. Redraws as you drag (the pane passes
/// its live `_gains` list on every build).
class _CurvePreview extends StatelessWidget {
  const _CurvePreview({required this.gains});

  final List<double> gains;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: CustomPaint(painter: _CurvePainter(gains: gains)),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({required this.gains});

  final List<double> gains;

  @override
  void paint(Canvas canvas, Size size) {
    if (gains.length < 2) return;
    final double mid = size.height / 2;
    // The 0 dB line, dashed.
    final Paint dash = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1.2;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, mid), Offset((x + 4).clamp(0.0, size.width), mid), dash);
    }
    // The curve.
    final Path path = Path();
    final double amp = size.height / 2 - 6;
    for (int i = 0; i < gains.length; i++) {
      final double x = size.width * i / (gains.length - 1);
      final double y = mid - (gains[i] / 12.0) * amp;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter oldDelegate) => oldDelegate.gains != gains;
}
