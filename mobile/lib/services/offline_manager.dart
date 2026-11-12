import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' hide Category;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'api_service.dart';
import 'offline_queue_service.dart';
import 'websocket_service.dart';

List<dynamic> _bgDecodeList(String raw) => jsonDecode(raw) as List<dynamic>;
Map<String, dynamic> _bgDecodeMap(String raw) => jsonDecode(raw) as Map<String, dynamic>;
String _bgEncodeJson(Object? value) => jsonEncode(value);

class OfflineManager {
  static final OfflineManager _instance = OfflineManager._internal();
  factory OfflineManager() => _instance;
  OfflineManager._internal();

  final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isSyncingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> pendingDispatchCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<String?> syncStatusNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<bool> showOfflineWarningNotifier = ValueNotifier<bool>(false);

  // In-memory fast cache
  final Map<String, Map<String, dynamic>> _serials = {};
  List<Product> _products = [];
  List<Category> _categories = [];
  List<Shop> _shops = [];
  List<Map<String, dynamic>> _queuedDispatches = [];

  // O(1) ID lookup indexes (lowercase ID -> entity)
  final Map<String, Product> _productById = {};
  final Map<String, Category> _categoryById = {};
  final Map<String, Shop> _shopById = {};

  SharedPreferences? _prefs;
  StreamSubscription? _wsSubscription;
  VoidCallback? _wsConnectedListener;
  Timer? _healthCheckTimer;
  Timer? _offlineWarningTimer;
  Timer? _diskSaveTimer;
  Timer? _wsSyncDebounceTimer;
  bool _serialsDirty = false;
  bool _queueDirty = false;
  bool _isWritingDisk = false;
  DateTime? _disconnectedSince;
  int _consecutiveFailures = 0;
  bool _isInitialized = false;
  bool _isSyncing = false;

  Future<SharedPreferences> _getPrefs() async => _prefs ??= await SharedPreferences.getInstance();

  void _rebuildProductIndex() {
    _productById.clear();
    for (final p in _products) {
      _productById[p.id.toLowerCase()] = p;
    }
  }

  void _rebuildCategoryIndex() {
    _categoryById.clear();
    for (final c in _categories) {
      _categoryById[c.id.toLowerCase()] = c;
    }
  }

  void _rebuildShopIndex() {
    _shopById.clear();
    for (final s in _shops) {
      _shopById[s.id.toLowerCase()] = s;
    }
  }

  Map<String, Map<String, dynamic>> get serials => _serials;
  List<Product> get products => _products;
  List<Category> get categories => _categories;
  List<Shop> get shops => _shops;
  int get pendingDispatchCount => _queuedDispatches.length;
  Product? getProductById(String id) => _productById[id.toLowerCase()];
  Category? getCategoryById(String id) => _categoryById[id.toLowerCase()];
  Shop? getShopById(String id) => _shopById[id.toLowerCase()];

  bool get isOnline => isOnlineNotifier.value;

  void markOffline() {
    // Never mark offline if WebSocket is actively connected and alive
    if (WebSocketService().isConnected) return;
    _consecutiveFailures++;
    if (_consecutiveFailures >= 3) {
      _setOnlineStatus(false);
    }
  }

  void markOnline() {
    _consecutiveFailures = 0;
    final bool wasOffline = !isOnlineNotifier.value;
    _setOnlineStatus(true);
    if (wasOffline || _queuedDispatches.isNotEmpty) {
      unawaited(syncPendingDispatches());
    }
  }

  void setOffline(bool offline) {
    _setOnlineStatus(!offline);
  }

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    await _loadFromDisk();
    _startHealthChecks();
    _listenToWebSocket();

    // Check server health immediately so offline status is accurate right at startup
    await checkServerHealth(timeoutSeconds: 3);

    if (isOnlineNotifier.value) {
      unawaited(syncFromBackend(silent: true));
      if (_queuedDispatches.isNotEmpty) {
        unawaited(syncPendingDispatches());
      }
    }
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await _getPrefs();
      final api = ApiService();

      // 1. Products (reuse ApiService decoded catalog if already loaded to avoid duplicate JSON decode)
      if (api.cachedProducts != null && api.cachedProducts!.isNotEmpty) {
        _products = List<Product>.from(api.cachedProducts!);
      } else {
        final pJson = prefs.getString('cache_products_json');
        if (pJson != null && pJson.isNotEmpty) {
          try {
            final List list = pJson.length > 25000 ? await compute(_bgDecodeList, pJson) : jsonDecode(pJson);
            _products = list.map((p) => Product.fromJson(p)).toList();
          } catch (_) {}
        }
      }
      _rebuildProductIndex();

      // 2. Categories
      if (api.cachedCategories != null && api.cachedCategories!.isNotEmpty) {
        _categories = List<Category>.from(api.cachedCategories!);
      } else {
        final cJson = prefs.getString('cache_categories_json');
        if (cJson != null && cJson.isNotEmpty) {
          try {
            final List list = cJson.length > 25000 ? await compute(_bgDecodeList, cJson) : jsonDecode(cJson);
            _categories = list.map((c) => Category.fromJson(c)).toList();
          } catch (_) {}
        }
      }
      _rebuildCategoryIndex();

