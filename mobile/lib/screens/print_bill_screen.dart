import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/api_service.dart';
import '../models/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PrintBillScreen – list bills and print/share as PDF
// ─────────────────────────────────────────────────────────────────────────────

class PrintBillScreen extends StatefulWidget {
  const PrintBillScreen({super.key});

  @override
  State<PrintBillScreen> createState() => _PrintBillScreenState();
}

class _PrintBillScreenState extends State<PrintBillScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<BillListItem> _bills = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBills({String? search}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bills = await _api.listBills(search: search);
      if (mounted) setState(() { _bills = bills; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _onSearch(String value) => _loadBills(search: value.trim().isEmpty ? null : value.trim());

  // ── Open detail then trigger print/share ──────────────────────────────────
  Future<void> _openBill(BillListItem item) async {
    // Navigate to detail screen which handles pdf preview
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BillDetailScreen(billNumber: item.billNumber)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Print / Export Bill',
          style: TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search by bill number or shop…',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF94A3B8)),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _loadBills();
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF3C3489), width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),

          // List
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF3C3489)));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFE11D48), size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFF64748B), fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadBills,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3C3489), foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    }
    if (_bills.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('No bills found', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadBills(search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim()),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _bills.length,
        itemBuilder: (ctx, i) => _buildBillCard(_bills[i]),
      ),
    );
  }

  Widget _buildBillCard(BillListItem bill) {
    return GestureDetector(
      onTap: () => _openBill(bill),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.receipt_long, color: Color(0xFF3C3489), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bill.billNumber,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${bill.shopName} • ${bill.shopCity}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _chip('${bill.totalUnits} units', const Color(0xFF059669), const Color(0xFFECFDF5)),
                      const SizedBox(width: 6),
                      _chip(bill.transactionDate, const Color(0xFF3C3489), const Color(0xFFEEF2FF)),
                    ],
                  ),
                  if (bill.modelsSummary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      bill.modelsSummary.join(', '),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.print, color: Color(0xFF94A3B8), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color text, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: text)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BillDetailScreen – preview and print a single bill as PDF
// ─────────────────────────────────────────────────────────────────────────────

class BillDetailScreen extends StatefulWidget {
  final String billNumber;
  const BillDetailScreen({super.key, required this.billNumber});

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
  final ApiService _api = ApiService();
  BillDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await _api.getBillDetail(widget.billNumber);
      if (mounted) setState(() { _detail = d; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // Build the PDF document from BillDetail - exact match to admin dashboard generateBillPdf
  Future<pw.Document> _buildPdf(BillDetail bill) async {
    final doc = pw.Document();

    pw.MemoryImage? logoImage;
    try {
      final bytes = await rootBundle.load('assets/images/logo.png');
      logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {}

    final nowFormatted = DateFormat('M/d/yyyy, h:mm:ss a').format(DateTime.now());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 39.69, vertical: 34.0),
        footer: (ctx) => _pdfFooter(ctx, bill, nowFormatted),
        build: (ctx) => [
          _pdfHeader(bill, logoImage),
          pw.SizedBox(height: 12),
          _pdfBillInfoCard(bill),
          pw.SizedBox(height: 14),
          _pdfModelsTable(bill),
          pw.SizedBox(height: 14),
          _pdfSerialsTable(bill),
          pw.SizedBox(height: 75),
          _pdfSignatureBlock(),
        ],
      ),
    );
    return doc;
  }

  // ── PDF widgets ─────────────────────────────────────────────────────────

