import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/offline_manager.dart';

/// The 6 supported brands specified for GA STOCK model identification.
const List<String> kSupportedTallyBrands = [
  'GENERAL',
  'HAIER',
  'FORMENTY',
  'CARRIER',
  'ROCKWELL',
  'MIDEA',
];

class BrandSelectionDialog extends StatefulWidget {
  final TallyVoucherItem item;
  final ApiService api;

  const BrandSelectionDialog({
    super.key,
    required this.item,
    required this.api,
  });

  /// Displays the brand selection dialog and returns the updated [Product] if a brand was assigned.
  static Future<Product?> show(
    BuildContext context, {
    required TallyVoucherItem item,
    required ApiService api,
  }) {
    return showDialog<Product>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BrandSelectionDialog(item: item, api: api),
    );
  }

  @override
  State<BrandSelectionDialog> createState() => _BrandSelectionDialogState();
}

class _BrandSelectionDialogState extends State<BrandSelectionDialog> {
  String? _selectedBrand;
  bool _isDualUnit = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Intelligent default suggestion for single vs dual unit:
    final nameU = widget.item.itemName.trim().toUpperCase();
    final hasAcHint = nameU.contains('AC') ||
        nameU.contains('SPLIT') ||
        nameU.contains('INVERTER') ||
        nameU.contains('AIR CONDITION') ||
        RegExp(r'^(ASGA|ASGG|AOGA|AOGG|AUG|AOG|ASG|12K|18K|24K|CAI|CAS)').hasMatch(nameU);
    final isNonAcHint = nameU.contains('TV') ||
        nameU.contains('LED') ||
        nameU.contains('BLENDER') ||
        nameU.contains('WASHING') ||
        nameU.contains('WM ') ||
        nameU.contains('W/M') ||
        nameU.contains('REF') ||
        nameU.contains('STAND') ||
        nameU.contains('FREEZER');

