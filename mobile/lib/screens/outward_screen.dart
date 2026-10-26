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
import 'print_bill_screen.dart';

class OutwardScreen extends StatefulWidget {
  const OutwardScreen({super.key});

  @override
  State<OutwardScreen> createState() => _OutwardScreenState();
}

class _OutwardScreenState extends State<OutwardScreen> {
  final ApiService _api = ApiService();
  final OfflineQueueService _queue = OfflineQueueService();
  StreamSubscription? _wsSubscription;
  VoidCallback? _scannerSub;

  // Wizard steps: 1 = Shop, 2 = Model & Ref, 3 = Scanning & Review
  int _currentStep = 1;

  // Selections
  List<Shop> _shops = [];
  Shop? _selectedShop;
  String _shopSearch = '';
  bool _loadingShops = true;

  List<Product> _products = [];
  Product? _selectedProduct;
  String _productSearch = '';
  bool _loadingProducts = true;

  final TextEditingController _billNumberController = TextEditingController();
  final TextEditingController _deliveryRefController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();
  String? _deliveryRefWarning;

  // Scanned lines
  final List<OutwardScanResult> _scannedItems = [];
  final Set<String> _scannedSerialSet = <String>{};
  int _sequenceCounter = 1;
  final List<String> _scanQueue = [];
  bool _isProcessingQueue = false;
  String _activeFilterModelId = 'ALL';
  String _outwardUnitType = 'indoor';
  bool _submitting = false;
  final Set<String> _inFlightSerials = <String>{};
  String? _dispatchRequestId;
  DateTime? _lastScanTime;
  String? _lastScanFeedback;

  BuildContext? _alertContext;
  Timer? _alertTimer;

  void _dismissSimpleAlert() {
    _alertTimer?.cancel();
    _alertTimer = null;
    if (_alertContext != null && _alertContext!.mounted) {
      try {
        Navigator.of(_alertContext!).pop();
      } catch (_) {}
    }
    _alertContext = null;
  }

  final ScrollController _scanListScrollController = ScrollController();

