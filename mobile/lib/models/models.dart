class User {
  final String id;
  final String username;
  final String fullName;
  final String role;
  final bool isActive;

  User({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.isActive,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      fullName: json['full_name'] ?? '',
      role: json['role'] ?? 'staff',
      isActive: json['is_active'] ?? true,
    );
  }
}

class Product {
  final String id;
  final String name;
  final String? sku;
  final String categoryId;
  final String? categoryName;
  final String brand;
  final String model;
  final String? sizeCapacity;
  final String unit;
  final bool serialNumberRequired;
  final int currentStockQty;
  final bool outOfStockReminder;
  final bool hasDualSerial;

  Product({
    required this.id,
    required this.name,
    this.sku,
    required this.categoryId,
    this.categoryName,
    required this.brand,
    required this.model,
    this.sizeCapacity,
    required this.unit,
    required this.serialNumberRequired,
    required this.currentStockQty,
    required this.outOfStockReminder,
    this.hasDualSerial = false,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      sku: json['sku'],
      categoryId: json['category_id'] ?? '',
      categoryName: json['category_name'],
      brand: json['brand'] ?? '',
      model: json['model'] ?? '',
      sizeCapacity: json['size_capacity'],
      unit: json['unit'] ?? 'unit',
      serialNumberRequired: json['serial_number_required'] ?? true,
      currentStockQty: json['current_stock_qty'] ?? 0,
      outOfStockReminder: json['out_of_stock_reminder'] ?? false,
      hasDualSerial: json['has_dual_serial'] ?? false,
    );
  }
}

class Shop {
  final String id;
  final String name;
  final String city;
  final String? phone;
  final bool isActive;

  Shop({
    required this.id,
    required this.name,
    required this.city,
    this.phone,
    required this.isActive,
  });

  factory Shop.fromJson(Map<String, dynamic> json) {
    return Shop(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      city: json['city'] ?? '',
      phone: json['phone'],
      isActive: json['is_active'] ?? true,
    );
  }
}

enum OutwardCase {
  matched, // Case 1: tracked & available
  recordedOnly, // Case 2: pre-go-live stock, not inwarded
  statusWarning, // Case 3: found but dispatched or damaged
  modelMismatch, // Case 4: serial belongs to another model
}

class OutwardScanResult {
  final String serialNumber;
  final Product? product;
  final OutwardCase caseType;
  final bool isMatched;
  final bool isFlaggedForReview;
  final String? warningMessage;
  final String? existingModelName;
  final String? lastShopName;
  final String? currentStatus;
  String? unitType; // 'indoor', 'outdoor', or null

  OutwardScanResult({
    required this.serialNumber,
    this.product,
    required this.caseType,
    required this.isMatched,
    this.isFlaggedForReview = false,
    this.warningMessage,
    this.existingModelName,
    this.lastShopName,
    this.currentStatus,
    this.unitType,
  });
}

class SerialHistoryEntry {
  final String id;
  final String action;
  final String? fromStatus;
  final String? toStatus;
  final String? shopName;
  final String? shopCity;
  final String userName;
  final String createdAt;
  final String? remarks;

  SerialHistoryEntry({
    required this.id,
    required this.action,
    this.fromStatus,
    this.toStatus,
    this.shopName,
    this.shopCity,
    required this.userName,
    required this.createdAt,
    this.remarks,
  });

  factory SerialHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SerialHistoryEntry(
      id: json['id'] ?? '',
      action: json['action'] ?? '',
      fromStatus: json['from_status'],
      toStatus: json['to_status'],
      shopName: json['shop_name'],
      shopCity: json['shop_city'],
      userName: json['user_name'] ?? 'Staff',
      createdAt: json['created_at'] ?? '',
      remarks: json['remarks'],
    );
  }
}

// ─── BILL / DISPATCH MODELS ────────────────────────────────────────────────

class BillListItem {
  final String billNumber;
  final String shopId;
  final String shopName;
  final String shopCity;
  final String transactionDate;
  final String createdAt;
  final String dispatchedByName;
  final String? deliveryReference;
  final String? remarks;
  final int totalUnits;
  final int totalBatches;
  final List<String> modelsSummary;

  BillListItem({
    required this.billNumber,
    required this.shopId,
    required this.shopName,
    required this.shopCity,
    required this.transactionDate,
    required this.createdAt,
    required this.dispatchedByName,
    this.deliveryReference,
    this.remarks,
    required this.totalUnits,
    required this.totalBatches,
    required this.modelsSummary,
  });

  factory BillListItem.fromJson(Map<String, dynamic> json) {
    return BillListItem(
      billNumber: json['bill_number'] ?? '',
      shopId: json['shop_id'] ?? '',
      shopName: json['shop_name'] ?? '',
      shopCity: json['shop_city'] ?? '',
      transactionDate: json['transaction_date'] ?? '',
      createdAt: json['created_at'] ?? '',
      dispatchedByName: json['dispatched_by_name'] ?? '',
      deliveryReference: json['delivery_reference'],
      remarks: json['remarks'],
      totalUnits: json['total_units'] ?? 0,
      totalBatches: json['total_batches'] ?? 0,
      modelsSummary: List<String>.from(json['models_summary'] ?? []),
    );
  }
}

