import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/deep_link.dart';
import 'theme.dart';

/// The in-app half of QR pairing (D2): the phone's camera reads the
/// `salu://pair` QR from the PC's Remote panel.
///
/// The camera app's own QR reader works too — the manifest registers a
/// `salu://pair` intent filter, so "Open with SALU Remote" is offered for
/// any scan. Both paths hand the same [PairLink] to the app (`DeepLink`).
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  /// Pushes the scanner; resolves to the scanned link, or `null` when the
  /// user cancelled (or had no camera to offer).
  static Future<PairLink?> open(BuildContext context) async {
    final PairLink? result =
        await Navigator.of(context).push<PairLink>(
          MaterialPageRoute<PairLink>(builder: (_) => const QrScanScreen()),
        );
    return result;
  }

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  late final MobileScannerController _controller;
  bool _handled = false;
  bool _cameraReady = false;
  bool _cameraDenied = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.normal,
      autoStart: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_startCamera()));
  }

  Future<void> _startCamera() async {
    try {
      await _controller.start();
      if (!mounted) return;
      setState(() {
        _cameraReady = true;
        _cameraDenied = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cameraReady = false;
        _cameraDenied = true;
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final Barcode barcode in capture.barcodes) {
      final PairLink? link = DeepLink.parse(barcode.rawValue);
      if (link != null) {
        _handled = true;
        unawaited(_controller.stop());
        HapticFeedback.mediumImpact();
        if (mounted) {
          Navigator.of(context).pop(link);
        }
        return;
      }
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.videoBackdrop,
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text('Scan the QR'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (!_cameraDenied)
                    MobileScanner(
                      controller: _controller,
                      onDetect: _cameraReady ? _onDetect : null,
                    )
                  else
                    const _CameraUnavailable(),
                  // The viewfinder: everything dimmed except a quiet rounded
                  // square, so the eye (and the camera) knows where to aim.
                  if (_cameraReady && !_handled)
                    const _ViewfinderOverlay(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
              child: Text(
                _cameraDenied
                    ? 'The camera is not available. Open SALU on the PC and type the code instead — it is shown under the QR.'
                    : 'Point the camera at the QR in the PC\'s Remote panel (right-click the picture → Remote).',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims the whole frame and leaves one 220×220 rounded square clear.
class _ViewfinderOverlay extends StatelessWidget {
  const _ViewfinderOverlay();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        final Rect cutout = Rect.fromCenter(
          center: size.center(Offset.zero),
          width: 220,
          height: 220,
        );
        return CustomPaint(painter: _ViewfinderPainter(cutout: cutout));
      },
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({required this.cutout});

  final Rect cutout;

  @override
  void paint(Canvas canvas, Size size) {
    final Path dimmed = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(cutout, const Radius.circular(18)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dimmed, Paint()..color = const Color(0x99000000));
    canvas.drawRRect(
      RRect.fromRectAndRadius(cutout, const Radius.circular(18)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.barThumb,
    );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter oldDelegate) =>
      oldDelegate.cutout != cutout;
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.no_photography, size: 44, color: AppColors.statusUnknown),
            const SizedBox(height: 14),
            Text(
              'No camera',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Allow camera access in the system settings and reopen this screen.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
