import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocket? _socket;
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();

  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isConnected = false;
  bool _isConnecting = false;

  Stream<Map<String, dynamic>> get stream => _eventController.stream;
  bool get isConnected => _isConnected;

  void connect() {
    if (_isConnected || _isConnecting) return;
    _isConnecting = true;

    _reconnectTimer?.cancel();
    _pingTimer?.cancel();

    _establishConnection();
  }

  String _getWsUrl() {
    final httpUrl = ApiService().baseUrl;
    String wsUrl = httpUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
    if (!wsUrl.endsWith('/ws')) {
      wsUrl = '$wsUrl/ws';
    }
    return wsUrl;
  }

  Future<void> _establishConnection() async {
    final uriStr = _getWsUrl();
    try {
      final uri = Uri.parse(uriStr);
      _socket = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 4));
      _isConnected = true;
      _isConnecting = false;
      debugPrint('[WS] Connected to $uriStr');

      // Heartbeat ping every 20 seconds
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
        if (_isConnected && _socket != null) {
          try {
            _socket!.add('ping');
          } catch (_) {
            _handleDisconnect();
          }
        }
      });

      _socket!.listen(
        (data) {
          if (data is String) {
            if (data == 'pong') return;
            try {
              final parsed = jsonDecode(data);
              if (parsed is Map<String, dynamic>) {
                _eventController.add(parsed);
              }
            } catch (e) {
              debugPrint('[WS] Failed to parse message: $e');
            }
          }
        },
        onError: (err) {
          debugPrint('[WS] Error: $err');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('[WS] Connection closed');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[WS] Connection attempt failed: $e');
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    _pingTimer?.cancel();
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;

    // Retry connection after 3 seconds
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      connect();
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _isConnected = false;
    _isConnecting = false;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}
