import 'dart:convert';
import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'api_service.dart';
import 'offline_manager.dart';

enum QueueType { inward, outward }

class QueuedCategory {
  final String tempId;
  final String name;
  final bool hasDualSerial;
  final DateTime createdAt;

  QueuedCategory({
    required this.tempId,
    required this.name,
    this.hasDualSerial = false,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'temp_id': tempId,
    'name': name,
    'has_dual_serial': hasDualSerial,
    'created_at': createdAt.toIso8601String(),
  };

  factory QueuedCategory.fromJson(Map<String, dynamic> json) => QueuedCategory(
    tempId: json['temp_id'] ?? json['id'] ?? '',
    name: json['name'] ?? '',
    hasDualSerial: json['has_dual_serial'] ?? false,
    createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
  );
}

class QueuedProduct {
  final String tempId;
  final String brand;
  final String model;
  final String categoryId;
  final String? categoryName;
  final String? name;
  final String? sku;
  final String? sizeCapacity;
  final String unit;
  final bool serialNumberRequired;
  final String? description;
  final int openingStockQty;
  final DateTime createdAt;

  QueuedProduct({
    required this.tempId,
    required this.brand,
    required this.model,
    required this.categoryId,
    this.categoryName,
    this.name,
    this.sku,
    this.sizeCapacity,
    this.unit = 'piece',
    this.serialNumberRequired = true,
    this.description,
    this.openingStockQty = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'temp_id': tempId,
    'brand': brand,
    'model': model,
    'category_id': categoryId,
    'category_name': categoryName,
    'name': name,
    'sku': sku,
    'size_capacity': sizeCapacity,
    'unit': unit,
    'serial_number_required': serialNumberRequired,
    'description': description,
    'opening_stock_qty': openingStockQty,
    'created_at': createdAt.toIso8601String(),
  };

  factory QueuedProduct.fromJson(Map<String, dynamic> json) => QueuedProduct(
    tempId: json['temp_id'] ?? json['id'] ?? '',
    brand: json['brand'] ?? '',
    model: json['model'] ?? '',
    categoryId: json['category_id'] ?? '',
    categoryName: json['category_name'],
    name: json['name'],
    sku: json['sku'],
    sizeCapacity: json['size_capacity'],
    unit: json['unit'] ?? 'piece',
    serialNumberRequired: json['serial_number_required'] ?? true,
    description: json['description'],
    openingStockQty: json['opening_stock_qty'] ?? 0,
    createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
  );
}

class QueuedShop {
  final String tempId;
  final String name;
  final String city;
  final String? phone;
  final DateTime createdAt;

  QueuedShop({
    required this.tempId,
    required this.name,
    this.city = '',
    this.phone,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'temp_id': tempId,
    'name': name,
    'city': city,
    'phone': phone,
    'created_at': createdAt.toIso8601String(),
  };

  factory QueuedShop.fromJson(Map<String, dynamic> json) => QueuedShop(
    tempId: json['temp_id'] ?? json['id'] ?? '',
    name: json['name'] ?? '',
    city: json['city'] ?? '',
    phone: json['phone'],
    createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
  );
}

class QueuedSerialDetail {
  final int index;
  final String serialNumber;
  final String productId;
  final String productName;
  final String model;
  final String brand;
  final String? unitType;
  final String? inwardType;

  QueuedSerialDetail({
    required this.index,
    required this.serialNumber,
    required this.productId,
    required this.productName,
    required this.model,
    required this.brand,
    this.unitType,
    this.inwardType,
  });
}

class QueuedBatch {
  final String id;
  final QueueType type;
  final DateTime createdAt;
  final Map<String, dynamic> payload;
  final String description;

