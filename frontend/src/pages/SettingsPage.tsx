import React, { useState, useEffect, useCallback } from "react";
import { 
  Settings as SettingsIcon, 
  UploadCloud, 
  CheckCircle2, 
  ShieldCheck, 
  Info,
  ToggleLeft,
  ToggleRight,
  RefreshCw,
  AlertCircle,
  Server,
  Power,
  Wifi,
  Clock
} from "lucide-react";
import { useAuth } from "../context/AuthContext";
import { apiRequest } from "../api/client";
import { apiCache } from "../api/cache";

interface TallyStatus {
  is_connected: boolean;
  host: string;
  port: number;
  active_company?: string | null;
  is_enabled: boolean;
  auto_sync: boolean;
  sync_interval_minutes?: number;
  enable_tally_1: boolean;
  enable_tally_2: boolean;
  tally_1_name: string;
  tally_2_name: string;
  tally_1_connected: boolean;
  tally_2_connected: boolean;
  available_companies: string[];
  last_sync_at?: string | null;
  last_sync_status?: string | null;
  is_syncing: boolean;
}

export const SettingsPage: React.FC = () => {
  const { user } = useAuth();
  const [activateImport, setActivateImport] = useState<boolean>(false);
  const [showEmptyCategories, setShowEmptyCategories] = useState<boolean>(false);
  const [allowBillModifications, setAllowBillModifications] = useState<boolean>(false);
  const [saveToast, setSaveToast] = useState<string | null>(null);
  const [pullError, setPullError] = useState<string | null>(null);
  const [pullingMasters, setPullingMasters] = useState<boolean>(false);
  const [pullingBills, setPullingBills] = useState<boolean>(false);

  // Tally reading state
  const [tallyStatus, setTallyStatus] = useState<TallyStatus | null>(() => apiCache.get<TallyStatus>("/tally/status") || null);
  const [loadingTallyStatus, setLoadingTallyStatus] = useState<boolean>(() => !apiCache.hasValid("/tally/status"));
  const [togglingTally, setTogglingTally] = useState<boolean>(false);

  const fetchTallyStatus = useCallback(async (force: boolean | unknown = false) => {
    try {
      if (!tallyStatus) {
        setLoadingTallyStatus(true);
      }
      const data = await apiRequest<TallyStatus>("/tally/status", { forceRefresh: force === true });
      setTallyStatus(data);
    } catch {
      // ignore
    } finally {
      setLoadingTallyStatus(false);
    }
  }, [tallyStatus]);

  useEffect(() => {
    const saved = localStorage.getItem("feature_activate_serial_import");
    setActivateImport(saved === "true");

    const savedEmptyCats = localStorage.getItem("feature_show_empty_categories");
    setShowEmptyCategories(savedEmptyCats === "true");

    const savedBillMods = localStorage.getItem("feature_allow_bill_delete_update");
    setAllowBillModifications(savedBillMods === "true");

    fetchTallyStatus();
  }, [fetchTallyStatus]);

  const handleToggleAutoSync = async () => {
    if (!tallyStatus || togglingTally) return;
    const nextVal = !tallyStatus.auto_sync;
    setTogglingTally(true);
    try {
      const updated = await apiRequest<TallyStatus>("/tally/toggle-reading", {
        method: "POST",
        body: JSON.stringify({ auto_sync: nextVal }),
      });
      setTallyStatus(updated);
      setSaveToast(
        nextVal
          ? "Tally Background Reading Activated! WMS will automatically poll enabled Tally systems."
          : "Tally Reading Stopped! All background polling and reads from Tally are completely paused."
      );
      setTimeout(() => setSaveToast(null), 4000);
    } catch (err: any) {
      setPullError(err.message || "Failed to toggle Tally reading.");
    } finally {
      setTogglingTally(false);
    }
  };

  const handleChangeSyncInterval = async (minutes: number) => {
    if (!tallyStatus || togglingTally) return;
    setTogglingTally(true);
    try {
      const updated = await apiRequest<TallyStatus>("/tally/toggle-reading", {
        method: "POST",
        body: JSON.stringify({ sync_interval_minutes: minutes }),
      });
      setTallyStatus(updated);
      const label = minutes >= 60 ? `${minutes / 60} Hour${minutes > 60 ? "s" : ""}` : `${minutes} Minutes`;
      setSaveToast(`Auto-Sync interval set to ${label}! Background queries will only run once every ${label}.`);
      setTimeout(() => setSaveToast(null), 4000);
    } catch (err: any) {
      setPullError(err.message || "Failed to update sync interval.");
    } finally {
      setTogglingTally(false);
    }
  };

  const handleToggleTally1 = async () => {
    if (!tallyStatus || togglingTally) return;
    const nextVal = !tallyStatus.enable_tally_1;
    setTogglingTally(true);
    try {
      const updated = await apiRequest<TallyStatus>("/tally/toggle-reading", {
        method: "POST",
        body: JSON.stringify({ enable_tally_1: nextVal }),
      });
      setTallyStatus(updated);
      setSaveToast(
        nextVal
          ? `Tally 1 Reading Activated! (${tallyStatus?.tally_1_name || "Tally 1"})`
          : "Tally 1 Reading Stopped! GA STOCK will not read from Tally 1."
      );
      setTimeout(() => setSaveToast(null), 4000);
    } catch (err: any) {
      setPullError(err.message || "Failed to toggle Tally 1 reading.");
    } finally {
      setTogglingTally(false);
    }
  };

  const handleToggleTally2 = async () => {
    if (!tallyStatus || togglingTally) return;
    const nextVal = !tallyStatus.enable_tally_2;
    setTogglingTally(true);
    try {
      const updated = await apiRequest<TallyStatus>("/tally/toggle-reading", {
        method: "POST",
        body: JSON.stringify({ enable_tally_2: nextVal }),
      });
      setTallyStatus(updated);
      setSaveToast(
        nextVal
          ? `Tally 2 Reading Activated! (${tallyStatus?.tally_2_name || "Tally 2"})`
          : "Tally 2 Reading Stopped! GA STOCK will not read from Tally 2."
      );
      setTimeout(() => setSaveToast(null), 4000);
    } catch (err: any) {
      setPullError(err.message || "Failed to toggle Tally 2 reading.");
    } finally {
      setTogglingTally(false);
    }
  };

  const handleToggleImport = () => {
    const nextVal = !activateImport;
    setActivateImport(nextVal);
    localStorage.setItem("feature_activate_serial_import", String(nextVal));
    setSaveToast(
      nextVal 
        ? "Serial Import Option Activated! You can now import serials directly on Stock cards."
        : "Serial Import Option Deactivated. Import buttons are now hidden on Stock cards."
    );
    setTimeout(() => {
      setSaveToast(null);
    }, 4000);
  };

  const handleToggleEmptyCategories = () => {
    const nextVal = !showEmptyCategories;
    setShowEmptyCategories(nextVal);
    localStorage.setItem("feature_show_empty_categories", String(nextVal));
    setSaveToast(
      nextVal 
        ? "Show Empty Categories Activated! All Tally categories (even with 0 models) will now be shown on Stock page."
        : "Empty Categories Hidden. Only categories with at least 1 model are shown on the Stock page."
    );
    setTimeout(() => {
      setSaveToast(null);
    }, 4000);
  };

  const handleToggleBillModifications = () => {
    const nextVal = !allowBillModifications;
    setAllowBillModifications(nextVal);
    localStorage.setItem("feature_allow_bill_delete_update", String(nextVal));
    setSaveToast(
      nextVal
        ? "Bill Delete & Update Options Activated! You can now edit, cancel, delete, or update bills and serials on the Bills page."
        : "Bill Delete & Update Options Hidden. Destructive actions are now hidden on the Bills page to prevent accidental alterations."
    );
    setTimeout(() => {
      setSaveToast(null);
    }, 4000);
  };

  const handlePullMasters = async () => {
    setPullingMasters(true);
    setPullError(null);
    try {
      const res = await apiRequest<{ status: string; message: string }>("/tally/sync-masters", {
        method: "POST",
      });
      setSaveToast(res.message || "Pulled categories, items, and shops from Tally.");
      setTimeout(() => setSaveToast(null), 6000);
    } catch (err) {
      setPullError(err instanceof Error ? err.message : "Failed to pull master data from Tally.");
    } finally {
      setPullingMasters(false);
    }
  };

  const handlePullFullBills = async () => {
    setPullingBills(true);
    setPullError(null);
    try {
      const res = await apiRequest<{ status: string; message: string }>("/tally/sync?force_full=false", {
        method: "POST",
      });
      setSaveToast(res.message || "Tally bill sync completed.");
      setTimeout(() => setSaveToast(null), 6000);
    } catch (err) {
      setPullError(err instanceof Error ? err.message : "Failed to pull bills from Tally.");
    } finally {
      setPullingBills(false);
    }
  };

  return (
    <div className="w-full max-w-[1720px] mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 pb-6 border-b border-slate-200">
        <div>
          <div className="flex items-center gap-2">
            <span className="text-xs font-semibold px-2.5 py-0.5 rounded-full bg-indigo-50 text-indigo-700 border border-indigo-200 uppercase tracking-wider">
              Administration
            </span>
          </div>
          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-slate-900 mt-1 flex items-center gap-2.5">
            <SettingsIcon className="text-indigo-600" size={28} />
            System Settings
          </h1>
          <p className="text-sm text-slate-500 mt-1">
            Configure warehouse operations, serial recording workflows, and system behavior.
          </p>
        </div>
      </div>

      {/* Toast Notification */}
      {saveToast && (
        <div className="p-4 rounded-xl bg-emerald-50 border border-emerald-200 text-emerald-800 text-sm font-medium flex items-center gap-3 shadow-sm animate-in fade-in slide-in-from-top-2">
          <CheckCircle2 size={18} className="text-emerald-600 shrink-0" />
          <span>{saveToast}</span>
        </div>
      )}

      {pullError && (
        <div className="p-4 rounded-xl bg-rose-50 border border-rose-200 text-rose-800 text-sm font-medium flex items-center gap-3 shadow-sm">
          <AlertCircle size={18} className="text-rose-600 shrink-0" />
          <span>{pullError}</span>
        </div>
      )}

      {/* Main Settings Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* Left 2 Cols: Main Feature Toggles */}
        <div className="lg:col-span-2 space-y-6">

          {/* Card: TallyPrime Connection & Reading Controls */}
          <div className="bg-white rounded-2xl border border-slate-200 shadow-sm overflow-hidden">
            <div className="p-5 bg-gradient-to-r from-[#3C3489] to-indigo-900 text-white flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-xl bg-white/10 text-indigo-200">
                  <Server size={20} />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">TallyPrime Reading &amp; Sync Controls</h3>
                  <p className="text-xs text-indigo-200">
                    Control live background reading and selective instance synchronization
                  </p>
                </div>
              </div>
              <div>
                {!tallyStatus?.auto_sync ? (
                  <span className="text-[11px] font-semibold px-2.5 py-1 rounded-full bg-rose-500/20 text-rose-100 border border-rose-300/30 flex items-center gap-1.5">
                    <Power size={12} /> Reading Stopped
                  </span>
                ) : !tallyStatus?.enable_tally_1 && !tallyStatus?.enable_tally_2 ? (
                  <span className="text-[11px] font-semibold px-2.5 py-1 rounded-full bg-amber-500/20 text-amber-100 border border-amber-300/30">
                    All Instances Disabled
                  </span>
                ) : (
                  <span className="text-[11px] font-semibold px-2.5 py-1 rounded-full bg-emerald-400/20 text-emerald-100 border border-emerald-300/30 flex items-center gap-1.5">
                    <Wifi size={12} /> Background Reading Active
                  </span>
                )}
              </div>
            </div>

            <div className="p-6 space-y-6">
              
              {/* Master Reading Switch */}
              <div className="p-4 rounded-xl bg-slate-50 border border-slate-200/90 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div className="space-y-1">
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-sm text-slate-900">
                      Tally Live Auto-Sync / Background Reading
                    </span>
                    {tallyStatus?.auto_sync ? (
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-200">
                        ENABLED
                      </span>
                    ) : (
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-rose-100 text-rose-800 border border-rose-200">
                        STOPPED
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-slate-500 leading-relaxed max-w-xl">
                    Master killswitch for all Tally reading operations. When turned <strong>OFF</strong>, all background
                    polls, live stock balance queries, and sales bill readers are completely halted across all Tally machines.
                  </p>
                </div>

                <button
                  type="button"
                  onClick={handleToggleAutoSync}
                  disabled={togglingTally || loadingTallyStatus}
                  className="cursor-pointer shrink-0 transition-transform active:scale-95 focus:outline-none disabled:opacity-50"
                  title={tallyStatus?.auto_sync ? "Click to stop all Tally reading" : "Click to activate Tally reading"}
                >
                  {tallyStatus?.auto_sync ? (
                    <ToggleRight size={40} className="text-emerald-600" />
                  ) : (
                    <ToggleLeft size={40} className="text-slate-300 hover:text-slate-400" />
                  )}
                </button>
              </div>

              {/* Auto-Sync Gap / Interval Selector */}
              <div className="p-4 rounded-xl bg-slate-50 border border-slate-200/90 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div className="space-y-1">
                  <div className="flex items-center gap-2">
                    <Clock size={16} className="text-indigo-600" />
                    <span className="font-bold text-xs text-slate-900">
                      Live Stock Auto-Sync Gap
                    </span>
                    <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-indigo-50 text-indigo-700 border border-indigo-200">
                      {(tallyStatus?.sync_interval_minutes || 60) >= 60 
                        ? `${(tallyStatus?.sync_interval_minutes || 60) / 60} Hour${(tallyStatus?.sync_interval_minutes || 60) > 60 ? "s" : ""} Gap`
                        : `${tallyStatus?.sync_interval_minutes || 60} Min Gap`}
                    </span>
                  </div>
                  <p className="text-xs text-slate-500 leading-relaxed max-w-xl">
                    New sales bills are fetched <strong>instantly in real time</strong> (~0.1s lightweight check) whenever a bill is generated in Tally.
                    Heavy stock balance calculations run on this relaxed interval (or via manual pull) to prevent any Tally billing lag.
                  </p>
                </div>

                <div className="flex items-center gap-2 shrink-0">
                  {[
                    { label: "1 Hour", mins: 60 },
                    { label: "2 Hours", mins: 120 },
                    { label: "5 Hours", mins: 300 },
                  ].map((opt) => {
                    const isSelected = (tallyStatus?.sync_interval_minutes || 60) === opt.mins && tallyStatus?.auto_sync;
                    return (
                      <button
                        key={opt.mins}
                        type="button"
                        onClick={() => handleChangeSyncInterval(opt.mins)}
                        disabled={togglingTally || loadingTallyStatus || !tallyStatus?.auto_sync}
                        className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all cursor-pointer disabled:opacity-50 ${
                          isSelected
                            ? "bg-[#3C3489] text-white shadow-xs"
                            : "bg-white text-slate-700 border border-slate-200 hover:bg-slate-100"
                        }`}
                      >
                        {opt.label}
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* Sub-section: Instance Specific Toggles */}
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <h4 className="text-xs font-bold uppercase tracking-wider text-slate-500">
                    Individual Tally Machine Controls
                  </h4>
                  
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  {/* Tally 1 Toggle Card */}
                  <div className={`p-4 rounded-xl border transition-all ${
                    tallyStatus?.enable_tally_1 
                      ? "bg-white border-slate-200 shadow-xs" 
                      : "bg-slate-50/70 border-slate-200 opacity-80"
                  }`}>
                    <div className="flex items-start justify-between gap-3">
                      <div className="space-y-1.5 flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="font-bold text-xs text-slate-900">
                            Tally 1 (Current FY)
                          </span>
                          {tallyStatus?.enable_tally_1 ? (
                            tallyStatus?.tally_1_connected ? (
                              <span className="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-200 inline-flex items-center gap-1">
                                <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
                                CONNECTED
                              </span>
                            ) : (
                              <span className="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-800 border border-amber-200">
                                OFFLINE
                              </span>
                            )
                          ) : (
                            <span className="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-slate-200 text-slate-700">
                              READING STOPPED
                            </span>
                          )}
                        </div>
                        <p className="text-xs font-semibold text-slate-800 truncate" title={tallyStatus?.tally_1_name || "Tally Machine 1"}>
                          {tallyStatus?.tally_1_name || "Tally Machine 1"}
                        </p>
                        <p className="text-[11px] text-slate-500 pt-0.5 leading-snug">
                          Live billing &amp; real-time warehouse stock sync.
                        </p>
                      </div>

                      <button
                        type="button"
                        onClick={handleToggleTally1}
                        disabled={togglingTally || loadingTallyStatus}
                        className="cursor-pointer shrink-0 transition-transform active:scale-95 focus:outline-none disabled:opacity-50 mt-0.5"
                        title={tallyStatus?.enable_tally_1 ? "Stop reading from Tally 1" : "Start reading from Tally 1"}
                      >
                        {tallyStatus?.enable_tally_1 ? (
                          <ToggleRight size={34} className="text-indigo-600" />
                        ) : (
                          <ToggleLeft size={34} className="text-slate-300 hover:text-slate-400" />
                        )}
                      </button>
                    </div>
                  </div>

                  {/* Tally 2 Toggle Card */}
                  <div className={`p-4 rounded-xl border transition-all ${
                    tallyStatus?.enable_tally_2 
                      ? "bg-white border-slate-200 shadow-xs" 
                      : "bg-slate-50/70 border-slate-200 opacity-80"
                  }`}>
                    <div className="flex items-start justify-between gap-3">
                      <div className="space-y-1.5 flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="font-bold text-xs text-slate-900">
                            Tally 2 (Current FY)
                          </span>
                          {tallyStatus?.enable_tally_2 ? (
                            tallyStatus?.tally_2_connected ? (
                              <span className="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-200 inline-flex items-center gap-1">
                                <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
                                CONNECTED
                              </span>
                            ) : (
                              <span className="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-800 border border-amber-200">
                                OFFLINE
                              </span>
                            )
                          ) : (
                            <span className="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-slate-200 text-slate-700">
                              READING STOPPED
                            </span>
                          )}
                        </div>
                        <p className="text-xs font-semibold text-slate-800 truncate" title={tallyStatus?.tally_2_name || "Tally Machine 2"}>
                          {tallyStatus?.tally_2_name || "Tally Machine 2"}
                        </p>
                        <p className="text-[11px] text-slate-500 pt-0.5 leading-snug">
                          Live billing &amp; real-time warehouse stock sync.
                        </p>
                      </div>

                      <button
                        type="button"
                        onClick={handleToggleTally2}
                        disabled={togglingTally || loadingTallyStatus}
                        className="cursor-pointer shrink-0 transition-transform active:scale-95 focus:outline-none disabled:opacity-50 mt-0.5"
                        title={tallyStatus?.enable_tally_2 ? "Stop reading from Tally 2" : "Start reading from Tally 2"}
                      >
                        {tallyStatus?.enable_tally_2 ? (
                          <ToggleRight size={34} className="text-indigo-600" />
                        ) : (
                          <ToggleLeft size={34} className="text-slate-300 hover:text-slate-400" />
                        )}
                      </button>
                    </div>
                  </div>
                </div>
              </div>

              {/* Status Warning if Reading is Paused */}
              {(!tallyStatus?.auto_sync || (!tallyStatus?.enable_tally_1 && !tallyStatus?.enable_tally_2)) && (
                <div className="p-3.5 rounded-xl bg-amber-50 border border-amber-200 text-amber-900 text-xs flex items-start gap-2.5">
                  <AlertCircle size={16} className="text-amber-600 shrink-0 mt-0.5" />
                  <div className="space-y-0.5">
                    <p className="font-semibold">
                      {!tallyStatus?.auto_sync 
                        ? "Tally background reading is stopped." 
                        : "Both Tally 1 and Tally 2 reading are disabled."}
                    </p>
                    <p className="text-amber-800">
                      GA STOCK will not query or pull data from stopped Tally machines. Existing warehouse models, serials, and historical bills remain fully accessible.
                    </p>
                  </div>
                </div>
              )}

              {/* Manual Data Pull Actions */}
              <div className="pt-2 border-t border-slate-100 space-y-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="space-y-0.5">
                    <h4 className="text-xs font-bold text-slate-800">Manual On-Demand Pull</h4>
                    <p className="text-[11px] text-slate-500">
                      Pull stock items, categories, customer shops, or bills on demand from enabled Tally machines.
                    </p>
                  </div>
                  {tallyStatus?.last_sync_at && (
                    <span className="text-[11px] text-slate-400 font-medium">
                      Last synced: {new Date(tallyStatus.last_sync_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                    </span>
                  )}
                </div>

                <div className="flex flex-wrap items-center gap-3 pt-1">
                  <button
                    type="button"
                    onClick={handlePullMasters}
                    disabled={pullingMasters || pullingBills || (!tallyStatus?.enable_tally_1 && !tallyStatus?.enable_tally_2)}
                    className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-[#3C3489] text-white text-xs font-semibold hover:bg-[#302970] shadow-xs transition-all cursor-pointer disabled:opacity-50"
                  >
                    <RefreshCw size={14} className={pullingMasters ? "animate-spin" : ""} />
                    <span>{pullingMasters ? "Pulling from Tally..." : "Pull Items, Categories & Shops"}</span>
                  </button>

                  <button
                    type="button"
                    onClick={handlePullFullBills}
                    disabled={pullingMasters || pullingBills || (!tallyStatus?.enable_tally_1 && !tallyStatus?.enable_tally_2)}
                    className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-white text-slate-700 border border-slate-200 text-xs font-semibold hover:bg-slate-50 shadow-xs transition-all cursor-pointer disabled:opacity-50"
                  >
                    <RefreshCw size={14} className={pullingBills ? "animate-spin" : ""} />
                    <span>{pullingBills ? "Syncing Bills..." : "Pull Bills Now"}</span>
                  </button>
                </div>
              </div>

            </div>
          </div>
          
          {/* Card: Stock & Serial Import Feature Toggle */}
          <div className="bg-white rounded-2xl border border-slate-200 shadow-sm overflow-hidden">
            <div className="p-5 bg-gradient-to-r from-slate-900 to-indigo-950 text-white flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-xl bg-white/10 text-indigo-300">
                  <UploadCloud size={20} />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Stock & Serial Import Settings</h3>
                  <p className="text-xs text-slate-300">Control data import options across warehouse stock screens</p>
                </div>
              </div>
            </div>

            <div className="p-6 space-y-6 divide-y divide-slate-100">
              
              {/* The Import Toggle */}
              <div className="flex items-start justify-between gap-6 pt-2 first:pt-0">
                <div className="space-y-1 max-w-xl">
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-sm text-slate-900">Activate Serial Import Option</span>
                    {activateImport ? (
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-200">
                        ACTIVE
                      </span>
                    ) : (
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-slate-100 text-slate-600 border border-slate-200">
                        DISABLED
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-slate-500 leading-relaxed">
                    Adds an <strong>"Import Serials"</strong> button to each model card and serial inspection modal on the <strong>Stock</strong> page. 
                    Allows admins to quickly backfill or record existing serials with custom statuses: 
                    <span className="font-medium text-slate-700"> In Stock, Dispatched, Returned, or Damaged</span>.
                  </p>
                </div>

                <button
                  type="button"
                  onClick={handleToggleImport}
                  className="cursor-pointer shrink-0 transition-transform active:scale-95 focus:outline-none"
                  title={activateImport ? "Click to deactivate" : "Click to activate"}
                >
                  {activateImport ? (
                    <ToggleRight size={38} className="text-indigo-600" />
                  ) : (
                    <ToggleLeft size={38} className="text-slate-300 hover:text-slate-400" />
                  )}
                </button>
              </div>

              {/* Empty Categories Display Toggle */}
              <div className="flex items-start justify-between gap-6 pt-6">
                <div className="space-y-1 max-w-xl">
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-sm text-slate-900">Show Empty Categories</span>
                    {showEmptyCategories ? (
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-200">
                        SHOW ALL
                      </span>
                    ) : (
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-indigo-100 text-indigo-800 border border-indigo-200">
                        ONLY WITH MODELS (RECOMMENDED)
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-slate-500 leading-relaxed">
                    When disabled, categories with <strong>0 models</strong> synced from Tally are hidden from the category filter bar on the <strong>Stock</strong> page, leaving only active categories with models.
                    Enable this if you need to browse or inspect all empty Tally stock groups.
                  </p>
                </div>

                <button
                  type="button"
                  onClick={handleToggleEmptyCategories}
                  className="cursor-pointer shrink-0 transition-transform active:scale-95 focus:outline-none"
                  title={showEmptyCategories ? "Click to hide empty categories" : "Click to show all categories"}
                >
                  {showEmptyCategories ? (
                    <ToggleRight size={38} className="text-indigo-600" />
                  ) : (
                    <ToggleLeft size={38} className="text-slate-300 hover:text-slate-400" />
                  )}
                </button>
              </div>

              {/* Bill Delete & Update Options Toggle */}
              <div className="flex items-start justify-between gap-6 pt-6">
                <div className="space-y-1 max-w-xl">
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-sm text-slate-900">Allow Bill Edit &amp; Deletion</span>
                    {allowBillModifications ? (
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-amber-100 text-amber-800 border border-amber-200">
                        OPTIONS VISIBLE (ACTIVE)
                      </span>
                    ) : (
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-slate-100 text-slate-600 border border-slate-200">
                        HIDDEN / PROTECTED (DEFAULT)
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-slate-500 leading-relaxed">
                    Controls whether <strong>Cancel Bill</strong>, <strong>Delete Bill</strong>, <strong>Update Bill Details</strong>, and <strong>Serial Edit &amp; Delete</strong> options are shown on the <strong>Bills &amp; Invoices</strong> page. 
                    Keep this disabled in everyday operations to prevent accidental cancellation or modifications to outward dispatch bills.
                  </p>
                </div>

                <button
                  type="button"
                  onClick={handleToggleBillModifications}
                  className="cursor-pointer shrink-0 transition-transform active:scale-95 focus:outline-none"
                  title={allowBillModifications ? "Click to hide bill delete & update options" : "Click to show bill delete & update options"}
                >
                  {allowBillModifications ? (
                    <ToggleRight size={38} className="text-indigo-600" />
                  ) : (
                    <ToggleLeft size={38} className="text-slate-300 hover:text-slate-400" />
                  )}
                </button>
              </div>

              {/* Explanatory Box */}
              <div className="pt-6">
                <div className="p-4 rounded-xl bg-slate-50 border border-slate-200/80 flex items-start gap-3">
                  <Info size={18} className="text-indigo-600 shrink-0 mt-0.5" />
                  <div className="text-xs text-slate-600 space-y-1.5">
                    <p className="font-semibold text-slate-800">How Model Serial Import works when activated:</p>
                    <ul className="list-disc pl-4 space-y-1 text-slate-600">
                      <li><strong>In Stock / Inwarded:</strong> Creates the serial number and automatically increments live warehouse stock for that model.</li>
                      <li><strong>Dispatched / Outwarded:</strong> Records the serial in history as already dispatched so past sales are tracked, without altering godown stock.</li>
                      <li><strong>Returned:</strong> Records unit as returned for warranty or customer tracking.</li>
                      <li><strong>Damaged:</strong> Records unit as damaged without adding to saleable stock.</li>
                    </ul>
                  </div>
                </div>
              </div>

            </div>
          </div>

        </div>

        {/* Right 1 Col: Quick Reference & System Info */}
        <div className="space-y-6">
          {/* Tally Connection Summary Card */}
          <div className="bg-white rounded-2xl border border-slate-200 shadow-sm p-6 space-y-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2 text-slate-900 font-bold text-sm">
                <Server className="text-indigo-600" size={18} />
                <span>Tally Reading Summary</span>
              </div>
              <button
                type="button"
                onClick={fetchTallyStatus}
                disabled={loadingTallyStatus}
                title="Refresh Tally status"
                className="text-slate-400 hover:text-slate-600 p-1 rounded-lg hover:bg-slate-50 transition-colors cursor-pointer"
              >
                <RefreshCw size={14} className={loadingTallyStatus ? "animate-spin text-indigo-600" : ""} />
              </button>
            </div>

            <div className="space-y-3 divide-y divide-slate-100 text-xs">
              <div className="flex items-center justify-between pt-1">
                <span className="text-slate-500">Auto-Sync Reading</span>
                {tallyStatus?.auto_sync ? (
                  <span className="font-semibold text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-200">
                    Active
                  </span>
                ) : (
                  <span className="font-semibold text-rose-700 bg-rose-50 px-2 py-0.5 rounded-full border border-rose-200">
                    Stopped
                  </span>
                )}
              </div>

              <div className="flex items-center justify-between pt-2">
                <span className="text-slate-500">Sync Frequency</span>
                <span className="font-semibold text-slate-800">
                  {tallyStatus?.auto_sync
                    ? `${(tallyStatus?.sync_interval_minutes || 60) >= 60 ? (tallyStatus?.sync_interval_minutes || 60) / 60 + ' hr gap' : (tallyStatus?.sync_interval_minutes || 60) + ' min gap'}`
                    : 'Manual Only'}
                </span>
              </div>

              <div className="flex items-center justify-between pt-2">
                <div>
                  <p className="font-medium text-slate-800">Tally 1 (Current FY)</p>
                  <p className="text-[10px] text-slate-400">Active Billing</p>
                </div>
                {tallyStatus?.enable_tally_1 ? (
                  tallyStatus?.tally_1_connected ? (
                    <span className="font-semibold text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-200">
                      Reading
                    </span>
                  ) : (
                    <span className="font-semibold text-amber-700 bg-amber-50 px-2 py-0.5 rounded-full border border-amber-200">
                      Unreachable
                    </span>
                  )
                ) : (
                  <span className="font-semibold text-slate-500 bg-slate-100 px-2 py-0.5 rounded-full">
                    Off
                  </span>
                )}
              </div>

              <div className="flex items-center justify-between pt-2">
                <div>
                  <p className="font-medium text-slate-800">Tally 2 (Current FY)</p>
                  <p className="text-[10px] text-slate-400">Active Billing</p>
                </div>
                {tallyStatus?.enable_tally_2 ? (
                  tallyStatus?.tally_2_connected ? (
                    <span className="font-semibold text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-200">
                      Reading
                    </span>
                  ) : (
                    <span className="font-semibold text-amber-700 bg-amber-50 px-2 py-0.5 rounded-full border border-amber-200">
                      Unreachable
                    </span>
                  )
                ) : (
                  <span className="font-semibold text-slate-500 bg-slate-100 px-2 py-0.5 rounded-full">
                    Off
                  </span>
                )}
              </div>
            </div>

            <div className="pt-2 border-t border-slate-100 text-[11px] text-slate-400">
              {tallyStatus?.last_sync_at ? (
                <span>Last auto-sync: {new Date(tallyStatus.last_sync_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>
              ) : (
                <span>No sync cycle completed yet</span>
              )}
            </div>
          </div>

          <div className="bg-white rounded-2xl border border-slate-200 shadow-sm p-6 space-y-4">
            <div className="flex items-center gap-2.5 text-slate-900 font-bold text-sm">
              <ShieldCheck className="text-emerald-600" size={18} />
              <span>Administrator Privileges</span>
            </div>
            <p className="text-xs text-slate-500 leading-relaxed">
              You are signed in as an administrator ({user?.username || "Admin"}). 
              Configuration toggles here immediately affect all staff and admin sessions in the web portal.
            </p>
            <div className="pt-2 border-t border-slate-100 flex items-center justify-between text-xs text-slate-500">
              <span>WMS Engine</span>
              <span className="font-mono font-semibold text-slate-800">GA STOCK v2.0</span>
            </div>
          </div>
        </div>

      </div>
    </div>
  );
};
export default SettingsPage;
