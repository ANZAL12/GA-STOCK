import 'package:flutter/material.dart';

/// Extension on [BuildContext] to effortlessly adapt UI sizes, paddings, and layouts
/// for Android Tablets vs Phones.
extension ResponsiveContext on BuildContext {
  /// Whether the current device is a tablet (shortest side >= 600dp or width >= 600dp)
  bool get isTablet {
    final size = MediaQuery.sizeOf(this);
    return size.shortestSide >= 600 || size.width >= 600;
  }

  /// Whether current orientation is landscape
  bool get isLandscape => MediaQuery.orientationOf(this) == Orientation.landscape;

  /// Whether running on a tablet in landscape mode
  bool get isLandscapeTablet => isTablet && isLandscape;

  /// Screen width
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// Screen height
  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// Returns [tablet] value if running on a tablet, otherwise [mobile]
  T responsive<T>(T mobile, T tablet) => isTablet ? tablet : mobile;

  /// Dynamic scale factor: 1.0 on phones, ~1.25 on tablets
  double get tabletScale => isTablet ? 1.25 : 1.0;
}
