/**
 * Node.js Bill PDF Generator
 * Uses the exact same jsPDF & jspdf-autotable logic from frontend/src/utils/generateBillPdf.ts
 */
const fs = require('fs');
const path = require('path');

// Resolve jspdf and jspdf-autotable from frontend node_modules
const frontendModules = path.resolve(__dirname, '../../../frontend/node_modules');
const { jsPDF } = require(path.join(frontendModules, 'jspdf'));
const autoTableModule = require(path.join(frontendModules, 'jspdf-autotable'));
const autoTable = autoTableModule.default || autoTableModule;

// Optional: logo base64
let LOGO_BASE64 = null;
try {
  const logoFile = path.resolve(__dirname, '../assets/logo.png');
  if (fs.existsSync(logoFile)) {
    const b64 = fs.readFileSync(logoFile).toString('base64');
    LOGO_BASE64 = 'data:image/png;base64,' + b64;
  }
} catch (_) {}

function buildBillPdf(bill) {
  const doc = new jsPDF({
    orientation: 'portrait',
    unit: 'mm',
    format: 'a4',
  });

  const pageWidth = doc.internal.pageSize.getWidth();
  const margin = 12;
  const contentWidth = pageWidth - margin * 2; // 186mm

  // Standard line and text styling (pure black, zero color ink waste)
  doc.setDrawColor(0, 0, 0);
  doc.setTextColor(0, 0, 0);
  doc.setLineWidth(0.25);

  // --- 1. TALLY PRIME STYLE HEADER BOX ---
  const startY = 12;
  const headerBoxHeight = 58;

  // Outer border of header
  doc.rect(margin, startY, contentWidth, headerBoxHeight);

  // Title Banner
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(12);
  doc.text('DELIVERY CHALLAN', pageWidth / 2, startY + 5.5, { align: 'center' });

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(7.5);
  doc.text('(CENTRAL WAREHOUSE OUTWARD DISPATCH / STOCK TRANSFER VOUCHER)', pageWidth / 2, startY + 9.5, {
    align: 'center',
  });

  // Divider line under title
  doc.line(margin, startY + 11.5, pageWidth - margin, startY + 11.5);

  // Vertical split between Consignor/Consignee (Left: 98mm) and Voucher Details (Right: 88mm)
  const splitX = margin + 98;
  doc.line(splitX, startY + 11.5, splitX, startY + headerBoxHeight);

  // Horizontal divider on the left side (dividing Dispatcher from Consignee)
  const leftMidY = startY + 34;
  doc.line(margin, leftMidY, splitX, leftMidY);

  // Left Top: Dispatcher / Consignor with Emblem Logo
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(7);
  doc.text('Consignor / Dispatcher:', margin + 2.5, startY + 15.5);

  let textStartX = margin + 2.5;
  if (LOGO_BASE64) {
    try {
      doc.addImage(LOGO_BASE64, 'PNG', margin + 2.5, startY + 17, 14, 14);
      textStartX = margin + 19;
    } catch (err) {}
  }

  doc.setFontSize(10.5);
  doc.text('GLOBAL LOGISTICS', textStartX, startY + 22);

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(7.2);
  doc.text('Central Warehouse & Distribution', textStartX, startY + 26.5);
  doc.text('Stock Management & Automated Serial Register', textStartX, startY + 30.5);

  // Left Bottom: Consignee (Buyer / Dispatch To)
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(7);
  doc.text('Consignee / Buyer (Dispatch To):', margin + 2.5, leftMidY + 4.5);

  doc.setFontSize(9);
  doc.text(bill.shop_name || '', margin + 2.5, leftMidY + 9.5, {
    maxWidth: splitX - margin - 5,
  });

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(7.2);
  let leftInfoY = leftMidY + 14.5;
  if (bill.shop_city && bill.shop_city.trim()) {
    doc.text(`Location: ${bill.shop_city.trim()}`, margin + 2.5, leftInfoY, {
      maxWidth: splitX - margin - 5,
    });
    leftInfoY += 4;
  }
  if (bill.remarks) {
    doc.text(`Remarks: ${bill.remarks}`, margin + 2.5, leftInfoY, {
      maxWidth: splitX - margin - 5,
    });
  }

  // Right Side: Tally Voucher Meta Details
  const labelX = splitX + 3;
  const valX = splitX + 31;
  const maxValWidth = pageWidth - margin - valX - 2;
  let rY = startY + 16.5;

  const addRightRow = (label, value, boldVal = true) => {
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(7.5);
    doc.text(label, labelX, rY);
    doc.setFont('helvetica', boldVal ? 'bold' : 'normal');
    doc.setFontSize(7.8);
    doc.text(String(value || ''), valX, rY, { maxWidth: maxValWidth });
    rY += 6;
  };

  addRightRow('Challan / Bill No.:', bill.bill_number, true);
  addRightRow('Dated:', bill.transaction_date, true);
  addRightRow('Dispatched By:', bill.dispatched_by_name || bill.dispatcher_name || 'Admin', true);
  addRightRow('Vehicle / Ref:', bill.delivery_reference || 'Direct / Local', true);
  addRightRow('Mode of Transport:', 'Road / Local Delivery', false);

  const destinationVal =
    bill.shop_city && bill.shop_city.trim()
      ? bill.shop_city.trim()
      : bill.shop_name || '-';
  addRightRow('Destination:', destinationVal, false);

  // --- 2. TABLE 1: DESCRIPTION OF GOODS & QUANTITY BREAKDOWN ---
  let currentY = startY + headerBoxHeight + 4;
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(9);
  doc.text('1. Description of Goods Dispatched', margin, currentY);

  const batches = bill.batches || [];
  const modelTableBody = batches.map((b, idx) => [
    (idx + 1).toString(),
    b.brand || '-',
    b.model || '-',
    b.product_name || '-',
    `${b.quantity || 0} Units`,
  ]);

  // Append Total Row
  modelTableBody.push([
    '',
    'TOTAL',
    `${batches.length} Model(s)`,
    '',
    `${bill.total_units || 0} Units`,
  ]);

  autoTable(doc, {
    startY: currentY + 2,
    head: [['SI No.', 'Brand', 'Model', 'Description / Specification', 'Quantity']],
    body: modelTableBody,
    theme: 'grid',
    styles: {
      font: 'helvetica',
      fontSize: 8,
      textColor: [0, 0, 0],
      lineColor: [0, 0, 0],
      lineWidth: 0.2,
      cellPadding: 2,
    },
    headStyles: {
      fillColor: [242, 242, 242],
      textColor: [0, 0, 0],
      fontStyle: 'bold',
      lineColor: [0, 0, 0],
      lineWidth: 0.25,
      halign: 'left',
    },
    columnStyles: {
      0: { cellWidth: 14, halign: 'center' },
      1: { cellWidth: 32, fontStyle: 'bold' },
      2: { cellWidth: 42, fontStyle: 'bold' },
      3: { cellWidth: 68 },
      4: { cellWidth: 30, halign: 'right', fontStyle: 'bold' },
    },
    margin: { left: margin, right: margin },
    didParseCell: (data) => {
      if (data.row.index === modelTableBody.length - 1) {
        data.cell.styles.fontStyle = 'bold';
        data.cell.styles.fillColor = [242, 242, 242];
        data.cell.styles.textColor = [0, 0, 0];
      }
    },
  });

  // --- 3. TABLE 2: SERIAL NUMBER REGISTER ---
  const lastTableY = doc.lastAutoTable.finalY || currentY + 40;
  let serialsHeaderY = lastTableY + 6;

  if (serialsHeaderY > 235) {
    doc.addPage();
    serialsHeaderY = 16;
  }

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(9);
  doc.text('2.Serial Number Register', margin, serialsHeaderY);

  const serialRows = [];
  batches.forEach((b, bIdx) => {
    const descText =
      b.product_name && b.product_name !== `${b.brand} ${b.model}` ? `  |  ${b.product_name}` : '';

    serialRows.push([
      {
        content: `${bIdx + 1}.  ${b.brand} - ${b.model}${descText}`,
        styles: {
          fillColor: [242, 242, 242],
          textColor: [0, 0, 0],
          fontStyle: 'bold',
          fontSize: 8.5,
          lineColor: [0, 0, 0],
          lineWidth: 0.2,
        },
      },
      {
        content: `${b.quantity} ${b.quantity === 1 ? 'Unit' : 'Units'}`,
        styles: {
          fillColor: [242, 242, 242],
          textColor: [0, 0, 0],
          fontStyle: 'bold',
          fontSize: 8.5,
          halign: 'right',
          lineColor: [0, 0, 0],
          lineWidth: 0.2,
        },
      },
    ]);

    const lines = b.lines || [];
    if (lines.length === 0) {
      serialRows.push([
        {
          content: '   No scanned serial numbers recorded for this batch',
          colSpan: 2,
          styles: {
            fontStyle: 'italic',
            textColor: [80, 80, 80],
            fontSize: 7.5,
            fillColor: false,
            lineColor: [0, 0, 0],
            lineWidth: 0.2,
          },
        },
      ]);
    } else {
      const serialStrings = lines.map((l, lIdx) => {
        const uType = l.unit_type && l.unit_type.trim() ? ` [${l.unit_type.toUpperCase()}]` : '';
        return `${lIdx + 1}. ${l.serial_text}${uType}`;
      });

      const chunkedLines = [];
      for (let i = 0; i < serialStrings.length; i += 3) {
        chunkedLines.push(serialStrings.slice(i, i + 3).join('          '));
      }

      serialRows.push([
        {
          content: chunkedLines.join('\n'),
          colSpan: 2,
          styles: {
            font: 'courier',
            fontSize: 8,
            textColor: [0, 0, 0],
            fillColor: false,
            lineColor: [0, 0, 0],
            lineWidth: 0.2,
            cellPadding: { top: 2.5, bottom: 3, left: 4, right: 4 },
          },
        },
      ]);
    }
  });

  autoTable(doc, {
    startY: serialsHeaderY + 2,
    head: [['Model Details & Serial Number Register', 'Quantity']],
    body: serialRows,
    theme: 'grid',
    styles: {
      lineColor: [0, 0, 0],
      lineWidth: 0.2,
    },
    headStyles: {
      fillColor: [242, 242, 242],
      textColor: [0, 0, 0],
      fontStyle: 'bold',
      fontSize: 8,
      lineColor: [0, 0, 0],
      lineWidth: 0.25,
    },
    columnStyles: {
      0: { cellWidth: contentWidth - 30 },
      1: { cellWidth: 30, halign: 'right' },
    },
    margin: { left: margin, right: margin },
  });

  // --- 4. TALLY PRIME STYLE DECLARATION & SIGNATURE FOOTER ---
  const finalTableY = doc.lastAutoTable.finalY || serialsHeaderY + 40;
  let signY = finalTableY + 6;

  if (signY > 245) {
    doc.addPage();
    signY = 16;
  }

  const signBoxHeight = 28;
  doc.rect(margin, signY, contentWidth, signBoxHeight);

  // Vertical divider in the signature box
  const signSplitX = margin + 105;
  doc.line(signSplitX, signY, signSplitX, signY + signBoxHeight);

  // Left Box: Declaration & Receiver
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(7.5);
  doc.text('Declaration:', margin + 2.5, signY + 4.5);

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(6.8);
  doc.text(
    'We declare that this Delivery Challan shows the actual quantity of goods\ndispatched and all serial numbers listed have been physically scanned\nand verified prior to warehouse release.',
    margin + 2.5,
    signY + 8.5
  );

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(7.5);
  doc.text("Customer / Receiver's Signature & Seal", margin + 2.5, signY + 24.5);

  // Right Box: Authorized Signatory
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(8);
  doc.text('for GLOBAL LOGISTICS', signSplitX + 3, signY + 5);

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(6.8);
  doc.text('(Central Warehouse Dispatch Authority)', signSplitX + 3, signY + 9);

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(7.5);
  doc.text('Authorised Signatory', margin + contentWidth - 3, signY + 24.5, { align: 'right' });

  // Page Numbers & Footer note
  const pageCount = doc.internal.getNumberOfPages();
  for (let i = 1; i <= pageCount; i++) {
    doc.setPage(i);
    doc.setFontSize(7);
    doc.setTextColor(60, 60, 60);
    doc.text(
      `This is a Computer Generated Delivery Challan | Bill #${bill.bill_number} | Page ${i} of ${pageCount}`,
      pageWidth / 2,
      292,
      { align: 'center' }
    );
  }

  return doc;
}

// CLI handler: reads JSON from file or stdin, outputs PDF to output path
if (require.main === module) {
  const inputArg = process.argv[2];
  const outputArg = process.argv[3];

  let billData;
  if (inputArg && inputArg !== '-') {
    billData = JSON.parse(fs.readFileSync(inputArg, 'utf8'));
  } else {
    billData = JSON.parse(fs.readFileSync(0, 'utf8'));
  }

  const doc = buildBillPdf(billData);
  const pdfBuffer = Buffer.from(doc.output('arraybuffer'));

  if (outputArg) {
    fs.writeFileSync(outputArg, pdfBuffer);
  } else {
    process.stdout.write(pdfBuffer);
  }
}

module.exports = { buildBillPdf };
