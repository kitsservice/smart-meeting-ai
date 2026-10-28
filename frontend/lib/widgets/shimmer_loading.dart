import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A sliding gradient transform for smooth shimmer sweeps.
class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (slidePercent * 2.5 - 1.25), 0.0, 0.0);
  }
}

/// A zero-dependency animated Shimmer effect container.
class ShimmerEffect extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Color? baseColor;
  final Color? highlightColor;

  const ShimmerEffect({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1400),
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBase = isDark ? const Color(0xFF242C3D) : const Color(0xFFE2E8F0);
    final defaultHighlight = isDark ? const Color(0xFF384357) : const Color(0xFFF8FAFC);

    final base = widget.baseColor ?? defaultBase;
    final highlight = widget.highlightColor ?? defaultHighlight;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
              transform: _SlidingGradientTransform(slidePercent: _controller.value),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A generic placeholder block used inside shimmer skeletons.
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton loader matching the meeting cards in [meetings_list_screen.dart].
class MeetingListSkeleton extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;

  const MeetingListSkeleton({
    super.key,
    this.count = 5,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: ListView.builder(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: count,
        itemBuilder: (context, index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(
                color: AppTheme.cardBorder(context),
                width: 1,
              ),
              boxShadow: AppTheme.cardShadow(context),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Leading icon container
                const ShimmerBox(
                  width: 36,
                  height: 36,
                  borderRadius: 10,
                ),
                const SizedBox(width: 12),
                // Title and subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ShimmerBox(
                        width: index.isEven ? 180 : 140,
                        height: 15,
                        borderRadius: 4,
                      ),
                      const SizedBox(height: 7),
                      ShimmerBox(
                        width: index.isEven ? 110 : 90,
                        height: 11,
                        borderRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Trailing pill/tag
                const ShimmerBox(
                  width: 24,
                  height: 24,
                  borderRadius: 6,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Skeleton loader matching the transcript chat in [meeting_details_screen.dart].
class TranscriptSkeleton extends StatelessWidget {
  final int count;

  const TranscriptSkeleton({
    super.key,
    this.count = 4,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: count,
        itemBuilder: (context, index) {
          final isLong = index % 2 == 0;
          return Padding(
            padding: EdgeInsets.only(
              bottom: 16.0,
              top: index != 0 ? 16.0 : 0.0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Speaker Avatar
                const SizedBox(
                  width: 44,
                  child: ShimmerBox(
                    width: 36,
                    height: 36,
                    borderRadius: 999,
                  ),
                ),
                const SizedBox(width: 8),
                // Speaker name + Speech Bubble
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Speaker name and time badges
                      Row(
                        children: [
                          ShimmerBox(
                            width: index.isEven ? 90 : 75,
                            height: 16,
                            borderRadius: 6,
                          ),
                          const SizedBox(width: 8),
                          const ShimmerBox(
                            width: 42,
                            height: 14,
                            borderRadius: 6,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Speech bubble container
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.cardBg(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.cardBorder(context),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShimmerBox(
                              width: double.infinity,
                              height: 13,
                              borderRadius: 4,
                            ),
                            const SizedBox(height: 6),
                            ShimmerBox(
                              width: isLong ? 220 : 150,
                              height: 13,
                              borderRadius: 4,
                            ),
                            if (isLong) ...[
                              const SizedBox(height: 6),
                              const ShimmerBox(
                                width: 110,
                                height: 13,
                                borderRadius: 4,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Skeleton loader matching the action items list in [action_items_screen.dart].
class ActionItemsSkeleton extends StatelessWidget {
  final int count;

  const ActionItemsSkeleton({
    super.key,
    this.count = 5,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: Column(
        children: [
          // Banner skeleton
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.cardBorder(context)),
              boxShadow: AppTheme.cardShadow(context),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ShimmerBox(width: 140, height: 14, borderRadius: 4),
                    ShimmerBox(width: 36, height: 14, borderRadius: 4),
                  ],
                ),
                SizedBox(height: 10),
                ShimmerBox(width: double.infinity, height: 6, borderRadius: 4),
              ],
            ),
          ),

          // Search field skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: const Row(
                children: [
                  ShimmerBox(width: 20, height: 20, borderRadius: 4),
                  SizedBox(width: 10),
                  ShimmerBox(width: 160, height: 14, borderRadius: 4),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Filter chips skeleton
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ShimmerBox(width: 60, height: 28, borderRadius: 20),
                SizedBox(width: 8),
                ShimmerBox(width: 80, height: 28, borderRadius: 20),
                SizedBox(width: 8),
                ShimmerBox(width: 90, height: 28, borderRadius: 20),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Task cards list skeleton
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              physics: const NeverScrollableScrollPhysics(),
              itemCount: count,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg(context),
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(color: AppTheme.cardBorder(context)),
                    boxShadow: AppTheme.cardShadow(context),
                  ),
                  child: Row(
                    children: [
                      // Checkbox placeholder
                      const ShimmerBox(width: 20, height: 20, borderRadius: 4),
                      const SizedBox(width: 12),
                      // Task details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShimmerBox(
                              width: index.isEven ? 210 : 160,
                              height: 14,
                              borderRadius: 4,
                            ),
                            const SizedBox(height: 6),
                            ShimmerBox(
                              width: index.isEven ? 120 : 90,
                              height: 11,
                              borderRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Action icons placeholder
                      const ShimmerBox(width: 24, height: 24, borderRadius: 6),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
