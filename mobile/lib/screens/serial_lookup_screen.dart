import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/hardware_scanner_service.dart';
import '../widgets/offline_banner.dart';
import '../widgets/responsive_utils.dart';
import '../widgets/scanner_widget.dart';

class SerialLookupScreen extends StatefulWidget {
  final String? initialSerial;
  const SerialLookupScreen({super.key, this.initialSerial});

  @override
  State<SerialLookupScreen> createState() => _SerialLookupScreenState();
}

class _SerialLookupScreenState extends State<SerialLookupScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  VoidCallback? _scannerSub;

  bool _loading = false;
  SerialLookupDetail? _detail;
  String? _errorMessage;
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    _scannerSub = HardwareScannerService().registerListener((barcode) {
      if (mounted) {
        if (ModalRoute.of(context)?.isCurrent != true) return;
        _lastScanTime = DateTime.now();
        FocusScope.of(context).unfocus();
        _searchController.text = barcode;
        _performLookup(barcode);
      }
    });

    if (widget.initialSerial != null && widget.initialSerial!.isNotEmpty) {
      _searchController.text = widget.initialSerial!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performLookup(widget.initialSerial!);
      });
    }
  }

  @override
  void dispose() {
    _scannerSub?.call();
    _searchController.dispose();
    super.dispose();
  }

  void _openScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerWidget(
          title: 'Lookup Serial Barcode',
          prompt: 'Scan barcode to trace lifecycle',
          onScanned: (serial) {
            Navigator.pop(context);
            _searchController.text = serial;
            _performLookup(serial);
          },
        ),
      ),
    );
  }

  Future<void> _performLookup(String serial) async {
    final cleanSerial = serial.trim();
    if (cleanSerial.isEmpty) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
      _detail = null;
    });

    try {
      final res = await _api.lookupSerial(cleanSerial);
      if (mounted) {
        setState(() {
          _detail = res;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Color _getStatusColor(String? status) {
    if (status == null) return const Color(0xFF64748B);
    switch (status.toLowerCase()) {
      case 'available':
        return const Color(0xFF059669);
      case 'dispatched':
        return const Color(0xFFD97706);
      case 'damaged':
      case 'lost':
        return const Color(0xFFE11D48);
      case 'under_repair':
      case 'returned':
        return const Color(0xFF3C3489);
      default:
        return const Color(0xFF475569);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = context.isTablet;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        // If a barcode scan occurred within the last 2000ms, swallow the pop request
        if (_lastScanTime != null && now.difference(_lastScanTime!).inMilliseconds < 2000) {
          debugPrint('[SerialLookupScreen] Swallowed pop attempt from scanner keys');
          return;
        }
        Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          toolbarHeight: isTablet ? 72 : 56,
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: const Color(0xFF0F172A),
          leading: Focus(
            canRequestFocus: false,
            descendantsAreFocusable: false,
            skipTraversal: true,
            child: IconButton(
              focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          title: Text(
            'Serial Lifecycle Trace',
            style: TextStyle(
              fontSize: isTablet ? 20 : 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      body: Column(
        children: [
          const OfflineBanner(),
          // Search & scan bar
          Container(
            color: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 28 : 16,
              vertical: isTablet ? 18 : 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textCapitalization: TextCapitalization.characters,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          fontSize: isTablet ? 17 : 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Type or scan serial...',
                          hintStyle: TextStyle(fontSize: isTablet ? 15 : 14),
                          prefixIcon: Icon(Icons.search, size: isTablet ? 24 : 20),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 20 : 16,
                            vertical: isTablet ? 18 : 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                            borderSide: const BorderSide(color: Color(0xFF3C3489), width: 1.5),
                          ),
                        ),
                        onSubmitted: (val) {
                          FocusScope.of(context).unfocus();
                          _performLookup(val);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Focus(
                      canRequestFocus: false,
                      descendantsAreFocusable: false,
                      skipTraversal: true,
                      child: IconButton(
                        focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF1E1B4B),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                          ),
                          padding: EdgeInsets.all(isTablet ? 16 : 12),
                        ),
                        icon: Icon(Icons.qr_code_scanner, size: isTablet ? 28 : 22),
                        tooltip: 'Scan Barcode',
                        onPressed: _openScanner,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isTablet ? 10 : 6),
                Row(
                  children: [
                    Container(
                      width: isTablet ? 9 : 7,
                      height: isTablet ? 9 : 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'External Scanner Active: Press trigger on Bluetooth/USB scanner',
                      style: TextStyle(
                        fontSize: isTablet ? 13 : 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Results view
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Color(0xFFE11D48)),
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _detail == null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search, size: 48, color: Colors.grey[300]),
                                const SizedBox(height: 8),
                                const Text(
                                  'Enter or scan a serial number to inspect trace.',
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                ),
                              ],
                            ),
                          )
                        : _buildDetailCard(_detail!),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildDetailCard(SerialLookupDetail d) {
    final statusColor = _getStatusColor(d.status);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Serial summary card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SERIAL NUMBER',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 1),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            d.serialNumber,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        d.statusLabel,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Product Model', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                          const SizedBox(height: 2),
                          Text(
                            d.productName ?? 'Unknown Appliance',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                          ),
                          if (d.brand != null || d.model != null)
                            Text(
                              '${d.brand ?? ''} ${d.model ?? ''}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                        ],
                      ),
                    ),
                    if (d.lastShopName != null)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Last Destination Shop', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                            const SizedBox(height: 2),
                            Text(
                              d.lastShopName!,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                            ),
                            if (d.lastShopCity != null && d.lastShopCity!.trim().isNotEmpty)
                              Text(d.lastShopCity!.trim(), style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const Text(
            'LIFECYCLE TIMELINE',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 12),

          // Vertical timeline list
          if (d.history.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text(
                'No recorded movement events found for this serial.',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: d.history.length,
              itemBuilder: (ctx, idx) {
                final h = d.history[idx];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Timeline indicator
                    Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3C3489),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                        if (idx < d.history.length - 1)
                          Container(
                            width: 2,
                            height: 48,
                            color: const Color(0xFFE2E8F0),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  h.action.replaceAll('_', ' ').toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF1E293B)),
                                ),
                                Text(
                                  h.createdAt.length >= 10 ? h.createdAt.substring(0, 10) : h.createdAt,
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'By ${h.userName}${h.shopName != null ? " • Shop: ${h.shopName}" : ""}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                            if (h.remarks != null) ...[
                              const SizedBox(height: 2),
                              Text('Remarks: ${h.remarks!}', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
