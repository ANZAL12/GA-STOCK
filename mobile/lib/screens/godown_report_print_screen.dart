import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../widgets/responsive_utils.dart';
import '../widgets/top_toast.dart';
import 'godown_report_preview_screen.dart';

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
  String _selectedReportType = 'today_inward_serials';
  Product? _selectedProduct;
  Shop? _selectedShop;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _selectedInwardType;

  // Model Filter Search State
  final TextEditingController _modelSearchController = TextEditingController();
  String _modelSearchQuery = '';

  // Filter Data
  List<Product> _products = [];
  List<Shop> _shops = [];

  // Printing & Preview State
  bool _isPrinting = false;
  bool _isPreviewing = false;
  String? _lastPrintSuccessMessage;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateFrom = now;
    _dateTo = now;
    _fetchPrinters();
    _loadFilterCatalogs();
  }

  @override
  void dispose() {
    _modelSearchController.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
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

  Future<void> _handlePreviewA4Report() async {
    setState(() {
      _isPreviewing = true;
    });

    try {
      final pdfBytes = await _api.previewGodownReport(
        reportType: _selectedReportType,
        productId: _selectedProduct?.id,
        shopId: _selectedShop?.id,
        dateFrom: _dateFrom?.toIso8601String().split('T').first,
        dateTo: _dateTo?.toIso8601String().split('T').first,
        inwardType: _selectedInwardType,
      );

      if (!mounted) return;
      setState(() => _isPreviewing = false);

      String reportTitle = 'Godown Stock Report';
      if (_selectedReportType == 'today_inward_serials') {
        reportTitle = 'Inward Serial Register';
      } else if (_selectedReportType == 'stock_by_model') {
        reportTitle = 'Stock by Model Report';
      } else if (_selectedReportType == 'stock_out') {
        reportTitle = 'Stock Out Dispatch Report';
      } else if (_selectedReportType == 'unmatched_outward') {
        reportTitle = 'Unmatched Outward Report';
      } else if (_selectedReportType == 'damaged') {
        reportTitle = 'Damaged Stock Report';
      } else if (_selectedReportType == 'today_summary') {
        reportTitle = 'Today Operations Summary';
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GodownReportPreviewScreen(
            pdfBytes: pdfBytes,
            reportTitle: reportTitle,
            selectedPrinter: _selectedPrinter,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isPreviewing = false);
        TopToast.show(
          context,
          message: 'Preview Failed: ${e.toString().replaceAll('Exception: ', '')}',
          backgroundColor: const Color(0xFFEF4444),
          icon: Icons.error_outline_rounded,
        );
      }
    }
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
        inwardType: _selectedInwardType,
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
            tooltip: 'A4 Print Preview',
            icon: _isPreviewing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Color(0xFF3C3489), strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF3C3489)),
            onPressed: (_isPreviewing || _isPrinting) ? null : _handlePreviewA4Report,
          ),
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
            if (_selectedReportType == 'today_inward_serials' ||
                _selectedReportType == 'stock_by_model' ||
                _selectedReportType == 'stock_out') ...[
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
            OutlinedButton.icon(
              onPressed: (_isPreviewing || _isPrinting) ? null : _handlePreviewA4Report,
              icon: _isPreviewing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Color(0xFF3C3489), strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_rounded, size: 20),
              label: Text(
                _isPreviewing ? 'Generating Exact A4 Document...' : 'Preview',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF3C3489),
                side: const BorderSide(color: Color(0xFF3C3489), width: 1.5),
                backgroundColor: const Color(0xFFEEF2FF),
                padding: EdgeInsets.symmetric(vertical: isTablet ? 17 : 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: (_isPrinting || _isPreviewing) ? null : _handlePrintReport,
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
        'id': 'today_inward_serials',
        'title': 'Inward Serial Register',
        'subtitle': 'Serials inwarded based on date, grouped by model with timestamps & inward type',
        'icon': Icons.assignment_turned_in_rounded,
        'color': const Color(0xFF4F46E5),
      },
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

  // ── SEARCHABLE MODEL FILTER ───────────────────────────────────────────────
  Widget _buildSearchableModelFilter(bool isTablet) {
    final query = _modelSearchQuery.trim().toLowerCase();
    final matching = query.isEmpty
        ? <Product>[]
        : _products.where((p) {
            final brand = p.brand.toLowerCase();
            final model = p.model.toLowerCase();
            final name = p.name.toLowerCase();
            return brand.contains(query) || model.contains(query) || name.contains(query);
          }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Search Box
        TextField(
          controller: _modelSearchController,
          decoration: InputDecoration(
            labelText: 'Search & Filter by Model',
            labelStyle: const TextStyle(fontSize: 12),
            hintText: 'Type brand, model, or name (e.g. Haier, 183V)...',
            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF4F46E5)),
            suffixIcon: _modelSearchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      setState(() {
                        _modelSearchController.clear();
                        _modelSearchQuery = '';
                      });
                    },
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
            ),
          ),
          onChanged: (val) {
            setState(() => _modelSearchQuery = val);
          },
        ),

        // 2. Search Results Drop-down Panel
        if (_modelSearchQuery.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFCBD5E1)),
              boxShadow: const [
                BoxShadow(color: Color(0x0C000000), blurRadius: 6, offset: Offset(0, 3)),
              ],
            ),
            child: matching.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'No models found matching "$_modelSearchQuery"',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: matching.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, idx) {
                      final p = matching[idx];
                      final isCurrent = _selectedProduct?.id == p.id;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedProduct = p;
                            _modelSearchController.clear();
                            _modelSearchQuery = '';
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  p.brand.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF4338CA),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${p.model}  •  ${p.name}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                    color: isCurrent ? const Color(0xFF4F46E5) : const Color(0xFF0F172A),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isCurrent)
                                const Icon(Icons.check_rounded, size: 16, color: Color(0xFF4F46E5)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],

        const SizedBox(height: 8),

        // 3. Current Selection Status Card
        if (_selectedProduct != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFC7D2FE)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: Color(0xFF4F46E5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 12),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Filtered Model: ${_selectedProduct!.brand} ${_selectedProduct!.model}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E1B4B),
                        ),
                      ),
                      Text(
                        _selectedProduct!.name,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6366F1)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _selectedProduct = null),
                  icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4338CA)),
                  label: const Text('Show All', style: TextStyle(fontSize: 11, color: Color(0xFF4338CA), fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: const [
                Icon(Icons.layers_outlined, size: 16, color: Color(0xFF64748B)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All Models Selected (Register will include all serials inwarded for selected date grouped by model)',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
      ],
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── SEARCHABLE MODEL FILTER (for today inward & stock by model)
          if (_selectedReportType == 'today_inward_serials' || _selectedReportType == 'stock_by_model') ...[
            _buildSearchableModelFilter(isTablet),
          ],

          // ── TODAY INWARD EXTRA FILTERS (Inward Type & Date)
          if (_selectedReportType == 'today_inward_serials') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _selectedInwardType,
              decoration: const InputDecoration(
                labelText: 'Filter Inward Type',
                labelStyle: TextStyle(fontSize: 12),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All Inward Types (Stock In, Return, Damaged)', style: TextStyle(fontSize: 13)),
                ),
                DropdownMenuItem<String?>(
                  value: 'stock_in',
                  child: Text('Stock In (Direct from Company)', style: TextStyle(fontSize: 13)),
                ),
                DropdownMenuItem<String?>(
                  value: 'return',
                  child: Text('Customer / Shop Return', style: TextStyle(fontSize: 13)),
                ),
                DropdownMenuItem<String?>(
                  value: 'damaged',
                  child: Text('Damaged Stock', style: TextStyle(fontSize: 13)),
                ),
              ],
              onChanged: (val) => setState(() => _selectedInwardType = val),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF4F46E5)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Register Date: ${_formatDate(_dateFrom ?? DateTime.now())}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dateFrom ?? DateTime.now(),
                        firstDate: DateTime(2025),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (picked != null) {
                        setState(() {
                          _dateFrom = picked;
                          _dateTo = picked;
                        });
                      }
                    },
                    child: const Text('Change Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
                  ),
                  if (_dateFrom != null && !_isSameDay(_dateFrom!, DateTime.now()))
                    IconButton(
                      tooltip: 'Reset to Today',
                      icon: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF64748B)),
                      onPressed: () => setState(() {
                        _dateFrom = DateTime.now();
                        _dateTo = DateTime.now();
                      }),
                    ),
                ],
              ),
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
