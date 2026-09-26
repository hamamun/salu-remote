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

  /// Our own subscription to the barcode stream.
  ///
  /// This is deliberately **not** `MobileScanner.onDetect`. That widget
  /// subscribes to the stream exactly once, in its `initState`, with whatever
  /// callback it was first built with — and it never re-subscribes when the
  /// callback changes. The previous version passed `null` until the camera
  /// was up, so the widget captured `null`, no subscription was ever made,
  /// and the scanner looked at QR codes forever without reacting. Listening
  /// on the controller directly has no such race.
  StreamSubscription<BarcodeCapture>? _barcodes;

  bool _handled = false;
  bool _cameraReady = false;
  bool _cameraDenied = false;
  String? _cameraProblem;

  /// The last thing the camera read that was *not* a SALU link, so a wrong
  /// QR (a Wi-Fi card, a web address) gets one honest line instead of the
  /// silence that looks like a broken scanner.
  String? _wrongCode;
  Timer? _wrongCodeTimer;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.normal,
      // The PC's QR is the only thing we want; skipping the other twelve
      // symbologies makes ML Kit noticeably quicker to lock on.
      formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
      autoStart: false,
    );
    _barcodes = _controller.barcodes.listen(
      _onDetect,
      onError: (Object error, StackTrace stack) {
        // A frame ML Kit could not decode. Not fatal; the next frame is
        // already on its way.
        debugPrint('[SALU remote] QR frame error: $error');
      },
      cancelOnError: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_startCamera()));
  }

  Future<void> _startCamera() async {
    try {
      await _controller.start();
      if (!mounted) return;
      // `start()` reports permission and hardware problems through the
      // controller's value rather than by throwing.
      final MobileScannerException? error = _controller.value.error;
      if (error != null) {
        debugPrint('[SALU remote] camera failed: ${error.errorCode} '
            '${error.errorDetails?.message ?? ''}');
        setState(() {
          _cameraReady = false;
          _cameraDenied = true;
          _cameraProblem = _describe(error);
        });
        return;
      }
      setState(() {
        _cameraReady = true;
        _cameraDenied = false;
        _cameraProblem = null;
      });
    } on MobileScannerException catch (error) {
      if (!mounted) return;
      debugPrint('[SALU remote] camera failed: ${error.errorCode}');
      setState(() {
        _cameraReady = false;
        _cameraDenied = true;
        _cameraProblem = _describe(error);
      });
    } catch (error) {
      if (!mounted) return;
      debugPrint('[SALU remote] camera failed: $error');
      setState(() {
        _cameraReady = false;
        _cameraDenied = true;
        _cameraProblem = null;
      });
    }
  }

  static String? _describe(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Camera access denied.';
      case MobileScannerErrorCode.unsupported:
        return 'This phone has no camera the scanner can use.';
      default:
        return null;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) return;
    String? unrecognised;
    for (final Barcode barcode in capture.barcodes) {
      final String? raw = barcode.rawValue ?? barcode.displayValue;
      final PairLink? link = DeepLink.parse(raw);
      if (link != null) {
        _handled = true;
        debugPrint('[SALU remote] QR read: ${link.address}');
        unawaited(_controller.stop());
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(link);
        return;
      }
      if (raw != null && raw.isNotEmpty) unrecognised = raw;
    }
    if (unrecognised != null && unrecognised != _wrongCode) {
      setState(() => _wrongCode = unrecognised);
      _wrongCodeTimer?.cancel();
      _wrongCodeTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _wrongCode = null);
      });
    }
  }

  @override
  void dispose() {
    _wrongCodeTimer?.cancel();
    unawaited(_barcodes?.cancel());
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
        actions: <Widget>[
          if (_cameraReady)
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (BuildContext context, MobileScannerState state, _) {
                final bool on = state.torchState == TorchState.on;
                if (state.torchState == TorchState.unavailable) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  tooltip: on ? 'Torch off' : 'Torch on',
                  icon: Icon(on ? Icons.flashlight_off : Icons.flashlight_on),
                  onPressed: () => unawaited(_controller.toggleTorch()),
                );
              },
            ),
        ],
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
                      // No onDetect here on purpose — see `_barcodes`.
                      errorBuilder: (BuildContext context, MobileScannerException error) =>
                          _CameraUnavailable(detail: _describe(error)),
                    )
                  else
                    _CameraUnavailable(detail: _cameraProblem),
                  // The viewfinder: everything dimmed except a quiet rounded
                  // square, so the eye (and the camera) knows where to aim.
                  if (_cameraReady && !_handled)
                    const _ViewfinderOverlay(),
                  if (_wrongCode != null)
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 24,
                      child: _WrongCodeLine(text: _wrongCode!),
                    ),
                ],
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

/// "That QR is not a SALU code" — shown for three seconds over the preview.
class _WrongCodeLine extends StatelessWidget {
  const _WrongCodeLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final String shown = text.length > 48 ? '${text.substring(0, 48)}…' : text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Not a SALU pairing code ($shown).',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.barThumb, fontSize: 13),
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({this.detail});

  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.no_photography, size: 44, color: AppColors.statusUnknown),
            const SizedBox(height: 14),
            Text(
              'No camera',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              detail ??
                  'Camera unavailable.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
