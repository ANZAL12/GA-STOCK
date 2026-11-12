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
  final String? tallyGuid;
  final String? tallyPartNumber;
  final String source;

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
    this.tallyGuid,
    this.tallyPartNumber,
    this.source = 'TALLY',
  });

  Product copyWith({
    String? id,
    String? name,
    String? sku,
    String? categoryId,
    String? categoryName,
    String? brand,
    String? model,
    String? sizeCapacity,
    String? unit,
    bool? serialNumberRequired,
    int? currentStockQty,
    bool? outOfStockReminder,
    bool? hasDualSerial,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      sizeCapacity: sizeCapacity ?? this.sizeCapacity,
      unit: unit ?? this.unit,
      serialNumberRequired: serialNumberRequired ?? this.serialNumberRequired,
      currentStockQty: currentStockQty ?? this.currentStockQty,
      outOfStockReminder: outOfStockReminder ?? this.outOfStockReminder,
      hasDualSerial: hasDualSerial ?? this.hasDualSerial,
    );
  }

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
      tallyGuid: json['tally_guid'],
      tallyPartNumber: json['tally_part_number'],
      source: json['source'] ?? 'TALLY',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sku': sku,
    'category_id': categoryId,
    'category_name': categoryName,
    'brand': brand,
    'model': model,
    'size_capacity': sizeCapacity,
    'unit': unit,
    'serial_number_required': serialNumberRequired,
    'current_stock_qty': currentStockQty,
    'out_of_stock_reminder': outOfStockReminder,
    'has_dual_serial': hasDualSerial,
    'tally_guid': tallyGuid,
    'tally_part_number': tallyPartNumber,
    'source': source,
  };
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

  Shop copyWith({
    String? id,
    String? name,
    String? city,
    String? phone,
    bool? isActive,
  }) {
    return Shop(
      id: id ?? this.id,
      name: name ?? this.name,
      city: city ?? this.city,
      phone: phone ?? this.phone,
      isActive: isActive ?? this.isActive,
    );
  }

  factory Shop.fromJson(Map<String, dynamic> json) {
    return Shop(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      city: json['city'] ?? '',
      phone: json['phone'],
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'city': city,
    'phone': phone,
    'is_active': isActive,
  };
}

class Category {
  final String id;
  final String name;
  final bool hasDualSerial;
  final bool isActive;
  final int productCount;
  final String? tallyGuid;
  final String? tallyParentGroup;
  final String source;

