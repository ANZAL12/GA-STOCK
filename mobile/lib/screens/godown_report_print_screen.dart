import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../widgets/responsive_utils.dart';
import '../widgets/top_toast.dart';

class GodownReportPrintScreen extends StatefulWidget {
  const GodownReportPrintScreen({super.key});

  @override
  State<GodownReportPrintScreen> createState() => _GodownReportPrintScreenState();
}

class _GodownReportPrintScreenState extends State<GodownReportPrintScreen> {
  final ApiService _api = ApiService();

  // Office PC Printers State
  bool _loadingPrinters = true;
  String? _printerError;
  List<Map<String, dynamic>> _printers = [];
  String? _selectedPrinter;

  // Selected Report Options
  String _selectedReportType = 'stock_by_model';
  Product? _selectedProduct;
  Shop? _selectedShop;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  // Filter Data
  List<Product> _products = [];
  List<Shop> _shops = [];

  // Printing State
  bool _isPrinting = false;
  String? _lastPrintSuccessMessage;

  @override
  void initState() {
    super.initState();
    _fetchPrinters();
    _loadFilterCatalogs();
  }

  Future<void> _fetchPrinters() async {
    setState(() {
      _loadingPrinters = true;
      _printerError = null;
    });

    try {
      final res = await _api.getOfficePrinters();
      final List rawPrinters = res['printers'] ?? [];
      final printers = rawPrinters.map((p) => Map<String, dynamic>.from(p as Map)).toList();
      final def = res['default_printer'] as String?;

      if (mounted) {
        setState(() {
          _printers = printers;
          _selectedPrinter = def ?? (printers.isNotEmpty ? printers.first['name'] as String? : null);
          _loadingPrinters = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _printerError = e.toString().replaceAll('Exception: ', '');
          _loadingPrinters = false;
        });
      }
    }
  }

  Future<void> _loadFilterCatalogs() async {
    try {
      final prods = await _api.getProducts();
      final shops = await _api.getShops();
      if (mounted) {
        setState(() {
          _products = prods;
          _shops = shops;
        });
      }
    } catch (_) {}
  }

