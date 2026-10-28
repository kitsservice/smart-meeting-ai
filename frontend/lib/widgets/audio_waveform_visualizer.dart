import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A hardware-accelerated real-time audio waveform visualizer.
class AudioWaveformVisualizer extends StatelessWidget {
  final List<double> samples;
  final bool isRecording;
  final bool isInterrupted;
  final double currentAmplitude;
  final double height;

  const AudioWaveformVisualizer({
    super.key,
    required this.samples,
    required this.isRecording,
    this.isInterrupted = false,
    required this.currentAmplitude,
    this.height = 42.0,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasSpeech = isRecording && currentAmplitude > 0.12;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isInterrupted
              ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dynamic Waveform Bars
          SizedBox(
            height: height,
            width: double.infinity,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _WaveformPainter(
                  samples: samples,
                  isRecording: isRecording,
                  isInterrupted: isInterrupted,
                  primaryColor: AppTheme.primaryColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Audio Status Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isInterrupted
                      ? const Color(0xFFF59E0B)
                      : (isRecording
                          ? (hasSpeech ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                          : Colors.grey),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isInterrupted
                    ? 'AUDIO INTERRUPTED • TAP RESUME'
                    : (isRecording
                        ? (hasSpeech ? 'SPEECH DETECTED' : 'MICROPHONE ACTIVE')
                        : 'RECORDING PAUSED'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: isInterrupted
                      ? const Color(0xFFF59E0B)
                      : (isRecording
                          ? (hasSpeech ? const Color(0xFF10B981) : Colors.white70)
                          : Colors.white38),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final bool isRecording;
  final bool isInterrupted;
  final Color primaryColor;

  _WaveformPainter({
    required this.samples,
    required this.isRecording,
    required this.isInterrupted,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final int count = samples.length;
    const double spacing = 3.5;
    final double totalSpacing = (count - 1) * spacing;
    final double barWidth = ((size.width - totalSpacing) / count).clamp(2.0, 6.0);
    final double centerY = size.height / 2;
    const double minBarHeight = 6.0;
    final double maxBarHeight = size.height * 0.9;

    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < count; i++) {
      final double normalized = samples[i].clamp(0.04, 1.0);
      final double barHeight = isRecording
          ? (minBarHeight + (normalized * (maxBarHeight - minBarHeight)))
          : minBarHeight;

      final double x = i * (barWidth + spacing);
      final double top = centerY - (barHeight / 2);

      final rect = Rect.fromLTWH(x, top, barWidth, barHeight);
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2));

      if (isInterrupted) {
        paint.shader = null;
        paint.color = const Color(0xFFF59E0B).withValues(alpha: 0.6);
      } else if (isRecording) {
        paint.shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            primaryColor,
            const Color(0xFF38BDF8),
          ],
        ).createShader(rect);
      } else {
        paint.shader = null;
        paint.color = Colors.white.withValues(alpha: 0.2);
      }

      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.isRecording != isRecording ||
        oldDelegate.isInterrupted != isInterrupted;
  }
}
