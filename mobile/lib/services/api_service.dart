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

  String _baseUrl = defaultBaseUrl;
  String? _accessToken;
  String? _refreshToken;
  User? _currentUser;
  String? _deviceUid;
  bool _isDeviceApproved = false;

  String get baseUrl => _baseUrl;
  User? get currentUser => _currentUser;
  String? get deviceUid => _deviceUid;
  bool get isDeviceApproved => _isDeviceApproved;
  bool get isAuthenticated => _accessToken != null && _currentUser != null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Base URL - auto-migrate to permanent Tailscale IP
    final savedUrl = prefs.getString('base_url');
    if (savedUrl == null || !savedUrl.contains('100.66.97.14')) {
      _baseUrl = defaultBaseUrl;
      await prefs.setString('base_url', defaultBaseUrl);
    } else {
      _baseUrl = savedUrl;
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
      final res = await http.post(
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
    final res = await http.post(
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
      final res = await http.post(
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

  Future<http.Response> _authenticatedGet(Uri uri) async {
    var res = await http.get(uri, headers: _headers());
    if (res.statusCode == 401 && _refreshToken != null) {
      final refreshed = await _refreshTokenNow();
      if (refreshed) {
        res = await http.get(uri, headers: _headers());
      }
    }
    return res;
  }

  Future<http.Response> _authenticatedPost(Uri uri, {Object? body}) async {
    var res = await http.post(uri, headers: _headers(), body: body);
    if (res.statusCode == 401 && _refreshToken != null) {
      final refreshed = await _refreshTokenNow();
      if (refreshed) {
        res = await http.post(uri, headers: _headers(), body: body);
      }
    }
    return res;
  }

  // --- PRODUCTS & SHOPS ---
  Future<List<Product>> getProducts() async {
    final res = await _authenticatedGet(
      Uri.parse('$_baseUrl/products?active_only=true'),
    );
    if (res.statusCode == 200) {
      final List list = jsonDecode(res.body);
      return list.map((p) => Product.fromJson(p)).toList();
    }
    if (res.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }
    String msg = 'Failed to load products';
    try {
      final err = jsonDecode(res.body);
      msg = err['detail'] ?? msg;
    } catch (_) {}
    throw Exception(msg);
  }

  Future<List<Shop>> getShops() async {
    final res = await _authenticatedGet(
      Uri.parse('$_baseUrl/shops?active_only=true'),
    );
    if (res.statusCode == 200) {
      final List list = jsonDecode(res.body);
      return list.map((s) => Shop.fromJson(s)).toList();
    }
    if (res.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }
    String msg = 'Failed to load shops';
    try {
      final err = jsonDecode(res.body);
      msg = err['detail'] ?? msg;
    } catch (_) {}
    throw Exception(msg);
  }

  // --- INWARD API ---
  Future<Map<String, dynamic>> validateInwardSerial(
    String productId,
    String serialNumber,
  ) async {
    final res = await _authenticatedGet(
      Uri.parse(
        '$_baseUrl/inward/validate-serial?product_id=$productId&serial_number=${Uri.encodeComponent(serialNumber.trim())}',
      ),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
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
    String? remarks,
  }) async {
    final res = await _authenticatedPost(
      Uri.parse('$_baseUrl/inward/batch'),
      body: jsonEncode({
        'product_id': productId,
        'serials': serialNumbers,
        'serial_numbers': serialNumbers,
        'remarks': remarks,
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
    final res = await _authenticatedGet(
      Uri.parse(
        '$_baseUrl/outward/check-serial?product_id=$productId&serial_number=${Uri.encodeComponent(serialNumber.trim())}',
      ),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
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
    String? deliveryReference,
    String? remarks,
  }) async {
    final res = await _authenticatedPost(
      Uri.parse('$_baseUrl/outward/batch'),
      body: jsonEncode({
        'shop_id': shopId,
        'product_id': productId,
        'serials': serialNumbers.map((s) => {'serial_number': s, 'confirmed_warning': true}).toList(),
        'serial_numbers': serialNumbers,
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
}
