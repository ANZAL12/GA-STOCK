
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'sound_service.dart';

typedef BarcodeScanCallback = FutureOr<void> Function(String barcode);

/// High-performance, anti-fragmentation service to intercept, reassemble,
/// and sequentially queue scans from external hardware barcode scanners
/// (2.4GHz Wi-Fi/USB dongle wireless scanners, Bluetooth HID guns, USB OTG,
/// back-clip scanners, ring scanners, and integrated Android PDA lasers).
class HardwareScannerService {
  static final HardwareScannerService _instance = HardwareScannerService._internal();
  factory HardwareScannerService() => _instance;
  HardwareScannerService._internal();

  final List<BarcodeScanCallback> _listeners = [];
  final StreamController<String> _scanStreamController = StreamController<String>.broadcast();
  Stream<String> get onScan => _scanStreamController.stream;

  static const MethodChannel _nativeChannel =
      MethodChannel('com.globalagencies.godown_scanner/scanner');

  // Keystroke burst assembly buffer
  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastKeystrokeTime;
  DateTime? _lastBurstEndTime;
  Timer? _burstTimer;
  bool _initialized = false;
  bool _isEnabled = true;
  bool isMismatchActive = false;

  bool get isEnabled => _isEnabled;
  set isEnabled(bool value) {
    _isEnabled = value;
    try {
      _nativeChannel.invokeMethod('setEnabled', {'enabled': value});
    } catch (_) {}
  }

  // Dedicated FIFO Scan Processing Queue
  final List<String> _scanQueue = [];
  bool _isProcessingQueue = false;

  // Duplicate debounce within a short window
  final Map<String, DateTime> _recentScanTimes = {};

  /// Number of active screen listeners registered
  int get activeListenersCount => _listeners.length;

  /// Current number of barcodes pending in queue
  int get pendingQueueCount => _scanQueue.length;

