import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../services/api_service.dart';
import '../widgets/top_toast.dart';
import '../widgets/responsive_utils.dart';

class GodownReportPreviewScreen extends StatefulWidget {
  final Uint8List pdfBytes;
  final String reportTitle;
  final String? selectedPrinter;

  const GodownReportPreviewScreen({
    super.key,
    required this.pdfBytes,
    required this.reportTitle,
    this.selectedPrinter,
  });

  @override
  State<GodownReportPreviewScreen> createState() => _GodownReportPreviewScreenState();
}

class _GodownReportPreviewScreenState extends State<GodownReportPreviewScreen> {
  final ApiService _api = ApiService();
  bool _isPrinting = false;

  Future<void> _handlePrintToOfficePc() async {
    setState(() => _isPrinting = true);

    try {
      final res = await _api.printRawPdf(
        pdfBytes: widget.pdfBytes,
        printerName: widget.selectedPrinter,
        jobName: widget.reportTitle,
      );

      if (!mounted) return;
      setState(() => _isPrinting = false);

      final msg = res['message'] ?? 'Successfully sent to Office PC Printer!';
      TopToast.show(context, message: msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPrinting = false);
      TopToast.show(
        context,
        message: 'Print failed: ${e.toString().replaceAll('Exception: ', '')}',
        backgroundColor: const Color(0xFFEF4444),
        icon: Icons.error_outline_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = context.isTablet;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        toolbarHeight: isTablet ? 68 : 56,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.reportTitle,
              style: TextStyle(
                fontSize: isTablet ? 17 : 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            const Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF059669)),
                SizedBox(width: 4),
                Text(
                  'Exact A4 Page Preview (595 × 842 pt)',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3C3489),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: _isPrinting ? null : _handlePrintToOfficePc,
              icon: _isPrinting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.print_rounded, size: 16),
              label: Text(
                _isPrinting ? 'Sending...' : 'Print on Office PC',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: PdfPreview(
        build: (format) async => widget.pdfBytes,
        pdfFileName: '${widget.reportTitle.replaceAll(' ', '_')}.pdf',
        initialPageFormat: PdfPageFormat.a4,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        maxPageWidth: isTablet ? 720 : 540,
        loadingWidget: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF3C3489)),
              SizedBox(height: 14),
              Text(
                'Rendering Exact A4 Document...',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
