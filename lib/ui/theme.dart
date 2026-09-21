import 'package:flutter/material.dart';

/// SALU's colour vocabulary, ported from the PC (`lib/theme/app_theme.dart`).
///
/// The two halves must look like one product: same deep grays (never pure
/// black), same thin monochrome marks, same quiet surfaces. If a colour changes
/// on the PC it changes here in the same sitting — that is the whole reason
/// this file is a copy rather than "some dark theme".
///
/// **One deliberate difference: the font.** SALU on Windows is strictly
/// "Segoe UI Variable", which does not exist on Android. Rather than bundle a
/// 300 KB font file to imitate it, the app uses the platform's own UI font —
/// what a phone user expects to read — and keeps everything else identical.
abstract final class AppColors {
  static const Color background = Color(0xFF1E1E1E);
  static const Color videoBackdrop = Color(0xFF121212);
  static const Color surface = Color(0xFF252526);
  static const Color surfaceHighlight = Color(0xFF2D2D30);
  static const Color glass = Color(0xCC1E1E1E);
  static const Color accent = Color(0xFF4C9EEB);
  static const Color textPrimary = Color(0xFFEDEDED);
  static const Color iconIdle = Color(0xFFA6A6A6);
  static const Color textSecondary = Color(0xFF9A9A9A);
  static const Color divider = Color(0xFF3A3A3C);
  static const Color surfaceOutline = Color(0xFF333336);
  static const Color statusAlive = Color(0xFF57C777);
  static const Color statusDead = Color(0xFFE05B5B);
  static const Color statusUnknown = Color(0xFF5A5A5E);
  static const Color barTrack = Color(0xFF35353C);
  static const Color barFill = Color(0x80FFFFFF);
  static const Color barThumb = Color(0xFFF2F2F2);
}

/// A SALU panel: dark surface, 18 px radius, one hairline. Phone scale of the
/// PC's own panels (16 px there, on a desk where 1 px reads clearly).
///
/// This is a plain widget rather than a `cardTheme` on purpose: it carries the
/// same look on every Flutter version and cannot be re-styled by accident.
class SaluCard extends StatelessWidget {
  const SaluCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceOutline, width: 1.2),
      ),
      child: child,
    );
  }
}

/// The app's one theme.
abstract final class SaluTheme {
  static ThemeData build() {
    const ColorScheme scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Color(0xFF10161C),
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.statusDead,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.divider,
      appBarTheme: const AppBarThemeData(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        bodySmall: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        labelLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.surfaceHighlight,
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.videoBackdrop,
        hintStyle: const TextStyle(color: AppColors.statusUnknown),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.surfaceOutline, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.surfaceOutline, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.barTrack,
        thumbColor: AppColors.barThumb,
        overlayColor: Color(0x334C9EEB),
        trackHeight: 4,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceHighlight,
        contentTextStyle: TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// "12:34" / "1:02:03" — the same clock the PC shows.
  static String clock(Duration value) {
    final int total = value.inSeconds < 0 ? 0 : value.inSeconds;
    final int hours = total ~/ 3600;
    final int minutes = (total % 3600) ~/ 60;
    final int seconds = total % 60;
    final String mm = hours > 0 ? minutes.toString().padLeft(2, '0') : minutes.toString();
    final String ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }
}

/// A slider that follows your thumb while you drag and sends **one** command
/// when you let go (`remote_apk_ui.md` §8: "Optimistic, locked against incoming
/// updates while dragging; one command on release").
///
/// Without this the PC's snapshot would fight the finger: the thumb would snap
/// back to the PC's position on every frame.
class CommitSlider extends StatefulWidget {
  const CommitSlider({
    super.key,
    required this.value,
    required this.max,
    required this.onCommit,
  });

  final double value;
  final double max;
  final ValueChanged<double> onCommit;

  @override
  State<CommitSlider> createState() => _CommitSliderState();
}

class _CommitSliderState extends State<CommitSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final double max = widget.max <= 0 ? 1 : widget.max;
    final double value = (_dragging ?? widget.value).clamp(0, max).toDouble();
    return Slider(
      value: value,
      max: max,
      onChanged: (double next) => setState(() => _dragging = next),
      onChangeEnd: (double next) {
        setState(() => _dragging = null);
        widget.onCommit(next);
      },
    );
  }
}
