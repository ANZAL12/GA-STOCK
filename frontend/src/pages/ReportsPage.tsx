import React, { useEffect, useRef, useState } from "react";
import { apiRequest } from "../api/client";
import { Badge } from "../components/Badge";
import { Modal } from "../components/Modal";
import type {
  Category,
  Shop,
  Product,
  StockByModelItem,
  StockOutReportItem,
  DamagedReportItem,
  AuditLogItem,
  GodownPrintReportRequest,
} from "../types";
import {
  Printer,
  FileText,
  FileSpreadsheet,
  FileDown,
  Eye,
  AlertCircle,
  AlertTriangle,
  Calendar,
  Package,
  Truck,
  Wrench,
  ClipboardCheck,
  Search,
  X,
  Layers,
  ExternalLink,
  SlidersHorizontal,
  Table,
  Check,
  Info,
} from "lucide-react";

type MainViewMode = "godown_print" | "raw_tables";
type ReportTab = "stock_by_model" | "stock_out" | "unmatched" | "damaged" | "audit";

interface GodownReportConfig {
  id: string;
  title: string;
  subtitle: string;
  badge: string;
  icon: React.ElementType;
  themeColor: string;
  bgClass: string;
  textClass: string;
  borderClass: string;
}

const GODOWN_REPORTS: GodownReportConfig[] = [
  {
    id: "today_inward_serials",
    title: "Inward Serial Register",
    subtitle: "Serials inwarded based on date, grouped by model with timestamps & inward type",
    badge: "Inward Register",
    icon: ClipboardCheck,
    themeColor: "#4F46E5",
    bgClass: "bg-indigo-50",
    textClass: "text-indigo-700",
    borderClass: "border-indigo-200",
  },
  {
    id: "stock_by_model",
    title: "Stock by Model Report",
    subtitle: "Available stock, dispatches, damaged, and negative alert counts",
    badge: "Inventory Balance",
    icon: Package,
    themeColor: "#3C3489",
    bgClass: "bg-[#3C3489]/10",
    textClass: "text-[#3C3489]",
    borderClass: "border-[#3C3489]/30",
  },
  {
    id: "stock_out",
    title: "Stock Out Dispatch Report",
    subtitle: "All dispatches with shop, delivery ref, and match status",
    badge: "Dispatches & Delivery",
    icon: Truck,
    themeColor: "#D97706",
    bgClass: "bg-amber-50",
    textClass: "text-amber-700",
    borderClass: "border-amber-200",
  },
  {
    id: "today_summary",
    title: "Today's Operations Summary",
    subtitle: "Concise log of today's inward batches and outward shop deliveries",
    badge: "Daily Operations",
    icon: Calendar,
    themeColor: "#059669",
    bgClass: "bg-emerald-50",
    textClass: "text-emerald-700",
    borderClass: "border-emerald-200",
  },
  {
    id: "unmatched_outward",
    title: "Unmatched Outward Report",
    subtitle: "Pre-go-live stock dispatches (scanned out without inward record)",
    badge: "Pre-Go-Live Stock",
    icon: AlertTriangle,
    themeColor: "#EA580C",
    bgClass: "bg-orange-50",
    textClass: "text-orange-700",
    borderClass: "border-orange-200",
  },
  {
    id: "damaged",
    title: "Damaged & Under Repair Report",
    subtitle: "Units flagged as damaged or under-repair awaiting action",
    badge: "Quality & Service",
    icon: Wrench,
    themeColor: "#E11D48",
    bgClass: "bg-rose-50",
    textClass: "text-rose-700",
    borderClass: "border-rose-200",
  },
];

const getTodayStr = () => {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
};

