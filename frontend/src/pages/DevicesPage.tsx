import React, { useEffect, useState } from "react";
import { apiRequest } from "../api/client";
import { Badge } from "../components/Badge";
import type { Device } from "../types";

export const DevicesPage: React.FC = () => {
  const [devices, setDevices] = useState<Device[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<"all" | "pending" | "approved">("all");
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  // Approve / Edit Label Modal
  const [targetDevice, setTargetDevice] = useState<Device | null>(null);
  const [modalMode, setModalMode] = useState<"approve" | "edit">("approve");
  const [deviceLabel, setDeviceLabel] = useState("");
  const [submitting, setSubmitting] = useState(false);

  // Copied indicator
  const [copiedId, setCopiedId] = useState<string | null>(null);

  const fetchDevices = async () => {
    try {
      setLoading(true);
      const url = filter === "all" ? "/devices" : `/devices?status=${filter}`;
      const data = await apiRequest<Device[]>(url);
      setDevices(data);
      setError(null);
    } catch (err: any) {
      setError(err.message || "Failed to load mobile devices");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchDevices();
  }, [filter]);

  const handleCopyUid = (uid: string) => {
    navigator.clipboard.writeText(uid);
    setCopiedId(uid);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const openApproveModal = (d: Device) => {
    setTargetDevice(d);
    setModalMode("approve");
    setDeviceLabel(d.label || "");
    setIsModalOpen(true);
  };

  const openEditLabelModal = (d: Device) => {
    setTargetDevice(d);
    setModalMode("edit");
    setDeviceLabel(d.label || "");
    setIsModalOpen(true);
  };

  const [isModalOpen, setIsModalOpen] = useState(false);

  const handleModalSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!targetDevice) return;
    setSubmitting(true);

    try {
      if (modalMode === "approve") {
        await apiRequest(`/devices/${targetDevice.id}/approve`, {
          method: "PATCH",
          body: JSON.stringify({ label: deviceLabel.trim() || undefined }),
        });
        setSuccessMsg(`Device approved successfully.`);
      } else {
        // If editing label on an already approved device, we can re-approve with new label
        await apiRequest(`/devices/${targetDevice.id}/approve`, {
          method: "PATCH",
          body: JSON.stringify({ label: deviceLabel.trim() || undefined }),
        });
        setSuccessMsg(`Device label updated.`);
      }

      setIsModalOpen(false);
      fetchDevices();
      setTimeout(() => setSuccessMsg(null), 4000);
    } catch (err: any) {
      alert(err.message || "Action failed.");
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeactivate = async (d: Device) => {
    const confirmMsg = `Revoke access for device "${d.label || d.device_uid}"? This phone will be blocked from scanning until re-approved.`;
    if (!window.confirm(confirmMsg)) return;

    try {
      await apiRequest(`/devices/${d.id}/deactivate`, { method: "PATCH" });
      setSuccessMsg(`Device access revoked.`);
      fetchDevices();
      setTimeout(() => setSuccessMsg(null), 4000);
    } catch (err: any) {
      alert(err.message || "Failed to deactivate device.");
    }
  };

  const pendingCount = devices.filter((d) => !d.is_active).length;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 bg-white border border-slate-200/80 rounded-2xl p-6 shadow-sm">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-xl font-bold text-slate-900 tracking-tight">Mobile Scanner Devices</h1>
            <span className="text-xs px-2.5 py-0.5 rounded-full bg-indigo-50 text-indigo-700 font-semibold border border-indigo-100">
              Hardware Security
            </span>
          </div>
          <p className="text-xs text-slate-500 mt-1">
            Authorize Android warehouse phones to scan inward stock and dispatch serials.
          </p>
        </div>

        <button
          onClick={fetchDevices}
          className="inline-flex items-center justify-center gap-2 px-3.5 py-2 rounded-xl bg-slate-50 hover:bg-slate-100 border border-slate-200 text-slate-700 text-xs font-semibold transition-colors cursor-pointer self-start sm:self-auto"
        >
          <svg className="w-3.5 h-3.5 text-slate-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          Refresh Devices
        </button>
      </div>

      {/* Pending Approval Alert Banner */}
      {pendingCount > 0 && filter !== "approved" && (
        <div className="p-4 bg-amber-50/90 border border-amber-200 rounded-2xl flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 text-xs text-amber-900 shadow-xs">
          <div className="flex items-center gap-3">
            <span className="w-8 h-8 rounded-xl bg-amber-200/80 text-amber-900 flex items-center justify-center shrink-0 font-bold">
              !
            </span>
            <div>
              <div className="font-bold text-slate-900">
                {pendingCount} Scanner Device{pendingCount > 1 ? "s" : ""} Awaiting Approval
              </div>
              <div className="text-amber-700 text-[11px] mt-0.5">
                Staff have installed the mobile scanning app and need authorization before they can record inventory.
              </div>
            </div>
          </div>
          <button
            onClick={() => setFilter("pending")}
            className="px-3 py-1.5 rounded-lg bg-amber-600 text-white font-semibold text-[11px] hover:bg-amber-700 transition-colors shrink-0 cursor-pointer"
          >
            Review Pending
          </button>
        </div>
      )}

      {/* Error Notification */}
      {error && (
        <div className="p-3.5 bg-rose-50 border border-rose-200 text-rose-800 text-xs font-medium rounded-xl flex items-center gap-2">
          <svg className="w-4 h-4 text-rose-600 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          {error}
        </div>
      )}

      {/* Success Notification */}
      {successMsg && (
        <div className="p-3.5 bg-emerald-50 border border-emerald-200 text-emerald-800 text-xs font-medium rounded-xl flex items-center gap-2">
          <svg className="w-4 h-4 text-emerald-600 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
          </svg>
          {successMsg}
        </div>
      )}

      {/* Filter Tabs */}
      <div className="flex items-center gap-2 border-b border-slate-200 pb-2">
        <button
          onClick={() => setFilter("all")}
          className={`px-3.5 py-1.5 rounded-xl text-xs font-semibold transition-all cursor-pointer ${
            filter === "all"
              ? "bg-slate-900 text-white shadow-xs"
              : "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
          }`}
        >
          All Devices ({devices.length})
        </button>
        <button
          onClick={() => setFilter("pending")}
          className={`inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl text-xs font-semibold transition-all cursor-pointer ${
            filter === "pending"
              ? "bg-amber-600 text-white shadow-xs"
              : "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
          }`}
        >
          Pending Approval
          {pendingCount > 0 && (
            <span className={`px-1.5 py-0.2 rounded-full text-[10px] font-bold ${
              filter === "pending" ? "bg-white text-amber-700" : "bg-amber-100 text-amber-800"
            }`}>
              {pendingCount}
            </span>
          )}
        </button>
        <button
          onClick={() => setFilter("approved")}
          className={`px-3.5 py-1.5 rounded-xl text-xs font-semibold transition-all cursor-pointer ${
            filter === "approved"
              ? "bg-emerald-700 text-white shadow-xs"
              : "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
          }`}
        >
          Approved & Active
        </button>
      </div>

      {/* Device Cards / Table */}
      <div className="bg-white border border-slate-200 rounded-2xl shadow-xs overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-xs text-slate-400">Loading device registry...</div>
        ) : devices.length === 0 ? (
          <div className="p-12 text-center text-xs text-slate-400">
            No devices found in this view.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse text-xs">
              <thead>
                <tr className="bg-slate-50/75 border-b border-slate-200 text-slate-500 font-semibold uppercase tracking-wider">
                  <th className="py-3 px-4">Device Label / Description</th>
                  <th className="py-3 px-4">Hardware Identifier (UID)</th>
                  <th className="py-3 px-4">Status</th>
                  <th className="py-3 px-4">Registered</th>
                  <th className="py-3 px-4">Approved At</th>
                  <th className="py-3 px-4 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                {devices.map((d) => (
                  <tr key={d.id} className="hover:bg-slate-50/80 transition-colors">
                    <td className="py-3.5 px-4">
                      <div className="flex items-center gap-2">
                        <div className="w-7 h-7 rounded-lg bg-slate-100 border border-slate-200 flex items-center justify-center text-slate-500 shrink-0">
                          <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z" />
                          </svg>
                        </div>
                        <div>
                          <div className="font-semibold text-slate-900">
                            {d.label || <span className="text-slate-400 italic font-normal">Unlabeled Device</span>}
                          </div>
                          <button
                            onClick={() => openEditLabelModal(d)}
                            className="text-[10px] text-indigo-700 hover:underline cursor-pointer"
                          >
                            Rename Label
                          </button>
                        </div>
                      </div>
                    </td>
                    <td className="py-3.5 px-4">
                      <div className="flex items-center gap-2">
                        <code className="text-[11px] font-mono bg-slate-100 px-2 py-0.5 rounded text-slate-700 border border-slate-200">
                          {d.device_uid.slice(0, 16)}...
                        </code>
                        <button
                          onClick={() => handleCopyUid(d.device_uid)}
                          title="Copy Full UID"
                          className="text-slate-400 hover:text-slate-600 cursor-pointer"
                        >
                          {copiedId === d.device_uid ? (
                            <span className="text-[10px] text-emerald-600 font-bold">Copied!</span>
                          ) : (
                            <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                            </svg>
                          )}
                        </button>
                      </div>
                    </td>
                    <td className="py-3.5 px-4">
                      {d.is_active ? (
                        <Badge variant="green">Approved</Badge>
                      ) : (
                        <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-amber-50 text-amber-800 border border-amber-200 text-[10px] font-semibold">
                          <span className="w-1.5 h-1.5 rounded-full bg-amber-500 animate-pulse"></span>
                          Pending Approval
                        </span>
                      )}
                    </td>
                    <td className="py-3.5 px-4 text-slate-500 text-[11px]">
                      {new Date(d.created_at).toLocaleDateString("en-IN", {
                        day: "numeric",
                        month: "short",
                        year: "numeric",
                      })}
                    </td>
                    <td className="py-3.5 px-4 text-slate-500 text-[11px]">
                      {d.approved_at ? (
                        new Date(d.approved_at).toLocaleDateString("en-IN", {
                          day: "numeric",
                          month: "short",
                          year: "numeric",
                        })
                      ) : (
                        <span className="text-slate-300">-</span>
                      )}
                    </td>
                    <td className="py-3.5 px-4 text-right">
                      <div className="inline-flex items-center gap-2">
                        {!d.is_active ? (
                          <button
                            onClick={() => openApproveModal(d)}
                            className="px-3 py-1 text-[11px] font-semibold text-white bg-indigo-900 hover:bg-indigo-800 rounded-lg transition-colors shadow-xs cursor-pointer"
                          >
                            Approve Device
                          </button>
                        ) : (
                          <button
                            onClick={() => handleDeactivate(d)}
                            className="px-2.5 py-1 text-[11px] font-semibold text-rose-700 hover:text-rose-800 bg-rose-50/60 hover:bg-rose-50 border border-rose-200 rounded-lg transition-colors cursor-pointer"
                          >
                            Revoke Access
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Modal for Approve / Edit Label */}
      {isModalOpen && targetDevice && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40 backdrop-blur-xs animate-in fade-in duration-150">
          <div className="bg-white rounded-2xl border border-slate-200 shadow-xl max-w-md w-full overflow-hidden">
            <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between">
              <h2 className="text-sm font-bold text-slate-900">
                {modalMode === "approve" ? "Authorize Mobile Device" : "Update Device Label"}
              </h2>
              <button
                onClick={() => setIsModalOpen(false)}
                className="text-slate-400 hover:text-slate-600 text-lg leading-none p-1 cursor-pointer"
              >
                &times;
              </button>
            </div>

            <form onSubmit={handleModalSubmit} className="p-6 space-y-4 text-xs">
              <div>
                <label className="block text-slate-700 font-semibold mb-1">
                  Device Hardware Identifier (UID)
                </label>
                <div className="p-2.5 bg-slate-100 border border-slate-200 rounded-xl font-mono text-[11px] text-slate-600 break-all select-all">
                  {targetDevice.device_uid}
                </div>
              </div>

              <div>
                <label className="block text-slate-700 font-semibold mb-1">
                  Device Label / Name
                </label>
                <input
                  type="text"
                  placeholder="e.g. Inward Bay Phone 1 (Rahul)"
                  value={deviceLabel}
                  onChange={(e) => setDeviceLabel(e.target.value)}
                  className="w-full px-3 py-2 rounded-xl border border-slate-200 bg-slate-50 text-slate-900 text-xs focus:outline-none focus:ring-1 focus:ring-indigo-800 focus:bg-white"
                />
                <p className="text-[10px] text-slate-400 mt-1">
                  Give this phone a recognizable name to easily track which device performed scans.
                </p>
              </div>

              <div className="pt-3 border-t border-slate-100 flex items-center justify-end gap-2">
                <button
                  type="button"
                  onClick={() => setIsModalOpen(false)}
                  className="px-4 py-2 rounded-xl border border-slate-200 text-slate-600 hover:bg-slate-50 font-semibold cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submitting}
                  className="px-4 py-2 rounded-xl bg-indigo-900 text-white font-semibold hover:bg-indigo-800 transition-colors disabled:opacity-50 cursor-pointer"
                >
                  {submitting
                    ? "Saving..."
                    : modalMode === "approve"
                    ? "Approve Device"
                    : "Update Label"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};