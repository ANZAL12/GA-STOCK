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
  final OutwardCase caseType;
  final bool isMatched;
  final bool isFlaggedForReview;
  final String? warningMessage;
  final String? existingModelName;
  final String? lastShopName;
  final String? currentStatus;

  OutwardScanResult({
    required this.serialNumber,
    required this.caseType,
    required this.isMatched,
    this.isFlaggedForReview = false,
    this.warningMessage,
    this.existingModelName,
    this.lastShopName,
    this.currentStatus,
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
