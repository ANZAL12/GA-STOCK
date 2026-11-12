import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/hardware_scanner_service.dart';
import 'top_toast.dart';

/// Reusable small action button to flush lag, purge audio queues,
/// wipe stuck hardware keyboard buffers, and release native system resources.
class FlushLagButton extends StatefulWidget {
  final VoidCallback? onCustomFlush;
  final bool compact;
  final Color? color;

  const FlushLagButton({
    super.key,
    this.onCustomFlush,
    this.compact = false,
    this.color,
  });

  @override
  State<FlushLagButton> createState() => _FlushLagButtonState();
}

class _FlushLagButtonState extends State<FlushLagButton> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  bool _isFlushing = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleFlush() async {
    if (_isFlushing) return;
    setState(() => _isFlushing = true);
    _animController.forward(from: 0.0);

    // 1. Immediate crisp tactile & audio feedback
    try {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}

    // 2. Unfocus any active keyboard or focus node to reset soft keyboard and dongle buffer
    try {
      FocusManager.instance.primaryFocus?.unfocus();
    } catch (_) {}

    // 3. Clear Flutter memory & image caches for low-RAM (3GB) tablets
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    // 4. Flush Hardware Scanner queues & Sound Service audio channels
    HardwareScannerService().flushAll();

    // 5. Invoke screen-specific cleanup if provided
    try {
      widget.onCustomFlush?.call();
    } catch (e) {
      debugPrint('[FlushLagButton] onCustomFlush error: $e');
    }

    // 6. Visual notification toast
    if (mounted) {
      TopToast.show(
        context,
        message: '⚡ Scanner Buffer & Audio Flushed — Lag Cleared',
        backgroundColor: const Color(0xFFD97706), // Amber-600
        icon: Icons.bolt_rounded,
        duration: const Duration(milliseconds: 1400),
      );
    }

    await Future.delayed(const Duration(milliseconds: 450));
    if (mounted) {
      setState(() => _isFlushing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return Focus(
        canRequestFocus: false,
        descendantsAreFocusable: false,
        skipTraversal: true,
        child: RotationTransition(
          turns: Tween(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
          ),
          child: IconButton(
            icon: Icon(
              Icons.bolt_rounded,
              color: widget.color ?? const Color(0xFFD97706),
              size: 22,
            ),
            tooltip: 'Flush Lag ⚡ (Reset Scanner & Audio)',
            onPressed: _handleFlush,
          ),
        ),
      );
    }

    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      skipTraversal: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Material(
            color: const Color(0xFFFEF3C7), // Amber 100
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFFF59E0B), width: 1), // Amber 500
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _handleFlush,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RotationTransition(
                      turns: Tween(begin: 0.0, end: 1.0).animate(
                        CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        size: 16,
                        color: Color(0xFFB45309), // Amber 700
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Text(
                      'Flush',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
