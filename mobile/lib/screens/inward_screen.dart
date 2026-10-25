import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/hardware_scanner_service.dart';
import '../services/offline_queue_service.dart';
import '../services/offline_manager.dart';
import '../services/websocket_service.dart';
import '../widgets/responsive_utils.dart';
import '../widgets/scanner_widget.dart';
import '../widgets/top_toast.dart';
import '../widgets/offline_banner.dart';
import '../services/sound_service.dart';

enum InwardStage {
  selectCase,   // Step 1: Pick Stock In, Returned Product, or Damaged Product
  selectModel,  // Step 2 (Only for Stock In): Select appliance model
  scanning,     // Step 3 (or Step 2 for Return/Damaged): Scanner & scanned items list
}

class InwardScannedItem {
  final String serialNumber;
  final Product product;
  String? unitType; // 'indoor' or 'outdoor'
  final bool isAutoDetected;
  final int sequenceNumber;

  InwardScannedItem({
    required this.serialNumber,
    required this.product,
    this.unitType,
    this.isAutoDetected = false,
    required this.sequenceNumber,
  });
}

class InwardScreen extends StatefulWidget {
  const InwardScreen({super.key});

  @override
  State<InwardScreen> createState() => _InwardScreenState();
}

class _InwardScreenState extends State<InwardScreen> {
  final ApiService _api = ApiService();
  final OfflineQueueService _queue = OfflineQueueService();
  StreamSubscription? _wsSubscription;
  VoidCallback? _scannerSub;

  InwardStage _stage = InwardStage.selectCase;
  String _inwardType = 'stock_in'; // 'stock_in', 'return', 'damaged'

  List<Product> _products = [];
  Product? _selectedProduct; // Only set upfront for 'stock_in'
  bool _loadingProducts = true;
  String _productSearch = '';

  final List<InwardScannedItem> _scannedItems = [];
  final Set<String> _scannedSerialSet = <String>{};
  int _sequenceCounter = 1;
  final List<String> _scanQueue = [];
  bool _isProcessingQueue = false;
  String? _lastScanFeedback;
  final ScrollController _scrollController = ScrollController();

  void _jumpToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _jumpToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  String _inwardUnitType = 'indoor'; // Used when scanning dual-serial in stock_in mode
  final TextEditingController _remarksController = TextEditingController();
  bool _submitting = false;
  final Set<String> _inFlightSerials = <String>{};
  String? _inwardRequestId;
  DateTime? _lastScanTime;

  BuildContext? _warningDialogContext;
  Timer? _warningDialogTimer;

  void _dismissWarningDialog() {
    _warningDialogTimer?.cancel();
    _warningDialogTimer = null;
    if (_warningDialogContext != null && _warningDialogContext!.mounted) {
      try {
        Navigator.of(_warningDialogContext!).pop();
      } catch (_) {}
    }
    _warningDialogContext = null;
  }

