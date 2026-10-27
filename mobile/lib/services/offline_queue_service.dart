import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'offline_manager.dart';

enum QueueType { inward, outward }

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

  /// Synchronize a single batch directly by batch ID
  Future<Map<String, dynamic>> syncSingle(String batchId) async {
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

    return {
      'total': list.length,
      'synced': synced,
      'failed': failed,
      'errors': errors,
    };
  }
}
