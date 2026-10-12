import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test('Verify complete boxes in mobile bill PDF', () async {
    const black = PdfColors.black;
    const headerBg = PdfColor.fromInt(0xFFF2F2F2);
    final doc = pw.Document();

    final destinationVal = 'Calicut';

    // 1. Header Box
    pw.Widget pdfHeader() {
      final divider = pw.Container(height: 0.25, color: black);
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
            pw.Divider(thickness: 0.5, color: black, height: 1),
            // Split Row
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
                    // Left Column
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        // Consignor
                        pw.Padding(
                          padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 4),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'Consignor / Dispatcher:',
                                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: black),
                              ),
                              pw.SizedBox(height: 3),
                              pw.Text(
                                'GLOBAL LOGISTICS',
                                style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: black),
                              ),
                              pw.Text('Central Warehouse & Distribution', style: const pw.TextStyle(fontSize: 7.2, color: black)),
                              pw.Text('Stock Management & Automated Serial Register', style: const pw.TextStyle(fontSize: 7.2, color: black)),
                            ],
                          ),
                        ),
                        pw.Divider(thickness: 0.5, color: black, height: 1),
                        // Consignee
                        pw.Padding(
                          padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 4),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'Consignee / Buyer (Dispatch To):',
                                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: black),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                'Super Star Electronics',
                                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: black),
                              ),
                              pw.SizedBox(height: 1),
                              pw.Text('Location: Calicut', style: const pw.TextStyle(fontSize: 7.2, color: black)),
                              pw.SizedBox(height: 1),
                              pw.Text('Remarks: Fast delivery', style: const pw.TextStyle(fontSize: 7.2, color: black)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Right Column
                    pw.Padding(
                      padding: const pw.EdgeInsets.fromLTRB(7, 4, 6, 4),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _metaRow('Challan / Bill No.:', '6886', true),
                          _metaRow('Dated:', '12/10/2026', true),
                          _metaRow('Dispatched By:', 'Godown Staff', true),
                          _metaRow('Vehicle / Ref:', 'KL-11-AB-1234', true),
                          _metaRow('Mode of Transport:', 'Road / Local Delivery', false),
                          _metaRow('Destination:', destinationVal, false),
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

    // 2. Table 1: Description of Goods
    pw.Widget pdfModelsTable() {
      const border = pw.TableBorder(
        top: pw.BorderSide(color: black, width: 0.25),
        bottom: pw.BorderSide(color: black, width: 0.25),
        left: pw.BorderSide(color: black, width: 0.25),
        right: pw.BorderSide(color: black, width: 0.25),
        horizontalInside: pw.BorderSide(color: black, width: 0.2),
        verticalInside: pw.BorderSide(color: black, width: 0.2),
      );

      final rows = <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: headerBg),
          children: [
            _cell('SI No.', bold: true, align: pw.Alignment.center),
            _cell('Brand', bold: true),
            _cell('Model', bold: true),
            _cell('Description / Specification', bold: true),
            _cell('Quantity', bold: true, align: pw.Alignment.centerRight),
          ],
        ),
        pw.TableRow(
          children: [
            _cell('1', align: pw.Alignment.center),
            _cell('Godrej', bold: true),
            _cell('GIC 18 ITC3-WTA', bold: true),
            _cell('Godrej 1.5 Ton Inverter AC'),
            _cell('2 Units', align: pw.Alignment.centerRight, bold: true),
          ],
        ),
        pw.TableRow(
          children: [
            _cell('2', align: pw.Alignment.center),
            _cell('Voltas', bold: true),
            _cell('V-200-3S', bold: true),
            _cell('Voltas 2 Ton 3 Star AC'),
            _cell('1 Units', align: pw.Alignment.centerRight, bold: true),
          ],
        ),
        // Total row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: headerBg),
          children: [
            _cell(''),
            _cell('TOTAL', bold: true),
            _cell('2 Model(s)', bold: true),
            _cell(''),
            _cell('3 Units', align: pw.Alignment.centerRight, bold: true),
          ],
        ),
      ];

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '1. Description of Goods Dispatched',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: black),
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

    // 3. Table 2: Serial Number Register with COMPLETE BOXES
    pw.Widget pdfSerialsTable() {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '2.Serial Number Register',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: black),
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
          // Batch 1
          _buildBatchBox(1, 'Godrej', 'GIC 18 ITC3-WTA', 'Godrej 1.5 Ton Inverter AC', 2, [
            '1. GDJ182948291 [INDOOR]          2. GDJ182948292 [OUTDOOR]'
          ]),
          // Batch 2
          _buildBatchBox(2, 'Voltas', 'V-200-3S', 'Voltas 2 Ton 3 Star AC', 1, [
            '1. VOL992817261'
          ]),
        ],
      );
    }

    // 4. Signature Block
    pw.Widget pdfSignatureBlock() {
      return pw.Table(
        border: pw.TableBorder.all(color: black, width: 0.25),
        columnWidths: const {
          0: pw.FlexColumnWidth(105),
          1: pw.FlexColumnWidth(81),
        },
        children: [
          pw.TableRow(
            children: [
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
                        pw.Text('Declaration:', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: black)),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'We declare that this Delivery Challan shows the actual quantity of goods\ndispatched and all serial numbers listed have been physically scanned\nand verified prior to warehouse release.',
                          style: const pw.TextStyle(fontSize: 6.8, color: black),
                        ),
                      ],
                    ),
                    pw.Text("Customer / Receiver's Signature & Seal", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: black)),
                  ],
                ),
              ),
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
                        pw.Text('for GLOBAL LOGISTICS', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: black)),
                        pw.SizedBox(height: 1),
                        pw.Text('(Central Warehouse Dispatch Authority)', style: const pw.TextStyle(fontSize: 6.8, color: black)),
                      ],
                    ),
                    pw.Align(
                      alignment: pw.Alignment.bottomRight,
                      child: pw.Text('Authorised Signatory', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: black)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(12 * PdfPageFormat.mm),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'This is a Computer Generated Delivery Challan | Bill #6886 | Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColor.fromInt(0xFF3C3C3C)),
          ),
        ),
        build: (ctx) => [
          pdfHeader(),
          pw.SizedBox(height: 4 * PdfPageFormat.mm),
          pdfModelsTable(),
          pw.SizedBox(height: 6 * PdfPageFormat.mm),
          pdfSerialsTable(),
          pw.SizedBox(height: 6 * PdfPageFormat.mm),
          pdfSignatureBlock(),
        ],
      ),
    );

    final bytes = await doc.save();
    File('sample_bill.pdf').writeAsBytesSync(bytes);
    print('Generated sample_bill.pdf successfully! Size: ${bytes.length}');
  });
}

