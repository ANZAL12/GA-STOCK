import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/offline_manager.dart';
import 'responsive_utils.dart';
import 'uppercase_formatter.dart';

/// Shows a dialog or modal sheet to add a new shop with only shop name.
/// Returns the newly created [Shop], or `null` if cancelled.
Future<Shop?> showAddShopDialog(
  BuildContext context, {
  String? initialName,
}) {
  return showDialog<Shop>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AddShopDialog(initialName: initialName),
  );
}

class AddShopDialog extends StatefulWidget {
  final String? initialName;

  const AddShopDialog({super.key, this.initialName});

  @override
  State<AddShopDialog> createState() => _AddShopDialogState();
}

class _AddShopDialogState extends State<AddShopDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: (widget.initialName ?? '').toUpperCase());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final name = _nameController.text.trim().toUpperCase();

    setState(() => _isSubmitting = true);

    try {
      final newShop = await ApiService().createShop(
        name: name,
      );

      if (!mounted) return;

      Navigator.of(context).pop(newShop);
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
        horizontal: isTablet ? 80 : 20,
        vertical: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isTablet ? 520 : 400,
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
              child: Form(
                key: _formKey,
                child: Padding(
                  padding: EdgeInsets.all(isTablet ? 28 : 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: isTablet ? 48 : 40,
                            height: isTablet ? 48 : 40,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F9FF),
                              borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
                              border: Border.all(color: const Color(0xFFBAE6FD)),
                            ),
                            child: Image.asset(
                              'assets/images/shop_icon.png',
                              fit: BoxFit.contain,
                              errorBuilder: (ctx, err, stack) => const Center(
                                child: Text('🏪', style: TextStyle(fontSize: 18)),
                              ),
                            ),
                          ),
                          SizedBox(width: isTablet ? 14 : 10),
                          Expanded(
                            child: Text(
                              'Add New Shop',
                              style: TextStyle(
                                fontSize: isTablet ? 19 : 17,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                            splashRadius: 20,
                          ),
                        ],
                      ),

                      if (!OfflineManager().isOnline) ...[
                        SizedBox(height: isTablet ? 14 : 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFCD34D)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.wifi_off_rounded, size: 14, color: Color(0xFF92400E)),
                              SizedBox(width: 6),
                              Text(
                                'Offline Ready (Will Sync to server on reconnect)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (_errorMessage != null) ...[
                        SizedBox(height: isTablet ? 16 : 12),
                        Container(
                          padding: EdgeInsets.all(isTablet ? 12 : 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              fontSize: isTablet ? 13 : 12,
                              color: const Color(0xFF991B1B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],

                      SizedBox(height: isTablet ? 22 : 18),

                      // Shop Name Input Only
                      Text(
                        'Shop Name',
                        style: TextStyle(
                          fontSize: isTablet ? 14 : 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        autofocus: true,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: const [UpperCaseTextFormatter()],
                        style: TextStyle(
                          fontSize: isTablet ? 16 : 14,
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter shop name',
                          hintStyle: TextStyle(
                            fontSize: isTablet ? 14 : 13,
                            color: const Color(0xFF94A3B8),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: isTablet ? 16 : 13,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.8),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFEF4444)),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.8),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter shop name';
                          }
                          if (val.trim().length > 255) {
                            return 'Shop name is too long';
                          }
                          return null;
                        },
                      ),

                      SizedBox(height: isTablet ? 26 : 20),

                      // Actions
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(
                                  vertical: isTablet ? 16 : 13,
                                ),
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: isTablet ? 15 : 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: isTablet ? 14 : 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: EdgeInsets.symmetric(
                                  vertical: isTablet ? 16 : 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _isSubmitting ? null : _submit,
                              child: _isSubmitting
                                  ? SizedBox(
                                      width: isTablet ? 22 : 18,
                                      height: isTablet ? 22 : 18,
                                      child: const CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : Text(
                                      'Add Shop',
                                      style: TextStyle(
                                        fontSize: isTablet ? 15 : 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