  void init() {
    if (_initialized) return;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _nativeChannel.setMethodCallHandler(_handleNativeCall);
    _initialized = true;
    debugPrint('[HardwareScannerService] Initialized - native Android & Dart scan queue active');
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onBarcodeScanned') {
      final barcode = call.arguments?.toString();
      if (barcode != null && barcode.isNotEmpty) {
        debugPrint('[HardwareScannerService] Received barcode from native Android: $barcode');
        _enqueueBarcode(barcode);
      }
    }
    return null;
  }

  /// Clears any pending or partial keystroke buffer and resets burst timer
  void clearBuffer() {
    _burstTimer?.cancel();
    _burstTimer = null;
    _buffer.clear();
    _lastKeystrokeTime = null;
    try {
      _nativeChannel.invokeMethod('clearBuffer');
    } catch (_) {}
  }

  /// Comprehensively flushes and cancels any pending keystroke buffer,
  /// clears the FIFO scan queue, terminates in-progress queue loops,
  /// resets duplicate debounce records, and purges the audio subsystem.
  void flushAll() {
    clearBuffer();
    _scanQueue.clear();
    _isProcessingQueue = false;
    _recentScanTimes.clear();
    isMismatchActive = false;
    SoundService().flush();
    debugPrint('[HardwareScannerService] flushAll completed - all queues, keystroke buffers, and audio reset.');
  }

  /// Register a listener on the stack. The top-most active screen or widget
  /// receives the scanned barcode.
  /// Returns a function to unregister this listener when the screen is disposed.
  VoidCallback registerListener(BarcodeScanCallback callback) {
    init(); // Ensure handler is active

    // Proactively unfocus any focused text field and hide IME immediately upon screen mount
    // so the soft keyboard can never steal or compose characters from the first scan
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');

    // Only clear buffer if it is truly stale (> 1500ms).
    // NEVER wipe an active scan in progress (< 1500ms) when a screen mounts!
    if (_lastKeystrokeTime != null &&
        DateTime.now().difference(_lastKeystrokeTime!).inMilliseconds > 1500) {
      clearBuffer();
    }

    _listeners.add(callback);
    debugPrint('[HardwareScannerService] Listener registered (total: ${_listeners.length})');

    // If a scan was completed while navigating/mounting, deliver it immediately!
    if (_scanQueue.isNotEmpty) {
      scheduleMicrotask(() => _drainQueue());
    }

    return () {
      _listeners.remove(callback);
      debugPrint('[HardwareScannerService] Listener unregistered (remaining: ${_listeners.length})');
    };
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!isEnabled) return false;

    final key = event.logicalKey;
    final physKey = event.physicalKey;
    final now = DateTime.now();

    // Allow hardware volume buttons through for physical volume adjustment
    if (key == LogicalKeyboardKey.audioVolumeUp ||
        key == LogicalKeyboardKey.audioVolumeDown) {
      return false;
    }

    // Ignore modifier-only key events completely (Shift, Ctrl, Alt, CapsLock, NumLock)
    // to avoid false starts or buffer corruption during dongle connect / wake-up
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.capsLock ||
        key == LogicalKeyboardKey.numLock ||
        key == LogicalKeyboardKey.scrollLock) {
      return true; // Swallowed completely so UI is never disrupted
    }

    // Handle KeyUp / KeyRepeat: swallow immediately so no trailing events reach UI
    if (event is! KeyDownEvent) {
      return true;
    }

    // 1. Escape / Back Key: cancel current burst and clear buffer
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      clearBuffer();
      return true; // 100% swallowed: never pop screen or exit unexpectedly
    }

    // 2. Discard stale partial buffer if gap between keystrokes exceeds 1500ms
    if (_lastKeystrokeTime != null &&
        now.difference(_lastKeystrokeTime!).inMilliseconds > 1500) {
      _buffer.clear();
    }

    // Drop any stray focus immediately on first keystroke so IME never consumes keys
    if (_buffer.isEmpty) {
      final currentFocus = FocusManager.instance.primaryFocus;
      if (currentFocus != null && currentFocus.hasFocus) {
        currentFocus.unfocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      }
    }

    // 3. Check for Terminator Keys (Enter / NumpadEnter / Carriage Return / LineFeed)
    // NOTE: We deliberately DO NOT treat Tab as a terminator because many 2.4GHz
    // scanners transmit 2D or multi-field barcodes with an embedded Tab.
    final bool isTerminator = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        physKey == PhysicalKeyboardKey.enter ||
        physKey == PhysicalKeyboardKey.numpadEnter ||
        event.character == '\n' ||
        event.character == '\r';

    if (isTerminator) {
      _lastKeystrokeTime = now;
      _buffer.write('\n');
      // Terminator received: scan is complete.
      // Use fast 25ms micro-window to ensure trailing CR/LF arrives without user-perceptible delay.
      _scheduleBurstCompletion(delayMs: 25);
      return true; // Swallowed completely
    }

    // 4. Extract printable character
    final char = _extractCharacter(event);
    if (char != null && char.isNotEmpty) {
      _lastKeystrokeTime = now;
      _buffer.write(char);

      // Auto-assembly fallback:
      // Adaptive quiet window to accommodate Bluetooth HID / 2.4GHz cold-start wake-up jitter:
      // When a scanner wakes from sleep (> 5s idle), 1500ms guarantees cold-start characters
      // are never prematurely cut off. Once 4+ characters are received, 350ms ensures swift completion.
      final bool isCold = _lastBurstEndTime == null ||
          now.difference(_lastBurstEndTime!).inMilliseconds > 5000;
      final int delay = _buffer.length < 4 ? (isCold ? 1500 : 650) : 350;
      _scheduleBurstCompletion(delayMs: delay);
    }

    // 100% SWALLOWED: All external hardware keyboard events are consumed here!
    return true;
  }

  /// Schedules burst finalization after a quiet period.
  /// If more characters arrive before the timer fires, the timer is reset,
  /// guaranteeing that the full barcode is received intact!
  void _scheduleBurstCompletion({required int delayMs}) {
    _burstTimer?.cancel();
    _burstTimer = Timer(Duration(milliseconds: delayMs), () {
      _finalizeBurst();
    });
  }

  /// Assembles the complete burst from `_buffer`, sanitizes it,
  /// enqueues it into `_scanQueue`, and kicks off the background queue processor.
  void _finalizeBurst() {
    _burstTimer?.cancel();
    _burstTimer = null;
    _lastKeystrokeTime = null;
    _lastBurstEndTime = DateTime.now();

    final raw = _buffer.toString();
    _buffer.clear();

    if (raw.trim().isEmpty) return;

    // Split on newlines if multiple distinct lines were sent in one burst
    // (e.g. 2D carton barcode containing both Model and Serial, or multi-scan)
    final lines = raw.split(RegExp(r'[\r\n]+'));
    for (final line in lines) {
      // Strip any unprintable ASCII control characters (0x00-0x1F, 0x7F-0x9F)
      final clean = line
          .replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), '')
          .trim()
          .toUpperCase();
      // Only process valid barcode tokens (length >= 2, ignore empty chunks)
      if (clean.length >= 2) {
        _enqueueBarcode(clean);
      }
    }
  }

  /// Enqueues a clean, assembled barcode into the FIFO scan processing queue
  void _enqueueBarcode(String barcode) {
    final now = DateTime.now();
    final lastTime = _recentScanTimes[barcode];
    // Debounce exact identical repeat within 500ms to eliminate accidental optical bounces
    if (lastTime != null && now.difference(lastTime).inMilliseconds < 500) {
      if (isMismatchActive) {
        SoundService().playErrorSound();
        HapticFeedback.heavyImpact();
      }
      debugPrint('[HardwareScannerService] Debounced rapid duplicate scan of $barcode (isMismatchActive=$isMismatchActive)');
      return;
    }
    _recentScanTimes[barcode] = now;
    if (_recentScanTimes.length > 50) {
      _recentScanTimes.removeWhere((_, time) => now.difference(time).inSeconds > 10);
    }

    _scanQueue.add(barcode);
    debugPrint('[HardwareScannerService] Enqueued barcode: $barcode (Queue size: ${_scanQueue.length})');

    // Asynchronously drain queue without blocking the hardware keyboard handler
    scheduleMicrotask(() {
      _drainQueue();
    });
  }

  /// Dedicated sequential queue worker. Processes one barcode at a time in exact FIFO order.
  /// Even if the user rapid-scans multiple barcodes in 1-2 seconds, each item is processed
  /// sequentially without race conditions, thread stalls, or split barcodes!
  Future<void> _drainQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (_scanQueue.isNotEmpty) {
        // If no screen has registered a listener yet (e.g. during app startup or route transition),
        // pause draining and preserve the queue so the barcode is NOT dropped!
        if (_listeners.isEmpty) {
          debugPrint('[HardwareScannerService] Scan queue paused waiting for screen listener (pending: ${_scanQueue.length})');
          break;
        }

        final barcode = _scanQueue.removeAt(0);

        // 1. Unfocus any active text field to prevent trailing keystroke contamination
        final currentFocus = FocusManager.instance.primaryFocus;
        if (currentFocus != null && currentFocus.hasFocus && currentFocus.context != null) {
          currentFocus.unfocus();
          SystemChannels.textInput.invokeMethod('TextInput.hide');
        }

        // 2. Immediate zero-latency audio and haptic feedback
        try {
          if (isMismatchActive) {
            SoundService().playErrorSound();
          } else {
            SoundService().playScannerBeep();
            HapticFeedback.lightImpact();
          }
        } catch (_) {}

        // 3. Emit on public scan stream
        _scanStreamController.add(barcode);

        // 4. Notify topmost screen listener and await completion
        final activeListener = _listeners.last;
        try {
          await Future.sync(() => activeListener(barcode));
        } catch (e) {
          debugPrint('[HardwareScannerService] Listener error on barcode $barcode: $e');
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  String? _extractCharacter(KeyDownEvent event) {
    // 1. Direct character from OS (fastest & most accurate when available)
    final rawChar = event.character;
    if (rawChar != null && rawChar.isNotEmpty) {
      final codeUnit = rawChar.codeUnitAt(0);
      // Printable ASCII characters (space to tilde: 32 to 126)
      if (codeUnit >= 32 && codeUnit <= 126) {
        return rawChar;
      }
    }

    final key = event.logicalKey;
    final physKey = event.physicalKey;

    // 2. Numpad keys (frequently used by 2.4GHz wireless USB dongles and external scanners)
    // Note: LogicalKeyboardKey.numpadX has keyLabel like "Numpad 1" (len 8), so label.length == 1 fails!
    if (key == LogicalKeyboardKey.numpad0 || physKey == PhysicalKeyboardKey.numpad0) return '0';
    if (key == LogicalKeyboardKey.numpad1 || physKey == PhysicalKeyboardKey.numpad1) return '1';
    if (key == LogicalKeyboardKey.numpad2 || physKey == PhysicalKeyboardKey.numpad2) return '2';
    if (key == LogicalKeyboardKey.numpad3 || physKey == PhysicalKeyboardKey.numpad3) return '3';
    if (key == LogicalKeyboardKey.numpad4 || physKey == PhysicalKeyboardKey.numpad4) return '4';
    if (key == LogicalKeyboardKey.numpad5 || physKey == PhysicalKeyboardKey.numpad5) return '5';
    if (key == LogicalKeyboardKey.numpad6 || physKey == PhysicalKeyboardKey.numpad6) return '6';
    if (key == LogicalKeyboardKey.numpad7 || physKey == PhysicalKeyboardKey.numpad7) return '7';
    if (key == LogicalKeyboardKey.numpad8 || physKey == PhysicalKeyboardKey.numpad8) return '8';
    if (key == LogicalKeyboardKey.numpad9 || physKey == PhysicalKeyboardKey.numpad9) return '9';
    if (key == LogicalKeyboardKey.numpadDecimal || physKey == PhysicalKeyboardKey.numpadDecimal) return '.';
    if (key == LogicalKeyboardKey.numpadDivide || physKey == PhysicalKeyboardKey.numpadDivide) return '/';
    if (key == LogicalKeyboardKey.numpadMultiply || physKey == PhysicalKeyboardKey.numpadMultiply) return '*';
    if (key == LogicalKeyboardKey.numpadSubtract || physKey == PhysicalKeyboardKey.numpadSubtract) return '-';
    if (key == LogicalKeyboardKey.numpadAdd || physKey == PhysicalKeyboardKey.numpadAdd) return '+';

    // 3. Fallback using keyLabel for single-character alphanumeric keys
    final label = key.keyLabel;
    if (label.length == 1) {
      final cu = label.codeUnitAt(0);
      if (cu >= 32 && cu <= 126) {
        return label;
      }
    }

    // 4. Physical key fallback for standard top-row digits (0-9)
    if (physKey == PhysicalKeyboardKey.digit0) return '0';
    if (physKey == PhysicalKeyboardKey.digit1) return '1';
    if (physKey == PhysicalKeyboardKey.digit2) return '2';
    if (physKey == PhysicalKeyboardKey.digit3) return '3';
    if (physKey == PhysicalKeyboardKey.digit4) return '4';
    if (physKey == PhysicalKeyboardKey.digit5) return '5';
    if (physKey == PhysicalKeyboardKey.digit6) return '6';
    if (physKey == PhysicalKeyboardKey.digit7) return '7';
    if (physKey == PhysicalKeyboardKey.digit8) return '8';
    if (physKey == PhysicalKeyboardKey.digit9) return '9';

    // 5. Physical key fallback for standard letters (A-Z)
    if (physKey == PhysicalKeyboardKey.keyA) return 'A';
    if (physKey == PhysicalKeyboardKey.keyB) return 'B';
    if (physKey == PhysicalKeyboardKey.keyC) return 'C';
    if (physKey == PhysicalKeyboardKey.keyD) return 'D';
    if (physKey == PhysicalKeyboardKey.keyE) return 'E';
    if (physKey == PhysicalKeyboardKey.keyF) return 'F';
    if (physKey == PhysicalKeyboardKey.keyG) return 'G';
    if (physKey == PhysicalKeyboardKey.keyH) return 'H';
    if (physKey == PhysicalKeyboardKey.keyI) return 'I';
    if (physKey == PhysicalKeyboardKey.keyJ) return 'J';
    if (physKey == PhysicalKeyboardKey.keyK) return 'K';
    if (physKey == PhysicalKeyboardKey.keyL) return 'L';
    if (physKey == PhysicalKeyboardKey.keyM) return 'M';
    if (physKey == PhysicalKeyboardKey.keyN) return 'N';
    if (physKey == PhysicalKeyboardKey.keyO) return 'O';
    if (physKey == PhysicalKeyboardKey.keyP) return 'P';
    if (physKey == PhysicalKeyboardKey.keyQ) return 'Q';
    if (physKey == PhysicalKeyboardKey.keyR) return 'R';
    if (physKey == PhysicalKeyboardKey.keyS) return 'S';
    if (physKey == PhysicalKeyboardKey.keyT) return 'T';
    if (physKey == PhysicalKeyboardKey.keyU) return 'U';
    if (physKey == PhysicalKeyboardKey.keyV) return 'V';
    if (physKey == PhysicalKeyboardKey.keyW) return 'W';
    if (physKey == PhysicalKeyboardKey.keyX) return 'X';
    if (physKey == PhysicalKeyboardKey.keyY) return 'Y';
    if (physKey == PhysicalKeyboardKey.keyZ) return 'Z';

    // 6. Symbols with shift modifier awareness (e.g. '_' vs '-', ':' vs ';')
    final bool isShift = HardwareKeyboard.instance.isShiftPressed;
    if (key == LogicalKeyboardKey.minus || physKey == PhysicalKeyboardKey.minus) return isShift ? '_' : '-';
    if (key == LogicalKeyboardKey.equal || physKey == PhysicalKeyboardKey.equal) return isShift ? '+' : '=';
    if (key == LogicalKeyboardKey.semicolon || physKey == PhysicalKeyboardKey.semicolon) return isShift ? ':' : ';';
    if (key == LogicalKeyboardKey.slash || physKey == PhysicalKeyboardKey.slash) return isShift ? '?' : '/';
    if (key == LogicalKeyboardKey.backslash || physKey == PhysicalKeyboardKey.backslash) return isShift ? '|' : '\\';
    if (key == LogicalKeyboardKey.comma || physKey == PhysicalKeyboardKey.comma) return isShift ? '<' : ',';
    if (key == LogicalKeyboardKey.period || physKey == PhysicalKeyboardKey.period) return isShift ? '>' : '.';
    if (key == LogicalKeyboardKey.space || physKey == PhysicalKeyboardKey.space) return ' ';

    return null;
  }
}
