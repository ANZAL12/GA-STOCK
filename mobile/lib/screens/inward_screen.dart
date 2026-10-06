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

  void _selectProduct(Product p) {
    setState(() {
      _selectedProduct = p;
      _scannedSerials.clear();
    });
  }

  void _openScanner() {
    if (_selectedProduct == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerWidget(
          title: 'Scan Inward: ${_selectedProduct!.model}',
          prompt: 'Scan barcode for ${_selectedProduct!.brand} ${_selectedProduct!.name}',
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
      final result = await _api.validateInwardSerial(_selectedProduct!.id, cleanSerial);
      final bool isValid = result['is_valid'] ?? true;
      final String? message = result['message'];

      if (!isValid) {
        HapticFeedback.heavyImpact();
        _showWarningDialog('Serial Validation Warning', message ?? 'This serial number cannot be registered.');
        return;
      }

      // Valid new serial
      setState(() {
        _scannedSerials.insert(0, cleanSerial);
      });
      HapticFeedback.lightImpact();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scanned: $cleanSerial (Total: ${_scannedSerials.length})'),
            duration: const Duration(seconds: 1),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      _showWarningDialog('Validation Error', 'Failed to validate serial "$cleanSerial": $e');
    }
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

  Future<void> _submitInwardBatch() async {
    if (_selectedProduct == null || _scannedSerials.isEmpty) return;

    setState(() => _submitting = true);

    try {
      final result = await _api.submitInwardBatch(
        productId: _selectedProduct!.id,
        serialNumbers: _scannedSerials,
        remarks: _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _submitting = false);

      final count = result['quantity'] ?? _scannedSerials.length;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF059669)),
              SizedBox(width: 8),
              Text('Inward Recorded!'),
            ],
          ),
          content: Text(
            'Successfully registered $count unit(s) of ${_selectedProduct!.name} into tracked godown inventory.',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      Navigator.pop(context);
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
            'remarks': _remarksController.text.trim(),
          },
          description: 'Inward: ${_selectedProduct!.name} (${_scannedSerials.length} units)',
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
                    onTap: () => _selectProduct(p),
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
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${p.currentStockQty} ${p.unit}s',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A)),
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
          child: Row(
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
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Text(
                  '${_scannedSerials.length} Scanned',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF065F46)),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1, color: Color(0xFFE2E8F0)),

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
                        setState(() => _scannedSerials.removeAt(idx));
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
                              '#${_scannedSerials.length - idx}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                serial,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16, color: Color(0xFF94A3B8)),
                              onPressed: () {
                                setState(() => _scannedSerials.removeAt(idx));
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
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: _submitting ? null : _submitInwardBatch,
                      child: _submitting
                          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                          : Text(
                              'Save Inward Batch (+${_scannedSerials.length} Stock)',
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
