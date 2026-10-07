import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/offline_queue_service.dart';
import '../services/websocket_service.dart';
import '../widgets/scanner_widget.dart';

class InwardScreen extends StatefulWidget {
  const InwardScreen({super.key});

  @override
  State<InwardScreen> createState() => _InwardScreenState();
}

class _InwardScreenState extends State<InwardScreen> {
  final ApiService _api = ApiService();
  final OfflineQueueService _queue = OfflineQueueService();
  StreamSubscription? _wsSubscription;

  List<Product> _products = [];
  Product? _selectedProduct;
  bool _loadingProducts = true;
  String _productSearch = '';

  final List<String> _scannedSerials = [];
  final Map<String, String> _scannedUnitTypes = {};
  String _inwardUnitType = 'indoor';
  String _inwardType = 'stock_in'; // 'stock_in', 'return', 'damaged'
  final TextEditingController _remarksController = TextEditingController();
  bool _submitting = false;

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

  void _showInwardCaseBottomSheet(Product p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
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
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.category_outlined, color: Color(0xFF4F46E5), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${p.brand} • ${p.model}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'SELECT INWARD CASE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 12),
              _buildCaseOption(
                ctx: ctx,
                product: p,
                caseType: 'stock_in',
                title: 'Stock In (Direct from Company)',
                subtitle: 'Fresh units received from company. Adds to sellable stock.',
                icon: Icons.local_shipping_outlined,
                accentColor: const Color(0xFF4F46E5),
                bgColor: const Color(0xFFEEF2FF),
                badgeText: 'New Stock',
              ),
              const SizedBox(height: 10),
              _buildCaseOption(
                ctx: ctx,
                product: p,
                caseType: 'return',
                title: 'Returned Product',
                subtitle: 'Customer or dealer return. Restores stock & frees serial for next dispatch.',
                icon: Icons.assignment_return_outlined,
                accentColor: const Color(0xFF059669),
                bgColor: const Color(0xFFECFDF5),
                badgeText: 'Restores Stock',
              ),
              const SizedBox(height: 10),
              _buildCaseOption(
                ctx: ctx,
                product: p,
                caseType: 'damaged',
                title: 'Damaged Product',
                subtitle: 'Damaged or defective unit. Logged as damaged; does NOT increase sellable stock.',
                icon: Icons.report_problem_outlined,
                accentColor: const Color(0xFFD97706),
                bgColor: const Color(0xFFFFFBEB),
                badgeText: 'Non-Sellable',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCaseOption({
    required BuildContext ctx,
    required Product product,
    required String caseType,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color bgColor,
    required String badgeText,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          Navigator.pop(ctx);
          _selectProduct(product, caseType);
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accentColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
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

  void _selectProduct(Product p, [String inwardType = 'stock_in']) {
    setState(() {
      _selectedProduct = p;
      _inwardType = inwardType;
      _scannedSerials.clear();
      _scannedUnitTypes.clear();
      _inwardUnitType = 'indoor';
    });
  }

  void _openScanner() {
    if (_selectedProduct == null) return;

    final shortType = _getInwardTypeShort(_inwardType);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerWidget(
          title: 'Scan $shortType: ${_selectedProduct!.model}',
          prompt: 'Scan barcode for ${_selectedProduct!.brand} ${_selectedProduct!.name} ($shortType)',
          initialLastScanned: _scannedSerials.isNotEmpty ? _scannedSerials.first : null,
          initialCount: _scannedSerials.length,
          onScanned: (serial) => _handleScannedSerial(serial),
        ),
      ),
    );
  }

  Future<void> _handleScannedSerial(String serial) async {
    final cleanSerial = serial.trim();
    if (cleanSerial.isEmpty) return;

    // Check duplicate in current batch
    if (_scannedSerials.contains(cleanSerial)) {
      HapticFeedback.heavyImpact();
      _showWarningDialog('Duplicate in Current Batch', 'Serial "$cleanSerial" is already in this batch.');
      return;
    }

    // Live validation against backend
    try {
      final result = await _api.validateInwardSerial(
        _selectedProduct!.id,
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

      // Valid serial to add
      setState(() {
        _scannedSerials.insert(0, cleanSerial);
        if (_selectedProduct!.hasDualSerial) {
          _scannedUnitTypes[cleanSerial] = _inwardUnitType;
        }
      });
      HapticFeedback.lightImpact();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scanned: $cleanSerial (Total: ${_scannedSerials.length})'),
            duration: const Duration(seconds: 1),
            backgroundColor: _getInwardTypeColor(_inwardType),
          ),
        );
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      _showWarningDialog('Validation Error', 'Failed to validate serial "$cleanSerial": $e');
    }
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
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
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
    if (_selectedProduct == null || _scannedSerials.isEmpty) return;

    // Strict validation: For dual-serial models, indoor and outdoor counts must match!
    if (_selectedProduct!.hasDualSerial) {
      final indoorCount = _scannedSerials.where((s) => _scannedUnitTypes[s] == 'indoor').length;
      final outdoorCount = _scannedSerials.where((s) => _scannedUnitTypes[s] == 'outdoor').length;
      if (indoorCount != outdoorCount) {
        HapticFeedback.heavyImpact();
        _showWarningDialog(
          'Count Mismatch: Cannot Store',
          'Dual-serial model "${_selectedProduct!.name}" requires equal numbers of Indoor and Outdoor units.\n\n'
          '• Indoor units: $indoorCount\n'
          '• Outdoor units: $outdoorCount\n\n'
          '${indoorCount > outdoorCount ? "Please scan ${indoorCount - outdoorCount} more Outdoor unit(s)." : "Please scan ${outdoorCount - indoorCount} more Indoor unit(s)."}\n\n'
          'Batch cannot be saved until Indoor and Outdoor counts match.',
        );
        return;
      }
    }

    _showInwardConfirmationDialog();
  }

  Future<void> _showInwardConfirmationDialog() async {
    final p = _selectedProduct!;
    final totalCount = _scannedSerials.length;
    final isDual = p.hasDualSerial;
    final indoorCount = isDual ? _scannedSerials.where((s) => _scannedUnitTypes[s] == 'indoor').length : 0;
    final outdoorCount = isDual ? _scannedSerials.where((s) => _scannedUnitTypes[s] == 'outdoor').length : 0;
    final pairCount = isDual ? indoorCount : totalCount;

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
                            'Review the batch summary before saving',
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

                // Model Information Card
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
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getInwardTypeBgColor(_inwardType),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _getInwardTypeColor(_inwardType).withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_getInwardTypeIcon(_inwardType), size: 13, color: _getInwardTypeColor(_inwardType)),
                                const SizedBox(width: 4),
                                Text(
                                  _getInwardTypeShort(_inwardType),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _getInwardTypeColor(_inwardType),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      if (isDual) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Complete Pairs:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                            Text('$pairCount Sets (${p.unit}s)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _getInwardTypeColor(_inwardType))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFC7D2FE)),
                                ),
                                child: Text(
                                  '$indoorCount Indoor Units',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF3C3489)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDFA),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF99F6E4)),
                                ),
                                child: Text(
                                  '$outdoorCount Outdoor Units',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0D9488)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Quantity:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                            Text('$totalCount ${p.unit}s', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _getInwardTypeColor(_inwardType))),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
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
                              ? '⚠️ Stored as damaged units. Does NOT increase sellable stock.'
                              : _inwardType == 'return'
                                  ? '✓ Restores +$pairCount ${p.unit}s to stock & frees serials for next dispatch.'
                                  : '✓ Adds +$pairCount ${p.unit}s of brand new stock to inventory.',
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

                // Optional remarks with plenty of width
                TextField(
                  controller: _remarksController,
                  decoration: InputDecoration(
                    labelText: 'Batch Remarks (Optional)',
                    hintText: _inwardType == 'damaged'
                        ? 'e.g. Reason for damage, transit fault...'
                        : _inwardType == 'return'
                            ? 'e.g. Customer return reason...'
                            : 'e.g. PO reference, supplier invoice...',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _getInwardTypeColor(_inwardType), width: 1.5)),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 18),

                // Action buttons side-by-side
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
    if (_selectedProduct == null || _scannedSerials.isEmpty) return;

    setState(() => _submitting = true);

    try {
      final result = await _api.submitInwardBatch(
        productId: _selectedProduct!.id,
        serialNumbers: _scannedSerials,
        unitTypes: _selectedProduct!.hasDualSerial ? _scannedUnitTypes : null,
        inwardType: _inwardType,
        remarks: _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _submitting = false);

      final count = result['quantity'] ?? _scannedSerials.length;
      final String successTitle = _inwardType == 'damaged'
          ? 'Damaged Units Recorded!'
          : _inwardType == 'return'
              ? 'Return Processed!'
              : 'Inward Recorded!';
      final String successMsg = _inwardType == 'damaged'
          ? 'Successfully marked $count unit(s) of ${_selectedProduct!.name} as damaged.'
          : _inwardType == 'return'
              ? 'Successfully processed $count returned unit(s). They are restored to stock and freed for future dispatch.'
              : 'Successfully registered $count unit(s) of ${_selectedProduct!.name} into tracked godown inventory.';

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

      // Offer offline queuing if network failed
      final queueOffline = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Connection Problem'),
          content: Text(
            'Submission failed: ${e.toString().replaceAll("Exception: ", "")}\n\nWould you like to store this batch in the local Offline Queue and sync when Wi-Fi is restored?',
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
          type: QueueType.inward,
          createdAt: DateTime.now(),
          payload: {
            'product_id': _selectedProduct!.id,
            'serial_numbers': _scannedSerials,
            if (_selectedProduct!.hasDualSerial) 'unit_types': _scannedUnitTypes,
            'inward_type': _inwardType,
            'remarks': _remarksController.text.trim(),
          },
          description: '${_getInwardTypeTitle(_inwardType)}: ${_selectedProduct!.name} (${_scannedSerials.length} units)',
        );
        await _queue.enqueue(batch);
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF0F172A),
        title: const Text('Inward Stock Scan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (_selectedProduct != null)
            TextButton(
              onPressed: () => setState(() => _selectedProduct = null),
              child: const Text('Change Model', style: TextStyle(color: Color(0xFF3C3489), fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _selectedProduct == null ? _buildModelSelector() : _buildScanningView(),
    );
  }

  // STEP 1: Select Model
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
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Color(0xFF3C3489)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Step 1: Select the appliance model being received before scanning serials.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF3C3489), fontWeight: FontWeight.w600),
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
                    onTap: () => _showInwardCaseBottomSheet(p),
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
                                      'Dual Serial (In/Out)',
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

  // STEP 2: Scanning & Review View
  Widget _buildScanningView() {
    final p = _selectedProduct!;

    return Column(
      children: [
        // Active model card
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                          p.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${p.brand} • Model: ${p.model}',
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
                      '${_scannedSerials.length} Scanned',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _getInwardTypeColor(_inwardType)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _getInwardTypeBgColor(_inwardType),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _getInwardTypeColor(_inwardType).withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    Icon(_getInwardTypeIcon(_inwardType), size: 15, color: _getInwardTypeColor(_inwardType)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _getInwardTypeTitle(_inwardType),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _getInwardTypeColor(_inwardType),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _showInwardCaseBottomSheet(p),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          'Switch Case',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _getInwardTypeColor(_inwardType),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1, color: Color(0xFFE2E8F0)),

        // Dual Serial Toggle (Indoor / Outdoor)
        if (p.hasDualSerial)
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
                            color: _inwardUnitType == 'indoor'
                                ? const Color(0xFF3C3489)
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Indoor Unit',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _inwardUnitType == 'indoor'
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: _inwardUnitType == 'indoor'
                                  ? const Color(0xFF3C3489)
                                  : const Color(0xFF64748B),
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
                            color: _inwardUnitType == 'outdoor'
                                ? const Color(0xFF0D9488)
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Outdoor Unit',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _inwardUnitType == 'outdoor'
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: _inwardUnitType == 'outdoor'
                                  ? const Color(0xFF0D9488)
                                  : const Color(0xFF64748B),
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
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E1B4B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 1,
                    ),
                    icon: const Icon(Icons.qr_code_scanner, size: 22),
                    label: const Text('Open Barcode Scanner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    onPressed: _openScanner,
                  ),
                ),
              ),
            ],
          ),
        ),

        // List of scanned serials
        Expanded(
          child: _scannedSerials.isEmpty
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
                      const Text(
                        'Tap the button above to begin scanning appliances.',
                        style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _scannedSerials.length,
                  itemBuilder: (ctx, idx) {
                    final serial = _scannedSerials[idx];
                    return Dismissible(
                      key: Key(serial),
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
                          final removed = _scannedSerials.removeAt(idx);
                          _scannedUnitTypes.remove(removed);
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '#${_scannedSerials.length - idx}',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                serial,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: 0.5,
                                ),
                                softWrap: true,
                              ),
                            ),
                            if (_scannedUnitTypes[serial] != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _scannedUnitTypes[serial] == 'indoor'
                                      ? const Color(0xFFEEF2FF)
                                      : const Color(0xFFF0FDFA),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _scannedUnitTypes[serial] == 'indoor'
                                        ? const Color(0xFFC7D2FE)
                                        : const Color(0xFF99F6E4),
                                  ),
                                ),
                                child: Text(
                                  _scannedUnitTypes[serial] == 'indoor' ? 'Indoor' : 'Outdoor',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _scannedUnitTypes[serial] == 'indoor'
                                        ? const Color(0xFF3C3489)
                                        : const Color(0xFF0D9488),
                                  ),
                                ),
                              ),
                            ],
                            IconButton(
                              icon: const Icon(Icons.close, size: 16, color: Color(0xFF94A3B8)),
                              onPressed: () {
                                setState(() {
                                  final removed = _scannedSerials.removeAt(idx);
                                  _scannedUnitTypes.remove(removed);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Bottom submit section
        if (_scannedSerials.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
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
                                  ? 'Save Damaged Batch (${_scannedSerials.length} Units)'
                                  : _inwardType == 'return'
                                      ? 'Save Returned Batch (+${_scannedSerials.length} Stock)'
                                      : 'Save Inward Batch (+${_scannedSerials.length} Stock)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
