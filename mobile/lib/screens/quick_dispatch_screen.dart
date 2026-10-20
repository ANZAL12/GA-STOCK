import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/hardware_scanner_service.dart';
import '../services/offline_manager.dart';
import '../widgets/responsive_utils.dart';
import '../widgets/scanner_widget.dart';
import '../widgets/top_toast.dart';
import '../widgets/offline_banner.dart';
import 'print_bill_screen.dart';

class QuickScanItem {
  final int sequenceNumber;
  final String serialNumber;
  final String productId;
  final String modelName;
  final String brand;
  final String? unitType;
  final bool isMatched;

  QuickScanItem({
    required this.sequenceNumber,
    required this.serialNumber,
    required this.productId,
    required this.modelName,
    required this.brand,
    this.unitType,
    required this.isMatched,
  });
}

class QuickDispatchScreen extends StatefulWidget {
  const QuickDispatchScreen({super.key});

  @override
  State<QuickDispatchScreen> createState() => _QuickDispatchScreenState();
}

class _QuickDispatchScreenState extends State<QuickDispatchScreen> {
  final ApiService _api = ApiService();
  VoidCallback? _scannerSub;

  List<Shop> _shops = [];
  Shop? _selectedShop;
  String _shopSearch = '';
  bool _loadingShops = true;

  List<Product> _products = [];
  final Map<String, Product> _productById = {};

  final List<QuickScanItem> _scannedItems = [];
  final Set<String> _scannedSerialSet = <String>{};
  final Set<String> _inFlightSerials = <String>{};
  int _sequenceCounter = 0;
  String? _lastScanFeedback;
  String _activeFilterModel = 'ALL';

  final TextEditingController _manualController = TextEditingController();
  final TextEditingController _billNumberController = TextEditingController();
  final TextEditingController _deliveryRefController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  final FocusNode _billNumberFocus = FocusNode();
  final FocusNode _deliveryRefFocus = FocusNode();
  final FocusNode _remarksFocus = FocusNode();

  bool _isSubmitting = false;

  void _indexProducts(List<Product> prods) {
    _products = prods;
    _productById.clear();
    for (final p in prods) {
      _productById[p.id.toLowerCase()] = p;
    }
  }

  @override
  void initState() {
    super.initState();
    final cachedShops = _api.cachedShops;
    final cachedProds = _api.cachedProducts;
    if (cachedShops != null && cachedShops.isNotEmpty) {
      _shops = List<Shop>.from(cachedShops);
      _loadingShops = false;
    }
    if (cachedProds != null && cachedProds.isNotEmpty) {
      _indexProducts(cachedProds);
    }
    _loadMetadata();

    _scannerSub = HardwareScannerService().registerListener((barcode) {
      if (!mounted) return;
      if (_selectedShop == null) {
        _showToast('Select a shop first', const Color(0xFFD97706));
        return;
      }
      _handleQuickScan(barcode);
    });
  }

  @override
  void dispose() {
    _scannerSub?.call();
    _manualController.dispose();
    _billNumberController.dispose();
    _deliveryRefController.dispose();
    _remarksController.dispose();
    _billNumberFocus.dispose();
    _deliveryRefFocus.dispose();
    _remarksFocus.dispose();
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    try {
      final s = await _api.getShops();
      final p = await _api.getProducts();
      if (mounted) {
        setState(() {
          _shops = s;
          _indexProducts(p);
          _loadingShops = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingShops = false;
        });
      }
    }
  }

  void _showToast(String message, Color bgColor) {
    TopToast.show(
      context,
      message: message,
      backgroundColor: bgColor,
    );
  }