  @override
  void initState() {
    super.initState();
    // Instant 0ms render from cache
    final cached = _api.cachedProducts;
    if (cached != null && cached.isNotEmpty) {
      _products = List<Product>.from(cached);
      _loadingProducts = false;
    }
    _loadProducts();
    _initWebSocket();

    // Hardware barcode scanner support
    _scannerSub = HardwareScannerService().registerListener((barcode) {
      if (!mounted) return;

      // If the duplicate/warning dialog is currently showing, dismiss it immediately on next scan!
      final bool wasWarningShowing = _warningDialogContext != null;
      if (wasWarningShowing) {
        _dismissWarningDialog();
      }

      // If a route other than the auto-dismissing warning dialog is on top (e.g. model picker), ignore
      if (!wasWarningShowing && ModalRoute.of(context)?.isCurrent != true) return;

      _lastScanTime = DateTime.now();
      if (FocusScope.of(context).hasFocus) {
        FocusScope.of(context).unfocus();
      }
      if (_stage == InwardStage.scanning) {
        _handleScannedSerial(barcode);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please select inward type and model first to register $barcode'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  void _initWebSocket() {
    WebSocketService().connect();
    _wsSubscription = WebSocketService().stream.listen((event) {
      if (!mounted) return;
      final type = event['event']?.toString() ?? event['type']?.toString();
      final data = event['data'];

      if (type == 'product_created' && data is Map<String, dynamic>) {
        try {
          final newProd = Product.fromJson(data);
          _api.updateCachedProduct(newProd);
          setState(() {
            _products.removeWhere((p) => p.id == newProd.id);
            _products.insert(0, newProd);
          });
        } catch (_) {}
      } else if (type == 'product_updated' && data is Map<String, dynamic>) {
        try {
          final updatedProd = Product.fromJson(data);
          _api.updateCachedProduct(updatedProd);
          setState(() {
            final idx = _products.indexWhere((p) => p.id == updatedProd.id);
            if (idx != -1) {
              _products[idx] = updatedProd;
              if (_selectedProduct?.id == updatedProd.id) {
                _selectedProduct = updatedProd;
              }
            }
          });
        } catch (_) {}
      } else if (type == 'product_deleted' && data is Map<String, dynamic>) {
        final id = data['id']?.toString();
        if (id != null) {
          setState(() {
            _products.removeWhere((p) => p.id == id);
            if (_selectedProduct?.id == id) {
              _selectedProduct = null;
            }
          });
        }
      } else if (type == 'stock_updated') {
        if (data is Map<String, dynamic>) {
          final pid = data['product_id']?.toString();
          final rawQty = data['current_stock_qty'];
          final newQty = rawQty is int ? rawQty : int.tryParse(rawQty?.toString() ?? '');
          if (pid != null && newQty != null) {
            _api.updateProductStock(pid, newQty);
            setState(() {
              final idx = _products.indexWhere((p) => p.id == pid);
              if (idx != -1) {
                _products[idx] = _products[idx].copyWith(currentStockQty: newQty);
                if (_selectedProduct?.id == pid) {
                  _selectedProduct = _products[idx];
                }
              }
            });
          } else {
            _loadProducts(forceRefresh: true);
          }
        } else {
          _loadProducts(forceRefresh: true);
        }
      }
    });
  }

  @override
  void dispose() {
    _dismissWarningDialog();
    _scannerSub?.call();
    _wsSubscription?.cancel();
    _scrollController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts({bool forceRefresh = false}) async {
    try {
      final list = await _api.getProducts(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _products = list;
          _loadingProducts = false;
          if (_selectedProduct != null) {
            final refreshed = _products.firstWhere(
              (p) => p.id == _selectedProduct!.id,
              orElse: () => _selectedProduct!,
            );
            _selectedProduct = refreshed;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingProducts = false);
        TopToast.show(
          context,
          message: 'Failed to load models: $e',
          backgroundColor: const Color(0xFFE11D48),
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  Product? _findProductById(String? id) {
    if (id == null) return null;
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  String _getInwardTypeTitle(String type) {
    switch (type) {
      case 'return':
        return 'Returned Product';
      case 'damaged':
        return 'Damaged Product';
      case 'stock_in':
      default:
        return 'Stock In (Direct from Company)';
    }
  }

  String _getInwardTypeShort(String type) {
    switch (type) {
      case 'return':
        return 'Return';
      case 'damaged':
        return 'Damaged';
      case 'stock_in':
      default:
        return 'Stock In';
    }
  }

  Color _getInwardTypeColor(String type) {
    switch (type) {
      case 'return':
        return const Color(0xFF059669); // Emerald
      case 'damaged':
        return const Color(0xFFD97706); // Amber
      case 'stock_in':
      default:
        return const Color(0xFF4F46E5); // Indigo
    }
  }

  Color _getInwardTypeBgColor(String type) {
    switch (type) {
      case 'return':
        return const Color(0xFFECFDF5);
      case 'damaged':
        return const Color(0xFFFFFBEB);
      case 'stock_in':
      default:
        return const Color(0xFFEEF2FF);
    }
  }

  IconData _getInwardTypeIcon(String type) {
    switch (type) {
      case 'return':
        return Icons.assignment_return_outlined;
      case 'damaged':
        return Icons.report_problem_outlined;
      case 'stock_in':
      default:
        return Icons.local_shipping_outlined;
    }
  }

  // Choose one of the 3 modes
  void _selectInwardCase(String type) {
    setState(() {
      _inwardType = type;
      _scannedItems.clear();
      _scannedSerialSet.clear();
      _sequenceCounter = 1;
      _scanQueue.clear();
      _isProcessingQueue = false;
      _lastScanFeedback = null;
      _inwardRequestId = null;

      if (type == 'stock_in') {
        // Stock In: Ask for model upfront
        _selectedProduct = null;
        _stage = InwardStage.selectModel;
      } else {
        // Returned Product or Damaged Product: Skip model selection, go straight to scanning!
        _selectedProduct = null;
        _stage = InwardStage.scanning;
      }
    });
  }

  void _onModelSelectedForStockIn(Product p) {
    setState(() {
      _selectedProduct = p;
      // Keep all previously scanned items and serials intact for multi-model batching
      _lastScanFeedback = 'Active model: ${p.brand} ${p.model}';
      _inwardUnitType = 'indoor';
      _stage = InwardStage.scanning;
    });
  }

  Future<bool> _handleWillPop() async {
    final now = DateTime.now();
    if (_lastScanTime != null && now.difference(_lastScanTime!).inMilliseconds < 2500) {
      debugPrint('[InwardScreen] _handleWillPop swallowed pop within 2500ms of scan');
      return false;
    }

    if (_stage == InwardStage.selectCase) {
      return true;
    }

    if (_stage == InwardStage.selectModel) {
      if (_scannedItems.isNotEmpty && _selectedProduct != null) {
        setState(() => _stage = InwardStage.scanning);
        return false;
      }
      setState(() => _stage = InwardStage.selectCase);
      return false;
    }

    // In scanning stage
    if (_scannedItems.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Discard Scanned Items?'),
          content: Text(
            'You have scanned ${_scannedItems.length} unit(s). Leaving will discard this batch.',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard & Leave', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (discard != true) return false;
    }

    setState(() {
      _scannedItems.clear();
      _scannedSerialSet.clear();
      _sequenceCounter = 1;
      _scanQueue.clear();
      _isProcessingQueue = false;
      _lastScanFeedback = null;
      if (_inwardType == 'stock_in') {
        _stage = InwardStage.selectModel;
      } else {
        _stage = InwardStage.selectCase;
      }
    });
    return false;
  }

  void _openScanner() {
    final shortType = _getInwardTypeShort(_inwardType);
    final String scanTitle = _inwardType == 'stock_in' && _selectedProduct != null
        ? 'Scan $shortType: ${_selectedProduct!.model}'
        : 'Scan $shortType Serials';
    final String prompt = _inwardType == 'stock_in' && _selectedProduct != null
        ? 'Scan barcode for ${_selectedProduct!.brand} ${_selectedProduct!.model}'
        : 'Scan appliance serial barcode to verify and register';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerWidget(
          title: scanTitle,
          prompt: prompt,
          initialLastScanned: _scannedItems.isNotEmpty ? _scannedItems.first.serialNumber : null,
          initialCount: _scannedItems.length,
          itemCountProvider: () => _scannedItems.length,
          existingSerials: _scannedSerialSet,
          isDuplicate: (s) {
            final sn = s.trim().toUpperCase();
            return _scannedSerialSet.contains(sn) || _scanQueue.contains(sn) || _inFlightSerials.contains(sn);
          },
          onScanned: (serial) => _handleScannedSerial(serial),
        ),
      ),
    );
  }

  void _handleScannedSerial(String serial) {
    _dismissWarningDialog();
    final cleanSerial = serial.trim().toUpperCase();
    if (cleanSerial.isEmpty) return;
    _lastScanTime = DateTime.now();

    // 1. Instant synchronous check: Reject immediately if already in batch OR currently in FIFO queue
    if (_scannedSerialSet.contains(cleanSerial) || _scanQueue.contains(cleanSerial)) {
      HapticFeedback.heavyImpact();
      SoundService().playErrorSound();
      if (mounted) {
        TopToast.show(
          context,
          message: 'Duplicate: Serial "$cleanSerial" already in batch',
          backgroundColor: const Color(0xFFE11D48),
        );
      }
      _showWarningDialog('Duplicate in Current Batch', 'Serial "$cleanSerial" is already scanned in this batch.');
      return;
    }

    // 2. Enqueue in strict FIFO order
    _scanQueue.add(cleanSerial);

    // 3. Start processing loop if idle
    if (!_isProcessingQueue) {
      _processScanQueue();
    }
  }

  Future<void> _processScanQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_scanQueue.isNotEmpty && mounted) {
      final cleanSerial = _scanQueue.removeAt(0);
      try {
        await _processSingleSerial(cleanSerial);
      } catch (e) {
        debugPrint('[InwardScreen] Exception processing serial $cleanSerial: $e');
      }
    }

    _isProcessingQueue = false;
  }

  Future<void> _processSingleSerial(String cleanSerial) async {
    // Re-verify it wasn't added already
    if (_scannedSerialSet.contains(cleanSerial)) return;
    _inFlightSerials.add(cleanSerial);

    try {
      // =========================================================================
      // CASE 1: STOCK IN (Direct from Company) - 0ms INSTANT LOCAL FAST-PATH
      // =========================================================================
      if (_inwardType == 'stock_in') {
        if (_selectedProduct == null) {
          _showWarningDialog('Model Required', 'Please select an appliance model before scanning.');
          return;
        }

        // Fast in-memory check against local godown inventory snapshot in 0ms:
        final localEntry = OfflineManager().serials[cleanSerial];
        if (localEntry != null && localEntry['st'] == 'available') {
          HapticFeedback.heavyImpact();
          SoundService().playErrorSound();
          _showWarningDialog(
            'Already in Stock',
            'Serial "$cleanSerial" is already registered in godown inventory as available (${localEntry['m'] ?? ""}).',
          );
          return;
        }

        final targetProduct = _selectedProduct!;
        final String? unitType = targetProduct.hasDualSerial ? _inwardUnitType : null;
        final seq = _sequenceCounter++;

        // Add to batch INSTANTLY (0ms latency, zero UI freeze, stable sequence number)
        setState(() {
          _scannedSerialSet.add(cleanSerial);
          _scannedItems.insert(
            0,
            InwardScannedItem(
              serialNumber: cleanSerial,
              product: targetProduct,
              unitType: unitType,
              isAutoDetected: false,
              sequenceNumber: seq,
            ),
          );
          _lastScanFeedback = '✓ Scanned #$seq: $cleanSerial • ${targetProduct.brand} ${targetProduct.model}';
        });

        // In stock_in mode, local 0ms memory check above already guaranteed uniqueness and stock availability.
        // The final atomic batch submission validates all serials together on the server.
        return;
      }

      // =========================================================================
      // CASE 2: RETURN & DAMAGED INWARD
      // =========================================================================
      // Fast check local snapshot first (0ms)
      Map<String, dynamic>? rawResult;
      if (OfflineManager().serials.containsKey(cleanSerial)) {
        rawResult = OfflineManager().validateInwardSerialOffline(null, cleanSerial, inwardType: _inwardType);
      }

      // If not in local snapshot, query backend sequentially (guaranteed 1 socket at a time)
      if (rawResult == null || rawResult['registered_model_id'] == null) {
        try {
          rawResult = await _api.validateInwardSerial(
            null,
            cleanSerial,
            inwardType: _inwardType,
          );
        } catch (_) {
          // Handled by fallback below
        }
      }

      final Map<String, dynamic> result = rawResult ??
          OfflineManager().validateInwardSerialOffline(null, cleanSerial, inwardType: _inwardType);

      final bool isValid = result['is_valid'] ?? true;
      final String? message = result['message'];
      final bool requiresConfirmation = result['requires_confirmation'] == true;

      if (!isValid) {
        HapticFeedback.heavyImpact();
        SoundService().playErrorSound();
        if (mounted) {
          TopToast.show(
            context,
            message: message ?? 'Cannot register serial "$cleanSerial"',
            backgroundColor: const Color(0xFFDC2626),
          );
        }
        _showWarningDialog('Serial Validation Warning', message ?? 'This serial number cannot be registered.');
        return;
      }

      if (requiresConfirmation) {
        HapticFeedback.mediumImpact();
        final proceed = await _showReturnNoticeDialog(
          cleanSerial,
          message ?? 'This serial was previously not marked as dispatched in the system.',
        );
        if (proceed != true) {
          return;
        }
      }

      Product? targetProduct;
      String? unitType;
      bool isAutoDetected = false;

      final registeredId = result['registered_model_id']?.toString();
      if (registeredId != null) {
        targetProduct = _findProductById(registeredId);
        if (targetProduct == null && result['model'] != null) {
          targetProduct = Product(
            id: registeredId,
            name: result['registered_model_name'] ?? '${result['brand'] ?? ''} ${result['model'] ?? ''}',
            brand: result['brand'] ?? '',
            model: result['model'] ?? '',
            categoryId: '',
            categoryName: 'Appliance',
            currentStockQty: 0,
            unit: 'unit',
            serialNumberRequired: true,
            outOfStockReminder: false,
            hasDualSerial: result['has_dual_serial'] == true,
          );
        }
        isAutoDetected = true;
        unitType = result['unit_type']?.toString();

        if (targetProduct != null && targetProduct.hasDualSerial && unitType == null) {
          unitType = await _showSelectUnitTypeDialog(cleanSerial, targetProduct);
          if (unitType == null) return;
        }
      } else {
        HapticFeedback.mediumImpact();
        final chosenProduct = await _showSelectModelForSerialDialog(cleanSerial);
        if (chosenProduct == null) {
          return;
        }
        targetProduct = chosenProduct;
        isAutoDetected = false;

        if (targetProduct.hasDualSerial) {
          unitType = await _showSelectUnitTypeDialog(cleanSerial, targetProduct);
          if (unitType == null) return;
        }
      }

      if (targetProduct == null) {
        _showWarningDialog('Model Required', 'Could not assign a model for serial "$cleanSerial".');
        return;
      }

      if (!_scannedSerialSet.contains(cleanSerial)) {
        final seq = _sequenceCounter++;
        setState(() {
          _scannedSerialSet.add(cleanSerial);
          _scannedItems.insert(
            0,
            InwardScannedItem(
              serialNumber: cleanSerial,
              product: targetProduct!,
              unitType: unitType,
              isAutoDetected: isAutoDetected,
              sequenceNumber: seq,
            ),
          );
          _lastScanFeedback = '✓ Scanned #$seq: $cleanSerial • ${targetProduct.brand} ${targetProduct.model}';
        });
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      _showWarningDialog('Validation Error', 'Failed to validate serial "$cleanSerial": $e');
    } finally {
      _inFlightSerials.remove(cleanSerial);
    }
  }

  // "Strange case" dialog: Prompt user to assign model for an unrecorded serial (Slides in from the TOP!)
  Future<Product?> _showSelectModelForSerialDialog(String serial) async {
    return showGeneralDialog<Product>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Assign Model',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, -1.0), // Pops out / drops down from the TOP (upside)
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: FadeTransition(
            opacity: anim,
            child: child,
          ),
        );
      },
                      pageBuilder: (ctx, anim1, anim2) {
        String filter = '';
        bool isSyncing = false;
        StreamSubscription? dialogWsSub;
        Timer? debounceTimer;

        return SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                elevation: 16,
                clipBehavior: Clip.antiAlias,
                child: StatefulBuilder(
                  builder: (context, setModalState) {
                    dialogWsSub ??= WebSocketService().stream.listen((event) {
                      final type = event['event']?.toString() ?? event['type']?.toString();
                      final data = event['data'];
                      if ((type == 'product_created' || type == 'product_updated') && data is Map<String, dynamic>) {
                        try {
                          final newProd = Product.fromJson(data);
                          _api.updateCachedProduct(newProd);
                          if (mounted) {
                            setState(() {
                              _products.removeWhere((p) => p.id == newProd.id);
                              _products.insert(0, newProd);
                            });
                          }
                          if (ctx.mounted) {
                            setModalState(() {});
                          }
                        } catch (_) {}
                      }
                    });

                    Future<void> syncFreshModels({String? query}) async {
                      setModalState(() => isSyncing = true);
                      try {
                        final fresh = await _api.getProducts(forceRefresh: true);
                        if (mounted) {
                          setState(() => _products = fresh);
                        }
                        if (ctx.mounted) {
                          setModalState(() => isSyncing = false);
                        }
                      } catch (_) {
                        if (ctx.mounted) {
                          setModalState(() => isSyncing = false);
                        }
                      }
                    }

                    final filtered = _products.where((p) {
                      final q = filter.toLowerCase();
                      return p.name.toLowerCase().contains(q) ||
                          p.brand.toLowerCase().contains(q) ||
                          p.model.toLowerCase().contains(q) ||
                          (p.sku?.toLowerCase().contains(q) ?? false);
                    }).toList();

                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                ),
                                child: const Icon(Icons.help_outline_rounded, color: Color(0xFFD97706), size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Assign Appliance Model',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Serial "$serial"',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontFamily: 'monospace'),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Sync Models from Server',
                                icon: isSyncing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F46E5)),
                                      )
                                    : const Icon(Icons.sync_rounded, color: Color(0xFF4F46E5)),
                                onPressed: isSyncing ? null : () => syncFreshModels(query: filter),
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => Navigator.pop(ctx, null),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.close, color: Color(0xFF94A3B8), size: 20),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline, size: 16, color: Color(0xFF475569)),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Select the matching appliance model for this unit:',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            autofocus: false,
                            decoration: InputDecoration(
                              hintText: 'Search brand or model (e.g. GXI 360)...',
                              prefixIcon: const Icon(Icons.search, size: 18),
                              suffixIcon: isSyncing
                                  ? const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                    )
                                  : null,
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFF1F5F9),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            ),
                            onChanged: (val) {
                              setModalState(() => filter = val);
                              if (val.trim().length >= 2) {
                                debounceTimer?.cancel();
                                debounceTimer = Timer(const Duration(milliseconds: 500), () {
                                  if (filtered.isEmpty && !isSyncing) {
                                    syncFreshModels(query: val);
                                  }
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.38),
                            child: filtered.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('No models match your search locally.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                                          const SizedBox(height: 8),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF4F46E5),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                            ),
                                            icon: isSyncing
                                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                                : const Icon(Icons.cloud_sync_outlined, size: 16),
                                            label: Text(isSyncing ? 'Syncing...' : 'Sync Models from Server'),
                                            onPressed: isSyncing ? null : () => syncFreshModels(query: filter),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                    itemBuilder: (c, idx) {
                                      final p = filtered[idx];
                                      return ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        title: Text(
                                          p.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        subtitle: Text(
                                          '${p.brand} • ${p.model}',
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                        ),
                                        trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
                                        onTap: () {
                                          dialogWsSub?.cancel();
                                          debounceTimer?.cancel();
                                          Navigator.pop(ctx, p);
                                        },
                                      );
                                    },
                                  ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx, null),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Cancel & Skip Serial'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Prompt user to select unit type (Indoor/Outdoor) for dual serial models
  Future<String?> _showSelectUnitTypeDialog(String serial, Product product) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.device_hub_outlined, color: Color(0xFF7C3AED), size: 22),
            SizedBox(width: 8),
            Text('Dual-Serial Unit Type', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Model: ${product.brand} ${product.model}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text('Serial: $serial', style: const TextStyle(fontFamily: 'monospace', color: Color(0xFF64748B), fontSize: 12)),
            const SizedBox(height: 12),
            const Text('Is this unit Indoor or Outdoor?', style: TextStyle(fontSize: 13, color: Color(0xFF334155))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3C3489),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.home_outlined, size: 16),
            label: const Text('Indoor'),
            onPressed: () => Navigator.pop(ctx, 'indoor'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.wb_sunny_outlined, size: 16),
            label: const Text('Outdoor'),
            onPressed: () => Navigator.pop(ctx, 'outdoor'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showReturnNoticeDialog(String serial, String message) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Color(0xFFD97706), size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Return Confirmation',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Text(
                message,
                style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF92400E)),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Accepting this unit will add it to godown stock as Available.',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          Focus(
            canRequestFocus: false,
            descendantsAreFocusable: false,
            skipTraversal: true,
            child: TextButton(
              focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
          ),
          Focus(
            canRequestFocus: false,
            descendantsAreFocusable: false,
            skipTraversal: true,
            child: ElevatedButton(
              focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Accept & Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  void _showWarningDialog(String title, String message, {Duration autoDismissDuration = const Duration(seconds: 3)}) {
    _dismissWarningDialog();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        _warningDialogContext = ctx;
        _warningDialogTimer?.cancel();
        _warningDialogTimer = Timer(autoDismissDuration, () {
          if (_warningDialogContext != null && ctx.mounted) {
            try {
              Navigator.of(ctx).pop();
            } catch (_) {}
            _warningDialogContext = null;
          }
        });

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, size: 13, color: Color(0xFF64748B)),
                    SizedBox(width: 4),
                    Text(
                      'Auto-closing in 3s (or scan next serial)',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
              onPressed: () => _dismissWarningDialog(),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    ).then((_) {
      _warningDialogTimer?.cancel();
      _warningDialogTimer = null;
      _warningDialogContext = null;
    });
  }

  void _onPressSaveInward() {
    if (_scannedItems.isEmpty) return;

    // Dual-serial balance validation for every model present in this batch
    final Map<String, List<InwardScannedItem>> byProduct = {};
    for (final item in _scannedItems) {
      byProduct.putIfAbsent(item.product.id, () => []).add(item);
    }

    for (final entry in byProduct.entries) {
      final p = entry.value.first.product;
      if (p.hasDualSerial) {
        final indoorCount = entry.value.where((it) => it.unitType == 'indoor').length;
        final outdoorCount = entry.value.where((it) => it.unitType == 'outdoor').length;
        if (indoorCount != outdoorCount) {
          HapticFeedback.heavyImpact();
          _showWarningDialog(
            'Count Mismatch: Cannot Store',
            'Dual-serial model "${p.brand} ${p.model}" requires equal numbers of Indoor and Outdoor units.\n\n'
            '• Indoor units: $indoorCount\n'
            '• Outdoor units: $outdoorCount\n\n'
            '${indoorCount > outdoorCount ? "Please scan ${indoorCount - outdoorCount} more Outdoor unit(s)." : "Please scan ${outdoorCount - indoorCount} more Indoor unit(s)."}\n\n'
            'Batch cannot be saved until Indoor and Outdoor counts match.',
          );
          return;
        }
      }
    }

    _showInwardConfirmationDialog();
  }

  Future<void> _showInwardConfirmationDialog() async {
    final Map<String, List<InwardScannedItem>> byProduct = {};
    for (final item in _scannedItems) {
      byProduct.putIfAbsent(item.product.id, () => []).add(item);
    }

    final totalUnits = _scannedItems.length;

    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Confirm Batch',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, -1.0), // Pops out / drops down from the TOP (upside)
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: FadeTransition(
            opacity: anim,
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, anim1, anim2) => SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              elevation: 16,
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: _getInwardTypeBgColor(_inwardType),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(_getInwardTypeIcon(_inwardType), color: _getInwardTypeColor(_inwardType), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Confirm ${_getInwardTypeShort(_inwardType)} Batch',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                'Review the batch summary ($totalUnits units) before saving',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.pop(ctx, false),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close, color: Color(0xFF94A3B8), size: 20),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Models breakdown list
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MODELS IN THIS BATCH',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 8),
                          ...byProduct.entries.map((entry) {
                            final p = entry.value.first.product;
                            final count = entry.value.length;
                            final isDual = p.hasDualSerial;
                            final indoor = isDual ? entry.value.where((it) => it.unitType == 'indoor').length : 0;
                            final outdoor = isDual ? entry.value.where((it) => it.unitType == 'outdoor').length : 0;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                        ),
                                        Text(
                                          '${p.brand} • ${p.model}',
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                        ),
                                        if (isDual)
                                          Text(
                                            '($indoor Indoor, $outdoor Outdoor)',
                                            style: const TextStyle(fontSize: 10, color: Color(0xFF7C3AED), fontWeight: FontWeight.w600),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _getInwardTypeBgColor(_inwardType),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isDual ? '${count ~/ 2} Sets' : '$count Units',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _getInwardTypeColor(_inwardType)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const Divider(height: 16),
                          // Stock effect note
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _getInwardTypeBgColor(_inwardType).withOpacity(0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _inwardType == 'damaged'
                                  ? '⚠️ Stored as Damaged stock. Does NOT increase saleable inventory.'
                                  : _inwardType == 'return'
                                      ? '✓ Restores units to godown stock & frees serials for future dispatch.'
                                      : '✓ Adds new factory units directly into saleable godown stock.',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _getInwardTypeColor(_inwardType),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _remarksController,
                      decoration: InputDecoration(
                        labelText: 'Batch Remarks (Optional)',
                        hintText: _inwardType == 'damaged'
                            ? 'e.g. Reason for damage...'
                            : _inwardType == 'return'
                                ? 'e.g. Return reason or shop name...'
                                : 'e.g. Supplier invoice reference...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _getInwardTypeColor(_inwardType), width: 1.5)),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 46,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF475569),
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 46,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _getInwardTypeColor(_inwardType),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(
                                _inwardType == 'damaged'
                                    ? 'Confirm Damaged Batch'
                                    : _inwardType == 'return'
                                        ? 'Confirm Return Batch'
                                        : 'Confirm & Save Inward',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      _submitInwardBatch();
    }
  }

  Future<void> _submitInwardBatch() async {
    if (_scannedItems.isEmpty) return;

    setState(() => _submitting = true);
    _inwardRequestId ??= const Uuid().v4();

    // Group items by product_id
    final Map<String, List<InwardScannedItem>> byProduct = {};
    for (final item in _scannedItems) {
      byProduct.putIfAbsent(item.product.id, () => []).add(item);
    }

    final multiBatchItems = byProduct.entries.map((entry) {
      final prodId = entry.key;
      final list = entry.value;
      final serials = list.map((e) => e.serialNumber).toList();
      final unitTypes = <String, String>{};
      for (final e in list) {
        if (e.unitType != null) {
          unitTypes[e.serialNumber] = e.unitType!;
        }
      }
      return {
        'product_id': prodId,
        'inward_type': _inwardType,
        'serials': serials,
        'unit_types': unitTypes.isNotEmpty ? unitTypes : null,
      };
    }).toList();

    try {
      final remarks = _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim();
      final result = await _api.submitInwardMultiBatch(
        items: multiBatchItems,
        remarks: remarks,
        clientRequestId: _inwardRequestId,
      );

      _inwardRequestId = null;

      if (!mounted) return;
      setState(() => _submitting = false);

      final totalUnits = result['total_units'] ?? _scannedItems.length;
      final String successTitle = _inwardType == 'damaged'
          ? 'Damaged Units Recorded!'
          : _inwardType == 'return'
              ? 'Return Processed!'
              : 'Inward Recorded!';
      final String successMsg = _inwardType == 'damaged'
          ? 'Successfully marked $totalUnits unit(s) as Damaged stock.'
          : _inwardType == 'return'
              ? 'Successfully processed $totalUnits returned unit(s). They are restored to godown stock.'
              : 'Successfully registered $totalUnits unit(s) into godown inventory.';

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: _getInwardTypeColor(_inwardType)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  successTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(
            successMsg,
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _getInwardTypeColor(_inwardType)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (mounted) {
        setState(() {
          _scannedItems.clear();
          _scannedSerialSet.clear();
          _sequenceCounter = 1;
          _scanQueue.clear();
          _isProcessingQueue = false;
        });
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);

      final errorStr = e.toString().replaceAll("Exception: ", "");

      // Check if a specific serial has conflicted
      final serialMatch = RegExp(r"Serial '([^']+)'").firstMatch(errorStr);
      final conflictedSerial = serialMatch?.group(1);

      if (conflictedSerial != null && _scannedItems.any((it) => it.serialNumber == conflictedSerial)) {
        final removeAndRetry = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
                SizedBox(width: 8),
                Text('Serial Conflict'),
              ],
            ),
            content: Text(
              'Serial \'$conflictedSerial\' is already registered.\n\nWould you like to remove this serial and retry storing the remaining items?',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep & Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Remove $conflictedSerial & Retry', style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );

        if (removeAndRetry == true) {
          setState(() {
            _scannedItems.removeWhere((it) => it.serialNumber == conflictedSerial);
          });
          _submitInwardBatch();
          return;
        }
      }

      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Inward Problem'),
          content: Text(
            'Submission failed:\n$errorStr\n\nYou can retry the batch, store it in the Offline Queue, or cancel.',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'retry'),
              child: const Text('Retry Now'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
              onPressed: () => Navigator.pop(ctx, 'queue'),
              child: const Text('Queue Offline', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (action == 'retry') {
        _submitInwardBatch();
        return;
      }

      if (action == 'queue') {
        final batch = QueuedBatch(
          id: const Uuid().v4(),
          type: QueueType.inward,
          createdAt: DateTime.now(),
          payload: {
            'items': multiBatchItems,
            'remarks': _remarksController.text.trim(),
          },
          description: '${_getInwardTypeTitle(_inwardType)}: ${_scannedItems.length} units',
        );
        await _queue.enqueue(batch);
        _inwardRequestId = null;
        if (!mounted) return;
        TopToast.show(
          context,
          message: '✓ Inward batch saved to Offline Queue!',
          backgroundColor: const Color(0xFF2563EB),
          icon: Icons.cloud_done_rounded,
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final now = DateTime.now();
        // If a barcode scan occurred within the last 2000ms, swallow the pop request
        if (_lastScanTime != null && now.difference(_lastScanTime!).inMilliseconds < 2000) {
          debugPrint('[InwardScreen] Swallowed pop attempt from scanner keys');
          return;
        }
        final canPop = await _handleWillPop();
        if (canPop && mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: const Color(0xFF0F172A),
          leading: Focus(
            canRequestFocus: false,
            descendantsAreFocusable: false,
            skipTraversal: true,
            child: IconButton(
              focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
              icon: const Icon(Icons.arrow_back),
              onPressed: () async {
                final canPop = await _handleWillPop();
                if (canPop && mounted) {
                  Navigator.pop(context);
                }
              },
            ),
          ),
          title: Text(_getAppBarTitle(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          actions: [
            if (_stage == InwardStage.scanning) ...[
              if (_inwardType == 'stock_in')
                Focus(
                  canRequestFocus: false,
                  descendantsAreFocusable: false,
                  skipTraversal: true,
                  child: TextButton(
                    focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
                    onPressed: () => setState(() => _stage = InwardStage.selectModel),
                    child: const Text('Change Model', style: TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.bold)),
                  ),
                ),
              Focus(
                canRequestFocus: false,
                descendantsAreFocusable: false,
                skipTraversal: true,
                child: TextButton(
                  focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
                  onPressed: () async {
                    if (_scannedItems.isNotEmpty) {
                      final discard = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text('Switch Inward Mode?'),
                          content: Text(
                            'You have ${_scannedItems.length} scanned item(s). Switching mode will discard them.',
                            style: const TextStyle(fontSize: 13),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Switch & Discard', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                      if (discard != true) return;
                    }
                    setState(() {
                      _scannedItems.clear();
                      _stage = InwardStage.selectCase;
                    });
                  },
                  child: const Text('Switch Mode', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
        body: Column(
          children: [
            const OfflineBanner(),
            Expanded(child: _buildCurrentStageView()),
          ],
        ),
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_stage) {
      case InwardStage.selectCase:
        return 'Inward Stock Options';
      case InwardStage.selectModel:
        return 'Stock In: Select Model';
      case InwardStage.scanning:
        if (_inwardType == 'stock_in') {
          return 'Stock In: ${_selectedProduct?.model ?? ''}';
        } else if (_inwardType == 'return') {
          return 'Returned Product Scan';
        } else {
          return 'Damaged Product Scan';
        }
    }
  }

  Widget _buildCurrentStageView() {
    switch (_stage) {
      case InwardStage.selectCase:
        return _buildCaseSelector();
      case InwardStage.selectModel:
        return _buildModelSelector();
      case InwardStage.scanning:
        return _buildScanningView();
    }
  }

  // STAGE 1: The 3 Primary Options Screen
  Widget _buildCaseSelector() {
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      skipTraversal: true,
      child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text(
            'SELECT INWARD CASE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 14),

          // Option 1: Stock In (Direct from Company)
          _buildPrimaryCaseCard(
            caseType: 'stock_in',
            title: 'Stock In (Direct from Company)',
            badgeText: 'New Inventory',
            subtitle: 'Receive fresh inventory delivered by manufacturer. Select appliance model and scan serial numbers to register onto shelves.',
            icon: Icons.local_shipping_outlined,
            accentColor: const Color(0xFF4F46E5),
            bgColor: const Color(0xFFEEF2FF),
            flowTag: 'Model Selection ➔ Continuous Inward Scan',
          ),
          const SizedBox(height: 16),

          // Option 2: Returned Product
          _buildPrimaryCaseCard(
            caseType: 'return',
            title: 'Returned Product',
            badgeText: 'Return Intake',
            subtitle: 'Receive appliances returned by customers or shops. Scan serial numbers directly to verify units and restore to godown inventory.',
            icon: Icons.assignment_return_outlined,
            accentColor: const Color(0xFF059669),
            bgColor: const Color(0xFFECFDF5),
            flowTag: 'Direct Serial Scan ➔ Restores Available Stock',
          ),
          const SizedBox(height: 16),

          // Option 3: Damaged Product
          _buildPrimaryCaseCard(
            caseType: 'damaged',
            title: 'Damaged Product',
            badgeText: 'Quarantine',
            subtitle: 'Record damaged or defective appliances. Scan serial numbers directly to log and quarantine without increasing saleable stock.',
            icon: Icons.report_problem_outlined,
            accentColor: const Color(0xFFD97706),
            bgColor: const Color(0xFFFFFBEB),
            flowTag: 'Direct Serial Scan ➔ Quarantined to Damaged',
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildPrimaryCaseCard({
    required String caseType,
    required String title,
    required String badgeText,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color bgColor,
    required String flowTag,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: () => _selectInwardCase(caseType),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accentColor, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: accentColor.withOpacity(0.3)),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accentColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFF94A3B8)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.flash_on_rounded, size: 13, color: accentColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        flowTag,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accentColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // STAGE 2: Model Selector (Only used for Stock In mode)
  Widget _buildModelSelector() {
    if (_loadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _products.where((p) {
      final q = _productSearch.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.brand.toLowerCase().contains(q) ||
          p.model.toLowerCase().contains(q) ||
          (p.sku?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_scannedItems.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 20, color: Color(0xFF16A34A)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_scannedItems.length} unit(s) in batch. Selecting a model keeps all previous scans.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF14532D), fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _stage = InwardStage.scanning),
                    child: const Text('Resume Scan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFC7D2FE)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: Color(0xFF4F46E5)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Step 2: Select the appliance model being stocked in.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF3C3489), fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    if (_scannedItems.isNotEmpty && _selectedProduct != null) {
                      setState(() => _stage = InwardStage.scanning);
                    } else {
                      setState(() => _stage = InwardStage.selectCase);
                    }
                  },
                  child: Text(
                    _scannedItems.isNotEmpty ? 'Cancel' : 'Back',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search brand, model, or SKU...',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            onChanged: (val) => setState(() => _productSearch = val),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, idx) {
                final p = filtered[idx];
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () => _onModelSelectedForStockIn(p),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.inventory_2, color: Color(0xFF475569), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${p.brand} • ${p.model}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontFamily: 'monospace'),
                                ),
                                if (p.hasDualSerial) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3E8FF),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFFDDD6FE)),
                                    ),
                                    child: const Text(
                                      'Dual Serial (Indoor + Outdoor)',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF7C3AED),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${p.currentStockQty} ${p.unit}s',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: p.currentStockQty < 0 ? const Color(0xFFE11D48) : const Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                p.currentStockQty < 0 ? 'negative stock' : 'on shelves',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: p.currentStockQty < 0 ? const Color(0xFFE11D48) : const Color(0xFF94A3B8),
                                  fontWeight: p.currentStockQty < 0 ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // STAGE 3: Scanning & Batch Review View
  Widget _buildScanningView() {
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      skipTraversal: true,
      child: Column(
      children: [
        // Mode Banner
        _buildScanningHeader(),

        const Divider(height: 1, color: Color(0xFFE2E8F0)),

        // Dual serial toggle (only for stock_in with dual serial)
        if (_inwardType == 'stock_in' && _selectedProduct != null && _selectedProduct!.hasDualSerial)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _inwardUnitType = 'indoor'),
                    borderRadius: BorderRadius.circular(9),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _inwardUnitType == 'indoor' ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: _inwardUnitType == 'indoor'
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.home_outlined,
                            size: 16,
                            color: _inwardUnitType == 'indoor' ? const Color(0xFF3C3489) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Indoor Unit',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _inwardUnitType == 'indoor' ? FontWeight.bold : FontWeight.w500,
                              color: _inwardUnitType == 'indoor' ? const Color(0xFF3C3489) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _inwardUnitType = 'outdoor'),
                    borderRadius: BorderRadius.circular(9),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _inwardUnitType == 'outdoor' ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: _inwardUnitType == 'outdoor'
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.wb_sunny_outlined,
                            size: 16,
                            color: _inwardUnitType == 'outdoor' ? const Color(0xFF0D9488) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Outdoor Unit',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _inwardUnitType == 'outdoor' ? FontWeight.bold : FontWeight.w500,
                              color: _inwardUnitType == 'outdoor' ? const Color(0xFF0D9488) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Big Scan Barcode Action
        Padding(
          padding: EdgeInsets.fromLTRB(
            context.isTablet ? 28 : 16,
            context.isTablet ? 22 : 16,
            context.isTablet ? 28 : 16,
            context.isTablet ? 12 : 8,
          ),
          child: Column(
            children: [
              Focus(
                canRequestFocus: false,
                descendantsAreFocusable: false,
                skipTraversal: true,
                child: SizedBox(
                  width: double.infinity,
                  height: context.isTablet ? 64 : 52,
                  child: ElevatedButton.icon(
                    focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E1B4B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(context.isTablet ? 18 : 14),
                      ),
                      elevation: 1,
                    ),
                    icon: Icon(Icons.qr_code_scanner, size: context.isTablet ? 26 : 22),
                    label: Text(
                      _inwardType == 'stock_in'
                          ? 'Scan Barcode (${_selectedProduct?.model ?? ''})'
                          : 'Open Barcode Scanner (${_getInwardTypeShort(_inwardType)})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: context.isTablet ? 16 : 14,
                      ),
                    ),
                    onPressed: _openScanner,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Real-time scan feedback banner
        if (_lastScanFeedback != null)
          Container(
            width: double.infinity,
            margin: EdgeInsets.symmetric(horizontal: context.isTablet ? 28 : 16, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Text(
              _lastScanFeedback!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF065F46),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

        // Scanned list header
        if (_scannedItems.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.isTablet ? 28 : 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scanned Units (${_scannedItems.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569)),
                      ),
                      Text(
                        'Newest (#${_scannedItems.isNotEmpty ? _scannedItems.first.sequenceNumber : 0}) at top • #1 at bottom',
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                if (_scannedItems.length >= 6) ...[
                  // Jump to Serial #1 (at bottom)
                  InkWell(
                    onTap: _jumpToBottom,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_downward, size: 12, color: Color(0xFF1D4ED8)),
                          SizedBox(width: 2),
                          Text('#1 Bottom', style: TextStyle(fontSize: 10.5, color: Color(0xFF1D4ED8), fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Jump to top (newest)
                  InkWell(
                    onTap: _jumpToTop,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_upward, size: 12, color: Color(0xFF475569)),
                          SizedBox(width: 2),
                          Text('Top', style: TextStyle(fontSize: 10.5, color: Color(0xFF475569), fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

        // Scanned Items List
        Expanded(
          child: _scannedItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.barcode_reader, size: 56, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      const Text(
                        'No serials scanned yet.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _inwardType == 'stock_in'
                            ? 'Tap the button above to scan ${_selectedProduct?.model ?? 'appliances'}.'
                            : 'Scan appliance serial barcode to register units into this batch.',
                        style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  key: const PageStorageKey('inward_scanned_list'),
                  controller: _scrollController,
                  cacheExtent: 250.0,
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: EdgeInsets.symmetric(horizontal: context.isTablet ? 28 : 16),
                  itemCount: _scannedItems.length,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  itemBuilder: (ctx, idx) {
                    final item = _scannedItems[idx];
                    return RepaintBoundary(
                      key: ValueKey(item.serialNumber),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '#${item.sequenceNumber}',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.serialNumber,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Color(0xFF0F172A),
                                      letterSpacing: 0.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${item.product.brand} • ${item.product.model}',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (item.unitType != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: item.unitType == 'indoor' ? const Color(0xFFEEF2FF) : const Color(0xFFF0FDFA),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: item.unitType == 'indoor' ? const Color(0xFFC7D2FE) : const Color(0xFF99F6E4),
                                  ),
                                ),
                                child: Text(
                                  item.unitType == 'indoor' ? 'Indoor' : 'Outdoor',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: item.unitType == 'indoor' ? const Color(0xFF3C3489) : const Color(0xFF0D9488),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _scannedSerialSet.remove(item.serialNumber);
                                  _scannedItems.removeAt(idx);
                                });
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.close, size: 18, color: Color(0xFF94A3B8)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Bottom submit section
        if (_scannedItems.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _getInwardTypeColor(_inwardType),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: _submitting ? null : _onPressSaveInward,
                  child: _submitting
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : Text(
                          _inwardType == 'damaged'
                              ? 'Save Damaged Batch (${_scannedItems.length} Units)'
                              : _inwardType == 'return'
                                  ? 'Save Returned Batch (+${_scannedItems.length} Stock)'
                                  : 'Save Inward Batch (+${_scannedItems.length} Stock)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                ),
              ),
            ),
          ),
      ],
    ),
    );
  }

  Widget _buildScanningHeader() {
    if (_inwardType == 'stock_in' && _selectedProduct != null) {
      final p = _selectedProduct!;
      final distinctModels = _scannedItems.map((e) => e.product.id).toSet().length;
      return Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFC7D2FE)),
                        ),
                        child: const Text(
                          'Active',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${p.brand} • Model: ${p.model}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _getInwardTypeBgColor(_inwardType),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _getInwardTypeColor(_inwardType).withOpacity(0.3)),
              ),
              child: Text(
                distinctModels > 1
                    ? '${_scannedItems.length} Scanned ($distinctModels models)'
                    : '${_scannedItems.length} Scanned',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _getInwardTypeColor(_inwardType)),
              ),
            ),
          ],
        ),
      );
    } else {
      // Returned Product or Damaged Product Header
      return Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _getInwardTypeBgColor(_inwardType),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_getInwardTypeIcon(_inwardType), color: _getInwardTypeColor(_inwardType), size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getInwardTypeTitle(_inwardType),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _inwardType == 'return'
                            ? 'Customer & Shop Return Verification'
                            : 'Damaged & Defective Stock Quarantine',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getInwardTypeBgColor(_inwardType),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _getInwardTypeColor(_inwardType).withOpacity(0.3)),
                  ),
                  child: Text(
                    '${_scannedItems.length} Scanned',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _getInwardTypeColor(_inwardType)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
  }
}
