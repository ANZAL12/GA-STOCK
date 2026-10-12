import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:godown_scanner/models/models.dart';
import 'package:godown_scanner/screens/print_bill_screen.dart';

void main() {
  test('Render PDF test', () async {
    final bill = BillDetail(
      billNumber: '6886',
      shopId: 'shop-1',
      shopName: 'Super Star Electronics',
      shopCity: 'Calicut',
      transactionDate: '12/10/2026',
      createdAt: '2026-10-12T16:00:00Z',
      dispatchedByName: 'Godown Staff',
      deliveryReference: 'KL-11-AB-1234',
      remarks: 'Fast dispatch',
      totalUnits: 3,
      totalBatches: 2,
      batches: [
        BillBatch(
          batchId: 'b-1',
          productId: 'p-1',
          productName: 'Godrej 1.5 Ton Inverter AC',
          brand: 'Godrej',
          model: 'GIC 18 ITC3-WTA',
          quantity: 2,
          matchedCount: 2,
          unmatchedCount: 0,
          flaggedCount: 0,
          lines: [
            BillLine(id: 'l1', serialText: 'GDJ182948291', isMatched: true, isFlagged: false, unitType: 'indoor', statusLabel: 'Available'),
            BillLine(id: 'l2', serialText: 'GDJ182948292', isMatched: true, isFlagged: false, unitType: 'outdoor', statusLabel: 'Available'),
          ],
        ),
        BillBatch(
          batchId: 'b-2',
          productId: 'p-2',
          productName: 'Voltas 2 Ton 3 Star AC',
          brand: 'Voltas',
          model: 'V-200-3S',
          quantity: 1,
          matchedCount: 1,
          unmatchedCount: 0,
          flaggedCount: 0,
          lines: [
            BillLine(id: 'l3', serialText: 'VOL992817261', isMatched: true, isFlagged: false, unitType: null, statusLabel: 'Available'),
          ],
        ),
      ],
    );

    // Call the exact buildPdf logic
    final screen = BillDetailScreen(billNumber: '6886');
    final state = screen.createState();
    final doc = await state.buildPdfForTesting(bill);
    final bytes = await doc.save();
    File('mobile_test.pdf').writeAsBytesSync(bytes);
    print('PDF written to mobile_test.pdf, size: ${bytes.length}');
  });
}
