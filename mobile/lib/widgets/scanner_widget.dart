import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/sound_service.dart';
import '../services/hardware_scanner_service.dart';
import 'uppercase_formatter.dart';
import 'flush_lag_button.dart';

class BarcodeScannerWidget extends StatefulWidget {
  final String title;
  final String prompt;
  final String? initialLastScanned;
  final int initialCount;
  final int Function()? itemCountProvider;
  final Set<String>? existingSerials;
  final bool Function(String barcode)? isDuplicate;
  final dynamic Function(String barcode) onScanned;

  const BarcodeScannerWidget({
    super.key,
    required this.title,
    this.prompt = 'Align barcode strictly inside viewfinder',
    this.initialLastScanned,
    this.initialCount = 0,
    this.itemCountProvider,
    this.existingSerials,
    this.isDuplicate,
    required this.onScanned,
  });

  @override
  State<BarcodeScannerWidget> createState() => _BarcodeScannerWidgetState();
}

class _BarcodeScannerWidgetState extends State<BarcodeScannerWidget>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    cameraResolution: const Size(1280, 720),
    facing: CameraFacing.back,
    torchEnabled: false,
    returnImage: false,
    formats: const [
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
  );

  late AnimationController _animController;
  late Animation<double> _scanLineAnimation;

  final ValueNotifier<bool> _isTorchOnN = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isProcessingN = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isDuplicateWarningN = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _holdToScanModeN = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _isHoldingTriggerN = ValueNotifier<bool>(false);
  final ValueNotifier<String?> _lastScannedValueN = ValueNotifier<String?>(null);
  final ValueNotifier<int> _scannedCountN = ValueNotifier<int>(0);
  late final Listenable _reticleListenable = Listenable.merge([
    _isProcessingN,
    _isDuplicateWarningN,
    _holdToScanModeN,
    _isHoldingTriggerN,
  ]);

  int get _currentCount => widget.itemCountProvider?.call() ?? _scannedCountN.value;
  final TextEditingController _manualTextController = TextEditingController();
  VoidCallback? _hardwareScannerSub;
  final List<String> _hwPendingQueue = [];
  bool _drainingHwQueue = false;
  bool _isClosing = false;

  late final Set<String> _sessionScannedSerials;
  final Map<String, DateTime> _recentScanTimes = {};
  DateTime? _lastScanTime;

  static const double _boxWidth = 290.0;
  static const double _boxHeight = 190.0;

  static const MethodChannel _volumeChannel =
      MethodChannel('com.globalagencies.godown_scanner/volume_key');

  @override
  void initState() {
    super.initState();
    SoundService().init();
    _lastScannedValueN.value = widget.initialLastScanned;
    _scannedCountN.value = widget.itemCountProvider?.call() ?? widget.initialCount;
    _sessionScannedSerials = widget.existingSerials != null
        ? Set<String>.from(widget.existingSerials!.map((s) => s.trim().toUpperCase()))
        : <String>{};
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );
    _scanLineAnimation = Tween<double>(begin: 8.0, end: _boxHeight - 12.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    if (!_holdToScanModeN.value) {
      _animController.repeat(reverse: true);
    }

    _initVolumeKeyListener();

    // Hardware barcode scanner (Bluetooth / USB) instant integration
    _hardwareScannerSub = HardwareScannerService().registerListener((barcode) {
      if (mounted && !_isClosing) {
        _enqueueHardwareScan(barcode);
      }
    });
  }

  void _enqueueHardwareScan(String barcode) {
    _hwPendingQueue.add(barcode);
    if (_drainingHwQueue) return;
    _drainHwQueue();
  }

  Future<void> _drainHwQueue() async {
    if (_drainingHwQueue) return;
    _drainingHwQueue = true;
    try {
      while (_hwPendingQueue.isNotEmpty && mounted && !_isClosing) {
        final next = _hwPendingQueue.removeAt(0);
        await _processScannedValue(next, fromHardware: true);
      }
    } finally {
      _drainingHwQueue = false;
    }
  }

  void _closeScanner() {
    if (_isClosing) return;
    _isClosing = true;
    _hwPendingQueue.clear();
    _hardwareScannerSub?.call();
    _hardwareScannerSub = null;
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _initVolumeKeyListener() {
    try {
      _volumeChannel.setMethodCallHandler((call) async {
        if (!mounted) return;
        switch (call.method) {
          case 'onVolumeKeyDown':
            _setTriggerHeld(true);
            break;
          case 'onVolumeKeyUp':
            _setTriggerHeld(false);
            break;
        }
      });
      _volumeChannel.invokeMethod('enable');
    } catch (_) {}

    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (!_holdToScanModeN.value) return false;
    if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp ||
        event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
      if (event is KeyDownEvent) {
        _setTriggerHeld(true);
        return true;
      } else if (event is KeyUpEvent) {
        _setTriggerHeld(false);
        return true;
      }
    }
    return false;
  }

  void _setTriggerHeld(bool isHeld) {
    if (!mounted || !_holdToScanModeN.value || _isHoldingTriggerN.value == isHeld) return;
    HapticFeedback.lightImpact();
    _isHoldingTriggerN.value = isHeld;
    if (isHeld) {
      if (!_animController.isAnimating) {
        _animController.repeat(reverse: true);
      }
    } else {
      _animController.stop();
      _animController.reset();
    }
  }

  @override
  void dispose() {
    _hardwareScannerSub?.call();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    try {
      _volumeChannel.invokeMethod('disable');
    } catch (_) {}
    _animController.dispose();
    _controller.dispose();
    _manualTextController.dispose();
    _isTorchOnN.dispose();
    _isProcessingN.dispose();
    _isDuplicateWarningN.dispose();
    _holdToScanModeN.dispose();
    _isHoldingTriggerN.dispose();
    _lastScannedValueN.dispose();
    _scannedCountN.dispose();
    super.dispose();
  }

  double? _computeNormalizedDistIfInsideBox(
    Barcode barcode,
    Size captureSize,
    Rect scanWindow,
    Size screenSize,
  ) {
    // MobileScanner already applies `scanWindow` natively; if a device/format omits
    // corner coordinates or reports Size.zero, accept rather than silently dropping the scan.
    final corners = barcode.corners;
    if (corners.isEmpty ||
        captureSize.width <= 0 ||
        captureSize.height <= 0 ||
        screenSize.width <= 0 ||
        screenSize.height <= 0) {
      return 0.0;
    }

    double minX = corners[0].dx;
    double maxX = minX;
    double minY = corners[0].dy;
    double maxY = minY;
    for (int i = 1; i < corners.length; i++) {
      final p = corners[i];
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    final normX = ((minX + maxX) * 0.5) / captureSize.width;
    final normY = ((minY + maxY) * 0.5) / captureSize.height;

    // Match buffer orientation against screen orientation so landscape tablets keep X->horiz and Y->vert
    final bool portraitCapture = captureSize.width < captureSize.height;
    final bool portraitScreen = screenSize.width < screenSize.height;
    final bool sameOrientation = (portraitCapture == portraitScreen);
    final double horiz = sameOrientation ? normX : normY;
    final double vert = sameOrientation ? normY : normX;

    // Exact normalized boundary ratios from the on-screen viewfinder box
    final double winLeftRatio = (scanWindow.left / screenSize.width).clamp(0.0, 1.0);
    final double winRightRatio = (scanWindow.right / screenSize.width).clamp(0.0, 1.0);
    final double winTopRatio = (scanWindow.top / screenSize.height).clamp(0.0, 1.0);
    final double winBottomRatio = (scanWindow.bottom / screenSize.height).clamp(0.0, 1.0);

    // Grace margin (+/- 6% padding) around the visual frame
    const double margin = 0.06;
    final double minHoriz = math.max(0.0, winLeftRatio - margin);
    final double maxHoriz = math.min(1.0, winRightRatio + margin);
    final double minVert = math.max(0.0, winTopRatio - margin);
    final double maxVert = math.min(1.0, winBottomRatio + margin);

    if (horiz < minHoriz || horiz > maxHoriz || vert < minVert || vert > maxVert) {
      return null;
    }

    // Distance squared from reticle center (0.5, 0.5)
    return (horiz - 0.5) * (horiz - 0.5) + (vert - 0.5) * (vert - 0.5);
  }

  void _handleBarcode(BarcodeCapture capture, Rect scanWindow, Size screenSize) {
    // In hold-to-scan mode, reject scans unless the user is actively holding down the trigger
    if (_holdToScanModeN.value && !_isHoldingTriggerN.value) {
      return;
    }

    if (_isProcessingN.value) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    String? bestVal;
    double bestDist = double.infinity;

    for (final barcode in barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue == null) continue;
      final String trimmed = rawValue.trim();
      if (trimmed.isEmpty) continue;

      final double? dist = _computeNormalizedDistIfInsideBox(
        barcode,
        capture.size,
        scanWindow,
        screenSize,
      );
      if (dist != null && dist < bestDist) {
        bestDist = dist;
        bestVal = trimmed;
      }
    }

    if (bestVal != null) {
      _processScannedValue(bestVal);
    }
  }

  Future<void> _processScannedValue(String rawVal, {bool fromHardware = false}) async {
    final String cleanVal = rawVal.trim().toUpperCase();
    if (cleanVal.isEmpty || _isClosing) return;
    if (!fromHardware && _isProcessingN.value) return;

    final DateTime now = DateTime.now();
    _lastScanTime = now;

    // 1. Prevent accidental optical repeat scanning of the same barcode within 2000ms for camera frames
    if (!fromHardware) {
      final lastTime = _recentScanTimes[cleanVal];
      if (lastTime != null && now.difference(lastTime).inMilliseconds < 2000) {
        return;
      }
    }

    // 2. Instant duplicate rejection: prefer live batch check `widget.isDuplicate` when provided
    // so rejected/cancelled serials can be re-scanned without getting stuck in local session set.
    final bool isAlreadyInBatch = widget.isDuplicate != null
        ? widget.isDuplicate!(cleanVal)
        : _sessionScannedSerials.contains(cleanVal);

    if (isAlreadyInBatch) {
      _recentScanTimes[cleanVal] = now;
      HapticFeedback.heavyImpact();
      SoundService().playErrorSound();
      if (!_isDuplicateWarningN.value) {
        _isDuplicateWarningN.value = true;
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) _isDuplicateWarningN.value = false;
        });
      }
      return;
    }

    _recentScanTimes[cleanVal] = now;
    _sessionScannedSerials.add(cleanVal); // Tentatively claim

    // Audio cue on barcode detection
    SoundService().playScannerBeep();
    HapticFeedback.mediumImpact();

    final int countBefore = widget.itemCountProvider?.call() ?? _scannedCountN.value;

    _isProcessingN.value = true;

    dynamic result;
    try {
      result = await widget.onScanned(cleanVal);
    } catch (_) {
      result = false;
    }

    if (!mounted) return;

    final int countAfter = widget.itemCountProvider?.call() ?? _scannedCountN.value;
    final bool isSuccess = (result is bool) ? result : (result != false);

    if (isSuccess) {
      _scannedCountN.value = (countAfter > countBefore) ? countAfter : (_scannedCountN.value + 1);
      _lastScannedValueN.value = cleanVal;
    } else {
      _sessionScannedSerials.remove(cleanVal);
      _recentScanTimes.remove(cleanVal);
      if (widget.itemCountProvider != null) {
        _scannedCountN.value = countAfter;
      }
    }

    // Super-fast cooldown (260ms) so moving to the next unique item scans instantly!
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) _isProcessingN.value = false;
    });
  }

  Color _getReticleBorderColor() {
    if (_isDuplicateWarningN.value) {
      return const Color(0xFFEF4444); // Bright Red when duplicate scanned
    }
    if (_isProcessingN.value) {
      return const Color(0xFF10B981); // Emerald green on successful read
    }
    if (_holdToScanModeN.value) {
      return _isHoldingTriggerN.value
          ? const Color(0xFF38BDF8) // Bright Cyan when trigger active
          : const Color(0xFF64748B); // Slate muted when idle
    }
    return const Color(0xFF818CF8); // Indigo in auto-scan mode
  }

  void _showManualInputDialog() {
    _manualTextController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Type Serial Number',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        content: TextField(
          controller: _manualTextController,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: const [UpperCaseTextFormatter()],
          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
          decoration: InputDecoration(
            hintText: 'e.g. LG2026-X89',
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3C3489), width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3C3489),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final val = _manualTextController.text.trim();
              if (val.isNotEmpty) {
                Navigator.pop(ctx);
                _processScannedValue(val);
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _isClosing = true;
          _hardwareScannerSub?.call();
          _hardwareScannerSub = null;
          return;
        }
        final now = DateTime.now();
        if (_lastScanTime != null && now.difference(_lastScanTime!).inMilliseconds < 2500) {
          debugPrint('[BarcodeScannerWidget] Swallowed pop attempt within 2500ms of scan');
          return;
        }
        _closeScanner();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          leading: Focus(
            canRequestFocus: false,
            descendantsAreFocusable: false,
            skipTraversal: true,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                final now = DateTime.now();
                if (_lastScanTime != null && now.difference(_lastScanTime!).inMilliseconds < 2500) {
                  return;
                }
                _closeScanner();
              },
            ),
          ),
          actions: [
            const FlushLagButton(compact: true, color: Colors.amberAccent),
            Focus(
              canRequestFocus: false,
              descendantsAreFocusable: false,
              child: ValueListenableBuilder<bool>(
                valueListenable: _isTorchOnN,
                builder: (context, isTorchOn, _) => IconButton(
                  icon: Icon(isTorchOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
                  onPressed: () async {
                    await _controller.toggleTorch();
                    _isTorchOnN.value = !_isTorchOnN.value;
                  },
                ),
              ),
            ),
            Focus(
              canRequestFocus: false,
              descendantsAreFocusable: false,
              child: IconButton(
                icon: const Icon(Icons.flip_camera_android),
                onPressed: () => _controller.switchCamera(),
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final screenSize = constraints.biggest;
            final scanWindow = Rect.fromCenter(
              center: Offset(screenSize.width / 2, screenSize.height / 2),
              width: _boxWidth,
              height: _boxHeight,
            );

            return Stack(
              alignment: Alignment.center,
              children: [
                // Isolated camera stream so trigger/overlay updates never rebuild MobileScanner
                RepaintBoundary(
                  child: MobileScanner(
                    controller: _controller,
                    scanWindow: scanWindow,
                    fit: BoxFit.cover,
                    onDetect: (capture) => _handleBarcode(capture, scanWindow, screenSize),
                  ),
                ),

                // Single-pass even-odd cutout overlay (eliminates ColorFiltered/BlendMode offscreen saveLayer)
                RepaintBoundary(
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: screenSize,
                      painter: _ScannerOverlayPainter(scanWindow: scanWindow),
                    ),
                  ),
                ),

                // Reticle border with corner accents and live scanning indicator
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _reticleListenable,
                    builder: (context, _) {
                      final bool holdMode = _holdToScanModeN.value;
                      final bool holding = _isHoldingTriggerN.value;
                      final bool processing = _isProcessingN.value;
                      final bool isScanningActive = !holdMode || holding;
                      final Color borderColor = _getReticleBorderColor();

                      return Container(
                        width: _boxWidth,
                        height: _boxHeight,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: borderColor.withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Precision corner brackets
                            CustomPaint(
                              size: const Size(_boxWidth, _boxHeight),
                              painter: _CornerBracketsPainter(
                                color: borderColor,
                                cornerLength: 26.0,
                                strokeWidth: isScanningActive ? 3.5 : 2.5,
                              ),
                            ),

                            if (isScanningActive)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: AnimatedBuilder(
                                  animation: _scanLineAnimation,
                                  builder: (context, child) {
                                    final Color lineColor = processing
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFF38BDF8);
                                    return Stack(
                                      children: [
                                        Positioned(
                                          top: _scanLineAnimation.value,
                                          left: 10,
                                          right: 10,
                                          child: Container(
                                            height: 2.5,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.transparent,
                                                  lineColor,
                                                  Colors.transparent,
                                                ],
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: lineColor.withValues(alpha: 0.8),
                                                  blurRadius: 6,
                                                  spreadRadius: 1.5,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),

                            if (holdMode && !holding)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.touch_app, size: 16, color: Colors.white70),
                                    SizedBox(width: 6),
                                    Text(
                                      'Hold button below to scan',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
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
                ),

                // Top Header (Last Scanned Card popped from upside + Prompt & Mode Switch)
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Prominently pop out the scanned serial number card from UPSIDE (the top)
                      RepaintBoundary(
                        child: ValueListenableBuilder<String?>(
                          valueListenable: _lastScannedValueN,
                          builder: (context, lastVal, _) => AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, anim) => SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.0, -0.6),
                                end: Offset.zero,
                              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                              child: FadeTransition(opacity: anim, child: child),
                            ),
                            child: (lastVal != null && lastVal.isNotEmpty)
                                ? Padding(
                                    key: ValueKey<String>(lastVal),
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _buildLastScannedCard(lastVal),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          widget.prompt,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Hold-to-scan Switch Toggle Pill
                      ValueListenableBuilder<bool>(
                        valueListenable: _holdToScanModeN,
                        builder: (context, holdMode, _) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: holdMode ? const Color(0xFF818CF8) : Colors.white24,
                              width: 1.2,
                            ),
                            boxShadow: [
                              if (holdMode)
                                BoxShadow(
                                  color: const Color(0xFF818CF8).withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                holdMode ? Icons.touch_app : Icons.bolt,
                                size: 18,
                                color: holdMode ? const Color(0xFF818CF8) : Colors.amberAccent,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                holdMode ? 'Hold to Scan Mode' : 'Continuous Auto Scan',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 28,
                                child: Switch(
                                  value: holdMode,
                                  activeThumbColor: const Color(0xFF818CF8),
                                  activeTrackColor: const Color(0xFF312E81),
                                  inactiveThumbColor: Colors.white70,
                                  inactiveTrackColor: Colors.white24,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  onChanged: (val) {
                                    HapticFeedback.selectionClick();
                                    _holdToScanModeN.value = val;
                                    _isHoldingTriggerN.value = false;
                                    if (!val) {
                                      if (!_animController.isAnimating) {
                                        _animController.repeat(reverse: true);
                                      }
                                    } else {
                                      _animController.stop();
                                      _animController.reset();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom Controls (Trigger + Manual Input)
                Positioned(
                  bottom: 24,
                  left: 20,
                  right: 20,
                  child: RepaintBoundary(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _holdToScanModeN,
                      builder: (context, holdMode, _) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (holdMode) ...[
                            ValueListenableBuilder<bool>(
                              valueListenable: _isHoldingTriggerN,
                              builder: (context, holding, _) => Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: (_) => _setTriggerHeld(true),
                                onPointerUp: (_) => _setTriggerHeld(false),
                                onPointerCancel: (_) => _setTriggerHeld(false),
                                child: AnimatedScale(
                                  scale: holding ? 0.96 : 1.0,
                                  duration: const Duration(milliseconds: 100),
                                  child: Container(
                                    height: 58,
                                    constraints: const BoxConstraints(maxWidth: 320),
                                    decoration: BoxDecoration(
                                      gradient: holding
                                          ? const LinearGradient(
                                              colors: [Color(0xFF10B981), Color(0xFF059669)],
                                            )
                                          : const LinearGradient(
                                              colors: [Color(0xFF4F46E5), Color(0xFF3730A3)],
                                            ),
                                      borderRadius: BorderRadius.circular(29),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (holding
                                                  ? const Color(0xFF10B981)
                                                  : const Color(0xFF4F46E5))
                                              .withValues(alpha: holding ? 0.6 : 0.35),
                                          blurRadius: holding ? 18 : 10,
                                          spreadRadius: holding ? 2 : 0,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            holding ? Icons.sensors : Icons.touch_app,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            holding ? 'SCANNING (HOLDING)...' : 'HOLD TO SCAN',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextButton.icon(
                              onPressed: _showManualInputDialog,
                              icon: const Icon(Icons.keyboard, color: Colors.white70, size: 18),
                              label: const Text(
                                'Type Serial Manually',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ] else ...[
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF1E293B),
                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                                elevation: 4,
                              ),
                              icon: const Icon(Icons.keyboard, size: 20, color: Color(0xFF3C3489)),
                              label: const Text('Type Serial Manually', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              onPressed: _showManualInputDialog,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLastScannedCard(String lastScannedValue) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF10B981),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.35),
            blurRadius: 14,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'LAST SCANNED SERIAL',
                      style: TextStyle(
                        color: Color(0xFF34D399),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: _scannedCountN,
                      builder: (context, _, _) {
                        final count = _currentCount;
                        if (count <= 0) return const SizedBox.shrink();
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '#$count',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                SelectableText(
                  lastScannedValue,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Rect scanWindow;

  const _ScannerOverlayPainter({required this.scanWindow});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(scanWindow, const Radius.circular(16)));

    final paint = Paint()..color = const Color(0xB8000000);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow;
  }
}

class _CornerBracketsPainter extends CustomPainter {
  final Color color;
  final double cornerLength;
  final double strokeWidth;

  const _CornerBracketsPainter({
    required this.color,
    this.cornerLength = 26.0,
    this.strokeWidth = 3.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const double r = 16.0;
    const Radius rad = Radius.circular(r);

    final path = Path()
      // Top-Left
      ..moveTo(0, cornerLength)
      ..lineTo(0, r)
      ..arcToPoint(const Offset(r, 0), radius: rad)
      ..lineTo(cornerLength, 0)
      // Top-Right
      ..moveTo(size.width - cornerLength, 0)
      ..lineTo(size.width - r, 0)
      ..arcToPoint(Offset(size.width, r), radius: rad)
      ..lineTo(size.width, cornerLength)
      // Bottom-Left
      ..moveTo(0, size.height - cornerLength)
      ..lineTo(0, size.height - r)
      ..arcToPoint(Offset(r, size.height), radius: rad)
      ..lineTo(cornerLength, size.height)
      // Bottom-Right
      ..moveTo(size.width - cornerLength, size.height)
      ..lineTo(size.width - r, size.height)
      ..arcToPoint(Offset(size.width, size.height - r), radius: rad)
      ..lineTo(size.width, size.height - cornerLength);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketsPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.cornerLength != cornerLength;
  }
}
