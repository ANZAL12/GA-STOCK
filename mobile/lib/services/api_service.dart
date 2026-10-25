import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'offline_manager.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const String defaultBaseUrl = 'http://100.66.97.14:8000/api/v1';

  http.Client _client = http.Client();

  void _resetClient() {
    try {
      _client.close();
    } catch (_) {}
    _client = http.Client();
  }

  String _baseUrl = defaultBaseUrl;
  String? _accessToken;
  String? _refreshToken;
  User? _currentUser;
  String? _deviceUid;
  bool _isDeviceApproved = false;

  // --- TWO-TIER CACHE (RAM + PERSISTENT DISK) ---
  List<Product>? _cachedProducts;
  List<Shop>? _cachedShops;
  List<BillListItem>? _cachedBills;
  DateTime? _productsCacheTime;
  DateTime? _shopsCacheTime;
  DateTime? _billsCacheTime;

  // Recent serial check cache: key is "$productId:$serial" -> response Map
  final Map<String, Map<String, dynamic>> _outwardSerialCheckCache = {};
  final Map<String, Map<String, dynamic>> _inwardSerialValidateCache = {};

  String get baseUrl => _baseUrl;
  User? get currentUser => _currentUser;
  String? get deviceUid => _deviceUid;
  bool get isDeviceApproved => _isDeviceApproved;
  bool get isAuthenticated => _accessToken != null && _currentUser != null;

  List<Product>? get cachedProducts => _cachedProducts;
  List<Shop>? get cachedShops => _cachedShops;
  List<BillListItem>? get cachedBills => _cachedBills;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Base URL
    final savedUrl = prefs.getString('base_url');
    if (savedUrl != null && savedUrl.trim().isNotEmpty) {
      _baseUrl = savedUrl.trim();
    } else {
      _baseUrl = defaultBaseUrl;
      await prefs.setString('base_url', defaultBaseUrl);
    }

    // 2. Persistent hardware Device UID
    String? uid = prefs.getString('device_uid');
    if (uid == null || uid.isEmpty) {
      uid = const Uuid().v4();
      await prefs.setString('device_uid', uid);
    }
    _deviceUid = uid;

    // 3. Saved tokens
    _accessToken = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');
    final userJson = prefs.getString('user_profile');
    if (userJson != null) {
      try {
        _currentUser = User.fromJson(jsonDecode(userJson));
      } catch (_) {}
    }

    // 4. Load persisted catalogs from disk for 0ms cold start
    final productsJson = prefs.getString('cache_products_json');
    if (productsJson != null) {
      try {
        final List list = jsonDecode(productsJson);
        _cachedProducts = list.map((p) => Product.fromJson(p)).toList();
        _productsCacheTime = DateTime.now();
      } catch (_) {}
    }

    final shopsJson = prefs.getString('cache_shops_json');
    if (shopsJson != null) {
      try {
        final List list = jsonDecode(shopsJson);
        _cachedShops = list.map((s) => Shop.fromJson(s)).toList();
        _shopsCacheTime = DateTime.now();
      } catch (_) {}
    }

    // 5. Saved device approval status
    _isDeviceApproved = prefs.getBool('device_approved') ?? false;
  }

  Future<void> setBaseUrl(String url) async {
    String cleanUrl = url.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    if (!cleanUrl.endsWith('/api/v1')) {
      cleanUrl = '$cleanUrl/api/v1';
    }
    _baseUrl = cleanUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('base_url', _baseUrl);
  }

  Map<String, String> _headers() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_deviceUid != null) {
      headers['X-Device-Uid'] = _deviceUid!;
    }
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  // --- DEVICE REGISTRATION & APPROVAL ---
  Future<bool> checkOrRegisterDevice({String? label}) async {
    if (_deviceUid == null) await init();

    try {
      final res = await _client.post(
        Uri.parse('$_baseUrl/devices/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_uid': _deviceUid,
          'label': label ?? 'Android Godown Scanner',
        }),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        _isDeviceApproved = data['is_active'] == true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('device_approved', _isDeviceApproved);
        OfflineManager().markOnline();
        return _isDeviceApproved;
      }
      return false;
    } catch (e) {
      // If offline or network unreachable, fallback to previously approved state
      OfflineManager().markOffline();
      return _isDeviceApproved;
    }
  }

  // --- AUTHENTICATION ---
  Future<User> login(String username, String password) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl/auth/login'),
      headers: _headers(),
      body: jsonEncode({
        'username': username.trim().toLowerCase(),
        'password': password,
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      _accessToken = data['access_token'];
      _refreshToken = data['refresh_token'];
      _currentUser = User.fromJson(data['user']);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', _accessToken!);
      await prefs.setString('refresh_token', _refreshToken!);
      await prefs.setString('user_profile', jsonEncode(data['user']));

      return _currentUser!;
    } else {
      String msg = 'Login failed';
      try {
        final err = jsonDecode(res.body);
        msg = err['detail'] ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
  }

  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_profile');
  }

  // --- TOKEN REFRESH & AUTHENTICATED REQUEST HELPERS ---
  Future<bool>? _refreshFuture;

  Future<bool> _refreshTokenNow() async {
    if (_refreshFuture != null) {
      return _refreshFuture!;
    }
    _refreshFuture = _doRefreshToken();
    try {
      return await _refreshFuture!;
    } finally {
      _refreshFuture = null;
    }
  }

  Future<bool> _doRefreshToken() async {
    if (_refreshToken == null || _refreshToken!.isEmpty) return false;
    try {
      final res = await _client.post(
        Uri.parse('$_baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _accessToken = data['access_token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', _accessToken!);
        return true;
      } else if (res.statusCode == 401 || res.statusCode == 403) {
        await logout();
      }
    } catch (_) {}
    return false;
  }

  bool _isTransientNetworkError(dynamic e) {
    if (e is TimeoutException) return true;
    final msg = e.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('connection closed') ||
        msg.contains('connection reset') ||
        msg.contains('broken pipe') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('clientexception') ||
        msg.contains('software caused connection abort');
  }

  String formatNetworkError(dynamic e) {
    if (e is TimeoutException) {
      return 'Connection timed out. Server response took too long.';
    }
    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('connection refused') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable')) {
      return 'Cannot reach server. Please check your vpn connection.';
    }
    return e.toString().replaceAll('Exception: ', '');
  }

  Future<http.Response> _authenticatedGet(Uri uri, {int maxRetries = 2}) async {
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        var res = await _client.get(uri, headers: _headers()).timeout(const Duration(seconds: 10));
        if (res.statusCode == 401 && _refreshToken != null) {
          final refreshed = await _refreshTokenNow();
          if (refreshed) {
            res = await _client.get(uri, headers: _headers()).timeout(const Duration(seconds: 10));
          }
        }
        return res;
      } catch (e) {
        if (attempts <= maxRetries && _isTransientNetworkError(e)) {
          _resetClient(); // Discard dead socket pool
          await Future.delayed(Duration(milliseconds: 200 * attempts));
          continue;
        }
        throw Exception(formatNetworkError(e));
      }
    }
  }

  Future<http.Response> _authenticatedPost(Uri uri, {Object? body, int maxRetries = 1}) async {
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        var res = await _client.post(uri, headers: _headers(), body: body).timeout(const Duration(seconds: 14));
        if (res.statusCode == 401 && _refreshToken != null) {
          final refreshed = await _refreshTokenNow();
          if (refreshed) {
            res = await _client.post(uri, headers: _headers(), body: body).timeout(const Duration(seconds: 14));
          }
        }
        return res;
      } catch (e) {
        if (attempts <= maxRetries && _isTransientNetworkError(e)) {
          _resetClient(); // Discard dead socket pool
          await Future.delayed(Duration(milliseconds: 250 * attempts));
          continue;
        }
        throw Exception(formatNetworkError(e));
      }
    }
  }

  // --- PRODUCTS & SHOPS CACHED METHODS ---

  /// Pre-warms the catalog caches in background so screens open in 0ms
  void preWarmCache() {
    if (_cachedProducts == null) {
      _fetchAndCacheProducts().catchError((_) => <Product>[]);
    }
    if (_cachedShops == null) {
      _fetchAndCacheShops().catchError((_) => <Shop>[]);
    }
  }

  /// Live update of single product in cache (e.g. from WebSocket push)
  void updateCachedProduct(Product product) {
    if (_cachedProducts == null) {
      _cachedProducts = [product];
    } else {
      final idx = _cachedProducts!.indexWhere((p) => p.id == product.id);
      if (idx != -1) {
        _cachedProducts![idx] = product;
      } else {
        _cachedProducts!.insert(0, product);
      }
    }
    // Update disk cache asynchronously
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('cache_products_json', jsonEncode(_cachedProducts!.map((p) => p.toJson()).toList()));
    }).catchError((_) {});
  }

  /// Live update of a product's stock count in RAM and disk cache (e.g. from WebSocket push)
  void updateProductStock(String productId, int newQty) {
    if (_cachedProducts == null) return;
    final idx = _cachedProducts!.indexWhere((p) => p.id == productId);
    if (idx != -1) {
      _cachedProducts![idx] = _cachedProducts![idx].copyWith(currentStockQty: newQty);
      _productsCacheTime = DateTime.now();
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('cache_products_json', jsonEncode(_cachedProducts!.map((p) => p.toJson()).toList()));
      }).catchError((_) {});
    } else {
      _refreshProductsInBackground();
    }
  }

  /// Invalidate products cache so subsequent getProducts calls fetch fresh stock from server
  void invalidateProductCache() {
    _productsCacheTime = null;
  }

  /// Live update of single shop in cache (e.g. from WebSocket push)
  void updateCachedShop(Shop shop) {
    if (_cachedShops == null) {
      if (shop.isActive) {
        _cachedShops = [shop];
      }
    } else {
      _cachedShops!.removeWhere((s) => s.id == shop.id);
      if (shop.isActive) {
        _cachedShops!.add(shop);
        _cachedShops!.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
    }
    _shopsCacheTime = DateTime.now();
    if (_cachedShops != null) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('cache_shops_json', jsonEncode(_cachedShops!.map((s) => s.toJson()).toList()));
      }).catchError((_) {});
    }
  }

  /// Remove shop from cache on permanent delete
  void removeCachedShop(String shopId) {
    if (_cachedShops == null) return;
    _cachedShops!.removeWhere((s) => s.id == shopId);
    _shopsCacheTime = DateTime.now();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('cache_shops_json', jsonEncode(_cachedShops!.map((s) => s.toJson()).toList()));
    }).catchError((_) {});
  }

  /// Invalidate shops cache so subsequent getShops calls fetch fresh list from server
  void invalidateShopCache() {
    _shopsCacheTime = null;
  }

  /// Handles incoming WebSocket events to keep RAM + Disk cache permanently fresh
  void handleWebSocketEvent(Map<String, dynamic> event) {
    final type = event['event']?.toString() ?? event['type']?.toString();
    final data = event['data'];
    if (type == 'stock_updated' && data is Map<String, dynamic>) {
      final pid = data['product_id']?.toString();
      final rawQty = data['current_stock_qty'];
      final qty = rawQty is int ? rawQty : int.tryParse(rawQty?.toString() ?? '');
      if (pid != null && qty != null) {
        updateProductStock(pid, qty);
      } else {
        _refreshProductsInBackground();
      }
    } else if ((type == 'product_updated' || type == 'product_created') && data is Map<String, dynamic>) {
      try {
        final p = Product.fromJson(data);
        updateCachedProduct(p);
      } catch (_) {}
    } else if (type == 'product_deleted' && data is Map<String, dynamic>) {
      final id = data['id']?.toString();
      if (id != null && _cachedProducts != null) {
        _cachedProducts!.removeWhere((p) => p.id == id);
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString('cache_products_json', jsonEncode(_cachedProducts!.map((p) => p.toJson()).toList()));
        }).catchError((_) {});
      }
    } else if ((type == 'shop_created' || type == 'shop_updated') && data is Map<String, dynamic>) {
      try {
        final s = Shop.fromJson(data);
        updateCachedShop(s);
      } catch (_) {}
    } else if (type == 'shop_deleted' && data is Map<String, dynamic>) {
      final id = data['id']?.toString();
      if (id != null) {
        removeCachedShop(id);
      }
    }
  }

  /// Stale-while-revalidate for products: returns instant cached if available
  Future<List<Product>> getProducts({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedProducts != null && _cachedProducts!.isNotEmpty) {
      // If cache time was invalidated (null), force re-fetch
      if (_productsCacheTime == null) {
        return await _fetchAndCacheProducts();
      }
      final age = DateTime.now().difference(_productsCacheTime!);
      if (age < const Duration(minutes: 5)) {
        return _cachedProducts!;
      }
      // Stale cache: trigger background refresh silently, return cached immediately
      _refreshProductsInBackground();
      return _cachedProducts!;
    }
    return await _fetchAndCacheProducts();
  }

  Future<List<Product>> _fetchAndCacheProducts() async {
    try {
      final res = await _authenticatedGet(
        Uri.parse('$_baseUrl/products?active_only=true'),
      );
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        final prods = list.map((p) => Product.fromJson(p)).toList();
        _cachedProducts = prods;
        _productsCacheTime = DateTime.now();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cache_products_json', res.body);
        return prods;
      }
      if (res.statusCode == 401) {
        throw Exception('Session expired. Please log in again.');
      }
    } catch (e) {
      OfflineManager().markOffline();
      if (_cachedProducts != null && _cachedProducts!.isNotEmpty) {
        return _cachedProducts!;
      }
      if (OfflineManager().products.isNotEmpty) {
        _cachedProducts = OfflineManager().products;
        return _cachedProducts!;
      }
      return [];
    }
    return _cachedProducts ?? [];
  }

  void _refreshProductsInBackground() {
    _fetchAndCacheProducts().catchError((_) => <Product>[]);
  }

  /// Stale-while-revalidate for shops: returns instant cached if available
  Future<List<Shop>> getShops({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedShops != null && _cachedShops!.isNotEmpty) {
      if (_shopsCacheTime == null) {
        return await _fetchAndCacheShops();
      }
      final age = DateTime.now().difference(_shopsCacheTime!);
      if (age < const Duration(minutes: 5)) {
        return _cachedShops!;
      }
      _refreshShopsInBackground();
      return _cachedShops!;
    }
    return await _fetchAndCacheShops();
  }

  Future<List<Shop>> _fetchAndCacheShops() async {
    try {
      final res = await _authenticatedGet(
        Uri.parse('$_baseUrl/shops?active_only=true'),
      );
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        final shops = list.map((s) => Shop.fromJson(s)).toList();
        _cachedShops = shops;
        _shopsCacheTime = DateTime.now();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cache_shops_json', res.body);
        return shops;
      }
      if (res.statusCode == 401) {
        throw Exception('Session expired. Please log in again.');
      }
    } catch (e) {
      OfflineManager().markOffline();
      if (_cachedShops != null && _cachedShops!.isNotEmpty) {
        return _cachedShops!;
      }
      if (OfflineManager().shops.isNotEmpty) {
        _cachedShops = OfflineManager().shops;
        return _cachedShops!;
      }
      return [];
    }
    return _cachedShops ?? [];
  }

  void _refreshShopsInBackground() {
    _fetchAndCacheShops().catchError((_) => <Shop>[]);
  }

  Future<Shop> createShop({
    required String name,
    String? city,
    String? phone,
  }) async {
    final payload = {
      'name': name.trim(),
      if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    };
    final res = await _authenticatedPost(
      Uri.parse('$_baseUrl/shops'),
      body: jsonEncode(payload),
    );
    if (res.statusCode == 201) {
      final data = jsonDecode(res.body);
      final newShop = Shop.fromJson(data);
      if (_cachedShops != null) {
        _cachedShops!.removeWhere((s) => s.id == newShop.id);
        _cachedShops!.add(newShop);
        _cachedShops!.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cache_shops_json', jsonEncode(_cachedShops!.map((s) => s.toJson()).toList()));
        } catch (_) {}
      }
      return newShop;
    }
    try {
      final body = jsonDecode(res.body);
      throw Exception(body['detail'] ?? 'Failed to create shop');
    } catch (e) {
      if (e is Exception && !e.toString().contains('FormatException')) {
        rethrow;
      }
      throw Exception('Server error (${res.statusCode}): Failed to create shop');
    }
  }

  void clearSerialCheckCache() {
    _outwardSerialCheckCache.clear();
    _inwardSerialValidateCache.clear();
  }

  // --- INWARD API ---
  Future<Map<String, dynamic>> validateInwardSerial(
    String? productId,
    String serialNumber, {
    String inwardType = 'stock_in',
  }) async {
    final cleanSerial = serialNumber.trim().toUpperCase();
    final cacheKey = '$productId:$cleanSerial:$inwardType';

    if (_inwardSerialValidateCache.containsKey(cacheKey)) {
      return _inwardSerialValidateCache[cacheKey]!;
    }

    // 0ms in-memory fast-path: If serial is in local memory cache, validate immediately
    if (OfflineManager().serials.containsKey(cleanSerial)) {
      final localResult = OfflineManager().validateInwardSerialOffline(productId, cleanSerial, inwardType: inwardType);
      _inwardSerialValidateCache[cacheKey] = localResult;
      return localResult;
    }

    // Fast-path offline check if connection is down
    if (!OfflineManager().isOnline) {
      final offlineResult = OfflineManager().validateInwardSerialOffline(productId, cleanSerial, inwardType: inwardType);
      _inwardSerialValidateCache[cacheKey] = offlineResult;
      return offlineResult;
    }

    final queryParams = <String, String>{
      'serial_number': cleanSerial,
      'inward_type': inwardType,
    };
    if (productId != null && productId.isNotEmpty) {
      queryParams['product_id'] = productId;
    }

    try {
      final uri = Uri.parse('$_baseUrl/inward/validate-serial').replace(queryParameters: queryParams);
      // Fast check: 1200ms timeout with 0 retries
      final res = await _client.get(uri, headers: _headers()).timeout(const Duration(milliseconds: 1200));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _inwardSerialValidateCache[cacheKey] = data;
        OfflineManager().markOnline();
        return data;
      } else {
        String msg = 'Validation error';
        try {
          final err = jsonDecode(res.body);
          msg = err['detail'] ?? msg;
        } catch (_) {}
        throw Exception(msg);
      }
    } catch (e) {
      OfflineManager().markOffline();
      final offlineResult = OfflineManager().validateInwardSerialOffline(productId, cleanSerial, inwardType: inwardType);
      _inwardSerialValidateCache[cacheKey] = offlineResult;
      return offlineResult;
    }
  }

  Future<Map<String, dynamic>> submitInwardBatch({
    required String productId,
    required List<String> serialNumbers,
    String inwardType = 'stock_in',
    Map<String, String>? unitTypes,
    String? remarks,
    String? clientRequestId,
  }) async {
    clearSerialCheckCache();
    final res = await _authenticatedPost(
      Uri.parse('$_baseUrl/inward/batch'),
      body: jsonEncode({
        'product_id': productId,
        'inward_type': inwardType,
        'serials': serialNumbers,
        'serial_numbers': serialNumbers,
        'unit_types': unitTypes,
        'remarks': remarks,
        if (clientRequestId != null) 'client_request_id': clientRequestId,
      }),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      invalidateProductCache();
      _refreshProductsInBackground();
      return jsonDecode(res.body);
    } else {
      String msg = 'Inward submission failed';
      try {
        final err = jsonDecode(res.body);
        msg = err['detail'] ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
  }

  Future<Map<String, dynamic>> submitInwardMultiBatch({
    required List<Map<String, dynamic>> items,
    String? invoiceReference,
    String? remarks,
    String? clientRequestId,
  }) async {
    clearSerialCheckCache();
    final res = await _authenticatedPost(
      Uri.parse('$_baseUrl/inward/multi-batch'),
      body: jsonEncode({
        'items': items,
        'invoice_reference': invoiceReference,
        'remarks': remarks,
        if (clientRequestId != null) 'client_request_id': clientRequestId,
      }),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      invalidateProductCache();
      _refreshProductsInBackground();
      return jsonDecode(res.body);
    } else {
      String msg = 'Inward submission failed';
      try {
        final err = jsonDecode(res.body);
        msg = err['detail'] ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
  }

  // --- OUTWARD API ---
  Future<Map<String, dynamic>> checkOutwardSerial(
    String? productId,
    String serialNumber,
  ) async {
    final cleanSerial = serialNumber.trim().toUpperCase();
    final cacheKey = '${productId ?? "any"}:$cleanSerial';

    if (_outwardSerialCheckCache.containsKey(cacheKey)) {
      return _outwardSerialCheckCache[cacheKey]!;
    }

    // 0ms in-memory fast-path: If serial is in local memory cache, check immediately without network latency
    if (OfflineManager().serials.containsKey(cleanSerial)) {
      final localResult = OfflineManager().checkOutwardSerialOffline(productId, cleanSerial);
      _outwardSerialCheckCache[cacheKey] = localResult;
      return localResult;
    }

    // Fast-path offline check if connection is known to be down
    if (!OfflineManager().isOnline) {
      final offlineResult = OfflineManager().checkOutwardSerialOffline(productId, cleanSerial);
      _outwardSerialCheckCache[cacheKey] = offlineResult;
      return offlineResult;
    }

    final queryParams = <String, String>{
      'serial_number': cleanSerial,
    };
    if (productId != null && productId.isNotEmpty) {
      queryParams['product_id'] = productId;
    }
    try {
      final uri = Uri.parse('$_baseUrl/outward/check-serial').replace(queryParameters: queryParams);
      // Fast check: 1200ms timeout, 0 retries so offline scanning never freezes
      final res = await _client.get(uri, headers: _headers()).timeout(const Duration(milliseconds: 1200));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _outwardSerialCheckCache[cacheKey] = data;
        OfflineManager().markOnline();
        return data;
      } else {
        String msg = 'Serial check failed';
        try {
          final err = jsonDecode(res.body);
          msg = err['detail'] ?? msg;
        } catch (_) {}
        throw Exception(msg);
      }
    } catch (e) {
      // Server down, network drop, or timeout -> instantly mark offline and match from local cache
      OfflineManager().markOffline();
      final offlineResult = OfflineManager().checkOutwardSerialOffline(productId, cleanSerial);
      _outwardSerialCheckCache[cacheKey] = offlineResult;
      return offlineResult;
    }
  }

  Future<Map<String, dynamic>> checkDeliveryReference(
    String shopId,
    String reference,
  ) async {
    if (reference.trim().isEmpty) {
      return {'is_duplicate_today': false};
    }
    final res = await _authenticatedGet(
      Uri.parse(
        '$_baseUrl/outward/check-reference?shop_id=$shopId&reference=${Uri.encodeComponent(reference.trim())}',
      ),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return {'is_duplicate_today': false};
  }

  Future<Map<String, dynamic>> submitOutwardBatch({
    required String shopId,
    required String productId,
    required List<String> serialNumbers,
    Map<String, String>? unitTypes,
    String? billNumber,
    String? deliveryReference,
    String? remarks,
  }) async {
    clearSerialCheckCache();
    final res = await _authenticatedPost(
      Uri.parse('$_baseUrl/outward/batch'),
      body: jsonEncode({
        'shop_id': shopId,
        'product_id': productId,
        'serials': serialNumbers.map((s) => {
          'serial_number': s,
          'confirmed_warning': true,
          if (unitTypes != null && unitTypes.containsKey(s)) 'unit_type': unitTypes[s],
        }).toList(),
        'serial_numbers': serialNumbers,
        'unit_types': unitTypes,
        'bill_number': billNumber?.trim().isEmpty == true ? null : billNumber?.trim(),
        'delivery_reference': deliveryReference?.trim().isEmpty == true ? null : deliveryReference?.trim(),
        'remarks': remarks,
      }),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      invalidateProductCache();
      _refreshProductsInBackground();
      return jsonDecode(res.body);
    } else {
      String msg = 'Outward dispatch failed';
      try {
        final err = jsonDecode(res.body);
        msg = err['detail'] ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
  }

  Future<Map<String, dynamic>> submitOutwardMultiBatch({
    required String shopId,
    required List<Map<String, dynamic>> items,
    String? billNumber,
    String? deliveryReference,
    String? remarks,
    String? clientRequestId,
  }) async {
    clearSerialCheckCache();
    final res = await _authenticatedPost(
      Uri.parse('$_baseUrl/outward/multi-batch'),
      body: jsonEncode({
        'shop_id': shopId,
        'items': items,
        'bill_number': billNumber?.trim().isEmpty == true ? null : billNumber?.trim(),
        'delivery_reference': deliveryReference?.trim().isEmpty == true ? null : deliveryReference?.trim(),
        'remarks': remarks?.trim().isEmpty == true ? null : remarks?.trim(),
        if (clientRequestId != null) 'client_request_id': clientRequestId,
      }),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      invalidateProductCache();
      _refreshProductsInBackground();
      return jsonDecode(res.body);
    } else {
      String msg = 'Outward dispatch failed';
      try {
        final err = jsonDecode(res.body);
        msg = err['detail'] ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
  }

  // --- SERIAL LOOKUP ---
  Future<SerialLookupDetail> lookupSerial(String serialNumber) async {
    final cleanSerial = serialNumber.trim();
    if (cleanSerial.isEmpty) {
      throw Exception('Serial number cannot be empty');
    }

    // 1. Fast-path offline check if connection is known to be down
    if (!OfflineManager().isOnline) {
      return OfflineManager().lookupSerialOffline(cleanSerial);
    }

    // 2. Online query with fast 1500ms timeout
    try {
      final uri = Uri.parse(
        '$_baseUrl/serials/lookup?serial_number=${Uri.encodeComponent(cleanSerial)}',
      );
      final res = await _client.get(uri, headers: _headers()).timeout(const Duration(milliseconds: 1500));

      if (res.statusCode == 200) {
        OfflineManager().markOnline();
        return SerialLookupDetail.fromJson(jsonDecode(res.body));
      } else if (res.statusCode == 404) {
        // Check offline snapshot before deciding it's completely missing
        final offlineDetail = OfflineManager().lookupSerialOffline(cleanSerial);
        if (offlineDetail.isTracked) {
          return offlineDetail;
        }
        String msg = 'Serial number "$cleanSerial" not found in system.';
        try {
          final err = jsonDecode(res.body);
          msg = err['detail'] ?? msg;
        } catch (_) {}
        throw Exception(msg);
      } else {
        String msg = 'Serial lookup failed';
        try {
          final err = jsonDecode(res.body);
          msg = err['detail'] ?? msg;
        } catch (_) {}
        throw Exception(msg);
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('not found in system')) {
        rethrow;
      }
      // Server down, network drop, or timeout -> instantly mark offline and match from local snapshot
      OfflineManager().markOffline();
      return OfflineManager().lookupSerialOffline(cleanSerial);
    }
  }

  // --- BILL LOOKUP ---
  Future<List<BillListItem>> listBills({String? search, int limit = 50, bool forceRefresh = false}) async {
    final isUnfiltered = search == null || search.trim().isEmpty;
    if (isUnfiltered && !forceRefresh && _cachedBills != null && _cachedBills!.isNotEmpty) {
      final age = _billsCacheTime != null ? DateTime.now().difference(_billsCacheTime!) : Duration.zero;
      if (age < const Duration(minutes: 5)) {
        return _cachedBills!;
      }
    }

    final uri = Uri.parse('$_baseUrl/outward/bills').replace(queryParameters: {
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'limit': limit.toString(),
    });
    final res = await _authenticatedGet(uri);
    if (res.statusCode == 200) {
      final List<dynamic> data = jsonDecode(res.body);
      final bills = data.map((j) => BillListItem.fromJson(j as Map<String, dynamic>)).toList();
      if (isUnfiltered) {
        _cachedBills = bills;
        _billsCacheTime = DateTime.now();
      }
      return bills;
    } else {
      if (isUnfiltered && _cachedBills != null) return _cachedBills!;
      throw Exception('Failed to load bills');
    }
  }

  Future<BillDetail> getBillDetail(String billNumber) async {
    final uri = Uri.parse(
      '$_baseUrl/outward/bills/${Uri.encodeComponent(billNumber)}',
    );
    final res = await _authenticatedGet(uri);
    if (res.statusCode == 200) {
      return BillDetail.fromJson(jsonDecode(res.body));
    } else {
      String msg = 'Bill not found';
      try {
        msg = jsonDecode(res.body)['detail'] ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
  }

  // --- TAILSCALE OFFICE PRINT SERVER ---

  Future<Map<String, dynamic>> getOfficePrinters() async {
    final uri = Uri.parse('$_baseUrl/print/printers');
    final res = await _authenticatedGet(uri);
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      String msg = 'Failed to load printers from Office PC';
      try {
        msg = jsonDecode(res.body)['detail'] ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
  }

  Future<Map<String, dynamic>> printBill({
    required String billNumber,
    String? printerName,
    bool dryRun = false,
  }) async {
    final uri = Uri.parse('$_baseUrl/print/bill');
    final payload = <String, dynamic>{
      'bill_number': billNumber.trim(),
      'dry_run': dryRun,
    };
    if (printerName != null && printerName.isNotEmpty) {
      payload['printer_name'] = printerName;
    }

    final res = await _authenticatedPost(uri, body: jsonEncode(payload));
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      String msg = 'Failed to print bill on Office PC';
      try {
        msg = jsonDecode(res.body)['detail'] ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
  }

  Future<Map<String, dynamic>> printGodownReport({
    required String reportType,
    String? printerName,
    String? categoryId,
    String? shopId,
    String? productId,
    String? dateFrom,
    String? dateTo,
    bool? isMatched,
    bool dryRun = false,
  }) async {
    final uri = Uri.parse('$_baseUrl/print/godown-report');
    final payload = <String, dynamic>{
      'report_type': reportType,
      'dry_run': dryRun,
    };
    if (printerName != null && printerName.isNotEmpty) payload['printer_name'] = printerName;
    if (categoryId != null) payload['category_id'] = categoryId;
    if (shopId != null) payload['shop_id'] = shopId;
    if (productId != null) payload['product_id'] = productId;
    if (dateFrom != null) payload['date_from'] = dateFrom;
    if (dateTo != null) payload['date_to'] = dateTo;
    if (isMatched != null) payload['is_matched'] = isMatched;

    final res = await _authenticatedPost(uri, body: jsonEncode(payload));
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      String msg = 'Failed to print Godown Report on Office PC';
      try {
        msg = jsonDecode(res.body)['detail'] ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
  }

  Future<Map<String, dynamic>> printRawPdf({
    required List<int> pdfBytes,
    String? printerName,
    String? jobName,
    bool dryRun = false,
  }) async {
    final uri = Uri.parse('$_baseUrl/print/raw-pdf');
    final payload = <String, dynamic>{
      'pdf_base64': base64Encode(pdfBytes),
      'dry_run': dryRun,
    };
    if (printerName != null && printerName.isNotEmpty) payload['printer_name'] = printerName;
    if (jobName != null) payload['job_name'] = jobName;

    final res = await _authenticatedPost(uri, body: jsonEncode(payload));
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      String msg = 'Failed to print document on Office PC';
      try {
        msg = jsonDecode(res.body)['detail'] ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
  }

  Future<Map<String, dynamic>> printTestSlip({String? printerName, bool dryRun = false}) async {
    final uri = Uri.parse('$_baseUrl/print/test');
    final payload = <String, dynamic>{
      if (printerName != null && printerName.isNotEmpty) 'printer_name': printerName,
      'dry_run': dryRun,
    };

    final res = await _authenticatedPost(uri, body: jsonEncode(payload));
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      String msg = 'Test print failed on Office PC';
      try {
        msg = jsonDecode(res.body)['detail'] ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
  }
}
