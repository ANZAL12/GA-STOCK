import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import type { SerialListItem, SerialDetail } from "../types";
import { LOGO_BASE64 } from "../assets/logoBase64";

function triggerPrintOrSave(doc: jsPDF, filename: string, isPrint?: boolean): void {
  if (isPrint) {
    doc.autoPrint();
    const rawUrl = doc.output("bloburl");
    const blobUrl = typeof rawUrl === "string" ? rawUrl : (rawUrl as any).toString();
    const printWindow = window.open(blobUrl, "_blank");
    if (!printWindow) {
      // Fallback for popup blockers: use hidden iframe
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
        try {
          iframe.contentWindow?.focus();
          iframe.contentWindow?.print();
        } catch (e) {
          console.warn("Iframe print failed", e);
        }
        setTimeout(() => {
          document.body.removeChild(iframe);
          URL.revokeObjectURL(blobUrl);
        }, 60000);
      };
    }
  } else {
    doc.save(filename);
  }
}

/**
 * Generate PDF or trigger Print for the filtered / complete Serials Registry Table
 */
export function generateSerialListPdf(options: {
  items: SerialListItem[];
  filterLabel: string;
  searchQuery?: string;
  isPrint?: boolean;
}): void {
  const { items, filterLabel, searchQuery, isPrint } = options;

  const doc = new jsPDF({
    orientation: "landscape",
    unit: "mm",
    format: "a4",
  });

  const pageWidth = doc.internal.pageSize.getWidth();
  const pageHeight = doc.internal.pageSize.getHeight();

  // --- 1. HEADER SECTION ---
  doc.setFillColor(30, 27, 75); // Dark Indigo #1E1B4B
  doc.rect(0, 0, pageWidth, 28, "F");

  // Logo
  let textStartX = 14;
  try {
    doc.addImage(LOGO_BASE64, "PNG", 14, 3.5, 21, 21);
    textStartX = 39;
  } catch (err) {
    console.warn("Could not load logo for PDF", err);
  }

  // Header Title
  doc.setTextColor(255, 255, 255);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(15);
  doc.text("GLOBAL LOGISTICS", textStartX, 11);

  doc.setFont("helvetica", "normal");
  doc.setFontSize(8.5);
  doc.setTextColor(224, 231, 255);
  doc.text("CENTRAL WAREHOUSE SERIAL NUMBER REGISTRY & AUDIT REPORT", textStartX, 17);
  doc.text("Appliance Serial Inventory • Live Movement & Destination Tracking Log", textStartX, 22.5);

  // Header Right Metadata Badge
  const badgeWidth = 72;
  const badgeX = pageWidth - badgeWidth - 14;
  doc.setFillColor(255, 255, 255);
  doc.roundedRect(badgeX, 5, badgeWidth, 18, 2, 2, "F");

  doc.setTextColor(30, 27, 75);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(7.5);
  doc.text("REPORT GENERATED:", badgeX + 4, 10);
  doc.setFont("helvetica", "normal");
  doc.setFontSize(8);
  doc.text(new Date().toLocaleString("en-IN", { dateStyle: "medium", timeStyle: "short" }), badgeX + 4, 15);

  doc.setFont("helvetica", "bold");
  doc.setFontSize(7.5);
  doc.text(`FILTER: ${filterLabel.toUpperCase()} (${items.length} records)`, badgeX + 4, 20);

  // --- 2. SUMMARY METRICS STRIP ---
  const inwardCount = items.filter((s) => s.flow_type === "inward").length;
  const outwardCount = items.filter((s) => s.flow_type === "outward").length;
  const attentionCount = items.filter((s) => ["damaged", "under_repair", "lost"].includes(s.status)).length;

  const startY = 32;
  const cardWidth = (pageWidth - 28 - 9) / 4;
  const cardHeight = 12;

  const metrics = [
    { label: "TOTAL DISPLAYED", value: `${items.length}`, color: [30, 27, 75] },
    { label: "IN STOCK / INWARD", value: `${inwardCount}`, color: [5, 150, 105] },
    { label: "DISPATCHED / OUTWARD", value: `${outwardCount}`, color: [67, 56, 202] },
    { label: "ATTENTION / DAMAGED", value: `${attentionCount}`, color: [225, 29, 72] },
  ];

  metrics.forEach((m, idx) => {
    const cx = 14 + idx * (cardWidth + 3);
    doc.setFillColor(248, 250, 252);
    doc.setDrawColor(226, 232, 240);
    doc.roundedRect(cx, startY, cardWidth, cardHeight, 1.5, 1.5, "FD");

    doc.setFontSize(6.5);
    doc.setFont("helvetica", "bold");
    doc.setTextColor(100, 116, 139);
    doc.text(m.label, cx + 4, startY + 4.5);

    doc.setFontSize(10.5);
    doc.setTextColor(m.color[0], m.color[1], m.color[2]);
    doc.text(m.value, cx + 4, startY + 9.5);
  });

  if (searchQuery && searchQuery.trim()) {
    doc.setFontSize(7.5);
    doc.setFont("helvetica", "italic");
    doc.setTextColor(100, 116, 139);
    doc.text(`Active search query: "${searchQuery.trim()}"`, 14, startY + cardHeight + 4);
  }

  // --- 3. DATA TABLE ---
  const tableStartY = searchQuery && searchQuery.trim() ? startY + cardHeight + 6 : startY + cardHeight + 3;

  const tableRows = items.map((item, idx) => {
    const serialDisplay = item.unit_type
      ? `${item.serial_number} (${item.unit_type.charAt(0).toUpperCase() + item.unit_type.slice(1).toLowerCase()})`
      : item.serial_number;

    const dateStr = item.transaction_date
      ? new Date(item.transaction_date).toLocaleDateString("en-IN", { month: "short", day: "numeric", year: "numeric" })
      : new Date(item.created_at).toLocaleDateString("en-IN", { month: "short", day: "numeric", year: "numeric" });

    const shopDisplay = item.shop_name
      ? `${item.shop_name}${item.shop_city ? ` (${item.shop_city})` : ""}`
      : "In Godown";

    return [
      (idx + 1).toString(),
      serialDisplay,
      item.flow_type === "inward" ? "INWARD" : "OUTWARD",
      `${item.brand} ${item.model}`,
      item.category_name || "General",
      item.status_label || item.status.toUpperCase(),
      dateStr,
      shopDisplay,
      item.bill_number
        ? (item.delivery_reference && item.delivery_reference !== item.bill_number
            ? `${item.bill_number} (Veh: ${item.delivery_reference})`
            : item.bill_number)
        : (item.reference ? item.reference : "—"),
    ];
  });

  autoTable(doc, {
    startY: tableStartY,
    head: [
      [
        "#",
        "SERIAL NUMBER",
        "FLOW",
        "BRAND & MODEL",
        "CATEGORY",
        "STATUS",
        "DATE",
        "DESTINATION / SHOP",
        "REFERENCE",
      ],
    ],
    body: tableRows,
    theme: "striped",
    headStyles: {
      fillColor: [30, 27, 75],
      textColor: [255, 255, 255],
      fontStyle: "bold",
      fontSize: 8,
      cellPadding: 2.2,
      halign: "left",
    },
    styles: {
      fontSize: 7.5,
      textColor: [30, 41, 59],
      cellPadding: 2,
      lineColor: [226, 232, 240],
      lineWidth: 0.1,
    },
    alternateRowStyles: {
      fillColor: [248, 250, 252],
    },
    columnStyles: {
      0: { cellWidth: 10, halign: "center", fontStyle: "bold" },
      1: { cellWidth: 44, fontStyle: "bold" },
      2: { cellWidth: 22, halign: "center", fontStyle: "bold" },
      3: { cellWidth: 50 },
      4: { cellWidth: 32 },
      5: { cellWidth: 26, halign: "center" },
      6: { cellWidth: 28 },
      7: { cellWidth: 42 },
      8: { cellWidth: 25 },
    },
    didParseCell: (data) => {
      // Highlight Flow Column
      if (data.section === "body" && data.column.index === 2) {
        if (data.cell.raw === "INWARD") {
          data.cell.styles.textColor = [5, 150, 105]; // Emerald
        } else {
          data.cell.styles.textColor = [67, 56, 202]; // Indigo
        }
      }
      // Highlight Status Column
      if (data.section === "body" && data.column.index === 5) {
        const rawStr = String(data.cell.raw || "").toLowerCase();
        if (rawStr.includes("available") || rawStr.includes("stock")) {
          data.cell.styles.textColor = [5, 150, 105];
        } else if (rawStr.includes("dispatch")) {
          data.cell.styles.textColor = [67, 56, 202];
        } else if (rawStr.includes("damage") || rawStr.includes("lost") || rawStr.includes("repair")) {
          data.cell.styles.textColor = [225, 29, 72];
          data.cell.styles.fontStyle = "bold";
        }
      }
    },
    margin: { left: 14, right: 14, bottom: 20 },
  });

  // --- 4. SIGNATURE LINES & FOOTER ON LAST PAGE ---
  const finalTableY = (doc as any).lastAutoTable?.finalY || 160;
  let signY = finalTableY + 12;

  if (signY > pageHeight - 30) {
    doc.addPage();
    signY = 30;
  }

  doc.setDrawColor(203, 213, 225);
  doc.line(14, signY + 12, 85, signY + 12);
  doc.line(pageWidth - 85, signY + 12, pageWidth - 14, signY + 12);

  doc.setFontSize(8);
  doc.setTextColor(71, 85, 105);
  doc.setFont("helvetica", "normal");
  doc.text("Warehouse Supervisor / In-Charge", 14, signY + 16.5);
  doc.text("Authorized Signatory (Global Logistics)", pageWidth - 85, signY + 16.5);

  // --- 5. PAGE NUMBERS ACROSS ALL PAGES ---
  const pageCount = (doc.internal as any).getNumberOfPages();
  for (let i = 1; i <= pageCount; i++) {
    doc.setPage(i);
    doc.setFontSize(7.5);
    doc.setTextColor(148, 163, 184);
    doc.text(
      `Generated on ${new Date().toLocaleString("en-IN")} • Global Logistics Serial Registry • Page ${i} of ${pageCount}`,
      pageWidth / 2,
      pageHeight - 8,
      { align: "center" }
    );
  }

  const safeFilterName = filterLabel.toLowerCase().replace(/[^a-z0-9]/g, "_");
  const filename = `Serials_Registry_${safeFilterName}_${new Date().toISOString().slice(0, 10)}.pdf`;
  triggerPrintOrSave(doc, filename, isPrint);
}

