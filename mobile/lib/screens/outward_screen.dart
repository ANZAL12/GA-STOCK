import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/offline_queue_service.dart';
import '../services/websocket_service.dart';
import '../widgets/scanner_widget.dart';

class OutwardScreen extends StatefulWidget {
  const OutwardScreen({super.key});

  @override
  State<OutwardScreen> createState() => _OutwardScreenState();
}

class _OutwardScreenState extends State<OutwardScreen> {
  final ApiService _api = ApiService();
  final OfflineQueueService _queue = OfflineQueueService();
  StreamSubscription? _wsSubscription;

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
  String _activeFilterModelId = 'ALL';
  String _outwardUnitType = 'indoor';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
    _initWebSocket();
  }

  void _initWebSocket() {
    WebSocketService().connect();
    _wsSubscription = WebSocketService().stream.listen((event) {
      if (!mounted) return;
      final type = event['event'];
      final data = event['data'];

      if (type == 'product_created' && data is Map<String, dynamic>) {
        try {
          final newProd = Product.fromJson(data);
          setState(() {
            _products.removeWhere((p) => p.id == newProd.id);
            _products.insert(0, newProd);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.bolt, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚡ Instant Update: Added ${newProd.brand} ${newProd.model}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 3),
              backgroundColor: const Color(0xFF1E1B4B),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } catch (_) {}
      } else if (type == 'product_updated' && data is Map<String, dynamic>) {
        try {
          final updatedProd = Product.fromJson(data);
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
        _loadMetadata();
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
          _loadMetadata();
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
    _wsSubscription?.cancel();
    _billNumberController.dispose();
    _deliveryRefController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    try {
      final results = await Future.wait([
        _api.getShops(),
        _api.getProducts(),
      ]);
      if (mounted) {
        setState(() {
          _shops = results[0] as List<Shop>;
          _products = results[1] as List<Product>;
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
          onScanned: (serial) => _handleOutwardScan(serial),
        ),
      ),
    );
  }

  Future<void> _handleOutwardScan(String serial) async {
    final cleanSerial = serial.trim();
    if (cleanSerial.isEmpty) return;

    // Check duplicate in current batch
    if (_scannedItems.any((item) => item.serialNumber == cleanSerial)) {
      HapticFeedback.heavyImpact();
      _showSimpleAlert('Duplicate Serial', 'Serial "$cleanSerial" is already in this dispatch batch.');
      return;
    }

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
        await _showAlreadyDispatchedDialog(
          cleanSerial,
          msg ?? 'Serial "$cleanSerial" has already been dispatched. Dispatched serials can NEVER be scanned or dispatched again.',
        );
        return; // NEVER ADD TO LIST!
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
        setState(() {
          _scannedItems.insert(
            0,
            OutwardScanResult(
              serialNumber: cleanSerial,
              product: _selectedProduct,
              caseType: OutwardCase.matched,
              isMatched: true,
              warningMessage: msg,
              unitType: unitType,
            ),
          );
        });
        _showToast('Matched: $cleanSerial (${_selectedProduct!.model})', const Color(0xFF059669));
      }

      // --- CASE 2: RECORDED ONLY (Unmatched pre-go-live stock) ---
      else if (caseVal == 2 || caseName == 'unmatched') {
        HapticFeedback.mediumImpact();
        final unitType = _selectedProduct?.hasDualSerial == true ? _outwardUnitType : null;
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
            ),
          );
        });
        _showToast('Recorded only: $cleanSerial (${_selectedProduct!.model})', const Color(0xFF475569));
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

        HapticFeedback.heavyImpact();
        final proceed = await _showCase3StatusWarningDialog(cleanSerial, msg ?? 'Unit is not currently marked available.');
        if (proceed == true) {
          final unitType = (res['unit_type'] as String?) ?? (_selectedProduct?.hasDualSerial == true ? _outwardUnitType : null);
          setState(() {
            _scannedItems.insert(
              0,
              OutwardScanResult(
                serialNumber: cleanSerial,
                product: _selectedProduct,
                caseType: OutwardCase.statusWarning,
                isMatched: isMatched,
                isFlaggedForReview: true,
                warningMessage: msg,
                unitType: unitType,
              ),
            );
          });
        }
      }

      // --- CASE 4: MODEL MISMATCH (Serial is registered under another model in this godown) ---
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
          } catch (_) {}
        }
        final existingModel = res['registered_model_name'] ?? serialDetail?['product_name'] ?? 'another model';

        if (matchedProd != null) {
          final dialogResult = await _showDifferentModelDialog(
            cleanSerial,
            matchedProd,
            initialUnitType: res['unit_type']?.toString(),
          );
          if (dialogResult != null && dialogResult['action'] == 'add') {
            final String? chosenUnitType = dialogResult['unit_type'];
            setState(() {
              _scannedItems.insert(
                0,
                OutwardScanResult(
                  serialNumber: cleanSerial,
                  product: matchedProd,
                  caseType: OutwardCase.matched,
                  isMatched: true,
                  unitType: chosenUnitType,
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
              'Added $cleanSerial (${matchedProd.model})${matchedProd.hasDualSerial ? " • Next unit: ${_outwardUnitType.toUpperCase()}" : ""}',
              const Color(0xFF059669),
            );
          }
        } else {
          await _showCase4ModelMismatchDialog(cleanSerial, existingModel, msg);
        }
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      _showSimpleAlert('Validation Error', 'Could not verify serial "$cleanSerial": $e');
    }
  }

  Future<Map<String, dynamic>?> _showDifferentModelDialog(
    String serial,
    Product targetProd, {
    String? initialUnitType,
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
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.swap_horiz, color: Color(0xFF4F46E5), size: 20),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Model Mismatch Detected',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String sheetSearch = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filteredProds = _products.where((p) {
              final q = sheetSearch.toLowerCase();
              return p.name.toLowerCase().contains(q) ||
                  p.brand.toLowerCase().contains(q) ||
                  p.model.toLowerCase().contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
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
                        const Text(
                          'Switch / Add Model for this Shop',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const Spacer(),
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
                        hintText: 'Search brand or model...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      onChanged: (val) {
                        setSheetState(() => sheetSearch = val);
                      },
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
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
                ],
              ),
            );
          },
        );
      },
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        backgroundColor: bgColor,
      ),
    );
  }

  void _showSimpleAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(message, style: const TextStyle(fontSize: 13)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showCase3StatusWarningDialog(String serial, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
            SizedBox(width: 8),
            Expanded(child: Text('Serial Status Warning', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Text(
                'If you proceed, this dispatch will be flagged for administrator review.',
                style: TextStyle(fontSize: 11, color: Color(0xFFB45309)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel Scan')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dispatch Anyway (Flag)', style: TextStyle(color: Colors.white)),
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
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.local_shipping_outlined, color: Color(0xFF4F46E5), size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Confirm Dispatch',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                          SizedBox(height: 1),
                          Text(
                            'Review dispatch summary before submitting',
                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
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

                // Destination Shop Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/shop_icon.png',
                            width: 20,
                            height: 20,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.storefront, size: 18, color: Color(0xFF4F46E5)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedShop!.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
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
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                          if (_deliveryRefController.text.trim().isNotEmpty) ...[
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Ref: ${_deliveryRefController.text.trim()}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4338CA)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                const Text(
                  'Models to be dispatched',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 8),

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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Serials Scanned:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                      ),
                      Text(
                        '${_scannedItems.length} units',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Bill Number / Invoice No (Required for outward dispatch)
                TextField(
                  controller: _billNumberController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Bill Number / Invoice No *',
                    hintText: 'e.g. BILL-1024, INV-8841',
                    prefixIcon: const Icon(Icons.receipt_long, size: 20, color: Color(0xFF4F46E5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5)),
                  ),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),

                // Optional remarks with plenty of width
                TextField(
                  controller: _remarksController,
                  decoration: InputDecoration(
                    labelText: 'Dispatch Remarks (Optional)',
                    hintText: 'e.g. Driver name, vehicle number...',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5)),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 18),

                // Full-width buttons side-by-side
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
                            backgroundColor: const Color(0xFF1E1B4B),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                          child: const Text('Confirm & Dispatch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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

    int totalMatched = 0;
    int totalRecorded = 0;
    int totalUnits = 0;
    final List<String> modelSummaries = [];

    try {
      for (final entry in byProduct.entries) {
        final prodId = entry.key;
        final items = entry.value;
        final serialList = items.map((e) => e.serialNumber).toList();
        final prodName = items.first.product?.name ?? _selectedProduct?.name ?? 'Appliance';

        final Map<String, String> unitTypesMap = {};
        for (final item in items) {
          if (item.unitType != null) {
            unitTypesMap[item.serialNumber] = item.unitType!;
          }
        }

        final result = await _api.submitOutwardBatch(
          shopId: _selectedShop!.id,
          productId: prodId,
          serialNumbers: serialList,
          unitTypes: unitTypesMap.isNotEmpty ? unitTypesMap : null,
          billNumber: billNumber.isEmpty ? null : billNumber,
          deliveryReference: deliveryRef.isEmpty ? null : deliveryRef,
          remarks: remarks.isEmpty ? null : remarks,
        );

        final mCount = (result['matched_count'] as num?)?.toInt() ?? 0;
        final uCount = (result['unmatched_count'] as num?)?.toInt() ?? 0;
        final qCount = (result['quantity'] as num?)?.toInt() ?? serialList.length;

        totalMatched += mCount;
        totalRecorded += uCount;
        totalUnits += qCount;
        modelSummaries.add('$prodName: $qCount unit(s)');
      }

      if (!mounted) return;
      setState(() => _submitting = false);

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Finish', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);

      final queueOffline = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Network Problem'),
          content: Text(
            'Dispatch submission failed: ${e.toString().replaceAll("Exception: ", "")}\n\nQueue this dispatch in local memory to sync when connection is restored?',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Queue Offline', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (queueOffline == true) {
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
          final prodName = items.first.product?.name ?? _selectedProduct?.name ?? 'Appliance';

          final batch = QueuedBatch(
            id: const Uuid().v4(),
            type: QueueType.outward,
            createdAt: DateTime.now(),
            payload: {
              'shop_id': _selectedShop!.id,
              'product_id': prodId,
              'serial_numbers': serialList,
              if (unitTypesMap.isNotEmpty) 'unit_types': unitTypesMap,
              'bill_number': billNumber.isEmpty ? null : billNumber,
              'delivery_reference': deliveryRef.isEmpty ? null : deliveryRef,
              'remarks': remarks.isEmpty ? null : remarks,
            },
            description: 'Outward: ${_selectedShop!.name} - $prodName (${serialList.length} units)',
          );
          await _queue.enqueue(batch);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All model batches saved to Offline Queue!')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF0F172A),
        title: const Text('Outward Dispatch Scan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (_currentStep > 1)
            TextButton(
              onPressed: () {
                setState(() {
                  _currentStep = 1;
                  _selectedProduct = null;
                  _scannedItems.clear();
                  _billNumberController.clear();
                  _deliveryRefController.clear();
                  _remarksController.clear();
                });
              },
              child: const Text('Restart', style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _buildCurrentStep(),
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

          const Text(
            'Select Model to Dispatch:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 8),

          TextField(
            decoration: InputDecoration(
              hintText: 'Search appliance model...',
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
          const SizedBox(height: 10),

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

    return Column(
      children: [
        // Ultra-Compact Header (Minimal height, zero wasted space)
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Shop details & Active Model inline
              Row(
                children: [
                  Image.asset(
                    'assets/images/shop_icon.png',
                    width: 22,
                    height: 22,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.storefront, size: 18, color: Color(0xFF4F46E5)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedShop!.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_selectedShop!.city.trim().isNotEmpty)
                          Text(
                            _selectedShop!.city.trim(),
                            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                          ),
                      ],
                    ),
                  ),
                  if (_deliveryRefController.text.trim().isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        'Ref: ${_deliveryRefController.text.trim()}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  // Active Model Switch pill
                  InkWell(
                    onTap: _showModelSwitchBottomSheet,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFC7D2FE)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 130),
                            child: Text(
                              '${_selectedProduct?.brand ?? ""} ${_selectedProduct?.model ?? ""}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4338CA)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.swap_horiz, size: 14, color: Color(0xFF4338CA)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // Row 2: Dual Serial Toggle (Compact) & Summary counts
              Row(
                children: [
                  if (_selectedProduct?.hasDualSerial == true) ...[
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => setState(() => _outwardUnitType = 'indoor'),
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: _outwardUnitType == 'indoor' ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(5),
                                boxShadow: _outwardUnitType == 'indoor'
                                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 2)]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.home_outlined, size: 12, color: _outwardUnitType == 'indoor' ? const Color(0xFF3C3489) : const Color(0xFF64748B)),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Indoor',
                                    style: TextStyle(
                                      fontSize: 11,
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
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: _outwardUnitType == 'outdoor' ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(5),
                                boxShadow: _outwardUnitType == 'outdoor'
                                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 2)]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.wb_sunny_outlined, size: 12, color: _outwardUnitType == 'outdoor' ? const Color(0xFF0D9488) : const Color(0xFF64748B)),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Outdoor',
                                    style: TextStyle(
                                      fontSize: 11,
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
                    const SizedBox(width: 8),
                  ],

                  // Matched & Recorded Pills
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Text(
                      '$matchedCount Matched',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                    ),
                  ),
                  if (recordedOnlyCount > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        '$recordedOnlyCount Recorded',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '${_scannedItems.length} Serials',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Multi-Model Filter Tabs Bar
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(
              top: BorderSide(color: Color(0xFFE2E8F0)),
              bottom: BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
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
                    fontSize: 11,
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
                const SizedBox(width: 6),

                // Individual Model Chips
                ...modelList.map((prod) {
                  final count = _scannedItems.where((e) => (e.product?.id ?? _selectedProduct?.id) == prod.id).length;
                  final isSelected = _activeFilterModelId == prod.id;
                  final isCurrentActive = prod.id == _selectedProduct?.id;

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      avatar: isCurrentActive
                          ? Icon(Icons.bolt, size: 13, color: isSelected ? Colors.amber : const Color(0xFF4F46E5))
                          : null,
                      label: Text('${prod.model} ($count)'),
                      selected: isSelected,
                      selectedColor: const Color(0xFF4F46E5),
                      labelStyle: TextStyle(
                        fontSize: 11,
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
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: const Icon(Icons.add, size: 14, color: Color(0xFF4F46E5)),
                  label: const Text('+ Add Model'),
                  labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
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

        // Continuous Scan Button (Clean, compact, no wasted margins or subtitles)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              label: Text(
                _selectedProduct?.hasDualSerial == true
                    ? 'Continuous Scan (${_selectedProduct?.model} - ${_outwardUnitType == "indoor" ? "Indoor" : "Outdoor"})'
                    : 'Continuous Scan (${_selectedProduct?.model ?? "Model"})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: _openContinuousScanner,
            ),
          ),
        ),

        // List of scanned dispatches
        Expanded(
          child: filteredItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.output_rounded, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 10),
                      Text(
                        _scannedItems.isEmpty
                            ? 'No serials scanned for dispatch.'
                            : 'No serials for ${_selectedProduct?.model ?? "this model"}.',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _scannedItems.isEmpty
                            ? 'Tap the button above to begin dispatch scanning.'
                            : 'Switch filter tab or scan serials for this model.',
                        style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  itemCount: filteredItems.length,
                  itemBuilder: (ctx, idx) {
                    final item = filteredItems[idx];
                    final itemProd = item.product ?? _selectedProduct;

                    return Dismissible(
                      key: Key(item.serialNumber),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white, size: 20),
                      ),
                      onDismissed: (_) {
                        setState(() => _scannedItems.removeWhere((e) => e.serialNumber == item.serialNumber));
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Row 1: Index Number + Prominent Serial Number + Status Pill + Delete button
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '#${filteredItems.length - idx}',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.serialNumber,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Color(0xFF0F172A),
                                      letterSpacing: 0.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: item.isFlaggedForReview
                                        ? const Color(0xFFFFFBEB)
                                        : item.isMatched
                                            ? const Color(0xFFECFDF5)
                                            : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: item.isFlaggedForReview
                                          ? const Color(0xFFFDE68A)
                                          : item.isMatched
                                              ? const Color(0xFFA7F3D0)
                                              : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Text(
                                    item.isFlaggedForReview
                                        ? 'Flagged'
                                        : item.isMatched
                                            ? 'Matched'
                                            : 'Recorded only',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: item.isFlaggedForReview
                                          ? const Color(0xFFB45309)
                                          : item.isMatched
                                              ? const Color(0xFF065F46)
                                              : const Color(0xFF475569),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    setState(() => _scannedItems.removeWhere((e) => e.serialNumber == item.serialNumber));
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(2),
                                    child: Icon(Icons.close, size: 16, color: Color(0xFF94A3B8)),
                                  ),
                                ),
                              ],
                            ),

                            // Row 2: Product Model Pill & Unit Type Badge
                            if (itemProd != null || item.unitType != null) ...[
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  if (itemProd != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEEF2FF),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFFC7D2FE)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.devices, size: 11, color: Color(0xFF4F46E5)),
                                          const SizedBox(width: 4),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 160),
                                            child: Text(
                                              '${itemProd.brand} • ${itemProd.model}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF4F46E5),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (item.unitType != null) ...[
                                    const SizedBox(width: 5),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(4),
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
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: item.unitType == 'indoor'
                                              ? const Color(0xFFEEF2FF)
                                              : const Color(0xFFF0FDFA),
                                          borderRadius: BorderRadius.circular(4),
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
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.bold,
                                                color: item.unitType == 'indoor'
                                                    ? const Color(0xFF3C3489)
                                                    : const Color(0xFF0D9488),
                                              ),
                                            ),
                                            const SizedBox(width: 3),
                                            Icon(
                                              Icons.swap_vert,
                                              size: 11,
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
                              const SizedBox(height: 3),
                              Text(
                                item.warningMessage!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFFD97706),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Bottom submit
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
                    backgroundColor: const Color(0xFF1E1B4B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: _submitting ? null : _onPressSubmitDispatch,
                  child: _submitting
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : Text(
                          distinctModelCount > 1
                              ? 'Submit Dispatch (${_scannedItems.length} Serials across $distinctModelCount Models)'
                              : 'Submit Dispatch (${_scannedItems.length} Serials)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