  QueuedBatch({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.payload,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'created_at': createdAt.toIso8601String(),
    'payload': payload,
    'description': description,
  };

  factory QueuedBatch.fromJson(Map<String, dynamic> json) => QueuedBatch(
    id: json['id'],
    type: json['type'] == 'inward' ? QueueType.inward : QueueType.outward,
    createdAt: DateTime.parse(json['created_at']),
    payload: Map<String, dynamic>.from(json['payload']),
    description: json['description'] ?? '',
  );

  /// Returns all scanned serials with full metadata, resolved across single or multi-batch formats
  List<QueuedSerialDetail> get serialDetails {
    final List<QueuedSerialDetail> result = [];
    int counter = 1;

    // 1. Check if payload has 'items' (multi-batch format)
    if (payload['items'] is List && (payload['items'] as List).isNotEmpty) {
      for (final rawItem in (payload['items'] as List)) {
        if (rawItem is Map) {
          final prodId = rawItem['product_id']?.toString() ?? '';
          final prod = prodId.isNotEmpty ? OfflineManager().getProductById(prodId) : null;
          final prodName = rawItem['product_name']?.toString() ?? prod?.name ?? 'Appliance';
          final prodModel = rawItem['product_model']?.toString() ?? prod?.model ?? 'Model';
          final prodBrand = rawItem['product_brand']?.toString() ?? prod?.brand ?? '';
          final inType = rawItem['inward_type']?.toString() ?? payload['inward_type']?.toString();
          final unitTypes = rawItem['unit_types'] is Map ? Map<String, dynamic>.from(rawItem['unit_types']) : {};

          final rawSerials = rawItem['serials'] ?? rawItem['serial_numbers'];
          if (rawSerials is List) {
            for (final s in rawSerials) {
              String? sn;
              String? uType;
              if (s is Map) {
                sn = s['serial_number']?.toString();
                uType = s['unit_type']?.toString();
              } else if (s is String) {
                sn = s;
              } else if (s != null) {
                sn = s.toString();
              }

              if (sn != null && sn.trim().isNotEmpty) {
                final cleanSn = sn.trim();
                uType ??= unitTypes[cleanSn]?.toString();
                result.add(QueuedSerialDetail(
                  index: counter++,
                  serialNumber: cleanSn,
                  productId: prodId,
                  productName: prodName,
                  model: prodModel,
                  brand: prodBrand,
                  unitType: uType,
                  inwardType: inType,
                ));
              }
            }
          }
        }
      }
    }

    // 2. Check top-level serial lists (single-batch format)
    final topSerials = payload['serial_numbers'] ?? payload['serials'];
    if (topSerials is List && topSerials.isNotEmpty) {
      final prodId = payload['product_id']?.toString() ?? '';
      final prod = prodId.isNotEmpty ? OfflineManager().getProductById(prodId) : null;
      final prodName = payload['product_name']?.toString() ?? prod?.name ?? 'Appliance';
      final prodModel = payload['product_model']?.toString() ?? prod?.model ?? 'Model';
      final prodBrand = payload['product_brand']?.toString() ?? prod?.brand ?? '';
      final inType = payload['inward_type']?.toString();
      final unitTypes = payload['unit_types'] is Map ? Map<String, dynamic>.from(payload['unit_types']) : {};

      for (final s in topSerials) {
        String? sn;
        String? uType;
        if (s is Map) {
          sn = s['serial_number']?.toString();
          uType = s['unit_type']?.toString();
        } else if (s is String) {
          sn = s;
        } else if (s != null) {
          sn = s.toString();
        }

        if (sn != null && sn.trim().isNotEmpty) {
          final cleanSn = sn.trim();
          if (!result.any((r) => r.serialNumber == cleanSn)) {
            uType ??= unitTypes[cleanSn]?.toString();
            result.add(QueuedSerialDetail(
              index: counter++,
              serialNumber: cleanSn,
              productId: prodId,
              productName: prodName,
              model: prodModel,
              brand: prodBrand,
              unitType: uType,
              inwardType: inType,
            ));
          }
        }
      }
    }

    return result;
  }

  /// Total count of serials stored in this queued batch
  int get totalSerialsCount => serialDetails.length;

  /// Resolved shop destination name for outward batches
  String get shopName {
    if (payload['shop_name'] != null && payload['shop_name'].toString().trim().isNotEmpty) {
      return payload['shop_name'].toString().trim();
    }
    final shopId = payload['shop_id']?.toString() ?? '';
    if (shopId.isNotEmpty) {
      final s = OfflineManager().getShopById(shopId);
      if (s != null) return s.name;
    }
    return '';
  }

  String? get billNumber => payload['bill_number']?.toString().trim();
  String? get deliveryReference => payload['delivery_reference']?.toString().trim();
  String? get invoiceReference => payload['invoice_reference']?.toString().trim();
  String? get remarks => payload['remarks']?.toString().trim();

  String? get inwardType {
    if (payload['inward_type'] != null) return payload['inward_type'].toString();
    if (payload['items'] is List && (payload['items'] as List).isNotEmpty) {
      final first = (payload['items'] as List).first;
      if (first is Map && first['inward_type'] != null) {
        return first['inward_type'].toString();
      }
    }
    return null;
  }

  /// Creates a copy of this batch with a specific serial number removed
  QueuedBatch removeSerial(String serialNumber) {
    final newPayload = Map<String, dynamic>.from(payload);
    final targetUpper = serialNumber.trim().toUpperCase();

    if (newPayload['items'] is List) {
      final items = List<Map<String, dynamic>>.from(
        (newPayload['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      for (final item in items) {
        if (item['serials'] is List) {
          final sList = List<dynamic>.from(item['serials']);
          sList.removeWhere((s) {
            final sn = (s is Map ? s['serial_number'] : s)?.toString().trim().toUpperCase();
            return sn == targetUpper;
          });
          item['serials'] = sList;
        }

        if (item['serial_numbers'] is List) {
          final snList = List<dynamic>.from(item['serial_numbers']);
          snList.removeWhere((s) => s.toString().trim().toUpperCase() == targetUpper);
          item['serial_numbers'] = snList;
        }

        if (item['unit_types'] is Map) {
          final uMap = Map<String, dynamic>.from(item['unit_types']);
          uMap.removeWhere((k, v) => k.trim().toUpperCase() == targetUpper);
          item['unit_types'] = uMap;
        }
      }

      // Remove items with 0 serials left
      items.removeWhere((item) {
        final s1 = item['serials'] as List?;
        final s2 = item['serial_numbers'] as List?;
        return (s1 == null || s1.isEmpty) && (s2 == null || s2.isEmpty);
      });

      newPayload['items'] = items;
    }

    if (newPayload['serials'] is List) {
      final sList = List<dynamic>.from(newPayload['serials']);
      sList.removeWhere((s) {
        final sn = (s is Map ? s['serial_number'] : s)?.toString().trim().toUpperCase();
        return sn == targetUpper;
      });
      newPayload['serials'] = sList;
    }

    if (newPayload['serial_numbers'] is List) {
      final snList = List<dynamic>.from(newPayload['serial_numbers']);
      snList.removeWhere((s) => s.toString().trim().toUpperCase() == targetUpper);
      newPayload['serial_numbers'] = snList;
    }

    if (newPayload['unit_types'] is Map) {
      final uMap = Map<String, dynamic>.from(newPayload['unit_types']);
      uMap.removeWhere((k, v) => k.trim().toUpperCase() == targetUpper);
      newPayload['unit_types'] = uMap;
    }

    return QueuedBatch(
      id: id,
      type: type,
      createdAt: createdAt,
      payload: newPayload,
      description: description,
    );
  }
}

class OfflineQueueService {
  static final OfflineQueueService _instance = OfflineQueueService._internal();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._internal();

  static const String _storageKey = 'godown_offline_queue';
  static const String _pendingProductsKey = 'godown_offline_pending_products';
  static const String _pendingCategoriesKey = 'godown_offline_pending_categories';
  static const String _pendingShopsKey = 'godown_offline_pending_shops';

  // --- BATCH QUEUE CRUD ---
  Future<List<QueuedBatch>> getQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? [];
    return raw.map((str) => QueuedBatch.fromJson(jsonDecode(str))).toList();
  }

  Future<void> enqueue(QueuedBatch batch) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? [];
    raw.add(jsonEncode(batch.toJson()));
    await prefs.setStringList(_storageKey, raw);
  }

  Future<void> update(QueuedBatch updatedBatch) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getQueue();
    final idx = list.indexWhere((b) => b.id == updatedBatch.id);
    if (idx != -1) {
      if (updatedBatch.totalSerialsCount == 0) {
        list.removeAt(idx);
      } else {
        list[idx] = updatedBatch;
      }
      final raw = list.map((b) => jsonEncode(b.toJson())).toList();
      await prefs.setStringList(_storageKey, raw);
    }
  }