pw.Widget _metaRow(String label, String value, bool boldVal) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.6),
    child: pw.Row(
      children: [
        pw.SizedBox(width: 78, child: pw.Text(label, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.black))),
        pw.Expanded(child: pw.Text(value, style: pw.TextStyle(fontSize: 7.8, fontWeight: boldVal ? pw.FontWeight.bold : pw.FontWeight.normal, color: PdfColors.black))),
      ],
    ),
  );
}

pw.Widget _cell(String text, {bool bold = false, pw.Alignment align = pw.Alignment.centerLeft}) {
  return pw.Container(
    alignment: align,
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Text(text, style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: PdfColors.black)),
  );
}

pw.Widget _buildBatchBox(int idx, String brand, String model, String prodName, int qty, List<String> lines) {
  const black = PdfColors.black;
  const headerBg = PdfColor.fromInt(0xFFF2F2F2);
  final desc = prodName.isNotEmpty && prodName != '$brand $model' ? '  |  $prodName' : '';

  return pw.Column(
    children: [
      // Model row table
      pw.Table(
        border: const pw.TableBorder(
          top: pw.BorderSide.none,
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
                  '$idx.  $brand - $model$desc',
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: black),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                child: pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    '$qty ${qty == 1 ? "Unit" : "Units"}',
                    style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: black),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      // Serials box
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
        child: pw.Text(
          lines.join('\n'),
          style: pw.TextStyle(font: pw.Font.courier(), fontSize: 8, color: black, lineSpacing: 3),
        ),
      ),
    ],
  );
}
