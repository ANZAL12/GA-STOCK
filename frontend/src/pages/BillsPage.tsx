import React, { useEffect, useState, useMemo } from "react";
import { apiRequest } from "../api/client";
import { useWebSocket } from "../api/useWebSocket";
import type { BillListItem, BillDetail, Shop } from "../types";
import { generateBillPdf } from "../utils/generateBillPdf";
import {
  Receipt,
  Search,
  FileDown,
  Calendar,
  Store,
  Eye,
  X,
  Layers,
  CheckCircle2,
  RotateCcw,
  Truck,
  Hash,
} from "lucide-react";

export const BillsPage: React.FC = () => {
  const [bills, setBills] = useState<BillListItem[]>([]);
  const [shops, setShops] = useState<Shop[]>([]);
  const [loading, setLoading] = useState(true);

  // Filters
  const [search, setSearch] = useState("");
  const [selectedShopId, setSelectedShopId] = useState<string>("");
  const [selectedDate, setSelectedDate] = useState<string>("");

  // Detailed Modal State
  const [selectedBill, setSelectedBill] = useState<BillDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState<string | null>(null);
  const [serialSearch, setSerialSearch] = useState("");
  const [downloadingPdf, setDownloadingPdf] = useState(false);

  const fetchShops = async () => {
    try {
      const data = await apiRequest<Shop[]>("/shops?active_only=false");
      setShops(data);
    } catch (e) {
      console.error("Failed to load shops", e);
    }
  };

  const fetchBills = async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams();
      if (search.trim()) params.append("search", search.trim());
      if (selectedShopId) params.append("shop_id", selectedShopId);
      if (selectedDate) {
        params.append("date_from", selectedDate);
        params.append("date_to", selectedDate);
      }
      params.append("limit", "150");

      const data = await apiRequest<BillListItem[]>(`/outward/bills?${params.toString()}`);
      setBills(data);
    } catch (e) {
      console.error("Failed to load bills", e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchShops();
  }, []);

  useEffect(() => {
    fetchBills();
  }, [search, selectedShopId, selectedDate]);

  useWebSocket((event) => {
    if (event === "stock_updated") {
      fetchBills();
    }
  });

  const openBillDetail = async (billNumber: string) => {
    setDetailLoading(true);
    setDetailError(null);
    setSerialSearch("");
    try {
      const detail = await apiRequest<BillDetail>(`/outward/bills/${encodeURIComponent(billNumber)}`);
      setSelectedBill(detail);
    } catch (err: any) {
      setDetailError(err.message || "Failed to load bill detail");
    } finally {
      setDetailLoading(false);
    }
  };

  const handleQuickDownloadPdf = async (e: React.MouseEvent, billNumber: string) => {
    e.stopPropagation();
    try {
      const detail = await apiRequest<BillDetail>(`/outward/bills/${encodeURIComponent(billNumber)}`);
      generateBillPdf(detail);
    } catch (err: any) {
      alert("Error generating PDF: " + (err.message || "Unknown error"));
    }
  };

  const handleDownloadDetailPdf = () => {
    if (!selectedBill) return;
    setDownloadingPdf(true);
    try {
      generateBillPdf(selectedBill);
    } finally {
      setDownloadingPdf(false);
    }
  };

  // Filtered serials in detail modal
  const filteredSerials = useMemo(() => {
    if (!selectedBill) return [];
    const list: Array<{
      serial_text: string;
      model: string;
      brand: string;
      unit_type?: string | null;
      status_label: string;
      is_flagged: boolean;
      flag_reason?: string | null;
    }> = [];

    for (const b of selectedBill.batches) {
      for (const l of b.lines) {
        list.push({
          serial_text: l.serial_text,
          model: b.model,
          brand: b.brand,
          unit_type: l.unit_type,
          status_label: l.status_label,
          is_flagged: l.is_flagged_for_review,
          flag_reason: l.flag_reason,
        });
      }
    }

    if (!serialSearch.trim()) return list;
    const q = serialSearch.trim().toLowerCase();
    return list.filter(
      (s) =>
        s.serial_text.toLowerCase().includes(q) ||
        s.model.toLowerCase().includes(q) ||
        s.brand.toLowerCase().includes(q) ||
        (s.unit_type && s.unit_type.toLowerCase().includes(q))
    );
  }, [selectedBill, serialSearch]);

  return (
    <div className="space-y-6">
      {/* 1. Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <span className="p-2 rounded-xl bg-[#EEF2FF] text-[#3C3489]">
              <Receipt size={22} />
            </span>
            <h1 className="text-2xl font-bold text-slate-900 tracking-tight">
              Dispatch Bills & Invoices
            </h1>
          </div>
          <p className="text-sm text-slate-500 mt-1">
            Track, inspect, and export outward dispatch batches grouped by Bill / Invoice number.
          </p>
        </div>

        <button
          onClick={fetchBills}
          className="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-semibold text-slate-700 bg-white border border-slate-200 hover:bg-slate-50 shadow-xs transition-colors self-start sm:self-auto"
        >
          <RotateCcw size={14} className={loading ? "animate-spin" : ""} />
          Refresh
        </button>
      </div>

      {/* 2. Search and Filters */}
      <div className="bg-white p-4 rounded-2xl border border-slate-200 shadow-xs space-y-3">
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-12 gap-3 items-center">
          {/* Text Search */}
          <div className="relative lg:col-span-5">
            <Search size={15} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" />
            <input
              type="text"
              placeholder="Search Bill No, Shop, Ref..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-xs rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489] bg-slate-50/50"
            />
          </div>

          {/* Shop Filter */}
          <div className="relative lg:col-span-4">
            <Store size={15} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 pointer-events-none" />
            <select
              value={selectedShopId}
              onChange={(e) => setSelectedShopId(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-xs rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489] bg-slate-50/50 appearance-none text-slate-700"
            >
              <option value="">All Shops / Dealers</option>
              {shops.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}{s.city ? ` (${s.city})` : ""}
                </option>
              ))}
            </select>
          </div>

          {/* Single Date Filter with Today Quick Button */}
          <div className="flex items-center gap-2 lg:col-span-3">
            <div className="relative flex-1">
              <Calendar size={15} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 pointer-events-none" />
              <input
                type="date"
                title="Filter by date"
                value={selectedDate}
                onChange={(e) => setSelectedDate(e.target.value)}
                className="w-full pl-9 pr-3 py-2 text-xs rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489] bg-slate-50/50 text-slate-700"
              />
            </div>

            <button
              type="button"
              onClick={() => {
                const todayStr = new Date().toISOString().split("T")[0];
                setSelectedDate(todayStr);
              }}
              title="Show today's bills"
              className={`px-3 py-2 text-xs font-semibold rounded-xl border transition-colors shrink-0 ${
                selectedDate === new Date().toISOString().split("T")[0]
                  ? "bg-[#3C3489] text-white border-[#3C3489]"
                  : "bg-white text-slate-700 border-slate-200 hover:bg-slate-50"
              }`}
            >
              Today
            </button>
          </div>
        </div>

        {(search || selectedShopId || selectedDate) && (
          <div className="flex items-center gap-2 pt-1 border-t border-slate-100 flex-wrap">
            <span className="text-[11px] font-semibold text-slate-500">Active Filters:</span>
            {selectedDate && (
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[11px] bg-slate-100 text-slate-700 font-medium">
                Date: {selectedDate}
                <button
                  type="button"
                  onClick={() => setSelectedDate("")}
                  className="hover:text-rose-600 ml-0.5 cursor-pointer"
                >
                  <X size={12} />
                </button>
              </span>
            )}
            <button
              type="button"
              onClick={() => {
                setSearch("");
                setSelectedShopId("");
                setSelectedDate("");
              }}
              className="text-[11px] text-rose-600 hover:underline font-medium cursor-pointer"
            >
              Reset all filters
            </button>
          </div>
        )}
      </div>

      {/* 4. Bills Table */}
      <div className="bg-white rounded-2xl border border-slate-200 shadow-xs overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead className="bg-slate-50/80 border-b border-slate-200 text-slate-600 font-semibold uppercase tracking-wider text-[10px]">
              <tr>
                <th className="py-3 px-4">Bill Number</th>
                <th className="py-3 px-4">Date</th>
                <th className="py-3 px-4">Consignee / Shop</th>
                <th className="py-3 px-4">Dispatched Units & Models</th>
                <th className="py-3 px-4">Dispatched By</th>
                <th className="py-3 px-4">Vehicle / Ref</th>
                <th className="py-3 px-4 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100 text-slate-700">
              {loading ? (
                <tr>
                  <td colSpan={7} className="text-center py-12 text-slate-400">
                    <div className="flex flex-col items-center gap-2">
                      <div className="w-6 h-6 border-2 border-[#3C3489] border-t-transparent rounded-full animate-spin" />
                      <span>Loading bills...</span>
                    </div>
                  </td>
                </tr>
              ) : bills.length === 0 ? (
                <tr>
                  <td colSpan={7} className="text-center py-14 text-slate-400">
                    <div className="flex flex-col items-center gap-2">
                      <Receipt size={32} className="opacity-30 text-[#3C3489]" />
                      <p className="font-semibold text-slate-600">No dispatch bills found</p>
                      <p className="text-[11px] text-slate-400">
                        When outward dispatches are submitted with a bill number, they will appear here.
                      </p>
                    </div>
                  </td>
                </tr>
              ) : (
                bills.map((bill) => (
                  <tr
                    key={bill.bill_number + bill.created_at}
                    onClick={() => openBillDetail(bill.bill_number)}
                    className="hover:bg-slate-50/80 cursor-pointer transition-colors"
                  >
                    {/* Bill Number Badge */}
                    <td className="py-3 px-4">
                      <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-bold bg-[#EEF2FF] text-[#3C3489] border border-[#C7D2FE]">
                        <Hash size={12} className="opacity-70" />
                        {bill.bill_number}
                      </span>
                    </td>

                    {/* Date */}
                    <td className="py-3 px-4 font-medium text-slate-800 whitespace-nowrap">
                      {bill.transaction_date}
                    </td>

                    {/* Shop */}
                    <td className="py-3 px-4">
                      <div>
                        <span className="font-semibold text-slate-900 block leading-tight">{bill.shop_name}</span>
                        <span className="text-[11px] text-slate-400 font-medium">{bill.shop_city}</span>
                      </div>
                    </td>

                    {/* Models & Quantities */}
                    <td className="py-3 px-4">
                      <div className="space-y-1">
                        <span className="inline-block px-2 py-0.5 rounded text-[11px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
                          {bill.total_units} unit{bill.total_units > 1 ? "s" : ""} ({bill.total_batches} model
                          {bill.total_batches > 1 ? "s" : ""})
                        </span>
                        <p className="text-[11px] text-slate-500 line-clamp-1">
                          {bill.models_summary.join(" • ")}
                        </p>
                      </div>
                    </td>

                    {/* Dispatched By */}
                    <td className="py-3 px-4 text-slate-600 font-medium whitespace-nowrap">
                      {bill.dispatched_by_name}
                    </td>

                    {/* Delivery Reference */}
                    <td className="py-3 px-4 text-slate-500 text-[11px] whitespace-nowrap">
                      {bill.delivery_reference ? (
                        <span className="inline-flex items-center gap-1 font-mono text-slate-700">
                          <Truck size={12} className="text-slate-400" />
                          {bill.delivery_reference}
                        </span>
                      ) : (
                        <span className="text-slate-300">-</span>
                      )}
                    </td>

                    {/* Actions */}
                    <td className="py-3 px-4 text-right whitespace-nowrap">
                      <div className="inline-flex items-center gap-1">
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            openBillDetail(bill.bill_number);
                          }}
                          title="View Bill Details"
                          className="p-1.5 rounded-lg text-slate-500 hover:text-[#3C3489] hover:bg-[#EEF2FF] transition-colors"
                        >
                          <Eye size={15} />
                        </button>

                        <button
                          onClick={(e) => handleQuickDownloadPdf(e, bill.bill_number)}
                          title="Download PDF Delivery Challan"
                          className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg text-[11px] font-semibold text-white bg-[#3C3489] hover:bg-[#2E286B] transition-colors shadow-xs"
                        >
                          <FileDown size={13} />
                          PDF
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Loading Overlay when fetching detail */}
      {detailLoading && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/30 backdrop-blur-xs">
          <div className="bg-white px-5 py-4 rounded-2xl shadow-xl flex items-center gap-3 border border-slate-200">
            <div className="w-5 h-5 border-2 border-[#3C3489] border-t-transparent rounded-full animate-spin" />
            <span className="text-xs font-semibold text-slate-700">Loading bill details...</span>
          </div>
        </div>
      )}

      {/* Error Toast */}
      {detailError && (
        <div className="fixed bottom-4 right-4 z-50 bg-rose-600 text-white text-xs px-4 py-2.5 rounded-xl shadow-lg flex items-center gap-2">
          <span>{detailError}</span>
          <button onClick={() => setDetailError(null)} className="p-0.5 hover:bg-white/20 rounded">
            <X size={14} />
          </button>
        </div>
      )}

      {/* 5. Detailed Modal when clicked */}
      {selectedBill && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-2 sm:p-4 md:p-6">
          <div
            className="fixed inset-0 bg-slate-900/60 backdrop-blur-xs transition-opacity"
            onClick={() => setSelectedBill(null)}
          />

          <div
            className="relative w-full max-w-4xl max-h-[92vh] flex flex-col bg-white rounded-2xl shadow-2xl border border-slate-200 overflow-hidden z-10 animate-in fade-in zoom-in-95 duration-150"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Modal Header */}
            <div className="shrink-0 bg-[#1E1B4B] text-white px-5 sm:px-6 py-4 flex items-start justify-between">
                <div>
                  <div className="flex items-center gap-2">
                    <span className="px-2.5 py-0.5 rounded-md bg-white/20 text-white font-mono font-bold text-xs">
                      BILL #{selectedBill.bill_number}
                    </span>
                    <span className="text-xs text-indigo-200 font-medium">
                      {selectedBill.transaction_date}
                    </span>
                  </div>
                  <h2 className="text-xl font-bold mt-1 tracking-tight text-white">
                    {selectedBill.shop_name}{selectedBill.shop_city ? ` (${selectedBill.shop_city})` : ""}
                  </h2>
                  <p className="text-xs text-indigo-200 mt-0.5">
                    Dispatched by {selectedBill.dispatched_by_name} • Ref:{" "}
                    {selectedBill.delivery_reference || "Direct / Local"}
                    {selectedBill.remarks ? ` • Remarks: ${selectedBill.remarks}` : ""}
                  </p>
                </div>

                <div className="flex items-center gap-2">
                  <button
                    onClick={handleDownloadDetailPdf}
                    disabled={downloadingPdf}
                    className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-white text-[#1E1B4B] text-xs font-bold hover:bg-indigo-50 transition-colors shadow-sm"
                  >
                    <FileDown size={14} />
                    {downloadingPdf ? "Generating..." : "Download PDF"}
                  </button>

                  <button
                    onClick={() => setSelectedBill(null)}
                    className="p-1.5 rounded-lg text-white/70 hover:text-white hover:bg-white/10 transition-colors"
                  >
                    <X size={18} />
                  </button>
                </div>
              </div>

              {/* Modal Body */}
              <div className="flex-1 overflow-y-auto p-5 sm:p-6 space-y-6 min-h-0">
                {/* 1. Summary Cards */}
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                  <div className="bg-slate-50 border border-slate-200 p-3 rounded-xl">
                    <span className="text-[10px] font-semibold uppercase text-slate-500">Total Units</span>
                    <p className="text-xl font-black text-slate-900 mt-0.5">{selectedBill.total_units}</p>
                  </div>
                  <div className="bg-slate-50 border border-slate-200 p-3 rounded-xl">
                    <span className="text-[10px] font-semibold uppercase text-slate-500">Models</span>
                    <p className="text-xl font-black text-slate-900 mt-0.5">{selectedBill.total_batches}</p>
                  </div>
                  <div className="bg-emerald-50 border border-emerald-200 p-3 rounded-xl">
                    <span className="text-[10px] font-semibold uppercase text-emerald-700">Matched Serials</span>
                    <p className="text-xl font-black text-emerald-800 mt-0.5">
                      {selectedBill.batches.reduce((acc, b) => acc + b.matched_count, 0)}
                    </p>
                  </div>
                  <div className="bg-amber-50 border border-amber-200 p-3 rounded-xl">
                    <span className="text-[10px] font-semibold uppercase text-amber-700">Recorded Only</span>
                    <p className="text-xl font-black text-amber-800 mt-0.5">
                      {selectedBill.batches.reduce((acc, b) => acc + b.unmatched_count, 0)}
                    </p>
                  </div>
                </div>

                {/* 2. Model Breakdown Table */}
                <div>
                  <h3 className="text-sm font-bold text-slate-900 mb-2 flex items-center gap-1.5">
                    <Layers size={16} className="text-[#3C3489]" />
                    Models in this Dispatch
                  </h3>
                  <div className="border border-slate-200 rounded-xl overflow-hidden">
                    <table className="w-full text-left text-xs">
                      <thead className="bg-slate-50 text-slate-600 font-semibold uppercase text-[10px] border-b border-slate-200">
                        <tr>
                          <th className="py-2.5 px-3">Brand & Model</th>
                          <th className="py-2.5 px-3">Description</th>
                          <th className="py-2.5 px-3 text-center">Matched</th>
                          <th className="py-2.5 px-3 text-center">Recorded</th>
                          <th className="py-2.5 px-3 text-center">Flagged</th>
                          <th className="py-2.5 px-3 text-right">Quantity</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100">
                        {selectedBill.batches.map((b) => (
                          <tr key={b.batch_id} className="hover:bg-slate-50/50">
                            <td className="py-2.5 px-3 font-bold text-slate-900">
                              {b.brand} {b.model}
                            </td>
                            <td className="py-2.5 px-3 text-slate-600">{b.product_name}</td>
                            <td className="py-2.5 px-3 text-center font-medium text-emerald-600">
                              {b.matched_count}
                            </td>
                            <td className="py-2.5 px-3 text-center font-medium text-slate-600">
                              {b.unmatched_count}
                            </td>
                            <td className="py-2.5 px-3 text-center font-medium text-amber-600">
                              {b.flagged_count}
                            </td>
                            <td className="py-2.5 px-3 text-right font-bold text-slate-900">
                              {b.quantity} unit{b.quantity > 1 ? "s" : ""}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>

                {/* 3. Scanned Serials List */}
                <div>
                  <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 mb-2">
                    <h3 className="text-sm font-bold text-slate-900 flex items-center gap-1.5">
                      <CheckCircle2 size={16} className="text-emerald-600" />
                      Scanned Serial Register ({filteredSerials.length} of {selectedBill.total_units})
                    </h3>
                    <div className="relative w-full sm:w-60">
                      <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-slate-400" />
                      <input
                        type="text"
                        placeholder="Search serial in this bill..."
                        value={serialSearch}
                        onChange={(e) => setSerialSearch(e.target.value)}
                        className="w-full pl-7 pr-3 py-1 text-xs rounded-lg border border-slate-200 focus:outline-none focus:ring-1 focus:ring-[#3C3489]"
                      />
                    </div>
                  </div>

                  <div className="border border-slate-200 rounded-xl overflow-hidden max-h-64 overflow-y-auto">
                    <table className="w-full text-left text-xs">
                      <thead className="bg-slate-50 text-slate-600 font-semibold uppercase text-[10px] border-b border-slate-200 sticky top-0 z-10">
                        <tr>
                          <th className="py-2 px-3">#</th>
                          <th className="py-2 px-3">Model</th>
                          <th className="py-2 px-3">Serial Number</th>
                          <th className="py-2 px-3 text-center">Unit Type</th>
                          <th className="py-2 px-3 text-right">Verification</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100 font-sans">
                        {filteredSerials.map((s, idx) => (
                          <tr key={s.serial_text + idx} className="hover:bg-slate-50/50">
                            <td className="py-2 px-3 text-slate-400 text-[10px]">{idx + 1}</td>
                            <td className="py-2 px-3 font-semibold text-slate-800">
                              {s.brand} {s.model}
                            </td>
                            <td className="py-2 px-3 font-mono font-bold text-slate-900">
                              {s.serial_text}
                            </td>
                            <td className="py-2 px-3 text-center">
                              {s.unit_type ? (
                                <span
                                  className={`inline-block px-2 py-0.5 rounded text-[10px] font-bold ${
                                    s.unit_type.toLowerCase() === "indoor"
                                      ? "bg-indigo-50 text-indigo-700 border border-indigo-200"
                                      : "bg-teal-50 text-teal-700 border border-teal-200"
                                  }`}
                                >
                                  {s.unit_type.toUpperCase()}
                                </span>
                              ) : (
                                <span className="text-slate-300">-</span>
                              )}
                            </td>
                            <td className="py-2 px-3 text-right">
                              <span
                                className={`inline-block px-2 py-0.5 rounded text-[10px] font-bold ${
                                  s.is_flagged
                                    ? "bg-amber-50 text-amber-700 border border-amber-200"
                                    : s.status_label === "Matched"
                                    ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                                    : "bg-slate-100 text-slate-600 border border-slate-200"
                                }`}
                              >
                                {s.status_label}
                              </span>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              </div>

              {/* Modal Footer */}
              <div className="shrink-0 bg-slate-50 border-t border-slate-200 px-5 sm:px-6 py-3.5 flex items-center justify-between">
                <span className="text-xs text-slate-500">
                  Ready to print or share delivery challan with dealer.
                </span>
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => setSelectedBill(null)}
                    className="px-4 py-2 rounded-xl text-xs font-semibold text-slate-600 hover:bg-slate-200/60 transition-colors"
                  >
                    Close
                  </button>
                  <button
                    onClick={handleDownloadDetailPdf}
                    className="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl bg-[#3C3489] text-white text-xs font-bold hover:bg-[#2E286B] transition-colors shadow-sm"
                  >
                    <FileDown size={14} />
                    Download PDF Challan
                  </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
