import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'sound_service.dart';

typedef BarcodeScanCallback = void Function(String barcode);

/// High-performance service to intercept and process scans from external hardware
/// barcode scanners (Bluetooth HID handheld guns, back-clip scanners, ring scanners,
/// USB OTG scanners, and integrated Android PDA laser scanners).
class HardwareScannerService {
  static final HardwareScannerService _instance = HardwareScannerService._internal();
  factory HardwareScannerService() => _instance;
  HardwareScannerService._internal();

  final List<BarcodeScanCallback> _listeners = [];
  final StreamController<String> _scanStreamController = StreamController<String>.broadcast();
  Stream<String> get onScan => _scanStreamController.stream;

  final StringBuffer _buffer = StringBuffer();
  final Map<String, DateTime> _recentScanTimes = {};
  DateTime? _lastKeystrokeTime;
  bool _initialized = false;
  bool isEnabled = true;
  bool _scannerUsesTerminator = true;

  /// Number of active screen listeners registered
  int get activeListenersCount => _listeners.length;

  void init() {
    if (_initialized) return;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _initialized = true;
    debugPrint('[HardwareScannerService] Initialized - listening for Bluetooth/USB barcode scanners');
  }

  /// Clears any pending or partial keystroke buffer
  void clearBuffer() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _buffer.clear();
    _lastKeystrokeTime = null;
  }

  /// Register a listener on the stack. The top-most active screen or widget
  /// receives the scanned barcode.
  /// Returns a function to unregister this listener when the screen is disposed.
  VoidCallback registerListener(BarcodeScanCallback callback) {
    init(); // Ensure handler is active
    clearBuffer(); // Clean slate whenever a screen registers to prevent first-scan corruption
    _listeners.add(callback);
    return () {
      _listeners.remove(callback);
      clearBuffer();
    };
  }

  Timer? _debounceTimer;

  bool _handleKeyEvent(KeyEvent event) {
    if (!isEnabled) return false;

    final key = event.logicalKey;
    final now = DateTime.now();

    // Allow hardware volume buttons through for physical volume adjustment
    if (key == LogicalKeyboardKey.audioVolumeUp ||
        key == LogicalKeyboardKey.audioVolumeDown) {
      return false;
    }

    // Handle KeyUp / KeyRepeat: swallow immediately so no trailing events reach UI
    if (event is! KeyDownEvent) {
      return true;
    }

    // 1. Scanner Terminator Keys (Enter, NumpadEnter, Tab, \r, \n)
    final bool isTerminator = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab ||
        event.character == '\n' ||
        event.character == '\r';

    if (isTerminator) {
      _scannerUsesTerminator = true;
      _debounceTimer?.cancel();
      _debounceTimer = null;

      if (_buffer.isNotEmpty) {
        final barcode = _buffer.toString().trim();
        _buffer.clear();
        _lastKeystrokeTime = null;

        if (barcode.length >= 2) {
          _dispatchBarcode(barcode);
        }
      }
      return true; // 100% swallowed: never activate buttons or trigger focus traversal!
    }

    // 2. Escape / Back
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      if (_buffer.isNotEmpty) {
        _buffer.clear();
        _lastKeystrokeTime = null;
      }
      return true; // 100% swallowed: never pop screen or go to home screen!
    }

    // 3. Clear buffer if gap between characters is too long (> 2000ms stale threshold)
    // Avoid clearing during 500-800ms CPU spikes on low-RAM tablets
    if (_lastKeystrokeTime != null &&
        now.difference(_lastKeystrokeTime!).inMilliseconds > 2000) {
      _buffer.clear();
    }
    _lastKeystrokeTime = now;

    // 4. Extract printable character
    final char = _extractCharacter(event);
    if (char != null && char.isNotEmpty) {
      _buffer.write(char);

      // Auto-dispatch fallback: ONLY for scanners that do not send an Enter key.
      // Once a terminator key has been observed, we disable timeout-based dispatch
      // so CPU stalls on low-RAM devices never prematurely split a serial number!
      _debounceTimer?.cancel();
      if (!_scannerUsesTerminator) {
        _debounceTimer = Timer(const Duration(milliseconds: 1200), () {
          if (_buffer.isNotEmpty) {
            final barcode = _buffer.toString().trim();
            // Require at least 6 characters for timer-based auto-dispatch to prevent
            // chopping partial barcodes in half during heavy device load
            if (barcode.length >= 6) {
              _buffer.clear();
              _lastKeystrokeTime = null;
              _dispatchBarcode(barcode);
            }
          }
        });
      }
    }

    // 100% SWALLOWED: All external hardware keyboard events are consumed here!
    // No physical keystroke can EVER leak into Flutter widgets, buttons, or focus traversal!
    return true;
  }

  void _dispatchBarcode(String rawBarcode) {
    final barcode = rawBarcode.trim().toUpperCase();
    if (barcode.length < 2) return;

    final now = DateTime.now();
    final lastTime = _recentScanTimes[barcode];
    // Prevent accidental repeat double-scanning of the exact same barcode within 1200ms
    if (lastTime != null && now.difference(lastTime).inMilliseconds < 1200) {
      debugPrint('[HardwareScannerService] Debounced repeat scan of $barcode');
      return;
    }
    _recentScanTimes[barcode] = now;
    if (_recentScanTimes.length > 50) {
      _recentScanTimes.removeWhere((_, time) => now.difference(time).inSeconds > 10);
    }

    debugPrint('[HardwareScannerService] Scanned barcode: $barcode');

    // Asynchronously dispatch on microtask queue so _handleKeyEvent returns
    // true immediately to Android, unblocking Android's hardware input pipeline
    scheduleMicrotask(() {
      // Dismiss focus only if an active element actually holds focus, avoiding Android ViewRootImpl surface relayout
      final currentFocus = FocusManager.instance.primaryFocus;
      if (currentFocus != null && currentFocus.hasFocus && currentFocus.context != null) {
        currentFocus.unfocus();
      }

      // Immediate zero-latency audio and haptic feedback
      try {
        SoundService().playScannerBeep();
        HapticFeedback.lightImpact();
      } catch (_) {}

      _scanStreamController.add(barcode);

      // Notify the topmost registered screen listener
      if (_listeners.isNotEmpty) {
        final activeListener = _listeners.last;
        activeListener(barcode);
      }
    });
  }

  String? _extractCharacter(KeyDownEvent event) {
    final rawChar = event.character;
    if (rawChar != null && rawChar.isNotEmpty) {
      final codeUnit = rawChar.codeUnitAt(0);
      // Printable ASCII characters (space to tilde: 32 to 126)
      if (codeUnit >= 32 && codeUnit <= 126) {
        return rawChar;
      }
    }

    final key = event.logicalKey;
    // Fallback using keyLabel for alphanumeric characters if character is null
    final label = key.keyLabel;
    if (label.length == 1) {
      final cu = label.codeUnitAt(0);
      if (cu >= 32 && cu <= 126) {
        return label;
      }
    }

    // Fallbacks for common barcode characters if event.character is null
    if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) return '-';
    if (key == LogicalKeyboardKey.slash || key == LogicalKeyboardKey.numpadDivide) return '/';
    if (key == LogicalKeyboardKey.space) return ' ';
    if (key == LogicalKeyboardKey.period || key == LogicalKeyboardKey.numpadDecimal) return '.';

    return null;
  }
}