  Future<bool> _handleQuickScan(String serial) async {
    final cleanSerial = serial.trim().toUpperCase();
    if (cleanSerial.isEmpty) return false;

    if (_scannedSerialSet.contains(cleanSerial) ||
        _inFlightSerials.contains(cleanSerial)) {
      HapticFeedback.heavyImpact();
      _showToast('Duplicate: $cleanSerial already scanned', const Color(0xFFE11D48));
      return false;
    }

    _inFlightSerials.add(cleanSerial);

    try {
      final res = await _api.checkOutwardSerial(null, cleanSerial);

      final bool isBlocked = res['is_blocked'] == true ||
          res['is_dispatched'] == true ||
          res['can_dispatch'] == false ||
          res['case'] == 0 ||
          res['badge'] == 'blocked';
      final String? msg = res['message'];

      if (isBlocked) {
        HapticFeedback.heavyImpact();
        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Already Dispatched', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
              content: Text(msg ?? 'Serial "$cleanSerial" has already been dispatched and cannot be scanned again.'),
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
        return false;
      }

      final dynamic caseVal = res['case'];
      final String caseName = (res['case_name'] ?? '').toString();
      final bool isMatched = res['is_matched'] == true || caseVal == 1 || caseName == 'matched' || caseVal == 3 || caseName == 'status_warning';
      final String? regProdId = res['registered_product_id'];
      final String? regModelName = res['registered_model_name'];
      final String? regUnitType = res['unit_type'];

      final bool isDamaged = res['is_damaged'] == true ||
          (res['current_status'] ?? '').toString().toLowerCase() == 'damaged' ||
          (res['message'] ?? '').toString().toLowerCase().contains('damaged');

      if (isDamaged) {
        HapticFeedback.heavyImpact();
        if (mounted) {
          final bool proceed = await _showDamagedConfirmationDialog(cleanSerial, regModelName);
          if (!proceed) {
            return false;
          }
        } else {
          return false;
        }
      }

      if (isMatched && regProdId != null) {
        Product? product = _productById[regProdId.toLowerCase()];

        final prodId = product?.id ?? regProdId;
        final brand = product?.brand ?? '';
        final model = regModelName ?? product?.model ?? 'Matched Unit';

        _sequenceCounter++;
        final newItem = QuickScanItem(
          sequenceNumber: _sequenceCounter,
          serialNumber: cleanSerial,
          productId: prodId,
          modelName: model,
          brand: brand,
          unitType: regUnitType,
          isMatched: true,
        );

        setState(() {
          _scannedSerialSet.add(cleanSerial);
          _scannedItems.insert(0, newItem);
          _lastScanFeedback = '✓ Matched: $cleanSerial ($model)';
        });

        HapticFeedback.lightImpact();
        return true;
      } else {
        // Serial not in system -> Prompt user to select model
        HapticFeedback.mediumImpact();
        if (mounted) {
          return await _promptSelectModelForNewSerial(cleanSerial);
        }
        return false;
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      _showToast('Check error: $e', const Color(0xFFE11D48));
      return false;
    } finally {
      _inFlightSerials.remove(cleanSerial);
    }
  }

  Future<bool> _showDamagedConfirmationDialog(String serial, String? modelName) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 26),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Damaged Product',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
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
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    serial,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                  if (modelName != null && modelName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      modelName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'This item is damaged. Are you sure you want to add?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
                height: 1.4,
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
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Add', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _promptSelectModelForNewSerial(String serial) async {
    String search = '';
    Product? chosenProduct;
    String chosenUnitType = 'indoor';

    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final isTablet = context.isTablet;
          final filtered = _products.where((p) {
            final q = search.toLowerCase();
            return p.name.toLowerCase().contains(q) ||
                p.brand.toLowerCase().contains(q) ||
                p.model.toLowerCase().contains(q);
          }).toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(isTablet ? 24 : 18)),
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
                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Text(
                          serial,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Select Model for Serial',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16, vertical: 6),
                  child: TextField(
                    autofocus: false,
                    decoration: InputDecoration(
                      hintText: 'Search brand or model...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    onChanged: (val) => setModalState(() => search = val),
                  ),
                ),
                if (chosenProduct != null && chosenProduct!.hasDualSerial)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16, vertical: 6),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Text('Unit Type:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(width: 12),
                          ChoiceChip(
                            label: const Text('Indoor'),
                            selected: chosenUnitType == 'indoor',
                            selectedColor: const Color(0xFF3C3489),
                            labelStyle: TextStyle(
                              color: chosenUnitType == 'indoor' ? Colors.white : const Color(0xFF334155),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: (val) {
                              if (val) setModalState(() => chosenUnitType = 'indoor');
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Outdoor'),
                            selected: chosenUnitType == 'outdoor',
                            selectedColor: const Color(0xFF0D9488),
                            labelStyle: TextStyle(
                              color: chosenUnitType == 'outdoor' ? Colors.white : const Color(0xFF334155),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: (val) {
                              if (val) setModalState(() => chosenUnitType = 'outdoor');
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16, vertical: 8),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (c, i) {
                      final p = filtered[i];
                      final isSelected = chosenProduct?.id == p.id;
                      return ListTile(
                        tileColor: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0),
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        title: Text(
                          '${p.brand} ${p.model}',
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          p.name,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: Color(0xFF4F46E5), size: 22)
                            : const Icon(Icons.chevron_right, color: Color(0xFF94A3B8), size: 20),
                        onTap: () {
                          if (p.hasDualSerial) {
                            setModalState(() => chosenProduct = p);
                          } else {
                            Navigator.pop(ctx, p);
                          }
                        },
                      );
                    },
                  ),
                ),
                if (chosenProduct != null && chosenProduct!.hasDualSerial)
                  Padding(
                    padding: EdgeInsets.all(isTablet ? 24 : 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(ctx, chosenProduct),
                        child: Text(
                          'Confirm ${chosenProduct!.model} ($chosenUnitType)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );

    if (result is Product && mounted) {
      final p = result;
      _sequenceCounter++;
      final newItem = QuickScanItem(
        sequenceNumber: _sequenceCounter,
        serialNumber: serial,
        productId: p.id,
        modelName: '${p.brand} ${p.model}'.trim(),
        brand: p.brand,
        unitType: p.hasDualSerial ? chosenUnitType : null,
        isMatched: false,
      );
      setState(() {
        _scannedSerialSet.add(serial);
        _scannedItems.insert(0, newItem);
        _lastScanFeedback = '✓ Added: $serial (${p.model})';
      });
      return true;
    }
    return false;
  }

  void _openCameraScanner() {
    if (_selectedShop == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerWidget(
          title: 'Quick Dispatch: ${_selectedShop!.name}',
          prompt: 'Scan serials directly',
          initialLastScanned: _scannedItems.isNotEmpty ? _scannedItems.first.serialNumber : null,
          initialCount: _scannedItems.length,
          itemCountProvider: () => _scannedItems.length,
          existingSerials: Set<String>.from(_scannedSerialSet),
          isDuplicate: (s) =>
              _scannedSerialSet.contains(s.trim().toUpperCase()) ||
              _inFlightSerials.contains(s.trim().toUpperCase()),
          onScanned: (serial) => _handleQuickScan(serial),
        ),
      ),
    );
  }

  Future<void> _submitDispatch() async {
    if (_scannedItems.isEmpty || _selectedShop == null) return;

    // Strict validation: For every dual-serial model, indoor and outdoor counts must match!
    final Map<String, List<QuickScanItem>> byProduct = {};
    for (var item in _scannedItems) {
      byProduct.putIfAbsent(item.productId, () => []).add(item);
    }

    final List<String> mismatchMessages = [];
    for (final entry in byProduct.entries) {
      final items = entry.value;
      final product = _productById[entry.key.toLowerCase()];
      final hasDual = product?.hasDualSerial == true || items.any((i) => i.unitType != null);
      if (hasDual) {
        final indoorCount = items.where((i) => i.unitType == 'indoor').length;
        final outdoorCount = items.where((i) => i.unitType == 'outdoor').length;
        if (indoorCount != outdoorCount) {
          final modelName = items.first.modelName;
          final diff = (indoorCount - outdoorCount).abs();
          final missingType = indoorCount > outdoorCount ? 'Outdoor' : 'Indoor';
          mismatchMessages.add(
            '$modelName:\n• Indoor: $indoorCount units\n• Outdoor: $outdoorCount units\n→ Missing $diff $missingType unit${diff > 1 ? "s" : ""}',
          );
        }
      }
    }

    if (mismatchMessages.isNotEmpty) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 24),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Indoor / Outdoor Mismatch',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dual-serial AC models require matching Indoor and Outdoor units before dispatch:',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                  ...mismatchMessages.map(
                    (msg) => Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Text(
                        msg,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // Temporarily pause hardware scanner key interception while typing in modal
    HardwareScannerService().isEnabled = false;

    bool? confirmed;
    try {
      confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(context.isTablet ? 24 : 18)),
        ),
        builder: (ctx) {
          final isTablet = context.isTablet;
          final Map<String, int> modelCounts = {};
          for (var item in _scannedItems) {
            modelCounts[item.modelName] = (modelCounts[item.modelName] ?? 0) + 1;
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.88,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Confirm Dispatch',
                          style: TextStyle(
                            fontSize: isTablet ? 20 : 17,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx, false),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(isTablet ? 24 : 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Image.asset(
                                  'assets/images/shop_icon.png',
                                  width: 24,
                                  height: 24,
                                  fit: BoxFit.contain,
                                  errorBuilder: (c, e, s) => const Icon(Icons.storefront, size: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _selectedShop!.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                                Text(
                                  '${_scannedItems.length} units',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Bounded breakdown summary with internal scrolling
                          Container(
                            constraints: BoxConstraints(
                              maxHeight: isTablet ? 180 : 130,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAFAFA),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              itemCount: modelCounts.length,
                              separatorBuilder: (_, _) => const Divider(height: 10, color: Color(0xFFE2E8F0)),
                              itemBuilder: (ctx, i) {
                                final entry = modelCounts.entries.elementAt(i);
                                final itemsOfModel = _scannedItems.where((e) => e.modelName == entry.key);
                                final hasDual = itemsOfModel.any((e) => e.unitType != null);
                                final inCount = hasDual ? itemsOfModel.where((e) => e.unitType == 'indoor').length : 0;
                                final outCount = hasDual ? itemsOfModel.where((e) => e.unitType == 'outdoor').length : 0;

                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.key,
                                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (hasDual) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              '$inCount In / $outCount Out',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: inCount == outCount ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      hasDual ? '$inCount Pairs' : '${entry.value} pcs',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _billNumberController,
                            focusNode: _billNumberFocus,
                            textCapitalization: TextCapitalization.characters,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.next,
                            onTap: () {
                              SystemChannels.textInput.invokeMethod('TextInput.show');
                            },
                            decoration: InputDecoration(
                              labelText: 'Bill / Invoice Number (Optional)',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _deliveryRefController,
                            focusNode: _deliveryRefFocus,
                            textCapitalization: TextCapitalization.characters,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.next,
                            onTap: () {
                              SystemChannels.textInput.invokeMethod('TextInput.show');
                            },
                            decoration: InputDecoration(
                              labelText: 'Vehicle / Ref (Optional)',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _remarksController,
                            focusNode: _remarksFocus,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.done,
                            onTap: () {
                              SystemChannels.textInput.invokeMethod('TextInput.show');
                            },
                            decoration: InputDecoration(
                              labelText: 'Remarks (Optional)',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E1B4B),
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: isTablet ? 18 : 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(
                                'Dispatch ${_scannedItems.length} Units',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      HardwareScannerService().isEnabled = true;
    }

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    final Map<String, List<QuickScanItem>> grouped = {};
    for (var item in _scannedItems) {
      grouped.putIfAbsent(item.productId, () => []).add(item);
    }

    final itemsPayload = grouped.entries.map((entry) {
      return {
        'product_id': entry.key,
        'serials': entry.value.map((s) => {
          'serial_number': s.serialNumber,
          'confirmed_warning': true,
          if (s.unitType != null) 'unit_type': s.unitType,
        }).toList(),
        'unit_types': {
          for (var s in entry.value)
            if (s.unitType != null) s.serialNumber: s.unitType!
        },
      };
    }).toList();

    final dispatchPayload = {
      'shop_id': _selectedShop!.id,
      'items': itemsPayload,
      'bill_number': _billNumberController.text.trim().isNotEmpty ? _billNumberController.text.trim() : null,
      'delivery_reference': _deliveryRefController.text.trim().isNotEmpty ? _deliveryRefController.text.trim() : null,
      'remarks': _remarksController.text.trim().isNotEmpty ? _remarksController.text.trim() : null,
      'client_request_id': 'offline_${DateTime.now().millisecondsSinceEpoch}',
    };

    if (!OfflineManager().isOnline) {
      await OfflineManager().queueDispatch(dispatchPayload);
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _scannedItems.clear();
        _scannedSerialSet.clear();
      });
      _showToast('Offline: Dispatch queued. Will auto-sync when online.', const Color(0xFFD97706));
      Navigator.pop(context);
      return;
    }

    try {
      final res = await _api.submitOutwardMultiBatch(
        shopId: _selectedShop!.id,
        items: itemsPayload,
        billNumber: _billNumberController.text.trim().isNotEmpty ? _billNumberController.text.trim() : null,
        deliveryReference: _deliveryRefController.text.trim().isNotEmpty ? _deliveryRefController.text.trim() : null,
        remarks: _remarksController.text.trim().isNotEmpty ? _remarksController.text.trim() : null,
      );

      final String? billNum = res['bill_number'];
      if (!mounted) return;

      if (billNum != null && billNum.isNotEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => BillDetailScreen(billNumber: billNum)),
        );
      } else {
        Navigator.pop(context);
        _showToast('Dispatch submitted successfully', const Color(0xFF059669));
      }
    } catch (e) {
      if (mounted) {
        final errStr = e.toString().toLowerCase();
        final isNetError = !OfflineManager().isOnline ||
            errStr.contains('cannot reach server') ||
            errStr.contains('connection') ||
            errStr.contains('socketexception') ||
            errStr.contains('timeout');

        if (isNetError) {
          OfflineManager().markOffline();
          await OfflineManager().queueDispatch(dispatchPayload);
          if (mounted) {
            setState(() {
              _isSubmitting = false;
              _scannedItems.clear();
              _scannedSerialSet.clear();
            });
            _showToast('Saved to offline queue. Will auto-sync when connected.', const Color(0xFFD97706));
            Navigator.pop(context);
          }
          return;
        }

        setState(() => _isSubmitting = false);
        _showToast('Submission failed: $e', const Color(0xFFE11D48));
      }
    }
  }

  Future<bool?> _showClearConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Clear All Scanned Items?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        content: Text(
          'This will remove all ${_scannedItems.length} scanned serials from this session.',
          style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = context.isTablet;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: isTablet ? 68 : 56,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF0F172A),
        title: Text(
          'Quick Dispatch Scan',
          style: TextStyle(
            fontSize: isTablet ? 18 : 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_selectedShop != null || _scannedItems.isNotEmpty)
            TextButton(
              onPressed: () async {
                if (_scannedItems.isNotEmpty) {
                  final confirm = await _showClearConfirmationDialog();
                  if (confirm != true) return;
                }
                setState(() {
                  _selectedShop = null;
                  _scannedItems.clear();
                  _scannedSerialSet.clear();
                  _sequenceCounter = 0;
                  _lastScanFeedback = null;
                  _activeFilterModel = 'ALL';
                });
              },
              child: const Text('Reset', style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: _selectedShop == null ? _buildShopSelector() : _buildScanView(),
          ),
        ],
      ),
    );
  }

  Widget _buildShopSelector() {
    if (_loadingShops) return const Center(child: CircularProgressIndicator());

    final filtered = _shops.where((s) {
      final q = _shopSearch.toLowerCase();
      return s.name.toLowerCase().contains(q) || s.city.toLowerCase().contains(q);
    }).toList();

    return Padding(
      padding: EdgeInsets.all(context.isTablet ? 24 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search dealer shop or city...',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                    onTap: () => setState(() => _selectedShop = s),
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
                              errorBuilder: (ctx, err, stack) => const Icon(Icons.storefront, color: Color(0xFF3C3489)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                                ),
                                if (s.city.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(s.city.trim(), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
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

  Widget _buildScanView() {
    final isTablet = context.isTablet;

    final Map<String, int> modelCounts = {};
    for (var item in _scannedItems) {
      modelCounts[item.modelName] = (modelCounts[item.modelName] ?? 0) + 1;
    }

    if (_activeFilterModel != 'ALL' && !modelCounts.containsKey(_activeFilterModel)) {
      _activeFilterModel = 'ALL';
    }

    final displayedItems = _activeFilterModel == 'ALL'
        ? _scannedItems
        : _scannedItems.where((e) => e.modelName == _activeFilterModel).toList();

    return Column(
      children: [
        // Shop banner
        Container(
          color: Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 24 : 16,
            vertical: isTablet ? 14 : 10,
          ),
          child: Row(
            children: [
              Image.asset(
                'assets/images/shop_icon.png',
                width: isTablet ? 28 : 22,
                height: isTablet ? 28 : 22,
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Icon(Icons.storefront, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedShop!.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isTablet ? 16 : 14,
                        color: const Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_selectedShop!.city.trim().isNotEmpty)
                      Text(
                        _selectedShop!.city.trim(),
                        style: TextStyle(fontSize: isTablet ? 12 : 11, color: const Color(0xFF64748B)),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _selectedShop = null),
                child: const Text('Change Shop', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),

        const Divider(height: 1, color: Color(0xFFE2E8F0)),

        // Scanning controls
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 24 : 16,
            vertical: isTablet ? 14 : 10,
          ),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(vertical: isTablet ? 18 : 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _openCameraScanner,
                  icon: const Icon(Icons.qr_code_scanner, size: 20),
                  label: Text(
                    'Continuous Camera Scan',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: isTablet ? 16 : 14),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Or enter serial manually...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                      ),
                      onSubmitted: (val) {
                        _handleQuickScan(val);
                        _manualController.clear();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      _handleQuickScan(_manualController.text);
                      _manualController.clear();
                    },
                    child: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Real-time scan feedback banner
        if (_lastScanFeedback != null)
          Container(
            width: double.infinity,
            margin: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16, vertical: 2),
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

        // Model Filter Tabs Bar (All filter + Model chips)
        if (modelCounts.length > 1)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 4, bottom: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16),
              child: Row(
                children: [
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text('All (${_scannedItems.length})'),
                    selected: _activeFilterModel == 'ALL',
                    selectedColor: const Color(0xFF1E1B4B),
                    labelStyle: TextStyle(
                      fontSize: isTablet ? 12 : 11,
                      fontWeight: FontWeight.bold,
                      color: _activeFilterModel == 'ALL' ? Colors.white : const Color(0xFF475569),
                    ),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: _activeFilterModel == 'ALL' ? const Color(0xFF1E1B4B) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _activeFilterModel = 'ALL');
                    },
                  ),
                  const SizedBox(width: 6),
                  ...modelCounts.entries.map((entry) {
                    final isSelected = _activeFilterModel == entry.key;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text('${entry.key} (${entry.value})'),
                        selected: isSelected,
                        selectedColor: const Color(0xFF4F46E5),
                        labelStyle: TextStyle(
                          fontSize: isTablet ? 12 : 11,
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
                          setState(() => _activeFilterModel = val ? entry.key : 'ALL');
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

        // Scanned list header
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _activeFilterModel == 'ALL'
                    ? 'Scanned Items (${_scannedItems.length})'
                    : 'Scanned Items (${displayedItems.length} / ${_scannedItems.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569)),
              ),
              if (_scannedItems.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final confirm = await _showClearConfirmationDialog();
                    if (confirm == true) {
                      setState(() {
                        _scannedItems.clear();
                        _scannedSerialSet.clear();
                        _sequenceCounter = 0;
                        _lastScanFeedback = null;
                        _activeFilterModel = 'ALL';
                      });
                    }
                  },
                  child: const Text('Clear All', style: TextStyle(color: Color(0xFFDC2626), fontSize: 12)),
                ),
            ],
          ),
        ),

        // Scanned List (Virtualised & RepaintBounded)
        Expanded(
          child: _scannedItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bolt, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 8),
                      const Text(
                        'Pull scanner trigger or tap Continuous Scan',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  key: const PageStorageKey('quick_dispatch_scanned_list'),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16, vertical: 4),
                  itemCount: displayedItems.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (ctx, idx) {
                    final item = displayedItems[idx];
                    return RepaintBoundary(
                      key: ValueKey(item.serialNumber),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
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
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.serialNumber,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            item.modelName,
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (item.unitType != null) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: item.unitType == 'indoor' ? const Color(0xFFEEF2FF) : const Color(0xFFF0FDFA),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              item.unitType == 'indoor' ? 'Indoor' : 'Outdoor',
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.bold,
                                                color: item.unitType == 'indoor' ? const Color(0xFF4F46E5) : const Color(0xFF0D9488),
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: item.isMatched ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            item.isMatched ? 'Matched' : 'New Serial',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                              color: item.isMatched ? const Color(0xFF059669) : const Color(0xFFB45309),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 18),
                                onPressed: () {
                                  setState(() {
                                    _scannedItems.removeWhere((e) => e.serialNumber == item.serialNumber);
                                    _scannedSerialSet.remove(item.serialNumber);
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Bottom submit bar
        Container(
          color: Colors.white,
          padding: EdgeInsets.all(isTablet ? 20 : 14),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E1B4B),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFCBD5E1),
                  padding: EdgeInsets.symmetric(vertical: isTablet ? 18 : 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _scannedItems.isNotEmpty && !_isSubmitting ? _submitDispatch : null,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _scannedItems.isNotEmpty
                            ? 'Submit Dispatch (${_scannedItems.length} Serials)'
                            : 'Scan serials to dispatch',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: isTablet ? 16 : 14),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
