import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

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
        return _isDeviceApproved;
      }
      return false;
    } catch (e) {
      return false;
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
      return 'Cannot reach server at $_baseUrl. Please check your Wi-Fi or VPN connection.';
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

  /// Stale-while-revalidate for products: returns instant cached if available
  Future<List<Product>> getProducts({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedProducts != null && _cachedProducts!.isNotEmpty) {
      final age = _productsCacheTime != null ? DateTime.now().difference(_productsCacheTime!) : Duration.zero;
      if (age < const Duration(minutes: 10)) {
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
      if (_cachedProducts != null && _cachedProducts!.isNotEmpty) {
        return _cachedProducts!;
      }
      rethrow;
    }
    return _cachedProducts ?? [];
  }

  void _refreshProductsInBackground() {
    _fetchAndCacheProducts().catchError((_) => <Product>[]);
  }

  /// Stale-while-revalidate for shops: returns instant cached if available
  Future<List<Shop>> getShops({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedShops != null && _cachedShops!.isNotEmpty) {
      final age = _shopsCacheTime != null ? DateTime.now().difference(_shopsCacheTime!) : Duration.zero;
      if (age < const Duration(minutes: 15)) {
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
      if (_cachedShops != null && _cachedShops!.isNotEmpty) {
        return _cachedShops!;
      }
      rethrow;
    }
    return _cachedShops ?? [];
  }

  void _refreshShopsInBackground() {
    _fetchAndCacheShops().catchError((_) => <Shop>[]);
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

    final queryParams = <String, String>{
      'serial_number': cleanSerial,
      'inward_type': inwardType,
    };
    if (productId != null && productId.isNotEmpty) {
      queryParams['product_id'] = productId;
    }
    final uri = Uri.parse('$_baseUrl/inward/validate-serial').replace(queryParameters: queryParams);
    final res = await _authenticatedGet(uri);

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      _inwardSerialValidateCache[cacheKey] = data;
      return data;
    } else {
      String msg = 'Validation error';
      try {
        final err = jsonDecode(res.body);
        msg = err['detail'] ?? msg;
      } catch (_) {}
      throw Exception(msg);
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
    String productId,
    String serialNumber,
  ) async {
    final cleanSerial = serialNumber.trim().toUpperCase();
    final cacheKey = '$productId:$cleanSerial';

    if (_outwardSerialCheckCache.containsKey(cacheKey)) {
      return _outwardSerialCheckCache[cacheKey]!;
    }

    final res = await _authenticatedGet(
      Uri.parse(
        '$_baseUrl/outward/check-serial?product_id=$productId&serial_number=${Uri.encodeComponent(cleanSerial)}',
      ),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      _outwardSerialCheckCache[cacheKey] = data;
      return data;
    } else {
      String msg = 'Serial check failed';
      try {
        final err = jsonDecode(res.body);
        msg = err['detail'] ?? msg;
      } catch (_) {}
      throw Exception(msg);
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
    final res = await _authenticatedGet(
      Uri.parse(
        '$_baseUrl/serials/lookup?serial_number=${Uri.encodeComponent(serialNumber.trim())}',
      ),
    );

    if (res.statusCode == 200) {
      return SerialLookupDetail.fromJson(jsonDecode(res.body));
    } else {
      String msg = 'Serial lookup failed';
      try {
        final err = jsonDecode(res.body);
        msg = err['detail'] ?? msg;
      } catch (_) {}
      throw Exception(msg);
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
}
