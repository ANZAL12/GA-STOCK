import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SessionType { outward, inward, quickDispatch }

class SessionDraft {
  final SessionType type;
  final DateTime updatedAt;
  final String? shopId;
  final String? shopName;
  final String? productId;
  final String? productName;
  final String? inwardType; // 'stock_in', 'return', 'damaged'
  final String? billNumber;
  final String? deliveryReference;
  final String? remarks;
  final String? unitType;
  final int currentStep;
  final List<Map<String, dynamic>> items;

  SessionDraft({
    required this.type,
    required this.updatedAt,
    this.shopId,
    this.shopName,
    this.productId,
    this.productName,
    this.inwardType,
    this.billNumber,
    this.deliveryReference,
    this.remarks,
    this.unitType,
    this.currentStep = 1,
    required this.items,
  });

  String get typeTitle {
    switch (type) {
      case SessionType.outward:
        return 'Outward Dispatch';
      case SessionType.inward:
        if (inwardType == 'damaged') return 'Damaged Inward';
        if (inwardType == 'return') return 'Customer Return Inward';
        return 'Inward Stock-In';
      case SessionType.quickDispatch:
        return 'Quick Multi-Model Dispatch';
    }
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'updated_at': updatedAt.toIso8601String(),
    'shop_id': shopId,
    'shop_name': shopName,
    'product_id': productId,
    'product_name': productName,
    'inward_type': inwardType,
    'bill_number': billNumber,
    'delivery_reference': deliveryReference,
    'remarks': remarks,
    'unit_type': unitType,
    'current_step': currentStep,
    'items': items,
  };

  factory SessionDraft.fromJson(Map<String, dynamic> json) {
    SessionType parsedType = SessionType.outward;
    final tStr = json['type']?.toString();
    if (tStr == 'inward') {
      parsedType = SessionType.inward;
    } else if (tStr == 'quickDispatch' || tStr == 'quick_dispatch') {
      parsedType = SessionType.quickDispatch;
    }

    final itemsRaw = json['items'] as List? ?? [];
    final itemsList = itemsRaw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return SessionDraft(
      type: parsedType,
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
      shopId: json['shop_id']?.toString(),
      shopName: json['shop_name']?.toString(),
      productId: json['product_id']?.toString(),
      productName: json['product_name']?.toString(),
      inwardType: json['inward_type']?.toString(),
      billNumber: json['bill_number']?.toString(),
      deliveryReference: json['delivery_reference']?.toString(),
      remarks: json['remarks']?.toString(),
      unitType: json['unit_type']?.toString(),
      currentStep: json['current_step'] is int ? json['current_step'] : 1,
      items: itemsList,
    );
  }
}

/// Service to automatically persist and recover unsubmitted scanning sessions
/// across app crashes, unexpected terminations, or device restarts.
class SessionRecoveryService {
  static final SessionRecoveryService _instance = SessionRecoveryService._internal();
  factory SessionRecoveryService() => _instance;
  SessionRecoveryService._internal();

  static const String _prefKey = 'active_unsubmitted_session_draft_v1';
  final ValueNotifier<SessionDraft?> activeDraftNotifier = ValueNotifier<SessionDraft?>(null);

  Timer? _saveDebounceTimer;
  SessionDraft? _pendingDraft;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await checkActiveDraft();
  }

  Future<SessionDraft?> checkActiveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final draft = SessionDraft.fromJson(decoded);
          // Only offer recovery if at least 1 item was scanned
          if (draft.items.isNotEmpty) {
            activeDraftNotifier.value = draft;
            return draft;
          }
        }
      }
    } catch (e) {
      debugPrint('[SessionRecoveryService] Error loading draft: $e');
    }
    activeDraftNotifier.value = null;
    return null;
  }

  /// Automatically persists draft to local disk with 300ms debounce
  void saveDraftDebounced(SessionDraft draft) {
    _pendingDraft = draft;
    activeDraftNotifier.value = draft;
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (_pendingDraft != null) {
        await _writeToDisk(_pendingDraft!);
      }
    });
  }

  Future<void> saveDraftImmediate(SessionDraft draft) async {
    _saveDebounceTimer?.cancel();
    _pendingDraft = draft;
    activeDraftNotifier.value = draft;
    await _writeToDisk(draft);
  }

  Future<void> _writeToDisk(SessionDraft draft) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (draft.items.isEmpty) {
        await prefs.remove(_prefKey);
        activeDraftNotifier.value = null;
      } else {
        await prefs.setString(_prefKey, jsonEncode(draft.toJson()));
      }
    } catch (e) {
      debugPrint('[SessionRecoveryService] Error writing draft to disk: $e');
    }
  }

  /// Clears active session draft upon successful submission or user discard
  Future<void> clearDraft() async {
    _saveDebounceTimer?.cancel();
    _pendingDraft = null;
    activeDraftNotifier.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
      debugPrint('[SessionRecoveryService] Active draft cleared');
    } catch (_) {}
  }
}
