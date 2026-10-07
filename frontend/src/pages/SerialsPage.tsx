import React, { useEffect, useState } from "react";
import { apiRequest } from "../api/client";
import { useWebSocket } from "../api/useWebSocket";
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
  ChevronRight,
  Layers
} from "lucide-react";

export const SerialsPage: React.FC = () => {
  const [serials, setSerials] = useState<SerialListItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState("");
  const [flowFilter, setFlowFilter] = useState<"all" | "inward" | "outward" | "damaged">("all");

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

  const fetchSerials = async () => {
    try {
      const res = await apiRequest<SerialListResponse>("/serials?limit=500");
      setSerials(res.items);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchSerials();
  }, []);

  useWebSocket((event) => {
    if (
      event === "stock_updated" ||
      event === "product_created" ||
      event === "product_updated" ||
      event === "product_deleted"
    ) {
      fetchSerials();
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

  // Filtered Serials
  const filteredSerials = serials
    .filter((s) => {
      if (flowFilter === "inward") return s.flow_type === "inward";
      if (flowFilter === "outward") return s.flow_type === "outward";
      if (flowFilter === "damaged") return ["damaged", "under_repair", "lost"].includes(s.status);
      return true;
    })
    .filter((s) => {
      if (!searchQuery.trim()) return true;
      const q = searchQuery.toLowerCase().trim();
      return (
        s.serial_number.toLowerCase().includes(q) ||
        (s.unit_type && s.unit_type.toLowerCase().includes(q)) ||
        s.model.toLowerCase().includes(q) ||
        s.brand.toLowerCase().includes(q) ||
        (s.category_name && s.category_name.toLowerCase().includes(q)) ||
        s.product_name.toLowerCase().includes(q) ||
        (s.shop_name && s.shop_name.toLowerCase().includes(q)) ||
        (s.shop_city && s.shop_city.toLowerCase().includes(q)) ||
        (s.reference && s.reference.toLowerCase().includes(q))
      );
    });

  const inwardCount = serials.filter((s) => s.flow_type === "inward").length;
  const outwardCount = serials.filter((s) => s.flow_type === "outward").length;
  const attentionCount = serials.filter((s) => ["damaged", "under_repair", "lost"].includes(s.status)).length;

  return (
    <div className="space-y-6 animate-fade-in pb-12">
      
      {/* Title & Quick Stats */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            Serial Number Registry
          </h1>
          <p className="text-xs text-slate-500 font-medium mt-0.5">
            Complete inventory log of inward and outward appliance serials • Live godown trace
          </p>
        </div>

        {/* Quick summary badges */}
        <div className="flex items-center gap-3">
          <div className="px-3 py-1.5 rounded-xl bg-white border border-slate-200 text-xs shadow-sm flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-emerald-500" />
            <span className="text-slate-500 font-medium">In Stock:</span>
            <span className="font-bold text-slate-900">{inwardCount}</span>
          </div>
          <div className="px-3 py-1.5 rounded-xl bg-white border border-slate-200 text-xs shadow-sm flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-[#3C3489]" />
            <span className="text-slate-500 font-medium">Dispatched:</span>
            <span className="font-bold text-slate-900">{outwardCount}</span>
          </div>
        </div>
      </div>

      {/* Filter Tabs & Search Bar */}
      <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3">
        {/* Flow Tabs */}
        <div className="flex items-center gap-1 p-1 bg-slate-100 rounded-xl w-fit text-xs font-medium">
          <button
            onClick={() => setFlowFilter("all")}
            className={`px-3 py-1.5 rounded-lg transition-all cursor-pointer ${
              flowFilter === "all"
                ? "bg-white text-slate-900 font-semibold shadow-sm"
                : "text-slate-600 hover:text-slate-900"
            }`}
          >
            All Serials ({serials.length})
          </button>
          <button
            onClick={() => setFlowFilter("inward")}
            className={`px-3 py-1.5 rounded-lg transition-all cursor-pointer flex items-center gap-1.5 ${
              flowFilter === "inward"
                ? "bg-white text-emerald-700 font-semibold shadow-sm"
                : "text-slate-600 hover:text-slate-900"
            }`}
          >
            <ArrowDownLeft size={13} className="text-emerald-600" />
            <span>Inward / In Stock ({inwardCount})</span>
          </button>
          <button
            onClick={() => setFlowFilter("outward")}
            className={`px-3 py-1.5 rounded-lg transition-all cursor-pointer flex items-center gap-1.5 ${
              flowFilter === "outward"
                ? "bg-white text-[#3C3489] font-semibold shadow-sm"
                : "text-slate-600 hover:text-slate-900"
            }`}
          >
            <ArrowUpRight size={13} className="text-[#3C3489]" />
            <span>Outward / Dispatched ({outwardCount})</span>
          </button>
          {attentionCount > 0 && (
            <button
              onClick={() => setFlowFilter("damaged")}
              className={`px-3 py-1.5 rounded-lg transition-all cursor-pointer flex items-center gap-1.5 ${
                flowFilter === "damaged"
                  ? "bg-white text-rose-700 font-semibold shadow-sm"
                  : "text-slate-600 hover:text-slate-900"
              }`}
            >
              <AlertCircle size={13} className="text-rose-600" />
              <span>Attention ({attentionCount})</span>
            </button>
          )}
        </div>

        {/* Live Search Input */}
        <div className="relative max-w-sm w-full sm:w-80">
          <Search size={15} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search serial, model, brand, shop, ref..."
            className="w-full pl-9 pr-4 py-2 text-xs rounded-xl border border-slate-200 bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] text-slate-800 placeholder-slate-400 shadow-sm"
          />
        </div>
      </div>

      {/* Serials Table */}
      <div className="bg-white border border-slate-200 rounded-2xl shadow-sm overflow-hidden">
        {loading ? (
          <div className="py-20 text-center text-xs text-slate-400">
            <div className="w-6 h-6 border-2 border-[#3C3489] border-t-transparent rounded-full animate-spin mx-auto mb-2" />
            Loading serial records...
          </div>
        ) : filteredSerials.length === 0 ? (
          <div className="py-20 text-center text-xs text-slate-400">
            No serials match the current filter or search criteria.
          </div>
        ) : (
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
                      {item.reference ? item.reference : "—"}
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
                    ? `${selectedSerial.last_shop_name} (${selectedSerial.last_shop_city})` 
                    : "In Godown"}
                </span>
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
                        <span>{h.shop_name} ({h.shop_city})</span>
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