  void _jumpToTop() {
    if (_scanListScrollController.hasClients) {
      _scanListScrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _jumpToBottom() {
    if (_scanListScrollController.hasClients) {
      _scanListScrollController.animateTo(
        _scanListScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // Instant 0ms render from cache
    final cachedProds = _api.cachedProducts;
    final cachedShops = _api.cachedShops;
    if (cachedProds != null && cachedProds.isNotEmpty) {
      _products = List<Product>.from(cachedProds);
      _loadingProducts = false;
    }
    if (cachedShops != null && cachedShops.isNotEmpty) {
      _shops = List<Shop>.from(cachedShops);
      _loadingShops = false;
    }
    _loadMetadata();
    _initWebSocket();

    // Hardware barcode scanner support
    _scannerSub = HardwareScannerService().registerListener((barcode) {
      if (!mounted) return;

      // If duplicate/alert dialog is currently showing, dismiss immediately on next scan!
      final bool wasAlertShowing = _alertContext != null;
      if (wasAlertShowing) {
        _dismissSimpleAlert();
      }

      if (!wasAlertShowing && ModalRoute.of(context)?.isCurrent != true) return;
      _lastScanTime = DateTime.now();
      if (FocusScope.of(context).hasFocus) {
        FocusScope.of(context).unfocus();
      }
      if (_selectedShop == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a destination shop first to dispatch serials.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (_selectedProduct == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a product model first to dispatch serials.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      _handleOutwardScan(barcode);
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
            _loadMetadata(forceRefresh: true);
          }
        } else {
          _loadMetadata(forceRefresh: true);
        }
      } else if (type == 'shop_created' && data is Map<String, dynamic>) {
        try {
          final newShop = Shop.fromJson(data);
          if (newShop.isActive) {
            setState(() {
              _shops.removeWhere((s) => s.id == newShop.id);
              _shops.add(newShop);
              _shops.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            });
          }
        } catch (_) {}
      } else if (type == 'shop_updated' && data is Map<String, dynamic>) {
        try {
          final updatedShop = Shop.fromJson(data);
          setState(() {
            _shops.removeWhere((s) => s.id == updatedShop.id);
            if (updatedShop.isActive) {
              _shops.add(updatedShop);
              _shops.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
              if (_selectedShop?.id == updatedShop.id) {
                _selectedShop = updatedShop;
              }
            } else {
              // Shop deactivated
              if (_selectedShop?.id == updatedShop.id) {
                _selectedShop = null;
                if (_currentStep > 1) {
                  _currentStep = 1;
                }
              }
            }
          });
        } catch (_) {}
      } else if (type == 'shop_deleted' && data is Map<String, dynamic>) {
        if (data['bulk'] == true) {
          _loadMetadata(forceRefresh: true);
        } else {
          final id = data['id']?.toString();
          if (id != null) {
            setState(() {
              _shops.removeWhere((s) => s.id == id);
              if (_selectedShop?.id == id) {
                _selectedShop = null;
                if (_currentStep > 1) {
                  _currentStep = 1;
                }
              }
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _dismissSimpleAlert();
    _scannerSub?.call();
    _wsSubscription?.cancel();
    _scanListScrollController.dispose();
    _billNumberController.dispose();
    _deliveryRefController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadMetadata({bool forceRefresh = false}) async {
    try {
      final results = await Future.wait([
        _api.getShops(forceRefresh: forceRefresh),
        _api.getProducts(forceRefresh: forceRefresh),
      ]);
      if (mounted) {
        setState(() {
          _shops = results[0] as List<Shop>;
          _products = results[1] as List<Product>;
          if (_selectedProduct != null) {
            final refreshed = _products.firstWhere(
              (p) => p.id == _selectedProduct!.id,
              orElse: () => _selectedProduct!,
            );
            _selectedProduct = refreshed;
          }
          _loadingShops = false;
          _loadingProducts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingShops = false;
          _loadingProducts = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load metadata: $e')),
        );
      }
    }
  }

  Future<void> _checkReferenceDuplicate() async {
    final ref = _deliveryRefController.text.trim();
    if (ref.isEmpty || _selectedShop == null) {
      setState(() => _deliveryRefWarning = null);
      return;
    }

    try {
      final res = await _api.checkDeliveryReference(_selectedShop!.id, ref);
      if (mounted) {
        setState(() {
          _deliveryRefWarning = res['is_duplicate_today'] == true ? res['warning_message'] : null;
        });
      }
    } catch (_) {}
  }

  void _openContinuousScanner() {
    if (_selectedProduct == null || _selectedShop == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerWidget(
          title: 'Dispatch: ${_selectedShop!.name}',
          prompt: 'Scanning: ${_selectedProduct!.brand} ${_selectedProduct!.model}',
          initialLastScanned: _scannedItems.isNotEmpty ? _scannedItems.first.serialNumber : null,
          initialCount: _scannedItems.length,
          itemCountProvider: () => _scannedItems.length,
          existingSerials: _scannedSerialSet,
          isDuplicate: (s) =>
              _scannedSerialSet.contains(s.trim().toUpperCase()) ||
              _scanQueue.contains(s.trim().toUpperCase()) ||
              _inFlightSerials.contains(s.trim().toUpperCase()),
          onScanned: (serial) => _handleOutwardScan(serial),
        ),
      ),
    );
  }

  void _handleOutwardScan(String serial) {
    _dismissSimpleAlert();
    final cleanSerial = serial.trim().toUpperCase();
    if (cleanSerial.isEmpty) return;
    _lastScanTime = DateTime.now();

    // 1. Instant synchronous check in O(1): Reject immediately if already in batch OR currently in FIFO queue
    if (_scannedSerialSet.contains(cleanSerial) ||
        _scanQueue.contains(cleanSerial) ||
        _scannedItems.any((item) => item.serialNumber == cleanSerial)) {
      HapticFeedback.heavyImpact();
      SoundService().playErrorSound();
      _showToast('Duplicate: Serial "$cleanSerial" already in batch', const Color(0xFFE11D48));
      _showSimpleAlert('Duplicate Serial', 'Serial "$cleanSerial" is already in this dispatch batch.');
      return;
    }

    _scanQueue.add(cleanSerial);

    if (!_isProcessingQueue) {
      _processOutwardScanQueue();
    }
  }

  Future<void> _processOutwardScanQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_scanQueue.isNotEmpty && mounted) {
      final cleanSerial = _scanQueue.removeAt(0);
      try {
        await _processSingleOutwardSerial(cleanSerial);
      } catch (e) {
        debugPrint('[OutwardScreen] Error processing outward serial $cleanSerial: $e');
      }
    }

    _isProcessingQueue = false;
  }

  Future<void> _processSingleOutwardSerial(String cleanSerial) async {
    if (_scannedSerialSet.contains(cleanSerial) ||
        _scannedItems.any((item) => item.serialNumber == cleanSerial)) {
      return;
    }
    _inFlightSerials.add(cleanSerial);

    try {
      final res = await _api.checkOutwardSerial(_selectedProduct!.id, cleanSerial);
      final bool isBlocked = res['is_blocked'] == true ||
          res['is_dispatched'] == true ||
          res['can_dispatch'] == false ||
          res['case'] == 0 ||
          res['badge'] == 'blocked';
      final String? msg = res['message'];

      // --- CRITICAL BLOCK: ALREADY DISPATCHED CAN NEVER BE SCANNED ---
      if (isBlocked) {
        HapticFeedback.heavyImpact();
        SoundService().playErrorSound();
        await _showAlreadyDispatchedDialog(
          cleanSerial,
          msg ?? 'Serial "$cleanSerial" has already been dispatched. Dispatched serials can NEVER be scanned or dispatched again.',
        );
        return; // NEVER ADD TO LIST!
      }

      // --- CRITICAL BLOCK: DAMAGED PRODUCT WARNING ---
      final bool isDamaged = res['is_damaged'] == true ||
          (res['current_status'] ?? '').toString().toLowerCase() == 'damaged' ||
          (res['message'] ?? '').toString().toLowerCase().contains('damaged');

      if (isDamaged) {
        HapticFeedback.heavyImpact();
        final proceed = await _showCase3StatusWarningDialog(
          cleanSerial,
          'This item is damaged. Are you sure you want to add?',
          isDamaged: true,
        );
        if (proceed != true) {
          return; // DO NOT ADD TO LIST!
        }
      }

      final dynamic caseVal = res['case'];
      final String caseName = (res['case_name'] ?? '').toString();
      final bool isMatched = res['is_matched'] == true || caseVal == 1 || caseName == 'matched';
      final serialDetail = res['serial'];

      // --- CASE 1: MATCHED (Tracked & Available for current model) ---
      if (caseVal == 1 || caseName == 'matched') {
        // Enforce dual serial unit type match for matched serial numbers
        if (_selectedProduct?.hasDualSerial == true) {
          final String? registeredUnitType = (res['unit_type'] as String?)?.toLowerCase();
          if (registeredUnitType != null &&
              registeredUnitType.isNotEmpty &&
              registeredUnitType != _outwardUnitType.toLowerCase()) {
            HapticFeedback.heavyImpact();
            await _showUnitTypeMismatchDialog(
              cleanSerial: cleanSerial,
              actualUnitType: registeredUnitType,
              selectedUnitType: _outwardUnitType,
            );
            return; // DO NOT ADD TO LIST!
          }
        }

        HapticFeedback.lightImpact();
        final unitType = (res['unit_type'] as String?) ?? (_selectedProduct?.hasDualSerial == true ? _outwardUnitType : null);
        if (!_scannedItems.any((item) => item.serialNumber == cleanSerial)) {
          final seq = _sequenceCounter++;
          _scannedSerialSet.add(cleanSerial);
          setState(() {
            _scannedItems.insert(
              0,
              OutwardScanResult(
                serialNumber: cleanSerial,
                product: _selectedProduct,
                caseType: isDamaged ? OutwardCase.statusWarning : OutwardCase.matched,
                isMatched: true,
                isFlaggedForReview: isDamaged,
                warningMessage: isDamaged ? 'Damaged item added after confirmation.' : msg,
                unitType: unitType,
                sequenceNumber: seq,
              ),
            );
            _lastScanFeedback = '✓ Scanned #$seq: $cleanSerial • ${_selectedProduct!.brand} ${_selectedProduct!.model}';
          });
        }
      }

      // --- CASE 2: RECORDED ONLY (Unmatched pre-go-live stock) ---
      else if (caseVal == 2 || caseName == 'unmatched') {
        HapticFeedback.lightImpact();
        final unitType = _selectedProduct?.hasDualSerial == true ? _outwardUnitType : null;
        if (!_scannedItems.any((item) => item.serialNumber == cleanSerial)) {
          final seq = _sequenceCounter++;
          _scannedSerialSet.add(cleanSerial);
          setState(() {
            _scannedItems.insert(
              0,
              OutwardScanResult(
                serialNumber: cleanSerial,
                product: _selectedProduct,
                caseType: OutwardCase.recordedOnly,
                isMatched: false,
                warningMessage: 'Old pre-go-live stock recorded. Never blocked.',
                unitType: unitType,
                sequenceNumber: seq,
              ),
            );
            _lastScanFeedback = '✓ Scanned #$seq (Old Stock): $cleanSerial • ${_selectedProduct!.brand} ${_selectedProduct!.model}';
          });
        }
      }

      // --- CASE 3: STATUS WARNING (Damaged, reserved, etc. NOT dispatched!) ---
      else if (caseVal == 3 || caseName == 'status_warning') {
        // Enforce dual serial unit type match for matched serial numbers
        if (_selectedProduct?.hasDualSerial == true) {
          final String? registeredUnitType = (res['unit_type'] as String?)?.toLowerCase();
          if (registeredUnitType != null &&
              registeredUnitType.isNotEmpty &&
              registeredUnitType != _outwardUnitType.toLowerCase()) {
            HapticFeedback.heavyImpact();
            await _showUnitTypeMismatchDialog(
              cleanSerial: cleanSerial,
              actualUnitType: registeredUnitType,
              selectedUnitType: _outwardUnitType,
            );
            return; // DO NOT ADD TO LIST!
          }
        }

        bool proceed = true;
        if (!isDamaged) {
          HapticFeedback.heavyImpact();
          final resProceed = await _showCase3StatusWarningDialog(
            cleanSerial,
            msg ?? 'Unit is not currently marked available.',
            isDamaged: false,
          );
          proceed = (resProceed == true);
        }

        if (proceed) {
          final unitType = (res['unit_type'] as String?) ?? (_selectedProduct?.hasDualSerial == true ? _outwardUnitType : null);
          final seq = _sequenceCounter++;
          _scannedSerialSet.add(cleanSerial);
          setState(() {
            _scannedItems.insert(
              0,
              OutwardScanResult(
                serialNumber: cleanSerial,
                product: _selectedProduct,
                caseType: OutwardCase.statusWarning,
                isMatched: isMatched,
                isFlaggedForReview: true,
                warningMessage: isDamaged ? 'Damaged item added after confirmation.' : msg,
                unitType: unitType,
                sequenceNumber: seq,
              ),
            );
          });
          _showToast(
            'Added $cleanSerial (${_selectedProduct!.model})${isDamaged ? " • DAMAGED" : ""}',
            const Color(0xFFD97706),
          );
        }
      }

      // --- CASE 4: MODEL MISMATCH (Serial is registered under another model in this godown) ---
      else if (caseVal == 4 || caseName == 'model_mismatch') {
        HapticFeedback.heavyImpact();
        final regProdId = res['registered_product_id']?.toString();
        Product? matchedProd;
        if (regProdId != null) {
          try {
            matchedProd = _products.firstWhere(
              (p) => p.id.toLowerCase() == regProdId.toLowerCase(),
            );
          } catch (_) {
            try {
              matchedProd = OfflineManager().products.firstWhere(
                (p) => p.id.toLowerCase() == regProdId.toLowerCase(),
              );
            } catch (_) {}
          }
        }
        final existingModel = res['registered_model_name'] ?? serialDetail?['product_name'] ?? 'another model';

        if (matchedProd != null) {
          final dialogResult = await _showDifferentModelDialog(
            cleanSerial,
            matchedProd,
            initialUnitType: res['unit_type']?.toString(),
            isDamaged: isDamaged,
          );
          if (dialogResult != null && dialogResult['action'] == 'add') {
            final String? chosenUnitType = dialogResult['unit_type'];
            if (!_scannedItems.any((item) => item.serialNumber == cleanSerial)) {
              final seq = _sequenceCounter++;
              _scannedSerialSet.add(cleanSerial);
              setState(() {
                _scannedItems.insert(
                  0,
                  OutwardScanResult(
                    serialNumber: cleanSerial,
                    product: matchedProd,
                    caseType: isDamaged ? OutwardCase.statusWarning : OutwardCase.matched,
                    isMatched: true,
                    isFlaggedForReview: isDamaged,
                    warningMessage: isDamaged ? 'Damaged item added after confirmation.' : null,
                    unitType: chosenUnitType,
                    sequenceNumber: seq,
                  ),
                );
                // Switch active model to matchedProd so staff can see and scan the matching unit!
                _selectedProduct = matchedProd;
                _activeFilterModelId = matchedProd!.id;
                if (matchedProd.hasDualSerial && chosenUnitType != null) {
                  // Auto-toggle to the companion unit so the next scan is ready for the other unit!
                  _outwardUnitType = (chosenUnitType == 'indoor') ? 'outdoor' : 'indoor';
                }
              });
              _showToast(
                'Added $cleanSerial (${matchedProd.model})${isDamaged ? " • DAMAGED" : ""}${matchedProd.hasDualSerial ? " • Next unit: ${_outwardUnitType.toUpperCase()}" : ""}',
                isDamaged ? const Color(0xFFD97706) : const Color(0xFF059669),
              );
            }
          }
        } else {
          await _showCase4ModelMismatchDialog(cleanSerial, existingModel, msg);
        }
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      _showSimpleAlert('Validation Error', 'Could not verify serial "$cleanSerial": $e');
    } finally {
      _inFlightSerials.remove(cleanSerial);
    }
  }

  Future<Map<String, dynamic>?> _showDifferentModelDialog(
    String serial,
    Product targetProd, {
    String? initialUnitType,
    bool isDamaged = false,
  }) {
    String selectedUnitType = initialUnitType ?? 'indoor';

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDual = targetProd.hasDualSerial;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            actionsPadding: const EdgeInsets.all(16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isDamaged ? const Color(0xFFFEF2F2) : const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isDamaged ? Icons.warning_amber_rounded : Icons.swap_horiz,
                    color: isDamaged ? const Color(0xFFDC2626) : const Color(0xFF4F46E5),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isDamaged ? 'Damaged Unit • Different Model' : 'Model Mismatch Detected',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDamaged) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFDC2626)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This item is marked as DAMAGED.',
                            style: TextStyle(
                              color: Color(0xFF991B1B),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Text(
                  'Scanned Serial:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[500]),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  serial,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Registered Under Model:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[500]),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.devices, size: 16, color: Color(0xFF4F46E5)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${targetProd.brand} • ${targetProd.model}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isDual)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3E8FF),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Dual Serial',
                                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF7C3AED)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        targetProd.name,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                if (isDual) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Select Unit Type for this barcode:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => selectedUnitType = 'indoor'),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: selectedUnitType == 'indoor' ? const Color(0xFFEEF2FF) : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selectedUnitType == 'indoor' ? const Color(0xFF6366F1) : const Color(0xFFCBD5E1),
                                width: selectedUnitType == 'indoor' ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.home_outlined,
                                  size: 15,
                                  color: selectedUnitType == 'indoor' ? const Color(0xFF4338CA) : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Indoor Unit',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: selectedUnitType == 'indoor' ? FontWeight.bold : FontWeight.w500,
                                    color: selectedUnitType == 'indoor' ? const Color(0xFF4338CA) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => selectedUnitType = 'outdoor'),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: selectedUnitType == 'outdoor' ? const Color(0xFFF0FDFA) : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selectedUnitType == 'outdoor' ? const Color(0xFF0D9488) : const Color(0xFFCBD5E1),
                                width: selectedUnitType == 'outdoor' ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.wb_sunny_outlined,
                                  size: 15,
                                  color: selectedUnitType == 'outdoor' ? const Color(0xFF0F766E) : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Outdoor Unit',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: selectedUnitType == 'outdoor' ? FontWeight.bold : FontWeight.w500,
                                    color: selectedUnitType == 'outdoor' ? const Color(0xFF0F766E) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Add this unit under this model to current dispatch?',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, {'action': 'cancel'}),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E1B4B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () => Navigator.pop(ctx, {
                  'action': 'add',
                  'unit_type': isDual ? selectedUnitType : null,
                  'switch_model': true,
                }),
                child: Text(
                  isDual ? 'Add & Switch Model' : 'Add to Dispatch',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showModelSwitchBottomSheet() {
    String sheetSearch = '';
    bool isSyncing = false;
    StreamSubscription? sheetWsSub;
    Timer? debounceTimer;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            sheetWsSub ??= WebSocketService().stream.listen((event) {
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
                    setSheetState(() {});
                  }
                } catch (_) {}
              }
            });

            Future<void> syncFreshModels({String? query}) async {
              setSheetState(() => isSyncing = true);
              try {
                final fresh = await _api.getProducts(forceRefresh: true);
                if (mounted) {
                  setState(() => _products = fresh);
                }
                if (ctx.mounted) {
                  setSheetState(() => isSyncing = false);
                }
              } catch (_) {
                if (ctx.mounted) {
                  setSheetState(() => isSyncing = false);
                }
              }
            }

            final filteredProds = _products.where((p) {
              final q = sheetSearch.toLowerCase();
              return p.name.toLowerCase().contains(q) ||
                  p.brand.toLowerCase().contains(q) ||
                  p.model.toLowerCase().contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.78,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.swap_horiz, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Switch / Add Model for this Shop',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Real-time Sync Button
                        IconButton(
                          tooltip: 'Sync Models from Server',
                          icon: isSyncing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F46E5)),
                                )
                              : const Icon(Icons.sync_rounded, color: Color(0xFF4F46E5)),
                          onPressed: isSyncing ? null : () => syncFreshModels(query: sheetSearch),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      autofocus: false,
                      decoration: InputDecoration(
                        hintText: 'Search brand or model (e.g. GXI 360)...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: isSyncing
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : (sheetSearch.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () => setSheetState(() => sheetSearch = ''),
                                  )
                                : null),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      onChanged: (val) {
                        setSheetState(() => sheetSearch = val);
                        if (val.trim().length >= 2) {
                          debounceTimer?.cancel();
                          debounceTimer = Timer(const Duration(milliseconds: 500), () {
                            if (filteredProds.isEmpty && !isSyncing) {
                              syncFreshModels(query: val);
                            }
                          });
                        }
                      },
                    ),
                  ),
                  Expanded(
                    child: filteredProds.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFF94A3B8)),
                                  const SizedBox(height: 12),
                                  Text(
                                    sheetSearch.isEmpty
                                        ? 'No models available'
                                        : 'No local match for "$sheetSearch"',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Color(0xFF1E293B),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'If this model was just added on the admin dashboard, tap below to sync immediately into this dispatch window.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF4F46E5),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: isSyncing
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.cloud_sync_outlined, size: 18),
                                    label: Text(isSyncing ? 'Syncing...' : 'Sync Models from Server'),
                                    onPressed: isSyncing ? null : () => syncFreshModels(query: sheetSearch),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () => syncFreshModels(query: sheetSearch),
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: filteredProds.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (c, i) {
                                final p = filteredProds[i];
                                final isSelected = p.id == _selectedProduct?.id;
                                final countInBatch = _scannedItems.where((e) => (e.product?.id ?? _selectedProduct!.id) == p.id).length;

                                return ListTile(
                                  tileColor: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0),
                                      width: isSelected ? 1.5 : 1.0,
                                    ),
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
                                    foregroundColor: isSelected ? Colors.white : const Color(0xFF475569),
                                    child: Icon(isSelected ? Icons.check : Icons.devices, size: 20),
                                  ),
                                  title: Text(
                                    p.name,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: Text(
                                    p.currentStockQty < 0
                                        ? '${p.brand} • ${p.model} (${p.currentStockQty} - Negative Stock)'
                                        : '${p.brand} • ${p.model} (${p.currentStockQty} on shelves)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: p.currentStockQty < 0 ? const Color(0xFFE11D48) : const Color(0xFF64748B),
                                      fontWeight: p.currentStockQty < 0 ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  trailing: countInBatch > 0
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '$countInBatch in dispatch',
                                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        )
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      _selectedProduct = p;
                                      _activeFilterModelId = 'ALL';
                                    });
                                    Navigator.pop(ctx);
                                    _showToast('Active model: ${p.brand} ${p.model}', const Color(0xFF4F46E5));
                                  },
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      sheetWsSub?.cancel();
      debounceTimer?.cancel();
    });
  }

  Future<void> _showUnitTypeMismatchDialog({
    required String cleanSerial,
    required String actualUnitType,
    required String selectedUnitType,
  }) {
    final isActualIndoor = actualUnitType.toLowerCase() == 'indoor';
    final actualTitle = isActualIndoor ? 'Indoor Unit' : 'Outdoor Unit';
    final selectedTitle = selectedUnitType.toLowerCase() == 'indoor' ? 'Indoor Unit' : 'Outdoor Unit';

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isActualIndoor ? Icons.home_outlined : Icons.wb_sunny_outlined,
              color: const Color(0xFFDC2626),
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'It is an $actualTitle!',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFDC2626),
                ),
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
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), height: 1.4),
                  children: [
                    const TextSpan(text: 'Serial '),
                    TextSpan(
                      text: cleanSerial,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                    const TextSpan(text: ' is registered in the system as an '),
                    TextSpan(
                      text: actualTitle.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isActualIndoor ? const Color(0xFF1D4ED8) : const Color(0xFF0D9488),
                      ),
                    ),
                    const TextSpan(text: '.\n\nYou have '),
                    TextSpan(
                      text: selectedTitle.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                    ),
                    const TextSpan(text: ' selected.\n\n'),
                    const TextSpan(
                      text: 'It was NOT added to dispatch!',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Please select $actualTitle in the scanner header if you wish to scan this unit.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3C3489),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: Icon(isActualIndoor ? Icons.home_outlined : Icons.wb_sunny_outlined, size: 16),
            label: Text('Switch to $actualTitle'),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _outwardUnitType = isActualIndoor ? 'indoor' : 'outdoor';
              });
              _showToast('Switched unit to $actualTitle.', const Color(0xFF3C3489));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showAlreadyDispatchedDialog(String serial, String message) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.block_rounded, color: Color(0xFFDC2626), size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Already Dispatched',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
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
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                message,
                style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B), fontWeight: FontWeight.w600, height: 1.4),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showToast(String message, Color bgColor) {
    if (!mounted) return;
    TopToast.show(
      context,
      message: message,
      backgroundColor: bgColor,
    );
  }

  void _showSimpleAlert(String title, String message, {Duration autoDismissDuration = const Duration(seconds: 3)}) {
    _dismissSimpleAlert();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        _alertContext = ctx;
        _alertTimer?.cancel();
        _alertTimer = Timer(autoDismissDuration, () {
          if (_alertContext != null && ctx.mounted) {
            try {
              Navigator.of(ctx).pop();
            } catch (_) {}
            _alertContext = null;
          }
        });

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
              onPressed: () => _dismissSimpleAlert(),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    ).then((_) {
      _alertTimer?.cancel();
      _alertTimer = null;
      _alertContext = null;
    });
  }

  Future<bool?> _showCase3StatusWarningDialog(
    String serial,
    String message, {
    bool isDamaged = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: isDamaged ? const Color(0xFFDC2626) : const Color(0xFFD97706),
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isDamaged ? 'Damaged Product' : 'Serial Status Warning',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDamaged ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDamaged ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Text(
                serial,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDamaged ? const Color(0xFF991B1B) : const Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              isDamaged ? 'This item is damaged. Are you sure you want to add?' : message,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF334155), height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDamaged ? const Color(0xFFFFF1F2) : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDamaged ? const Color(0xFFFECDD3) : const Color(0xFFFDE68A),
                ),
              ),
              child: Text(
                isDamaged
                    ? 'If you proceed, this dispatch will record the item as damaged for review.'
                    : 'If you proceed, this dispatch will be flagged for administrator review.',
                style: TextStyle(
                  fontSize: 11,
                  color: isDamaged ? const Color(0xFF9F1239) : const Color(0xFFB45309),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDamaged ? const Color(0xFFDC2626) : const Color(0xFFD97706),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isDamaged ? 'Yes, Add' : 'Dispatch Anyway (Flag)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCase4ModelMismatchDialog(String serial, String existingModel, String? msg) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cancel, color: Color(0xFFE11D48)),
            SizedBox(width: 8),
            Expanded(child: Text('Model Mismatch!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Text(
          msg ?? 'Serial "$serial" belongs to "$existingModel", but this active model is "${_selectedProduct!.name}".',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _onPressSubmitDispatch() {
    if (_selectedShop == null || _scannedItems.isEmpty) return;

    // Group items by product ID
    final Map<String, List<OutwardScanResult>> byProduct = {};
    for (final item in _scannedItems) {
      final pid = item.product?.id ?? _selectedProduct!.id;
      byProduct.putIfAbsent(pid, () => []).add(item);
    }

    // Strict validation: For every dual-serial model, indoor and outdoor counts must match!
    for (final entry in byProduct.entries) {
      final items = entry.value;
      final prod = items.first.product ?? _selectedProduct;
      if (prod != null && prod.hasDualSerial) {
        final indoorCount = items.where((e) => e.unitType == 'indoor').length;
        final outdoorCount = items.where((e) => e.unitType == 'outdoor').length;
        if (indoorCount != outdoorCount) {
          HapticFeedback.heavyImpact();
          _showSimpleAlert(
            'Count Mismatch: Cannot Dispatch',
            'Model "${prod.brand} ${prod.model}" requires equal numbers of Indoor and Outdoor units.\n\n'
            '• Indoor units: $indoorCount\n'
            '• Outdoor units: $outdoorCount\n\n'
            '${indoorCount > outdoorCount ? "Please scan ${indoorCount - outdoorCount} more Outdoor unit(s)." : "Please scan ${outdoorCount - indoorCount} more Indoor unit(s)."}\n\n'
            'Dispatch cannot proceed until counts match.',
          );
          return;
        }
      }
    }

    _showOutwardConfirmationDialog(byProduct);
  }

  Future<void> _showOutwardConfirmationDialog(Map<String, List<OutwardScanResult>> byProduct) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top drag indicator
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header Row
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(context.isTablet ? 12 : 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(context.isTablet ? 14 : 10),
                      ),
                      child: Icon(Icons.local_shipping_outlined, color: const Color(0xFF4F46E5), size: context.isTablet ? 28 : 22),
                    ),
                    SizedBox(width: context.isTablet ? 16 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Confirm Dispatch',
                            style: TextStyle(
                              fontSize: context.isTablet ? 22 : 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Review dispatch summary before submitting',
                            style: TextStyle(
                              fontSize: context.isTablet ? 13 : 11,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.pop(ctx, false),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close, color: const Color(0xFF94A3B8), size: context.isTablet ? 24 : 20),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: context.isTablet ? 20 : 16),

                // Destination Shop Card
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(context.isTablet ? 16 : 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(context.isTablet ? 16 : 12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/shop_icon.png',
                            width: context.isTablet ? 26 : 20,
                            height: context.isTablet ? 26 : 20,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                Icon(Icons.storefront, size: context.isTablet ? 22 : 18, color: const Color(0xFF4F46E5)),
                          ),
                          SizedBox(width: context.isTablet ? 10 : 8),
                          Expanded(
                            child: Text(
                              _selectedShop!.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: context.isTablet ? 17 : 14,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (_selectedShop!.city.trim().isNotEmpty)
                            Text(
                              'City: ${_selectedShop!.city.trim()}',
                              style: TextStyle(
                                fontSize: context.isTablet ? 14 : 12,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          if (_deliveryRefController.text.trim().isNotEmpty) ...[
                            const SizedBox(width: 12),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: context.isTablet ? 10 : 6,
                                vertical: context.isTablet ? 4 : 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Ref: ${_deliveryRefController.text.trim()}',
                                style: TextStyle(
                                  fontSize: context.isTablet ? 13 : 11,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF4338CA),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: context.isTablet ? 18 : 14),

                Text(
                  'Models to be dispatched',
                  style: TextStyle(
                    fontSize: context.isTablet ? 15 : 13,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF334155),
                  ),
                ),
                SizedBox(height: context.isTablet ? 12 : 8),

                // Breakdown of each model in batch
                ...byProduct.entries.map((entry) {
                  final items = entry.value;
                  final prod = items.first.product ?? _selectedProduct;
                  final isDual = prod?.hasDualSerial == true;
                  final inCount = isDual ? items.where((e) => e.unitType == 'indoor').length : 0;
                  final outCount = isDual ? items.where((e) => e.unitType == 'outdoor').length : 0;

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${prod?.brand ?? ""} ${prod?.model ?? ""}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: Text(
                                isDual ? '$inCount Pairs' : '${items.length} Units',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF065F46)),
                              ),
                            ),
                          ],
                        ),
                        if (isDual) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: const Color(0xFFC7D2FE)),
                                ),
                                child: Text(
                                  '$inCount Indoor',
                                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF3C3489)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDFA),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: const Color(0xFF99F6E4)),
                                ),
                                child: Text(
                                  '$outCount Outdoor',
                                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF0D9488)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 4),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.isTablet ? 18 : 14,
                    vertical: context.isTablet ? 14 : 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(context.isTablet ? 12 : 10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Serials Scanned:',
                        style: TextStyle(
                          fontSize: context.isTablet ? 15 : 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF475569),
                        ),
                      ),
                      Text(
                        '${_scannedItems.length} units',
                        style: TextStyle(
                          fontSize: context.isTablet ? 16 : 14,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: context.isTablet ? 18 : 14),

                // Bill Number / Invoice No (Required for outward dispatch)
                TextField(
                  controller: _billNumberController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Bill Number / Invoice No *',
                    hintText: 'e.g. BILL-1024, INV-8841',
                    prefixIcon: Icon(Icons.receipt_long, size: context.isTablet ? 24 : 20, color: const Color(0xFF4F46E5)),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: context.isTablet ? 18 : 14,
                      vertical: context.isTablet ? 16 : 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(context.isTablet ? 12 : 10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(context.isTablet ? 12 : 10),
                      borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                    ),
                  ),
                  style: TextStyle(fontSize: context.isTablet ? 16 : 13, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: context.isTablet ? 16 : 12),

                // Optional remarks with plenty of width
                TextField(
                  controller: _remarksController,
                  decoration: InputDecoration(
                    labelText: 'Dispatch Remarks (Optional)',
                    hintText: 'e.g. Driver name, vehicle number...',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: context.isTablet ? 18 : 14,
                      vertical: context.isTablet ? 16 : 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(context.isTablet ? 12 : 10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(context.isTablet ? 12 : 10),
                      borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                    ),
                  ),
                  style: TextStyle(fontSize: context.isTablet ? 15 : 13),
                ),
                SizedBox(height: context.isTablet ? 24 : 18),

                // Full-width buttons side-by-side
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: SizedBox(
                        height: context.isTablet ? 56 : 46,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF475569),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(context.isTablet ? 14 : 10),
                            ),
                          ),
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: context.isTablet ? 16 : 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: context.isTablet ? 16 : 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: context.isTablet ? 56 : 46,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E1B4B),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(context.isTablet ? 14 : 10),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {
                            final billText = _billNumberController.text.trim();
                            if (billText.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter Bill Number before confirming dispatch'),
                                  backgroundColor: Color(0xFFDC2626),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              return;
                            }
                            Navigator.pop(ctx, true);
                          },
                          child: Text(
                            'Confirm & Dispatch',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: context.isTablet ? 16 : 14,
                            ),
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
    );

    if (confirmed == true) {
      _submitOutwardBatch();
    }
  }

  Future<void> _submitOutwardBatch() async {
    if (_selectedShop == null || _scannedItems.isEmpty) return;

    setState(() => _submitting = true);

    final billNumber = _billNumberController.text.trim();
    final deliveryRef = _deliveryRefController.text.trim();
    final remarks = _remarksController.text.trim();

    // Group items by product ID
    final Map<String, List<OutwardScanResult>> byProduct = {};
    for (final item in _scannedItems) {
      final pid = item.product?.id ?? _selectedProduct!.id;
      byProduct.putIfAbsent(pid, () => []).add(item);
    }

    final List<Map<String, dynamic>> batchItems = [];
    for (final entry in byProduct.entries) {
      final prodId = entry.key;
      final items = entry.value;
      final serialList = items.map((e) => e.serialNumber).toList();

      final Map<String, String> unitTypesMap = {};
      for (final item in items) {
        if (item.unitType != null) {
          unitTypesMap[item.serialNumber] = item.unitType!;
        }
      }

      batchItems.add({
        'product_id': prodId,
        'serials': serialList.map((s) => {
          'serial_number': s,
          'confirmed_warning': true,
          if (unitTypesMap.containsKey(s)) 'unit_type': unitTypesMap[s],
        }).toList(),
        'serial_numbers': serialList,
        if (unitTypesMap.isNotEmpty) 'unit_types': unitTypesMap,
      });
    }

    // Preserve client request ID across retries of this dispatch attempt
    _dispatchRequestId ??= const Uuid().v4();

    final dispatchPayload = {
      'shop_id': _selectedShop!.id,
      'items': batchItems,
      'bill_number': billNumber.isEmpty ? null : billNumber,
      'delivery_reference': deliveryRef.isEmpty ? null : deliveryRef,
      'remarks': remarks.isEmpty ? null : remarks,
      'client_request_id': _dispatchRequestId,
    };

    if (!OfflineManager().isOnline) {
      await OfflineManager().queueDispatch(dispatchPayload);
      _dispatchRequestId = null;
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _scannedItems.clear();
        _scannedSerialSet.clear();
        _sequenceCounter = 1;
        _scanQueue.clear();
        _isProcessingQueue = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dispatch saved offline • Will auto-sync when online!')),
      );
      Navigator.pop(context);
      return;
    }

    try {
      final result = await _api.submitOutwardMultiBatch(
        shopId: _selectedShop!.id,
        items: batchItems,
        billNumber: billNumber.isEmpty ? null : billNumber,
        deliveryReference: deliveryRef.isEmpty ? null : deliveryRef,
        remarks: remarks.isEmpty ? null : remarks,
        clientRequestId: _dispatchRequestId,
      );

      // Successfully processed: reset request ID
      _dispatchRequestId = null;

      if (!mounted) return;
      setState(() => _submitting = false);

      final totalUnits = (result['total_units'] as num?)?.toInt() ?? _scannedItems.length;
      final totalMatched = (result['total_matched'] as num?)?.toInt() ?? 0;
      final totalRecorded = (result['total_unmatched'] as num?)?.toInt() ?? 0;
      final List<dynamic> batches = (result['batches'] as List<dynamic>?) ?? [];
      final finalBillNumber = (result['bill_number'] as String?)?.trim() ?? billNumber.trim();

      final List<String> modelSummaries = [];
      for (final b in batches) {
        final mName = b['product_name'] ?? b['model'] ?? 'Appliance';
        final q = b['quantity'] ?? 0;
        modelSummaries.add('$mName: $q unit(s)');
      }
      if (modelSummaries.isEmpty) {
        for (final entry in byProduct.entries) {
          final prodName = entry.value.first.product?.name ?? 'Appliance';
          modelSummaries.add('$prodName: ${entry.value.length} unit(s)');
        }
      }

      int printCooldownSeconds = 0;
      Timer? printCooldownTimer;

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (dialogCtx, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF059669)),
                SizedBox(width: 8),
                Text('Dispatch Recorded!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dispatched $totalUnits unit(s) across ${byProduct.length} model(s) to ${_selectedShop!.name}:',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, height: 1.4),
                ),
                const SizedBox(height: 10),
                ...modelSummaries.map((s) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.check, size: 14, color: Color(0xFF059669)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(s, style: const TextStyle(fontSize: 12))),
                        ],
                      ),
                    )),
                const Divider(height: 16),
                Text(
                  '• $totalMatched Matched (Tracked Inward)\n• $totalRecorded Recorded only (Old Stock)',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
            actions: [
              if (finalBillNumber.isNotEmpty) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: printCooldownSeconds > 0
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF94A3B8),
                    disabledForegroundColor: Colors.white,
                  ),
                  icon: Icon(
                    printCooldownSeconds > 0 ? Icons.hourglass_top_rounded : Icons.print_rounded,
                    size: 16,
                  ),
                  label: Text(
                    printCooldownSeconds > 0
                        ? 'Print on Office PC (${printCooldownSeconds}s)'
                        : 'Print on Office PC',
                  ),
                  onPressed: printCooldownSeconds > 0
                      ? null
                      : () async {
                          setDialogState(() => printCooldownSeconds = 30);
                          printCooldownTimer?.cancel();
                          printCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
                            if (printCooldownSeconds <= 1) {
                              t.cancel();
                              setDialogState(() => printCooldownSeconds = 0);
                            } else {
                              setDialogState(() => printCooldownSeconds--);
                            }
                          });

                          TopToast.show(
                            context,
                            message: 'Sending Bill #$finalBillNumber to Office PC...',
                            backgroundColor: const Color(0xFF3C3489),
                            icon: Icons.print_rounded,
                          );
                          try {
                            final res = await _api.printBill(billNumber: finalBillNumber);
                            if (dialogCtx.mounted) {
                              TopToast.show(
                                dialogCtx,
                                message: res['message'] ?? 'Printed to Office PC!',
                                backgroundColor: const Color(0xFF059669),
                                icon: Icons.check_circle_rounded,
                              );
                            }
                          } catch (e) {
                            if (dialogCtx.mounted) {
                              TopToast.show(
                                dialogCtx,
                                message: 'Print failed: ${e.toString().replaceAll('Exception: ', '')}',
                                backgroundColor: const Color(0xFFEF4444),
                                icon: Icons.error_outline_rounded,
                              );
                            }
                          }
                        },
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3C3489),
                    side: const BorderSide(color: Color(0xFF3C3489)),
                  ),
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('View Bill'),
                  onPressed: () {
                    printCooldownTimer?.cancel();
                    Navigator.pop(ctx);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BillDetailScreen(billNumber: finalBillNumber),
                      ),
                    );
                  },
                ),
              ],
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF64748B)),
                onPressed: () {
                  printCooldownTimer?.cancel();
                  Navigator.pop(ctx);
                },
                child: const Text('Finish', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
      printCooldownTimer?.cancel();

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);

      final errorStr = e.toString().replaceAll("Exception: ", "");

      // Check if a specific serial was identified as already dispatched
      final serialMatch = RegExp(r"Serial '([^']+)'").firstMatch(errorStr);
      final conflictedSerial = serialMatch?.group(1);

      if (conflictedSerial != null && _scannedItems.any((i) => i.serialNumber == conflictedSerial)) {
        final removeAndRetry = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
                SizedBox(width: 8),
                Text('Serial Already Dispatched'),
              ],
            ),
            content: Text(
              'Serial \'$conflictedSerial\' has already been dispatched.\n\nWould you like to remove this serial from your dispatch list and retry sending the remaining items?',
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
            _scannedItems.removeWhere((i) => i.serialNumber == conflictedSerial);
            _scannedSerialSet.remove(conflictedSerial);
            _reindexScannedItems();
          });
          _submitOutwardBatch();
          return;
        }
      }

      final errLower = errorStr.toLowerCase();
      final isNetError = !OfflineManager().isOnline ||
          errLower.contains('cannot reach server') ||
          errLower.contains('connection') ||
          errLower.contains('socketexception') ||
          errLower.contains('timeout');

      if (isNetError) {
        OfflineManager().markOffline();
        await OfflineManager().queueDispatch(dispatchPayload);
        _dispatchRequestId = null;
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _scannedItems.clear();
          _scannedSerialSet.clear();
          _sequenceCounter = 1;
          _scanQueue.clear();
          _isProcessingQueue = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dispatch saved to offline queue • Will auto-sync when connected!')),
        );
        Navigator.pop(context);
        return;
      }

      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Dispatch Problem'),
          content: Text(
            'Dispatch submission failed:\n$errorStr\n\nYou can retry the entire batch, queue it offline, or cancel to review.',
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
        _submitOutwardBatch();
        return;
      }

      if (action == 'queue') {
        final batch = QueuedBatch(
          id: const Uuid().v4(),
          type: QueueType.outward,
          createdAt: DateTime.now(),
          payload: {
            'shop_id': _selectedShop!.id,
            'items': batchItems,
            'bill_number': billNumber.isEmpty ? null : billNumber,
            'delivery_reference': deliveryRef.isEmpty ? null : deliveryRef,
            'remarks': remarks.isEmpty ? null : remarks,
          },
          description: 'Outward: ${_selectedShop!.name} (${_scannedItems.length} units, ${byProduct.length} models)',
        );
        await _queue.enqueue(batch);
        _dispatchRequestId = null;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dispatch saved to Offline Queue!')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _handleRestartPress() async {
    final int count = _scannedItems.length;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.restart_alt_rounded, color: Color(0xFFD97706), size: 24),
            SizedBox(width: 8),
            Text(
              'Restart Dispatch?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count > 0
                  ? 'You have scanned $count serial number${count == 1 ? "" : "s"}. Restarting will clear all scanned items and return to shop selection.'
                  : 'Are you sure you want to restart? This will reset your current selection and return to shop selection.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
            ),
            if (count > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFD97706)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$count scanned item${count == 1 ? "" : "s"} will be discarded.',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB45309)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restart', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      HapticFeedback.mediumImpact();
      setState(() {
        _currentStep = 1;
        _selectedProduct = null;
        _scannedItems.clear();
        _scannedSerialSet.clear();
        _sequenceCounter = 1;
        _scanQueue.clear();
        _isProcessingQueue = false;
        _billNumberController.clear();
        _deliveryRefController.clear();
        _remarksController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        // If a barcode scan occurred within the last 2000ms, swallow the pop request
        if (_lastScanTime != null && now.difference(_lastScanTime!).inMilliseconds < 2000) {
          debugPrint('[OutwardScreen] Swallowed pop attempt from scanner keys');
          return;
        }
        Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: const Color(0xFF0F172A),
          title: const Text('Outward Dispatch Scan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          leading: Focus(
            canRequestFocus: false,
            descendantsAreFocusable: false,
            skipTraversal: true,
            child: IconButton(
              focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          actions: [
            if (_currentStep > 1)
              Focus(
                canRequestFocus: false,
                descendantsAreFocusable: false,
                skipTraversal: true,
                child: TextButton(
                  focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
                  onPressed: _handleRestartPress,
                  child: const Text('Restart', style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            const OfflineBanner(),
            Expanded(child: _buildCurrentStep()),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    if (_currentStep == 1) {
      return _buildShopSelector();
    } else if (_currentStep == 2) {
      return _buildModelAndRefSelector();
    } else {
      return _buildScanningAndReviewView();
    }
  }

  // STEP 1: Select Shop
  Widget _buildShopSelector() {
    if (_loadingShops || _loadingProducts) return const Center(child: CircularProgressIndicator());

    final filtered = _shops.where((s) {
      final q = _shopSearch.toLowerCase();
      return s.name.toLowerCase().contains(q) || s.city.toLowerCase().contains(q);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/shop_icon.png',
                  width: 22,
                  height: 22,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.storefront, size: 18, color: Color(0xFFD97706)),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Step 1: Select destination shop receiving this dispatch.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFD97706), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search dealer shop or city...',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            onChanged: (val) => setState(() => _shopSearch = val),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, idx) {
                final s = filtered[idx];
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedShop = s;
                        _currentStep = 2;
                      });
                    },
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
                            width: 42,
                            height: 42,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Image.asset(
                              'assets/images/shop_icon.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.storefront, color: Color(0xFF3C3489), size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                ),
                                if (s.city.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    s.city.trim(),
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
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

  // STEP 2: Select Model & Delivery Ref
  Widget _buildModelAndRefSelector() {
    final filtered = _products.where((p) {
      final q = _productSearch.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.brand.toLowerCase().contains(q) ||
          p.model.toLowerCase().contains(q);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shop header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Image.asset(
                    'assets/images/shop_icon.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.storefront, color: Color(0xFF059669), size: 16),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedShop!.city.trim().isNotEmpty
                        ? 'Destination: ${_selectedShop!.name} (${_selectedShop!.city.trim()})'
                        : 'Destination: ${_selectedShop!.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _currentStep = 1),
                  child: const Text('Change', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Bill Number input
          TextField(
            controller: _billNumberController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Bill / Invoice No (e.g. BILL-1024, INV-8841)',
              prefixIcon: const Icon(Icons.receipt_long, size: 20, color: Color(0xFF4F46E5)),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Delivery Reference input
          TextField(
            controller: _deliveryRefController,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => _checkReferenceDuplicate(),
            decoration: InputDecoration(
              hintText: 'Delivery / Vehicle Ref (e.g. DEL-8890, KL-07-8822)',
              prefixIcon: const Icon(Icons.local_shipping_outlined, size: 20),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
          ),
          if (_deliveryRefWarning != null) ...[
            const SizedBox(height: 6),
            Text(
              _deliveryRefWarning!,
              style: const TextStyle(color: Color(0xFFD97706), fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Select Model to Dispatch:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
              ),
              InkWell(
                onTap: _loadingProducts ? null : () => _loadMetadata(forceRefresh: true),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      _loadingProducts
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                          : const Icon(Icons.sync_rounded, size: 14, color: Color(0xFF4F46E5)),
                      const SizedBox(width: 4),
                      Text(
                        _loadingProducts ? 'Syncing...' : 'Sync Models',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          TextField(
            decoration: InputDecoration(
              hintText: 'Search appliance model (e.g. GXI 360)...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _loadingProducts
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_productSearch.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() => _productSearch = ''),
                        )
                      : null),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            onChanged: (val) {
              setState(() => _productSearch = val);
              if (val.trim().length >= 2 && filtered.isEmpty && !_loadingProducts) {
                _loadMetadata(forceRefresh: true);
              }
            },
          ),
          const SizedBox(height: 10),

          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFF94A3B8)),
                          const SizedBox(height: 12),
                          Text(
                            _productSearch.isEmpty
                                ? 'No models available'
                                : 'No local match for "$_productSearch"',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF1E293B),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'If this model was just added on the admin dashboard, tap below to sync immediately.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: _loadingProducts
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.cloud_sync_outlined, size: 18),
                            label: Text(_loadingProducts ? 'Syncing...' : 'Sync Models from Server'),
                            onPressed: _loadingProducts ? null : () => _loadMetadata(forceRefresh: true),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _loadMetadata(forceRefresh: true),
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (ctx, idx) {
                        final p = filtered[idx];

                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedProduct = p;
                                _currentStep = 3;
                              });
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
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
                                              color: const Color(0xFFEFF6FF),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'Dual Serial Model: Scan Indoor & Outdoor units as 2 separate serials',
                                              style: TextStyle(fontSize: 10, color: Color(0xFF1D4ED8), fontWeight: FontWeight.w500),
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
                                        '${p.currentStockQty}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                      ),
                                      const Text('on shelves', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
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
          ),
        ],
      ),
    );
  }

  // STEP 3: Scanning & Review
  Widget _buildScanningAndReviewView() {
    final matchedCount = _scannedItems.where((e) => e.isMatched).length;
    final recordedOnlyCount = _scannedItems.where((e) => !e.isMatched).length;

    // Distinct models in current batch + selected
    final Map<String, Product> modelMap = {};
    if (_selectedProduct != null) {
      modelMap[_selectedProduct!.id] = _selectedProduct!;
    }
    for (final item in _scannedItems) {
      final p = item.product ?? _selectedProduct;
      if (p != null) {
        modelMap[p.id] = p;
      }
    }
    final modelList = modelMap.values.toList();
    final distinctModelCount = _scannedItems.map((e) => e.product?.id ?? _selectedProduct?.id).toSet().length;

    // Filter items based on active model tab
    final filteredItems = _activeFilterModelId == 'ALL'
        ? _scannedItems
        : _scannedItems.where((e) => (e.product?.id ?? _selectedProduct?.id) == _activeFilterModelId).toList();

    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      skipTraversal: true,
      child: Column(
        children: [
        // Ultra-Compact Header (Minimal height, zero wasted space)
        Container(
          color: Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: context.isTablet ? 24 : 14,
            vertical: context.isLandscapeTablet ? 4 : (context.isTablet ? 12 : 8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Shop details & Active Model inline
              Row(
                children: [
                  Image.asset(
                    'assets/images/shop_icon.png',
                    width: context.isLandscapeTablet ? 20 : (context.isTablet ? 28 : 22),
                    height: context.isLandscapeTablet ? 20 : (context.isTablet ? 28 : 22),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        Icon(Icons.storefront, size: context.isLandscapeTablet ? 18 : (context.isTablet ? 22 : 18), color: const Color(0xFF4F46E5)),
                  ),
                  SizedBox(width: context.isTablet ? 10 : 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedShop!.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: context.isLandscapeTablet ? 13.5 : (context.isTablet ? 16 : 13),
                            color: const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_selectedShop!.city.trim().isNotEmpty && !context.isLandscapeTablet)
                          Text(
                            _selectedShop!.city.trim(),
                            style: TextStyle(
                              fontSize: context.isTablet ? 12 : 10,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_deliveryRefController.text.trim().isNotEmpty) ...[
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.isTablet ? 10 : 6,
                        vertical: context.isLandscapeTablet ? 2 : (context.isTablet ? 4 : 2),
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(context.isTablet ? 6 : 4),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        'Ref: ${_deliveryRefController.text.trim()}',
                        style: TextStyle(
                          fontSize: context.isLandscapeTablet ? 11 : (context.isTablet ? 12 : 10),
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ),
                    SizedBox(width: context.isTablet ? 8 : 6),
                  ],
                  // Active Model Switch pill
                  InkWell(
                    onTap: _showModelSwitchBottomSheet,
                    borderRadius: BorderRadius.circular(context.isTablet ? 10 : 8),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.isTablet ? 12 : 8,
                        vertical: context.isLandscapeTablet ? 3 : (context.isTablet ? 6 : 4),
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(context.isTablet ? 10 : 8),
                        border: Border.all(color: const Color(0xFFC7D2FE)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: context.isTablet ? 260 : 130),
                            child: Text(
                              '${_selectedProduct?.brand ?? ""} ${_selectedProduct?.model ?? ""}',
                              style: TextStyle(
                                fontSize: context.isLandscapeTablet ? 11.5 : (context.isTablet ? 13 : 11),
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF4338CA),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.swap_horiz, size: context.isLandscapeTablet ? 15 : (context.isTablet ? 18 : 14), color: const Color(0xFF4338CA)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: context.isLandscapeTablet ? 3 : (context.isTablet ? 10 : 6)),

              // Row 2: Dual Serial Toggle (Compact) & Summary counts
              Row(
                children: [
                  if (_selectedProduct?.hasDualSerial == true) ...[
                    Container(
                      padding: EdgeInsets.all(context.isTablet ? 3 : 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(context.isTablet ? 9 : 7),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => setState(() => _outwardUnitType = 'indoor'),
                            borderRadius: BorderRadius.circular(context.isTablet ? 7 : 5),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: context.isTablet ? 12 : 8,
                                vertical: context.isLandscapeTablet ? 3 : (context.isTablet ? 5 : 3.5),
                              ),
                              decoration: BoxDecoration(
                                color: _outwardUnitType == 'indoor' ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(context.isTablet ? 7 : 5),
                                boxShadow: _outwardUnitType == 'indoor'
                                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 2)]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.home_outlined,
                                    size: context.isLandscapeTablet ? 13 : (context.isTablet ? 16 : 12),
                                    color: _outwardUnitType == 'indoor' ? const Color(0xFF3C3489) : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Indoor',
                                    style: TextStyle(
                                      fontSize: context.isLandscapeTablet ? 11 : (context.isTablet ? 13 : 11),
                                      fontWeight: _outwardUnitType == 'indoor' ? FontWeight.bold : FontWeight.w500,
                                      color: _outwardUnitType == 'indoor' ? const Color(0xFF3C3489) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => setState(() => _outwardUnitType = 'outdoor'),
                            borderRadius: BorderRadius.circular(context.isTablet ? 7 : 5),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: context.isTablet ? 12 : 8,
                                vertical: context.isLandscapeTablet ? 3 : (context.isTablet ? 5 : 3.5),
                              ),
                              decoration: BoxDecoration(
                                color: _outwardUnitType == 'outdoor' ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(context.isTablet ? 7 : 5),
                                boxShadow: _outwardUnitType == 'outdoor'
                                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 2)]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.wb_sunny_outlined,
                                    size: context.isLandscapeTablet ? 13 : (context.isTablet ? 16 : 12),
                                    color: _outwardUnitType == 'outdoor' ? const Color(0xFF0D9488) : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Outdoor',
                                    style: TextStyle(
                                      fontSize: context.isLandscapeTablet ? 11 : (context.isTablet ? 13 : 11),
                                      fontWeight: _outwardUnitType == 'outdoor' ? FontWeight.bold : FontWeight.w500,
                                      color: _outwardUnitType == 'outdoor' ? const Color(0xFF0D9488) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: context.isTablet ? 12 : 8),
                  ],

                  // Matched & Recorded Pills
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.isTablet ? 10 : 6,
                      vertical: context.isLandscapeTablet ? 2 : (context.isTablet ? 4 : 2),
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(context.isTablet ? 8 : 6),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Text(
                      '$matchedCount Matched',
                      style: TextStyle(
                        fontSize: context.isLandscapeTablet ? 11 : (context.isTablet ? 12.5 : 10),
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF065F46),
                      ),
                    ),
                  ),
                  if (recordedOnlyCount > 0) ...[
                    SizedBox(width: context.isTablet ? 8 : 4),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.isTablet ? 10 : 6,
                        vertical: context.isLandscapeTablet ? 2 : (context.isTablet ? 4 : 2),
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(context.isTablet ? 8 : 6),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        '$recordedOnlyCount Recorded',
                        style: TextStyle(
                          fontSize: context.isLandscapeTablet ? 11 : (context.isTablet ? 12.5 : 10),
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '${_scannedItems.length} Serials',
                    style: TextStyle(
                      fontSize: context.isLandscapeTablet ? 12 : (context.isTablet ? 14 : 11),
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Multi-Model Filter Tabs Bar
        Focus(
          canRequestFocus: false,
          descendantsAreFocusable: false,
          skipTraversal: true,
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(
                top: BorderSide(color: Color(0xFFE2E8F0)),
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            padding: EdgeInsets.symmetric(vertical: context.isLandscapeTablet ? 2 : (context.isTablet ? 8 : 4)),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: context.isTablet ? 24 : 14),
              child: Row(
                children: [
                  // ALL Tab
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text('All (${_scannedItems.length})'),
                    selected: _activeFilterModelId == 'ALL',
                    selectedColor: const Color(0xFF1E1B4B),
                    labelStyle: TextStyle(
                      fontSize: context.isLandscapeTablet ? 11 : (context.isTablet ? 13 : 11),
                      fontWeight: FontWeight.bold,
                      color: _activeFilterModelId == 'ALL' ? Colors.white : const Color(0xFF475569),
                    ),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: _activeFilterModelId == 'ALL' ? const Color(0xFF1E1B4B) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _activeFilterModelId = 'ALL');
                    },
                  ),
                  SizedBox(width: context.isTablet ? 8 : 6),

                  // Individual Model Chips
                  ...modelList.map((prod) {
                    final count = _scannedItems.where((e) => (e.product?.id ?? _selectedProduct?.id) == prod.id).length;
                    final isSelected = _activeFilterModelId == prod.id;
                    final isCurrentActive = prod.id == _selectedProduct?.id;

                    return Padding(
                      padding: EdgeInsets.only(right: context.isTablet ? 8 : 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: isCurrentActive
                            ? Icon(Icons.bolt, size: context.isLandscapeTablet ? 13 : (context.isTablet ? 16 : 13), color: isSelected ? Colors.amber : const Color(0xFF4F46E5))
                            : null,
                        label: Text('${prod.model} ($count)'),
                        selected: isSelected,
                        selectedColor: const Color(0xFF4F46E5),
                        labelStyle: TextStyle(
                          fontSize: context.isLandscapeTablet ? 11 : (context.isTablet ? 13 : 11),
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : const Color(0xFF334155),
                        ),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        onSelected: (val) {
                          setState(() {
                            _activeFilterModelId = val ? prod.id : 'ALL';
                            if (val) _selectedProduct = prod;
                          });
                        },
                      ),
                    );
                  }),

                  // Add / Switch Model Chip
                  ActionChip(
                    focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    avatar: Icon(Icons.add, size: context.isLandscapeTablet ? 13 : (context.isTablet ? 16 : 14), color: const Color(0xFF4F46E5)),
                    label: const Text('+ Add Model'),
                    labelStyle: TextStyle(
                      fontSize: context.isLandscapeTablet ? 11 : (context.isTablet ? 13 : 11),
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF4F46E5),
                    ),
                    backgroundColor: const Color(0xFFEEF2FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Color(0xFFC7D2FE)),
                    ),
                    onPressed: _showModelSwitchBottomSheet,
                  ),
                ],
              ),
            ),
          ),
        ),

        // Continuous Scan Button (Clean, wraps so full model name is always visible)
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.isTablet ? 24 : 14,
            vertical: context.isLandscapeTablet ? 4 : (context.isTablet ? 14 : 6),
          ),
          child: Column(
            children: [
              Focus(
                canRequestFocus: false,
                descendantsAreFocusable: false,
                skipTraversal: true,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: context.isLandscapeTablet ? 38 : (context.isTablet ? 66 : 44)),
                  child: SizedBox(
                    width: double.infinity,
                    height: context.isLandscapeTablet ? 38 : null,
                    child: ElevatedButton.icon(
                      focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(context.isLandscapeTablet ? 8 : (context.isTablet ? 16 : 10)),
                        ),
                        elevation: 0,
                        padding: EdgeInsets.symmetric(
                          horizontal: context.isTablet ? 24 : 12,
                          vertical: context.isLandscapeTablet ? 4 : (context.isTablet ? 16 : 8),
                        ),
                      ),
                      icon: Icon(Icons.qr_code_scanner, size: context.isLandscapeTablet ? 18 : (context.isTablet ? 28 : 20)),
                      label: Flexible(
                        child: Text(
                          _selectedProduct?.hasDualSerial == true
                              ? 'Continuous Scan (${_selectedProduct?.model} - ${_outwardUnitType == "indoor" ? "Indoor" : "Outdoor"})'
                              : 'Continuous Scan (${_selectedProduct?.model ?? "Model"})',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: context.isLandscapeTablet ? 13 : (context.isTablet ? 17 : 13),
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: context.isLandscapeTablet ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onPressed: _openContinuousScanner,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Real-time scan feedback banner (zero-latency, replaces heavy TopToast overlay on every scan)
        if (_lastScanFeedback != null)
          Container(
            width: double.infinity,
            margin: EdgeInsets.symmetric(horizontal: context.isTablet ? 24 : 14, vertical: context.isLandscapeTablet ? 1 : 3),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: context.isLandscapeTablet ? 3 : 6),
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

        // Order hint & quick jump buttons
        if (_scannedItems.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.isTablet ? 24 : 14,
              vertical: 3,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Newest (#${_scannedItems.length}) at top • #1 at bottom',
                  style: TextStyle(
                    fontSize: context.isTablet ? 12 : 10.5,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_scannedItems.length >= 6)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: _jumpToBottom,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
                      InkWell(
                        onTap: _jumpToTop,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
                  ),
              ],
            ),
          ),

        // List of scanned dispatches
        Expanded(
          child: filteredItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.output_rounded, size: context.isTablet ? 64 : 48, color: Colors.grey[300]),
                      const SizedBox(height: 10),
                      Text(
                        _scannedItems.isEmpty
                            ? 'No serials scanned for dispatch.'
                            : 'No serials for ${_selectedProduct?.model ?? "this model"}.',
                        style: TextStyle(color: const Color(0xFF94A3B8), fontSize: context.isTablet ? 15 : 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _scannedItems.isEmpty
                            ? 'Tap the button above to begin dispatch scanning.'
                            : 'Switch filter tab or scan serials for this model.',
                        style: TextStyle(color: const Color(0xFFCBD5E1), fontSize: context.isTablet ? 13 : 11),
                      ),
                    ],
                  ),
                )
              : context.isLandscapeTablet
                  ? GridView.builder(
                      controller: _scanListScrollController,
                      cacheExtent: 250.0,
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 4.8,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 5,
                      ),
                      itemCount: filteredItems.length,
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                      itemBuilder: (ctx, idx) => _buildOutwardItemCard(filteredItems[idx]),
                    )
                  : ListView.builder(
                      controller: _scanListScrollController,
                      cacheExtent: 250.0,
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: EdgeInsets.symmetric(
                        horizontal: context.isTablet ? 24 : 14,
                        vertical: context.isTablet ? 8 : 4,
                      ),
                      itemCount: filteredItems.length,
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                      itemBuilder: (ctx, idx) => _buildOutwardItemCard(filteredItems[idx]),
                    ),
        ),

        // Bottom submit
        if (_scannedItems.isNotEmpty)
          Container(
            padding: EdgeInsets.all(context.isLandscapeTablet ? 8 : (context.isTablet ? 24 : 16)),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: context.isLandscapeTablet ? 42 : (context.isTablet ? 64 : 50),
                child: ElevatedButton(
                  focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E1B4B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(context.isLandscapeTablet ? 10 : (context.isTablet ? 16 : 14)),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _submitting ? null : _onPressSubmitDispatch,
                  child: _submitting
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : Text(
                          distinctModelCount > 1
                              ? 'Submit Dispatch (${_scannedItems.length} Serials across $distinctModelCount Models)'
                              : 'Submit Dispatch (${_scannedItems.length} Serials)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: context.isLandscapeTablet ? 14 : (context.isTablet ? 17 : 14),
                          ),
                        ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

  void _reindexScannedItems() {
    final total = _scannedItems.length;
    for (int i = 0; i < total; i++) {
      _scannedItems[i].sequenceNumber = total - i;
    }
    _sequenceCounter = total + 1;
  }

  Widget _buildOutwardItemCard(OutwardScanResult item) {
    final itemProd = item.product ?? _selectedProduct;

    return Dismissible(
      key: ValueKey('outward_${item.serialNumber}'),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        margin: EdgeInsets.only(bottom: context.isLandscapeTablet ? 2 : (context.isTablet ? 10 : 6)),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          borderRadius: BorderRadius.circular(context.isLandscapeTablet ? 8 : (context.isTablet ? 14 : 10)),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Delete',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
            SizedBox(width: 6),
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        setState(() {
          _scannedItems.removeWhere((e) => e.serialNumber == item.serialNumber);
          _scannedSerialSet.remove(item.serialNumber);
          _reindexScannedItems();
        });
      },
      child: Container(
        key: ValueKey(item.serialNumber),
        margin: EdgeInsets.only(bottom: context.isLandscapeTablet ? 2 : (context.isTablet ? 10 : 6)),
        padding: EdgeInsets.symmetric(
          horizontal: context.isLandscapeTablet ? 10 : (context.isTablet ? 18 : 12),
          vertical: context.isLandscapeTablet ? 6 : (context.isTablet ? 14 : 8),
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(context.isLandscapeTablet ? 8 : (context.isTablet ? 14 : 10)),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: context.isTablet && !context.isLandscapeTablet
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Row 1: Index Number + Prominent Serial Number + Status Pill
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.isTablet ? 8 : 5,
                    vertical: context.isTablet ? 3 : 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(context.isTablet ? 6 : 4),
                  ),
                  child: Text(
                    '#${item.sequenceNumber}',
                    style: TextStyle(
                      fontSize: context.isLandscapeTablet ? 10 : (context.isTablet ? 12 : 9.5),
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
                SizedBox(width: context.isLandscapeTablet ? 6 : (context.isTablet ? 10 : 8)),
                Expanded(
                  child: Text(
                    item.serialNumber,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: context.isLandscapeTablet ? 13.5 : (context.isTablet ? 16 : 14),
                      color: const Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Matched or Recorded Status Pill
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.isLandscapeTablet ? 6 : (context.isTablet ? 10 : 6),
                    vertical: context.isLandscapeTablet ? 2 : (context.isTablet ? 4 : 2),
                  ),
                  decoration: BoxDecoration(
                    color: item.isMatched ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(context.isTablet ? 8 : 4),
                    border: Border.all(
                      color: item.isMatched ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
                    ),
                  ),
                  child: Text(
                    item.isMatched ? 'Matched' : 'New Serial',
                    style: TextStyle(
                      fontSize: context.isLandscapeTablet ? 9.5 : (context.isTablet ? 11.5 : 9.5),
                      fontWeight: FontWeight.bold,
                      color: item.isMatched ? const Color(0xFF065F46) : const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),

          // Row 2: Product Model Tag + Unit Type (Indoor/Outdoor) toggle button
          if (itemProd != null || item.unitType != null) ...[
            SizedBox(height: context.isLandscapeTablet ? 2 : (context.isTablet ? 8 : 4)),
            Row(
              children: [
                if (itemProd != null)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.isLandscapeTablet ? 6 : (context.isTablet ? 10 : 6),
                      vertical: context.isLandscapeTablet ? 2 : (context.isTablet ? 4 : 2),
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(context.isTablet ? 6 : 4),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.devices, size: context.isLandscapeTablet ? 11 : (context.isTablet ? 14 : 11), color: const Color(0xFF4F46E5)),
                        SizedBox(width: context.isTablet ? 6 : 4),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: context.isTablet ? 320 : 160),
                          child: Text(
                            '${itemProd.brand} • ${itemProd.model}',
                            style: TextStyle(
                              fontSize: context.isLandscapeTablet ? 10 : (context.isTablet ? 12.5 : 10),
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF4F46E5),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (item.unitType != null) ...[
                  SizedBox(width: context.isTablet ? 8 : 5),
                  InkWell(
                    borderRadius: BorderRadius.circular(context.isTablet ? 6 : 4),
                    onTap: () {
                      setState(() {
                        item.unitType = (item.unitType == 'indoor') ? 'outdoor' : 'indoor';
                      });
                      ScaffoldMessenger.of(context).removeCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${item.serialNumber} toggled to ${item.unitType!.toUpperCase()}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.isLandscapeTablet ? 6 : (context.isTablet ? 10 : 6),
                        vertical: context.isLandscapeTablet ? 2 : (context.isTablet ? 4 : 2),
                      ),
                      decoration: BoxDecoration(
                        color: item.unitType == 'indoor'
                            ? const Color(0xFFEEF2FF)
                            : const Color(0xFFF0FDFA),
                        borderRadius: BorderRadius.circular(context.isTablet ? 6 : 4),
                        border: Border.all(
                          color: item.unitType == 'indoor'
                              ? const Color(0xFFC7D2FE)
                              : const Color(0xFF99F6E4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.unitType == 'indoor' ? 'Indoor' : 'Outdoor',
                            style: TextStyle(
                              fontSize: context.isLandscapeTablet ? 9.5 : (context.isTablet ? 12 : 9.5),
                              fontWeight: FontWeight.bold,
                              color: item.unitType == 'indoor'
                                  ? const Color(0xFF3C3489)
                                  : const Color(0xFF0D9488),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.swap_vert,
                            size: context.isLandscapeTablet ? 11 : (context.isTablet ? 14 : 11),
                            color: item.unitType == 'indoor'
                                ? const Color(0xFF3C3489)
                                : const Color(0xFF0D9488),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],

          // Row 3: Only show if flagged with warning
          if (item.isFlaggedForReview && item.warningMessage != null && item.warningMessage!.isNotEmpty) ...[
            SizedBox(height: context.isTablet ? 6 : 3),
            Text(
              item.warningMessage!,
              style: TextStyle(
                fontSize: context.isLandscapeTablet ? 9.5 : (context.isTablet ? 12 : 10),
                fontWeight: FontWeight.w500,
                color: const Color(0xFFD97706),
              ),
            ),
          ],
        ],
      ),
    ),
    );
  }
}
