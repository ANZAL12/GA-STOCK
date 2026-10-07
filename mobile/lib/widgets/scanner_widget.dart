import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/sound_service.dart';

class BarcodeScannerWidget extends StatefulWidget {
  final String title;
  final String prompt;
  final String? initialLastScanned;
  final int initialCount;
  final Function(String barcode) onScanned;

  const BarcodeScannerWidget({
    super.key,
    required this.title,
    this.prompt = 'Align barcode strictly inside viewfinder',
    this.initialLastScanned,
    this.initialCount = 0,
    required this.onScanned,
  });

  @override
  State<BarcodeScannerWidget> createState() => _BarcodeScannerWidgetState();
}

class _BarcodeScannerWidgetState extends State<BarcodeScannerWidget>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.unrestricted,
    facing: CameraFacing.back,
    torchEnabled: false,
    returnImage: false,
  );

  late AnimationController _animController;
  late Animation<double> _scanLineAnimation;

  bool _isTorchOn = false;
  bool _isProcessing = false;
  bool _holdToScanMode = true;
  bool _isHoldingTrigger = false;
  String? _lastScannedValue;
  int _scannedCount = 0;
  DateTime _lastScannedTime = DateTime.fromMillisecondsSinceEpoch(0);
  final TextEditingController _manualTextController = TextEditingController();

  static const double _boxWidth = 290.0;
  static const double _boxHeight = 190.0;

  @override
  void initState() {
    super.initState();
    SoundService().init();
    _lastScannedValue = widget.initialLastScanned;
    _scannedCount = widget.initialCount;
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );
    _scanLineAnimation = Tween<double>(begin: 8.0, end: _boxHeight - 12.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    if (!_holdToScanMode) {
      _animController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    _manualTextController.dispose();
    super.dispose();
  }

  bool _isBarcodeInsideBox(
    Barcode barcode,
    Size captureSize,
    Rect scanWindow,
    Size screenSize,
  ) {
    // Strict constraint: Reject immediately if corner points are missing or dimensions invalid
    if (barcode.corners.isEmpty || captureSize.width <= 0 || captureSize.height <= 0) {
      return false;
    }

    try {
      final xs = barcode.corners.map((p) => p.dx);
      final ys = barcode.corners.map((p) => p.dy);
      final minX = xs.reduce(math.min);
      final maxX = xs.reduce(math.max);
      final minY = ys.reduce(math.min);
      final maxY = ys.reduce(math.max);

      final centerX = (minX + maxX) / 2.0;
      final centerY = (minY + maxY) / 2.0;

      final normX = centerX / captureSize.width;
      final normY = centerY / captureSize.height;

      // Normalize coordinates according to portrait phone orientation
      // When camera buffer is landscape (width > height), buffer X maps to portrait Y and buffer Y to portrait X
      final double horiz = captureSize.width < captureSize.height ? normX : normY;
      final double vert = captureSize.width < captureSize.height ? normY : normX;

      // Exact normalized boundary ratios from the on-screen viewfinder box
      final double winLeftRatio = (scanWindow.left / screenSize.width).clamp(0.0, 1.0);
      final double winRightRatio = (scanWindow.right / screenSize.width).clamp(0.0, 1.0);
      final double winTopRatio = (scanWindow.top / screenSize.height).clamp(0.0, 1.0);
      final double winBottomRatio = (scanWindow.bottom / screenSize.height).clamp(0.0, 1.0);

      // Tight grace margin (+/- 3.5% padding) around the visual frame
      const double margin = 0.035;
      final double minHoriz = math.max(0.0, winLeftRatio - margin);
      final double maxHoriz = math.min(1.0, winRightRatio + margin);
      final double minVert = math.max(0.0, winTopRatio - margin);
      final double maxVert = math.min(1.0, winBottomRatio + margin);

      final bool inHoriz = horiz >= minHoriz && horiz <= maxHoriz;
      final bool inVert = vert >= minVert && vert <= maxVert;

      return inHoriz && inVert;
    } catch (_) {
      return false;
    }
  }

  void _handleBarcode(BarcodeCapture capture, Rect scanWindow, Size screenSize) {
    // In hold-to-scan mode, reject scans unless the user is actively holding down the trigger
    if (_holdToScanMode && !_isHoldingTrigger) {
      return;
    }

    if (_isProcessing) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    // Filter to candidates strictly inside the preferred viewfinder area
    final List<({Barcode barcode, double distFromCenter, String cleanVal})> candidates = [];

    for (final barcode in barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue == null || rawValue.trim().isEmpty) continue;

      // Strict constraint: Reject barcodes located outside the preferred viewfinder area
      if (!_isBarcodeInsideBox(barcode, capture.size, scanWindow, screenSize)) {
        continue;
      }

      final xs = barcode.corners.map((p) => p.dx);
      final ys = barcode.corners.map((p) => p.dy);
      final centerX = (xs.reduce(math.min) + xs.reduce(math.max)) / 2.0;
      final centerY = (ys.reduce(math.min) + ys.reduce(math.max)) / 2.0;
      final normX = centerX / capture.size.width;
      final normY = centerY / capture.size.height;
      final horiz = capture.size.width < capture.size.height ? normX : normY;
      final vert = capture.size.width < capture.size.height ? normY : normX;

      // Distance from reticle center (0.5, 0.5)
      final dist = (horiz - 0.5) * (horiz - 0.5) + (vert - 0.5) * (vert - 0.5);

      candidates.add((
        barcode: barcode,
        distFromCenter: dist,
        cleanVal: rawValue.trim(),
      ));
    }

    if (candidates.isEmpty) return;

    // Prioritize the barcode closest to the viewfinder center
    candidates.sort((a, b) => a.distFromCenter.compareTo(b.distFromCenter));

    final String cleanVal = candidates.first.cleanVal;
    final DateTime now = DateTime.now();

    // Prevent accidental repeat scanning of the EXACT same physical barcode
    if (_lastScannedValue == cleanVal &&
        now.difference(_lastScannedTime).inMilliseconds < 1500) {
      return;
    }

    _lastScannedTime = now;

    // Fire beep sound and haptic first for absolute zero-delay audio feedback
    SoundService().playScannerBeep();
    HapticFeedback.mediumImpact();
    setState(() {
      _lastScannedValue = cleanVal;
      _scannedCount++;
      _isProcessing = true;
    });

    widget.onScanned(cleanVal);

    // Super-fast cooldown (280ms) so moving to the next item scans instantly!
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted) setState(() => _isProcessing = false);
    });
  }

  Color _getReticleBorderColor() {
    if (_isProcessing) {
      return const Color(0xFF10B981); // Emerald green on successful read
    }
    if (_holdToScanMode) {
      return _isHoldingTrigger
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
                HapticFeedback.lightImpact();
                setState(() {
                  _lastScannedValue = val;
                  _scannedCount++;
                });
                widget.onScanned(val);
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
    final bool isScanningActive = !_holdToScanMode || _isHoldingTrigger;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
            onPressed: () async {
              await _controller.toggleTorch();
              setState(() => _isTorchOn = !_isTorchOn);
            },
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android),
            onPressed: () => _controller.switchCamera(),
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
              // Camera stream with strict native scanWindow constraint
              MobileScanner(
                controller: _controller,
                scanWindow: scanWindow,
                fit: BoxFit.cover,
                onDetect: (capture) => _handleBarcode(capture, scanWindow, screenSize),
              ),

              // Overlay cutout - darkens area outside the preferred box
              ColorFiltered(
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.72),
                  BlendMode.srcOut,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        backgroundBlendMode: BlendMode.dstOut,
                      ),
                    ),
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: _boxWidth,
                        height: _boxHeight,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Reticle border with corner accents and live scanning indicator
              Container(
                width: _boxWidth,
                height: _boxHeight,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _getReticleBorderColor().withValues(alpha: 0.35),
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
                        color: _getReticleBorderColor(),
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
                                      _isProcessing
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFF38BDF8),
                                      Colors.transparent,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_isProcessing
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFF38BDF8))
                                          .withValues(alpha: 0.8),
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
                if (_holdToScanMode && !_isHoldingTrigger)
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
          ),

          // Top Header (Prompt & Mode Switch)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _holdToScanMode ? const Color(0xFF818CF8) : Colors.white24,
                      width: 1.2,
                    ),
                    boxShadow: [
                      if (_holdToScanMode)
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
                        _holdToScanMode ? Icons.touch_app : Icons.bolt,
                        size: 18,
                        color: _holdToScanMode ? const Color(0xFF818CF8) : Colors.amberAccent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _holdToScanMode ? 'Hold to Scan Mode' : 'Continuous Auto Scan',
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
                          value: _holdToScanMode,
                          activeThumbColor: const Color(0xFF818CF8),
                          activeTrackColor: const Color(0xFF312E81),
                          inactiveThumbColor: Colors.white70,
                          inactiveTrackColor: Colors.white24,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (val) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _holdToScanMode = val;
                              _isHoldingTrigger = false;
                            });
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
              ],
            ),
          ),

          // Bottom Controls (Trigger + Manual Input + Last Scanned)
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Prominently display the last scanned serial number
                _buildLastScannedCard(),
                const SizedBox(height: 12),

                if (_holdToScanMode) ...[
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) {
                      HapticFeedback.lightImpact();
                      setState(() => _isHoldingTrigger = true);
                      if (!_animController.isAnimating) {
                        _animController.repeat(reverse: true);
                      }
                    },
                    onPointerUp: (_) {
                      setState(() => _isHoldingTrigger = false);
                      _animController.stop();
                      _animController.reset();
                    },
                    onPointerCancel: (_) {
                      setState(() => _isHoldingTrigger = false);
                      _animController.stop();
                      _animController.reset();
                    },
                    child: AnimatedScale(
                      scale: _isHoldingTrigger ? 0.96 : 1.0,
                      duration: const Duration(milliseconds: 100),
                      child: Container(
                        height: 58,
                        constraints: const BoxConstraints(maxWidth: 320),
                        decoration: BoxDecoration(
                          gradient: _isHoldingTrigger
                              ? const LinearGradient(
                                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                                )
                              : const LinearGradient(
                                  colors: [Color(0xFF4F46E5), Color(0xFF3730A3)],
                                ),
                          borderRadius: BorderRadius.circular(29),
                          boxShadow: [
                            BoxShadow(
                              color: (_isHoldingTrigger
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF4F46E5))
                                  .withValues(alpha: _isHoldingTrigger ? 0.6 : 0.35),
                              blurRadius: _isHoldingTrigger ? 18 : 10,
                              spreadRadius: _isHoldingTrigger ? 2 : 0,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isHoldingTrigger ? Icons.sensors : Icons.touch_app,
                                color: Colors.white,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _isHoldingTrigger ? 'SCANNING (HOLDING)...' : 'HOLD TO SCAN',
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
        ],
      );
    },
  ),
);
  }

  Widget _buildLastScannedCard() {
    if (_lastScannedValue == null || _lastScannedValue!.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_scanner, size: 14, color: Colors.white54),
            SizedBox(width: 8),
            Text(
              'No serial scanned yet',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

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
                    if (_scannedCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '#$_scannedCount',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                SelectableText(
                  _lastScannedValue!,
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

    // Top-Left
    final pathTL = Path()
      ..moveTo(0, cornerLength)
      ..lineTo(0, r)
      ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
      ..lineTo(cornerLength, 0);
    canvas.drawPath(pathTL, paint);

    // Top-Right
    final pathTR = Path()
      ..moveTo(size.width - cornerLength, 0)
      ..lineTo(size.width - r, 0)
      ..arcToPoint(Offset(size.width, r), radius: const Radius.circular(r))
      ..lineTo(size.width, cornerLength);
    canvas.drawPath(pathTR, paint);

    // Bottom-Left
    final pathBL = Path()
      ..moveTo(0, size.height - cornerLength)
      ..lineTo(0, size.height - r)
      ..arcToPoint(Offset(r, size.height), radius: const Radius.circular(r))
      ..lineTo(cornerLength, size.height);
    canvas.drawPath(pathBL, paint);

    // Bottom-Right
    final pathBR = Path()
      ..moveTo(size.width - cornerLength, size.height)
      ..lineTo(size.width - r, size.height)
      ..arcToPoint(Offset(size.width, size.height - r), radius: const Radius.circular(r))
      ..lineTo(size.width, size.height - cornerLength);
    canvas.drawPath(pathBR, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketsPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.cornerLength != cornerLength;
  }
}