class BillLine {
  final String id;
  final String serialText;
  final bool isMatched;
  final bool isFlagged;
  final String? unitType;
  final String statusLabel;

  BillLine({
    required this.id,
    required this.serialText,
    required this.isMatched,
    required this.isFlagged,
    this.unitType,
    required this.statusLabel,
  });

  factory BillLine.fromJson(Map<String, dynamic> json) {
    return BillLine(
      id: json['id'] ?? '',
      serialText: json['serial_text'] ?? '',
      isMatched: json['is_matched'] ?? false,
      isFlagged: json['is_flagged_for_review'] ?? false,
      unitType: json['unit_type'],
      statusLabel: json['status_label'] ?? 'Recorded only',
    );
  }
}

class BillBatch {
  final String batchId;
  final String productId;
  final String productName;
  final String brand;
  final String model;
  final int quantity;
  final int matchedCount;
  final int unmatchedCount;
  final int flaggedCount;
  final List<BillLine> lines;

  BillBatch({
    required this.batchId,
    required this.productId,
    required this.productName,
    required this.brand,
    required this.model,
    required this.quantity,
    required this.matchedCount,
    required this.unmatchedCount,
    required this.flaggedCount,
    required this.lines,
  });

  factory BillBatch.fromJson(Map<String, dynamic> json) {
    return BillBatch(
      batchId: json['batch_id'] ?? '',
      productId: json['product_id'] ?? '',
      productName: json['product_name'] ?? '',
      brand: json['brand'] ?? '',
      model: json['model'] ?? '',
      quantity: json['quantity'] ?? 0,
      matchedCount: json['matched_count'] ?? 0,
      unmatchedCount: json['unmatched_count'] ?? 0,
      flaggedCount: json['flagged_count'] ?? 0,
      lines: (json['lines'] as List<dynamic>? ?? [])
          .map((l) => BillLine.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }
}

class BillDetail {
  final String billNumber;
  final String shopId;
  final String shopName;
  final String shopCity;
  final String transactionDate;
  final String createdAt;
  final String dispatchedByName;
  final String? deliveryReference;
  final String? remarks;
  final int totalUnits;
  final int totalBatches;
  final List<BillBatch> batches;

  BillDetail({
    required this.billNumber,
    required this.shopId,
    required this.shopName,
    required this.shopCity,
    required this.transactionDate,
    required this.createdAt,
    required this.dispatchedByName,
    this.deliveryReference,
    this.remarks,
    required this.totalUnits,
    required this.totalBatches,
    required this.batches,
  });

  factory BillDetail.fromJson(Map<String, dynamic> json) {
    return BillDetail(
      billNumber: json['bill_number'] ?? '',
      shopId: json['shop_id'] ?? '',
      shopName: json['shop_name'] ?? '',
      shopCity: json['shop_city'] ?? '',
      transactionDate: json['transaction_date'] ?? '',
      createdAt: json['created_at'] ?? '',
      dispatchedByName: json['dispatched_by_name'] ?? '',
      deliveryReference: json['delivery_reference'],
      remarks: json['remarks'],
      totalUnits: json['total_units'] ?? 0,
      totalBatches: json['total_batches'] ?? 0,
      batches: (json['batches'] as List<dynamic>? ?? [])
          .map((b) => BillBatch.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ─── SERIAL LOOKUP ──────────────────────────────────────────────────────────

class SerialLookupDetail {
  final String serialNumber;
  final bool isTracked;
  final String? status;
  final String? productName;
  final String? brand;
  final String? model;
  final String? lastShopName;
  final String? lastShopCity;
  final String statusLabel;
  final List<SerialHistoryEntry> history;

  SerialLookupDetail({
    required this.serialNumber,
    required this.isTracked,
    this.status,
    this.productName,
    this.brand,
    this.model,
    this.lastShopName,
    this.lastShopCity,
    required this.statusLabel,
    required this.history,
  });

  factory SerialLookupDetail.fromJson(Map<String, dynamic> json) {
    final list = (json['history'] as List<dynamic>? ?? [])
        .map((h) => SerialHistoryEntry.fromJson(h as Map<String, dynamic>))
        .toList();

    return SerialLookupDetail(
      serialNumber: json['serial_number'] ?? '',
      isTracked: json['is_tracked'] ?? false,
      status: json['status'],
      productName: json['product_name'],
      brand: json['brand'],
      model: json['model'],
      lastShopName: json['last_shop_name'],
      lastShopCity: json['last_shop_city'],
      statusLabel: json['status_label'] ?? 'Unknown',
      history: list,
    );
  }
}
