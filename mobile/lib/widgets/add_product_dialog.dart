import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/offline_manager.dart';
import 'responsive_utils.dart';
import 'uppercase_formatter.dart';

/// Shows a dialog to add a new Product Model matching the Master Product Catalog.
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
  late final TextEditingController _openingStockController;
  late final TextEditingController _descriptionController;

  List<Category> _categories = [];
  Category? _selectedCategory;
  bool _loadingCategories = true;

  List<String> _previouslyAddedBrands = [];
  bool _loadingBrands = true;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _brandController = TextEditingController(text: (widget.initialBrand ?? '').toUpperCase());
    _modelController = TextEditingController(text: (widget.initialModel ?? '').toUpperCase());
    _openingStockController = TextEditingController(text: '0');
    _descriptionController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    _openingStockController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadCategories(),
      _loadBrands(),
    ]);
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

  Future<void> _loadBrands() async {
    try {
      final list = await _api.getBrands();
      if (mounted) {
        setState(() {
          _previouslyAddedBrands = list;
          _loadingBrands = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingBrands = false);
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
                textCapitalization: TextCapitalization.characters,
                inputFormatters: const [UpperCaseTextFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Category Name',
                  hintText: 'e.g. MICROWAVE, AIR COOLER',
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
                backgroundColor: const Color(0xFF3C3489),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim().toUpperCase();
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

    final brand = _brandController.text.trim().toUpperCase();
    final model = _modelController.text.trim().toUpperCase();
    final openingStock = int.tryParse(_openingStockController.text.trim()) ?? 0;
    final description = _descriptionController.text.trim();

    setState(() => _isSubmitting = true);

    try {
      final newProduct = await _api.createProduct(
        brand: brand,
        model: model,
        categoryId: _selectedCategory!.id,
        openingStockQty: openingStock,
        description: description.isNotEmpty ? description : null,
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
        vertical: 20,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isTablet ? 560 : 440,
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
                          colors: [Color(0xFF28235C), Color(0xFF3C3489)],
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
                              Icons.post_add_rounded,
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
                                  'Global Logistics Master Product Catalog',
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
                            // Single Model Mode Badge
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3C3489),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'Single Model',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (!OfflineManager().isOnline) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFFDE68A)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.cloud_off_rounded, size: 14, color: Color(0xFFB45309)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Offline Ready (Will Sync)',
                                          style: TextStyle(
                                            color: Color(0xFFB45309),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 16),

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

                            // BRAND NAME *
                            const Text(
                              'BRAND NAME *',
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
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: const [UpperCaseTextFormatter()],
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'e.g. SAMSUNG, LG, IFB',
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

                            // Dynamic recommended brands fetched from previously added products
                            const SizedBox(height: 6),
                            if (_loadingBrands)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4),
                                child: Text('Loading brand suggestions...', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                              )
                            else if (_previouslyAddedBrands.isNotEmpty)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'PREVIOUSLY ADDED BRANDS:',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF94A3B8),
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: _previouslyAddedBrands.map((b) {
                                        final isSelected = _brandController.text.trim().toLowerCase() == b.toLowerCase();
                                        return Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: ActionChip(
                                            label: Text(
                                              b,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                color: isSelected ? Colors.white : const Color(0xFF334155),
                                              ),
                                            ),
                                            backgroundColor: isSelected ? const Color(0xFF3C3489) : const Color(0xFFF1F5F9),
                                            side: BorderSide(
                                              color: isSelected ? const Color(0xFF3C3489) : const Color(0xFFE2E8F0),
                                            ),
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            visualDensity: VisualDensity.compact,
                                            onPressed: () {
                                              setState(() {
                                                _brandController.text = b.toUpperCase();
                                              });
                                            },
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),

                            const SizedBox(height: 14),

                            // CATEGORY * with + New Category Button
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'CATEGORY *',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF64748B),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                InkWell(
                                  onTap: _quickCreateCategory,
                                  borderRadius: BorderRadius.circular(6),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.add, size: 13, color: Color(0xFF3C3489)),
                                        SizedBox(width: 2),
                                        Text(
                                          'New Category',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF3C3489),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (_loadingCategories)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
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

                            const SizedBox(height: 14),

                            // MODEL NUMBER *
                            const Text(
                              'MODEL NUMBER *',
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
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: const [UpperCaseTextFormatter()],
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'e.g. UA43T5350',
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

                            // OLD STOCK NUMBER (OPENING QTY)
                            const Text(
                              'OLD STOCK NUMBER (OPENING QTY)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF64748B),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _openingStockController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '0',
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
                                if (val != null && val.trim().isNotEmpty) {
                                  final num = int.tryParse(val.trim());
                                  if (num == null || num < 0) {
                                    return 'Please enter a valid non-negative number';
                                  }
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 14),

                            // DESCRIPTION / REMARKS
                            const Text(
                              'DESCRIPTION / REMARKS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF64748B),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _descriptionController,
                              maxLines: 3,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Optional notes or warranty details...',
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
                            ),

                            const SizedBox(height: 22),

                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 13),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                                    ),
                                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                                    child: const Text('Cancel', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w600)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 13),
                                      backgroundColor: const Color(0xFF3C3489),
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
                                        : const Text('Save Product', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