const formatDateDisplay = (dateStr: string) => {
  if (!dateStr) return "-";
  const [y, m, d] = dateStr.split("-").map(Number);
  const date = new Date(y, m - 1, d);
  return date.toLocaleDateString("en-IN", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
};

export const ReportsPage: React.FC = () => {
  // Main view toggle
  const [mainView, setMainView] = useState<MainViewMode>("godown_print");

  // Selected Godown Report Type
  const [selectedReportType, setSelectedReportType] = useState<string>("today_inward_serials");

  // Date Filters
  const [dateFrom, setDateFrom] = useState<string>(getTodayStr());
  const [dateTo, setDateTo] = useState<string>(getTodayStr());

  // Model & Search Filters
  const [products, setProducts] = useState<Product[]>([]);
  const [selectedProduct, setSelectedProduct] = useState<Product | null>(null);
  const [modelSearchQuery, setModelSearchQuery] = useState("");

  // Inward & Shop Filters
  const [selectedInwardType, setSelectedInwardType] = useState<string>("");
  const [shops, setShops] = useState<Shop[]>([]);
  const [selectedShop, setSelectedShop] = useState<Shop | null>(null);

  // Preview & Print Execution States
  const [isPreviewing, setIsPreviewing] = useState(false);
  const [isPrinting, setIsPrinting] = useState(false);
  const [printError, setPrintError] = useState<string | null>(null);

  // Hidden print iframe and preview iframe
  const hiddenPrintIframeRef = useRef<HTMLIFrameElement | null>(null);
  const previewIframeRef = useRef<HTMLIFrameElement | null>(null);

  // Preview Modal State
  const [previewModalOpen, setPreviewModalOpen] = useState(false);
  const [previewBlobUrl, setPreviewBlobUrl] = useState<string | null>(null);
  const [previewTitle, setPreviewTitle] = useState("A4 Godown Report");

  // Raw Tables State (for second view)
  const [activeTab, setActiveTab] = useState<ReportTab>("stock_by_model");
  const [categories, setCategories] = useState<Category[]>([]);
  const [tableCategory, setTableCategory] = useState<string>("");
  const [tableShop, setTableShop] = useState<string>("");
  const [tableProduct, setTableProduct] = useState<string>("");
  const [tableDateFrom, setTableDateFrom] = useState<string>("");
  const [tableDateTo, setTableDateTo] = useState<string>("");
  const [matchedFilter, setMatchedFilter] = useState<string>("all");
  const [auditAction, setAuditAction] = useState<string>("");
  const [auditEntity, setAuditEntity] = useState<string>("");
  const [tableLoading, setTableLoading] = useState(false);
  const [exportingFormat, setExportingFormat] = useState<string | null>(null);
  const [stockByModel, setStockByModel] = useState<StockByModelItem[]>([]);
  const [stockOutData, setStockOutData] = useState<StockOutReportItem[]>([]);
  const [unmatchedData, setUnmatchedData] = useState<StockOutReportItem[]>([]);
  const [damagedData, setDamagedData] = useState<DamagedReportItem[]>([]);
  const [auditData, setAuditData] = useState<AuditLogItem[]>([]);
  const [tableError, setTableError] = useState<string | null>(null);

  // Load Catalogs on Mount
  useEffect(() => {
    const loadCatalogs = async () => {
      try {
        const [cats, shps, prds] = await Promise.all([
          apiRequest<Category[]>("/categories"),
          apiRequest<Shop[]>("/shops"),
          apiRequest<Product[]>("/products"),
        ]);
        setCategories(cats);
        setShops(shps);
        setProducts(prds);
      } catch (err) {
        console.error("Failed to load catalogs", err);
      }
    };
    loadCatalogs();
  }, []);

  // Quick Preset Date Helpers
  const handleQuickPreset = (preset: "today" | "yesterday" | "last_7_days" | "this_month") => {
    const now = new Date();
    const today = getTodayStr();

    if (preset === "today") {
      setDateFrom(today);
      setDateTo(today);
    } else if (preset === "yesterday") {
      const y = new Date(now);
      y.setDate(y.getDate() - 1);
      const yStr = y.toISOString().split("T")[0];
      setDateFrom(yStr);
      setDateTo(yStr);
    } else if (preset === "last_7_days") {
      const d7 = new Date(now);
      d7.setDate(d7.getDate() - 6);
      setDateFrom(d7.toISOString().split("T")[0]);
      setDateTo(today);
    } else if (preset === "this_month") {
      const m1 = new Date(now.getFullYear(), now.getMonth(), 1);
      const m1Str = `${m1.getFullYear()}-${String(m1.getMonth() + 1).padStart(2, "0")}-01`;
      setDateFrom(m1Str);
      setDateTo(today);
    }
  };

  // Build Payload
  const getGodownPayload = (): GodownPrintReportRequest => {
    return {
      report_type: selectedReportType,
      product_id: selectedProduct?.id || null,
      shop_id: selectedShop?.id || null,
      date_from: selectedReportType === "stock_by_model" ? null : dateFrom || null,
      date_to: selectedReportType === "stock_by_model" ? null : dateTo || null,
      inward_type: selectedReportType === "today_inward_serials" ? selectedInwardType || null : null,
    };
  };

  const getActiveReportConfig = () => {
    return GODOWN_REPORTS.find((r) => r.id === selectedReportType) || GODOWN_REPORTS[0];
  };

  // Preview Exact A4 Report in Modal
  const handlePreviewA4 = async () => {
    try {
      setIsPreviewing(true);
      setPrintError(null);
      const payload = getGodownPayload();
      const blob = await apiRequest<Blob>("/print/godown-report/preview", {
        method: "POST",
        body: JSON.stringify(payload),
      });

      if (previewBlobUrl) {
        window.URL.revokeObjectURL(previewBlobUrl);
      }
      const url = window.URL.createObjectURL(blob);
      setPreviewBlobUrl(url);
      setPreviewTitle(getActiveReportConfig().title);
      setPreviewModalOpen(true);
    } catch (err: any) {
      setPrintError(`Preview generation failed: ${err.message || "Unknown error"}`);
    } finally {
      setIsPreviewing(false);
    }
  };

  // Direct Local Browser Print (opens native print dialog on this PC)
  const handleLocalPrint = async () => {
    try {
      setIsPrinting(true);
      setPrintError(null);
      const payload = getGodownPayload();
      const blob = await apiRequest<Blob>("/print/godown-report/preview", {
        method: "POST",
        body: JSON.stringify(payload),
      });

      const blobUrl = window.URL.createObjectURL(blob);

      let iframe = hiddenPrintIframeRef.current;
      if (!iframe) {
        iframe = document.createElement("iframe");
        iframe.style.position = "fixed";
        iframe.style.right = "0";
        iframe.style.bottom = "0";
        iframe.style.width = "0";
        iframe.style.height = "0";
        iframe.style.border = "0";
        document.body.appendChild(iframe);
        hiddenPrintIframeRef.current = iframe;
      }

      iframe.src = blobUrl;
      iframe.onload = () => {
        setTimeout(() => {
          try {
            iframe?.contentWindow?.focus();
            iframe?.contentWindow?.print();
          } catch {
            window.open(blobUrl, "_blank");
          }
        }, 150);
      };
    } catch (err: any) {
      setPrintError(`Print failed: ${err.message || "Unknown error"}`);
    } finally {
      setIsPrinting(false);
    }
  };

  // Direct PDF Download
  const handleDirectDownloadPdf = async () => {
    try {
      setIsPreviewing(true);
      const payload = getGodownPayload();
      const blob = await apiRequest<Blob>("/print/godown-report/preview", {
        method: "POST",
        body: JSON.stringify(payload),
      });

      const blobUrl = window.URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = blobUrl;
      a.download = `${selectedReportType}_${getTodayStr()}.pdf`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      window.URL.revokeObjectURL(blobUrl);
    } catch (err: any) {
      alert(`Download failed: ${err.message}`);
    } finally {
      setIsPreviewing(false);
    }
  };

  // Filtered Products for Model Search Dropdown
  const matchingProducts = modelSearchQuery.trim()
    ? products
        .filter((p) => {
          const q = modelSearchQuery.toLowerCase().trim();
          return (
            p.brand.toLowerCase().includes(q) ||
            p.model.toLowerCase().includes(q) ||
            p.name.toLowerCase().includes(q)
          );
        })
        .slice(0, 10)
    : [];

  // -------------------------------------------------------------
  // Raw Data Tables Handlers (Preserving original functionality)
  // -------------------------------------------------------------
  const fetchTableData = async () => {
    try {
      setTableLoading(true);
      setTableError(null);

      if (activeTab === "stock_by_model") {
        const query = tableCategory ? `?category_id=${tableCategory}` : "";
        const data = await apiRequest<StockByModelItem[]>(`/reports/stock-by-model${query}`);
        setStockByModel(data);
      } else if (activeTab === "stock_out") {
        const params = new URLSearchParams();
        if (tableShop) params.append("shop_id", tableShop);
        if (tableProduct) params.append("product_id", tableProduct);
        if (tableDateFrom) params.append("date_from", tableDateFrom);
        if (tableDateTo) params.append("date_to", tableDateTo);
        if (matchedFilter === "matched") params.append("is_matched", "true");
        if (matchedFilter === "unmatched") params.append("is_matched", "false");
        const qs = params.toString() ? `?${params.toString()}` : "";
        const data = await apiRequest<StockOutReportItem[]>(`/reports/stock-out${qs}`);
        setStockOutData(data);
      } else if (activeTab === "unmatched") {
        const params = new URLSearchParams();
        if (tableShop) params.append("shop_id", tableShop);
        if (tableProduct) params.append("product_id", tableProduct);
        if (tableDateFrom) params.append("date_from", tableDateFrom);
        if (tableDateTo) params.append("date_to", tableDateTo);
        const qs = params.toString() ? `?${params.toString()}` : "";
        const data = await apiRequest<StockOutReportItem[]>(`/reports/unmatched-outward${qs}`);
        setUnmatchedData(data);
      } else if (activeTab === "damaged") {
        const query = tableProduct ? `?product_id=${tableProduct}` : "";
        const data = await apiRequest<DamagedReportItem[]>(`/reports/damaged${query}`);
        setDamagedData(data);
      } else if (activeTab === "audit") {
        const params = new URLSearchParams();
        if (auditAction) params.append("action", auditAction);
        if (auditEntity) params.append("entity_type", auditEntity);
        if (tableDateFrom) params.append("date_from", tableDateFrom);
        if (tableDateTo) params.append("date_to", tableDateTo);
        params.append("limit", "200");
        const qs = `?${params.toString()}`;
        const data = await apiRequest<AuditLogItem[]>(`/audit${qs}`);
        setAuditData(data);
      }
    } catch (err: any) {
      setTableError(err.message || "Failed to load report data");
    } finally {
      setTableLoading(false);
    }
  };

  useEffect(() => {
    if (mainView === "raw_tables") {
      fetchTableData();
    }
  }, [
    mainView,
    activeTab,
    tableCategory,
    tableShop,
    tableProduct,
    tableDateFrom,
    tableDateTo,
    matchedFilter,
    auditAction,
    auditEntity,
  ]);

  const handleExportRawFormat = async (format: "csv" | "xlsx" | "pdf") => {
    try {
      setExportingFormat(format);
      let endpoint = "";
      const params = new URLSearchParams();
      params.append("export", format);

      if (activeTab === "stock_by_model") {
        endpoint = "/reports/stock-by-model";
        if (tableCategory) params.append("category_id", tableCategory);
      } else if (activeTab === "stock_out") {
        endpoint = "/reports/stock-out";
        if (tableShop) params.append("shop_id", tableShop);
        if (tableProduct) params.append("product_id", tableProduct);
        if (tableDateFrom) params.append("date_from", tableDateFrom);
        if (tableDateTo) params.append("date_to", tableDateTo);
        if (matchedFilter === "matched") params.append("is_matched", "true");
        if (matchedFilter === "unmatched") params.append("is_matched", "false");
      } else if (activeTab === "unmatched") {
        endpoint = "/reports/unmatched-outward";
        if (tableShop) params.append("shop_id", tableShop);
        if (tableProduct) params.append("product_id", tableProduct);
        if (tableDateFrom) params.append("date_from", tableDateFrom);
        if (tableDateTo) params.append("date_to", tableDateTo);
      } else if (activeTab === "damaged") {
        endpoint = "/reports/damaged";
        if (tableProduct) params.append("product_id", tableProduct);
      } else if (activeTab === "audit") {
        endpoint = "/audit";
        if (auditAction) params.append("action", auditAction);
        if (auditEntity) params.append("entity_type", auditEntity);
        if (tableDateFrom) params.append("date_from", tableDateFrom);
        if (tableDateTo) params.append("date_to", tableDateTo);
      }

      const url = `${endpoint}?${params.toString()}`;
      const blob = await apiRequest<Blob>(url);

      const blobUrl = window.URL.createObjectURL(blob);
      const link = document.createElement("a");
      const dateStr = getTodayStr();
      link.href = blobUrl;
      link.download = `${activeTab}_report_${dateStr}.${format}`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(blobUrl);
    } catch (err: any) {
      alert(`Export failed: ${err.message || "Unknown error"}`);
    } finally {
      setExportingFormat(null);
    }
  };

  const isSingleDay = dateFrom === dateTo;
  const daysDifference =
    Math.round(
      (new Date(dateTo).getTime() - new Date(dateFrom).getTime()) / (1000 * 60 * 60 * 24)
    ) + 1;

  return (
    <div className="space-y-6 animate-fade-in pb-16">
      
      {/* Top Header Card */}
      <div className="bg-white border border-slate-200/90 rounded-2xl p-6 shadow-sm flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4">
        <div>
          <div className="flex items-center gap-2.5 flex-wrap">
            <h1 className="text-2xl font-bold text-slate-900 tracking-tight">
              Godown Stock & Operations Reports
            </h1>
            <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-indigo-50 text-[#3C3489] border border-indigo-200">
              <Printer size={12} />
              Instant A4 Print & PDF
            </span>
          </div>
          <p className="text-xs text-slate-500 font-medium mt-1">
            Generate exact A4 stock reports, preview layouts, print directly on local warehouse printers, or export official spreadsheets.
          </p>
        </div>

        {/* View Switcher Tabs (Godown Report Generator vs Raw Data Tables) */}
        <div className="flex items-center gap-1.5 p-1 bg-slate-100 rounded-xl w-fit text-xs font-semibold self-start lg:self-auto">
          <button
            onClick={() => setMainView("godown_print")}
            className={`flex items-center gap-1.5 px-3.5 py-2 rounded-lg transition-all cursor-pointer ${
              mainView === "godown_print"
                ? "bg-white text-[#3C3489] shadow-sm font-bold"
                : "text-slate-600 hover:text-slate-900"
            }`}
          >
            <Printer size={14} />
            <span>Godown Reports & Print</span>
          </button>
          <button
            onClick={() => setMainView("raw_tables")}
            className={`flex items-center gap-1.5 px-3.5 py-2 rounded-lg transition-all cursor-pointer ${
              mainView === "raw_tables"
                ? "bg-white text-slate-900 shadow-sm font-bold"
                : "text-slate-600 hover:text-slate-900"
            }`}
          >
            <Table size={14} />
            <span>Interactive Tables & Audit</span>
          </button>
        </div>
      </div>

      {/* ───────────────────────────────────────────────────────────────────────────── */}
      {/* 1. GODOWN STOCK REPORTS & LOCAL PRINT VIEW                                    */}
      {/* ───────────────────────────────────────────────────────────────────────────── */}
      {mainView === "godown_print" && (
        <div className="space-y-6">

          {printError && (
            <div className="p-4 rounded-xl bg-rose-50 border border-rose-200 text-rose-800 text-xs flex items-center justify-between gap-3 animate-fade-in shadow-xs">
              <div className="flex items-center gap-2.5">
                <AlertCircle size={18} className="text-rose-600 shrink-0" />
                <span className="font-semibold">{printError}</span>
              </div>
              <button
                onClick={() => setPrintError(null)}
                className="text-rose-600 hover:text-rose-900 cursor-pointer"
              >
                <X size={15} />
              </button>
            </div>
          )}

          {/* Grid Layout: Left Column (Report Selector Cards), Right Column (Filters & Action Panel) */}
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">

            {/* Left 7 Columns: Report Selection Cards (The 6 Mobile Reports) */}
            <div className="lg:col-span-7 space-y-3">
              <div className="flex items-center justify-between text-xs font-bold uppercase tracking-wider text-slate-500">
                <div className="flex items-center gap-2">
                  <FileText size={15} className="text-[#3C3489]" />
                  <span>Select Godown Report</span>
                </div>
                <span className="text-[11px] text-slate-400 font-normal">
                  Standard A4 Print Layouts
                </span>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                {GODOWN_REPORTS.map((report) => {
                  const isSelected = selectedReportType === report.id;
                  const IconComp = report.icon;
                  return (
                    <div
                      key={report.id}
                      onClick={() => setSelectedReportType(report.id)}
                      className={`p-4 rounded-2xl border transition-all cursor-pointer flex flex-col justify-between ${
                        isSelected
                          ? "bg-white shadow-md ring-2 ring-[#3C3489] border-[#3C3489]"
                          : "bg-white border-slate-200 hover:border-slate-300 hover:shadow-xs"
                      }`}
                    >
                      <div>
                        <div className="flex items-start justify-between gap-2 mb-2">
                          <div className={`w-8 h-8 rounded-lg flex items-center justify-center ${report.bgClass} ${report.textClass}`}>
                            <IconComp size={18} />
                          </div>
                          <span
                            className={`w-4 h-4 rounded-full border flex items-center justify-center transition-all ${
                              isSelected
                                ? "border-[#3C3489] bg-[#3C3489] text-white"
                                : "border-slate-300 bg-white"
                            }`}
                          >
                            {isSelected && <Check size={11} strokeWidth={3} />}
                          </span>
                        </div>

                        <h3 className={`text-xs font-bold ${isSelected ? "text-slate-900" : "text-slate-800"}`}>
                          {report.title}
                        </h3>
                        <p className="text-[11px] text-slate-500 mt-1 line-clamp-2 leading-relaxed">
                          {report.subtitle}
                        </p>
                      </div>

                      <div className="mt-3 pt-2.5 border-t border-slate-100 flex items-center justify-between text-[10px]">
                        <span className={`font-semibold px-2 py-0.5 rounded-full ${report.bgClass} ${report.textClass}`}>
                          {report.badge}
                        </span>
                        <span className="text-slate-400 font-medium">Exact A4</span>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>

            {/* Right 5 Columns: Filters & Direct Print Action Panel */}
            <div className="lg:col-span-5 space-y-6">

              {/* Report Filters Card */}
              <div className="bg-white border border-slate-200 rounded-2xl p-5 shadow-sm space-y-4">
                <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-slate-500 pb-2 border-b border-slate-100">
                  <SlidersHorizontal size={15} className="text-[#3C3489]" />
                  <span>Report Filters ({getActiveReportConfig().title})</span>
                </div>

                {/* 1. MODEL SEARCH & FILTER (for today inward & stock by model) */}
                {(selectedReportType === "today_inward_serials" || selectedReportType === "stock_by_model") && (
                  <div className="space-y-2">
                    <label className="block text-xs font-bold text-slate-700">
                      Filter by Product Model:
                    </label>

                    {/* Search Input */}
                    <div className="relative">
                      <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
                      <input
                        type="text"
                        value={modelSearchQuery}
                        onChange={(e) => setModelSearchQuery(e.target.value.toUpperCase())}
                        placeholder="Search model, brand (e.g. Haier, 183V)..."
                        className="w-full pl-8.5 pr-8 py-2 text-xs rounded-xl border border-slate-200 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] uppercase font-mono font-bold text-slate-800"
                      />
                      {modelSearchQuery && (
                        <button
                          onClick={() => setModelSearchQuery("")}
                          className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 cursor-pointer"
                        >
                          <X size={14} />
                        </button>
                      )}
                    </div>

                    {/* Dropdown Suggestions */}
                    {modelSearchQuery && (
                      <div className="max-h-48 overflow-y-auto rounded-xl border border-slate-200 bg-white shadow-lg divide-y divide-slate-100 text-xs">
                        {matchingProducts.length === 0 ? (
                          <div className="p-3 text-center text-slate-400 text-xs">
                            No models found matching "{modelSearchQuery}"
                          </div>
                        ) : (
                          matchingProducts.map((p) => (
                            <div
                              key={p.id}
                              onClick={() => {
                                setSelectedProduct(p);
                                setModelSearchQuery("");
                              }}
                              className="p-2.5 hover:bg-indigo-50/70 transition-colors cursor-pointer flex items-center justify-between"
                            >
                              <div>
                                <span className="font-bold text-slate-900">{p.brand} {p.model}</span>
                                <span className="text-[11px] text-slate-500 block">{p.name}</span>
                              </div>
                              <span className="text-[10px] px-2 py-0.5 rounded bg-indigo-50 text-indigo-700 font-semibold uppercase">
                                Select
                              </span>
                            </div>
                          ))
                        )}
                      </div>
                    )}

                    {/* Selected Product Pill or All Models Notice */}
                    {selectedProduct ? (
                      <div className="p-3 rounded-xl bg-indigo-50 border border-indigo-200 flex items-center justify-between gap-2">
                        <div>
                          <div className="flex items-center gap-1.5">
                            <span className="w-2 h-2 rounded-full bg-indigo-600" />
                            <span className="text-xs font-bold text-indigo-950">
                              {selectedProduct.brand} {selectedProduct.model}
                            </span>
                          </div>
                          <span className="text-[11px] text-indigo-700 block mt-0.5">
                            {selectedProduct.name}
                          </span>
                        </div>
                        <button
                          onClick={() => setSelectedProduct(null)}
                          className="px-2 py-1 rounded-lg bg-white border border-indigo-200 text-[11px] font-bold text-indigo-700 hover:bg-indigo-100/60 cursor-pointer shadow-xs"
                        >
                          Show All
                        </button>
                      </div>
                    ) : (
                      <div className="p-2.5 rounded-xl bg-slate-50 border border-slate-200 text-[11px] text-slate-600 flex items-center gap-2">
                        <Layers size={14} className="text-slate-400 shrink-0" />
                        <span>All Models Selected (Report groups serials by model)</span>
                      </div>
                    )}
                  </div>
                )}

                {/* 2. INWARD FLOW TYPE (for today inward) */}
                {selectedReportType === "today_inward_serials" && (
                  <div className="space-y-1.5">
                    <label className="block text-xs font-bold text-slate-700">Filter Inward Type:</label>
                    <select
                      value={selectedInwardType}
                      onChange={(e) => setSelectedInwardType(e.target.value)}
                      className="w-full px-3 py-2 text-xs rounded-xl border border-slate-200 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] text-slate-800 font-medium"
                    >
                      <option value="">All Inward Types (Stock In, Return, Damaged)</option>
                      <option value="stock_in">Stock In (Direct from Company)</option>
                      <option value="return">Customer / Shop Return</option>
                      <option value="damaged">Damaged Stock</option>
                    </select>
                  </div>
                )}

                {/* 3. DESTINATION SHOP (for stock_out & unmatched_outward) */}
                {(selectedReportType === "stock_out" || selectedReportType === "unmatched_outward") && (
                  <div className="space-y-1.5">
                    <label className="block text-xs font-bold text-slate-700">Filter Destination Shop:</label>
                    <select
                      value={selectedShop?.id || ""}
                      onChange={(e) => {
                        const sh = shops.find((s) => s.id === e.target.value) || null;
                        setSelectedShop(sh);
                      }}
                      className="w-full px-3 py-2 text-xs rounded-xl border border-slate-200 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] text-slate-800 font-medium"
                    >
                      <option value="">All Destination Shops</option>
                      {shops.map((s) => (
                        <option key={s.id} value={s.id}>
                          {s.name} {s.city ? `(${s.city})` : ""}
                        </option>
                      ))}
                    </select>
                  </div>
                )}

                {/* 4. DATE RANGE PICKER (for all except stock_by_model) */}
                {selectedReportType !== "stock_by_model" && (
                  <div className="space-y-3 pt-2">
                    <div className="flex items-center justify-between">
                      <label className="text-xs font-bold text-slate-700">Report Date Range:</label>
                      <span className="text-[10px] text-slate-400 font-semibold uppercase">Calendar</span>
                    </div>

                    {/* From & To Inputs */}
                    <div className="grid grid-cols-2 gap-2.5">
                      <div>
                        <span className="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-1">
                          From (Start Date)
                        </span>
                        <input
                          type="date"
                          value={dateFrom}
                          onChange={(e) => setDateFrom(e.target.value)}
                          className="w-full px-2.5 py-1.5 text-xs rounded-xl border border-slate-200 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 font-medium text-slate-800"
                        />
                      </div>
                      <div>
                        <span className="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-1">
                          To (End Date)
                        </span>
                        <input
                          type="date"
                          value={dateTo}
                          onChange={(e) => setDateTo(e.target.value)}
                          className="w-full px-2.5 py-1.5 text-xs rounded-xl border border-slate-200 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 font-medium text-slate-800"
                        />
                      </div>
                    </div>

                    {/* Quick Preset Chips Matching Mobile */}
                    <div className="flex items-center gap-1.5 flex-wrap pt-1">
                      <button
                        type="button"
                        onClick={() => handleQuickPreset("today")}
                        className={`px-2.5 py-1 text-[11px] rounded-lg font-semibold transition-all cursor-pointer ${
                          isSingleDay && dateFrom === getTodayStr()
                            ? "bg-[#3C3489] text-white shadow-xs"
                            : "bg-slate-100 text-slate-600 hover:bg-slate-200"
                        }`}
                      >
                        Today
                      </button>
                      <button
                        type="button"
                        onClick={() => handleQuickPreset("yesterday")}
                        className="px-2.5 py-1 text-[11px] rounded-lg font-semibold bg-slate-100 text-slate-600 hover:bg-slate-200 transition-all cursor-pointer"
                      >
                        Yesterday
                      </button>
                      <button
                        type="button"
                        onClick={() => handleQuickPreset("last_7_days")}
                        className="px-2.5 py-1 text-[11px] rounded-lg font-semibold bg-slate-100 text-slate-600 hover:bg-slate-200 transition-all cursor-pointer"
                      >
                        Last 7 Days
                      </button>
                      <button
                        type="button"
                        onClick={() => handleQuickPreset("this_month")}
                        className="px-2.5 py-1 text-[11px] rounded-lg font-semibold bg-slate-100 text-slate-600 hover:bg-slate-200 transition-all cursor-pointer"
                      >
                        This Month
                      </button>
                    </div>

                    {/* Dynamic Range Summary Badge */}
                    <div className="p-2.5 rounded-xl bg-slate-50 border border-slate-200 text-[11px] font-medium text-slate-600 flex items-center gap-2">
                      <Info size={14} className="text-[#3C3489] shrink-0" />
                      <span>
                        {isSingleDay
                          ? `Printing records for single day: ${formatDateDisplay(dateFrom)}`
                          : `Printing records from ${formatDateDisplay(dateFrom)} to ${formatDateDisplay(dateTo)} (${daysDifference} days)`}
                      </span>
                    </div>
                  </div>
                )}
              </div>

              {/* Direct Print & Output Action Panel */}
              <div className="bg-white border border-slate-200 rounded-2xl p-5 shadow-sm space-y-3">
                <div className="text-xs font-bold text-slate-700">Actions & Local Print:</div>

                {/* 1. Direct Print on Local PC */}
                <button
                  type="button"
                  onClick={handleLocalPrint}
                  disabled={isPrinting || isPreviewing}
                  className="w-full py-2.5 px-4 rounded-xl bg-[#3C3489] hover:bg-[#312B72] text-xs font-bold text-white shadow-sm transition-all flex items-center justify-center gap-2 cursor-pointer disabled:opacity-50"
                  title="Directly print to local printer attached to this PC"
                >
                  {isPrinting ? (
                    <>
                      <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                      <span>Preparing Local Print Dialog...</span>
                    </>
                  ) : (
                    <>
                      <Printer size={16} />
                      <span>Print Document (Local Printer)</span>
                    </>
                  )}
                </button>

                {/* 2. Preview Button */}
                <button
                  type="button"
                  onClick={handlePreviewA4}
                  disabled={isPreviewing || isPrinting}
                  className="w-full py-2.5 px-4 rounded-xl border border-indigo-300 bg-indigo-50/80 hover:bg-indigo-100 text-xs font-bold text-[#3C3489] shadow-xs transition-all flex items-center justify-center gap-2 cursor-pointer disabled:opacity-50"
                >
                  {isPreviewing ? (
                    <>
                      <div className="w-4 h-4 border-2 border-[#3C3489] border-t-transparent rounded-full animate-spin" />
                      <span>Generating Exact A4 Document...</span>
                    </>
                  ) : (
                    <>
                      <Eye size={16} />
                      <span>Preview Exact A4 Document</span>
                    </>
                  )}
                </button>

                {/* 3. Export Formats (PDF / Excel / CSV) */}
                <div className="pt-2 flex items-center gap-2">
                  <button
                    type="button"
                    onClick={handleDirectDownloadPdf}
                    disabled={isPreviewing}
                    className="flex-1 py-2 px-2.5 rounded-xl border border-slate-200 bg-white text-slate-700 hover:bg-slate-50 text-[11px] font-semibold transition-all flex items-center justify-center gap-1.5 cursor-pointer shadow-xs disabled:opacity-50"
                    title="Download Official A4 PDF"
                  >
                    <FileDown size={14} className="text-rose-600" />
                    <span>Download PDF</span>
                  </button>

                  <button
                    type="button"
                    onClick={() => {
                      setActiveTab(
                        selectedReportType === "stock_by_model"
                          ? "stock_by_model"
                          : selectedReportType === "damaged"
                          ? "damaged"
                          : selectedReportType === "unmatched_outward"
                          ? "unmatched"
                          : "stock_out"
                      );
                      setMainView("raw_tables");
                      handleExportRawFormat("xlsx");
                    }}
                    className="flex-1 py-2 px-2.5 rounded-xl border border-slate-200 bg-white text-slate-700 hover:bg-slate-50 text-[11px] font-semibold transition-all flex items-center justify-center gap-1.5 cursor-pointer shadow-xs"
                    title="Export as Excel"
                  >
                    <FileSpreadsheet size={14} className="text-emerald-600" />
                    <span>Excel (.xlsx)</span>
                  </button>
                </div>
              </div>

            </div>
          </div>
        </div>
      )}

      {/* ───────────────────────────────────────────────────────────────────────────── */}
      {/* 2. INTERACTIVE DATA TABLES & SYSTEM AUDIT VIEW (Row-by-row on Screen)        */}
      {/* ───────────────────────────────────────────────────────────────────────────── */}
      {mainView === "raw_tables" && (
        <div className="space-y-6">

          {/* Subheader and Export Buttons */}
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-white border border-slate-200 rounded-2xl p-4 shadow-sm">
            <div className="flex items-center gap-2">
              <span className="text-xs font-bold uppercase tracking-wider text-slate-700">
                Active Table Mode:
              </span>
              <span className="text-xs text-slate-500">
                Browse records directly on screen or export spreadsheets.
              </span>
            </div>

            <div className="flex items-center gap-2">
              <button
                onClick={() => handleExportRawFormat("xlsx")}
                disabled={exportingFormat !== null}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-emerald-700 hover:bg-emerald-800 text-white text-xs font-semibold shadow-xs transition-colors disabled:opacity-50 cursor-pointer"
              >
                <FileSpreadsheet size={14} />
                <span>{exportingFormat === "xlsx" ? "Generating..." : "Export Excel"}</span>
              </button>

              {activeTab !== "audit" && (
                <button
                  onClick={() => handleExportRawFormat("pdf")}
                  disabled={exportingFormat !== null}
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-rose-700 hover:bg-rose-800 text-white text-xs font-semibold shadow-xs transition-colors disabled:opacity-50 cursor-pointer"
                >
                  <FileDown size={14} />
                  <span>{exportingFormat === "pdf" ? "Building..." : "Export PDF"}</span>
                </button>
              )}

              <button
                onClick={() => handleExportRawFormat("csv")}
                disabled={exportingFormat !== null}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-slate-800 hover:bg-slate-900 text-white text-xs font-semibold shadow-xs transition-colors disabled:opacity-50 cursor-pointer"
              >
                <FileText size={14} />
                <span>{exportingFormat === "csv" ? "Exporting..." : "Export CSV"}</span>
              </button>
            </div>
          </div>

          {/* Tabs */}
          <div className="flex items-center gap-1 overflow-x-auto border-b border-slate-200 pb-2 scrollbar-none text-xs font-semibold">
            <button
              onClick={() => setActiveTab("stock_by_model")}
              className={`px-3.5 py-2 rounded-xl shrink-0 transition-all cursor-pointer ${
                activeTab === "stock_by_model"
                  ? "bg-[#3C3489] text-white shadow-xs"
                  : "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
              }`}
            >
              Stock by Model
            </button>
            <button
              onClick={() => setActiveTab("stock_out")}
              className={`px-3.5 py-2 rounded-xl shrink-0 transition-all cursor-pointer ${
                activeTab === "stock_out"
                  ? "bg-[#3C3489] text-white shadow-xs"
                  : "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
              }`}
            >
              Stock Out (Dispatches)
            </button>
            <button
              onClick={() => setActiveTab("unmatched")}
              className={`px-3.5 py-2 rounded-xl shrink-0 transition-all cursor-pointer ${
                activeTab === "unmatched"
                  ? "bg-[#3C3489] text-white shadow-xs"
                  : "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
              }`}
            >
              Unmatched Outward (Pre-Go-Live)
            </button>
            <button
              onClick={() => setActiveTab("damaged")}
              className={`px-3.5 py-2 rounded-xl shrink-0 transition-all cursor-pointer ${
                activeTab === "damaged"
                  ? "bg-[#3C3489] text-white shadow-xs"
                  : "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
              }`}
            >
              Damaged & Under Repair
            </button>
            <button
              onClick={() => setActiveTab("audit")}
              className={`px-3.5 py-2 rounded-xl shrink-0 transition-all cursor-pointer ${
                activeTab === "audit"
                  ? "bg-[#3C3489] text-white shadow-xs"
                  : "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
              }`}
            >
              System Audit Log
            </button>
          </div>

          {/* Table Filters */}
          <div className="bg-white border border-slate-200 rounded-xl p-4 shadow-xs flex flex-wrap items-center gap-3 text-xs">
            {activeTab === "stock_by_model" && (
              <div>
                <label className="block text-slate-500 font-semibold mb-1">Filter Category</label>
                <select
                  value={tableCategory}
                  onChange={(e) => setTableCategory(e.target.value)}
                  className="px-3 py-1.5 rounded-lg border border-slate-200 bg-white font-medium"
                >
                  <option value="">All Categories</option>
                  {categories.map((c) => (
                    <option key={c.id} value={c.id}>{c.name}</option>
                  ))}
                </select>
              </div>
            )}

            {(activeTab === "stock_out" || activeTab === "unmatched") && (
              <>
                <div>
                  <label className="block text-slate-500 font-semibold mb-1">Filter Shop</label>
                  <select
                    value={tableShop}
                    onChange={(e) => setTableShop(e.target.value)}
                    className="px-3 py-1.5 rounded-lg border border-slate-200 bg-white font-medium"
                  >
                    <option value="">All Destination Shops</option>
                    {shops.map((s) => (
                      <option key={s.id} value={s.id}>{s.name} ({s.city})</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block text-slate-500 font-semibold mb-1">Filter Product</label>
                  <select
                    value={tableProduct}
                    onChange={(e) => setTableProduct(e.target.value)}
                    className="px-3 py-1.5 rounded-lg border border-slate-200 bg-white font-medium"
                  >
                    <option value="">All Products</option>
                    {products.map((p) => (
                      <option key={p.id} value={p.id}>{p.brand} {p.model}</option>
                    ))}
                  </select>
                </div>
                {activeTab === "stock_out" && (
                  <div>
                    <label className="block text-slate-500 font-semibold mb-1">Match Filter</label>
                    <select
                      value={matchedFilter}
                      onChange={(e) => setMatchedFilter(e.target.value)}
                      className="px-3 py-1.5 rounded-lg border border-slate-200 bg-white font-medium"
                    >
                      <option value="all">All Records</option>
                      <option value="matched">Matched Only</option>
                      <option value="unmatched">Unmatched Only</option>
                    </select>
                  </div>
                )}
              </>
            )}

            {activeTab === "damaged" && (
              <div>
                <label className="block text-slate-500 font-semibold mb-1">Filter Product</label>
                <select
                  value={tableProduct}
                  onChange={(e) => setTableProduct(e.target.value)}
                  className="px-3 py-1.5 rounded-lg border border-slate-200 bg-white font-medium"
                >
                  <option value="">All Damaged Products</option>
                  {products.map((p) => (
                    <option key={p.id} value={p.id}>{p.brand} {p.model}</option>
                  ))}
                </select>
              </div>
            )}

            {activeTab === "audit" && (
              <>
                <div>
                  <label className="block text-slate-500 font-semibold mb-1">Filter Action</label>
                  <input
                    type="text"
                    value={auditAction}
                    onChange={(e) => setAuditAction(e.target.value)}
                    placeholder="e.g. login, create..."
                    className="px-3 py-1.5 rounded-lg border border-slate-200 bg-white font-medium"
                  />
                </div>
                <div>
                  <label className="block text-slate-500 font-semibold mb-1">Filter Entity</label>
                  <input
                    type="text"
                    value={auditEntity}
                    onChange={(e) => setAuditEntity(e.target.value)}
                    placeholder="e.g. serial, user..."
                    className="px-3 py-1.5 rounded-lg border border-slate-200 bg-white font-medium"
                  />
                </div>
              </>
            )}

            {activeTab !== "stock_by_model" && (
              <>
                <div>
                  <label className="block text-slate-500 font-semibold mb-1">Date From</label>
                  <input
                    type="date"
                    value={tableDateFrom}
                    onChange={(e) => setTableDateFrom(e.target.value)}
                    className="px-3 py-1.5 rounded-lg border border-slate-200 bg-white font-medium"
                  />
                </div>
                <div>
                  <label className="block text-slate-500 font-semibold mb-1">Date To</label>
                  <input
                    type="date"
                    value={tableDateTo}
                    onChange={(e) => setTableDateTo(e.target.value)}
                    className="px-3 py-1.5 rounded-lg border border-slate-200 bg-white font-medium"
                  />
                </div>
              </>
            )}
          </div>

          {/* Table Container */}
          <div className="bg-white border border-slate-200 rounded-2xl shadow-sm overflow-hidden">
            {tableLoading ? (
              <div className="py-20 text-center text-xs text-slate-400">
                <div className="w-6 h-6 border-2 border-[#3C3489] border-t-transparent rounded-full animate-spin mx-auto mb-2" />
                Loading records...
              </div>
            ) : tableError ? (
              <div className="p-6 text-center text-xs text-rose-600 font-semibold">
                {tableError}
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-left text-xs">
                  {/* Stock by model header */}
                  {activeTab === "stock_by_model" && (
                    <>
                      <thead className="bg-slate-50 border-b border-slate-200 text-slate-500 font-semibold uppercase text-[10px] tracking-wider">
                        <tr>
                          <th className="py-3 px-4">Product Name</th>
                          <th className="py-3 px-4">Brand & Model</th>
                          <th className="py-3 px-4">Category</th>
                          <th className="py-3 px-4 text-center">Stock Qty</th>
                          <th className="py-3 px-4 text-center">Available</th>
                          <th className="py-3 px-4 text-center">Dispatched</th>
                          <th className="py-3 px-4 text-center">Damaged</th>
                          <th className="py-3 px-4 text-center">Total Inward</th>
                          <th className="py-3 px-4 text-center">Unmatched Out</th>
                          <th className="py-3 px-4 text-right">Status</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                        {stockByModel.map((item) => (
                          <tr key={item.product_id} className="hover:bg-slate-50/70">
                            <td className="py-3 px-4 font-bold text-slate-900">{item.name}</td>
                            <td className="py-3 px-4 font-mono">{item.brand} {item.model}</td>
                            <td className="py-3 px-4 text-slate-500">{item.category_name}</td>
                            <td className="py-3 px-4 text-center font-bold text-slate-900">{item.current_stock_qty}</td>
                            <td className="py-3 px-4 text-center font-semibold text-emerald-600">{item.available_count}</td>
                            <td className="py-3 px-4 text-center text-indigo-600">{item.dispatched_count}</td>
                            <td className="py-3 px-4 text-center text-rose-600">{item.damaged_count}</td>
                            <td className="py-3 px-4 text-center text-slate-500">{item.total_received}</td>
                            <td className="py-3 px-4 text-center text-amber-600 font-bold">{item.unmatched_dispatched_count}</td>
                            <td className="py-3 px-4 text-right">
                              <Badge label={item.reminder_label || (item.current_stock_qty > 0 ? "In Stock" : "Out of Stock")} />
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </>
                  )}

                  {/* Stock out header */}
                  {activeTab === "stock_out" && (
                    <>
                      <thead className="bg-slate-50 border-b border-slate-200 text-slate-500 font-semibold uppercase text-[10px] tracking-wider">
                        <tr>
                          <th className="py-3 px-4">Date</th>
                          <th className="py-3 px-4">Serial Number</th>
                          <th className="py-3 px-4">Product Model</th>
                          <th className="py-3 px-4">Shop</th>
                          <th className="py-3 px-4">Delivery Ref</th>
                          <th className="py-3 px-4">Status</th>
                          <th className="py-3 px-4 text-right">Dispatcher</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                        {stockOutData.map((item) => (
                          <tr key={item.id} className="hover:bg-slate-50/70">
                            <td className="py-3 px-4 text-slate-500">{item.transaction_date}</td>
                            <td className="py-3 px-4 font-mono font-bold text-slate-900">{item.serial_number}</td>
                            <td className="py-3 px-4">{item.brand} {item.model}</td>
                            <td className="py-3 px-4">{item.shop_name} ({item.shop_city})</td>
                            <td className="py-3 px-4 font-mono text-[11px]">{item.delivery_reference || "—"}</td>
                            <td className="py-3 px-4">
                              <span className={`inline-flex px-2 py-0.5 rounded text-[10px] font-bold uppercase ${item.is_matched ? "bg-emerald-50 text-emerald-700" : "bg-amber-50 text-amber-700"}`}>
                                {item.status_label}
                              </span>
                            </td>
                            <td className="py-3 px-4 text-right text-slate-500">{item.dispatcher_name}</td>
                          </tr>
                        ))}
                      </tbody>
                    </>
                  )}

                  {/* Unmatched out header */}
                  {activeTab === "unmatched" && (
                    <>
                      <thead className="bg-slate-50 border-b border-slate-200 text-slate-500 font-semibold uppercase text-[10px] tracking-wider">
                        <tr>
                          <th className="py-3 px-4">Date</th>
                          <th className="py-3 px-4">Serial Number</th>
                          <th className="py-3 px-4">Product Model</th>
                          <th className="py-3 px-4">Shop</th>
                          <th className="py-3 px-4">Delivery Ref</th>
                          <th className="py-3 px-4 text-right">Dispatcher</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                        {unmatchedData.map((item) => (
                          <tr key={item.id} className="hover:bg-slate-50/70">
                            <td className="py-3 px-4 text-slate-500">{item.transaction_date}</td>
                            <td className="py-3 px-4 font-mono font-bold text-amber-800">{item.serial_number}</td>
                            <td className="py-3 px-4">{item.brand} {item.model}</td>
                            <td className="py-3 px-4">{item.shop_name} ({item.shop_city})</td>
                            <td className="py-3 px-4 font-mono text-[11px]">{item.delivery_reference || "—"}</td>
                            <td className="py-3 px-4 text-right text-slate-500">{item.dispatcher_name}</td>
                          </tr>
                        ))}
                      </tbody>
                    </>
                  )}

                  {/* Damaged header */}
                  {activeTab === "damaged" && (
                    <>
                      <thead className="bg-slate-50 border-b border-slate-200 text-slate-500 font-semibold uppercase text-[10px] tracking-wider">
                        <tr>
                          <th className="py-3 px-4">Serial Number</th>
                          <th className="py-3 px-4">Product</th>
                          <th className="py-3 px-4">Brand & Model</th>
                          <th className="py-3 px-4">Current Status</th>
                          <th className="py-3 px-4">Last Shop</th>
                          <th className="py-3 px-4 text-right">Date Marked</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                        {damagedData.map((item) => (
                          <tr key={item.id} className="hover:bg-slate-50/70">
                            <td className="py-3 px-4 font-mono font-bold text-rose-800">{item.serial_number}</td>
                            <td className="py-3 px-4">{item.product_name}</td>
                            <td className="py-3 px-4 font-mono">{item.brand} {item.model}</td>
                            <td className="py-3 px-4">
                              <span className="inline-flex px-2 py-0.5 rounded text-[10px] font-bold uppercase bg-rose-50 text-rose-700">
                                {item.status.replace("_", " ")}
                              </span>
                            </td>
                            <td className="py-3 px-4 text-slate-500">{item.last_shop_name || "Godown"}</td>
                            <td className="py-3 px-4 text-right text-slate-500">{item.updated_at ? item.updated_at.split("T")[0] : "—"}</td>
                          </tr>
                        ))}
                      </tbody>
                    </>
                  )}

                  {/* Audit Log header */}
                  {activeTab === "audit" && (
                    <>
                      <thead className="bg-slate-50 border-b border-slate-200 text-slate-500 font-semibold uppercase text-[10px] tracking-wider">
                        <tr>
                          <th className="py-3 px-4">Timestamp</th>
                          <th className="py-3 px-4">Action</th>
                          <th className="py-3 px-4">Entity Type</th>
                          <th className="py-3 px-4">User</th>
                          <th className="py-3 px-4">Device</th>
                          <th className="py-3 px-4 text-right">IP Address</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                        {auditData.map((item) => (
                          <tr key={item.id} className="hover:bg-slate-50/70">
                            <td className="py-3 px-4 text-slate-500">
                              {new Date(item.created_at).toLocaleString("en-IN")}
                            </td>
                            <td className="py-3 px-4">
                              <span className="inline-flex px-2 py-0.5 rounded text-[10px] font-bold uppercase bg-indigo-50 text-indigo-700">
                                {item.action}
                              </span>
                            </td>
                            <td className="py-3 px-4 font-mono text-[11px]">{item.entity_type}</td>
                            <td className="py-3 px-4 font-semibold text-slate-800">{item.user_name || "System"}</td>
                            <td className="py-3 px-4 text-slate-500">{item.device_label || "Web Admin"}</td>
                            <td className="py-3 px-4 text-right font-mono text-[11px] text-slate-400">{item.ip_address || "—"}</td>
                          </tr>
                        ))}
                      </tbody>
                    </>
                  )}
                </table>
              </div>
            )}
          </div>
        </div>
      )}

      {/* ───────────────────────────────────────────────────────────────────────────── */}
      {/* EXACT A4 PREVIEW MODAL                                                        */}
      {/* ───────────────────────────────────────────────────────────────────────────── */}
      <Modal
        isOpen={previewModalOpen}
        onClose={() => {
          setPreviewModalOpen(false);
          if (previewBlobUrl) {
            window.URL.revokeObjectURL(previewBlobUrl);
            setPreviewBlobUrl(null);
          }
        }}
        title={`Exact A4 Document Preview • ${previewTitle}`}
        subtitle="Standard Print Format: A4 (595 × 842 pt) • Local PC Direct Print & Download"
        maxWidth="5xl"
      >
        <div className="space-y-4">
          {/* Action Toolbar inside Modal */}
          <div className="flex flex-wrap items-center justify-between gap-3 p-3 bg-slate-50 border border-slate-200 rounded-xl">
            <div className="flex items-center gap-2 text-xs text-slate-600 font-medium">
              <span className="w-2 h-2 rounded-full bg-emerald-500" />
              <span>Ready to print directly on this computer</span>
            </div>

            <div className="flex items-center gap-2">
              {previewBlobUrl && (
                <a
                  href={previewBlobUrl}
                  target="_blank"
                  rel="noreferrer"
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 transition-all shadow-xs"
                >
                  <ExternalLink size={13} />
                  <span>Open in Tab</span>
                </a>
              )}

              {previewBlobUrl && (
                <a
                  href={previewBlobUrl}
                  download={`${selectedReportType}_${getTodayStr()}.pdf`}
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-slate-200 bg-white hover:bg-slate-50 text-xs font-semibold text-slate-700 transition-all shadow-xs"
                >
                  <FileDown size={13} className="text-rose-600" />
                  <span>Download PDF</span>
                </a>
              )}

              <button
                type="button"
                onClick={() => {
                  try {
                    previewIframeRef.current?.contentWindow?.focus();
                    previewIframeRef.current?.contentWindow?.print();
                  } catch {
                    if (previewBlobUrl) window.open(previewBlobUrl, "_blank");
                  }
                }}
                className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg bg-[#3C3489] hover:bg-[#312B72] text-xs font-bold text-white shadow-xs transition-all cursor-pointer"
              >
                <Printer size={13} />
                <span>Print Document</span>
              </button>
            </div>
          </div>

          {/* Embedded PDF iframe */}
          <div className="relative w-full h-[68vh] rounded-xl overflow-hidden border border-slate-200 bg-slate-100">
            {previewBlobUrl ? (
              <iframe
                ref={previewIframeRef}
                src={previewBlobUrl}
                title="A4 PDF Preview"
                className="w-full h-full border-0"
              />
            ) : (
              <div className="flex items-center justify-center h-full text-xs text-slate-400">
                Rendering preview document...
              </div>
            )}
          </div>
        </div>
      </Modal>

    </div>
  );
};