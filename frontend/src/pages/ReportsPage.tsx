import React, { useEffect, useState } from "react";
import { apiRequest } from "../api/client";
import { Badge } from "../components/Badge";
import type {
  Category,
  Shop,
  Product,
  StockByModelItem,
  StockOutReportItem,
  DamagedReportItem,
  AuditLogItem,
} from "../types";

type ReportTab = "stock_by_model" | "stock_out" | "unmatched" | "damaged" | "audit";

export const ReportsPage: React.FC = () => {
  const [activeTab, setActiveTab] = useState<ReportTab>("stock_by_model");

  // Metadata dropdowns
  const [categories, setCategories] = useState<Category[]>([]);
  const [shops, setShops] = useState<Shop[]>([]);
  const [products, setProducts] = useState<Product[]>([]);

  // Filter states
  const [selectedCategory, setSelectedCategory] = useState<string>("");
  const [selectedShop, setSelectedShop] = useState<string>("");
  const [selectedProduct, setSelectedProduct] = useState<string>("");
  const [dateFrom, setDateFrom] = useState<string>("");
  const [dateTo, setDateTo] = useState<string>("");
  const [matchedFilter, setMatchedFilter] = useState<string>("all");
  const [auditAction, setAuditAction] = useState<string>("");
  const [auditEntity, setAuditEntity] = useState<string>("");

  // Data states
  const [loading, setLoading] = useState(false);
  const [exporting, setExporting] = useState<string | null>(null);
  const [stockByModel, setStockByModel] = useState<StockByModelItem[]>([]);
  const [stockOutData, setStockOutData] = useState<StockOutReportItem[]>([]);
  const [unmatchedData, setUnmatchedData] = useState<StockOutReportItem[]>([]);
  const [damagedData, setDamagedData] = useState<DamagedReportItem[]>([]);
  const [auditData, setAuditData] = useState<AuditLogItem[]>([]);
  const [error, setError] = useState<string | null>(null);

  // Load dropdown lists on mount
  useEffect(() => {
    const loadMetadata = async () => {
      try {
        const [cats, shps, prds] = await Promise.all([
          apiRequest<Category[]>("/categories"),
          apiRequest<Shop[]>("/shops"),
          apiRequest<Product[]>("/products"),
        ]);
        setCategories(cats);
        setShops(shps);
        setProducts(prds);
      } catch (e) {
        console.error("Failed to load metadata", e);
      }
    };
    loadMetadata();
  }, []);

  // Fetch report data on tab or filter change
  const fetchReportData = async () => {
    try {
      setLoading(true);
      setError(null);

      if (activeTab === "stock_by_model") {
        const query = selectedCategory ? `?category_id=${selectedCategory}` : "";
        const data = await apiRequest<StockByModelItem[]>(`/reports/stock-by-model${query}`);
        setStockByModel(data);
      } else if (activeTab === "stock_out") {
        const params = new URLSearchParams();
        if (selectedShop) params.append("shop_id", selectedShop);
        if (selectedProduct) params.append("product_id", selectedProduct);
        if (dateFrom) params.append("date_from", dateFrom);
        if (dateTo) params.append("date_to", dateTo);
        if (matchedFilter === "matched") params.append("is_matched", "true");
        if (matchedFilter === "unmatched") params.append("is_matched", "false");
        const qs = params.toString() ? `?${params.toString()}` : "";
        const data = await apiRequest<StockOutReportItem[]>(`/reports/stock-out${qs}`);
        setStockOutData(data);
      } else if (activeTab === "unmatched") {
        const params = new URLSearchParams();
        if (selectedShop) params.append("shop_id", selectedShop);
        if (selectedProduct) params.append("product_id", selectedProduct);
        if (dateFrom) params.append("date_from", dateFrom);
        if (dateTo) params.append("date_to", dateTo);
        const qs = params.toString() ? `?${params.toString()}` : "";
        const data = await apiRequest<StockOutReportItem[]>(`/reports/unmatched-outward${qs}`);
        setUnmatchedData(data);
      } else if (activeTab === "damaged") {
        const query = selectedProduct ? `?product_id=${selectedProduct}` : "";
        const data = await apiRequest<DamagedReportItem[]>(`/reports/damaged${query}`);
        setDamagedData(data);
      } else if (activeTab === "audit") {
        const params = new URLSearchParams();
        if (auditAction) params.append("action", auditAction);
        if (auditEntity) params.append("entity_type", auditEntity);
        if (dateFrom) params.append("date_from", dateFrom);
        if (dateTo) params.append("date_to", dateTo);
        params.append("limit", "200");
        const qs = `?${params.toString()}`;
        const data = await apiRequest<AuditLogItem[]>(`/audit${qs}`);
        setAuditData(data);
      }
    } catch (err: any) {
      setError(err.message || "Failed to load report data");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchReportData();
  }, [
    activeTab,
    selectedCategory,
    selectedShop,
    selectedProduct,
    dateFrom,
    dateTo,
    matchedFilter,
    auditAction,
    auditEntity,
  ]);

  // Download Trigger Handler
  const handleExport = async (format: "csv" | "xlsx" | "pdf") => {
    try {
      setExporting(format);
      let endpoint = "";
      const params = new URLSearchParams();
      params.append("export", format);

      if (activeTab === "stock_by_model") {
        endpoint = "/reports/stock-by-model";
        if (selectedCategory) params.append("category_id", selectedCategory);
      } else if (activeTab === "stock_out") {
        endpoint = "/reports/stock-out";
        if (selectedShop) params.append("shop_id", selectedShop);
        if (selectedProduct) params.append("product_id", selectedProduct);
        if (dateFrom) params.append("date_from", dateFrom);
        if (dateTo) params.append("date_to", dateTo);
        if (matchedFilter === "matched") params.append("is_matched", "true");
        if (matchedFilter === "unmatched") params.append("is_matched", "false");
      } else if (activeTab === "unmatched") {
        endpoint = "/reports/unmatched-outward";
        if (selectedShop) params.append("shop_id", selectedShop);
        if (selectedProduct) params.append("product_id", selectedProduct);
        if (dateFrom) params.append("date_from", dateFrom);
        if (dateTo) params.append("date_to", dateTo);
      } else if (activeTab === "damaged") {
        endpoint = "/reports/damaged";
        if (selectedProduct) params.append("product_id", selectedProduct);
      } else if (activeTab === "audit") {
        endpoint = "/audit";
        if (auditAction) params.append("action", auditAction);
        if (auditEntity) params.append("entity_type", auditEntity);
        if (dateFrom) params.append("date_from", dateFrom);
        if (dateTo) params.append("date_to", dateTo);
      }

      const url = `${endpoint}?${params.toString()}`;
      const blob = await apiRequest<Blob>(url);

      // Create download trigger
      const blobUrl = window.URL.createObjectURL(blob);
      const link = document.createElement("a");
      const dateStr = new Date().toISOString().split("T")[0];
      link.href = blobUrl;
      link.download = `${activeTab}_report_${dateStr}.${format}`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(blobUrl);
    } catch (err: any) {
      alert(`Export failed: ${err.message || "Unknown error"}`);
    } finally {
      setExporting(null);
    }
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4 bg-white border border-slate-200/80 rounded-2xl p-6 shadow-sm">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-xl font-bold text-slate-900 tracking-tight">Warehouse Reports & Exports</h1>
            <span className="text-xs px-2.5 py-0.5 rounded-full bg-slate-100 text-slate-700 font-semibold border border-slate-200">
              Live Godown Records
            </span>
          </div>
          <p className="text-xs text-slate-500 mt-1">
            Filter dispatch history, verify unmatched pre-go-live stock, and export official Excel, PDF, or CSV sheets.
          </p>
        </div>

        {/* Export Buttons Group */}
        <div className="flex items-center gap-2 self-start lg:self-auto">
          <button
            onClick={() => handleExport("xlsx")}
            disabled={exporting !== null}
            className="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-xl bg-emerald-700 hover:bg-emerald-800 text-white text-xs font-semibold shadow-xs transition-colors disabled:opacity-50 cursor-pointer"
          >
            <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
            {exporting === "xlsx" ? "Generating Excel..." : "Excel (.xlsx)"}
          </button>

          {activeTab !== "audit" && (
            <button
              onClick={() => handleExport("pdf")}
              disabled={exporting !== null}
              className="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-xl bg-rose-700 hover:bg-rose-800 text-white text-xs font-semibold shadow-xs transition-colors disabled:opacity-50 cursor-pointer"
            >
              <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z" />
              </svg>
              {exporting === "pdf" ? "Building PDF..." : "PDF Report"}
            </button>
          )}

          <button
            onClick={() => handleExport("csv")}
            disabled={exporting !== null}
            className="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-xl bg-slate-800 hover:bg-slate-900 text-white text-xs font-semibold shadow-xs transition-colors disabled:opacity-50 cursor-pointer"
          >
            <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
            </svg>
            {exporting === "csv" ? "Exporting CSV..." : "CSV (.csv)"}
          </button>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex items-center gap-1 overflow-x-auto border-b border-slate-200 pb-2 scrollbar-none">
        <button
          onClick={() => setActiveTab("stock_by_model")}
          className={`px-3.5 py-2 rounded-xl text-xs font-semibold shrink-0 transition-all cursor-pointer ${
            activeTab === "stock_by_model"
              ? "bg-indigo-900 text-white shadow-xs"
              : "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
          }`}
        >
          Stock by Model
        </button>
        <button
          onClick={() => setActiveTab("stock_out")}
          className={`px-3.5 py-2 rounded-xl text-xs font-semibold shrink-0 transition-all cursor-pointer ${
            activeTab === "stock_out"
              ? "bg-indigo-900 text-white shadow-xs"
              : "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
          }`}
        >
          Stock Out (Dispatches)
        </button>
        <button
          onClick={() => setActiveTab("unmatched")}
          className={`px-3.5 py-2 rounded-xl text-xs font-semibold shrink-0 transition-all cursor-pointer ${
            activeTab === "unmatched"
              ? "bg-indigo-900 text-white shadow-xs"
              : "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
          }`}
        >
          Unmatched Outward (Pre-Go-Live)
        </button>
        <button
          onClick={() => setActiveTab("damaged")}
          className={`px-3.5 py-2 rounded-xl text-xs font-semibold shrink-0 transition-all cursor-pointer ${
            activeTab === "damaged"
              ? "bg-indigo-900 text-white shadow-xs"
              : "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
          }`}
        >
          Damaged & Under Repair
        </button>
        <button
          onClick={() => setActiveTab("audit")}
          className={`px-3.5 py-2 rounded-xl text-xs font-semibold shrink-0 transition-all cursor-pointer ${
            activeTab === "audit"
              ? "bg-indigo-900 text-white shadow-xs"
              : "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
          }`}
        >
          System Audit Log
        </button>
      </div>

      {/* Filter Bar */}
      <div className="bg-white border border-slate-200 rounded-xl p-4 shadow-xs flex flex-wrap items-center gap-3 text-xs">
        {activeTab === "stock_by_model" && (
          <div>
            <label className="block text-slate-500 font-semibold mb-1">Filter Category</label>
            <select
              value={selectedCategory}
              onChange={(e) => setSelectedCategory(e.target.value)}
              className="px-3 py-1.5 rounded-lg border border-slate-200 bg-slate-50 text-slate-900 focus:outline-none focus:ring-1 focus:ring-indigo-800"
            >
              <option value="">All Categories</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>
        )}

        {(activeTab === "stock_out" || activeTab === "unmatched") && (
          <>
            <div>
              <label className="block text-slate-500 font-semibold mb-1">Destination Shop</label>
              <select
                value={selectedShop}
                onChange={(e) => setSelectedShop(e.target.value)}
                className="px-3 py-1.5 rounded-lg border border-slate-200 bg-slate-50 text-slate-900 focus:outline-none focus:ring-1 focus:ring-indigo-800"
              >
                <option value="">All Destination Shops</option>
                {shops.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name} ({s.city})
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-slate-500 font-semibold mb-1">Appliance Model</label>
              <select
                value={selectedProduct}
                onChange={(e) => setSelectedProduct(e.target.value)}
                className="px-3 py-1.5 rounded-lg border border-slate-200 bg-slate-50 text-slate-900 focus:outline-none focus:ring-1 focus:ring-indigo-800 max-w-xs truncate"
              >
                <option value="">All Models</option>
                {products.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name} ({p.model})
                  </option>
                ))}
              </select>
            </div>

            {activeTab === "stock_out" && (
              <div>
                <label className="block text-slate-500 font-semibold mb-1">Match Status</label>
                <select
                  value={matchedFilter}
                  onChange={(e) => setMatchedFilter(e.target.value)}
                  className="px-3 py-1.5 rounded-lg border border-slate-200 bg-slate-50 text-slate-900 focus:outline-none focus:ring-1 focus:ring-indigo-800"
                >
                  <option value="all">All Dispatches</option>
                  <option value="matched">Matched (Tracked Inward)</option>
                  <option value="unmatched">Recorded only (Old Stock)</option>
                </select>
              </div>
            )}

            <div>
              <label className="block text-slate-500 font-semibold mb-1">From Date</label>
              <input
                type="date"
                value={dateFrom}
                onChange={(e) => setDateFrom(e.target.value)}
                className="px-3 py-1.5 rounded-lg border border-slate-200 bg-slate-50 text-slate-900 focus:outline-none focus:ring-1 focus:ring-indigo-800"
              />
            </div>

            <div>
              <label className="block text-slate-500 font-semibold mb-1">To Date</label>
              <input
                type="date"
                value={dateTo}
                onChange={(e) => setDateTo(e.target.value)}
                className="px-3 py-1.5 rounded-lg border border-slate-200 bg-slate-50 text-slate-900 focus:outline-none focus:ring-1 focus:ring-indigo-800"
              />
            </div>
          </>
        )}

        {activeTab === "damaged" && (
          <div>
            <label className="block text-slate-500 font-semibold mb-1">Filter Model</label>
            <select
              value={selectedProduct}
              onChange={(e) => setSelectedProduct(e.target.value)}
              className="px-3 py-1.5 rounded-lg border border-slate-200 bg-slate-50 text-slate-900 focus:outline-none focus:ring-1 focus:ring-indigo-800 max-w-xs truncate"
            >
              <option value="">All Damaged Models</option>
              {products.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name} ({p.model})
                </option>
              ))}
            </select>
          </div>
        )}

        {activeTab === "audit" && (
          <>
            <div>
              <label className="block text-slate-500 font-semibold mb-1">Entity Type</label>
              <select
                value={auditEntity}
                onChange={(e) => setAuditEntity(e.target.value)}
                className="px-3 py-1.5 rounded-lg border border-slate-200 bg-slate-50 text-slate-900 focus:outline-none focus:ring-1 focus:ring-indigo-800"
              >
                <option value="">All Entities</option>
                <option value="product">Product</option>
                <option value="shop">Shop</option>
                <option value="inward_batch">Inward Batch</option>
                <option value="outward_batch">Outward Batch</option>
                <option value="serial_number">Serial Number</option>
                <option value="user">User Account</option>
                <option value="device">Mobile Device</option>
              </select>
            </div>

            <div>
              <label className="block text-slate-500 font-semibold mb-1">Action Keyword</label>
              <input
                type="text"
                placeholder="e.g. CREATED, DISPATCH"
                value={auditAction}
                onChange={(e) => setAuditAction(e.target.value)}
                className="px-3 py-1.5 rounded-lg border border-slate-200 bg-slate-50 text-slate-900 focus:outline-none focus:ring-1 focus:ring-indigo-800"
              />
            </div>

            <div>
              <label className="block text-slate-500 font-semibold mb-1">From Date</label>
              <input
                type="date"
                value={dateFrom}
                onChange={(e) => setDateFrom(e.target.value)}
                className="px-3 py-1.5 rounded-lg border border-slate-200 bg-slate-50 text-slate-900 focus:outline-none focus:ring-1 focus:ring-indigo-800"
              />
            </div>
          </>
        )}

        {/* Reset Filters button */}
        {(selectedCategory || selectedShop || selectedProduct || dateFrom || dateTo || matchedFilter !== "all" || auditAction || auditEntity) && (
          <button
            onClick={() => {
              setSelectedCategory("");
              setSelectedShop("");
              setSelectedProduct("");
              setDateFrom("");
              setDateTo("");
              setMatchedFilter("all");
              setAuditAction("");
              setAuditEntity("");
            }}
            className="mt-5 text-[11px] font-semibold text-rose-700 hover:underline cursor-pointer"
          >
            Clear Filters
          </button>
        )}
      </div>

      {/* Error Banner */}
      {error && (
        <div className="p-3.5 bg-rose-50 border border-rose-200 text-rose-800 text-xs font-medium rounded-xl">
          {error}
        </div>
      )}

      {/* Table Content */}
      <div className="bg-white border border-slate-200 rounded-2xl shadow-xs overflow-hidden">
        {loading ? (
          <div className="p-16 text-center text-xs text-slate-400">Loading report data...</div>
        ) : (
          <>
            {/* 1. Stock by Model Table */}
            {activeTab === "stock_by_model" && (
              <div className="overflow-x-auto">
                <table className="w-full text-left border-collapse text-xs">
                  <thead>
                    <tr className="bg-slate-50/75 border-b border-slate-200 text-slate-500 font-semibold uppercase tracking-wider">
                      <th className="py-3 px-4">Model & Appliance</th>
                      <th className="py-3 px-4">Category</th>
                      <th className="py-3 px-4 text-right">Physical Stock</th>
                      <th className="py-3 px-4 text-right">Available Tracked</th>
                      <th className="py-3 px-4 text-right">Dispatched</th>
                      <th className="py-3 px-4 text-right">Damaged</th>
                      <th className="py-3 px-4 text-right">Total Inward</th>
                      <th className="py-3 px-4 text-right">Recorded Only</th>
                      <th className="py-3 px-4">Status</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                    {stockByModel.map((item) => (
                      <tr key={item.product_id} className="hover:bg-slate-50/80 transition-colors">
                        <td className="py-3 px-4">
                          <div className="font-semibold text-slate-900">{item.name}</div>
                          <div className="text-[11px] text-slate-400 font-mono">
                            {item.brand} • {item.model}
                          </div>
                        </td>
                        <td className="py-3 px-4 text-slate-600">{item.category_name}</td>
                        <td className={`py-3 px-4 text-right font-bold ${item.current_stock_qty < 0 ? 'text-rose-600' : 'text-slate-900'}`}>
                          {item.current_stock_qty}
                        </td>
                        <td className="py-3 px-4 text-right text-emerald-700 font-bold">
                          {item.available_count}
                        </td>
                        <td className="py-3 px-4 text-right text-amber-700 font-medium">
                          {item.dispatched_count}
                        </td>
                        <td className="py-3 px-4 text-right text-rose-700 font-medium">
                          {item.damaged_count}
                        </td>
                        <td className="py-3 px-4 text-right text-slate-600">
                          {item.total_received}
                        </td>
                        <td className="py-3 px-4 text-right text-slate-500">
                          {item.unmatched_dispatched_count}
                        </td>
                        <td className="py-3 px-4">
                          {item.out_of_stock_reminder ? (
                            <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-bold bg-amber-100 text-amber-900 border border-amber-200">
                              No tracked stock left
                            </span>
                          ) : (
                            <Badge variant="green">In Stock</Badge>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            {/* 2. Stock Out Table */}
            {activeTab === "stock_out" && (
              <div className="overflow-x-auto">
                <table className="w-full text-left border-collapse text-xs">
                  <thead>
                    <tr className="bg-slate-50/75 border-b border-slate-200 text-slate-500 font-semibold uppercase tracking-wider">
                      <th className="py-3 px-4">Date</th>
                      <th className="py-3 px-4">Serial Number</th>
                      <th className="py-3 px-4">Product Model</th>
                      <th className="py-3 px-4">Destination Shop</th>
                      <th className="py-3 px-4">Delivery Ref</th>
                      <th className="py-3 px-4">Match Status</th>
                      <th className="py-3 px-4">Dispatched By</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                    {stockOutData.length === 0 ? (
                      <tr>
                        <td colSpan={7} className="p-8 text-center text-slate-400">
                          No dispatch records match your selected filters.
                        </td>
                      </tr>
                    ) : (
                      stockOutData.map((line) => (
                        <tr key={line.id} className="hover:bg-slate-50/80 transition-colors">
                          <td className="py-3 px-4 text-slate-500 whitespace-nowrap">
                            {line.transaction_date}
                          </td>
                          <td className="py-3 px-4">
                            <div className="flex items-center gap-1.5 flex-wrap">
                              <span className="font-mono font-bold text-slate-900 bg-slate-100 px-2 py-0.5 rounded border border-slate-200">
                                {line.serial_number}
                              </span>
                              {line.unit_type && (
                                <span className={`text-[11px] font-semibold ${
                                  line.unit_type.toLowerCase() === 'indoor' ? 'text-indigo-600' : 'text-teal-600'
                                }`}>
                                  ({line.unit_type.charAt(0).toUpperCase() + line.unit_type.slice(1).toLowerCase()})
                                </span>
                              )}
                            </div>
                          </td>
                          <td className="py-3 px-4">
                            <div className="font-semibold text-slate-800">{line.product_name}</div>
                            <div className="text-[11px] text-slate-400 font-mono">
                              {line.brand} {line.model}
                            </div>
                          </td>
                          <td className="py-3 px-4">
                            <div className="font-semibold text-slate-900">{line.shop_name}</div>
                            <div className="text-[11px] text-slate-400">{line.shop_city}</div>
                          </td>
                          <td className="py-3 px-4 font-mono text-slate-600">
                            {line.delivery_reference || "-"}
                          </td>
                          <td className="py-3 px-4">
                            {line.status_label === "Matched" ? (
                              <Badge variant="blue">Matched</Badge>
                            ) : line.status_label === "Recorded only" ? (
                              <Badge variant="grey">Recorded only</Badge>
                            ) : (
                              <Badge variant="amber">{line.status_label}</Badge>
                            )}
                          </td>
                          <td className="py-3 px-4 text-slate-600">{line.dispatcher_name}</td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            )}

            {/* 3. Unmatched Outward Table */}
            {activeTab === "unmatched" && (
              <div className="overflow-x-auto">
                <table className="w-full text-left border-collapse text-xs">
                  <thead>
                    <tr className="bg-slate-50/75 border-b border-slate-200 text-slate-500 font-semibold uppercase tracking-wider">
                      <th className="py-3 px-4">Date</th>
                      <th className="py-3 px-4">Serial Number</th>
                      <th className="py-3 px-4">Product Model</th>
                      <th className="py-3 px-4">Destination Shop</th>
                      <th className="py-3 px-4">Delivery Ref</th>
                      <th className="py-3 px-4">Dispatched By</th>
                      <th className="py-3 px-4">Audit Note</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                    {unmatchedData.length === 0 ? (
                      <tr>
                        <td colSpan={7} className="p-8 text-center text-slate-400">
                          No unmatched dispatches recorded in this period.
                        </td>
                      </tr>
                    ) : (
                      unmatchedData.map((line) => (
                        <tr key={line.id} className="hover:bg-slate-50/80 transition-colors">
                          <td className="py-3 px-4 text-slate-500 whitespace-nowrap">
                            {line.transaction_date}
                          </td>
                          <td className="py-3 px-4">
                            <div className="flex items-center gap-1.5 flex-wrap">
                              <span className="font-mono font-bold text-slate-900 bg-slate-100 px-2 py-0.5 rounded border border-slate-200">
                                {line.serial_number}
                              </span>
                              {line.unit_type && (
                                <span className={`text-[11px] font-semibold ${
                                  line.unit_type.toLowerCase() === 'indoor' ? 'text-indigo-600' : 'text-teal-600'
                                }`}>
                                  ({line.unit_type.charAt(0).toUpperCase() + line.unit_type.slice(1).toLowerCase()})
                                </span>
                              )}
                            </div>
                          </td>
                          <td className="py-3 px-4">
                            <div className="font-semibold text-slate-800">{line.product_name}</div>
                            <div className="text-[11px] text-slate-400 font-mono">
                              {line.brand} {line.model}
                            </div>
                          </td>
                          <td className="py-3 px-4">
                            <div className="font-semibold text-slate-900">{line.shop_name}</div>
                            <div className="text-[11px] text-slate-400">{line.shop_city}</div>
                          </td>
                          <td className="py-3 px-4 font-mono text-slate-600">
                            {line.delivery_reference || "-"}
                          </td>
                          <td className="py-3 px-4 text-slate-600">{line.dispatcher_name}</td>
                          <td className="py-3 px-4">
                            <span className="text-[11px] text-slate-500 bg-slate-100 px-2 py-0.5 rounded">
                              Pre-go-live stock (Dispatched without inward record)
                            </span>
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            )}

            {/* 4. Damaged & Under Repair Table */}
            {activeTab === "damaged" && (
              <div className="overflow-x-auto">
                <table className="w-full text-left border-collapse text-xs">
                  <thead>
                    <tr className="bg-slate-50/75 border-b border-slate-200 text-slate-500 font-semibold uppercase tracking-wider">
                      <th className="py-3 px-4">Serial Number</th>
                      <th className="py-3 px-4">Product Name</th>
                      <th className="py-3 px-4">Brand & Model</th>
                      <th className="py-3 px-4">Condition</th>
                      <th className="py-3 px-4">Current Location / Last Shop</th>
                      <th className="py-3 px-4">Date Marked</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                    {damagedData.length === 0 ? (
                      <tr>
                        <td colSpan={6} className="p-8 text-center text-slate-400">
                          All clear! No damaged or under-repair items currently in godown.
                        </td>
                      </tr>
                    ) : (
                      damagedData.map((d) => (
                        <tr key={d.id} className="hover:bg-slate-50/80 transition-colors">
                          <td className="py-3 px-4">
                            <div className="flex items-center gap-1.5 flex-wrap">
                              <span className="font-mono font-bold text-slate-900 bg-slate-100 px-2 py-0.5 rounded border border-slate-200">
                                {d.serial_number}
                              </span>
                              {d.unit_type && (
                                <span className={`text-[11px] font-semibold ${
                                  d.unit_type.toLowerCase() === 'indoor' ? 'text-indigo-600' : 'text-teal-600'
                                }`}>
                                  ({d.unit_type.charAt(0).toUpperCase() + d.unit_type.slice(1).toLowerCase()})
                                </span>
                              )}
                            </div>
                          </td>
                          <td className="py-3 px-4 font-semibold text-slate-900">{d.product_name}</td>
                          <td className="py-3 px-4 text-slate-500 font-mono">
                            {d.brand} {d.model}
                          </td>
                          <td className="py-3 px-4">
                            {d.status === "damaged" ? (
                              <Badge variant="red">Damaged</Badge>
                            ) : (
                              <Badge variant="amber">Under Repair</Badge>
                            )}
                          </td>
                          <td className="py-3 px-4 text-slate-700">{d.last_shop_name || "Godown Shelves"}</td>
                          <td className="py-3 px-4 text-slate-500">
                            {new Date(d.updated_at).toLocaleDateString("en-IN", {
                              day: "numeric",
                              month: "short",
                              year: "numeric",
                            })}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            )}

            {/* 5. System Audit Log Table */}
            {activeTab === "audit" && (
              <div className="overflow-x-auto">
                <table className="w-full text-left border-collapse text-xs">
                  <thead>
                    <tr className="bg-slate-50/75 border-b border-slate-200 text-slate-500 font-semibold uppercase tracking-wider">
                      <th className="py-3 px-4">Timestamp</th>
                      <th className="py-3 px-4">User</th>
                      <th className="py-3 px-4">Action</th>
                      <th className="py-3 px-4">Entity</th>
                      <th className="py-3 px-4">Device</th>
                      <th className="py-3 px-4">Details</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                    {auditData.length === 0 ? (
                      <tr>
                        <td colSpan={6} className="p-8 text-center text-slate-400">
                          No audit trail records match your filters.
                        </td>
                      </tr>
                    ) : (
                      auditData.map((log) => (
                        <tr key={log.id} className="hover:bg-slate-50/80 transition-colors">
                          <td className="py-3 px-4 text-slate-500 whitespace-nowrap text-[11px]">
                            {new Date(log.created_at).toLocaleString("en-IN", {
                              day: "numeric",
                              month: "short",
                              hour: "2-digit",
                              minute: "2-digit",
                              second: "2-digit",
                            })}
                          </td>
                          <td className="py-3 px-4 font-semibold text-slate-900">
                            {log.user_name || "System"}
                          </td>
                          <td className="py-3 px-4">
                            <span className="font-mono text-[11px] px-2 py-0.5 rounded bg-slate-100 text-slate-800 font-semibold border border-slate-200">
                              {log.action}
                            </span>
                          </td>
                          <td className="py-3 px-4 text-slate-600">
                            <span className="capitalize">{log.entity_type}</span>
                            {log.entity_id && (
                              <span className="block font-mono text-[10px] text-slate-400 truncate max-w-[120px]">
                                {log.entity_id}
                              </span>
                            )}
                          </td>
                          <td className="py-3 px-4 text-slate-500 text-[11px]">
                            {log.device_label || <span className="text-slate-300">-</span>}
                          </td>
                          <td className="py-3 px-4 text-[11px] font-mono text-slate-600 max-w-xs truncate">
                            {log.details ? JSON.stringify(log.details) : "-"}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
};