      // 3. Shops
      if (api.cachedShops != null && api.cachedShops!.isNotEmpty) {
        _shops = List<Shop>.from(api.cachedShops!);
      } else {
        final sJson = prefs.getString('cache_shops_json');
        if (sJson != null && sJson.isNotEmpty) {
          try {
            final List list = sJson.length > 25000 ? await compute(_bgDecodeList, sJson) : jsonDecode(sJson);
            _shops = list.map((s) => Shop.fromJson(s)).toList();
          } catch (_) {}
        }
      }
      _rebuildShopIndex();

      // 4. Serials snapshot
      final snJson = prefs.getString('cache_serials_snapshot_json');
      if (snJson != null && snJson.isNotEmpty) {
        try {
          final Map<String, dynamic> map =
              snJson.length > 25000 ? await compute(_bgDecodeMap, snJson) : jsonDecode(snJson);
          _serials.clear();
          map.forEach((k, v) {
            if (v is Map) {
              _serials[k.toUpperCase()] = Map<String, dynamic>.from(v);
            }
          });
        } catch (_) {}
      }

      // 5. Queued dispatches
      final qJson = prefs.getString('offline_dispatch_queue_json');
      if (qJson != null && qJson.isNotEmpty) {
        try {
          final List list = qJson.length > 25000 ? await compute(_bgDecodeList, qJson) : jsonDecode(qJson);
          _queuedDispatches = list.map((e) => Map<String, dynamic>.from(e)).toList();
          pendingDispatchCountNotifier.value = _queuedDispatches.length;
        } catch (_) {}
      }

