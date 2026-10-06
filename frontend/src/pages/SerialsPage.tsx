import React, { useState } from "react";
import { apiRequest } from "../api/client";
import type { SerialDetail } from "../types";
import { Badge } from "../components/Badge";
import { Modal } from "../components/Modal";
import { 
  Barcode, 
  Building2, 
  AlertCircle, 
  Clock,
  Wrench,
  } from "lucide-react";

export const SerialsPage: React.FC = () => {
  const [searchQuery, setSearchQuery] = useState("");
  const [loading, setLoading] = useState(false);
  const [serialDetail, setSerialDetail] = useState<SerialDetail | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Status Change Modal
  const [isStatusModalOpen, setIsStatusModalOpen] = useState(false);
  const [newStatus, setNewStatus] = useState<string>("damaged");
  const [statusReason, setStatusReason] = useState("");
  const [statusRemarks, setStatusRemarks] = useState("");
  const [statusSubmitting, setStatusSubmitting] = useState(false);
  const [statusError, setStatusError] = useState<string | null>(null);

  const handleLookup = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    const clean = searchQuery.trim();
    if (!clean) return;

    setLoading(true);
    setError(null);
    setSerialDetail(null);

    try {
      const res = await apiRequest<SerialDetail>(`/serials/lookup?serial_number=${encodeURIComponent(clean)}`);
      setSerialDetail(res);
    } catch (err: any) {
      setError(err.message || "Serial number not found.");
    } finally {
      setLoading(false);
    }
  };

  const handleStatusSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!serialDetail?.serial_number_id) return;
    if (!statusReason.trim()) {
      setStatusError("Reason for status change is mandatory.");
      return;
    }

    setStatusSubmitting(true);
    setStatusError(null);

    try {
      const updated = await apiRequest<SerialDetail>(`/serials/${serialDetail.serial_number_id}/status`, {
        method: "PATCH",
        body: JSON.stringify({
          new_status: newStatus,
          reason: statusReason.trim(),
          remarks: statusRemarks.trim() || null,
        }),
      });
      setSerialDetail(updated);
      setIsStatusModalOpen(false);
      setStatusReason("");
      setStatusRemarks("");
    } catch (err: any) {
      setStatusError(err.message || "Failed to update serial status.");
    } finally {
      setStatusSubmitting(false);
    }
  };

  return (
    <div className="space-y-6 animate-fade-in pb-12">
      
      {/* Title */}
      <div>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900">
          Serial Number Lookup
        </h1>
        <p className="text-xs text-slate-500 font-medium mt-0.5">
          Complete lifecycle trace of any appliance unit • From inward to dispatch and returns
        </p>
      </div>

      {/* Search Input */}
      <form onSubmit={handleLookup} className="relative max-w-xl">
        <Barcode size={18} className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400" />
        <input
          type="text"
          autoFocus
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder="Enter or scan serial number (e.g. SMTV004512)..."
          className="w-full pl-11 pr-24 py-3 text-sm rounded-2xl border border-slate-200 bg-white shadow-sm focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] text-slate-800 placeholder-slate-400"
        />
        <button
          type="submit"
          disabled={loading || !searchQuery.trim()}
          className="absolute right-2 top-1/2 -translate-y-1/2 px-4 py-1.5 rounded-xl bg-[#3C3489] text-white text-xs font-semibold hover:bg-[#312B72] disabled:opacity-50 transition-colors cursor-pointer"
        >
          {loading ? "Searching..." : "Lookup"}
        </button>
      </form>

      {error && (
        <div className="max-w-xl p-4 bg-white border border-rose-200 rounded-2xl shadow-sm flex items-center gap-3 text-rose-700 text-xs">
          <AlertCircle size={16} className="text-rose-500 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {/* Serial Detail Card */}
      {serialDetail && (
        <div className="bg-white border border-slate-200 rounded-2xl p-6 shadow-sm space-y-6 animate-fade-in max-w-3xl">
          
          {/* Header Info */}
          <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-4 pb-5 border-b border-slate-100">
            <div>
              <div className="flex flex-wrap items-center gap-2 mb-1.5">
                <span className="font-mono font-bold text-xl text-slate-900 tracking-tight">
                  {serialDetail.serial_number}
                </span>
                <Badge label={serialDetail.status_label} />
                <Badge
                  label={serialDetail.is_tracked ? "Tracked Unit" : "Recorded only (Pre-go-live)"}
                  variant={serialDetail.is_tracked ? "matched" : "unmatched"}
                />
              </div>
              <h2 className="text-base font-semibold text-slate-800">
                {serialDetail.product_name}
              </h2>
              <p className="text-xs text-slate-400 mt-0.5">
                {serialDetail.brand} • {serialDetail.model}
              </p>
            </div>

            {serialDetail.is_tracked && (
              <button
                onClick={() => setIsStatusModalOpen(true)}
                className="px-3.5 py-2 rounded-xl text-xs font-semibold bg-slate-100 hover:bg-slate-200 text-slate-700 transition-colors flex items-center gap-1.5 self-start cursor-pointer"
              >
                <Wrench size={14} />
                <span>Adjust Status</span>
              </button>
            )}
          </div>

          {/* Key Facts Strip */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 p-4 rounded-xl bg-slate-50 border border-slate-100 text-xs">
            <div>
              <span className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider block">
                Tracking Type
              </span>
              <span className="font-semibold text-slate-700 mt-0.5 block">
                {serialDetail.is_tracked ? "Serial Scanned In" : "Unmatched Dispatch"}
              </span>
            </div>

            <div>
              <span className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider block">
                Current Status
              </span>
              <span className="font-semibold text-slate-700 mt-0.5 block capitalize">
                {serialDetail.status || "Unknown"}
              </span>
            </div>

            <div>
              <span className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider block">
                Destination Shop
              </span>
              <span className="font-semibold text-slate-700 mt-0.5 block">
                {serialDetail.last_shop_name ? `${serialDetail.last_shop_name} (${serialDetail.last_shop_city})` : "None (In Godown)"}
              </span>
            </div>
          </div>

          {/* Complete Vertical Timeline */}
          <div className="space-y-4">
            <h3 className="text-xs font-bold uppercase tracking-wider text-slate-500 flex items-center gap-2">
              <Clock size={15} />
              Chronological Audit History
            </h3>

            <div className="relative pl-6 space-y-5 before:absolute before:left-2 before:top-2 before:bottom-2 before:w-0.5 before:bg-slate-200">
              {serialDetail.history.map((h) => (
                <div key={h.id} className="relative text-xs space-y-1">
                  <div className="absolute -left-6 top-1 w-2.5 h-2.5 rounded-full ring-4 bg-[#3C3489] ring-[#EEF2FF]" />
                  
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <span className="font-semibold text-slate-800 capitalize text-sm">
                      {h.action.replace(/_/g, " ")}
                    </span>
                    <span className="text-[11px] text-slate-400">
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
                    <div className="flex items-center gap-1.5 text-slate-600 font-medium">
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
                    <p className="text-slate-500 bg-slate-50 p-2 rounded-lg border border-slate-100">
                      {h.remarks}
                    </p>
                  )}

                  <span className="text-[11px] text-slate-400 block">
                    Recorded by: {h.user_name}
                  </span>
                </div>
              ))}
            </div>
          </div>

        </div>
      )}

      {/* Status Transition Modal */}
      <Modal
        isOpen={isStatusModalOpen}
        onClose={() => setIsStatusModalOpen(false)}
        title="Adjust Serial Status"
        subtitle={`Update status for ${serialDetail?.serial_number}`}
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