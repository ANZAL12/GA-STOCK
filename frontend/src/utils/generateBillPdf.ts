import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import type { BillDetail } from "../types";
import { LOGO_BASE64 } from "../assets/logoBase64";

export function generateBillPdf(bill: BillDetail): void {
  const doc = new jsPDF({
    orientation: "portrait",
    unit: "mm",
    format: "a4",
  });

  const pageWidth = doc.internal.pageSize.getWidth();

  // --- 1. HEADER SECTION ---
  doc.setFillColor(30, 27, 75); // Dark Indigo
  doc.rect(0, 0, pageWidth, 30, "F");

  // Render Emblem Logo
  let textStartX = 14;
  try {
    doc.addImage(LOGO_BASE64, "PNG", 14, 4, 22, 22);
    textStartX = 39;
  } catch (err) {
    console.warn("Could not load logo for PDF", err);
  }

  doc.setTextColor(255, 255, 255);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(16);
  doc.text("GLOBAL LOGISTICS", textStartX, 13);

  doc.setFont("helvetica", "normal");
  doc.setFontSize(8.5);
  doc.setTextColor(224, 231, 255);
  doc.text("CENTRAL WAREHOUSE DISPATCH BILL / DELIVERY CHALLAN", textStartX, 18.5);
  doc.text("Stock Management & Automated Serial Tracking System", textStartX, 23.5);

  // Bill badge on top right
  doc.setFillColor(255, 255, 255);
  doc.roundedRect(pageWidth - 70, 7, 56, 16, 2, 2, "F");
  doc.setTextColor(30, 27, 75);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(8);
  doc.text("BILL NO:", pageWidth - 66, 13);
  doc.setFontSize(10.5);
  doc.text(bill.bill_number, pageWidth - 66, 19.5);

  // --- 2. BILL & CONSIGNEE DETAILS CARD ---
  const startY = 36;
  doc.setDrawColor(226, 232, 240);
  doc.setFillColor(248, 250, 252);
  doc.roundedRect(14, startY, pageWidth - 28, 26, 2, 2, "FD");

  doc.setFontSize(8.5);
  doc.setTextColor(100, 116, 139);
  doc.setFont("helvetica", "bold");
  doc.text("DISPATCH TO (CONSIGNEE):", 18, startY + 6);
  doc.text("DISPATCH DETAILS:", 115, startY + 6);

  doc.setFont("helvetica", "bold");
  doc.setFontSize(10.5);
  doc.setTextColor(15, 23, 42);
  doc.text(bill.shop_name, 18, startY + 12);

  doc.setFont("helvetica", "normal");
  doc.setFontSize(9);
  doc.setTextColor(71, 85, 105);
  let leftInfoY = startY + 17;
  if (bill.shop_city && bill.shop_city.trim()) {
    doc.text(`City / Location: ${bill.shop_city.trim()}`, 18, leftInfoY);
    leftInfoY += 5;
  }
  if (bill.remarks) {
    doc.text(`Remarks: ${bill.remarks}`, 18, leftInfoY);
  }

  doc.text(`Date: ${bill.transaction_date}`, 115, startY + 12);
  doc.text(`Vehicle / Ref: ${bill.delivery_reference || "Direct / Local"}`, 115, startY + 17);
  doc.text(`Dispatched By: ${bill.dispatched_by_name}`, 115, startY + 22);

  // --- 3. MODEL QUANTITY BREAKDOWN TABLE ---
  let currentY = startY + 31;
  doc.setFont("helvetica", "bold");
  doc.setFontSize(10);
  doc.setTextColor(15, 23, 42);
  doc.text("1. Models & Quantities Dispatched", 14, currentY);

  const modelTableBody = bill.batches.map((b, idx) => [
    (idx + 1).toString(),
    b.brand,
    b.model,
    b.product_name,
    b.quantity.toString(),
  ]);

  // Append Total Row
  modelTableBody.push([
    "",
    "TOTAL",
    `${bill.batches.length} Model(s)`,
    "",
    bill.total_units.toString(),
  ]);

  autoTable(doc, {
    startY: currentY + 3,
    head: [["#", "Brand", "Model", "Description", "Quantity"]],
    body: modelTableBody,
    theme: "grid",
    headStyles: {
      fillColor: [60, 52, 137],
      textColor: [255, 255, 255],
      fontStyle: "bold",
      fontSize: 8.5,
    },
    bodyStyles: {
      fontSize: 8.5,
      textColor: [30, 41, 59],
    },
    columnStyles: {
      0: { cellWidth: 10, halign: "center" },
      1: { fontStyle: "bold", cellWidth: 35 },
      2: { fontStyle: "bold", cellWidth: 45 },
      3: { cellWidth: 62 },
      4: { halign: "center", fontStyle: "bold", cellWidth: 30 },
    },
    margin: { left: 14, right: 14 },
    didParseCell: (data) => {
      if (data.row.index === modelTableBody.length - 1) {
        data.cell.styles.fontStyle = "bold";
        data.cell.styles.fillColor = [241, 245, 249];
        data.cell.styles.textColor = [15, 23, 42];
      }
    },
  });

  // --- 4. INDIVIDUAL SERIAL NUMBERS REGISTER ---
  const lastTableY = (doc as any).lastAutoTable.finalY || currentY + 40;
  let serialsHeaderY = lastTableY + 8;

  // Check if we need a page break before serials table
  if (serialsHeaderY > 240) {
    doc.addPage();
    serialsHeaderY = 18;
  }

  doc.setFont("helvetica", "bold");
  doc.setFontSize(10);
  doc.setTextColor(15, 23, 42);
  doc.text("2.Serial Number Register", 14, serialsHeaderY);

  const serialRows: any[] = [];
  bill.batches.forEach((b, bIdx) => {
    // Model Header Row (Model shown once)
    const descText = b.product_name && b.product_name !== `${b.brand} ${b.model}` ? `  |  ${b.product_name}` : "";
    serialRows.push([
      {
        content: `${bIdx + 1}.  ${b.brand} - ${b.model}${descText}`,
        styles: {
          fillColor: [241, 245, 249],
          textColor: [15, 23, 42],
          fontStyle: "bold",
          fontSize: 8.5,
        },
      },
      {
        content: `${b.quantity} ${b.quantity === 1 ? "Unit" : "Units"}`,
        styles: {
          fillColor: [241, 245, 249],
          textColor: [60, 52, 137],
          fontStyle: "bold",
          fontSize: 8.5,
          halign: "right",
        },
      },
    ]);

    // Format serial numbers neatly below this model
    if (!b.lines || b.lines.length === 0) {
      serialRows.push([
        {
          content: "   No scanned serial numbers recorded",
          colSpan: 2,
          styles: {
            fontStyle: "italic",
            textColor: [148, 163, 184],
            fontSize: 8,
          },
        },
      ]);
    } else {
      const serialStrings = b.lines.map((l, lIdx) => {
        const uType = l.unit_type && l.unit_type.trim() ? ` [${l.unit_type.toUpperCase()}]` : "";
        return `${lIdx + 1}. ${l.serial_text}${uType}`;
      });

      // Group serial numbers 3 per line for clean reading
      const lines: string[] = [];
      for (let i = 0; i < serialStrings.length; i += 3) {
        lines.push(serialStrings.slice(i, i + 3).join("         "));
      }

      serialRows.push([
        {
          content: lines.join("\n"),
          colSpan: 2,
          styles: {
            font: "courier",
            fontSize: 8,
            textColor: [30, 41, 59],
            cellPadding: { top: 2.5, bottom: 3.5, left: 6, right: 6 },
          },
        },
      ]);
    }
  });

  autoTable(doc, {
    startY: serialsHeaderY + 3,
    head: [["Model Details", "Quantity"]],
    body: serialRows,
    theme: "grid",
    headStyles: {
      fillColor: [79, 70, 229],
      textColor: [255, 255, 255],
      fontStyle: "bold",
      fontSize: 8.5,
    },
    columnStyles: {
      0: { cellWidth: pageWidth - 28 - 28 },
      1: { cellWidth: 28, halign: "right" },
    },
    margin: { left: 14, right: 14 },
  });

  // --- 5. SIGNATURE & VERIFICATION SECTION ---
  const finalTableY = (doc as any).lastAutoTable.finalY || serialsHeaderY + 40;
  let signY = finalTableY + 12;

  if (signY > 250) {
    doc.addPage();
    signY = 30;
  }

  doc.setDrawColor(203, 213, 225);
  doc.line(14, signY + 15, 80, signY + 15);
  doc.line(pageWidth - 80, signY + 15, pageWidth - 14, signY + 15);

  doc.setFontSize(8.5);
  doc.setTextColor(71, 85, 105);
  doc.setFont("helvetica", "normal");
  doc.text("Receiver's Signature & Seal", 14, signY + 20);
  doc.text("Authorized Signatory (Global Logistics)", pageWidth - 14, signY + 20, { align: "right" });

  // Footer page numbers
  const pageCount = (doc.internal as any).getNumberOfPages();
  for (let i = 1; i <= pageCount; i++) {
    doc.setPage(i);
    doc.setFontSize(7.5);
    doc.setTextColor(148, 163, 184);
    doc.text(
      `Generated on ${new Date().toLocaleString()} • Bill #${bill.bill_number} • Page ${i} of ${pageCount}`,
      pageWidth / 2,
      290,
      { align: "center" }
    );
  }

  doc.save(`Bill_${bill.bill_number}.pdf`);
}