  Category({
    required this.id,
    required this.name,
    this.hasDualSerial = false,
    this.isActive = true,
    this.productCount = 0,
    this.tallyGuid,
    this.tallyParentGroup,
    this.source = 'TALLY',
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      hasDualSerial: json['has_dual_serial'] ?? false,
      isActive: json['is_active'] ?? true,
      productCount: json['product_count'] ?? 0,
      tallyGuid: json['tally_guid'],
      tallyParentGroup: json['tally_parent_group'],
      source: json['source'] ?? 'TALLY',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'has_dual_serial': hasDualSerial,
    'is_active': isActive,
    'product_count': productCount,
    'tally_guid': tallyGuid,
    'tally_parent_group': tallyParentGroup,
    'source': source,
  };
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
  int sequenceNumber;

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
    this.sequenceNumber = 0,
  });

  Map<String, dynamic> toJson() => {
    'serialNumber': serialNumber,
    'product': product?.toJson(),
    'caseType': caseType.name,
    'isMatched': isMatched,
    'isFlaggedForReview': isFlaggedForReview,
    'warningMessage': warningMessage,
    'existingModelName': existingModelName,
    'lastShopName': lastShopName,
    'currentStatus': currentStatus,
    'unitType': unitType,
    'sequenceNumber': sequenceNumber,
  };

  factory OutwardScanResult.fromJson(Map<String, dynamic> json) {
    return OutwardScanResult(
      serialNumber: json['serialNumber'] ?? '',
      product: json['product'] != null ? Product.fromJson(json['product']) : null,
      caseType: OutwardCase.values.firstWhere(
        (e) => e.name == json['caseType'],
        orElse: () => OutwardCase.matched,
      ),
      isMatched: json['isMatched'] ?? true,
      isFlaggedForReview: json['isFlaggedForReview'] ?? false,
      warningMessage: json['warningMessage'],
      existingModelName: json['existingModelName'],
      lastShopName: json['lastShopName'],
      currentStatus: json['currentStatus'],
      unitType: json['unitType'],
      sequenceNumber: json['sequenceNumber'] ?? 0,
    );
  }
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
  final String? shopGstin;
  final String? shopAddress;
  final String? shopState;
  final String? shopPhone;
  final String? vehicleNumber;
  final String transactionDate;
  final String createdAt;
  final String dispatchedByName;
  final String? deliveryReference;
  final String? remarks;
  final int totalUnits;
  final int totalBatches;
  final bool isCancelled;
  final String? cancelledAt;
  final String? cancelledByName;
  final String? cancelReason;
  final List<String> modelsSummary;

  BillListItem({
    required this.billNumber,
    required this.shopId,
    required this.shopName,
    required this.shopCity,
    this.shopGstin,
    this.shopAddress,
    this.shopState,
    this.shopPhone,
    this.vehicleNumber,
    required this.transactionDate,
    required this.createdAt,
    required this.dispatchedByName,
    this.deliveryReference,
    this.remarks,
    required this.totalUnits,
    required this.totalBatches,
    this.isCancelled = false,
    this.cancelledAt,
    this.cancelledByName,
    this.cancelReason,
    required this.modelsSummary,
  });

  factory BillListItem.fromJson(Map<String, dynamic> json) {
    return BillListItem(
      billNumber: json['bill_number'] ?? '',
      shopId: json['shop_id'] ?? '',
      shopName: json['shop_name'] ?? '',
      shopCity: json['shop_city'] ?? '',
      shopGstin: json['shop_gstin']?.toString(),
      shopAddress: json['shop_address']?.toString(),
      shopState: json['shop_state']?.toString(),
      shopPhone: json['shop_phone']?.toString(),
      vehicleNumber: json['vehicle_number']?.toString(),
      transactionDate: json['transaction_date'] ?? '',
      createdAt: json['created_at'] ?? '',
      dispatchedByName: json['dispatched_by_name'] ?? '',
      deliveryReference: json['delivery_reference'],
      remarks: json['remarks'],
      totalUnits: json['total_units'] ?? 0,
      totalBatches: json['total_batches'] ?? 0,
      isCancelled: json['is_cancelled'] ?? false,
      cancelledAt: json['cancelled_at'],
      cancelledByName: json['cancelled_by_name'],
      cancelReason: json['cancel_reason'],
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
  final bool isCancelled;

  BillLine({
    required this.id,
    required this.serialText,
    required this.isMatched,
    required this.isFlagged,
    this.unitType,
    required this.statusLabel,
    this.isCancelled = false,
  });

  factory BillLine.fromJson(Map<String, dynamic> json) {
    return BillLine(
      id: json['id'] ?? '',
      serialText: json['serial_text'] ?? '',
      isMatched: json['is_matched'] ?? false,
      isFlagged: json['is_flagged_for_review'] ?? false,
      unitType: json['unit_type'],
      statusLabel: json['status_label'] ?? 'Recorded only',
      isCancelled: json['is_cancelled'] ?? false,
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
  final bool isCancelled;
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
    this.isCancelled = false,
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
      isCancelled: json['is_cancelled'] ?? false,
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
  final String? shopGstin;
  final String? shopAddress;
  final String? shopState;
  final String? shopPincode;
  final String? shopPhone;
  final String? shopContactPerson;
  final String? vehicleNumber;
  final String? transporterName;
  final String? deliveryNote;
  final String? destination;
  final String transactionDate;
  final String createdAt;
  final String dispatchedByName;
  final String? deliveryReference;
  final String? remarks;
  final int totalUnits;
  final int totalBatches;
  final bool isCancelled;
  final String? cancelledAt;
  final String? cancelledByName;
  final String? cancelReason;
  final List<BillBatch> batches;

  BillDetail({
    required this.billNumber,
    required this.shopId,
    required this.shopName,
    required this.shopCity,
    this.shopGstin,
    this.shopAddress,
    this.shopState,
    this.shopPincode,
    this.shopPhone,
    this.shopContactPerson,
    this.vehicleNumber,
    this.transporterName,
    this.deliveryNote,
    this.destination,
    required this.transactionDate,
    required this.createdAt,
    required this.dispatchedByName,
    this.deliveryReference,
    this.remarks,
    required this.totalUnits,
    required this.totalBatches,
    this.isCancelled = false,
    this.cancelledAt,
    this.cancelledByName,
    this.cancelReason,
    required this.batches,
  });

  factory BillDetail.fromJson(Map<String, dynamic> json) {
    return BillDetail(
      billNumber: json['bill_number'] ?? '',
      shopId: json['shop_id'] ?? '',
      shopName: json['shop_name'] ?? '',
      shopCity: json['shop_city'] ?? '',
      shopGstin: json['shop_gstin']?.toString(),
      shopAddress: json['shop_address']?.toString(),
      shopState: json['shop_state']?.toString(),
      shopPincode: json['shop_pincode']?.toString(),
      shopPhone: json['shop_phone']?.toString(),
      shopContactPerson: json['shop_contact_person']?.toString(),
      vehicleNumber: json['vehicle_number']?.toString(),
      transporterName: json['transporter_name']?.toString(),
      deliveryNote: json['delivery_note']?.toString(),
      destination: json['destination']?.toString(),
      transactionDate: json['transaction_date'] ?? '',
      createdAt: json['created_at'] ?? '',
      dispatchedByName: json['dispatched_by_name'] ?? '',
      deliveryReference: json['delivery_reference'],
      remarks: json['remarks'],
      totalUnits: json['total_units'] ?? 0,
      totalBatches: json['total_batches'] ?? 0,
      isCancelled: json['is_cancelled'] ?? false,
      cancelledAt: json['cancelled_at'],
      cancelledByName: json['cancelled_by_name'],
      cancelReason: json['cancel_reason'],
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

// ─── TALLY INTEGRATION ───────────────────────────────────────────────────────

class TallyVoucherItem {
  final String id;
  final String voucherId;
  final String itemName;
  final String? itemCode;
  final String? productId;
  final double quantity;
  final String? uom;
  final String? rawQtyText;
  final String? godownName;
  final String? batchName;
  final Map<String, dynamic>? batchDetails;
  final String? matchedProductName;
  final String? matchedProductModel;

  TallyVoucherItem({
    required this.id,
    required this.voucherId,
    required this.itemName,
    this.itemCode,
    this.productId,
    required this.quantity,
    this.uom,
    this.rawQtyText,
    this.godownName,
    this.batchName,
    this.batchDetails,
    this.matchedProductName,
    this.matchedProductModel,
  });

  factory TallyVoucherItem.fromJson(Map<String, dynamic> json) {
    return TallyVoucherItem(
      id: json['id'] ?? '',
      voucherId: json['voucher_id'] ?? '',
      itemName: json['item_name'] ?? '',
      itemCode: json['item_code'],
      productId: json['product_id'],
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      uom: json['uom'],
      rawQtyText: json['raw_qty_text'],
      godownName: json['godown_name'],
      batchName: json['batch_name'],
      batchDetails: json['batch_details'] as Map<String, dynamic>?,
      matchedProductName: json['matched_product_name'],
      matchedProductModel: json['matched_product_model'],
    );
  }
}

class TallySalesVoucher {
  final String id;
  final String guid;
  final int? alterId;
  final String voucherNumber;
  final String voucherDate;
  final String voucherType;
  final String partyName;
  final String? partyLedgerName;
  final String? buyerName;
  final String? address;
  final String? stateName;
  final String? companyName;
  final String? shopId;
  final String? vehicleNumber;
  final String? transporterName;
  final String? deliveryNote;
  final String? destination;
  final bool isCancelled;
  final bool isDeleted;
  final bool isProcessed;
  final String? processedAt;
  final int itemCount;
  final double totalQuantity;
  final List<String> godowns;
  final List<TallyVoucherItem> items;
  final String? notes;

  TallySalesVoucher({
    required this.id,
    required this.guid,
    this.alterId,
    required this.voucherNumber,
    required this.voucherDate,
    required this.voucherType,
    required this.partyName,
    this.partyLedgerName,
    this.buyerName,
    this.address,
    this.stateName,
    this.companyName,
    this.shopId,
    this.vehicleNumber,
    this.transporterName,
    this.deliveryNote,
    this.destination,
    required this.isCancelled,
    required this.isDeleted,
    required this.isProcessed,
    this.processedAt,
    required this.itemCount,
    required this.totalQuantity,
    required this.godowns,
    this.items = const [],
    this.notes,
  });

  factory TallySalesVoucher.fromJson(Map<String, dynamic> json) {
    final itms = (json['items'] as List<dynamic>? ?? [])
        .map((e) => TallyVoucherItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final gds = (json['godowns'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();

    return TallySalesVoucher(
      id: json['id'] ?? '',
      guid: json['guid'] ?? '',
      alterId: json['alter_id'],
      voucherNumber: json['voucher_number'] ?? '',
      voucherDate: json['voucher_date'] ?? '',
      voucherType: json['voucher_type'] ?? 'Sales',
      partyName: json['party_name'] ?? '',
      partyLedgerName: json['party_ledger_name'],
      buyerName: json['buyer_name'],
      address: json['address'],
      stateName: json['state_name'],
      companyName: json['company_name'],
      shopId: json['shop_id']?.toString(),
      vehicleNumber: json['vehicle_number']?.toString(),
      transporterName: json['transporter_name']?.toString(),
      deliveryNote: json['delivery_note']?.toString(),
      destination: json['destination']?.toString(),
      isCancelled: json['is_cancelled'] ?? false,
      isDeleted: json['is_deleted'] ?? false,
      isProcessed: json['is_processed'] ?? false,
      processedAt: json['processed_at'],
      itemCount: json['item_count'] ?? itms.length,
      totalQuantity: (json['total_quantity'] as num?)?.toDouble() ?? 0.0,
      godowns: gds,
      items: itms,
      notes: json['notes'],
    );
  }
}

class TallyStatus {
  final bool isConnected;
  final String host;
  final int port;
  final String? tallyUrl;
  final String? activeCompany;
  final bool isEnabled;
  final bool autoSync;
  final int syncIntervalMinutes;
  final String? lastSyncAt;
  final String? lastSyncStatus;
  final String? lastSyncMessage;
  final int lastAlterId;
  final List<String> availableCompanies;
  final int totalVouchers;
  final int pendingVouchers;
  final bool isSyncing;

  TallyStatus({
    required this.isConnected,
    required this.host,
    required this.port,
    this.tallyUrl,
    this.activeCompany,
    required this.isEnabled,
    required this.autoSync,
    required this.syncIntervalMinutes,
    this.lastSyncAt,
    this.lastSyncStatus,
    this.lastSyncMessage,
    required this.lastAlterId,
    required this.availableCompanies,
    required this.totalVouchers,
    required this.pendingVouchers,
    required this.isSyncing,
  });

  factory TallyStatus.fromJson(Map<String, dynamic> json) {
    return TallyStatus(
      isConnected: json['is_connected'] ?? false,
      host: json['host'] ?? 'localhost',
      port: json['port'] ?? 9000,
      tallyUrl: json['tally_url'],
      activeCompany: json['active_company'],
      isEnabled: json['is_enabled'] ?? true,
      autoSync: json['auto_sync'] ?? true,
      syncIntervalMinutes: json['sync_interval_minutes'] ?? 1,
      lastSyncAt: json['last_sync_at'],
      lastSyncStatus: json['last_sync_status'],
      lastSyncMessage: json['last_sync_message'],
      lastAlterId: json['last_alter_id'] ?? 0,
      availableCompanies: (json['available_companies'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      totalVouchers: json['total_vouchers'] ?? 0,
      pendingVouchers: json['pending_vouchers'] ?? 0,
      isSyncing: json['is_syncing'] ?? false,
    );
  }
}