    _isDualUnit = hasAcHint && !isNonAcHint;
  }

  Future<void> _submit() async {
    if (_selectedBrand == null) {
      setState(() {
        _errorMessage = 'Please select a brand.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final updatedProduct = await widget.api.assignProductBrand(
        brand: _selectedBrand!,
        hasDualSerial: _isDualUnit,
        productId: widget.item.productId,
        voucherItemId: widget.item.id.isNotEmpty ? widget.item.id : null,
        itemName: widget.item.itemName,
      );

      if (mounted) {
        Navigator.of(context).pop(updatedProduct);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSaving,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 16,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.branding_watermark_rounded,
                        color: Color(0xFF7E22CE),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'New Model Detected',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Choose brand and unit type for scanning',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Item details banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          const Text(
                            'ITEM FROM TALLY BILL',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E7FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Qty: ${widget.item.quantity.toInt()} ${widget.item.uom ?? "NOS"}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF3730A3),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.item.itemName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Step 1: Select Brand
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: Color(0xFF7E22CE),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          '1',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Select Brand',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 6 Brand Cards Grid
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kSupportedTallyBrands.map((brand) {
                    final isCurrentSelected = _selectedBrand == brand;

                    return SizedBox(
                      width: (MediaQuery.of(context).size.width > 420 ? 136 : 100),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isSaving
                              ? null
                              : () {
                                  setState(() {
                                    _selectedBrand = brand;
                                    _errorMessage = null;
                                  });
                                },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              color: isCurrentSelected
                                  ? const Color(0xFFF3E8FF)
                                  : const Color(0xFFFFFFFF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isCurrentSelected
                                    ? const Color(0xFF7E22CE)
                                    : const Color(0xFFCBD5E1),
                                width: isCurrentSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isCurrentSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  size: 16,
                                  color: isCurrentSelected
                                      ? const Color(0xFF7E22CE)
                                      : const Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    brand,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: isCurrentSelected ? FontWeight.bold : FontWeight.w600,
                                      color: isCurrentSelected
                                          ? const Color(0xFF7E22CE)
                                          : const Color(0xFF1E293B),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 18),

                // Step 2: Select Unit Type (Single vs Dual)
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: Color(0xFF7E22CE),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          '2',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Select Unit Type',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Two option cards: Single Unit vs Dual Unit
                Row(
                  children: [
                    // Single Unit Card
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isSaving ? null : () => setState(() => _isDualUnit = false),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: !_isDualUnit
                                  ? const Color(0xFFEFF6FF)
                                  : const Color(0xFFFFFFFF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: !_isDualUnit
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFFCBD5E1),
                                width: !_isDualUnit ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      !_isDualUnit
                                          ? Icons.radio_button_checked_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      size: 18,
                                      color: !_isDualUnit
                                          ? const Color(0xFF2563EB)
                                          : const Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Single Unit',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  '1 Serial per item\n(Window AC, TV, Fridge, Cooler)',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF64748B),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Dual Unit Card
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isSaving ? null : () => setState(() => _isDualUnit = true),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _isDualUnit
                                  ? const Color(0xFFFAF5FF)
                                  : const Color(0xFFFFFFFF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isDualUnit
                                    ? const Color(0xFF7E22CE)
                                    : const Color(0xFFCBD5E1),
                                width: _isDualUnit ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      _isDualUnit
                                          ? Icons.radio_button_checked_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      size: 18,
                                      color: _isDualUnit
                                          ? const Color(0xFF7E22CE)
                                          : const Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Dual Unit',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  '2 Serials per item\n(Indoor + Outdoor Split AC)',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF64748B),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Action buttons: Cancel and Confirm
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(null),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7E22CE),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        _isSaving ? 'Saving...' : 'Confirm & Save',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper class to check voucher items for unconfirmed brands before entering outward scan.
class TallyBrandHelper {
  /// Checks whether an item already has a confirmed recognized brand in GA STOCK DB.
  /// Recognizes: GENERAL, HAIER, FORMENTY, CARRIER, ROCKWELL, MIDEA.
  static bool hasConfirmedDbBrand(TallyVoucherItem item, {List<Product>? products}) {
    // 1. If backend already matched a recognized brand from DB, it is confirmed!
    final itemBrand = (item.matchedProductBrand ?? '').trim().toUpperCase();
    if (kSupportedTallyBrands.contains(itemBrand)) {
      return true;
    }

    // 2. Check against GA STOCK product list (cached, offline, or fetched)
    if (products != null && products.isNotEmpty) {
      final itemClean = item.itemName.trim().toLowerCase();
      final itemCodeClean = (item.itemCode ?? '').trim().toLowerCase();
      final matchedModelClean = (item.matchedProductModel ?? '').trim().toLowerCase();
      final matchedNameClean = (item.matchedProductName ?? '').trim().toLowerCase();
      final itemId = (item.productId ?? '').trim().toLowerCase();

      final matchingProduct = products.where((p) {
        // Match by product ID
        if (itemId.isNotEmpty && !itemId.startsWith('tally_') && p.id.toLowerCase() == itemId) {
          return true;
        }

        final pModel = p.model.trim().toLowerCase();
        final pName = p.name.trim().toLowerCase();

        // Exact match by model or name
        if (pModel.isNotEmpty && (pModel == itemClean || (itemCodeClean.isNotEmpty && pModel == itemCodeClean) || (matchedModelClean.isNotEmpty && pModel == matchedModelClean))) {
          return true;
        }
        if (pName.isNotEmpty && (pName == itemClean || (matchedNameClean.isNotEmpty && pName == matchedNameClean))) {
          return true;
        }

        // Substring / word match: e.g. "GENERAL ASGA24BUTA-B 2T" containing "ASGA24BUTA-B 2T"
        if (itemClean.length >= 4 && (pName.contains(itemClean) || pModel.contains(itemClean))) {
          return true;
        }
        if (pModel.length >= 4 && itemClean.contains(pModel)) {
          return true;
        }

        return false;
      }).firstOrNull;

      if (matchingProduct != null) {
        // Product exists in GA STOCK DB!
        final pBrand = matchingProduct.brand.trim().toUpperCase();
        if (kSupportedTallyBrands.contains(pBrand) || pBrand.isNotEmpty) {
          return true;
        }
      }
    }

    return false;
  }

  /// Iterates through voucher items. If any item does not exist in DB or lacks a confirmed brand,
  /// prompts staff to select the brand and single/dual unit type.
  /// Returns `true` if all items are confirmed, or `false` if cancelled.
  static Future<bool> checkAndPromptBrands({
    required BuildContext context,
    required TallySalesVoucher voucher,
    required ApiService api,
    List<Product>? products,
  }) async {
    // Ensure we have products to check against
    List<Product> prodList = products ?? api.cachedProducts ?? [];
    if (prodList.isEmpty) {
      try {
        prodList = await api.getProducts();
      } catch (_) {
        prodList = OfflineManager().products;
      }
    }

    for (int i = 0; i < voucher.items.length; i++) {
      final item = voucher.items[i];
      if (!hasConfirmedDbBrand(item, products: prodList)) {
        if (!context.mounted) return false;
        // Prompt brand and unit type selection for this unconfirmed model
        final updatedProduct = await BrandSelectionDialog.show(
          context,
          item: item,
          api: api,
        );

        if (updatedProduct == null) {
          // Staff cancelled the dialog
          return false;
        }

        // Update item in voucher with the selected unit type and brand
        voucher.items[i] = item.copyWith(
          hasDualSerial: updatedProduct.hasDualSerial,
          matchedProductBrand: updatedProduct.brand,
          matchedProductName: updatedProduct.name,
          matchedProductModel: updatedProduct.model,
          productId: updatedProduct.id,
          isNewModel: false,
        );

        // Add or update in local products list so subsequent items and outward screen don't re-prompt
        prodList.removeWhere((p) => p.id == updatedProduct.id);
        prodList.add(updatedProduct);
      }
    }

    return true;
  }
}
