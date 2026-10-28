import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Screen size device categories
enum ScreenDeviceType {
  /// Very narrow screens (< 350dp), e.g. Samsung Galaxy Z Fold outer cover screen (~320-340dp),
  /// narrow feature phones, or compact phone models.
  narrow,

  /// Standard smartphone screens (350dp - 599dp), e.g. Galaxy S22/S23/S24, iPhone 13-16, Pixel.
  mobile,

  /// Foldable unfolded inner screens or small tablets (600dp - 899dp),
  /// e.g. Galaxy Z Fold inner screen (~673dp x 829dp), Pixel Fold inner screen, iPad Mini.
  foldableOrTablet,

  /// Large tablets or desktop displays (>= 900dp).
  desktopOrLargeTablet,
}

/// Central responsive utility and layout helpers for Ares Smart Meeting.
/// Handles phone, foldables (Z Fold outer cover & unfolded inner display), and tablets.
class Responsive {
  /// Breakpoint constants
  static const double narrowBreakpoint = 350.0;
  static const double tabletBreakpoint = 600.0;
  static const double desktopBreakpoint = 900.0;

  /// Default max content width for centering readable content on wide/unfolded screens
  static const double maxContentWidth = 680.0;
  static const double maxSheetWidth = 560.0;
  static const double maxDialogWidth = 480.0;

  /// Screen size queries
  static double width(BuildContext context) => MediaQuery.of(context).size.width;
  static double height(BuildContext context) => MediaQuery.of(context).size.height;
  static Size size(BuildContext context) => MediaQuery.of(context).size;
  static Orientation orientation(BuildContext context) => MediaQuery.of(context).orientation;
  static bool isLandscape(BuildContext context) => orientation(context) == Orientation.landscape;

  /// Device type queries
  static ScreenDeviceType deviceType(BuildContext context) {
    final w = width(context);
    if (w < narrowBreakpoint) {
      return ScreenDeviceType.narrow;
    } else if (w < tabletBreakpoint) {
      return ScreenDeviceType.mobile;
    } else if (w < desktopBreakpoint) {
      return ScreenDeviceType.foldableOrTablet;
    } else {
      return ScreenDeviceType.desktopOrLargeTablet;
    }
  }

  static bool isNarrow(BuildContext context) => width(context) < narrowBreakpoint;
  static bool isMobile(BuildContext context) => width(context) < tabletBreakpoint;
  static bool isStandardMobile(BuildContext context) {
    final w = width(context);
    return w >= narrowBreakpoint && w < tabletBreakpoint;
  }
  static bool isFoldableOrTablet(BuildContext context) {
    final w = width(context);
    return w >= tabletBreakpoint && w < desktopBreakpoint;
  }
  static bool isLargeScreen(BuildContext context) => width(context) >= tabletBreakpoint;
  static bool isDesktopOrLargeTablet(BuildContext context) => width(context) >= desktopBreakpoint;

  /// Check if the screen has a foldable hinge or display feature
  static bool hasFoldOrHinge(BuildContext context) {
    final displayFeatures = MediaQuery.of(context).displayFeatures;
    for (final feature in displayFeatures) {
      if (feature.type == ui.DisplayFeatureType.hinge ||
          feature.type == ui.DisplayFeatureType.fold) {
        return true;
      }
    }
    return false;
  }

  /// Adaptive padding based on screen width
  static double horizontalPadding(BuildContext context) {
    final w = width(context);
    if (w < narrowBreakpoint) return 12.0;
    if (w < tabletBreakpoint) return 16.0;
    if (w < desktopBreakpoint) return 24.0;
    return 32.0;
  }

  /// Adaptive grid column count
  static int gridColumns(
    BuildContext context, {
    int narrow = 1,
    int mobile = 2,
    int foldable = 3,
    int desktop = 4,
  }) {
    final w = width(context);
    if (w < narrowBreakpoint) return narrow;
    if (w < tabletBreakpoint) return mobile;
    if (w < desktopBreakpoint) return foldable;
    return desktop;
  }

  /// Adaptive child aspect ratio for grid cards based on available width and column count
  static double gridChildAspectRatio(
    BuildContext context, {
    double narrow = 1.30,
    double mobile = 0.84,
    double foldable = 0.95,
    double desktop = 1.10,
  }) {
    final w = width(context);
    if (w < narrowBreakpoint) return narrow;
    if (w < tabletBreakpoint) {
      // Dynamic ratio for standard mobile: if narrower (e.g. 360-380dp), give slightly more height
      if (w < 380) return 0.80;
      return mobile;
    }
    if (w < desktopBreakpoint) return foldable;
    return desktop;
  }

  /// Adaptive font size scaler that bounds text scaling to prevent layout breakage
  static double scaleFont(BuildContext context, double baseFontSize, {double min = 0.85, double max = 1.25}) {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final clampedScale = textScale.clamp(min, max);
    final widthFactor = width(context) < narrowBreakpoint ? 0.92 : 1.0;
    return baseFontSize * clampedScale * widthFactor;
  }

  /// Value selector helper: returns a value based on the current screen size
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? narrow,
    T? foldable,
    T? desktop,
  }) {
    final w = width(context);
    if (w < narrowBreakpoint && narrow != null) return narrow;
    if (w >= desktopBreakpoint && desktop != null) return desktop;
    if (w >= tabletBreakpoint && foldable != null) return foldable;
    return mobile;
  }
}

/// A wrapper widget that centers its child and constrains its maximum width
/// on unfolded foldables, tablets, and desktops.
class ResponsiveContentWrapper extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  const ResponsiveContentWrapper({
    super.key,
    required this.child,
    this.maxWidth = Responsive.maxContentWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: padding != null ? Padding(padding: padding!, child: child) : child,
      ),
    );
  }
}

/// A responsive bottom sheet container that keeps modal bottom sheets
/// from stretching to awkward full-width bars on wide fold screens or tablets.
class ResponsiveSheetContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final Color? backgroundColor;
  final BorderRadiusGeometry? borderRadius;
  final EdgeInsetsGeometry? padding;

  const ResponsiveSheetContainer({
    super.key,
    required this.child,
    this.maxWidth = Responsive.maxSheetWidth,
    this.backgroundColor,
    this.borderRadius,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor ?? defaultBg,
            borderRadius: borderRadius ?? const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Builder widget for responsive designs
typedef ResponsiveWidgetBuilder = Widget Function(
  BuildContext context,
  ScreenDeviceType deviceType,
  BoxConstraints constraints,
);

class ResponsiveLayoutBuilder extends StatelessWidget {
  final ResponsiveWidgetBuilder builder;

  const ResponsiveLayoutBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final ScreenDeviceType type;
        if (w < Responsive.narrowBreakpoint) {
          type = ScreenDeviceType.narrow;
        } else if (w < Responsive.tabletBreakpoint) {
          type = ScreenDeviceType.mobile;
        } else if (w < Responsive.desktopBreakpoint) {
          type = ScreenDeviceType.foldableOrTablet;
        } else {
          type = ScreenDeviceType.desktopOrLargeTablet;
        }
        return builder(context, type, constraints);
      },
    );
  }
}