/**
 * Generate PDF or trigger Print for an individual Serial Trace & Lifecycle
 */
export function generateSerialTracePdf(options: {
  serial: SerialDetail;
  isPrint?: boolean;
}): void {
  const { serial, isPrint } = options;

  const doc = new jsPDF({
    orientation: "portrait",
    unit: "mm",
    format: "a4",
  });

  const pageWidth = doc.internal.pageSize.getWidth();
  const pageHeight = doc.internal.pageSize.getHeight();

  // --- 1. HEADER SECTION ---
  doc.setFillColor(30, 27, 75);
  doc.rect(0, 0, pageWidth, 28, "F");

  // Logo
  let textStartX = 14;
  try {
    doc.addImage(LOGO_BASE64, "PNG", 14, 3.5, 21, 21);
    textStartX = 39;
  } catch (err) {
    console.warn("Could not load logo for PDF", err);
  }

  doc.setTextColor(255, 255, 255);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(15);
  doc.text("GLOBAL LOGISTICS", textStartX, 11);

  doc.setFont("helvetica", "normal");
  doc.setFontSize(8.5);
  doc.setTextColor(224, 231, 255);
  doc.text("APPLIANCE SERIAL LIFECYCLE & MOVEMENT AUDIT TRACE", textStartX, 17);
  doc.text("Central Warehouse Real-Time Inventory Tracking System", textStartX, 22.5);

  // Badge on top right
  const badgeWidth = 62;
  const badgeX = pageWidth - badgeWidth - 14;
  doc.setFillColor(255, 255, 255);
  doc.roundedRect(badgeX, 5, badgeWidth, 18, 2, 2, "F");

  doc.setTextColor(30, 27, 75);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(7.5);
  doc.text("AUDIT REPORT DATE:", badgeX + 4, 10);
  doc.setFont("helvetica", "normal");
  doc.setFontSize(8);
  doc.text(new Date().toLocaleString("en-IN", { dateStyle: "medium", timeStyle: "short" }), badgeX + 4, 15);

  doc.setFont("helvetica", "bold");
  doc.setFontSize(8);
  doc.setTextColor(5, 150, 105);
  doc.text(`STATUS: ${(serial.status_label || serial.status || "UNKNOWN").toUpperCase()}`, badgeX + 4, 20);

  // --- 2. SERIAL SUMMARY CARD ---
  const startY = 33;
  doc.setFillColor(248, 250, 252);
  doc.setDrawColor(226, 232, 240);
  doc.roundedRect(14, startY, pageWidth - 28, 36, 2, 2, "FD");

  doc.setFontSize(8);
  doc.setFont("helvetica", "bold");
  doc.setTextColor(100, 116, 139);
  doc.text("SERIAL NUMBER:", 18, startY + 7);
  doc.text("PRODUCT / MODEL:", 100, startY + 7);

  doc.setFontSize(13);
  doc.setFont("helvetica", "bold");
  doc.setTextColor(30, 27, 75);
  doc.text(serial.serial_number, 18, startY + 13.5);

  doc.setFontSize(10);
  doc.text(`${serial.brand || ""} ${serial.model || ""}`.trim() || "—", 100, startY + 13.5);

  doc.setFontSize(8);
  doc.setFont("helvetica", "normal");
  doc.setTextColor(100, 116, 139);
  if (serial.unit_type) {
    doc.text(`Unit Type: ${serial.unit_type.toUpperCase()}`, 18, startY + 19);
  }
  doc.text(`Product Name: ${serial.product_name || "—"}`, 100, startY + 19);

  // Bottom row inside card
  doc.setDrawColor(226, 232, 240);
  doc.line(18, startY + 23, pageWidth - 18, startY + 23);

  doc.setFontSize(7.5);
  doc.setTextColor(100, 116, 139);
  doc.text("CATEGORY:", 18, startY + 28);
  doc.text("CURRENT LOCATION / SHOP:", 75, startY + 28);
  doc.text("SYSTEM RECORD TYPE:", 145, startY + 28);

  doc.setFontSize(8.5);
  doc.setFont("helvetica", "bold");
  doc.setTextColor(30, 41, 59);
  doc.text(serial.category_name || "General Appliance", 18, startY + 32.5);

  const locText = serial.last_shop_name
    ? `${serial.last_shop_name}${serial.last_shop_city ? ` (${serial.last_shop_city})` : ""}`
    : "In Central Godown (Available)";
  doc.text(locText, 75, startY + 32.5);

  doc.text(serial.is_tracked ? "Tracked Full Inventory" : "Pre-Go-Live Stock", 145, startY + 32.5);

  // --- 3. LIFECYCLE AUDIT TRAIL TABLE ---
  const tableStartY = startY + 42;

  const historyRows = (serial.history || []).map((h, idx) => {
    const timeStr = h.created_at
      ? new Date(h.created_at).toLocaleString("en-IN", {
          month: "short",
          day: "numeric",
          year: "numeric",
          hour: "2-digit",
          minute: "2-digit",
        })
      : "—";

    const statusTransition =
      h.from_status && h.to_status
        ? `${h.from_status} → ${h.to_status}`
        : h.to_status || h.from_status || "—";

    const loc = h.shop_name
      ? `${h.shop_name}${h.shop_city ? ` (${h.shop_city})` : ""}`
      : "Central Godown";

    return [
      (idx + 1).toString(),
      (h.action || "EVENT").toUpperCase(),
      timeStr,
      statusTransition.toUpperCase(),
      loc,
      h.user_name || "System",
      h.remarks || "—",
    ];
  });

  autoTable(doc, {
    startY: tableStartY,
    head: [
      [
        "#",
        "ACTION",
        "DATE & TIME",
        "STATUS TRANSITION",
        "LOCATION / SHOP",
        "STAFF",
        "REMARKS",
      ],
    ],
    body: historyRows,
    theme: "striped",
    headStyles: {
      fillColor: [30, 27, 75],
      textColor: [255, 255, 255],
      fontStyle: "bold",
      fontSize: 8,
      cellPadding: 2.5,
    },
    styles: {
      fontSize: 7.5,
      textColor: [30, 41, 59],
      cellPadding: 2.2,
      lineColor: [226, 232, 240],
      lineWidth: 0.1,
    },
    alternateRowStyles: {
      fillColor: [248, 250, 252],
    },
    columnStyles: {
      0: { cellWidth: 8, halign: "center", fontStyle: "bold" },
      1: { cellWidth: 26, fontStyle: "bold" },
      2: { cellWidth: 35 },
      3: { cellWidth: 32, fontStyle: "bold" },
      4: { cellWidth: 35 },
      5: { cellWidth: 22 },
      6: { cellWidth: 24 },
    },
    margin: { left: 14, right: 14, bottom: 20 },
  });

  // --- 4. SIGNATURES & VERIFICATION ---
  const finalTableY = (doc as any).lastAutoTable?.finalY || 180;
  let signY = finalTableY + 15;

  if (signY > pageHeight - 35) {
    doc.addPage();
    signY = 30;
  }

  doc.setDrawColor(203, 213, 225);
  doc.line(14, signY + 12, 75, signY + 12);
  doc.line(pageWidth - 75, signY + 12, pageWidth - 14, signY + 12);

  doc.setFontSize(8);
  doc.setTextColor(71, 85, 105);
  doc.setFont("helvetica", "normal");
  doc.text("Audited By / Warehouse In-Charge", 14, signY + 16.5);
  doc.text("Authorized Signatory (Global Logistics)", pageWidth - 75, signY + 16.5);

  // Page numbering
  const pageCount = (doc.internal as any).getNumberOfPages();
  for (let i = 1; i <= pageCount; i++) {
    doc.setPage(i);
    doc.setFontSize(7.5);
    doc.setTextColor(148, 163, 184);
    doc.text(
      `Generated on ${new Date().toLocaleString("en-IN")} • Serial #${serial.serial_number} Lifecycle • Page ${i} of ${pageCount}`,
      pageWidth / 2,
      pageHeight - 8,
      { align: "center" }
    );
  }

  const filename = `Serial_Trace_${serial.serial_number}.pdf`;
  triggerPrintOrSave(doc, filename, isPrint);
}