  Future<void> _handlePrintReport() async {
    if (_printers.isEmpty && _printerError != null) {
      TopToast.show(
        context,
        message: 'Cannot print: Office PC printer is unreachable. Check Tailscale VPN.',
        backgroundColor: const Color(0xFFEF4444),
        icon: Icons.error_outline_rounded,
      );
      return;
    }

    setState(() {
      _isPrinting = true;
      _lastPrintSuccessMessage = null;
    });

    try {
      final res = await _api.printGodownReport(
        reportType: _selectedReportType,
        printerName: _selectedPrinter,
        productId: _selectedProduct?.id,
        shopId: _selectedShop?.id,
        dateFrom: _dateFrom?.toIso8601String().split('T').first,
        dateTo: _dateTo?.toIso8601String().split('T').first,
      );

      final msg = res['message'] ?? 'Print job submitted successfully to Office PC!';
      if (mounted) {
        setState(() {
          _isPrinting = false;
          _lastPrintSuccessMessage = msg;
        });
        TopToast.show(context, message: msg);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPrinting = false);
        TopToast.show(
          context,
          message: 'Print Failed: ${e.toString().replaceAll('Exception: ', '')}',
          backgroundColor: const Color(0xFFEF4444),
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = context.isTablet;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: isTablet ? 68 : 56,
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Godown Report Print Server',
          style: TextStyle(
            color: const Color(0xFF0F172A),
            fontSize: isTablet ? 19 : 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        actions: [
          IconButton(
            tooltip: 'Refresh Printers',
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF3C3489)),
            onPressed: _loadingPrinters ? null : _fetchPrinters,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isTablet ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── OFFICE PC PRINTER STATUS CARD ──────────────────────────────
            _buildOfficePrinterStatusCard(isTablet),
            const SizedBox(height: 18),

            // ── REPORT TYPE SELECTOR ───────────────────────────────────────
            _buildSectionHeader('Select Godown Report', Icons.description_outlined),
            const SizedBox(height: 10),
            _buildReportTypeSelector(isTablet),
            const SizedBox(height: 18),

            // ── OPTIONAL FILTERS ───────────────────────────────────────────
            if (_selectedReportType == 'stock_by_model' || _selectedReportType == 'stock_out') ...[
              _buildSectionHeader('Report Filters (Optional)', Icons.filter_list_rounded),
              const SizedBox(height: 10),
              _buildFilterSection(isTablet),
              const SizedBox(height: 20),
            ],

            // ── LAST PRINT FEEDBACK ────────────────────────────────────────
            if (_lastPrintSuccessMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _lastPrintSuccessMessage!,
                        style: const TextStyle(
                          color: Color(0xFF065F46),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            // ── ACTION BUTTONS ─────────────────────────────────────────────
            ElevatedButton.icon(
              onPressed: _isPrinting ? null : _handlePrintReport,
              icon: _isPrinting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.print_rounded, size: 20),
              label: Text(
                _isPrinting ? 'Sending to Office PC...' : 'Print on Office PC Printer',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3C3489),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: isTablet ? 18 : 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PRINTER STATUS CARD ───────────────────────────────────────────────────
  Widget _buildOfficePrinterStatusCard(bool isTablet) {
    return Container(
      padding: EdgeInsets.all(isTablet ? 18 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.print, color: Color(0xFF3C3489), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Office PC Print Server',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _printerError == null ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _printerError == null
                              ? 'Connected via Tailscale'
                              : 'Offline / Unreachable',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _printerError == null ? const Color(0xFF059669) : const Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_loadingPrinters)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3C3489)),
                ),
            ],
          ),
          const SizedBox(height: 14),

          if (_printerError != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _printerError!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
              ),
            )
          else ...[
            const Text(
              'Target Office Printer:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedPrinter,
                  hint: const Text('Select Printer', style: TextStyle(fontSize: 13)),
                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF3C3489)),
                  items: _printers.map((p) {
                    final name = p['name'] as String? ?? 'Printer';
                    final isDef = p['is_default'] == true;
                    return DropdownMenuItem<String>(
                      value: name,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isDef)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'DEFAULT',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF3C3489)),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedPrinter = val);
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── REPORT TYPE SELECTOR ──────────────────────────────────────────────────
  Widget _buildReportTypeSelector(bool isTablet) {
    final reports = [
      {
        'id': 'stock_by_model',
        'title': 'Stock by Model Report',
        'subtitle': 'Available stock, dispatches, damaged, and negative alert counts',
        'icon': Icons.inventory_2_outlined,
        'color': const Color(0xFF3C3489),
      },
      {
        'id': 'stock_out',
        'title': 'Stock Out Dispatch Report',
        'subtitle': 'All dispatches with shop, delivery ref, and match status',
        'icon': Icons.local_shipping_outlined,
        'color': const Color(0xFFD97706),
      },
      {
        'id': 'today_summary',
        'title': "Today's Operations Summary",
        'subtitle': "Concise log of today's inward batches and outward shop deliveries",
        'icon': Icons.today_rounded,
        'color': const Color(0xFF059669),
      },
      {
        'id': 'unmatched_outward',
        'title': 'Unmatched Outward Report',
        'subtitle': 'Pre-go-live stock dispatches (scanned out without inward record)',
        'icon': Icons.warning_amber_rounded,
        'color': const Color(0xFFEA580C),
      },
      {
        'id': 'damaged',
        'title': 'Damaged & Under Repair Report',
        'subtitle': 'Units flagged as damaged or under-repair awaiting action',
        'icon': Icons.build_circle_outlined,
        'color': const Color(0xFFE11D48),
      },
    ];

    return Column(
      children: reports.map((r) {
        final id = r['id'] as String;
        final isSelected = _selectedReportType == id;
        final color = r['color'] as Color;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => setState(() => _selectedReportType = id),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? color : const Color(0xFFE2E8F0),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))]
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(r['icon'] as IconData, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r['title'] as String,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? color : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r['subtitle'] as String,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: isSelected ? color : const Color(0xFF94A3B8),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── FILTER SECTION ────────────────────────────────────────────────────────
  Widget _buildFilterSection(bool isTablet) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          if (_selectedReportType == 'stock_by_model') ...[
            DropdownButtonFormField<Product?>(
              initialValue: _selectedProduct,
              decoration: const InputDecoration(
                labelText: 'Filter by Specific Model',
                labelStyle: TextStyle(fontSize: 12),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<Product?>(
                  value: null,
                  child: Text('All Models in Godown', style: TextStyle(fontSize: 13)),
                ),
                ..._products.map((p) => DropdownMenuItem<Product?>(
                      value: p,
                      child: Text('${p.brand} ${p.model}', style: const TextStyle(fontSize: 13)),
                    )),
              ],
              onChanged: (p) => setState(() => _selectedProduct = p),
            ),
          ],
          if (_selectedReportType == 'stock_out') ...[
            DropdownButtonFormField<Shop?>(
              initialValue: _selectedShop,
              decoration: const InputDecoration(
                labelText: 'Filter by Shop',
                labelStyle: TextStyle(fontSize: 12),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<Shop?>(
                  value: null,
                  child: Text('All Shops', style: TextStyle(fontSize: 13)),
                ),
                ..._shops.map((s) => DropdownMenuItem<Shop?>(
                      value: s,
                      child: Text('${s.name} (${s.city})', style: const TextStyle(fontSize: 13)),
                    )),
              ],
              onChanged: (s) => setState(() => _selectedShop = s),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF334155),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
