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
import '../widgets/uppercase_formatter.dart';
import '../widgets/office_pc_confirm_dialog.dart';
import '../services/sound_service.dart';
import '../services/session_recovery_service.dart';
import 'print_bill_screen.dart';
import '../widgets/flush_lag_button.dart';

class OutwardScreen extends StatefulWidget {
  final SessionDraft? restoredDraft;
  final TallySalesVoucher? fromTallyVoucher;
  const OutwardScreen({super.key, this.restoredDraft, this.fromTallyVoucher});

  @override
  State<OutwardScreen> createState() => _OutwardScreenState();
}

class _OutwardScreenState extends State<OutwardScreen> {
  final ApiService _api = ApiService();
  final OfflineQueueService _queue = OfflineQueueService();
  StreamSubscription? _wsSubscription;
  VoidCallback? _scannerSub;
  TallySalesVoucher? _tallyVoucher;
  String? _selectedTallyItemId;

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
  BuildContext? _modelSheetContext;
  Timer? _alertTimer;
  bool _isMismatchDialogOpen = false;
  void Function(void Function())? _setMismatchDialogState;
  String? _mismatchScanWarning;

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

  void _persistDraft() {
    if (_scannedItems.isEmpty) {
      SessionRecoveryService().clearDraft();
      return;
    }
    final draft = SessionDraft(
      type: SessionType.outward,
      updatedAt: DateTime.now(),
      shopId: _selectedShop?.id,
      shopName: _selectedShop?.name,
      productId: _selectedProduct?.id,
      productName: _selectedProduct != null ? '${_selectedProduct!.brand} ${_selectedProduct!.model}' : null,
      billNumber: _billNumberController.text.trim().isEmpty ? null : _billNumberController.text.trim(),
      deliveryReference: _deliveryRefController.text.trim().isEmpty ? null : _deliveryRefController.text.trim(),
      remarks: _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
      unitType: _outwardUnitType,
      currentStep: _currentStep,
      items: _scannedItems.map((e) => e.toJson()).toList(),
    );
    SessionRecoveryService().saveDraftDebounced(draft);
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

    // Restore unsubmitted draft if recovering
    if (widget.restoredDraft != null) {
      final draft = widget.restoredDraft!;
      if (draft.shopId != null) {
        final existingShop = _shops.where((s) => s.id == draft.shopId).firstOrNull;
        _selectedShop = existingShop ?? Shop(
          id: draft.shopId!,
          name: draft.shopName ?? 'Shop',
          city: '',
          isActive: true,
        );
      }
      if (draft.productId != null) {
        final existingProd = _products.where((p) => p.id == draft.productId).firstOrNull;
        _selectedProduct = existingProd;
        _activeFilterModelId = draft.productId!;
      }
      if (draft.billNumber != null) _billNumberController.text = draft.billNumber!;
      if (draft.deliveryReference != null) _deliveryRefController.text = draft.deliveryReference!;
      if (draft.remarks != null) _remarksController.text = draft.remarks!;
      if (draft.unitType != null) _outwardUnitType = draft.unitType!;

      for (final itemJson in draft.items) {
        try {
          final item = OutwardScanResult.fromJson(itemJson);
          _scannedItems.add(item);
          _scannedSerialSet.add(item.serialNumber.trim().toUpperCase());
          if (item.sequenceNumber >= _sequenceCounter) {
            _sequenceCounter = item.sequenceNumber + 1;
          }
        } catch (e) {
          debugPrint('Error restoring outward item: $e');
        }
      }

      if (_selectedProduct == null && _scannedItems.isNotEmpty && _scannedItems.first.product != null) {
        _selectedProduct = _scannedItems.first.product;
        _activeFilterModelId = _selectedProduct!.id;
      }

      _currentStep = 3;
    }

    // Initialize directly from incoming Tally Sales Bill
    if (widget.fromTallyVoucher != null) {
      _tallyVoucher = widget.fromTallyVoucher!;
      final tv = _tallyVoucher!;

      // 1. Auto-select shop from Tally party
      final partyClean = tv.partyName.trim().toLowerCase();
      final matchedShop = _shops.where((s) {
        if (tv.shopId != null && s.id == tv.shopId) return true;
        return s.name.trim().toLowerCase() == partyClean;
      }).firstOrNull;

      _selectedShop = matchedShop ?? Shop(
        id: tv.shopId ?? 'tally_${tv.id}',
        name: tv.partyName,
        city: tv.stateName ?? tv.address ?? '',
        isActive: true,
      );

      // 2. Prefill Bill / Invoice Number and Delivery / Vehicle Reference
      _billNumberController.text = tv.voucherNumber;
      if (tv.vehicleNumber != null && tv.vehicleNumber!.trim().isNotEmpty) {
        _deliveryRefController.text = tv.vehicleNumber!.trim();
      } else {
        // Vehicle / Delivery reference is inputted from mobile; do not default to bill number
        _deliveryRefController.text = '';
      }

      final remarksParts = <String>[];
      if (tv.transporterName != null && tv.transporterName!.trim().isNotEmpty) {
        remarksParts.add('Transporter: ${tv.transporterName!.trim()}');
      }
      if (tv.destination != null && tv.destination!.trim().isNotEmpty) {
        remarksParts.add('Destination: ${tv.destination!.trim()}');
      }
      if (tv.address != null && tv.address!.trim().isNotEmpty) {
        remarksParts.add(tv.address!.trim());
      }
      if (remarksParts.isNotEmpty) {
        _remarksController.text = remarksParts.join(' • ');
      }

      // 3. Immediately select first product model from bill items
      if (tv.items.isNotEmpty) {
        final firstItem = tv.items.first;
        _selectedTallyItemId = firstItem.id;
        final resolved = _resolveTallyProduct(firstItem);
        _selectedProduct = resolved;
        _activeFilterModelId = resolved.id;
        if (resolved.hasDualSerial) {
          _outwardUnitType = 'indoor';
        }
      }

      // Fetch fresh voucher details from server in background to sync product & shop IDs
      _loadTallyVoucherFresh(tv.id);

      // 4. Jump directly to Step 3: Scanning & Review!
      _currentStep = 3;
    }

    // Hardware barcode scanner support
    _scannerSub = HardwareScannerService().registerListener((barcode) {
      if (!mounted) return;

      // 1. If duplicate/alert dialog is currently showing, dismiss immediately on next scan!
      final bool wasAlertShowing = _alertContext != null;
      if (wasAlertShowing) {
        _dismissSimpleAlert();
      }

      // 2. If a model mismatch or unit type mismatch dialog is active, keep beeping error
      // and display the warning under the dialog until the mismatch is resolved!
      if (_isMismatchDialogOpen) {
        SoundService().playErrorSound();
        HapticFeedback.heavyImpact();
        if (_setMismatchDialogState != null) {
          _setMismatchDialogState!(() {
            _mismatchScanWarning = 'Resolve model mismatch first before scanning "$barcode"!';
          });
        }
        _showToast(
          'Model Mismatch Active! Please resolve or cancel this dialog before scanning.',
          const Color(0xFFDC2626),
        );
        return;
      }

      // 3. If model switch bottom sheet is currently open:
      // Check if scanned barcode matches a product model name or is a serial to auto-route!
      if (_modelSheetContext != null && _modelSheetContext!.mounted) {
        final clean = barcode.trim().toUpperCase();
        Product? matchedProd;
        try {
          matchedProd = _products.firstWhere(
            (p) => p.model.trim().toUpperCase() == clean || p.name.trim().toUpperCase() == clean,
          );
        } catch (_) {}

        if (matchedProd != null) {
          setState(() {
            _selectedProduct = matchedProd;
            _activeFilterModelId = 'ALL';
          });
          try {
            Navigator.of(_modelSheetContext!).pop();
          } catch (_) {}
          _modelSheetContext = null;
          _showToast('Active model: ${matchedProd.brand} ${matchedProd.model}', const Color(0xFF4F46E5));
          return;
        } else {
          // Serial scanned: auto-dismiss model sheet so serial can be dispatched immediately!
          try {
            Navigator.of(_modelSheetContext!).pop();
          } catch (_) {}
          _modelSheetContext = null;
        }
      }

      // Allow scan when OutwardScreen is active even if a dialog/sheet is mid-animation
      if (ModalRoute.of(context)?.isActive != true) return;
      _lastScanTime = DateTime.now();

      // Proactively clear focus and close IME so keystrokes never get intercepted
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');

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
        final clean = barcode.trim().toUpperCase();
        Product? matchedProd;
        try {
          matchedProd = _products.firstWhere(
            (p) => p.model.trim().toUpperCase() == clean || p.name.trim().toUpperCase() == clean,
          );
        } catch (_) {}

        if (matchedProd != null) {
          setState(() {
            _selectedProduct = matchedProd;
            _currentStep = 3;
          });
          _showToast('Selected: ${matchedProd.brand} ${matchedProd.model}', const Color(0xFF4F46E5));
          return;
        }

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
      } else if ((type == 'tally_bill_cancelled' || type == 'bill_cancelled') && data is Map<String, dynamic>) {
        final bNum = (data['bill_number'] ?? data['voucher_number'])?.toString().trim().toLowerCase();
        if (_tallyVoucher != null && _tallyVoucher!.voucherNumber.trim().toLowerCase() == bNum) {
          HapticFeedback.heavyImpact();
          SoundService().playErrorSound();
          _showSimpleAlert(
            'Bill Cancelled in Tally',
            'Tally Bill ${_tallyVoucher!.voucherNumber} has been cancelled in TallyPrime.\n\nDispatch cannot continue for a cancelled bill.',
          );
        }
      }
    });
  }

  void _flushScreenLag() {
    _dismissSimpleAlert();
    _scanQueue.clear();
    _inFlightSerials.clear();
    _isProcessingQueue = false;
    setState(() {});
  }

  @override
  void dispose() {
    HardwareScannerService().isMismatchActive = false;
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
          if (_selectedShop != null) {
            final refreshedShop = _shops.firstWhere(
              (s) => s.id == _selectedShop!.id,
              orElse: () => _selectedShop!,
            );
            _selectedShop = refreshedShop;
          }
          if (_tallyVoucher != null) {
            final pClean = _tallyVoucher!.partyName.trim().toLowerCase();
            final matchedShop = _shops.where((s) {
              if (_tallyVoucher!.shopId != null && s.id == _tallyVoucher!.shopId) return true;
              return s.name.trim().toLowerCase() == pClean;
            }).firstOrNull;
            if (matchedShop != null) {
              _selectedShop = matchedShop;
            } else {
              final fuzzyShop = _shops.where((s) {
                final sName = s.name.trim().toLowerCase();
                return sName.contains(pClean) || pClean.contains(sName);
              }).firstOrNull;
              if (fuzzyShop != null) {
                _selectedShop = fuzzyShop;
              }
            }

            if (_selectedTallyItemId != null) {
              final currentItem = _tallyVoucher!.items.where((it) => it.id == _selectedTallyItemId).firstOrNull;
              if (currentItem != null) {
                _selectedProduct = _resolveTallyProduct(currentItem);
                _activeFilterModelId = _selectedProduct!.id;
              }
            } else if (_tallyVoucher!.items.isNotEmpty) {
              final firstItem = _tallyVoucher!.items.first;
              _selectedTallyItemId = firstItem.id;
              _selectedProduct = _resolveTallyProduct(firstItem);
              _activeFilterModelId = _selectedProduct!.id;
              if (_selectedProduct!.hasDualSerial) {
                _outwardUnitType = 'indoor';
              }
            }
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

  Future<void> _loadTallyVoucherFresh(String voucherId) async {
    try {
      final fresh = await _api.getTallyVoucherDetail(voucherId);
      if (mounted) {
        setState(() {
          _tallyVoucher = fresh;
          if (fresh.shopId != null && fresh.shopId!.isNotEmpty) {
            final matched = _shops.where((s) => s.id == fresh.shopId).firstOrNull;
            if (matched != null) {
              _selectedShop = matched;
            }
          }
          if (_selectedTallyItemId != null) {
            final itm = fresh.items.where((i) => i.id == _selectedTallyItemId).firstOrNull;
            if (itm != null) {
              _selectedProduct = _resolveTallyProduct(itm);
              _activeFilterModelId = _selectedProduct!.id;
            }
          }
        });
      }
    } catch (_) {}
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

  Product _resolveTallyProduct(TallyVoucherItem item) {
    if (item.productId != null && item.productId!.isNotEmpty) {
      final p = _products.where((prod) => prod.id.toLowerCase() == item.productId!.toLowerCase()).firstOrNull;
      if (p != null) return p;
    }

    final itemClean = item.itemName.trim().toLowerCase();
    final codeClean = item.itemCode?.trim().toLowerCase();
    final matchedNameClean = item.matchedProductName?.trim().toLowerCase();
    final matchedModelClean = item.matchedProductModel?.trim().toLowerCase();

    // 1. Exact match by itemCode or matchedProductModel
    if (codeClean != null && codeClean.isNotEmpty) {
      final p = _products.where((prod) => prod.model.trim().toLowerCase() == codeClean).firstOrNull;
      if (p != null) return p;
    }
    if (matchedModelClean != null && matchedModelClean.isNotEmpty) {
      final p = _products.where((prod) => prod.model.trim().toLowerCase() == matchedModelClean).firstOrNull;
      if (p != null) return p;
    }

    // 2. Exact match by model or name
    for (final prod in _products) {
      final pModel = prod.model.trim().toLowerCase();
      final pName = prod.name.trim().toLowerCase();
      if (pModel.isNotEmpty && pModel == itemClean) return prod;
      if (pName.isNotEmpty && pName == itemClean) return prod;
      if (matchedNameClean != null && matchedNameClean.isNotEmpty && pName == matchedNameClean) return prod;
    }

    // 3. High-confidence model substring match
    for (final prod in _products) {
      final pModel = prod.model.trim().toLowerCase();
      if (pModel.length >= 3 && itemClean.contains(pModel)) {
        return prod;
      }
    }

    // 4. Token match: if words of DB product model appear in item name
    for (final prod in _products) {
      final pModel = prod.model.trim().toLowerCase();
      final tokens = pModel.split(RegExp(r'[\s\-_]+')).where((t) => t.length >= 3).toList();
      if (tokens.isNotEmpty && tokens.every((t) => itemClean.contains(t))) {
        return prod;
      }
    }

    // 5. Unique fallback: in-memory product uniquely tied to this item's specific ID
    final bool hasValidProductId = item.productId != null &&
        RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(item.productId!.trim());
    final brandGuess = item.itemName.split(' ').first;
    final catId = _products.isNotEmpty ? _products.first.categoryId : 'tally_category';
    return Product(
      id: hasValidProductId ? item.productId!.trim() : 'tally_item_${item.id}',
      name: item.matchedProductName ?? item.itemName,
      model: item.matchedProductModel ?? ((item.itemCode != null && item.itemCode!.trim().isNotEmpty)
          ? item.itemCode!.trim()
          : item.itemName),
      brand: brandGuess.length <= 15 ? brandGuess : 'Tally',
      categoryId: catId,
      unit: item.uom ?? 'NOS',
      serialNumberRequired: true,
      currentStockQty: item.quantity.toInt(),
      outOfStockReminder: false,
      hasDualSerial: false,
    );
  }

  bool _doesTallyItemMatchProduct(TallyVoucherItem item, Product prod) {
    if (item.productId != null && item.productId!.isNotEmpty) {
      if (item.productId!.toLowerCase() == prod.id.toLowerCase()) return true;
    }
    final resolved = _resolveTallyProduct(item);
    if (resolved.id.toLowerCase() == prod.id.toLowerCase()) return true;

    final itemClean = item.itemName.trim().toLowerCase();
    final itemModelClean = (item.matchedProductModel ?? item.itemCode ?? '').trim().toLowerCase();
    final prodModelClean = prod.model.trim().toLowerCase();
    final prodNameClean = prod.name.trim().toLowerCase();

    if (prodModelClean.isNotEmpty) {
      if (prodModelClean == itemClean || prodModelClean == itemModelClean) return true;
      if (prodModelClean.length >= 3 && itemClean.contains(prodModelClean)) return true;
    }
    if (prodNameClean.isNotEmpty && prodNameClean == itemClean) return true;

    return false;
  }

  TallyVoucherItem? _findTallyItemForProduct(Product? prod) {
    if (_tallyVoucher == null || prod == null) return null;
    for (final item in _tallyVoucher!.items) {
      if (_doesTallyItemMatchProduct(item, prod)) return item;
    }
    return null;
  }

  /// Strictly only models parsed from this specific Tally bill
  List<Product> get _tallyBillProducts {
    if (_tallyVoucher == null) return [];
    final Map<String, Product> uniqueProds = {};
    for (final item in _tallyVoucher!.items) {
      final p = _resolveTallyProduct(item);
      uniqueProds[p.id] = p;
    }
    return uniqueProds.values.toList();
  }

  TallyVoucherItem? _getCurrentTallyItem() {
    if (_tallyVoucher == null) return null;
    if (_selectedTallyItemId != null) {
      final itm = _tallyVoucher!.items.where((it) => it.id == _selectedTallyItemId).firstOrNull;
      if (itm != null) return itm;
    }
    if (_selectedProduct != null) {
      return _findTallyItemForProduct(_selectedProduct);
    }
    return _tallyVoucher!.items.firstOrNull;
  }

  int _getScannedCountForProduct(Product prod) {
    return _scannedItems.where((s) {
      final p = s.product;
      if (p == null) return false;
      return p.id.toLowerCase() == prod.id.toLowerCase() ||
          p.model.trim().toLowerCase() == prod.model.trim().toLowerCase();
    }).length;
  }

  void _openContinuousScanner() {
    if (_selectedProduct == null && _tallyVoucher != null && _tallyVoucher!.items.isNotEmpty) {
      final firstItem = _tallyVoucher!.items.first;
      _selectedTallyItemId = firstItem.id;
      _selectedProduct = _resolveTallyProduct(firstItem);
      _activeFilterModelId = _selectedProduct?.id ?? 'ALL';
    }

    if (_selectedShop == null && _tallyVoucher != null) {
      _selectedShop = Shop(
        id: _tallyVoucher!.shopId ?? 'tally_${_tallyVoucher!.id}',
        name: _tallyVoucher!.partyName,
        city: _tallyVoucher!.stateName ?? _tallyVoucher!.address ?? '',
        isActive: true,
      );
    }

    if (_selectedProduct == null || _selectedShop == null) {
      _showToast('Please select a model and shop to start scanning', const Color(0xFFE11D48));
      return;
    }

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
      final String? pidToSend = (_selectedProduct != null &&
              !_selectedProduct!.id.startsWith('tally_') &&
              !_selectedProduct!.id.startsWith('offline_'))
          ? _selectedProduct!.id
          : null;
      final res = await _api.checkOutwardSerial(pidToSend, cleanSerial);
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
        SoundService().playErrorSound();
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

      // Identify registered DB product when serial is identified
      final regProdId = res['registered_product_id']?.toString();
      Product? realProd = (regProdId != null && regProdId.isNotEmpty)
          ? (_products.where((p) => p.id.toLowerCase() == regProdId.toLowerCase()).firstOrNull ??
              OfflineManager().products.where((p) => p.id.toLowerCase() == regProdId.toLowerCase()).firstOrNull)
          : null;

      // Fallback: If not resolved by ID, resolve by registered_model_name
      if (realProd == null) {
        final existingModelName = (res['registered_model_name'] ?? serialDetail?['product_name'])?.toString().trim();
        if (existingModelName != null && existingModelName.isNotEmpty) {
          final cleanM = existingModelName.toLowerCase();
          realProd = _products.where((p) => p.model.trim().toLowerCase() == cleanM || p.name.trim().toLowerCase() == cleanM).firstOrNull ??
              OfflineManager().products.where((p) => p.model.trim().toLowerCase() == cleanM || p.name.trim().toLowerCase() == cleanM).firstOrNull;
          if (realProd == null && _tallyVoucher != null) {
            for (final itm in _tallyVoucher!.items) {
              if (itm.itemName.trim().toLowerCase() == cleanM || (itm.itemCode != null && itm.itemCode!.trim().toLowerCase() == cleanM)) {
                realProd = _resolveTallyProduct(itm);
                break;
              }
            }
          }
        }
      }

      // =========================================================================
      // STRICT TALLY BILL ENFORCEMENT: ONLY MODELS IN THIS BILL MAY BE SCANNED
      // =========================================================================
      if (_tallyVoucher != null) {
        final currentTallyItem = _getCurrentTallyItem();

        // 1. If serial belongs to a known registered product in the warehouse
        if (realProd != null) {
          final Product targetProd = realProd;
          // Check A: Is this product part of this Tally bill at all?
          final billItemForProd = _findTallyItemForProduct(targetProd);
          if (billItemForProd == null) {
            HapticFeedback.heavyImpact();
            SoundService().playErrorSound();
            _showSimpleAlert(
              'Model Not In Tally Bill',
              'Serial "$cleanSerial" is registered under "${targetProd.brand} ${targetProd.model}", which is NOT in Tally Bill ${_tallyVoucher!.voucherNumber}.\n\nStrictly only models present in this Tally bill can be scanned.',
              autoDismissDuration: const Duration(seconds: 12),
            );
            return; // STRICTLY REJECTED!
          }

          // Check B: Has the target quantity for this model already been reached?
          final targetQty = billItemForProd.quantity.toInt();
          final scannedQty = _getScannedCountForProduct(targetProd);
          if (scannedQty >= targetQty && targetQty > 0) {
            HapticFeedback.heavyImpact();
            SoundService().playErrorSound();
            _showSimpleAlert(
              'Target Quantity Reached',
              'All $targetQty units of "${targetProd.model}" in Tally Bill ${_tallyVoucher!.voucherNumber} have already been scanned ($scannedQty/$targetQty).\n\nCannot scan extra units.',
            );
            return; // STRICTLY REJECTED!
          }

          // Check C: Auto-switch active model to this model without any mismatch warning!
          final bool wasDifferentModel = _selectedProduct == null || _selectedProduct!.id != targetProd.id;
          if (wasDifferentModel) {
            setState(() {
              _selectedProduct = targetProd;
              _selectedTallyItemId = billItemForProd.id;
              _activeFilterModelId = targetProd.id;
              if (targetProd.hasDualSerial) {
                final detectedUnit = res['unit_type']?.toString().toLowerCase();
                if (detectedUnit == 'indoor' || detectedUnit == 'outdoor') {
                  _outwardUnitType = detectedUnit!;
                }
              }
            });
          }

          // Automatically add serial directly to its matching model in this Tally bill
          final unitType = (res['unit_type'] as String?) ?? (targetProd.hasDualSerial ? _outwardUnitType : null);
          if (!_scannedItems.any((item) => item.serialNumber == cleanSerial)) {
            final seq = _sequenceCounter++;
            _scannedSerialSet.add(cleanSerial);
            setState(() {
              _scannedItems.insert(
                0,
                OutwardScanResult(
                  serialNumber: cleanSerial,
                  product: targetProd,
                  caseType: isDamaged ? OutwardCase.statusWarning : OutwardCase.matched,
                  isMatched: true,
                  isFlaggedForReview: isDamaged,
                  warningMessage: isDamaged ? 'Damaged item added after confirmation.' : msg,
                  unitType: unitType,
                  sequenceNumber: seq,
                ),
              );
              if (targetProd.hasDualSerial) {
                _outwardUnitType = (_outwardUnitType == 'indoor') ? 'outdoor' : 'indoor';
              }
              _lastScanFeedback = '✓ Scanned #$seq: $cleanSerial • ${targetProd.brand} ${targetProd.model}';
            });
            HapticFeedback.lightImpact();
            SoundService().playScannerBeep();
            if (wasDifferentModel) {
              _showToast('Auto-switched to ${targetProd.model}: $cleanSerial added', const Color(0xFF0284C7));
            } else {
              _showToast('Added $cleanSerial (${targetProd.model})', const Color(0xFF059669));
            }
          }
          return; // Processed and added to matching Tally bill model!
        }
        // 2. If backend reported a model mismatch (Case 4), but model is not in this Tally bill
        else if (caseVal == 4 || caseName == 'model_mismatch') {
          HapticFeedback.heavyImpact();
          SoundService().playErrorSound();
          final existingModel = res['registered_model_name'] ?? serialDetail?['product_name'] ?? 'another model';
          _showSimpleAlert(
            'Model Not In Tally Bill',
            'Serial "$cleanSerial" is registered under "$existingModel", which is NOT in Tally Bill ${_tallyVoucher!.voucherNumber}.\n\nStrictly only models present in this Tally bill can be scanned.',
            autoDismissDuration: const Duration(seconds: 12),
          );
          return; // STRICTLY REJECTED!
        }
        // 3. For pre-go-live untracked stock (Case 2) or Case 1 without registered realProd:
        else {
          if (currentTallyItem != null && _selectedProduct != null) {
            final targetQty = currentTallyItem.quantity.toInt();
            final scannedQty = _getScannedCountForProduct(_selectedProduct!);
            if (scannedQty >= targetQty && targetQty > 0) {
              HapticFeedback.heavyImpact();
              SoundService().playErrorSound();
              _showSimpleAlert(
                'Target Quantity Reached',
                'All $targetQty units of "${_selectedProduct!.model}" in Tally Bill ${_tallyVoucher!.voucherNumber} have already been scanned ($scannedQty/$targetQty).\n\nCannot scan extra units.',
              );
              return; // STRICTLY REJECTED!
            }
          }
        }
      } else {
        // Non-Tally manual dispatch: upgrade placeholder product if applicable
        if (realProd != null) {
          final Product manualProd = realProd;
          if (_selectedProduct == null ||
              _selectedProduct!.id.startsWith('offline_')) {
            setState(() {
              _selectedProduct = manualProd;
              _activeFilterModelId = manualProd.id;
            });
          }
        }
      }

      // --- CASE 1: MATCHED (Tracked & Available for current model) ---
      if (caseVal == 1 || caseName == 'matched') {
        // Enforce dual serial unit type match for matched serial numbers
        if (_selectedProduct?.hasDualSerial == true) {
          final String? registeredUnitType = (res['unit_type'] as String?)?.toLowerCase();
          if (registeredUnitType != null &&
              registeredUnitType.isNotEmpty &&
              registeredUnitType != _outwardUnitType.toLowerCase()) {
            HapticFeedback.heavyImpact();
            SoundService().playErrorSound();
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
            if (_selectedProduct!.hasDualSerial) {
              _outwardUnitType = (_outwardUnitType == 'indoor') ? 'outdoor' : 'indoor';
            }
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
            if (_selectedProduct!.hasDualSerial) {
              _outwardUnitType = (_outwardUnitType == 'indoor') ? 'outdoor' : 'indoor';
            }
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
            SoundService().playErrorSound();
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
          SoundService().playErrorSound();
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
            if (_selectedProduct!.hasDualSerial) {
              _outwardUnitType = (_outwardUnitType == 'indoor') ? 'outdoor' : 'indoor';
            }
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
        SoundService().playErrorSound();
        if (_tallyVoucher != null) {
          final existingModel = res['registered_model_name'] ?? serialDetail?['product_name'] ?? 'another model';
          _showSimpleAlert(
            'Model Mismatch',
            'Serial "$cleanSerial" is registered under "$existingModel".\n\nStrictly only models in Tally Bill ${_tallyVoucher!.voucherNumber} can be scanned.',
          );
          return; // STRICTLY REJECTED!
        }

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
                FocusManager.instance.primaryFocus?.unfocus();
                SystemChannels.textInput.invokeMethod('TextInput.hide');
                HardwareScannerService().clearBuffer();
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
      SoundService().playErrorSound();
      _showSimpleAlert('Validation Error', 'Could not verify serial "$cleanSerial": $e');
    } finally {
      _inFlightSerials.remove(cleanSerial);
      _persistDraft();
    }
  }

  Future<Map<String, dynamic>?> _showDifferentModelDialog(
    String serial,
    Product targetProd, {
    String? initialUnitType,
    bool isDamaged = false,
  }) {
    SoundService().playErrorSound();
    _isMismatchDialogOpen = true;
    HardwareScannerService().isMismatchActive = true;
    _mismatchScanWarning = null;
    String selectedUnitType = initialUnitType ?? 'indoor';

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          _setMismatchDialogState = setDialogState;
          final isDual = targetProd.hasDualSerial;
          final inCount = _scannedItems.where((e) => (e.product?.id == targetProd.id) && e.unitType?.toLowerCase() == 'indoor').length;
          final outCount = _scannedItems.where((e) => (e.product?.id == targetProd.id) && e.unitType?.toLowerCase() == 'outdoor').length;

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
                                  'Indoor ($inCount)',
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
                                  'Outdoor ($outCount)',
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
                if (_mismatchScanWarning != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _mismatchScanWarning!,
                            style: const TextStyle(
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
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _isMismatchDialogOpen = false;
                  HardwareScannerService().isMismatchActive = false;
                  _setMismatchDialogState = null;
                  _mismatchScanWarning = null;
                  Navigator.pop(ctx, {'action': 'cancel'});
                },
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E1B4B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () {
                  _isMismatchDialogOpen = false;
                  HardwareScannerService().isMismatchActive = false;
                  _setMismatchDialogState = null;
                  _mismatchScanWarning = null;
                  Navigator.pop(ctx, {
                    'action': 'add',
                  'unit_type': isDual ? selectedUnitType : null,
                  'switch_model': true,
                });
                },
                child: Text(
                  isDual ? 'Add & Switch Model' : 'Add to Dispatch',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      _isMismatchDialogOpen = false;
      HardwareScannerService().isMismatchActive = false;
      _setMismatchDialogState = null;
      _mismatchScanWarning = null;
    });
  }

  void _showVehicleInputDialog(BuildContext context) {
    final textController = TextEditingController(text: _deliveryRefController.text.trim());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.local_shipping_outlined, color: Color(0xFF4F46E5)),
            SizedBox(width: 8),
            Text('Vehicle / Ref No', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the vehicle registration number or delivery reference for this dispatch:',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: textController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'e.g. KL-07-CD-1234, Local Van',
                prefixIcon: const Icon(Icons.directions_car_outlined, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E1B4B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final val = textController.text.trim();
              setState(() {
                _deliveryRefController.text = val;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Save Vehicle No'),
          ),
        ],
      ),
    );
  }

  void _showModelSwitchBottomSheet() {
    String sheetSearch = '';
    bool isSyncing = false;
    StreamSubscription? sheetWsSub;
    Timer? debounceTimer;
    final isTallyMode = _tallyVoucher != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        _modelSheetContext = ctx;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            if (!isTallyMode) {
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
            }

            Future<void> syncFreshModels({String? query}) async {
              if (isTallyMode) return;
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

            // Strictly restrict to only models in this Tally bill when dispatching a Tally bill
            final sourceProducts = isTallyMode ? _tallyBillProducts : _products;
            final filteredProds = sourceProducts.where((p) {
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
                        Icon(isTallyMode ? Icons.receipt_long_rounded : Icons.swap_horiz, color: const Color(0xFF4F46E5)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isTallyMode
                                ? 'Models in Tally Bill (${_tallyVoucher!.voucherNumber})'
                                : 'Switch Model for this Shop',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isTallyMode) ...[
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
                        ],
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
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: const [UpperCaseTextFormatter()],
                      decoration: InputDecoration(
                        hintText: isTallyMode
                            ? 'Search models in Tally Bill ${_tallyVoucher!.voucherNumber}...'
                            : 'Search brand or model (e.g. GXI 360)...',
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
                        if (!isTallyMode && val.trim().length >= 2) {
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
                                    isTallyMode
                                        ? (sheetSearch.isEmpty
                                            ? 'No models in Tally Bill ${_tallyVoucher!.voucherNumber}'
                                            : 'No model matching "$sheetSearch" in Tally Bill ${_tallyVoucher!.voucherNumber}')
                                        : (sheetSearch.isEmpty
                                            ? 'No models available'
                                            : 'No local match for "$sheetSearch"'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Color(0xFF1E293B),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isTallyMode
                                        ? 'Only models present in Tally Bill ${_tallyVoucher!.voucherNumber} can be selected.'
                                        : (sheetSearch.isNotEmpty
                                            ? 'Model "$sheetSearch" is not in the system yet. Sync from server.'
                                            : 'No models found. Sync models from server.'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                  if (!isTallyMode) ...[
                                    const SizedBox(height: 16),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 12,
                                      runSpacing: 10,
                                      children: [
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: const Color(0xFF4F46E5),
                                            side: const BorderSide(color: Color(0xFF4F46E5)),
                                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          icon: isSyncing
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F46E5)),
                                                )
                                              : const Icon(Icons.cloud_sync_outlined, size: 18),
                                          label: Text(isSyncing ? 'Syncing...' : 'Sync Models from Server'),
                                          onPressed: isSyncing ? null : () => syncFreshModels(query: sheetSearch),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () async {
                              if (!isTallyMode) {
                                await syncFreshModels(query: sheetSearch);
                              }
                            },
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: filteredProds.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (c, i) {
                                final p = filteredProds[i];
                                final isSelected = p.id == _selectedProduct?.id;
                                final itm = isTallyMode ? _findTallyItemForProduct(p) : null;
                                final target = itm?.quantity.toInt() ?? 0;
                                final countInBatch = _getScannedCountForProduct(p);
                                final isDone = isTallyMode && target > 0 && countInBatch >= target;

                                return ListTile(
                                  tileColor: isSelected
                                      ? const Color(0xFFEEF2FF)
                                      : (isDone ? const Color(0xFFF0FDF4) : Colors.white),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: isSelected
                                          ? const Color(0xFF6366F1)
                                          : (isDone ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0)),
                                      width: isSelected ? 1.5 : 1.0,
                                    ),
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected
                                        ? const Color(0xFF4F46E5)
                                        : (isDone ? const Color(0xFF16A34A) : const Color(0xFFF1F5F9)),
                                    foregroundColor: (isSelected || isDone) ? Colors.white : const Color(0xFF475569),
                                    child: Icon(isSelected ? Icons.check : (isDone ? Icons.check_circle : Icons.devices), size: 20),
                                  ),
                                  title: Text(
                                    p.name,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: Text(
                                    isTallyMode
                                        ? '${p.brand} • ${p.model} • Target: $target units'
                                        : (p.currentStockQty < 0
                                            ? '${p.brand} • ${p.model} (${p.currentStockQty} - Negative Stock)'
                                            : '${p.brand} • ${p.model} (${p.currentStockQty} on shelves)'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDone ? const Color(0xFF15803D) : const Color(0xFF64748B),
                                      fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  trailing: isTallyMode
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isDone ? const Color(0xFF16A34A) : const Color(0xFF0284C7),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            isDone ? 'Completed ($countInBatch/$target)' : '$countInBatch / $target',
                                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        )
                                      : (countInBatch > 0
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
                                          : null),
                                  onTap: () {
                                    FocusManager.instance.primaryFocus?.unfocus();
                                    SystemChannels.textInput.invokeMethod('TextInput.hide');
                                    HardwareScannerService().clearBuffer();
                                    setState(() {
                                      _selectedProduct = p;
                                      _activeFilterModelId = p.id;
                                      if (_tallyVoucher != null) {
                                        final matchItem = _findTallyItemForProduct(p);
                                        if (matchItem != null) {
                                          _selectedTallyItemId = matchItem.id;
                                        }
                                      }
                                      if (p.hasDualSerial) {
                                        _outwardUnitType = 'indoor';
                                      }
                                    });
                                    _persistDraft();
                                    _modelSheetContext = null;
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
      _modelSheetContext = null;
      sheetWsSub?.cancel();
      debounceTimer?.cancel();
    });
  }

  Future<void> _showUnitTypeMismatchDialog({
    required String cleanSerial,
    required String actualUnitType,
    required String selectedUnitType,
  }) {
    SoundService().playErrorSound();
    _isMismatchDialogOpen = true;
    HardwareScannerService().isMismatchActive = true;
    _mismatchScanWarning = null;
    final isActualIndoor = actualUnitType.toLowerCase() == 'indoor';
    final actualTitle = isActualIndoor ? 'Indoor Unit' : 'Outdoor Unit';
    final selectedTitle = selectedUnitType.toLowerCase() == 'indoor' ? 'Indoor Unit' : 'Outdoor Unit';

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          _setMismatchDialogState = setDialogState;
          return AlertDialog(
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
            if (_mismatchScanWarning != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _mismatchScanWarning!,
                        style: const TextStyle(
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
      );
    },
  ),
).whenComplete(() {
  _isMismatchDialogOpen = false;
  HardwareScannerService().isMismatchActive = false;
  _setMismatchDialogState = null;
  _mismatchScanWarning = null;
});
}

  Future<void> _showAlreadyDispatchedDialog(String serial, String message) {
    SoundService().playErrorSound();
    _isMismatchDialogOpen = true;
    HardwareScannerService().isMismatchActive = true;
    _mismatchScanWarning = null;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          _setMismatchDialogState = setDialogState;
          return AlertDialog(
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
      );
    },
  ),
).whenComplete(() {
  _isMismatchDialogOpen = false;
  HardwareScannerService().isMismatchActive = false;
  _setMismatchDialogState = null;
  _mismatchScanWarning = null;
});
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

    int remainingSeconds = autoDismissDuration.inSeconds;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        _alertContext = ctx;
        _alertTimer?.cancel();

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            _alertTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
              if (remainingSeconds <= 1) {
                timer.cancel();
                _alertTimer = null;
                if (_alertContext != null && dialogCtx.mounted) {
                  try {
                    Navigator.of(dialogCtx).pop();
                  } catch (_) {}
                  _alertContext = null;
                }
              } else {
                if (dialogCtx.mounted) {
                  setDialogState(() {
                    remainingSeconds--;
                  });
                }
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, size: 13, color: Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(
                          'Auto-closing in ${remainingSeconds}s (or scan next serial)',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
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
    SoundService().playErrorSound();
    _isMismatchDialogOpen = true;
    HardwareScannerService().isMismatchActive = true;
    _mismatchScanWarning = null;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          _setMismatchDialogState = setDialogState;
          return AlertDialog(
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
      );
    },
  ),
).whenComplete(() {
  _isMismatchDialogOpen = false;
  HardwareScannerService().isMismatchActive = false;
  _setMismatchDialogState = null;
  _mismatchScanWarning = null;
});
}

  Future<void> _showCase4ModelMismatchDialog(String serial, String existingModel, String? msg) {
    SoundService().playErrorSound();
    _isMismatchDialogOpen = true;
    HardwareScannerService().isMismatchActive = true;
    _mismatchScanWarning = null;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          _setMismatchDialogState = setDialogState;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.cancel, color: Color(0xFFE11D48)),
                SizedBox(width: 8),
                Expanded(child: Text('Model Mismatch!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg ?? 'Serial "$serial" belongs to "$existingModel", but this active model is "${_selectedProduct!.name}".',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                if (_mismatchScanWarning != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _mismatchScanWarning!,
                            style: const TextStyle(
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
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Dismiss', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      _isMismatchDialogOpen = false;
      HardwareScannerService().isMismatchActive = false;
      _setMismatchDialogState = null;
      _mismatchScanWarning = null;
    });
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
                SizedBox(height: context.isTablet ? 14 : 10),

                // Vehicle Number / Delivery Reference (Input from mobile)
                TextField(
                  controller: _deliveryRefController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Vehicle / Delivery Ref No (Optional)',
                    hintText: 'e.g. KL-07-CD-1234, Local Van',
                    prefixIcon: Icon(Icons.local_shipping_outlined, size: context.isTablet ? 24 : 20, color: const Color(0xFF4F46E5)),
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
                SizedBox(height: context.isTablet ? 14 : 10),

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

      final firstProd = items.first.product;
      batchItems.add({
        'product_id': prodId,
        'product_name': firstProd?.name,
        'product_model': firstProd?.model,
        'product_brand': firstProd?.brand,
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
      'shop_name': _selectedShop!.name,
      'items': batchItems,
      'bill_number': billNumber.isEmpty ? null : billNumber,
      'delivery_reference': deliveryRef.isEmpty ? null : deliveryRef,
      'remarks': remarks.isEmpty ? null : remarks,
      'client_request_id': _dispatchRequestId,
    };

    final bool hasOfflineShop = _selectedShop!.id.startsWith('offline_');
    final bool hasOfflineProduct = batchItems.any((item) => (item['product_id']?.toString() ?? '').startsWith('offline_'));

    Future<void> saveOfflineAndExit([BuildContext? loadingCtx]) async {
      if (loadingCtx != null && Navigator.canPop(loadingCtx)) {
        Navigator.pop(loadingCtx);
      }
      OfflineManager().markOffline();
      await OfflineManager().queueDispatch(dispatchPayload);
      await SessionRecoveryService().clearDraft();
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

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.cloud_done_rounded, color: Color(0xFF2563EB), size: 28),
              SizedBox(width: 10),
              Text('Saved in Offline Queue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded, color: Color(0xFF2563EB), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bill  for  saved offline.',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E3A8A), fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'No server / network connection was available. Your bill and all scanned serial numbers have been securely stored in the offline queue.',
                style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.sync_rounded, color: Color(0xFF16A34A), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'When network is restored, the app will automatically submit this bill in the background.',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E1B4B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('OK, Got it', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    if (!OfflineManager().isOnline || hasOfflineShop || hasOfflineProduct) {
      await saveOfflineAndExit();
      return;
    }

    BuildContext? loadingCtx;
    bool isSavingOfflineManually = false;

    // Show visual submission dialog with immediate 'Save Offline' option
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (lCtx) {
        loadingCtx = lCtx;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3C3489)),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Submitting Dispatch...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Connecting to server for Bill ...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD97706),
                    side: const BorderSide(color: Color(0xFFF59E0B)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.wifi_off_rounded, size: 16),
                  label: const Text('Save Offline & Auto-Submit Later', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    isSavingOfflineManually = true;
                    saveOfflineAndExit(loadingCtx);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      // Fast probe: check if server is reachable within 2.5 seconds before attempting large request
      final isAlive = await OfflineManager().checkServerHealth(timeoutSeconds: 3);
      if (!isAlive) {
        if (!isSavingOfflineManually) {
          await saveOfflineAndExit(loadingCtx);
        }
        return;
      }

      final result = await _api.submitOutwardMultiBatch(
        shopId: _selectedShop!.id,
        items: batchItems,
        billNumber: billNumber.isEmpty ? null : billNumber,
        deliveryReference: deliveryRef.isEmpty ? null : deliveryRef,
        remarks: remarks.isEmpty ? null : remarks,
        clientRequestId: _dispatchRequestId,
        tallyVoucherId: _tallyVoucher?.id,
      ).timeout(const Duration(seconds: 10));

      if (loadingCtx != null && Navigator.canPop(loadingCtx!)) {
        Navigator.pop(loadingCtx!);
      }

      // Successfully processed: reset request ID
      _dispatchRequestId = null;
      await SessionRecoveryService().clearDraft();

      if (_tallyVoucher != null) {
        try {
          await _api.markTallyVoucherProcessed(
            _tallyVoucher!.id,
            processed: true,
            notes: 'Dispatched via Godown Scanner (Bill: $billNumber)',
          );
        } catch (_) {}
        _api.clearLatestTallyBill();
      }

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
                          final confirmed = await confirmOfficePcPrint(
                            dialogCtx,
                            title: 'Print on Office PC',
                            message: 'Are you sure you want to send Bill #$finalBillNumber to the Office PC printer?',
                            documentName: 'Bill #$finalBillNumber',
                          );
                          if (!confirmed || !dialogCtx.mounted) return;

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
                            dialogCtx,
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
      Navigator.pop(context, true);
    } catch (e) {
      if (isSavingOfflineManually) return;
      if (loadingCtx != null && Navigator.canPop(loadingCtx!)) {
        Navigator.pop(loadingCtx!);
      }
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
          errLower.contains('timeout') ||
          errLower.contains('timed out') ||
          errLower.contains('host lookup') ||
          errLower.contains('unreachable') ||
          errLower.contains('clientexception') ||
          errLower.contains('handshake') ||
          errLower.contains('network') ||
          errLower.contains('os error');

      if (isNetError) {
        await saveOfflineAndExit();
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
            if (_tallyVoucher != null) 'tally_voucher_id': _tallyVoucher!.id,
          },
          description: 'Outward: ${_selectedShop!.name} (${_scannedItems.length} units, ${byProduct.length} models)',
        );
        await _queue.enqueue(batch);
        await SessionRecoveryService().clearDraft();
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
      await SessionRecoveryService().clearDraft();
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

  Future<bool> _handleWillPop() async {
    final now = DateTime.now();
    // If a barcode scan occurred within the last 2000ms, swallow the pop request
    if (_lastScanTime != null && now.difference(_lastScanTime!).inMilliseconds < 2000) {
      debugPrint('[OutwardScreen] Swallowed pop attempt from scanner keys');
      return false;
    }

    if (_scannedItems.isNotEmpty) {
      final int count = _scannedItems.length;
      final bool? discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
              SizedBox(width: 8),
              Text(
                'Discard Dispatch?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          content: Text(
            'You have scanned $count serial number${count == 1 ? "" : "s"}. Leaving will discard this dispatch and clear the session.',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard & Leave', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (discard != true) {
        return false;
      }
    }

    // User is intentionally discarding/leaving: clear any unsubmitted draft so home screen won't show it
    await SessionRecoveryService().clearDraft();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final canPop = await _handleWillPop();
        if (canPop) {
          if (!mounted) return;
          Navigator.of(context).pop();
        }
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
              onPressed: () async {
                final canPop = await _handleWillPop();
                if (canPop) {
                  if (!mounted) return;
                  Navigator.of(context).pop();
                }
              },
            ),
          ),
          actions: [
            FlushLagButton(onCustomFlush: _flushScreenLag),
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
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [UpperCaseTextFormatter()],
            decoration: InputDecoration(
              hintText: 'Search dealer shop or city...',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            onChanged: (val) => setState(() => _shopSearch = val),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.storefront_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            _shopSearch.trim().isNotEmpty
                                ? 'No dealer shop matching "$_shopSearch"'
                                : 'No shops available',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Shops are synced automatically from TallyPrime ledgers.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => _loadMetadata(forceRefresh: true),
                            icon: const Icon(Icons.sync_rounded, size: 18),
                            label: const Text('Refresh Shops'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3C3489),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
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
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              s.name,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                            ),
                                          ),
                                          if (s.id.startsWith('offline_'))
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFEF3C7),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text('Offline Shop', style: TextStyle(fontSize: 10, color: Color(0xFF92400E), fontWeight: FontWeight.bold)),
                                            ),
                                        ],
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
    final isTallyMode = _tallyVoucher != null;
    final sourceProducts = isTallyMode ? _tallyBillProducts : _products;
    final filtered = sourceProducts.where((p) {
      final q = _productSearch.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.brand.toLowerCase().contains(q) ||
          p.model.toLowerCase().contains(q);
    }).toList();

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.isTablet ? 24 : 16,
        vertical: context.isLandscapeTablet ? 8 : 16,
      ),
      child: RefreshIndicator(
        onRefresh: () => isTallyMode ? Future.value() : _loadMetadata(forceRefresh: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
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
                  SizedBox(height: context.isLandscapeTablet ? 8 : 12),

                  // Bill Number input
                  TextField(
                    controller: _billNumberController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Bill / Invoice No (e.g. BILL-1024, INV-8841)',
                      prefixIcon: const Icon(Icons.receipt_long, size: 20, color: Color(0xFF4F46E5)),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: context.isLandscapeTablet ? 10 : 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  SizedBox(height: context.isLandscapeTablet ? 6 : 8),

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
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: context.isLandscapeTablet ? 10 : 14,
                      ),
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
                  SizedBox(height: context.isLandscapeTablet ? 8 : 14),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isTallyMode
                            ? 'Models in Tally Bill (${_tallyVoucher!.voucherNumber}):'
                            : 'Select Model to Dispatch:',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                      ),
                      if (!isTallyMode)
                        Row(
                          children: [
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
                    ],
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: const [UpperCaseTextFormatter()],
                    decoration: InputDecoration(
                      hintText: isTallyMode
                          ? 'Search models in Tally Bill ${_tallyVoucher!.voucherNumber}...'
                          : 'Search appliance model (e.g. GXI 360)...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: context.isLandscapeTablet ? 10 : 14,
                      ),
                      suffixIcon: _loadingProducts && !isTallyMode
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
                      if (!isTallyMode && val.trim().length >= 2 && filtered.isEmpty && !_loadingProducts) {
                        _loadMetadata(forceRefresh: true);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFF94A3B8)),
                        const SizedBox(height: 12),
                        Text(
                          isTallyMode
                              ? (_productSearch.isEmpty
                                  ? 'No models in Tally Bill ${_tallyVoucher!.voucherNumber}'
                                  : 'No model matching "$_productSearch" in Tally Bill ${_tallyVoucher!.voucherNumber}')
                              : (_productSearch.isEmpty
                                  ? 'No models available'
                                  : 'No local match for "$_productSearch"'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF1E293B),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isTallyMode
                              ? 'Only models parsed from Tally Bill ${_tallyVoucher!.voucherNumber} can be dispatched.'
                              : (_productSearch.isNotEmpty
                                  ? 'Model "$_productSearch" not found. Models are synced from TallyPrime.'
                                  : 'Sync your catalog directly from TallyPrime to see latest stock items.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                        if (!isTallyMode) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, idx) {
                    final p = filtered[idx];
                    final itm = isTallyMode ? _findTallyItemForProduct(p) : null;
                    final target = itm?.quantity.toInt() ?? 0;
                    final count = _getScannedCountForProduct(p);
                    final isDone = isTallyMode && target > 0 && count >= target;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: isDone ? const Color(0xFFF0FDF4) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            SystemChannels.textInput.invokeMethod('TextInput.hide');
                            HardwareScannerService().clearBuffer();
                            setState(() {
                              _selectedProduct = p;
                              _activeFilterModelId = p.id;
                              if (_tallyVoucher != null) {
                                final matchItem = _findTallyItemForProduct(p);
                                if (matchItem != null) {
                                  _selectedTallyItemId = matchItem.id;
                                }
                              }
                              _currentStep = 3;
                            });
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDone ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
                                width: isDone ? 1.5 : 1.0,
                              ),
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
                                        isTallyMode
                                            ? '${p.brand} • ${p.model} • Target: $target units'
                                            : '${p.brand} • ${p.model}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDone ? const Color(0xFF15803D) : const Color(0xFF64748B),
                                          fontFamily: isTallyMode ? null : 'monospace',
                                          fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                                        ),
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
                                if (isTallyMode) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isDone ? const Color(0xFF16A34A) : const Color(0xFF0284C7),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      isDone ? 'Completed ($count/$target)' : '$count / $target',
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ] else ...[
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
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: filtered.length,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTallyTargetBar(BuildContext context) {
    if (_tallyVoucher == null) return const SizedBox.shrink();
    final v = _tallyVoucher!;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: Color(0xFF16A34A), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tally Bill: ${v.voucherNumber} • ${v.partyName}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF166534)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Auto-Synced',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              InkWell(
                onTap: () => _showVehicleInputDialog(context),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _deliveryRefController.text.trim().isNotEmpty
                          ? const Color(0xFF86EFAC)
                          : const Color(0xFFFCD34D),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_shipping_outlined,
                        size: 14,
                        color: _deliveryRefController.text.trim().isNotEmpty
                            ? const Color(0xFF15803D)
                            : const Color(0xFFB45309),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _deliveryRefController.text.trim().isNotEmpty
                            ? 'Vehicle: ${_deliveryRefController.text.trim()}'
                            : '+ Input Vehicle No',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _deliveryRefController.text.trim().isNotEmpty
                              ? const Color(0xFF15803D)
                              : const Color(0xFFB45309),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.edit,
                        size: 11,
                        color: _deliveryRefController.text.trim().isNotEmpty
                            ? const Color(0xFF15803D)
                            : const Color(0xFFB45309),
                      ),
                    ],
                  ),
                ),
              ),
              if (v.transporterName != null && v.transporterName!.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Transporter: ${v.transporterName!.trim()}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF15803D)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          if (v.items.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'TAP MODEL TO SCAN:',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFF15803D),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: v.items.map((item) {
                final prod = _resolveTallyProduct(item);
                final isSelected = _selectedTallyItemId != null
                    ? _selectedTallyItemId == item.id
                    : _selectedProduct?.id == prod.id;
                final count = _scannedItems.where((s) {
                  final p = s.product;
                  if (p == null) return false;
                  return p.id == prod.id ||
                         p.name.trim().toLowerCase() == prod.name.trim().toLowerCase() ||
                         p.model.trim().toLowerCase() == prod.model.trim().toLowerCase();
                }).length;

                final target = item.quantity.toInt();
                final isDone = count >= target && target > 0;

                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedTallyItemId = item.id;
                      _selectedProduct = prod;
                      _activeFilterModelId = prod.id;
                      if (prod.hasDualSerial) _outwardUnitType = 'indoor';
                    });
                    _showToast('Scanning: ${prod.model}', const Color(0xFF16A34A));
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF1E1B4B)
                          : (isDone ? const Color(0xFFDCFCE7) : Colors.white),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF4F46E5)
                            : (isDone ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1)),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected
                          ? [const BoxShadow(color: Color(0x224F46E5), blurRadius: 4, offset: Offset(0, 2))]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected
                              ? Icons.bolt
                              : (isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded),
                          size: 14,
                          color: isSelected
                              ? Colors.amber
                              : (isDone ? const Color(0xFF16A34A) : const Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${item.itemName} ($count/$target)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : (isDone ? const Color(0xFF166534) : const Color(0xFF1E293B)),
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF1E1B4B)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // STEP 3: Scanning & Review
  Widget _buildScanningAndReviewView() {
    final matchedCount = _scannedItems.where((e) => e.isMatched).length;
    final recordedOnlyCount = _scannedItems.where((e) => !e.isMatched).length;

    // Separate indoor and outdoor unit counts for currently active dual serial model
    final currentProdId = _selectedProduct?.id;
    final int dualIndoorCount = _selectedProduct == null
        ? 0
        : _scannedItems.where((e) {
            final pid = e.product?.id ?? _selectedProduct?.id;
            return pid == currentProdId && e.unitType?.toLowerCase() == 'indoor';
          }).length;
    final int dualOutdoorCount = _selectedProduct == null
        ? 0
        : _scannedItems.where((e) {
            final pid = e.product?.id ?? _selectedProduct?.id;
            return pid == currentProdId && e.unitType?.toLowerCase() == 'outdoor';
          }).length;

    // Distinct models in current batch + selected + all Tally bill items
    final Map<String, Product> modelMap = {};
    if (_tallyVoucher != null) {
      for (final item in _tallyVoucher!.items) {
        final p = _resolveTallyProduct(item);
        modelMap[p.id] = p;
      }
    }
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
          if (_tallyVoucher != null) _buildTallyTargetBar(context),
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
                  InkWell(
                    onTap: () => _showVehicleInputDialog(context),
                    borderRadius: BorderRadius.circular(context.isTablet ? 8 : 6),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.isTablet ? 10 : 7,
                        vertical: context.isLandscapeTablet ? 3 : (context.isTablet ? 5 : 3),
                      ),
                      decoration: BoxDecoration(
                        color: _deliveryRefController.text.trim().isNotEmpty
                            ? const Color(0xFFF1F5F9)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(context.isTablet ? 8 : 6),
                        border: Border.all(
                          color: _deliveryRefController.text.trim().isNotEmpty
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFFFDE68A),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_shipping_outlined,
                            size: context.isTablet ? 15 : 12,
                            color: _deliveryRefController.text.trim().isNotEmpty
                                ? const Color(0xFF475569)
                                : const Color(0xFF92400E),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _deliveryRefController.text.trim().isNotEmpty
                                ? 'Vehicle: ${_deliveryRefController.text.trim()}'
                                : '+ Vehicle No',
                            style: TextStyle(
                              fontSize: context.isLandscapeTablet ? 11 : (context.isTablet ? 12 : 10),
                              fontWeight: FontWeight.bold,
                              color: _deliveryRefController.text.trim().isNotEmpty
                                  ? const Color(0xFF334155)
                                  : const Color(0xFF92400E),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            Icons.edit,
                            size: context.isTablet ? 12 : 10,
                            color: _deliveryRefController.text.trim().isNotEmpty
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFFB45309),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: context.isTablet ? 8 : 6),
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
                                    'Indoor ($dualIndoorCount)',
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
                                    'Outdoor ($dualOutdoorCount)',
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
                  Builder(
                    builder: (context) {
                      final dualIn = _scannedItems.where((e) => e.unitType?.toLowerCase() == 'indoor').length;
                      final dualOut = _scannedItems.where((e) => e.unitType?.toLowerCase() == 'outdoor').length;
                      final hasDual = dualIn > 0 || dualOut > 0 || _selectedProduct?.hasDualSerial == true;
                      return Text(
                        hasDual
                            ? '${_scannedItems.length} Serials (Indoor: $dualIn, Outdoor: $dualOut)'
                            : '${_scannedItems.length} Serials',
                        style: TextStyle(
                          fontSize: context.isLandscapeTablet ? 12 : (context.isTablet ? 14 : 11),
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F172A),
                        ),
                      );
                    },
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
                    final mIn = _scannedItems.where((e) => (e.product?.id ?? _selectedProduct?.id) == prod.id && e.unitType?.toLowerCase() == 'indoor').length;
                    final mOut = _scannedItems.where((e) => (e.product?.id ?? _selectedProduct?.id) == prod.id && e.unitType?.toLowerCase() == 'outdoor').length;
                    final showDual = prod.hasDualSerial || mIn > 0 || mOut > 0;
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
                        label: Text(showDual ? '${prod.model} ($count [In: $mIn, Out: $mOut])' : '${prod.model} ($count)'),
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
                          FocusManager.instance.primaryFocus?.unfocus();
                          SystemChannels.textInput.invokeMethod('TextInput.hide');
                          HardwareScannerService().clearBuffer();
                          setState(() {
                            _activeFilterModelId = val ? prod.id : 'ALL';
                            if (val) {
                              _selectedProduct = prod;
                              if (_tallyVoucher != null) {
                                final matchItem = _tallyVoucher!.items.where((it) {
                                  final p = _resolveTallyProduct(it);
                                  return p.id == prod.id;
                                }).firstOrNull;
                                if (matchItem != null) {
                                  _selectedTallyItemId = matchItem.id;
                                }
                              }
                            }
                          });
                        },
                      ),
                    );
                  }),

                  // Switch Model Chip (only shown in manual mode, hidden in Tally bill mode)
                  if (_tallyVoucher == null)
                    ActionChip(
                      focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      avatar: Icon(Icons.swap_horiz_rounded, size: context.isLandscapeTablet ? 13 : (context.isTablet ? 16 : 14), color: const Color(0xFF4F46E5)),
                      label: const Text('Switch Model'),
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
        _persistDraft();
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
                      _persistDraft();
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
