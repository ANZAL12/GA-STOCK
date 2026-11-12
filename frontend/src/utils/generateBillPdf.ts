import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import type { BillDetail } from "../types";
import { LOGO_BASE64 } from "../assets/logoBase64";

/**
 * Builds an ink-saving, black & white Delivery Challan / Dispatch Bill PDF
 * styled similarly to Tally Prime invoices (crisp grid boxes, no solid color fills).
 */
export function buildBillPdf(bill: BillDetail): jsPDF {
  const doc = new jsPDF({
    orientation: "portrait",
    unit: "mm",
    format: "a4",
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
  const headerBoxHeight = 68;

  // Outer border of header
  doc.rect(margin, startY, contentWidth, headerBoxHeight);

  // Title Banner
  doc.setFont("helvetica", "bold");
  doc.setFontSize(12);
  const titleText = bill.is_cancelled ? "DELIVERY CHALLAN [CANCELLED]" : "DELIVERY CHALLAN";
  doc.text(titleText, pageWidth / 2, startY + 5.5, { align: "center" });

  doc.setFont("helvetica", "normal");
  doc.setFontSize(7.5);
  const subText = bill.is_cancelled
    ? "(THIS BILL HAS BEEN CANCELLED - RETURN SCAN PENDING)"
    : "(CENTRAL WAREHOUSE OUTWARD DISPATCH / STOCK TRANSFER VOUCHER)";
  doc.text(subText, pageWidth / 2, startY + 9.5, {
    align: "center",
  });

  // Divider line under title
  doc.line(margin, startY + 11.5, pageWidth - margin, startY + 11.5);

  // Vertical split between Consignor/Consignee (Left: 100mm) and Voucher Details (Right: 86mm)
  const splitX = margin + 100;
  doc.line(splitX, startY + 11.5, splitX, startY + headerBoxHeight);

  // Horizontal divider on the left side (dividing Dispatcher from Consignee)
  const leftMidY = startY + 28;
  doc.line(margin, leftMidY, splitX, leftMidY);

  // Left Top: Dispatcher / Consignor with Emblem Logo
  doc.setFont("helvetica", "bold");
  doc.setFontSize(6.8);
  doc.text("Consignor / Dispatcher:", margin + 2.5, startY + 15);

  let textStartX = margin + 2.5;
  try {
    doc.addImage(LOGO_BASE64, "PNG", margin + 2.5, startY + 16, 11, 11);
    textStartX = margin + 15.5;
  } catch (err) {
    console.warn("Could not load logo for PDF", err);
  }

  doc.setFontSize(9.5);
  doc.text("GLOBAL LOGISTICS", textStartX, startY + 20);

  doc.setFont("helvetica", "normal");
  doc.setFontSize(6.8);
  doc.text("Central Warehouse & Distribution", textStartX, startY + 23.8);
  doc.text("Stock Management & Automated Serial Register", textStartX, startY + 27);

  // Left Bottom: Consignee (Buyer / Dispatch To)
  doc.setFont("helvetica", "bold");
  doc.setFontSize(7);
  doc.text("Consignee / Buyer (Dispatch To):", margin + 2.5, leftMidY + 4);

  doc.setFontSize(9);
  doc.text(bill.shop_name, margin + 2.5, leftMidY + 8.5, {
    maxWidth: splitX - margin - 5,
  });

  let leftInfoY = leftMidY + 12.5;

  // Show GSTIN / UIN if available
  if (bill.shop_gstin && bill.shop_gstin.trim()) {
    doc.setFont("helvetica", "bold");
    doc.setFontSize(7.2);
    doc.text(`GSTIN / UIN: ${bill.shop_gstin.trim()}`, margin + 2.5, leftInfoY, {
      maxWidth: splitX - margin - 5,
    });
    leftInfoY += 3.8;
  }

  // Show complete Address if available
  if (bill.shop_address && bill.shop_address.trim()) {
    doc.setFont("helvetica", "normal");
    doc.setFontSize(6.8);
    const addrLines = doc.splitTextToSize(`Address: ${bill.shop_address.trim()}`, splitX - margin - 5);
    doc.text(addrLines, margin + 2.5, leftInfoY);
    leftInfoY += addrLines.length * 3.2;
  }

  // Show City, State & PIN
  const locParts: string[] = [];
  if (bill.shop_city && bill.shop_city.trim()) locParts.push(bill.shop_city.trim());
  if (bill.shop_state && bill.shop_state.trim()) locParts.push(`State: ${bill.shop_state.trim()}`);
  if (bill.shop_pincode && bill.shop_pincode.trim()) locParts.push(`PIN: ${bill.shop_pincode.trim()}`);
  if (locParts.length > 0) {
    doc.setFont("helvetica", "normal");
    doc.setFontSize(6.8);
    doc.text(`Location: ${locParts.join(", ")}`, margin + 2.5, leftInfoY, {
      maxWidth: splitX - margin - 5,
    });
    leftInfoY += 3.5;
  }

  // Show Phone & Contact Person if available
  const contactParts: string[] = [];
  if (bill.shop_phone && bill.shop_phone.trim()) contactParts.push(`Ph: ${bill.shop_phone.trim()}`);
  if (bill.shop_contact_person && bill.shop_contact_person.trim()) contactParts.push(`Attn: ${bill.shop_contact_person.trim()}`);
  if (contactParts.length > 0) {
    doc.setFont("helvetica", "normal");
    doc.setFontSize(6.8);
    doc.text(contactParts.join(" • "), margin + 2.5, leftInfoY, {
      maxWidth: splitX - margin - 5,
    });
    leftInfoY += 3.5;
  }

  // Show Remarks if available
  if (bill.remarks && bill.remarks.trim()) {
    doc.setFont("helvetica", "italic");
    doc.setFontSize(6.5);
    doc.text(`Remarks: ${bill.remarks.trim()}`, margin + 2.5, leftInfoY, {
      maxWidth: splitX - margin - 5,
    });
  }

  // Right Side: Tally Voucher Meta Details
  const labelX = splitX + 3;
  const valX = splitX + 31;
  const maxValWidth = pageWidth - margin - valX - 2;
  let rY = startY + 15.5;

  const addRightRow = (label: string, value: string, boldVal = true) => {
    doc.setFont("helvetica", "normal");
    doc.setFontSize(7.2);
    doc.text(label, labelX, rY);
    doc.setFont("helvetica", boldVal ? "bold" : "normal");
    doc.setFontSize(7.5);
    doc.text(value, valX, rY, { maxWidth: maxValWidth });
    rY += 4.8;
  };

  addRightRow("Challan / Bill No.:", bill.bill_number, true);
  if (bill.is_cancelled) {
    addRightRow("Voucher Status:", "CANCELLED", true);
  }
  addRightRow("Dated:", bill.transaction_date, true);
  addRightRow("Dispatched By:", bill.dispatched_by_name, true);

  const rawRef = bill.delivery_reference ? bill.delivery_reference.trim() : "";
  const isRefBillNo = rawRef.toLowerCase() === bill.bill_number.trim().toLowerCase() || rawRef.toLowerCase().startsWith("tally:");
  const vehicleVal = bill.vehicle_number || (!isRefBillNo && rawRef ? rawRef : "") || "Direct / Local";
  addRightRow("Vehicle / Reg No.:", vehicleVal, true);

  if (bill.transporter_name && bill.transporter_name.trim()) {
    addRightRow("Transporter:", bill.transporter_name.trim(), false);
  }

  if (bill.delivery_note && bill.delivery_note.trim()) {
    addRightRow("Delivery Note:", bill.delivery_note.trim(), false);
  }

  addRightRow("Mode of Transport:", "Road / Local Delivery", false);

  const destinationVal =
    bill.destination && bill.destination.trim()
      ? bill.destination.trim()
      : (bill.shop_city && bill.shop_city.trim() ? bill.shop_city.trim() : bill.shop_name);
  addRightRow("Destination:", destinationVal, false);

  // --- 2. TABLE 1: DESCRIPTION OF GOODS & QUANTITY BREAKDOWN ---
  let currentY = startY + headerBoxHeight + 4;
  doc.setFont("helvetica", "bold");
  doc.setFontSize(9);
  doc.text("1. Description of Goods Dispatched", margin, currentY);

  const modelTableBody: any[] = bill.batches.map((b, idx) => [
    (idx + 1).toString(),
    b.brand,
    b.model,
    b.product_name || "-",
    `${b.quantity} Units`,
  ]);

  // Append Total Row (Classic Tally Total Row)
  modelTableBody.push([
    "",
    "TOTAL",
    `${bill.batches.length} Model(s)`,
    "",
    `${bill.total_units} Units`,
  ]);

  autoTable(doc, {
    startY: currentY + 2,
    head: [["SI No.", "Brand", "Model", "Description / Specification", "Quantity"]],
    body: modelTableBody,
    theme: "grid",
    styles: {
      font: "helvetica",
      fontSize: 8,
      textColor: [0, 0, 0],
      lineColor: [0, 0, 0],
      lineWidth: 0.2,
      cellPadding: 2,
    },
    headStyles: {
      fillColor: [242, 242, 242], // Light gray header, no heavy ink
      textColor: [0, 0, 0],
      fontStyle: "bold",
      lineColor: [0, 0, 0],
      lineWidth: 0.25,
      halign: "left",
    },
    columnStyles: {
      0: { cellWidth: 14, halign: "center" },
      1: { cellWidth: 32, fontStyle: "bold" },
      2: { cellWidth: 42, fontStyle: "bold" },
      3: { cellWidth: 68 },
      4: { cellWidth: 30, halign: "right", fontStyle: "bold" },
    },
    margin: { left: margin, right: margin },
    didParseCell: (data) => {
      // Style total row with bold borders and subtle gray fill
      if (data.row.index === modelTableBody.length - 1) {
        data.cell.styles.fontStyle = "bold";
        data.cell.styles.fillColor = [242, 242, 242];
        data.cell.styles.textColor = [0, 0, 0];
      }
    },
  });

  // --- 3. TABLE 2:SERIAL NUMBER REGISTER (Tally Batch/Serial List) ---
  const lastTableY = (doc as any).lastAutoTable.finalY || currentY + 40;
  let serialsHeaderY = lastTableY + 6;

  if (serialsHeaderY > 235) {
    doc.addPage();
    serialsHeaderY = 16;
  }

  doc.setFont("helvetica", "bold");
  doc.setFontSize(9);
  doc.text("2.Serial Number Register", margin, serialsHeaderY);

  const serialRows: any[] = [];
  bill.batches.forEach((b, bIdx) => {
    const descText =
      b.product_name && b.product_name !== `${b.brand} ${b.model}` ? `  |  ${b.product_name}` : "";

    // Model Row Header (Shown once per model)
    serialRows.push([
      {
        content: `${bIdx + 1}.  ${b.brand} - ${b.model}${descText}`,
        styles: {
          fillColor: [242, 242, 242],
          textColor: [0, 0, 0],
          fontStyle: "bold",
          fontSize: 8.5,
          lineColor: [0, 0, 0],
          lineWidth: 0.2,
        },
      },
      {
        content: `${b.quantity} ${b.quantity === 1 ? "Unit" : "Units"}`,
        styles: {
          fillColor: [242, 242, 242],
          textColor: [0, 0, 0],
          fontStyle: "bold",
          fontSize: 8.5,
          halign: "right",
          lineColor: [0, 0, 0],
          lineWidth: 0.2,
        },
      },
    ]);

    // Serial numbers listed neatly below
    if (!b.lines || b.lines.length === 0) {
      serialRows.push([
        {
          content: "   No scanned serial numbers recorded for this batch",
          colSpan: 2,
          styles: {
            fontStyle: "italic",
            textColor: [80, 80, 80],
            fontSize: 7.5,
            fillColor: false,
            lineColor: [0, 0, 0],
            lineWidth: 0.2,
          },
        },
      ]);
    } else {
      const serialStrings = b.lines.map((l, lIdx) => {
        const isDual = l.unit_type && ["indoor", "outdoor", "idu", "odu"].includes(l.unit_type.trim().toLowerCase());
        const uType = isDual ? ` [${l.unit_type!.trim().toUpperCase()}]` : "";
        return `${lIdx + 1}.\u00A0${l.serial_text}${uType}`;
      });

      const maxLen = serialStrings.length > 0 ? Math.max(...serialStrings.map((s) => s.length)) : 0;
      const itemsPerLine = maxLen > 28 ? 2 : 3;
      const colWidth = itemsPerLine === 2 ? 52 : 34;

      const lines: string[] = [];
      for (let i = 0; i < serialStrings.length; i += itemsPerLine) {
        const rowItems = serialStrings.slice(i, i + itemsPerLine);
        if (rowItems.length === 1) {
          lines.push(rowItems[0]);
        } else {
          let rowStr = "";
          for (let c = 0; c < rowItems.length; c++) {
            if (c === rowItems.length - 1) {
              rowStr += rowItems[c];
            } else {
              rowStr += rowItems[c].padEnd(colWidth, " ");
            }
          }
          lines.push(rowStr);
        }
      }

      serialRows.push([
        {
          content: lines.join("\n"),
          colSpan: 2,
          styles: {
            font: "courier",
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
    head: [["Model Details & Serial Number Register", "Quantity"]],
    body: serialRows,
    theme: "grid",
    styles: {
      lineColor: [0, 0, 0],
      lineWidth: 0.2,
    },
    headStyles: {
      fillColor: [242, 242, 242],
      textColor: [0, 0, 0],
      fontStyle: "bold",
      fontSize: 8,
      lineColor: [0, 0, 0],
      lineWidth: 0.25,
    },
    columnStyles: {
      0: { cellWidth: contentWidth - 30 },
      1: { cellWidth: 30, halign: "right" },
    },
    margin: { left: margin, right: margin },
  });

  // --- 4. TALLY PRIME STYLE DECLARATION & SIGNATURE FOOTER ---
  const finalTableY = (doc as any).lastAutoTable.finalY || serialsHeaderY + 40;
  let signY = finalTableY + 6;

  if (signY > 255) {
    doc.addPage();
    signY = 16;
  }

  const signBoxHeight = 28;
  doc.rect(margin, signY, contentWidth, signBoxHeight);

  // Vertical divider in the signature box
  const signSplitX = margin + 105;
  doc.line(signSplitX, signY, signSplitX, signY + signBoxHeight);

  // Left Box: Declaration & Receiver
  doc.setFont("helvetica", "bold");
  doc.setFontSize(7.5);
  doc.text("Declaration:", margin + 2.5, signY + 4.5);

  doc.setFont("helvetica", "normal");
  doc.setFontSize(6.8);
  doc.text(
    "We declare that this Delivery Challan shows the actual quantity of goods\ndispatched and all serial numbers listed have been physically scanned\nand verified prior to warehouse release.",
    margin + 2.5,
    signY + 8.5
  );

  doc.setFont("helvetica", "bold");
  doc.setFontSize(7.5);
  doc.text("Customer / Receiver's Signature & Seal", margin + 2.5, signY + 24.5);

  // Right Box: Authorized Signatory
  doc.setFont("helvetica", "bold");
  doc.setFontSize(8);
  doc.text("for GLOBAL LOGISTICS", signSplitX + 3, signY + 5);

  doc.setFont("helvetica", "normal");
  doc.setFontSize(6.8);
  doc.text("(Central Warehouse Dispatch Authority)", signSplitX + 3, signY + 9);

  doc.setFont("helvetica", "bold");
  doc.setFontSize(7.5);
  doc.text("Authorised Signatory", margin + contentWidth - 3, signY + 24.5, { align: "right" });

  // Page Numbers & Footer note
  const pageCount = (doc.internal as any).getNumberOfPages();
  const pageHeight = doc.internal.pageSize.getHeight();
  for (let i = 1; i <= pageCount; i++) {
    doc.setPage(i);

    // Watermark on every page if bill is cancelled
    if (bill.is_cancelled) {
      doc.saveGraphicsState();
      doc.setGState(new (doc as any).GState({ opacity: 0.20 }));
      doc.setTextColor(220, 38, 38);
      doc.setFontSize(70);
      doc.setFont("helvetica", "bold");
      doc.text("CANCELLED", pageWidth / 2, pageHeight / 2, {
        align: "center",
        angle: 45,
      });
      doc.restoreGraphicsState();
    }

    doc.setFontSize(7);
    doc.setTextColor(60, 60, 60);
    doc.text(
      `This is a Computer Generated Delivery Challan | Bill #${bill.bill_number} | Page ${i} of ${pageCount}`,
      pageWidth / 2,
      292,
      { align: "center" }
    );
  }

  return doc;
}

/**
 * Downloads the Bill PDF to the user's computer.
 */
export function generateBillPdf(bill: BillDetail): void {
  const doc = buildBillPdf(bill);
  doc.save(`Bill_${bill.bill_number}.pdf`);
}

/**
 * Directly prints the Bill PDF using the browser's native print dialog.
 */
export function printBillPdf(bill: BillDetail): void {
  const doc = buildBillPdf(bill);
  doc.autoPrint();

  const blob = doc.output("blob");
  const blobUrl = URL.createObjectURL(blob);

  // Hidden iframe to trigger native browser print dialog without popup blocking
  const iframe = document.createElement("iframe");
  iframe.style.position = "fixed";
  iframe.style.right = "0";
  iframe.style.bottom = "0";
  iframe.style.width = "0";
  iframe.style.height = "0";
  iframe.style.border = "0";
  iframe.src = blobUrl;
  document.body.appendChild(iframe);

  iframe.onload = () => {
    setTimeout(() => {
      try {
        iframe.contentWindow?.focus();
        iframe.contentWindow?.print();
      } catch (err) {
        console.warn("Direct iframe print failed, opening in new window", err);
        window.open(blobUrl, "_blank");
      }
      setTimeout(() => {
        try {
          document.body.removeChild(iframe);
          URL.revokeObjectURL(blobUrl);
        } catch (_) {}
      }, 60000);
    }, 250);
  };
}
