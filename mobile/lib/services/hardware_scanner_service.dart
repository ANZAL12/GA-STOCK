import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  DateTime? _lastKeystrokeTime;
  bool _initialized = false;
  bool isEnabled = true;

  /// Number of active screen listeners registered
  int get activeListenersCount => _listeners.length;

  void init() {
    if (_initialized) return;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _initialized = true;
    debugPrint('[HardwareScannerService] Initialized - listening for Bluetooth/USB barcode scanners');
  }

  /// Register a listener on the stack. The top-most active screen or widget
  /// receives the scanned barcode.
  /// Returns a function to unregister this listener when the screen is disposed.
  VoidCallback registerListener(BarcodeScanCallback callback) {
    init(); // Ensure handler is active
    _listeners.add(callback);
    return () {
      _listeners.remove(callback);
    };
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!isEnabled) return false;
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;
    final now = DateTime.now();

    // 1. Check for Scanner Terminator Keys (Enter, NumpadEnter, Tab)
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      if (_buffer.isNotEmpty) {
        final barcode = _buffer.toString().trim();
        _buffer.clear();
        _lastKeystrokeTime = null;

        // Barcodes typically have at least 2 alphanumeric characters
        if (barcode.length >= 2) {
          _dispatchBarcode(barcode);
          return true; // Handled: prevent triggering default Enter key behavior in UI
        }
      }
      return false;
    }

    // 2. Clear buffer on Escape
    if (key == LogicalKeyboardKey.escape) {
      _buffer.clear();
      _lastKeystrokeTime = null;
      return false;
    }

    // 3. Reset buffer if gap between keystrokes is too long (human typing vs hardware scanner burst)
    if (_lastKeystrokeTime != null &&
        now.difference(_lastKeystrokeTime!).inMilliseconds > 250) {
      _buffer.clear();
    }
    _lastKeystrokeTime = now;

    // 4. Extract character
    final char = _extractCharacter(event);
    if (char != null && char.isNotEmpty) {
      _buffer.write(char);
    }

    return false;
  }

  void _dispatchBarcode(String rawBarcode) {
    final barcode = rawBarcode.trim().toUpperCase();
    debugPrint('[HardwareScannerService] Scanned barcode: $barcode');

    // Immediate zero-latency audio and haptic feedback
    try {
      SoundService().playScannerBeep();
      HapticFeedback.mediumImpact();
    } catch (_) {}

    _scanStreamController.add(barcode);

    // Notify the topmost registered screen listener
    if (_listeners.isNotEmpty) {
      final activeListener = _listeners.last;
      activeListener(barcode);
    }
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

    // Fallbacks for common barcode characters if event.character is null
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) return '-';
    if (key == LogicalKeyboardKey.slash || key == LogicalKeyboardKey.numpadDivide) return '/';
    if (key == LogicalKeyboardKey.space) return ' ';
    if (key == LogicalKeyboardKey.period || key == LogicalKeyboardKey.numpadDecimal) return '.';

    return null;
  }
}