  Future<void> remove(String batchId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getQueue();
    list.removeWhere((b) => b.id == batchId);
    final raw = list.map((b) => jsonEncode(b.toJson())).toList();
    await prefs.setStringList(_storageKey, raw);
  }

  Future<void> removeSerialFromBatch(String batchId, String serialNumber) async {
    final list = await getQueue();
    final idx = list.indexWhere((b) => b.id == batchId);
    if (idx != -1) {
      final updated = list[idx].removeSerial(serialNumber);
      await update(updated);
    }
  }

  Future<void> clearQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<int> queueCount() async {
    final list = await getQueue();
    return list.length;
  }

  // --- PENDING OFFLINE PRODUCTS (MODELS) CRUD ---
  Future<List<QueuedProduct>> getPendingProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingProductsKey) ?? [];
    return raw.map((str) => QueuedProduct.fromJson(jsonDecode(str))).toList();
  }

  Future<void> enqueueProduct(QueuedProduct product) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingProductsKey) ?? [];
    // Prevent duplicate entries for same tempId
    raw.removeWhere((str) {
      try {
        final j = jsonDecode(str);
        return j['temp_id'] == product.tempId;
      } catch (_) {
        return false;
      }
    });
    raw.add(jsonEncode(product.toJson()));
    await prefs.setStringList(_pendingProductsKey, raw);
  }

  Future<void> removePendingProduct(String tempId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getPendingProducts();
    list.removeWhere((p) => p.tempId == tempId);
    final raw = list.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_pendingProductsKey, raw);
  }

  Future<int> pendingProductCount() async {
    final list = await getPendingProducts();
    return list.length;
  }

  // --- PENDING OFFLINE CATEGORIES CRUD ---
  Future<List<QueuedCategory>> getPendingCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingCategoriesKey) ?? [];
    return raw.map((str) => QueuedCategory.fromJson(jsonDecode(str))).toList();
  }

  Future<void> enqueueCategory(QueuedCategory category) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingCategoriesKey) ?? [];
    raw.removeWhere((str) {
      try {
        final j = jsonDecode(str);
        return j['temp_id'] == category.tempId;
      } catch (_) {
        return false;
      }
    });
    raw.add(jsonEncode(category.toJson()));
    await prefs.setStringList(_pendingCategoriesKey, raw);
  }

  Future<void> removePendingCategory(String tempId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getPendingCategories();
    list.removeWhere((c) => c.tempId == tempId);
    final raw = list.map((c) => jsonEncode(c.toJson())).toList();
    await prefs.setStringList(_pendingCategoriesKey, raw);
  }

  // --- PENDING OFFLINE SHOPS CRUD ---
  Future<List<QueuedShop>> getPendingShops() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingShopsKey) ?? [];
    return raw.map((str) => QueuedShop.fromJson(jsonDecode(str))).toList();
  }

  Future<void> enqueueShop(QueuedShop shop) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingShopsKey) ?? [];
    raw.removeWhere((str) {
      try {
        final j = jsonDecode(str);
        return j['temp_id'] == shop.tempId;
      } catch (_) {
        return false;
      }
    });
    raw.add(jsonEncode(shop.toJson()));
    await prefs.setStringList(_pendingShopsKey, raw);
  }

  Future<void> removePendingShop(String tempId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getPendingShops();
    list.removeWhere((s) => s.tempId == tempId);
    final raw = list.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_pendingShopsKey, raw);
  }

  Future<int> pendingShopCount() async {
    final list = await getPendingShops();
    return list.length;
  }

  Future<int> totalPendingCount() async {
    final b = await queueCount();
    final p = await pendingProductCount();
    final s = await pendingShopCount();
    return b + p + s;
  }

  // --- MODEL & CATEGORY SYNC WITH SERVER ID REMAPPING ---
  /// Syncs any offline-created categories and models to backend, remapping temporary IDs
  /// in local cache and all queued batches to ensure genuine backend product IDs.
  Future<Map<String, String>> syncPendingModelsAndCategories() async {
    final Map<String, String> categoryMap = {};
    final Map<String, String> productMap = {};
    final api = ApiService();

    // 1. Fetch live categories from server
    List<Category> serverCats = [];
    try {
      serverCats = await api.getCategories(forceRefresh: true);
    } catch (_) {
      serverCats = OfflineManager().categories;
    }

    // 2. Sync pending categories
    final pendingCats = await getPendingCategories();
    for (final cat in pendingCats) {
      try {
        final match = serverCats.firstWhere(
          (c) => c.name.trim().toLowerCase() == cat.name.trim().toLowerCase(),
          orElse: () => Category(id: '', name: ''),
        );
        String realCatId;
        if (match.id.isNotEmpty) {
          realCatId = match.id;
        } else {
          final created = await api.createCategory(
            name: cat.name,
            hasDualSerial: cat.hasDualSerial,
            allowOfflineFallback: false,
          );
          realCatId = created.id;
          serverCats.add(created);
        }
        categoryMap[cat.tempId] = realCatId;
        await removePendingCategory(cat.tempId);
      } catch (e) {
        debugPrint('[OfflineQueueService] Failed to sync pending category ${cat.name}: $e');
      }
    }

    // Helper to resolve ANY category string (like 'cat_ac', 'offline_cat_...', or name) to a valid server UUID
    String resolveServerCategoryId(String inputCatId, String? catName) {
      if (categoryMap.containsKey(inputCatId)) {
        return categoryMap[inputCatId]!;
      }

      final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

      // If already a valid UUID and present in server categories
      if (uuidRegex.hasMatch(inputCatId) && serverCats.any((c) => c.id == inputCatId)) {
        return inputCatId;
      }

      final nameLower = (catName ?? '').trim().toLowerCase();
      final idLower = inputCatId.trim().toLowerCase();

      // Check exact category name match
      for (final sc in serverCats) {
        if (sc.name.trim().toLowerCase() == nameLower && sc.id.isNotEmpty) {
          return sc.id;
        }
      }

      // Check category name and mock ID keywords
      for (final sc in serverCats) {
        final scLower = sc.name.toLowerCase();
        if (idLower == 'cat_ac' || nameLower.contains('air cond') || nameLower.contains('ac')) {
          if (scLower == 'ac' || scLower.contains('ac')) return sc.id;
        }
        if (idLower == 'cat_ref' || nameLower.contains('ref') || nameLower.contains('fridge')) {
          if (scLower.contains('ref')) return sc.id;
        }
        if (idLower == 'cat_wm' || nameLower.contains('wash') || nameLower.contains('wm')) {
          if (scLower.contains('wm')) return sc.id;
        }
        if (idLower == 'cat_tv' || nameLower.contains('tv') || nameLower.contains('led')) {
          if (scLower.contains('tv')) return sc.id;
        }
        if (idLower == 'cat_mw' || nameLower.contains('micro') || nameLower.contains('oven')) {
          if (scLower.contains('micro') || scLower.contains('oven')) return sc.id;
        }
        if (idLower == 'cat_cooler' || nameLower.contains('cool')) {
          if (scLower.contains('cool')) return sc.id;
        }
      }

      // Check partial substring match
      if (nameLower.isNotEmpty) {
        for (final sc in serverCats) {
          final scLower = sc.name.toLowerCase();
          if (scLower.contains(nameLower) || nameLower.contains(scLower)) {
            return sc.id;
          }
        }
      }

      // If input is already a valid UUID format, keep it
      if (uuidRegex.hasMatch(inputCatId)) {
        return inputCatId;
      }

      // Fallback to first available server category with valid UUID
      if (serverCats.isNotEmpty) {
        final valid = serverCats.firstWhere((c) => uuidRegex.hasMatch(c.id), orElse: () => serverCats.first);
        return valid.id;
      }

      return inputCatId;
    }

    // 3. Fetch server products
    List<Product> serverProds = [];
    try {
      serverProds = await api.getProducts(forceRefresh: true);
    } catch (_) {
      serverProds = OfflineManager().products;
    }

    // 4. Sync pending products (models)
    final pendingProds = await getPendingProducts();
    for (final p in pendingProds) {
      try {
        final effectiveCatId = resolveServerCategoryId(p.categoryId, p.categoryName);

        // Check if server already has product with matching brand and model (case-insensitive)
        final match = serverProds.firstWhere(
          (sp) => sp.brand.trim().toLowerCase() == p.brand.trim().toLowerCase() &&
                  sp.model.trim().toLowerCase() == p.model.trim().toLowerCase(),
          orElse: () => Product(
            id: '',
            name: '',
            categoryId: '',
            brand: '',
            model: '',
            unit: '',
            serialNumberRequired: true,
            currentStockQty: 0,
            outOfStockReminder: false,
          ),
        );

        Product realProduct;
        if (match.id.isNotEmpty) {
          realProduct = match;
        } else {
          realProduct = await api.createProduct(
            brand: p.brand,
            model: p.model,
            categoryId: effectiveCatId,
            name: p.name,
            sku: p.sku,
            sizeCapacity: p.sizeCapacity,
            unit: p.unit,
            serialNumberRequired: p.serialNumberRequired,
            description: p.description,
            openingStockQty: p.openingStockQty,
            allowOfflineFallback: false,
          );
          serverProds.add(realProduct);
        }

        productMap[p.tempId] = realProduct.id;
        await removePendingProduct(p.tempId);
        OfflineManager().remapProductId(p.tempId, realProduct.id, updatedProduct: realProduct);
      } catch (e) {
        debugPrint('[OfflineQueueService] Failed to sync pending model ${p.brand} ${p.model}: $e');
      }
    }

    // 5. Scan all queued batches for any remaining offline_prod_ IDs that need remapping
    final batches = await getQueue();
    for (final b in batches) {
      final List<Map<String, dynamic>> itemsToCheck = [];
      if (b.payload['items'] is List) {
        itemsToCheck.addAll(
          (b.payload['items'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
        );
      }
      if (b.payload['product_id'] != null) {
        itemsToCheck.add(b.payload);
      }

      for (final item in itemsToCheck) {
        final pid = item['product_id']?.toString();
        if (pid != null && pid.startsWith('offline_prod_') && !productMap.containsKey(pid)) {
          final localProd = OfflineManager().getProductById(pid);
          final brand = item['product_brand']?.toString() ?? localProd?.brand ?? '';
          final model = item['product_model']?.toString() ?? localProd?.model ?? '';
          final name = item['product_name']?.toString() ?? localProd?.name;
          final catId = localProd?.categoryId ?? '';
          final catName = localProd?.categoryName;

          if (brand.isNotEmpty && model.isNotEmpty) {
            try {
              final match = serverProds.firstWhere(
                (sp) => sp.brand.trim().toLowerCase() == brand.trim().toLowerCase() &&
                        sp.model.trim().toLowerCase() == model.trim().toLowerCase(),
                orElse: () => Product(
                  id: '',
                  name: '',
                  categoryId: '',
                  brand: '',
                  model: '',
                  unit: '',
                  serialNumberRequired: true,
                  currentStockQty: 0,
                  outOfStockReminder: false,
                ),
              );

              Product realProd;
              if (match.id.isNotEmpty) {
                realProd = match;
              } else {
                final effectiveCatId = resolveServerCategoryId(catId, catName);
                realProd = await api.createProduct(
                  brand: brand,
                  model: model,
                  categoryId: effectiveCatId,
                  name: name,
                  allowOfflineFallback: false,
                );
                serverProds.add(realProd);
              }
              productMap[pid] = realProd.id;
              OfflineManager().remapProductId(pid, realProd.id, updatedProduct: realProd);
            } catch (e) {
              debugPrint('[OfflineQueueService] Failed to resolve offline batch product $pid ($brand $model): $e');
            }
          }
        }
      }
    }

    // 6. Remap all queued batches if any products were mapped
    if (productMap.isNotEmpty) {
      final currentBatches = await getQueue();
      for (final b in currentBatches) {
        bool modified = false;
        final newPayload = Map<String, dynamic>.from(b.payload);

        // Check single batch product_id
        if (newPayload['product_id'] != null && productMap.containsKey(newPayload['product_id'])) {
          newPayload['product_id'] = productMap[newPayload['product_id']];
          modified = true;
        }

        // Check multi batch items
        if (newPayload['items'] is List) {
          final items = List<Map<String, dynamic>>.from(
            (newPayload['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
          );
          for (final item in items) {
            final pid = item['product_id']?.toString();
            if (pid != null && productMap.containsKey(pid)) {
              item['product_id'] = productMap[pid];
              modified = true;
            }
          }
          newPayload['items'] = items;
        }

        if (modified) {
          await update(QueuedBatch(
            id: b.id,
            type: b.type,
            createdAt: b.createdAt,
            payload: newPayload,
            description: b.description,
          ));
        }
      }

      // Also remap any queued dispatches in OfflineManager
      OfflineManager().remapDispatchesProductIds(productMap);
    }

    return productMap;
  }

  // --- SHOP SYNC WITH SERVER ID REMAPPING ---
  /// Syncs any offline-created shops to backend, remapping temporary IDs
  /// in local cache and all queued outward batches to ensure genuine backend shop IDs.
  Future<Map<String, String>> syncPendingShops() async {
    final Map<String, String> shopMap = {};
    final pendingShops = await getPendingShops();
    final api = ApiService();
    List<Shop> serverShops = [];
    try {
      serverShops = await api.getShops(forceRefresh: true);
    } catch (_) {
      serverShops = OfflineManager().shops;
    }

    for (final s in pendingShops) {
      try {
        final match = serverShops.firstWhere(
          (ss) => ss.name.trim().toLowerCase() == s.name.trim().toLowerCase(),
          orElse: () => Shop(id: '', name: '', city: '', isActive: true),
        );

        Shop realShop;
        if (match.id.isNotEmpty) {
          realShop = match;
        } else {
          realShop = await api.createShop(
            name: s.name,
            city: s.city,
            phone: s.phone,
            allowOfflineFallback: false,
          );
          serverShops.add(realShop);
        }

        shopMap[s.tempId] = realShop.id;
        await removePendingShop(s.tempId);
        OfflineManager().remapShopId(s.tempId, realShop.id, updatedShop: realShop);
      } catch (e) {
        debugPrint('[OfflineQueueService] Failed to sync pending shop ${s.name}: $e');
      }
    }

    // Scan all queued batches for any remaining offline_shop_ IDs
    final batches = await getQueue();
    for (final b in batches) {
      if (b.type == QueueType.outward) {
        final sid = b.payload['shop_id']?.toString();
        if (sid != null && sid.startsWith('offline_shop_') && !shopMap.containsKey(sid)) {
          final localShop = OfflineManager().getShopById(sid);
          final shopName = b.payload['shop_name']?.toString() ?? localShop?.name ?? '';
          if (shopName.isNotEmpty) {
            try {
              final match = serverShops.firstWhere(
                (ss) => ss.name.trim().toLowerCase() == shopName.trim().toLowerCase(),
                orElse: () => Shop(id: '', name: '', city: '', isActive: true),
              );

              Shop realShop;
              if (match.id.isNotEmpty) {
                realShop = match;
              } else {
                realShop = await api.createShop(
                  name: shopName,
                  city: localShop?.city ?? '',
                  phone: localShop?.phone,
                  allowOfflineFallback: false,
                );
                serverShops.add(realShop);
              }
              shopMap[sid] = realShop.id;
              OfflineManager().remapShopId(sid, realShop.id, updatedShop: realShop);
            } catch (e) {
              debugPrint('[OfflineQueueService] Failed to resolve offline batch shop $sid ($shopName): $e');
            }
          }
        }
      }
    }

    // Remap all queued outward batches if any shops were mapped
    if (shopMap.isNotEmpty) {
      final currentBatches = await getQueue();
      for (final b in currentBatches) {
        if (b.type == QueueType.outward) {
          final newPayload = Map<String, dynamic>.from(b.payload);
          final sid = newPayload['shop_id']?.toString();
          if (sid != null && shopMap.containsKey(sid)) {
            newPayload['shop_id'] = shopMap[sid];
            await update(QueuedBatch(
              id: b.id,
              type: b.type,
              createdAt: b.createdAt,
              payload: newPayload,
              description: b.description,
            ));
          }
        }
      }

      // Also remap any queued dispatches in OfflineManager
      OfflineManager().remapDispatchesShopIds(shopMap);
    }

    return shopMap;
  }

  /// Synchronize a single batch directly by batch ID
  Future<Map<String, dynamic>> syncSingle(String batchId) async {
    // Sync any pending models/categories and shops first so product/shop IDs are resolved
    await syncPendingModelsAndCategories();
    await syncPendingShops();

    final list = await getQueue();
    final item = list.firstWhere((b) => b.id == batchId, orElse: () => throw Exception('Batch not found in queue'));
    final api = ApiService();

    if (item.type == QueueType.inward) {
      if (item.payload.containsKey('items') && item.payload['items'] != null) {
        await api.submitInwardMultiBatch(
          items: List<Map<String, dynamic>>.from(
            (item.payload['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
          ),
          invoiceReference: item.payload['invoice_reference'],
          remarks: item.payload['remarks'],
        );
      } else {
        await api.submitInwardBatch(
          productId: item.payload['product_id'],
          serialNumbers: List<String>.from(item.payload['serial_numbers']),
          unitTypes: item.payload['unit_types'] != null
              ? Map<String, String>.from(item.payload['unit_types'])
              : null,
          inwardType: item.payload['inward_type'] ?? 'stock_in',
          remarks: item.payload['remarks'],
        );
      }
    } else {
      if (item.payload.containsKey('items') && item.payload['items'] != null) {
        await api.submitOutwardMultiBatch(
          shopId: item.payload['shop_id'],
          items: List<Map<String, dynamic>>.from(
            (item.payload['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
          ),
          billNumber: item.payload['bill_number'],
          deliveryReference: item.payload['delivery_reference'],
          remarks: item.payload['remarks'],
        );
      } else {
        await api.submitOutwardBatch(
          shopId: item.payload['shop_id'],
          productId: item.payload['product_id'],
          serialNumbers: List<String>.from(item.payload['serial_numbers']),
          unitTypes: item.payload['unit_types'] != null
              ? Map<String, String>.from(item.payload['unit_types'])
              : null,
          billNumber: item.payload['bill_number'],
          deliveryReference: item.payload['delivery_reference'],
          remarks: item.payload['remarks'],
        );
      }
    }
    await remove(item.id);
    return {'success': true};
  }

  Future<Map<String, dynamic>> syncAll() async {
    // 1. First sync any pending offline-created categories, models, and shops
    try {
      await syncPendingModelsAndCategories();
      await syncPendingShops();
    } catch (e) {
      debugPrint('[OfflineQueueService] syncPendingModelsAndCategories / syncPendingShops error: $e');
    }

    final list = await getQueue();
    if (list.isEmpty) {
      return {'total': 0, 'synced': 0, 'failed': 0, 'errors': []};
    }

    int synced = 0;
    int failed = 0;
    final List<String> errors = [];
    final api = ApiService();

    for (final item in list) {
      try {
        if (item.type == QueueType.inward) {
          if (item.payload.containsKey('items') && item.payload['items'] != null) {
            await api.submitInwardMultiBatch(
              items: List<Map<String, dynamic>>.from(
                (item.payload['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
              ),
              invoiceReference: item.payload['invoice_reference'],
              remarks: item.payload['remarks'],
            );
          } else {
            await api.submitInwardBatch(
              productId: item.payload['product_id'],
              serialNumbers: List<String>.from(item.payload['serial_numbers']),
              unitTypes: item.payload['unit_types'] != null
                  ? Map<String, String>.from(item.payload['unit_types'])
                  : null,
              inwardType: item.payload['inward_type'] ?? 'stock_in',
              remarks: item.payload['remarks'],
            );
          }
        } else {
          if (item.payload.containsKey('items') && item.payload['items'] != null) {
            await api.submitOutwardMultiBatch(
              shopId: item.payload['shop_id'],
              items: List<Map<String, dynamic>>.from(
                (item.payload['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
              ),
              billNumber: item.payload['bill_number'],
              deliveryReference: item.payload['delivery_reference'],
              remarks: item.payload['remarks'],
            );
          } else {
            await api.submitOutwardBatch(
              shopId: item.payload['shop_id'],
              productId: item.payload['product_id'],
              serialNumbers: List<String>.from(item.payload['serial_numbers']),
              unitTypes: item.payload['unit_types'] != null
                  ? Map<String, String>.from(item.payload['unit_types'])
                  : null,
              billNumber: item.payload['bill_number'],
              deliveryReference: item.payload['delivery_reference'],
              remarks: item.payload['remarks'],
            );
          }
        }
        await remove(item.id);
        synced++;
      } catch (e) {
        failed++;
        errors.add('${item.description}: ${e.toString()}');
      }
    }

    // Refresh local cache snapshot silently after sync completes
    try {
      OfflineManager().syncFromBackend(silent: true);
    } catch (_) {}

    return {
      'total': list.length,
      'synced': synced,
      'failed': failed,
      'errors': errors,
    };
  }
}