  pw.Widget _pdfHeader(BillDetail bill, pw.MemoryImage? logoImage) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xFF1E1B4B),
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logoImage != null)
                pw.Container(
                  width: 38,
                  height: 38,
                  margin: const pw.EdgeInsets.only(right: 12),
                  child: pw.Image(logoImage),
                ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'GLOBAL LOGISTICS',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'CENTRAL WAREHOUSE DISPATCH BILL / DELIVERY CHALLAN',
                    style: const pw.TextStyle(color: PdfColor.fromInt(0xFFE0E7FF), fontSize: 8),
                  ),
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'Stock Management & Automated Serial Tracking System',
                    style: const pw.TextStyle(color: PdfColor.fromInt(0xFFE0E7FF), fontSize: 7.5),
                  ),
                ],
              ),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'BILL NO:',
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xFF1E1B4B),
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  bill.billNumber,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xFF1E1B4B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfFooter(pw.Context ctx, BillDetail bill, String nowFormatted) {
    return pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text(
        'Generated on $nowFormatted  |  Bill #${bill.billNumber}  |  Page ${ctx.pageNumber} of ${ctx.pagesCount}',
        style: const pw.TextStyle(fontSize: 7.5, color: PdfColor.fromInt(0xFF94A3B8)),
      ),
    );
  }

  pw.Widget _pdfBillInfoCard(BillDetail bill) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFF8FAFC),
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0)),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'DISPATCH TO (CONSIGNEE):',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xFF64748B),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  bill.shopName,
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xFF0F172A),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'City / Location: ${bill.shopCity}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF475569)),
                ),
                if (bill.remarks != null && bill.remarks!.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Remarks: ${bill.remarks}',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF475569)),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 24),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'DISPATCH DETAILS:',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xFF64748B),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Date: ${bill.transactionDate}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF475569)),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Vehicle / Ref: ${bill.deliveryReference ?? "Direct / Local"}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF475569)),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Dispatched By: ${bill.dispatchedByName}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF475569)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfModelsTable(BillDetail bill) {
    final modelRows = bill.batches.asMap().entries.map((e) {
      final b = e.value;
      return [
        '${e.key + 1}',
        b.brand,
        b.model,
        b.productName,
        '${b.quantity}',
      ];
    }).toList();

    // Total row matching web dashboard
    modelRows.add([
      '',
      'TOTAL',
      '${bill.batches.length} Model(s)',
      '',
      '${bill.totalUnits}',
    ]);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '1. Models & Quantities Dispatched',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: const PdfColor.fromInt(0xFF0F172A),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: ['#', 'Brand', 'Model', 'Description', 'Quantity'],
          data: modelRows,
          headerStyle: pw.TextStyle(
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
            fontSize: 8.5,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF3C3489)),
          cellStyle: const pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFF1E293B)),
          cellDecoration: (index, data, rowNum) {
            if (rowNum == modelRows.length) {
              return const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9));
            }
            return const pw.BoxDecoration();
          },
          columnWidths: {
            0: const pw.FixedColumnWidth(26),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(2.5),
            3: const pw.FlexColumnWidth(3.5),
            4: const pw.FixedColumnWidth(55),
          },
          cellAlignments: {
            0: pw.Alignment.center,
            4: pw.Alignment.center,
          },
          border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
        ),
      ],
    );
  }

  pw.Widget _pdfSerialsTable(BillDetail bill) {
    final rows = <List<String>>[];
    int idx = 1;
    for (final b in bill.batches) {
      for (final l in b.lines) {
        rows.add([
          '${idx++}',
          b.brand,
          b.model,
          l.serialText,
          l.unitType != null && l.unitType!.isNotEmpty ? l.unitType!.toUpperCase() : '-',
        ]);
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '2. Scanned Serial Number Register',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: const PdfColor.fromInt(0xFF0F172A),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: ['#', 'Brand', 'Model', 'Serial Number', 'Unit Type'],
          data: rows,
          headerStyle: pw.TextStyle(
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
            fontSize: 8.5,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF4F46E5)),
          cellStyle: const pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFF1E293B)),
          columnWidths: {
            0: const pw.FixedColumnWidth(26),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(2.5),
            3: const pw.FlexColumnWidth(3.5),
            4: const pw.FixedColumnWidth(55),
          },
          cellAlignments: {
            0: pw.Alignment.center,
            4: pw.Alignment.center,
          },
          border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8FAFC)),
        ),
      ],
    );
  }

  pw.Widget _pdfSignatureBlock() {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 25),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(width: 150, height: 0.75, color: const PdfColor.fromInt(0xFFCBD5E1)),
              pw.SizedBox(height: 6),
              pw.Text(
                "Receiver's Signature & Seal",
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFF475569)),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(width: 180, height: 0.75, color: const PdfColor.fromInt(0xFFCBD5E1)),
              pw.SizedBox(height: 6),
              pw.Text(
                'Authorized Signatory (Global Logistics)',
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFF475569)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Bill: ${widget.billNumber}',
          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        actions: [
          if (_detail != null)
            IconButton(
              icon: const Icon(Icons.print, color: Color(0xFF3C3489)),
              tooltip: 'Print / Share PDF',
              onPressed: _printOrShare,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3C3489)))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFE11D48), size: 48),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF64748B))),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3C3489), foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                )
              : _buildDetail(_detail!),
      bottomNavigationBar: _detail != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: _printOrShare,
                  icon: const Icon(Icons.print),
                  label: const Text('Print / Share PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3C3489),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _printOrShare() async {
    if (_detail == null) return;
    final doc = await _buildPdf(_detail!);
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  Widget _buildDetail(BillDetail bill) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Bill info card
          _infoCard(bill),
          const SizedBox(height: 16),

          // ── Models summary
          _sectionHeader('Models & Quantities', Icons.inventory_2_outlined),
          const SizedBox(height: 8),
          ...bill.batches.asMap().entries.map((e) => _batchCard(e.key + 1, e.value)),

          const SizedBox(height: 16),
          // ── Serial register
          _sectionHeader('Scanned Serial Numbers', Icons.qr_code_scanner),
          const SizedBox(height: 8),
          _serialsTable(bill),

          const SizedBox(height: 80), // space for bottom bar
        ],
      ),
    );
  }

  Widget _infoCard(BillDetail bill) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFF1E1B4B), borderRadius: BorderRadius.circular(6)),
              child: Text(bill.billNumber, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(6)),
              child: Text('${bill.totalUnits} units',
                  style: const TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 10),
          _infoRow(Icons.store_outlined, 'Shop', '${bill.shopName} – ${bill.shopCity}'),
          _infoRow(Icons.calendar_today_outlined, 'Date', bill.transactionDate),
          _infoRow(Icons.person_outline, 'Dispatched By', bill.dispatchedByName),
          if (bill.deliveryReference != null)
            _infoRow(Icons.local_shipping_outlined, 'Vehicle / Ref', bill.deliveryReference!),
          if (bill.remarks != null)
            _infoRow(Icons.notes_outlined, 'Remarks', bill.remarks!),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF3C3489)),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
      ],
    );
  }

  Widget _batchCard(int no, BillBatch batch) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(8)),
            child: Text('$no', style: const TextStyle(color: Color(0xFF3C3489), fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${batch.brand} ${batch.model}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                Text(batch.productName, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(6)),
            child: Text('${batch.quantity} u', style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _serialsTable(BillDetail bill) {
    final allLines = <({String brand, String model, BillLine line})>[];
    for (final b in bill.batches) {
      for (final l in b.lines) {
        allLines.add((brand: b.brand, model: b.model, line: l));
      }
    }

    if (allLines.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Text('No serial lines available', style: TextStyle(color: Color(0xFF94A3B8))),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          // header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF4F46E5),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 30, child: Text('#', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                Expanded(flex: 3, child: Text('Serial Number', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Model', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                SizedBox(width: 50, child: Text('Type', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          ...allLines.asMap().entries.map((e) {
            final even = e.key.isEven;
            final item = e.value;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: even ? Colors.white : const Color(0xFFF8FAFC),
                borderRadius: e.key == allLines.length - 1
                    ? const BorderRadius.vertical(bottom: Radius.circular(12))
                    : BorderRadius.zero,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text('${e.key + 1}', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(item.line.serialText, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(item.model, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  ),
                  SizedBox(
                    width: 50,
                    child: Text(
                      item.line.unitType?.toUpperCase() ?? '-',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: item.line.unitType == 'indoor'
                            ? const Color(0xFF0369A1)
                            : item.line.unitType == 'outdoor'
                                ? const Color(0xFF059669)
                                : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