      debugPrint('[OfflineManager] Loaded ${_serials.length} cached serials, ${_products.length} products, ${_categories.length} categories, ${_shops.length} shops');
    } catch (e) {
      debugPrint('[OfflineManager] Error loading offline cache: $e');
    }
  }

  void _scheduleSaveToDisk({bool serials = false, bool queue = false}) {
    if (serials) _serialsDirty = true;
    if (queue) _queueDirty = true;
    _diskSaveTimer?.cancel();
    _diskSaveTimer = Timer(const Duration(milliseconds: 450), () {
      unawaited(_flushDiskSave());
    });
  }

  Future<void> _flushDiskSave({bool serials = false, bool queue = false}) async {
    if (serials) _serialsDirty = true;
    if (queue) _queueDirty = true;
    _diskSaveTimer?.cancel();
    _diskSaveTimer = null;

    if (_isWritingDisk || (!_serialsDirty && !_queueDirty)) return;
    _isWritingDisk = true;
    try {
      final prefs = await _getPrefs();
      while (_serialsDirty || _queueDirty) {
        final writeSerials = _serialsDirty;
        final writeQueue = _queueDirty;
        _serialsDirty = false;
        _queueDirty = false;

        if (writeSerials) {
          final encodedSerials = _serials.length > 150
              ? await compute(_bgEncodeJson, Map<String, dynamic>.from(_serials))
              : jsonEncode(_serials);
          await prefs.setString('cache_serials_snapshot_json', encodedSerials);
        }
        if (writeQueue) {
          final encodedQueue = jsonEncode(_queuedDispatches);
          await prefs.setString('offline_dispatch_queue_json', encodedQueue);
        }
      }
    } catch (_) {
    } finally {
      _isWritingDisk = false;
    }
  }

  void _startHealthChecks() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      await checkServerHealth(timeoutSeconds: 6);
    });
  }

  Future<bool> checkServerHealth({int timeoutSeconds = 6}) async {
    // If WebSocket is actively connected, the server is definitively reachable
    if (WebSocketService().isConnected) {
      _consecutiveFailures = 0;
      _setOnlineStatus(true);
      return true;
    }

    final api = ApiService();
    try {
      final baseUri = Uri.parse(api.baseUrl);
      final healthUri = baseUri.replace(path: '/health', queryParameters: null);

      final res = await http.get(healthUri).timeout(Duration(seconds: timeoutSeconds));
      final bool online = (res.statusCode == 200);
      if (online) {
        _consecutiveFailures = 0;
        _setOnlineStatus(true);
      } else {
        _consecutiveFailures++;
        if (_consecutiveFailures >= 3) {
          _setOnlineStatus(false);
        }
      }
      return online;
    } catch (_) {
      // Re-verify if WebSocket connected in the meantime
      if (WebSocketService().isConnected) {
        _consecutiveFailures = 0;
        _setOnlineStatus(true);
        return true;
      }
      _consecutiveFailures++;
      if (_consecutiveFailures >= 3) {
        _setOnlineStatus(false);
      }
      return false;
    }
  }

  void _setOnlineStatus(bool online) {
    if (online) {
      _consecutiveFailures = 0;
      _disconnectedSince = null;
      _offlineWarningTimer?.cancel();
      _offlineWarningTimer = null;
      showOfflineWarningNotifier.value = false;

      if (!isOnlineNotifier.value) {
        isOnlineNotifier.value = true;
        syncStatusNotifier.value = 'Connected';
        // Auto-sync snapshot and queued dispatches silently on reconnect
        unawaited(syncFromBackend(silent: true));
        unawaited(syncPendingDispatches());
      } else {
        // Automatically sync whenever pending queue items exist
        unawaited(OfflineQueueService().totalPendingCount().then((count) {
          if (count > 0 || _queuedDispatches.isNotEmpty) {
            unawaited(syncPendingDispatches());
          }
        }));
      }
    } else {
      if (isOnlineNotifier.value) {
        isOnlineNotifier.value = false;
        syncStatusNotifier.value = 'Server not reachable • Offline mode';
      }
      _disconnectedSince ??= DateTime.now();
      _offlineWarningTimer ??= Timer(const Duration(minutes: 1), () {
        if (!isOnlineNotifier.value) {
          showOfflineWarningNotifier.value = true;
        }
      });
    }
  }

  void updateShop(Shop shop) {
    final idx = _shops.indexWhere((s) => s.id == shop.id);
    if (!shop.isActive) {
      if (idx != -1) _shops.removeAt(idx);
    } else {
      if (idx != -1) {
        _shops[idx] = shop;
      } else {
        _shops.add(shop);
      }
      _shops.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    _rebuildShopIndex();
    ApiService().updateCachedShop(shop, persistToDisk: false);
    _getPrefs().then((prefs) async {
      final encoded = _shops.length > 80
          ? await compute(_bgEncodeJson, _shops.map((s) => s.toJson()).toList())
          : jsonEncode(_shops.map((s) => s.toJson()).toList());
      await prefs.setString('cache_shops_json', encoded);
    }).catchError((_) {});
  }

  void removeShop(String id) {
    _shops.removeWhere((s) => s.id == id);
    _rebuildShopIndex();
    ApiService().removeCachedShop(id, persistToDisk: false);
    _getPrefs().then((prefs) {
      prefs.setString('cache_shops_json', jsonEncode(_shops.map((s) => s.toJson()).toList()));
    }).catchError((_) {});
  }

  void updateProduct(Product product) {
    final idx = _products.indexWhere((p) => p.id == product.id);
    if (idx != -1) {
      _products[idx] = product;
    } else {
      _products.insert(0, product);
    }
    _rebuildProductIndex();
    ApiService().updateCachedProduct(product, persistToDisk: false);
    _getPrefs().then((prefs) async {
      final encoded = _products.length > 80
          ? await compute(_bgEncodeJson, _products.map((p) => p.toJson()).toList())
          : jsonEncode(_products.map((p) => p.toJson()).toList());
      await prefs.setString('cache_products_json', encoded);
    }).catchError((_) {});
  }

  void removeProduct(String id) {
    _products.removeWhere((p) => p.id == id);
    _rebuildProductIndex();
    if (ApiService().cachedProducts != null) {
      ApiService().cachedProducts!.removeWhere((p) => p.id == id);
    }
    _getPrefs().then((prefs) {
      prefs.setString('cache_products_json', jsonEncode(_products.map((p) => p.toJson()).toList()));
    }).catchError((_) {});
  }

  void setCategories(List<Category> cats, {bool persistToDisk = true}) {
    final offlineCats = _categories.where((c) => c.id.startsWith('offline_')).toList();
    _categories = List<Category>.from(cats);
    if (offlineCats.isNotEmpty) {
      final ids = _categories.map((c) => c.id).toSet();
      for (final oc in offlineCats) {
        if (!ids.contains(oc.id)) {
          _categories.add(oc);
        }
      }
    }
    _rebuildCategoryIndex();
    if (persistToDisk) {
      _getPrefs().then((prefs) {
        prefs.setString('cache_categories_json', jsonEncode(_categories.map((c) => c.toJson()).toList()));
      }).catchError((_) {});
    }
  }

  void updateCategory(Category category) {
    final idx = _categories.indexWhere((c) => c.id == category.id);
    if (!category.isActive) {
      if (idx != -1) _categories.removeAt(idx);
    } else {
      if (idx != -1) {
        _categories[idx] = category;
      } else {
        _categories.add(category);
      }
      _categories.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    _rebuildCategoryIndex();
    ApiService().updateCachedCategory(category);
    _getPrefs().then((prefs) {
      prefs.setString('cache_categories_json', jsonEncode(_categories.map((c) => c.toJson()).toList()));
    }).catchError((_) {});
  }

  void removeCategory(String id) {
    _categories.removeWhere((c) => c.id == id);
    _rebuildCategoryIndex();
    ApiService().removeCachedCategory(id);
    _getPrefs().then((prefs) {
      prefs.setString('cache_categories_json', jsonEncode(_categories.map((c) => c.toJson()).toList()));
    }).catchError((_) {});
  }

  /// Records an inward-scanned serial directly into local offline inventory cache
  void recordScannedInwardSerial({
    required String serialNumber,
    required String productId,
    required String modelName,
    String? unitType,
    String inwardType = 'stock_in',
  }) {
    final cleanSerial = serialNumber.trim().toUpperCase();
    final entry = _serials[cleanSerial] ?? <String, dynamic>{};
    entry['p'] = productId;
    entry['m'] = modelName;
    if (unitType != null) entry['u'] = unitType;
    if (inwardType == 'damaged') {
      entry['st'] = 'damaged';
      entry['d'] = false;
      entry['dmg'] = true;
    } else {
      entry['st'] = 'available';
      entry['d'] = false;
      entry['dmg'] = false;
    }
    _serials[cleanSerial] = entry;
    _scheduleSaveToDisk(serials: true);
  }

  /// Atomically updates a temporary offline product ID to its genuine server ID across cache and serials
  void remapProductId(String oldTempId, String newRealId, {Product? updatedProduct}) {
    final idx = _products.indexWhere((p) => p.id == oldTempId);
    if (idx != -1) {
      if (updatedProduct != null) {
        _products[idx] = updatedProduct;
      } else {
        _products[idx] = _products[idx].copyWith(id: newRealId);
      }
    } else if (updatedProduct != null) {
      _products.insert(0, updatedProduct);
    }
    _rebuildProductIndex();
    ApiService().invalidateProductCache();

    bool changedSerials = false;
    _serials.forEach((sn, data) {
      if (data['p'] == oldTempId) {
        data['p'] = newRealId;
        if (updatedProduct != null) {
          data['m'] = '${updatedProduct.brand} ${updatedProduct.model}'.trim();
        }
        changedSerials = true;
      }
    });

    _getPrefs().then((prefs) {
      prefs.setString('cache_products_json', jsonEncode(_products.map((p) => p.toJson()).toList()));
      if (changedSerials) {
        _scheduleSaveToDisk(serials: true);
      }
    }).catchError((_) {});
  }

  /// Remaps temporary product IDs inside queued outward dispatches
  void remapDispatchesProductIds(Map<String, String> productMap) {
    bool modified = false;
    for (final d in _queuedDispatches) {
      if (d['product_id'] != null && productMap.containsKey(d['product_id'])) {
        d['product_id'] = productMap[d['product_id']];
        modified = true;
      }
      if (d['items'] is List) {
        for (final item in (d['items'] as List)) {
          if (item is Map && item['product_id'] != null && productMap.containsKey(item['product_id'])) {
            item['product_id'] = productMap[item['product_id']];
            modified = true;
          }
        }
      }
    }
    if (modified) {
      _scheduleSaveToDisk(queue: true);
    }
  }

  /// Atomically updates a temporary offline shop ID to its genuine server ID across cache and dispatches
  void remapShopId(String oldTempId, String newRealId, {Shop? updatedShop}) {
    final idx = _shops.indexWhere((s) => s.id == oldTempId);
    if (idx != -1) {
      if (updatedShop != null) {
        _shops[idx] = updatedShop;
      } else {
        _shops[idx] = _shops[idx].copyWith(id: newRealId);
      }
    } else if (updatedShop != null) {
      _shops.insert(0, updatedShop);
    }
    _shops.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _rebuildShopIndex();
    ApiService().invalidateShopCache();

    _getPrefs().then((prefs) {
      prefs.setString('cache_shops_json', jsonEncode(_shops.map((s) => s.toJson()).toList()));
    }).catchError((_) {});
  }

  /// Remaps temporary shop IDs inside queued outward dispatches
  void remapDispatchesShopIds(Map<String, String> shopMap) {
    bool modified = false;
    for (final d in _queuedDispatches) {
      if (d['shop_id'] != null && shopMap.containsKey(d['shop_id'])) {
        d['shop_id'] = shopMap[d['shop_id']];
        modified = true;
      }
    }
    if (modified) {
      _scheduleSaveToDisk(queue: true);
    }
  }

  // --- WEBSOCKET EVENT LISTENER ---
  void _listenToWebSocket() {
    _wsSubscription?.cancel();
    _wsSubscription = WebSocketService().stream.listen(
      (event) {
        markOnline();
        _handleWebSocketMessage(event);
      },
      onError: (_) {},
    );

    if (_wsConnectedListener != null) {
      WebSocketService().isConnectedNotifier.removeListener(_wsConnectedListener!);
    }
    _wsConnectedListener = () {
      if (WebSocketService().isConnected) {
        markOnline();
      }
    };
    // Auto-mark online whenever the WebSocket connects
    WebSocketService().isConnectedNotifier.addListener(_wsConnectedListener!);
  }

  void _scheduleWsSync() {
    _wsSyncDebounceTimer?.cancel();
    _wsSyncDebounceTimer = Timer(const Duration(milliseconds: 1500), () {
      unawaited(syncFromBackend(silent: true));
    });
  }

  void _handleWebSocketMessage(Map<String, dynamic> json) {
    try {
      final event = json['event']?.toString() ?? json['type']?.toString() ?? '';
      final data = json['data'];

      if (event == 'shop_created' || event == 'shop_updated') {
        if (data is Map<String, dynamic>) {
          try {
            final s = Shop.fromJson(data);
            updateShop(s);
          } catch (_) {}
        }
        _scheduleWsSync();
      } else if (event == 'shop_deleted') {
        final id = data?['id']?.toString();
        if (id != null) {
          removeShop(id);
        }
        _scheduleWsSync();
      } else if (event == 'product_created' || event == 'product_updated') {
        if (data is Map<String, dynamic>) {
          try {
            final p = Product.fromJson(data);
            updateProduct(p);
          } catch (_) {}
        }
        _scheduleWsSync();
      } else if (event == 'product_deleted') {
        final id = data?['id']?.toString();
        if (id != null) {
          removeProduct(id);
        }
        _scheduleWsSync();
      } else if (event == 'stock_updated') {
        if (data is Map<String, dynamic>) {
          final pid = data['product_id']?.toString();
          final rawQty = data['current_stock_qty'];
          final qty = rawQty is int ? rawQty : int.tryParse(rawQty?.toString() ?? '');
          if (pid != null && qty != null) {
            ApiService().updateProductStock(pid, qty);
          }
        }
        ApiService().clearSerialCaches();
        _scheduleWsSync();
      } else if (event == 'serial_updated') {
        if (data is Map<String, dynamic>) {
          final sn = data['serial']?.toString().toUpperCase();
          final status = data['status']?.toString();
          if (sn != null && status != null) {
            final entry = _serials[sn] ?? <String, dynamic>{};
            entry['st'] = status;
            entry['d'] = (status == 'dispatched');
            entry['dmg'] = (status == 'damaged');
            _serials[sn] = entry;
            _scheduleSaveToDisk(serials: true);
          }
        }
        ApiService().clearSerialCaches();
        _scheduleWsSync();
      } else if (event == 'serial_deleted') {
        final sn = data?['serial']?.toString().toUpperCase();
        if (sn != null) {
          _serials.remove(sn);
          _scheduleSaveToDisk(serials: true);
        }
        ApiService().clearSerialCaches();
        _scheduleWsSync();
      }
    } catch (_) {}
  }

  // --- FULL SNAPSHOT SYNC FROM BACKEND ---
  Future<void> syncFromBackend({bool silent = true}) async {
    if (_isSyncing) return;
    final api = ApiService();
    if (!api.isAuthenticated) return;

    _isSyncing = true;
    if (!silent) isSyncingNotifier.value = true;

    try {
      final prefs = await _getPrefs();
      final token = prefs.getString('access_token');
      final uri = Uri.parse('${api.baseUrl}/sync/snapshot');

      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (api.deviceUid != null) 'X-Device-Uid': api.deviceUid!,
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final Map<String, dynamic> data =
            res.body.length > 25000 ? await compute(_bgDecodeMap, res.body) : jsonDecode(res.body);

        // Update Products
        if (data['products'] is List) {
          final List pList = data['products'];
          final offlineProds = _products.where((p) => p.id.startsWith('offline_')).toList();
          _products = pList.map((p) => Product.fromJson(p)).toList();
          if (offlineProds.isNotEmpty) {
            final ids = _products.map((p) => p.id).toSet();
            for (final op in offlineProds) {
              if (!ids.contains(op.id)) {
                _products.add(op);
              }
            }
          }
          _rebuildProductIndex();
          final pMaps = _products.map((p) => p.toJson()).toList();
          final encodedProds = pMaps.length > 80 ? await compute(_bgEncodeJson, pMaps) : jsonEncode(pMaps);
          await prefs.setString('cache_products_json', encodedProds);
          api.invalidateProductCache();
        }

        // Update Categories
        if (data['categories'] is List) {
          final List cList = data['categories'];
          final offlineCats = _categories.where((c) => c.id.startsWith('offline_')).toList();
          _categories = cList.map((c) => Category.fromJson(c)).toList();
          if (offlineCats.isNotEmpty) {
            final ids = _categories.map((c) => c.id).toSet();
            for (final oc in offlineCats) {
              if (!ids.contains(oc.id)) {
                _categories.add(oc);
              }
            }
          }
          _rebuildCategoryIndex();
          await prefs.setString('cache_categories_json', jsonEncode(_categories.map((c) => c.toJson()).toList()));
        }

        // Update Shops
        if (data['shops'] is List) {
          final List sList = data['shops'];
          final offlineShops = _shops.where((s) => s.id.startsWith('offline_')).toList();
          _shops = sList.map((s) => Shop.fromJson(s)).toList();
          if (offlineShops.isNotEmpty) {
            final ids = _shops.map((s) => s.id).toSet();
            for (final os in offlineShops) {
              if (!ids.contains(os.id)) {
                _shops.add(os);
              }
            }
          }
          _rebuildShopIndex();
          final sMaps = _shops.map((s) => s.toJson()).toList();
          final encodedShops = sMaps.length > 80 ? await compute(_bgEncodeJson, sMaps) : jsonEncode(sMaps);
          await prefs.setString('cache_shops_json', encodedShops);
          api.invalidateShopCache();
        }

        // Update Serials
        if (data['serials'] is Map) {
          final Map<String, dynamic> sMap = data['serials'];
          _serials.clear();
          sMap.forEach((k, v) {
            if (v is Map) {
              _serials[k.toUpperCase()] = Map<String, dynamic>.from(v);
            }
          });
          await _flushDiskSave(serials: true);
        }

        _setOnlineStatus(true);
        syncStatusNotifier.value = 'Data up to date';
        debugPrint('[OfflineManager] Snapshot successfully synced! Products: ${_products.length}, Categories: ${_categories.length}, Shops: ${_shops.length}, Serials: ${_serials.length}');
      } else {
        debugPrint('[OfflineManager] Snapshot returned HTTP ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('[OfflineManager] Sync snapshot failed: $e');
    } finally {
      _isSyncing = false;
      if (!silent) isSyncingNotifier.value = false;
    }
  }

  // --- OFFLINE SCAN CHECK ---
  Map<String, dynamic> checkOutwardSerialOffline(String? productId, String serialNumber) {
    final cleanSerial = serialNumber.trim().toUpperCase();
    final entry = _serials[cleanSerial];

    if (entry != null) {
      final bool isDispatched = entry['d'] == true || entry['st'] == 'dispatched';
      final bool isDamaged = entry['dmg'] == true || entry['st'] == 'damaged';
      final String? regProdId = entry['p'];
      final String regModelName = entry['m'] ?? 'Registered Unit';
      final String? unitType = entry['u'];

      if (isDispatched) {
        return {
          'serial_number': cleanSerial,
          'case': 0,
          'case_name': 'blocked',
          'badge': 'blocked',
          'badge_label': 'Already Dispatched',
          'message': 'Serial "$cleanSerial" has ALREADY been dispatched. (Offline verified)',
          'is_blocked': true,
          'is_dispatched': true,
          'can_dispatch': false,
          'is_matched': true,
          'is_damaged': isDamaged,
          'is_offline': true,
        };
      }

      if (productId != null && productId.isNotEmpty && regProdId != null && regProdId.toLowerCase() != productId.toLowerCase()) {
        return {
          'serial_number': cleanSerial,
          'case': 4,
          'case_name': 'model_mismatch',
          'badge': 'warning',
          'badge_label': isDamaged ? 'Damaged & Model Warning' : 'Model Warning',
          'message': isDamaged
              ? 'This item is damaged and registered under "$regModelName", not the selected model. Are you sure you want to add?'
              : 'Serial is registered under "$regModelName", not the selected model. (Offline verified)',
          'requires_confirmation': true,
          'is_blocked': false,
          'is_dispatched': false,
          'can_dispatch': true,
          'is_matched': false,
          'is_damaged': isDamaged,
          'registered_model_name': regModelName,
          'registered_product_id': regProdId,
          'current_status': entry['st'],
          'unit_type': unitType,
          'is_offline': true,
        };
      }

      if (isDamaged) {
        return {
          'serial_number': cleanSerial,
          'case': 3,
          'case_name': 'status_warning',
          'badge': 'warning',
          'badge_label': 'Damaged',
          'message': 'This item is damaged. Are you sure you want to add? (Offline verified)',
          'requires_confirmation': true,
          'is_blocked': false,
          'is_dispatched': false,
          'can_dispatch': true,
          'is_matched': true,
          'is_damaged': true,
          'registered_model_name': regModelName,
          'registered_product_id': regProdId,
          'current_status': 'damaged',
          'unit_type': unitType,
          'is_offline': true,
        };
      }

      // Available matched unit
      return {
        'serial_number': cleanSerial,
        'case': 1,
        'case_name': 'matched',
        'badge': 'matched',
        'badge_label': 'Matched',
        'message': 'Available and matched to model. (Offline verified)',
        'requires_confirmation': false,
        'is_blocked': false,
        'is_dispatched': false,
        'can_dispatch': true,
        'is_matched': true,
        'is_damaged': false,
        'registered_model_name': regModelName,
        'registered_product_id': regProdId,
        'current_status': 'available',
        'unit_type': unitType,
        'is_offline': true,
      };
    }

    // Not found in cache -> Case 2 Unmatched pre-go-live stock
    return {
      'serial_number': cleanSerial,
      'case': 2,
      'case_name': 'unmatched',
      'badge': 'unmatched',
      'badge_label': 'Not in system, will be recorded',
      'message': 'Not in system (pre-go-live stock). Will be recorded offline.',
      'requires_confirmation': false,
      'is_blocked': false,
      'is_dispatched': false,
      'can_dispatch': true,
      'is_matched': false,
      'is_damaged': false,
      'is_offline': true,
    };
  }

  // --- OFFLINE INWARD VALIDATION ---
  Map<String, dynamic> validateInwardSerialOffline(
    String? productId,
    String serialNumber, {
    String inwardType = 'stock_in',
  }) {
    final cleanSerial = serialNumber.trim().toUpperCase();
    final entry = _serials[cleanSerial];

    if (inwardType == 'stock_in') {
      if (entry != null && entry['st'] == 'available') {
        return {
          'is_valid': false,
          'message': 'Serial "$cleanSerial" is already in stock (${entry['m'] ?? ""}).',
          'is_duplicate': true,
        };
      }
      return {
        'is_valid': true,
        'message': 'Valid for stock in (Offline verified)',
        'requires_confirmation': false,
      };
    }

    // return or damaged
    if (entry != null) {
      final bool isDispatched = entry['st'] == 'dispatched' || entry['d'] == true;
      return {
        'is_valid': true,
        'requires_confirmation': !isDispatched,
        'message': isDispatched
            ? 'Matched to previously dispatched unit (${entry['m']}).'
            : 'Serial is currently marked as ${entry['st']} in local inventory.',
        'registered_model_id': entry['p'],
        'registered_model_name': entry['m'],
        'unit_type': entry['u'],
      };
    }

    // Not in local cache -> prompt for model
    return {
      'is_valid': true,
      'requires_confirmation': true,
      'message': 'Serial not found in local inventory. Please assign model.',
    };
  }

  /// Syncs live server outward check response into local offline serials map
  void updateSerialFromCheckOutward(String serialNumber, Map<String, dynamic> data) {
    final cleanSerial = serialNumber.trim().toUpperCase();
    final isDispatched = data['is_already_dispatched'] == true || data['is_dispatched'] == true;
    final isDamaged = data['is_damaged'] == true;
    final status = isDispatched ? 'dispatched' : (isDamaged ? 'damaged' : (data['current_status'] ?? 'available'));

    final entry = _serials[cleanSerial] ?? <String, dynamic>{};
    entry['st'] = status;
    entry['d'] = isDispatched;
    entry['dmg'] = isDamaged;
    if (data['registered_model_id'] != null) {
      entry['p'] = data['registered_model_id'].toString();
    }
    if (data['registered_model_name'] != null) {
      entry['m'] = data['registered_model_name'].toString();
    }
    if (data['unit_type'] != null) {
      entry['u'] = data['unit_type'].toString();
    }
    _serials[cleanSerial] = entry;
  }

  /// Syncs live server inward validation response into local offline serials map
  void updateSerialFromValidateInward(String serialNumber, Map<String, dynamic> data, {String inwardType = 'stock_in'}) {
    final cleanSerial = serialNumber.trim().toUpperCase();
    final entry = _serials[cleanSerial] ?? <String, dynamic>{};
    if (inwardType == 'stock_in' && data['is_valid'] == true) {
      entry['st'] = 'available';
      entry['d'] = false;
      entry['dmg'] = false;
    } else if (inwardType == 'damaged' && data['is_valid'] == true) {
      entry['st'] = 'damaged';
      entry['d'] = false;
      entry['dmg'] = true;
    }
    if (data['registered_model_id'] != null) {
      entry['p'] = data['registered_model_id'].toString();
    }
    if (data['registered_model_name'] != null) {
      entry['m'] = data['registered_model_name'].toString();
    }
    if (data['unit_type'] != null) {
      entry['u'] = data['unit_type'].toString();
    }
    _serials[cleanSerial] = entry;
  }

  /// Removes serial from offline cache when deleted on server
  void removeSerial(String serialNumber) {
    final cleanSerial = serialNumber.trim().toUpperCase();
    _serials.remove(cleanSerial);
    _scheduleSaveToDisk(serials: true);
  }

  // --- OFFLINE SERIAL LIFECYCLE LOOKUP ---
  SerialLookupDetail lookupSerialOffline(String serialNumber) {
    final cleanSerial = serialNumber.trim().toUpperCase();
    final entry = _serials[cleanSerial];

    // Check if it's currently queued in pending offline dispatches
    Map<String, dynamic>? pendingDispatch;
    for (var d in _queuedDispatches) {
      final items = d['items'] as List?;
      if (items != null) {
        for (var it in items) {
          final sList = it['serials'] as List?;
          if (sList != null) {
            for (var s in sList) {
              final sn = (s is Map ? s['serial_number'] : s)?.toString().toUpperCase();
              if (sn == cleanSerial) {
                pendingDispatch = d;
                break;
              }
            }
          }
        }
      }
      final sNums = d['serial_numbers'] as List?;
      if (sNums != null && sNums.any((s) => s.toString().toUpperCase() == cleanSerial)) {
        pendingDispatch = d;
      }
      if (pendingDispatch != null) break;
    }

    if (entry != null) {
      final String? prodId = entry['p'] as String?;
      final Product? prod = (prodId != null) ? getProductById(prodId) : null;
      final String rawStatus = (entry['st'] as String? ?? 'available').toLowerCase();
      final bool isDispatched = entry['d'] == true || rawStatus == 'dispatched' || pendingDispatch != null;
      final bool isDamaged = entry['dmg'] == true || rawStatus == 'damaged';
      final String? unitType = entry['u'] as String?;
      final String modelName = prod?.model ?? entry['m'] as String? ?? 'Registered Unit';
      final String productName = prod?.name ?? entry['m'] as String? ?? 'Cached Product';
      final String? brand = prod?.brand;

      String? shopName = entry['sn'] as String?;
      String? shopCity = entry['sc'] as String?;

      if (pendingDispatch != null) {
        final sId = pendingDispatch['shop_id']?.toString();
        if (sId != null) {
          final shop = getShopById(sId);
          shopName = shop?.name;
          shopCity = shop?.city;
        }
      }

      String statusLabel;
      String effStatus;
      if (pendingDispatch != null) {
        statusLabel = 'Dispatched (Offline Queue)';
        effStatus = 'dispatched';
      } else if (isDamaged) {
        statusLabel = 'Damaged (Offline Cache)';
        effStatus = 'damaged';
      } else if (isDispatched) {
        statusLabel = 'Dispatched (Offline Cache)';
        effStatus = 'dispatched';
      } else {
        statusLabel = 'Available in Godown (Offline Cache)';
        effStatus = 'available';
      }

      final List<SerialHistoryEntry> history = [];

      if (pendingDispatch != null) {
        history.add(
          SerialHistoryEntry(
            id: 'offline_queue',
            action: 'DISPATCH_QUEUED',
            fromStatus: 'available',
            toStatus: 'dispatched',
            shopName: shopName,
            shopCity: shopCity,
            userName: 'Device (Offline Queue)',
            createdAt: pendingDispatch['timestamp']?.toString() ?? DateTime.now().toIso8601String(),
            remarks: 'Dispatched offline (Bill: ${pendingDispatch['bill_number'] ?? 'N/A'}). Awaiting server sync.',
          ),
        );
      }

      history.add(
        SerialHistoryEntry(
          id: 'offline_snapshot',
          action: isDispatched ? 'OUTWARD_DISPATCH' : (isDamaged ? 'DAMAGED_STATUS' : 'INWARD_VERIFIED'),
          fromStatus: null,
          toStatus: effStatus,
          shopName: shopName,
          shopCity: shopCity,
          userName: 'Local Cache',
          createdAt: DateTime.now().toIso8601String(),
          remarks: 'Unit verified in local godown snapshot.${unitType != null ? " [Unit: $unitType]" : ""}',
        ),
      );

      return SerialLookupDetail(
        serialNumber: cleanSerial,
        isTracked: true,
        status: effStatus,
        productName: productName,
        brand: brand,
        model: modelName,
        lastShopName: shopName,
        lastShopCity: shopCity,
        statusLabel: statusLabel,
        history: history,
      );
    }

    // If not in cache but in offline pending dispatch
    if (pendingDispatch != null) {
      final sId = pendingDispatch['shop_id']?.toString();
      final shop = sId != null ? getShopById(sId) : null;
      return SerialLookupDetail(
        serialNumber: cleanSerial,
        isTracked: false,
        status: 'dispatched',
        productName: 'Recorded Stock (Pre-go-live)',
        model: 'Pre-go-live Stock',
        lastShopName: shop?.name,
        lastShopCity: shop?.city,
        statusLabel: 'Dispatched (Offline Queue)',
        history: [
          SerialHistoryEntry(
            id: 'offline_queue',
            action: 'DISPATCH_QUEUED',
            fromStatus: 'unmatched',
            toStatus: 'dispatched',
            shopName: shop?.name,
            shopCity: shop?.city,
            userName: 'Device (Offline)',
            createdAt: pendingDispatch['timestamp']?.toString() ?? DateTime.now().toIso8601String(),
            remarks: 'Dispatched as unmatched pre-go-live stock offline (Bill: ${pendingDispatch['bill_number'] ?? 'N/A'}).',
          ),
        ],
      );
    }

    // Completely unknown in local offline cache
    return SerialLookupDetail(
      serialNumber: cleanSerial,
      isTracked: false,
      status: 'unknown',
      productName: 'Not in Offline Cache',
      model: 'Unknown Model',
      statusLabel: 'Not in Offline Cache',
      history: [
        SerialHistoryEntry(
          id: 'not_found',
          action: 'OFFLINE_VERIFICATION',
          fromStatus: null,
          toStatus: 'not_found',
          userName: 'Device Scanner',
          createdAt: DateTime.now().toIso8601String(),
          remarks: 'Serial "$cleanSerial" is not present in local offline database (${_serials.length} units cached). Connect to server to query archived database logs.',
        ),
      ],
    );
  }

  // --- RECORD SERIAL IN LOCAL CACHE ---
  void recordLocalDispatch(
    String serial, {
    String? productId,
    String? modelName,
    bool deferSave = false,
  }) {
    final clean = serial.trim().toUpperCase();
    _serials[clean] = {
      'p': productId,
      'm': modelName ?? 'Dispatched Unit',
      'st': 'dispatched',
      'd': true,
      'dmg': false,
    };
    if (deferSave) {
      _serialsDirty = true;
    } else {
      _scheduleSaveToDisk(serials: true);
    }
  }

  // --- OFFLINE DISPATCH QUEUE ---
  Future<void> queueDispatch(Map<String, dynamic> dispatchPayload) async {
    _queuedDispatches.add(dispatchPayload);
    pendingDispatchCountNotifier.value = _queuedDispatches.length;

    // Also mark each serial in local memory as dispatched right away to prevent reuse
    if (dispatchPayload['items'] is List) {
      for (var item in dispatchPayload['items']) {
        if (item['serials'] is List) {
          for (var s in item['serials']) {
            final sn = (s is Map ? s['serial_number'] : s)?.toString();
            if (sn != null) {
              recordLocalDispatch(sn, productId: item['product_id']?.toString(), deferSave: true);
            }
          }
        }
      }
    }
    await _flushDiskSave(serials: true, queue: true);

    // Enqueue into OfflineQueueService so it is fully inspectable in OfflineQueueScreen
    final shopId = dispatchPayload['shop_id']?.toString() ?? '';
    final shop = getShopById(shopId);
    final shopName = dispatchPayload['shop_name'] ?? shop?.name ?? 'Shop';
    final items = dispatchPayload['items'] as List? ?? [];
    int totalUnits = 0;
    for (var it in items) {
      if (it is Map) {
        final sList = it['serials'] ?? it['serial_numbers'];
        if (sList is List) totalUnits += sList.length;
      }
    }
    final batch = QueuedBatch(
      id: dispatchPayload['client_request_id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type: QueueType.outward,
      createdAt: DateTime.now(),
      payload: Map<String, dynamic>.from(dispatchPayload),
      description: 'Outward: $shopName ($totalUnits units)',
    );
    await OfflineQueueService().enqueue(batch);

    // Immediately try to auto-sync if connection is available or probe health
    if (isOnlineNotifier.value) {
      unawaited(syncPendingDispatches());
    } else {
      unawaited(checkServerHealth(timeoutSeconds: 1));
    }
  }

  bool _isSyncingDispatches = false;

  Future<void> syncPendingDispatches() async {
    if (_isSyncingDispatches) return;
    if (!isOnlineNotifier.value) return;

    final int queuePending = await OfflineQueueService().totalPendingCount();
    final bool hadLegacyQueue = _queuedDispatches.isNotEmpty;
    if (queuePending == 0 && !hadLegacyQueue) return;

    _isSyncingDispatches = true;
    try {
      // 1. Drain all items from OfflineQueueService
      int syncedCount = 0;
      if (queuePending > 0) {
        try {
          final res = await OfflineQueueService().syncAll();
          syncedCount = (res['synced'] as int?) ?? 0;
        } catch (_) {}
      }

      // 2. Clear _queuedDispatches to prevent duplicate submission (already mirrored into OfflineQueueService)
      if (hadLegacyQueue) {
        _queuedDispatches.clear();
        pendingDispatchCountNotifier.value = 0;
        await _flushDiskSave(queue: true);
      }

      if (syncedCount > 0 || hadLegacyQueue) {
        syncStatusNotifier.value = 'All offline dispatches synced';
      }
    } finally {
      _isSyncingDispatches = false;
    }
  }
}
