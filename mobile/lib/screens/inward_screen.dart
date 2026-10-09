import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/offline_queue_service.dart';
import '../services/websocket_service.dart';
import '../widgets/scanner_widget.dart';

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

  InwardScannedItem({
    required this.serialNumber,
    required this.product,
    this.unitType,
    this.isAutoDetected = false,
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

  InwardStage _stage = InwardStage.selectCase;
  String _inwardType = 'stock_in'; // 'stock_in', 'return', 'damaged'

  List<Product> _products = [];
  Product? _selectedProduct; // Only set upfront for 'stock_in'
  bool _loadingProducts = true;
  String _productSearch = '';

  final List<InwardScannedItem> _scannedItems = [];
  String _inwardUnitType = 'indoor'; // Used when scanning dual-serial in stock_in mode
  final TextEditingController _remarksController = TextEditingController();
  bool _submitting = false;
  bool _isHandlingScan = false;
  String? _inwardRequestId;

  @override
  void initState() {
    super.initState();
    _loadProducts();
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
        _loadProducts();
      }
    });
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final list = await _api.getProducts();
      if (mounted) {
        setState(() {
          _products = list;
          _loadingProducts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingProducts = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load models: $e')),
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
      _scannedItems.clear();
      _inwardUnitType = 'indoor';
      _stage = InwardStage.scanning;
    });
  }

  Future<bool> _handleWillPop() async {
    if (_stage == InwardStage.selectCase) {
      return true;
    }

    if (_stage == InwardStage.selectModel) {
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
          onScanned: (serial) => _handleScannedSerial(serial),
        ),
      ),
    );
  }

  Future<void> _handleScannedSerial(String serial) async {
    final cleanSerial = serial.trim();
    if (cleanSerial.isEmpty) return;

    if (_isHandlingScan) return;
    _isHandlingScan = true;

    try {
      // 1. Check duplicate in current session batch
      if (_scannedItems.any((it) => it.serialNumber == cleanSerial)) {
        HapticFeedback.heavyImpact();
        _showWarningDialog('Duplicate in Current Batch', 'Serial "$cleanSerial" is already scanned in this batch.');
        return;
      }

      // 2. Live validation against backend
      final String? reqProdId = _inwardType == 'stock_in' ? _selectedProduct?.id : null;
      final result = await _api.validateInwardSerial(
        reqProdId,
        cleanSerial,
        inwardType: _inwardType,
      );

      final bool isValid = result['is_valid'] ?? true;
      final String? message = result['message'];
      final bool requiresConfirmation = result['requires_confirmation'] == true;

      if (!isValid) {
        HapticFeedback.heavyImpact();
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

      // 3. Determine the Product
      Product? targetProduct;
      String? unitType;
      bool isAutoDetected = false;

      if (_inwardType == 'stock_in') {
        // Stock In: Model is fixed to the upfront selected model
        targetProduct = _selectedProduct;
        if (targetProduct != null && targetProduct.hasDualSerial) {
          unitType = _inwardUnitType;
        }
      } else {
        // Return or Damaged: Look up auto-detected model from backend response
        final registeredId = result['registered_model_id']?.toString();
        if (registeredId != null) {
          targetProduct = _findProductById(registeredId);
          if (targetProduct == null && result['model'] != null) {
            // Product not yet in memory list, construct instance from backend details
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

          // If dual serial model and unit_type not stored previously, ask user
          if (targetProduct != null && targetProduct.hasDualSerial && unitType == null) {
            unitType = await _showSelectUnitTypeDialog(cleanSerial, targetProduct);
            if (unitType == null) return; // User cancelled unit selection
          }
        } else {
          // "THE STRANGE CASE": Serial is NOT recorded in system!
          // Ask staff to select the model after scanning this serial!
          HapticFeedback.mediumImpact();
          final chosenProduct = await _showSelectModelForSerialDialog(cleanSerial);
          if (chosenProduct == null) {
            return; // Staff cancelled
          }
          targetProduct = chosenProduct;
          isAutoDetected = false;

          if (targetProduct.hasDualSerial) {
            unitType = await _showSelectUnitTypeDialog(cleanSerial, targetProduct);
            if (unitType == null) return;
          }
        }
      }

      if (targetProduct == null) {
        _showWarningDialog('Model Required', 'Could not assign a model for serial "$cleanSerial".');
        return;
      }

      // 4. Add to scanned items list
      setState(() {
        _scannedItems.insert(
          0,
          InwardScannedItem(
            serialNumber: cleanSerial,
            product: targetProduct!,
            unitType: unitType,
            isAutoDetected: isAutoDetected,
          ),
        );
      });
      HapticFeedback.lightImpact();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Scanned $cleanSerial • ${targetProduct.brand} ${targetProduct.model} (${_scannedItems.length} total)'),
            duration: const Duration(seconds: 2),
            backgroundColor: _getInwardTypeColor(_inwardType),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      _showWarningDialog('Validation Error', 'Failed to validate serial "$cleanSerial": $e');
    } finally {
      _isHandlingScan = false;
    }
  }

  // "Strange case" dialog: Prompt user to assign model for an unrecorded serial
  Future<Product?> _showSelectModelForSerialDialog(String serial) async {
    return showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        String filter = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _products.where((p) {
              final q = filter.toLowerCase();
              return p.name.toLowerCase().contains(q) ||
                  p.brand.toLowerCase().contains(q) ||
                  p.model.toLowerCase().contains(q) ||
                  (p.sku?.toLowerCase().contains(q) ?? false);
            }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        hintText: 'Search brand or model...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                      onChanged: (val) => setModalState(() => filter = val),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                      child: filtered.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('No models match your search.', style: TextStyle(color: Color(0xFF94A3B8))),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              separatorBuilder: (_, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                              itemBuilder: (ctx, idx) {
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
                                  onTap: () => Navigator.pop(ctx, p),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 10),
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
              ),
            );
          },
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accept & Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showWarningDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 13, height: 1.4)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inward batch saved to Offline Queue!')),
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
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final canPop = await _handleWillPop();
              if (canPop && mounted) {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(_getAppBarTitle(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          actions: [
            if (_stage == InwardStage.scanning) ...[
              if (_inwardType == 'stock_in')
                TextButton(
                  onPressed: () => setState(() => _stage = InwardStage.selectModel),
                  child: const Text('Change Model', style: TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.bold)),
                ),
              TextButton(
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
            ],
          ],
        ),
        body: _buildCurrentStageView(),
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
    return SingleChildScrollView(
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
                  onPressed: () => setState(() => _stage = InwardStage.selectCase),
                  child: const Text('Back', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
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
    return Column(
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
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E1B4B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 1,
              ),
              icon: const Icon(Icons.qr_code_scanner, size: 22),
              label: Text(
                _inwardType == 'stock_in'
                    ? 'Scan Barcode (${_selectedProduct?.model ?? ''})'
                    : 'Open Barcode Scanner (${_getInwardTypeShort(_inwardType)})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              onPressed: _openScanner,
            ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _scannedItems.length,
                  itemBuilder: (ctx, idx) {
                    final item = _scannedItems[idx];
                    return Dismissible(
                      key: Key('${item.serialNumber}_$idx'),
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
                        setState(() {
                          _scannedItems.removeAt(idx);
                        });
                      },
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
                                '#${_scannedItems.length - idx}',
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
    );
  }

  Widget _buildScanningHeader() {
    if (_inwardType == 'stock_in' && _selectedProduct != null) {
      final p = _selectedProduct!;
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
                  Text(
                    p.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
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
                '${_scannedItems.length} Scanned',
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
