import 'package:flutter/material.dart';

/// Extension on [BuildContext] to effortlessly adapt UI sizes, paddings, and layouts
/// for Android Tablets vs Phones.
extension ResponsiveContext on BuildContext {
  /// Whether the current device is a tablet (shortest side >= 600dp or width >= 600dp)
  bool get isTablet {
    final media = MediaQuery.of(this);
    return media.size.shortestSide >= 600 || media.size.width >= 600;
  }

  /// Whether current orientation is landscape
  bool get isLandscape => MediaQuery.of(this).orientation == Orientation.landscape;

  /// Whether running on a tablet in landscape mode
  bool get isLandscapeTablet => isTablet && isLandscape;

  /// Screen width
  double get screenWidth => MediaQuery.of(this).size.width;

  /// Screen height
  double get screenHeight => MediaQuery.of(this).size.height;

  /// Returns [tablet] value if running on a tablet, otherwise [mobile]
  T responsive<T>(T mobile, T tablet) => isTablet ? tablet : mobile;

  /// Dynamic scale factor: 1.0 on phones, ~1.25 on tablets
  double get tabletScale => isTablet ? 1.25 : 1.0;
}
