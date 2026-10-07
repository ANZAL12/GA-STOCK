import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

enum QueueType { inward, outward }

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
}

class OfflineQueueService {
  static final OfflineQueueService _instance = OfflineQueueService._internal();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._internal();

  static const String _storageKey = 'godown_offline_queue';

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

  Future<void> remove(String batchId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getQueue();
    list.removeWhere((b) => b.id == batchId);
    final raw = list.map((b) => jsonEncode(b.toJson())).toList();
    await prefs.setStringList(_storageKey, raw);
  }

  Future<void> clearQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<int> queueCount() async {
    final list = await getQueue();
    return list.length;
  }

  Future<Map<String, dynamic>> syncAll() async {
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
          await api.submitInwardBatch(
            productId: item.payload['product_id'],
            serialNumbers: List<String>.from(item.payload['serial_numbers']),
            unitTypes: item.payload['unit_types'] != null
                ? Map<String, String>.from(item.payload['unit_types'])
                : null,
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
            deliveryReference: item.payload['delivery_reference'],
            remarks: item.payload['remarks'],
          );
        }
        await remove(item.id);
        synced++;
      } catch (e) {
        failed++;
        errors.add('${item.description}: ${e.toString()}');
      }
    }

    return {
      'total': list.length,
      'synced': synced,
      'failed': failed,
      'errors': errors,
    };
  }
}
