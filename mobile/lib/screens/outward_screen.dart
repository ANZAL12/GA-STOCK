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

  final TextEditingController _deliveryRefController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();
  String? _deliveryRefWarning;

  // Scanned lines
  final List<OutwardScanResult> _scannedItems = [];
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
          prompt: 'Continuous Scan: ${_selectedProduct!.brand} ${_selectedProduct!.model}',
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

      // --- CASE 1: MATCHED (Tracked & Available) ---
      if (caseVal == 1 || caseName == 'matched') {
        HapticFeedback.lightImpact();
        setState(() {
          _scannedItems.insert(
            0,
            OutwardScanResult(
              serialNumber: cleanSerial,
              caseType: OutwardCase.matched,
              isMatched: true,
              warningMessage: msg,
            ),
          );
        });
        _showToast('Matched: $cleanSerial', const Color(0xFF059669));
      }

      // --- CASE 2: RECORDED ONLY (Unmatched pre-go-live stock) ---
      else if (caseVal == 2 || caseName == 'unmatched') {
        HapticFeedback.mediumImpact();
        setState(() {
          _scannedItems.insert(
            0,
            OutwardScanResult(
              serialNumber: cleanSerial,
              caseType: OutwardCase.recordedOnly,
              isMatched: false,
              warningMessage: 'Old pre-go-live stock recorded. Never blocked.',
            ),
          );
        });
        _showToast('Recorded only: $cleanSerial', const Color(0xFF475569));
      }

      // --- CASE 3: STATUS WARNING (Damaged, reserved, etc. NOT dispatched!) ---
      else if (caseVal == 3 || caseName == 'status_warning') {
        HapticFeedback.heavyImpact();
        final proceed = await _showCase3StatusWarningDialog(cleanSerial, msg ?? 'Unit is not currently marked available.');
        if (proceed == true) {
          setState(() {
            _scannedItems.insert(
              0,
              OutwardScanResult(
                serialNumber: cleanSerial,
                caseType: OutwardCase.statusWarning,
                isMatched: isMatched,
                isFlaggedForReview: true,
                warningMessage: msg,
              ),
            );
          });
        }
      }

      // --- CASE 4: MODEL MISMATCH (Belongs to different appliance model) ---
      else if (caseVal == 4 || caseName == 'model_mismatch') {
        HapticFeedback.heavyImpact();
        final existingModel = res['registered_model_name'] ?? serialDetail?['product_name'] ?? 'another model';
        await _showCase4ModelMismatchDialog(cleanSerial, existingModel, msg);
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      _showSimpleAlert('Validation Error', 'Could not verify serial "$cleanSerial": $e');
    }
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
            const Text(
              'A barcode that has already been dispatched can NEVER be scanned or dispatched again to any shop or under any model.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.3),
            ),
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
          msg ?? 'Serial "$serial" belongs to "$existingModel", but this dispatch is configured for "${_selectedProduct!.name}".',
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

  Future<void> _submitOutwardBatch() async {
    if (_selectedShop == null || _selectedProduct == null || _scannedItems.isEmpty) return;

    setState(() => _submitting = true);

    final serialList = _scannedItems.map((e) => e.serialNumber).toList();
    final deliveryRef = _deliveryRefController.text.trim();
    final remarks = _remarksController.text.trim();

    try {
      final result = await _api.submitOutwardBatch(
        shopId: _selectedShop!.id,
        productId: _selectedProduct!.id,
        serialNumbers: serialList,
        deliveryReference: deliveryRef.isEmpty ? null : deliveryRef,
        remarks: remarks.isEmpty ? null : remarks,
      );

      if (!mounted) return;
      setState(() => _submitting = false);

      final matchedCount = result['matched_count'] ?? 0;
      final unmatchedCount = result['unmatched_count'] ?? 0;
      final total = result['quantity'] ?? serialList.length;

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
          content: Text(
            'Dispatched $total unit(s) to ${_selectedShop!.name}.\n\n• $matchedCount Matched (Tracked Inward)\n• $unmatchedCount Recorded only (Old Stock)',
            style: const TextStyle(fontSize: 13, height: 1.4),
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
        final batch = QueuedBatch(
          id: const Uuid().v4(),
          type: QueueType.outward,
          createdAt: DateTime.now(),
          payload: {
            'shop_id': _selectedShop!.id,
            'product_id': _selectedProduct!.id,
            'serial_numbers': serialList,
            'delivery_reference': deliveryRef,
            'remarks': remarks,
          },
          description: 'Outward: ${_selectedShop!.name} - ${_selectedProduct!.name} (${serialList.length} units)',
        );
        await _queue.enqueue(batch);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dispatch batch saved to Offline Queue!')),
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
            child: const Row(
              children: [
                Icon(Icons.storefront, size: 18, color: Color(0xFFD97706)),
                SizedBox(width: 8),
                Expanded(
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
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: const Icon(Icons.storefront, color: Color(0xFF3C3489), size: 20),
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
                                const SizedBox(height: 2),
                                Text(
                                  s.city,
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
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
                const Icon(Icons.check_circle, color: Color(0xFF059669), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Destination: ${_selectedShop!.name} (${_selectedShop!.city})',
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
                final isAC = p.name.toLowerCase().contains('ac') ||
                    p.name.toLowerCase().contains('conditioner') ||
                    (p.categoryName?.toLowerCase().contains('ac') ?? false);

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
                                if (isAC) ...[
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

    return Column(
      children: [
        // Summary header card
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedShop!.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                        ),
                        Text(
                          '${_selectedProduct!.name} • ${_selectedProduct!.model}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _currentStep = 2),
                    child: const Text('Change Model', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Text(
                      '$matchedCount Matched',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      '$recordedOnlyCount Recorded only',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Total: ${_scannedItems.length}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
            ],
          ),
        ),

        const Divider(height: 1, color: Color(0xFFE2E8F0)),

        // Big Continuous Scan Button
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 1,
              ),
              icon: const Icon(Icons.qr_code_scanner, size: 22),
              label: const Text('Continuous Barcode Scan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              onPressed: _openContinuousScanner,
            ),
          ),
        ),

        // List of scanned dispatches
        Expanded(
          child: _scannedItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.output_rounded, size: 56, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      const Text(
                        'No serials scanned for dispatch.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap the button above to begin dispatch scanning.',
                        style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _scannedItems.length,
                  itemBuilder: (ctx, idx) {
                    final item = _scannedItems[idx];
                    return Dismissible(
                      key: Key(item.serialNumber),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) {
                        setState(() => _scannedItems.removeAt(idx));
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '#${_scannedItems.length - idx}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.serialNumber,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  if (item.warningMessage != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      item.warningMessage!,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: item.isFlaggedForReview ? const Color(0xFFD97706) : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: item.isFlaggedForReview
                                    ? const Color(0xFFFFFBEB)
                                    : item.isMatched
                                        ? const Color(0xFFECFDF5)
                                        : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
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
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: item.isFlaggedForReview
                                      ? const Color(0xFFB45309)
                                      : item.isMatched
                                          ? const Color(0xFF065F46)
                                          : const Color(0xFF475569),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16, color: Color(0xFF94A3B8)),
                              onPressed: () {
                                setState(() => _scannedItems.removeAt(idx));
                              },
                            ),
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
                  onPressed: _submitting ? null : _submitOutwardBatch,
                  child: _submitting
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : Text(
                          'Submit Dispatch (${_scannedItems.length} Serials)',
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
