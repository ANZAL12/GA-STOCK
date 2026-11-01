import React, { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { apiRequest } from "../api/client";
import { useWebSocket } from "../api/useWebSocket";
import { useAuth } from "../context/AuthContext";
import type { SerialDetail, SerialListItem, SerialListResponse } from "../types";
import { Badge } from "../components/Badge";
import { Modal } from "../components/Modal";
import { 
  Barcode, 
  Building2, 
  AlertCircle, 
  Clock, 
  Wrench, 
  Search,
  ArrowDownLeft,
  ArrowUpRight,
  ChevronLeft,
  ChevronRight,
  ChevronsLeft,
  ChevronsRight,
  Layers,
  FileDown,
  Printer,
  FileSpreadsheet
} from "lucide-react";
import { generateSerialListPdf, generateSerialTracePdf } from "../utils/generateSerialReportPdf";

export const SerialsPage: React.FC = () => {
  const { isAdmin } = useAuth();
  const [serials, setSerials] = useState<SerialListItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState("");
  const [debouncedSearch, setDebouncedSearch] = useState("");
  const [flowFilter, setFlowFilter] = useState<"all" | "inward" | "outward" | "damaged">("all");
  const [currentPage, setCurrentPage] = useState<number>(1);
  const [jumpPageInput, setJumpPageInput] = useState<string>("");
  const pageSize = 100;

  // Table Top Anchor & Page Change Scroll Tracking
  const tableTopRef = useRef<HTMLDivElement>(null);
  const isPageChangingRef = useRef(false);

  // Selected Serial Lifecycle Detail Modal
  const [selectedSerial, setSelectedSerial] = useState<SerialDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState<string | null>(null);

  // Status Change Modal
  const [isStatusModalOpen, setIsStatusModalOpen] = useState(false);
  const [newStatus, setNewStatus] = useState<string>("damaged");
  const [statusReason, setStatusReason] = useState("");
  const [statusRemarks, setStatusRemarks] = useState("");
  const [statusSubmitting, setStatusSubmitting] = useState(false);
  const [statusError, setStatusError] = useState<string | null>(null);

  const [totalCounts, setTotalCounts] = useState({
    total: 0,
    inward: 0,
    outward: 0,
    damaged: 0,
  });

  const fetchSerials = async (flow = flowFilter, query = searchQuery, page = currentPage) => {
    try {
      setLoading(true);
      const params = new URLSearchParams();
      params.append("limit", String(pageSize));
      params.append("offset", String((page - 1) * pageSize));
      if (flow && flow !== "all") params.append("flow", flow);
      if (query.trim()) params.append("q", query.trim());

      const res = await apiRequest<SerialListResponse>(`/serials?${params.toString()}`);
      setSerials(res.items);
      setTotalCounts({
        total: res.total || 0,
        inward: res.total_inward ?? res.items.filter((s) => s.flow_type === "inward").length,
        outward: res.total_outward ?? res.items.filter((s) => s.flow_type === "outward").length,
        damaged: res.total_damaged ?? 0,
      });
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  // Debounce search input keystrokes (250ms)
  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedSearch(searchQuery);
    }, 250);
    return () => clearTimeout(handler);
  }, [searchQuery]);

  // Fetch immediately whenever flowFilter, debouncedSearch, or currentPage changes
  useEffect(() => {
    fetchSerials(flowFilter, debouncedSearch, currentPage);
  }, [flowFilter, debouncedSearch, currentPage]);

  // Keep scroll aligned with the top of the table after new page data renders
  useEffect(() => {
    if (isPageChangingRef.current) {
      isPageChangingRef.current = false;
      requestAnimationFrame(() => {
        scrollToTableTop("smooth");
      });
    }
  }, [serials]);

  useWebSocket((event) => {
    if (
      event === "stock_updated" ||
      event === "product_created" ||
      event === "product_updated" ||
      event === "product_deleted"
    ) {
      fetchSerials(flowFilter, debouncedSearch, currentPage);
    }
  });

  const openSerialTrace = async (serialText: string) => {
    setDetailLoading(true);
    setDetailError(null);
    try {
      const res = await apiRequest<SerialDetail>(`/serials/lookup?serial_number=${encodeURIComponent(serialText)}`);
      setSelectedSerial(res);
    } catch (err: any) {
      setDetailError(err.message || "Failed to load serial lifecycle trace.");
    } finally {
      setDetailLoading(false);
    }
  };

  const handleStatusSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedSerial?.serial_number_id) return;
    if (!statusReason.trim()) {
      setStatusError("Reason for status change is mandatory.");
      return;
    }

    setStatusSubmitting(true);
    setStatusError(null);

    try {
      const updated = await apiRequest<SerialDetail>(`/serials/${selectedSerial.serial_number_id}/status`, {
        method: "PATCH",
        body: JSON.stringify({
          new_status: newStatus,
          reason: statusReason.trim(),
          remarks: statusRemarks.trim() || null,
        }),
      });
      setSelectedSerial(updated);
      setIsStatusModalOpen(false);
      setStatusReason("");
      setStatusRemarks("");
      fetchSerials();
    } catch (err: any) {
      setStatusError(err.message || "Failed to update serial status.");
    } finally {
      setStatusSubmitting(false);
    }
  };

  // Paginated Serials list for current page
  const filteredSerials = serials;

  const inwardCount = totalCounts.inward || serials.filter((s) => s.flow_type === "inward").length;
  const outwardCount = totalCounts.outward || serials.filter((s) => s.flow_type === "outward").length;
  const attentionCount = totalCounts.damaged || serials.filter(
    (s) =>
      s.is_damaged ||
      s.is_dispatched_damaged ||
      ["damaged", "under_repair", "lost"].includes(s.status) ||
      Boolean(s.flag_reason?.toLowerCase().includes("damage"))
  ).length;

  const getActiveTotal = () => {
    if (searchQuery.trim()) {
      return totalCounts.total;
    }
    if (flowFilter === "inward") return inwardCount;
    if (flowFilter === "outward") return outwardCount;
    if (flowFilter === "damaged") return attentionCount;
    return totalCounts.total;
  };

  const activeTotal = getActiveTotal();
  const totalPages = Math.max(1, Math.ceil(activeTotal / pageSize));

  const handleFlowFilterChange = (flow: "all" | "inward" | "outward" | "damaged") => {
    setFlowFilter(flow);
    setCurrentPage(1);
  };

  const handleSearchChange = (val: string) => {
    setSearchQuery(val);
    setCurrentPage(1);
  };

  // Scroll to table top with compensation for sticky navbar
  const scrollToTableTop = (behavior: ScrollBehavior = "smooth") => {
    if (tableTopRef.current) {
      tableTopRef.current.scrollIntoView({ behavior, block: "start" });
    } else {
      window.scrollTo({ top: 0, behavior });
    }
  };

  const handlePageChange = (newPage: number) => {
    const target = Math.max(1, Math.min(newPage, totalPages));
    if (target !== currentPage) {
      isPageChangingRef.current = true;
      setCurrentPage(target);
      // Trigger smooth scroll immediately on click
      scrollToTableTop("smooth");
    }
  };

  const handleJumpSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const p = parseInt(jumpPageInput.trim(), 10);
    if (!isNaN(p) && p >= 1 && p <= totalPages) {
      handlePageChange(p);
      setJumpPageInput("");
    }
  };

  const getPageNumbers = () => {
    const pages: (number | string)[] = [];
    if (totalPages <= 7) {
      for (let i = 1; i <= totalPages; i++) pages.push(i);
    } else {
      if (currentPage <= 4) {
        pages.push(1, 2, 3, 4, 5, "...", totalPages);
      } else if (currentPage >= totalPages - 3) {
        pages.push(1, "...", totalPages - 4, totalPages - 3, totalPages - 2, totalPages - 1, totalPages);
      } else {
        pages.push(1, "...", currentPage - 1, currentPage, currentPage + 1, "...", totalPages);
      }
    }
    return pages;
  };

  const getFilterLabel = () => {
    switch (flowFilter) {
      case "inward":
        return "Inward / In Stock";
      case "outward":
        return "Outward / Dispatched";
      case "damaged":
        return "Attention (Damaged / Repair / Lost)";
      default:
        return "All Serials";
    }
  };

  const handleExportList = (isPrint: boolean) => {
    generateSerialListPdf({
      items: filteredSerials,
      filterLabel: getFilterLabel(),
      searchQuery: searchQuery.trim() || undefined,
      isPrint,
    });
  };

  return (
    <div className="space-y-6 animate-fade-in pb-12">
      
      {/* Title & Quick Stats */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            Serial Number Registry
          </h1>
          <p className="text-xs text-slate-500 font-medium mt-0.5">
            Complete inventory log of inward and outward appliance serials • {(totalCounts.total || serials.length).toLocaleString()} total registered serials
          </p>
        </div>

        {/* Action Buttons & Quick summary badges */}
        <div className="flex flex-wrap items-center gap-2.5">
          {isAdmin && (
            <Link
              to="/import-serials"
              className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-indigo-50 border border-indigo-200 text-xs font-semibold text-[#3C3489] hover:bg-indigo-100/80 transition-all shadow-sm"
              title="Import Serial Numbers from Excel or CSV via Column Select"
            >
              <FileSpreadsheet size={14} />
              <span>Import Excel Serials</span>
            </Link>
          )}

          <button
            onClick={() => handleExportList(false)}
            disabled={filteredSerials.length === 0}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-white border border-slate-200 text-xs font-semibold text-slate-700 hover:text-[#3C3489] hover:border-[#3C3489]/40 hover:bg-slate-50 transition-all shadow-sm cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
            title="Download PDF report of current serials"
          >
            <FileDown size={14} className="text-[#3C3489]" />
            <span>Export PDF</span>
          </button>

          <button
            onClick={() => handleExportList(true)}
            disabled={filteredSerials.length === 0}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#3C3489] text-white text-xs font-semibold hover:bg-[#312B72] transition-all shadow-sm cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
            title="Print current serials registry table"
          >
            <Printer size={14} />
            <span>Print</span>
          </button>

          <div className="h-6 w-[1px] bg-slate-200 mx-1 hidden sm:block" />

          <div className="px-3 py-1.5 rounded-xl bg-white border border-slate-200 text-xs shadow-sm flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-emerald-500" />
            <span className="text-slate-500 font-medium">In Stock:</span>
            <span className="font-bold text-slate-900">{inwardCount.toLocaleString()}</span>
          </div>
          <div className="px-3 py-1.5 rounded-xl bg-white border border-slate-200 text-xs shadow-sm flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-[#3C3489]" />
            <span className="text-slate-500 font-medium">Dispatched:</span>
            <span className="font-bold text-slate-900">{outwardCount.toLocaleString()}</span>
          </div>
        </div>
      </div>

      {/* Filter Tabs & Search Bar */}
      <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3">
        {/* Flow Tabs */}
        <div className="flex items-center gap-1 p-1 bg-slate-100 rounded-xl w-fit text-xs font-medium">
          <button
            onClick={() => handleFlowFilterChange("all")}
            className={`px-3 py-1.5 rounded-lg transition-all cursor-pointer ${
              flowFilter === "all"
                ? "bg-white text-slate-900 font-semibold shadow-sm"
                : "text-slate-600 hover:text-slate-900"
            }`}
          >
            All Serials ({(totalCounts.total || serials.length).toLocaleString()})
          </button>
          <button
            onClick={() => handleFlowFilterChange("inward")}
            className={`px-3 py-1.5 rounded-lg transition-all cursor-pointer flex items-center gap-1.5 ${
              flowFilter === "inward"
                ? "bg-white text-emerald-700 font-semibold shadow-sm"
                : "text-slate-600 hover:text-slate-900"
            }`}
          >
            <ArrowDownLeft size={13} className="text-emerald-600" />
            <span>Inward / In Stock ({inwardCount.toLocaleString()})</span>
          </button>
          <button
            onClick={() => handleFlowFilterChange("outward")}
            className={`px-3 py-1.5 rounded-lg transition-all cursor-pointer flex items-center gap-1.5 ${
              flowFilter === "outward"
                ? "bg-white text-[#3C3489] font-semibold shadow-sm"
                : "text-slate-600 hover:text-slate-900"
            }`}
          >
            <ArrowUpRight size={13} className="text-[#3C3489]" />
            <span>Outward / Dispatched ({outwardCount.toLocaleString()})</span>
          </button>
          {attentionCount > 0 && (
            <button
              onClick={() => handleFlowFilterChange("damaged")}
              className={`px-3 py-1.5 rounded-lg transition-all cursor-pointer flex items-center gap-1.5 ${
                flowFilter === "damaged"
                  ? "bg-white text-rose-700 font-semibold shadow-sm"
                  : "text-slate-600 hover:text-slate-900"
              }`}
            >
              <AlertCircle size={13} className="text-rose-600" />
              <span>Attention ({attentionCount.toLocaleString()})</span>
            </button>
          )}
        </div>

        {/* Live Search Input */}
        <div className="relative max-w-sm w-full sm:w-80">
          <Search size={15} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => handleSearchChange(e.target.value)}
            placeholder="Search serial, model, brand, shop, ref..."
            className="w-full pl-9 pr-4 py-2 text-xs rounded-xl border border-slate-200 bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] text-slate-800 placeholder-slate-400 shadow-sm"
          />
        </div>
      </div>

      {/* Anchor for smooth pagination scroll-to-top */}
      <div ref={tableTopRef} id="serials-table-top" className="scroll-mt-24" />

      {/* Serials Table */}
      <div className="bg-white border border-slate-200 rounded-2xl shadow-sm overflow-hidden">
        {loading && serials.length === 0 ? (
          <div className="py-20 text-center text-xs text-slate-400">
            <div className="w-6 h-6 border-2 border-[#3C3489] border-t-transparent rounded-full animate-spin mx-auto mb-2" />
            Loading serial records...
          </div>
        ) : filteredSerials.length === 0 ? (
          <div className="py-20 text-center text-xs text-slate-400">
            No serials match the current filter or search criteria.
          </div>
        ) : (
          <div className="relative">
            {/* Top Table Pagination & Quick Switcher */}
            <div className="px-5 py-2.5 bg-slate-50 border-b border-slate-200 flex items-center justify-between text-xs text-slate-500 select-none">
              <div className="flex items-center gap-2">
                <span>
                  Showing <span className="font-semibold text-slate-800">{activeTotal === 0 ? 0 : ((currentPage - 1) * pageSize + 1).toLocaleString()} – {Math.min(currentPage * pageSize, activeTotal).toLocaleString()}</span> of <span className="font-bold text-slate-900">{activeTotal.toLocaleString()}</span>
                </span>
                <span className="hidden sm:inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-semibold bg-indigo-50 text-[#3C3489] border border-indigo-100">
                  Page {currentPage} of {totalPages}
                </span>
              </div>
              <div className="flex items-center gap-1.5">
                <button
                  type="button"
                  onClick={() => handlePageChange(currentPage - 1)}
                  disabled={currentPage === 1 || loading}
                  className="p-1 rounded-lg border border-slate-200 bg-white text-slate-600 hover:bg-slate-100 hover:text-slate-900 disabled:opacity-40 disabled:cursor-not-allowed transition-all"
                  title="Previous Page"
                >
                  <ChevronLeft size={13} />
                </button>
                <span className="text-xs font-semibold px-1 text-slate-700 min-w-[45px] text-center">
                  {currentPage} / {totalPages}
                </span>
                <button
                  type="button"
                  onClick={() => handlePageChange(currentPage + 1)}
                  disabled={currentPage >= totalPages || loading}
                  className="p-1 rounded-lg border border-slate-200 bg-white text-slate-600 hover:bg-slate-100 hover:text-slate-900 disabled:opacity-40 disabled:cursor-not-allowed transition-all"
                  title="Next Page"
                >
                  <ChevronRight size={13} />
                </button>
              </div>
            </div>

            {loading && (
              <div className="absolute inset-0 bg-white/60 backdrop-blur-[1px] z-10 flex items-center justify-center">
                <div className="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-white shadow-md border border-slate-200 text-xs font-semibold text-slate-700">
                  <div className="w-4 h-4 border-2 border-[#3C3489] border-t-transparent rounded-full animate-spin" />
                  <span>Loading page {currentPage}...</span>
                </div>
              </div>
            )}
            <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead className="bg-slate-50 border-b border-slate-200 text-slate-500 font-semibold uppercase text-[10px] tracking-wider">
                <tr>
                  <th className="py-3 px-4">Serial Number</th>
                  <th className="py-3 px-4">Flow / Type</th>
                  <th className="py-3 px-4">Model & Brand</th>
                  <th className="py-3 px-4">Category</th>
                  <th className="py-3 px-4">Status</th>
                  <th className="py-3 px-4">Date & Time</th>
                  <th className="py-3 px-4">Destination Shop</th>
                  <th className="py-3 px-4">Reference</th>
                  <th className="py-3 px-4 text-right">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                {filteredSerials.map((item, idx) => (
                  <tr 
                    key={idx}
                    onClick={() => openSerialTrace(item.serial_number)}
                    className="hover:bg-slate-50/80 transition-colors cursor-pointer group"
                  >
                    {/* Serial Number */}
                    <td className="py-3.5 px-4 font-mono font-bold text-slate-900">
                      <div className="flex items-center gap-1.5 flex-wrap">
                        <Barcode size={14} className="text-slate-400 group-hover:text-[#3C3489] transition-colors shrink-0" />
                        <span>{item.serial_number}</span>
                        {item.unit_type && (
                          <span className={`text-[11px] font-sans font-semibold ${
                            item.unit_type.toLowerCase() === 'indoor' ? 'text-indigo-600' : 'text-teal-600'
                          }`}>
                            ({item.unit_type.charAt(0).toUpperCase() + item.unit_type.slice(1).toLowerCase()})
                          </span>
                        )}
                        {!item.is_matched && (
                          <span className="text-[10px] font-normal px-1.5 py-0.5 rounded bg-slate-100 text-slate-500 font-sans">
                            Pre-go-live
                          </span>
                        )}
                      </div>

                      {/* Small Colored Damaged Indicator Under Serial Number */}
                      {(item.is_damaged || item.is_dispatched_damaged || item.status === "damaged" || item.flag_reason?.toLowerCase().includes("damage")) && (
                        <div className="mt-1 flex items-center gap-1.5 flex-wrap">
                          <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-bold uppercase tracking-wider bg-rose-50 text-rose-700 border border-rose-200">
                            <span className="w-1.5 h-1.5 rounded-full bg-rose-500 animate-pulse" />
                            Damaged
                          </span>
                          {item.flow_type === "outward" && (
                            <span className="text-[10px] font-semibold text-rose-600">
                              (Dispatched Damaged)
                            </span>
                          )}
                        </div>
                      )}
                    </td>

                    {/* Flow Type Badge */}
                    <td className="py-3.5 px-4">
                      {item.flow_type === "inward" ? (
                        <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200">
                          <ArrowDownLeft size={12} />
                          <span>Inward</span>
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-semibold bg-indigo-50 text-indigo-700 border border-indigo-200">
                          <ArrowUpRight size={12} />
                          <span>Outward</span>
                        </span>
                      )}
                    </td>

                    {/* Model & Brand */}
                    <td className="py-3.5 px-4">
                      <div className="font-semibold text-slate-900">{item.brand} {item.model}</div>
                      <div className="text-[11px] text-slate-400 font-normal">{item.product_name}</div>
                    </td>

                    {/* Category */}
                    <td className="py-3.5 px-4">
                      <span className="inline-flex items-center gap-1 text-[11px] text-slate-600 bg-slate-100 px-2 py-0.5 rounded-full font-medium">
                        <Layers size={10} className="text-slate-400" />
                        {item.category_name || "General"}
                      </span>
                    </td>

                    {/* Status */}
                    <td className="py-3.5 px-4">
                      <Badge label={item.status_label} />
                    </td>

                    {/* Date & Time */}
                    <td className="py-3.5 px-4 text-slate-600">
                      <div>
                        {item.transaction_date 
                          ? new Date(item.transaction_date).toLocaleDateString("en-IN", { month: "short", day: "numeric", year: "numeric" })
                          : new Date(item.created_at).toLocaleDateString("en-IN", { month: "short", day: "numeric", year: "numeric" })
                        }
                      </div>
                      <div className="text-[10px] text-slate-400">
                        {new Date(item.created_at).toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" })}
                      </div>
                    </td>

                    {/* Destination Shop */}
                    <td className="py-3.5 px-4">
                      {item.shop_name ? (
                        <div className="flex items-center gap-1.5">
                          <Building2 size={13} className="text-slate-400 shrink-0" />
                          <div>
                            <span className="font-semibold text-slate-800">{item.shop_name}</span>
                            {item.shop_city && (
                              <span className="text-slate-400 text-[11px] block">({item.shop_city})</span>
                            )}
                          </div>
                        </div>
                      ) : (
                        <span className="text-slate-400 text-[11px] italic">In Godown</span>
                      )}
                    </td>

                    {/* Reference */}
                    <td className="py-3.5 px-4 font-mono text-[11px] text-slate-500">
                      {item.bill_number ? (
                        <div>
                          <span className="font-semibold text-slate-800">{item.bill_number}</span>
                          {item.delivery_reference && item.delivery_reference !== item.bill_number && (
                            <span className="text-[10px] text-slate-400 block font-normal font-sans">
                              Veh: {item.delivery_reference}
                            </span>
                          )}
                        </div>
                      ) : (
                        <span>{item.reference ? item.reference : "—"}</span>
                      )}
                    </td>

                    {/* Action */}
                    <td className="py-3.5 px-4 text-right">
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          openSerialTrace(item.serial_number);
                        }}
                        className="inline-flex items-center gap-1 text-[11px] font-semibold text-[#3C3489] hover:text-[#312B72] px-2.5 py-1 rounded-lg hover:bg-[#3C3489]/5 transition-colors cursor-pointer"
                      >
                        <span>Trace</span>
                        <ChevronRight size={13} />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Pagination Footer Bar */}
          <div className="px-5 py-3.5 bg-slate-50 border-t border-slate-200 flex flex-col md:flex-row items-center justify-between gap-4 select-none">
            
            {/* Left: Range and Total Counts */}
            <div className="flex items-center gap-2 text-xs text-slate-500">
              <span className="font-semibold text-slate-700">
                Showing {activeTotal === 0 ? 0 : ((currentPage - 1) * pageSize + 1).toLocaleString()} – {Math.min(currentPage * pageSize, activeTotal).toLocaleString()}
              </span>
              <span>of</span>
              <span className="font-bold text-slate-900">{activeTotal.toLocaleString()}</span>
              <span>records</span>
              <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-semibold bg-indigo-50 text-[#3C3489] border border-indigo-100 ml-1">
                100 per page
              </span>
            </div>

            {/* Center: Pagination Buttons */}
            <div className="flex items-center gap-1">
              {/* First Page */}
              <button
                type="button"
                onClick={() => handlePageChange(1)}
                disabled={currentPage === 1 || loading}
                className="p-1.5 rounded-lg border border-slate-200 bg-white text-slate-600 hover:bg-slate-100 hover:text-slate-900 disabled:opacity-40 disabled:cursor-not-allowed transition-all"
                title="First Page"
              >
                <ChevronsLeft size={15} />
              </button>

              {/* Prev Page */}
              <button
                type="button"
                onClick={() => handlePageChange(currentPage - 1)}
                disabled={currentPage === 1 || loading}
                className="p-1.5 rounded-lg border border-slate-200 bg-white text-slate-600 hover:bg-slate-100 hover:text-slate-900 disabled:opacity-40 disabled:cursor-not-allowed transition-all"
                title="Previous Page"
              >
                <ChevronLeft size={15} />
              </button>

              {/* Numbered Page Buttons */}
              <div className="flex items-center gap-1 mx-1">
                {getPageNumbers().map((pg, idx) => {
                  if (pg === "...") {
                    return (
                      <span key={`dots-${idx}`} className="px-2 py-1 text-xs text-slate-400">
                        ...
                      </span>
                    );
                  }
                  const pageNum = Number(pg);
                  const isActive = pageNum === currentPage;
                  return (
                    <button
                      key={`page-${pageNum}`}
                      type="button"
                      onClick={() => handlePageChange(pageNum)}
                      disabled={loading}
                      className={`min-w-[32px] h-8 px-2 text-xs font-semibold rounded-lg transition-all ${
                        isActive
                          ? "bg-[#3C3489] text-white shadow-sm"
                          : "bg-white border border-slate-200 text-slate-700 hover:bg-slate-100 hover:text-slate-900"
                      }`}
                    >
                      {pageNum}
                    </button>
                  );
                })}
              </div>

              {/* Next Page */}
              <button
                type="button"
                onClick={() => handlePageChange(currentPage + 1)}
                disabled={currentPage >= totalPages || loading}
                className="p-1.5 rounded-lg border border-slate-200 bg-white text-slate-600 hover:bg-slate-100 hover:text-slate-900 disabled:opacity-40 disabled:cursor-not-allowed transition-all"
                title="Next Page"
              >
                <ChevronRight size={15} />
              </button>

              {/* Last Page */}
              <button
                type="button"
                onClick={() => handlePageChange(totalPages)}
                disabled={currentPage >= totalPages || loading}
                className="p-1.5 rounded-lg border border-slate-200 bg-white text-slate-600 hover:bg-slate-100 hover:text-slate-900 disabled:opacity-40 disabled:cursor-not-allowed transition-all"
                title="Last Page"
              >
                <ChevronsRight size={15} />
              </button>
            </div>

            {/* Right: Quick jump to page */}
            <form onSubmit={handleJumpSubmit} className="flex items-center gap-1.5 text-xs">
              <span className="text-slate-500">Go to:</span>
              <input
                type="number"
                min={1}
                max={totalPages}
                value={jumpPageInput}
                onChange={(e) => setJumpPageInput(e.target.value)}
                placeholder={String(currentPage)}
                className="w-14 px-2 py-1 text-center font-medium text-xs rounded-lg border border-slate-200 bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
              />
              <button
                type="submit"
                className="px-2.5 py-1 text-xs font-semibold rounded-lg bg-white border border-slate-200 text-slate-700 hover:bg-slate-100 hover:text-slate-900 transition-all cursor-pointer shadow-xs"
              >
                Go
              </button>
            </form>

          </div>
        </div>
      )}
    </div>

      {/* Serial Detail / Lifecycle Modal */}
      <Modal
        isOpen={Boolean(selectedSerial)}
        onClose={() => setSelectedSerial(null)}
        title={selectedSerial ? `Serial Trace • ${selectedSerial.serial_number}${selectedSerial.unit_type ? ` (${selectedSerial.unit_type.charAt(0).toUpperCase() + selectedSerial.unit_type.slice(1).toLowerCase()})` : ""}` : ""}
        subtitle={selectedSerial ? `${selectedSerial.brand} ${selectedSerial.model} • ${selectedSerial.category_name || "Appliance"}` : ""}
        maxWidth="2xl"
      >
        {detailLoading ? (
          <div className="py-16 text-center text-xs text-slate-400">
            <div className="w-6 h-6 border-2 border-[#3C3489] border-t-transparent rounded-full animate-spin mx-auto mb-2" />
            Loading complete lifecycle history...
          </div>
        ) : detailError ? (
          <div className="p-4 bg-rose-50 border border-rose-200 rounded-xl text-rose-700 text-xs flex items-center gap-2">
            <AlertCircle size={15} />
            <span>{detailError}</span>
          </div>
        ) : selectedSerial && (
          <div className="space-y-6">
            
            {/* Header Fact Strip */}
            <div className={`grid grid-cols-1 ${selectedSerial.unit_type ? 'sm:grid-cols-5' : 'sm:grid-cols-4'} gap-3 p-4 rounded-xl bg-slate-50 border border-slate-200 text-xs`}>
              <div>
                <span className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">
                  Current Status
                </span>
                <span className="font-bold text-slate-900 mt-0.5 block capitalize">
                  {selectedSerial.status_label}
                </span>
                {(selectedSerial.is_damaged || selectedSerial.is_dispatched_damaged || selectedSerial.status === "damaged" || selectedSerial.flag_reason?.toLowerCase().includes("damage")) && (
                  <span className="inline-flex items-center gap-1 mt-1 px-1.5 py-0.5 rounded text-[10px] font-bold uppercase tracking-wider bg-rose-50 text-rose-700 border border-rose-200">
                    <span className="w-1.5 h-1.5 rounded-full bg-rose-500 animate-pulse" />
                    Damaged {selectedSerial.status === "dispatched" || selectedSerial.is_dispatched_damaged ? "(Dispatched Damaged)" : ""}
                  </span>
                )}
              </div>
              {selectedSerial.unit_type && (
                <div>
                  <span className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">
                    Unit Type
                  </span>
                  <span className={`font-semibold mt-0.5 block ${
                    selectedSerial.unit_type.toLowerCase() === 'indoor' ? 'text-indigo-600' : 'text-teal-600'
                  }`}>
                    {selectedSerial.unit_type.charAt(0).toUpperCase() + selectedSerial.unit_type.slice(1).toLowerCase()}
                  </span>
                </div>
              )}
              <div>
                <span className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">
                  Category
                </span>
                <span className="font-semibold text-slate-800 mt-0.5 block">
                  {selectedSerial.category_name || "General"}
                </span>
              </div>
              <div>
                <span className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">
                  Tracking Type
                </span>
                <span className="font-semibold text-slate-800 mt-0.5 block">
                  {selectedSerial.is_tracked ? "Scanned at Inward" : "Pre-go-live Outward"}
                </span>
              </div>
              <div>
                <span className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">
                  Destination Shop
                </span>
                <span className="font-semibold text-slate-800 mt-0.5 block">
                  {selectedSerial.last_shop_name 
                    ? `${selectedSerial.last_shop_name}${selectedSerial.last_shop_city ? ` (${selectedSerial.last_shop_city})` : ""}` 
                    : "In Godown"}
                </span>
              </div>
            </div>

            {/* Serial Trace PDF & Print Toolbar */}
            <div className="flex flex-wrap items-center justify-between gap-2.5 p-3 rounded-xl bg-slate-50 border border-slate-200">
              <div>
                <span className="text-xs font-semibold text-slate-800 block">Serial Lifecycle Audit Report</span>
                <span className="text-[11px] text-slate-500">Download or print full movement trace for #{selectedSerial.serial_number}</span>
              </div>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => generateSerialTracePdf({ serial: selectedSerial, isPrint: false })}
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white border border-slate-200 text-xs font-semibold text-slate-700 hover:text-[#3C3489] hover:border-[#3C3489]/40 hover:bg-slate-50 transition-all shadow-sm cursor-pointer"
                >
                  <FileDown size={13} className="text-[#3C3489]" />
                  <span>Download Trace PDF</span>
                </button>
                <button
                  type="button"
                  onClick={() => generateSerialTracePdf({ serial: selectedSerial, isPrint: true })}
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[#3C3489] text-white text-xs font-semibold hover:bg-[#312B72] transition-all shadow-sm cursor-pointer"
                >
                  <Printer size={13} />
                  <span>Print Trace</span>
                </button>
              </div>
            </div>

            {/* Adjust Status Action */}
            {selectedSerial.is_tracked && (
              <div className="flex items-center justify-between p-3 rounded-xl bg-indigo-50/50 border border-indigo-100">
                <div className="text-xs">
                  <span className="font-semibold text-indigo-950 block">Unit Status Adjustment</span>
                  <span className="text-[11px] text-indigo-700">Flag as damaged, lost, under repair, or restore to available stock.</span>
                </div>
                <button
                  onClick={() => setIsStatusModalOpen(true)}
                  className="px-3.5 py-1.5 rounded-xl text-xs font-semibold bg-[#3C3489] text-white hover:bg-[#312B72] transition-colors flex items-center gap-1.5 cursor-pointer shadow-sm"
                >
                  <Wrench size={13} />
                  <span>Adjust Status</span>
                </button>
              </div>
            )}

            {/* Complete Vertical Timeline */}
            <div className="space-y-4">
              <h3 className="text-xs font-bold uppercase tracking-wider text-slate-500 flex items-center gap-2">
                <Clock size={15} />
                Chronological Audit History
              </h3>

              <div className="relative pl-6 space-y-5 before:absolute before:left-2 before:top-2 before:bottom-2 before:w-0.5 before:bg-slate-200">
                {selectedSerial.history.map((h) => (
                  <div key={h.id} className="relative text-xs space-y-1">
                    <div className="absolute -left-6 top-1 w-2.5 h-2.5 rounded-full ring-4 bg-[#3C3489] ring-[#EEF2FF]" />
                    
                    <div className="flex flex-wrap items-baseline justify-between gap-2">
                      <span className="font-semibold text-slate-900 capitalize text-sm">
                        {h.action.replace(/_/g, " ")}
                      </span>
                      <span className="text-[11px] text-slate-400 font-mono">
                        {new Date(h.created_at).toLocaleString("en-IN", {
                          day: "numeric",
                          month: "short",
                          year: "numeric",
                          hour: "2-digit",
                          minute: "2-digit",
                        })}
                      </span>
                    </div>

                    {h.shop_name && (
                      <div className="flex items-center gap-1.5 text-slate-700 font-medium">
                        <Building2 size={13} className="text-slate-400" />
                        <span>{h.shop_name}{h.shop_city ? ` (${h.shop_city})` : ""}</span>
                        {h.is_matched !== null && (
                          <Badge
                            label={h.is_matched ? "Matched" : "Recorded only"}
                            variant={h.is_matched ? "matched" : "unmatched"}
                            size="sm"
                          />
                        )}
                      </div>
                    )}

                    {h.remarks && (
                      <p className="text-slate-600 bg-slate-50 p-2.5 rounded-xl border border-slate-200 mt-1">
                        {h.remarks}
                      </p>
                    )}

                    <span className="text-[11px] text-slate-400 block pt-0.5">
                      Handled by: <strong className="text-slate-600">{h.user_name}</strong>
                    </span>
                  </div>
                ))}
              </div>
            </div>

          </div>
        )}
      </Modal>

      {/* Status Transition Modal */}
      <Modal
        isOpen={isStatusModalOpen}
        onClose={() => setIsStatusModalOpen(false)}
        title="Adjust Serial Status"
        subtitle={`Update status for ${selectedSerial?.serial_number}${selectedSerial?.unit_type ? ` (${selectedSerial.unit_type.charAt(0).toUpperCase() + selectedSerial.unit_type.slice(1).toLowerCase()})` : ""}`}
        maxWidth="md"
      >
        {statusError && (
          <div className="mb-4 p-3 rounded-xl bg-rose-50 border border-rose-200 text-rose-700 text-xs flex items-center gap-2">
            <AlertCircle size={15} />
            <span>{statusError}</span>
          </div>
        )}

        <form onSubmit={handleStatusSubmit} className="space-y-4">
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
              New Status *
            </label>
            <select
              value={newStatus}
              onChange={(e) => setNewStatus(e.target.value)}
              className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
            >
              <option value="available">Available (Restores to available stock)</option>
              <option value="damaged">Damaged (Removed from available stock)</option>
              <option value="under_repair">Under Repair (Temporarily unavailable)</option>
              <option value="lost">Lost</option>
            </select>
          </div>

          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
              Reason *
            </label>
            <input
              type="text"
              required
              value={statusReason}
              onChange={(e) => setStatusReason(e.target.value)}
              placeholder="e.g. Dent observed on side panel / PCB replaced"
              className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
              Remarks
            </label>
            <textarea
              rows={2}
              value={statusRemarks}
              onChange={(e) => setStatusRemarks(e.target.value)}
              placeholder="Optional inspection notes..."
              className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
            />
          </div>

          <div className="pt-3 border-t border-slate-100 flex items-center justify-end gap-2">
            <button
              type="button"
              onClick={() => setIsStatusModalOpen(false)}
              className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl transition-colors cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={statusSubmitting}
              className="px-4 py-2 text-xs font-semibold text-white bg-[#3C3489] hover:bg-[#312B72] rounded-xl shadow-sm transition-colors cursor-pointer disabled:opacity-50"
            >
              {statusSubmitting ? "Updating..." : "Update Status"}
            </button>
          </div>
        </form>
      </Modal>

    </div>
  );
};