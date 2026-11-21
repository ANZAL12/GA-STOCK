import 'package:flutter/widgets.dart';
import 'api_service.dart';

/// Caps Flutter image caches and reacts to Android onTrimMemory.
/// Cheap 3GB tablets otherwise keep decoded bitmaps until the OS kills the process.
class MemoryGuard with WidgetsBindingObserver {
  MemoryGuard._();
  static final MemoryGuard instance = MemoryGuard._();

  bool _attached = false;

  static const int imageCacheBytes = 18 * 1024 * 1024; // 18 MB
  static const int imageCacheCount = 32;

  void attach() {
    if (_attached) return;
    _attached = true;
    applyCaches();
    WidgetsBinding.instance.addObserver(this);
  }

  static void applyCaches() {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSizeBytes = imageCacheBytes;
    cache.maximumSize = imageCacheCount;
  }

  static void purge() {
    try {
      final cache = PaintingBinding.instance.imageCache;
      cache.clear();
      cache.clearLiveImages();
    } catch (_) {}
    ApiService().clearSerialCaches();
    ApiService().clearSerialCheckCache();
  }

  @override
  void didHaveMemoryPressure() {
    purge();
  }
}
