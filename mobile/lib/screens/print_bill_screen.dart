import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../widgets/top_toast.dart';

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
    final cached = _api.cachedBills;
    if (cached != null && cached.isNotEmpty) {
      _bills = List<BillListItem>.from(cached);
      _loading = false;
    }
    _loadBills();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBills({String? search, bool forceRefresh = false}) async {
    if (_bills.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final bills = await _api.listBills(search: search, forceRefresh: forceRefresh);
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
                    bill.shopCity.trim().isNotEmpty ? '${bill.shopName} • ${bill.shopCity.trim()}' : bill.shopName,
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

  // For test verification
  Future<pw.Document> buildPdfForTesting(BillDetail bill) => _buildPdf(bill);

  // Build the PDF document from BillDetail - exact match to admin dashboard generateBillPdf
  Future<pw.Document> _buildPdf(BillDetail bill) async {
    final doc = pw.Document();

    pw.MemoryImage? logoImage;
    try {
      final bytes = await rootBundle.load('assets/images/logo.png');
      logoImage = pw.MemoryImage(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
    } catch (_) {}

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(12 * PdfPageFormat.mm),
        footer: (ctx) => _pdfFooter(ctx, bill),
        build: (ctx) => [
          _pdfHeader(bill, logoImage),
          pw.SizedBox(height: 4 * PdfPageFormat.mm),
          _pdfModelsTable(bill),
          pw.SizedBox(height: 6 * PdfPageFormat.mm),
          _pdfSerialsTable(bill),
          pw.SizedBox(height: 6 * PdfPageFormat.mm),
          _pdfSignatureBlock(),
        ],
      ),
    );
    return doc;
  }

  // ── PDF widgets ─────────────────────────────────────────────────────────

  pw.Widget _pdfHeader(BillDetail bill, pw.MemoryImage? logoImage) {
    const black = PdfColors.black;

    final destinationVal = bill.shopCity.trim().isNotEmpty
        ? bill.shopCity.trim()
        : bill.shopName;

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: black, width: 0.25),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Title Banner
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Column(
              children: [
                pw.Text(
                  'DELIVERY CHALLAN',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: black,
                  ),
                ),
                pw.SizedBox(height: 1.5),
                pw.Text(
                  '(CENTRAL WAREHOUSE OUTWARD DISPATCH / STOCK TRANSFER VOUCHER)',
                  style: const pw.TextStyle(
                    fontSize: 7.5,
                    color: black,
                  ),
                ),
              ],
            ),
          ),
          pw.Divider(thickness: 0.25, color: black, height: 1),
          // Split Row: Consignor/Consignee (left) vs Voucher Meta (right)
          pw.Table(
            border: const pw.TableBorder(
              verticalInside: pw.BorderSide(color: black, width: 0.25),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(98),
              1: pw.FlexColumnWidth(88),
            },
            children: [
              pw.TableRow(
                children: [
                  // Left Column: Consignor & Consignee
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      // Consignor / Dispatcher
                      pw.Padding(
                        padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 4),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Consignor / Dispatcher:',
                              style: pw.TextStyle(
                                fontSize: 7,
                                fontWeight: pw.FontWeight.bold,
                                color: black,
                              ),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                if (logoImage != null)
                                  pw.Container(
                                    width: 34,
                                    height: 34,
                                    margin: const pw.EdgeInsets.only(right: 7),
                                    child: pw.Image(logoImage),
                                  ),
                                pw.Expanded(
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text(
                                        'GLOBAL LOGISTICS',
                                        style: pw.TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: pw.FontWeight.bold,
                                          color: black,
                                        ),
                                      ),
                                      pw.SizedBox(height: 1),
                                      pw.Text(
                                        'Central Warehouse & Distribution',
                                        style: const pw.TextStyle(fontSize: 7.2, color: black),
                                      ),
                                      pw.Text(
                                        'Stock Management & Automated Serial Register',
                                        style: const pw.TextStyle(fontSize: 7.2, color: black),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      pw.Divider(thickness: 0.25, color: black, height: 1),
                      // Consignee / Buyer (Dispatch To)
                      pw.Padding(
                        padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 4),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Consignee / Buyer (Dispatch To):',
                              style: pw.TextStyle(
                                fontSize: 7,
                                fontWeight: pw.FontWeight.bold,
                                color: black,
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              bill.shopName,
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                color: black,
                              ),
                            ),
                            if (bill.shopCity.trim().isNotEmpty) ...[
                              pw.SizedBox(height: 1),
                              pw.Text(
                                'Location: ${bill.shopCity.trim()}',
                                style: const pw.TextStyle(fontSize: 7.2, color: black),
                              ),
                            ],
                            if (bill.remarks != null && bill.remarks!.trim().isNotEmpty) ...[
                              pw.SizedBox(height: 1),
                              pw.Text(
                                'Remarks: ${bill.remarks!.trim()}',
                                style: const pw.TextStyle(fontSize: 7.2, color: black),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Right Column: Voucher Details
                  pw.Padding(
                    padding: const pw.EdgeInsets.fromLTRB(7, 4, 6, 4),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _pdfMetaRow('Challan / Bill No.:', bill.billNumber, boldVal: true),
                        _pdfMetaRow('Dated:', bill.transactionDate, boldVal: true),
                        _pdfMetaRow('Dispatched By:', bill.dispatchedByName, boldVal: true),
                        _pdfMetaRow('Vehicle / Ref:', bill.deliveryReference ?? 'Direct / Local', boldVal: true),
                        _pdfMetaRow('Mode of Transport:', 'Road / Local Delivery', boldVal: false),
                        _pdfMetaRow('Destination:', destinationVal, boldVal: false),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfMetaRow(String label, String value, {bool boldVal = true}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 78,
            child: pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.black),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 7.8,
                fontWeight: boldVal ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: PdfColors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _tableCell(
    String text, {
    bool bold = false,
    pw.Alignment align = pw.Alignment.centerLeft,
  }) {
    return pw.Container(
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: PdfColors.black,
        ),
      ),
    );
  }

  pw.Widget _pdfModelsTable(BillDetail bill) {
    const headerBg = PdfColor.fromInt(0xFFF2F2F2);
    const border = pw.TableBorder(
      top: pw.BorderSide(color: PdfColors.black, width: 0.25),
      bottom: pw.BorderSide(color: PdfColors.black, width: 0.25),
      left: pw.BorderSide(color: PdfColors.black, width: 0.25),
      right: pw.BorderSide(color: PdfColors.black, width: 0.25),
      horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.2),
      verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.2),
    );

    final rows = <pw.TableRow>[
      // Table Header
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: headerBg),
        children: [
          _tableCell('SI No.', bold: true, align: pw.Alignment.center),
          _tableCell('Brand', bold: true),
          _tableCell('Model', bold: true),
          _tableCell('Description / Specification', bold: true),
          _tableCell('Quantity', bold: true, align: pw.Alignment.centerRight),
        ],
      ),
      // Batches
      ...bill.batches.asMap().entries.map((e) {
        final b = e.value;
        return pw.TableRow(
          children: [
            _tableCell('${e.key + 1}', align: pw.Alignment.center),
            _tableCell(b.brand, bold: true),
            _tableCell(b.model, bold: true),
            _tableCell(b.productName.isNotEmpty ? b.productName : '-'),
            _tableCell('${b.quantity} Units', align: pw.Alignment.centerRight, bold: true),
          ],
        );
      }),
      // Total Row
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: headerBg),
        children: [
          _tableCell(''),
          _tableCell('TOTAL', bold: true),
          _tableCell('${bill.batches.length} Model(s)', bold: true),
          _tableCell(''),
          _tableCell('${bill.totalUnits} Units', align: pw.Alignment.centerRight, bold: true),
        ],
      ),
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '1. Description of Goods Dispatched',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
          ),
        ),
        pw.SizedBox(height: 2 * PdfPageFormat.mm),
        pw.Table(
          border: border,
          columnWidths: const {
            0: pw.FlexColumnWidth(14),
            1: pw.FlexColumnWidth(32),
            2: pw.FlexColumnWidth(42),
            3: pw.FlexColumnWidth(68),
            4: pw.FlexColumnWidth(30),
          },
          children: rows,
        ),
      ],
    );
  }

  pw.Widget _pdfSerialsTable(BillDetail bill) {
    const headerBg = PdfColor.fromInt(0xFFF2F2F2);
    const black = PdfColors.black;

    final batchWidgets = <pw.Widget>[];

    for (int i = 0; i < bill.batches.length; i++) {
      final b = bill.batches[i];
      final descText = (b.productName.isNotEmpty && b.productName != '${b.brand} ${b.model}')
          ? '  |  ${b.productName}'
          : '';

      final serialStrings = <String>[];
      for (int j = 0; j < b.lines.length; j++) {
        final l = b.lines[j];
        final uType = (l.unitType != null && l.unitType!.trim().isNotEmpty)
            ? ' [${l.unitType!.toUpperCase()}]'
            : '';
        serialStrings.add('${j + 1}. ${l.serialText}$uType');
      }

      final lines = <String>[];
      for (int k = 0; k < serialStrings.length; k += 3) {
        final end = (k + 3 < serialStrings.length) ? k + 3 : serialStrings.length;
        lines.add(serialStrings.sublist(k, end).join('          '));
      }

      batchWidgets.add(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Model title row with complete borders and vertical divider
            pw.Table(
              border: const pw.TableBorder(
                top: pw.BorderSide(color: black, width: 0.25),
                bottom: pw.BorderSide(color: black, width: 0.25),
                left: pw.BorderSide(color: black, width: 0.25),
                right: pw.BorderSide(color: black, width: 0.25),
                verticalInside: pw.BorderSide(color: black, width: 0.25),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(156),
                1: pw.FlexColumnWidth(30),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: headerBg),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                      child: pw.Text(
                        '${i + 1}.  ${b.brand} - ${b.model}$descText',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: black,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          '${b.quantity} ${b.quantity == 1 ? "Unit" : "Units"}',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // Complete serial numbers box
            pw.Container(
              width: double.infinity,
              decoration: const pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border(
                  left: pw.BorderSide(color: black, width: 0.25),
                  right: pw.BorderSide(color: black, width: 0.25),
                  bottom: pw.BorderSide(color: black, width: 0.25),
                ),
              ),
              padding: const pw.EdgeInsets.fromLTRB(8, 4, 8, 5),
              child: lines.isNotEmpty
                  ? pw.Text(
                      lines.join('\n'),
                      style: pw.TextStyle(
                        font: pw.Font.courier(),
                        fontSize: 8,
                        color: black,
                        lineSpacing: 3,
                      ),
                    )
                  : pw.Text(
                      '   No scanned serial numbers recorded for this batch',
                      style: const pw.TextStyle(
                        fontSize: 7.5,
                        color: PdfColor.fromInt(0xFF505050),
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '2.Serial Number Register',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: black,
          ),
        ),
        pw.SizedBox(height: 2 * PdfPageFormat.mm),
        // Complete Header Table
        pw.Table(
          border: const pw.TableBorder(
            top: pw.BorderSide(color: black, width: 0.25),
            bottom: pw.BorderSide(color: black, width: 0.25),
            left: pw.BorderSide(color: black, width: 0.25),
            right: pw.BorderSide(color: black, width: 0.25),
            verticalInside: pw.BorderSide(color: black, width: 0.25),
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(156),
            1: pw.FlexColumnWidth(30),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: headerBg),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                  child: pw.Text(
                    'Model Details & Serial Number Register',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: black),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                  child: pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      'Quantity',
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: black),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        ...batchWidgets,
      ],
    );
  }

  pw.Widget _pdfSignatureBlock() {
    const black = PdfColors.black;
    return pw.Table(
      border: pw.TableBorder.all(color: black, width: 0.25),
      columnWidths: const {
        0: pw.FlexColumnWidth(105),
        1: pw.FlexColumnWidth(81),
      },
      children: [
        pw.TableRow(
          children: [
            // Left Box: Declaration & Receiver
            pw.Container(
              height: 75,
              padding: const pw.EdgeInsets.fromLTRB(7, 5, 7, 5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Declaration:',
                        style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: black),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'We declare that this Delivery Challan shows the actual quantity of goods\ndispatched and all serial numbers listed have been physically scanned\nand verified prior to warehouse release.',
                        style: const pw.TextStyle(fontSize: 6.8, color: black),
                      ),
                    ],
                  ),
                  pw.Text(
                    "Customer / Receiver's Signature & Seal",
                    style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: black),
                  ),
                ],
              ),
            ),
            // Right Box: Authorized Signatory
            pw.Container(
              height: 75,
              padding: const pw.EdgeInsets.fromLTRB(7, 5, 7, 5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'for GLOBAL LOGISTICS',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: black),
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        '(Central Warehouse Dispatch Authority)',
                        style: const pw.TextStyle(fontSize: 6.8, color: black),
                      ),
                    ],
                  ),
                  pw.Align(
                    alignment: pw.Alignment.bottomRight,
                    child: pw.Text(
                      'Authorised Signatory',
                      style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: black),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _pdfFooter(pw.Context ctx, BillDetail bill) {
    return pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 6),
      child: pw.Text(
        'This is a Computer Generated Delivery Challan | Bill #${bill.billNumber} | Page ${ctx.pageNumber} of ${ctx.pagesCount}',
        style: const pw.TextStyle(fontSize: 7, color: PdfColor.fromInt(0xFF3C3C3C)),
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  bool _isGeneratingPdf = false;

  Future<void> _openPdfPreview() async {
    if (_detail == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BillPdfViewerScreen(bill: _detail!, onBuildPdf: _buildPdf)),
    );
  }

  Future<void> _directPrint() async {
    if (_detail == null || _isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final doc = await _buildPdf(_detail!);
      await Printing.layoutPdf(
        name: 'Bill_${_detail!.billNumber}',
        onLayout: (_) async => doc.save(),
      );
    } catch (e) {
      if (mounted) {
        TopToast.show(
          context,
          message: 'Direct print unavailable ($e). Opening preview...',
          backgroundColor: const Color(0xFFD97706),
          icon: Icons.info_outline_rounded,
        );
        _openPdfPreview();
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _sharePdf() async {
    if (_detail == null || _isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final doc = await _buildPdf(_detail!);
      final bytes = await doc.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Bill_${_detail!.billNumber}.pdf',
      );
    } catch (e) {
      if (mounted) {
        TopToast.show(
          context,
          message: 'Share error: $e',
          backgroundColor: const Color(0xFFE11D48),
          icon: Icons.error_outline_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

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
          if (_detail != null) ...[
            IconButton(
              icon: const Icon(Icons.share_outlined, color: Color(0xFF3C3489)),
              tooltip: 'Share PDF',
              onPressed: _isGeneratingPdf ? null : _sharePdf,
            ),
            IconButton(
              icon: const Icon(Icons.print, color: Color(0xFF3C3489)),
              tooltip: 'Direct Print',
              onPressed: _isGeneratingPdf ? null : _directPrint,
            ),
          ],
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
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _isGeneratingPdf ? null : _sharePdf,
                          icon: const Icon(Icons.share_outlined, size: 18),
                          label: const Text('Share PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF3C3489),
                            side: const BorderSide(color: Color(0xFF3C3489)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isGeneratingPdf ? null : _openPdfPreview,
                          icon: _isGeneratingPdf
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.picture_as_pdf_rounded, size: 20),
                          label: const Text('View & Print PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3C3489),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
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
          _infoRow(Icons.store_outlined, 'Shop', bill.shopCity.trim().isNotEmpty ? '${bill.shopName} – ${bill.shopCity.trim()}' : bill.shopName),
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

// ─────────────────────────────────────────────────────────────────────────────
//  BillPdfViewerScreen – Interactive PDF Preview with Print & Share actions
// ─────────────────────────────────────────────────────────────────────────────

class BillPdfViewerScreen extends StatelessWidget {
  final BillDetail bill;
  final Future<pw.Document> Function(BillDetail) onBuildPdf;

  const BillPdfViewerScreen({
    super.key,
    required this.bill,
    required this.onBuildPdf,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(
          'Challan: ${bill.billNumber}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
      body: PdfPreview(
        build: (format) async {
          final doc = await onBuildPdf(bill);
          return doc.save();
        },
        pdfFileName: 'Bill_${bill.billNumber}.pdf',
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        loadingWidget: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF3C3489)),
              SizedBox(height: 12),
              Text(
                'Rendering Challan PDF...',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

