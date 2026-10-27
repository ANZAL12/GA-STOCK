import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'responsive_utils.dart';

/// Shows a dialog or modal sheet to add a new Product Model.
/// Returns the newly created [Product], or `null` if cancelled.
Future<Product?> showAddProductDialog(
  BuildContext context, {
  String? initialModel,
  String? initialBrand,
}) {
  return showDialog<Product>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AddProductDialog(
      initialModel: initialModel,
      initialBrand: initialBrand,
    ),
  );
}

class AddProductDialog extends StatefulWidget {
  final String? initialModel;
  final String? initialBrand;

  const AddProductDialog({
    super.key,
    this.initialModel,
    this.initialBrand,
  });

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final ApiService _api = ApiService();

  late final TextEditingController _brandController;
  late final TextEditingController _modelController;
  late final TextEditingController _sizeController;
  late final TextEditingController _skuController;

  List<Category> _categories = [];
  Category? _selectedCategory;
  bool _loadingCategories = true;

  bool _isSubmitting = false;
  String? _errorMessage;

  static const List<String> _popularBrands = [
    'Voltas',
    'Daikin',
    'Godrej',
    'LG',
    'Blue Star',
    'Samsung',
    'Lloyd',
    'Carrier',
    'Panasonic',
    'Whirlpool',
    'Haier',
    'IFB',
  ];

  @override
  void initState() {
    super.initState();
    _brandController = TextEditingController(text: widget.initialBrand ?? '');
    _modelController = TextEditingController(text: widget.initialModel ?? '');
    _sizeController = TextEditingController();
    _skuController = TextEditingController();
    _loadCategories();
  }

  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    _sizeController.dispose();
    _skuController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final list = await _api.getCategories();
      if (mounted) {
        setState(() {
          _categories = list;
          if (list.isNotEmpty) {
            _selectedCategory = list.first;
          }
          _loadingCategories = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingCategories = false);
      }
    }
  }

  Future<void> _quickCreateCategory() async {
    final nameCtrl = TextEditingController();
    bool dualSerial = false;

    final created = await showDialog<Category>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('New Category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Category Name',
                  hintText: 'e.g. Microwave, Air Cooler',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dual Serial (Indoor / Outdoor)', style: TextStyle(fontSize: 13)),
                value: dualSerial,
                onChanged: (v) => setDialogState(() => dualSerial = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                try {
                  final cat = await _api.createCategory(name: name, hasDualSerial: dualSerial);
                  if (ctx.mounted) Navigator.pop(ctx, cat);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Add Category'),
            ),
          ],
        ),
      ),
    );

    if (created != null && mounted) {
      setState(() {
        _categories.add(created);
        _selectedCategory = created;
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCategory == null) {
      setState(() => _errorMessage = 'Please select a product category.');
      return;
    }

    final brand = _brandController.text.trim();
    final model = _modelController.text.trim();
    final size = _sizeController.text.trim();
    final sku = _skuController.text.trim();

    setState(() => _isSubmitting = true);

    try {
      final newProduct = await _api.createProduct(
        brand: brand,
        model: model,
        categoryId: _selectedCategory!.id,
        sizeCapacity: size.isNotEmpty ? size : null,
        sku: sku.isNotEmpty ? sku : null,
      );

      if (!mounted) return;
      Navigator.of(context).pop(newProduct);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = context.isTablet;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isTablet ? 80 : 18,
        vertical: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isTablet ? 540 : 420,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(isTablet ? 24 : 18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isTablet ? 24 : 18),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Banner
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF3C3489), Color(0xFF4F46E5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.add_shopping_cart_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Add Product Model',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Register a new appliance model for inward & outward',
                                  style: TextStyle(
                                    color: Color(0xFFC7D2FE),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),

                    // Body
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_errorMessage != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFFCA5A5)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // Category Dropdown
                            const Text(
                              'CATEGORY *',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF64748B),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (_loadingCategories)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                              )
                            else
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<Category>(
                                          value: _selectedCategory,
                                          isExpanded: true,
                                          hint: const Text('Select Category', style: TextStyle(fontSize: 13)),
                                          items: _categories.map((c) {
                                            return DropdownMenuItem<Category>(
                                              value: c,
                                              child: Text(
                                                c.hasDualSerial ? '${c.name} (Dual Unit)' : c.name,
                                                style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (cat) => setState(() => _selectedCategory = cat),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filledTonal(
                                    tooltip: 'New Category',
                                    icon: const Icon(Icons.add, size: 18),
                                    style: IconButton.styleFrom(
                                      backgroundColor: const Color(0xFFEEF2FF),
                                      foregroundColor: const Color(0xFF4F46E5),
                                    ),
                                    onPressed: _quickCreateCategory,
                                  ),
                                ],
                              ),
                            const SizedBox(height: 14),

                            // Brand Field & Quick Chips
                            const Text(
                              'BRAND *',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF64748B),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _brandController,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'e.g. Voltas, Daikin, LG',
                                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Brand name is required';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 6),
                            // Quick brand selection chips
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: _popularBrands.take(7).map((b) {
                                  final isSelected = _brandController.text.trim().toLowerCase() == b.toLowerCase();
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ActionChip(
                                      label: Text(b, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : const Color(0xFF475569))),
                                      backgroundColor: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
                                      side: BorderSide(color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0)),
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => setState(() => _brandController.text = b),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Model Number / Name
                            const Text(
                              'MODEL NUMBER / SPECIFICATION *',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF64748B),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _modelController,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'e.g. 183V CZR, GL-B201ABPD',
                                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Model number is required';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),

                            // Optional Size / Capacity & SKU row
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'CAPACITY / SIZE',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                      ),
                                      const SizedBox(height: 6),
                                      TextFormField(
                                        controller: _sizeController,
                                        style: const TextStyle(fontSize: 13),
                                        decoration: InputDecoration(
                                          hintText: 'e.g. 1.5 Ton, 260L',
                                          hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'SKU (OPTIONAL)',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                      ),
                                      const SizedBox(height: 6),
                                      TextFormField(
                                        controller: _skuController,
                                        style: const TextStyle(fontSize: 13),
                                        decoration: InputDecoration(
                                          hintText: 'e.g. VOL-183V',
                                          hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                                    ),
                                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                                    child: const Text('Cancel', style: TextStyle(color: Color(0xFF475569))),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      backgroundColor: const Color(0xFF4F46E5),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: _isSubmitting ? null : _submit,
                                    child: _isSubmitting
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                          )
                                        : const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.check_rounded, size: 18),
                                              SizedBox(width: 6),
                                              Text('Save Model', style: TextStyle(fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
