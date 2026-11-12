import React, { useState, useEffect } from "react";
import { 
  Settings as SettingsIcon, 
  UploadCloud, 
  CheckCircle2, 
  ShieldCheck, 
  Info,
  ToggleLeft,
  ToggleRight
} from "lucide-react";
import { useAuth } from "../context/AuthContext";

export const SettingsPage: React.FC = () => {
  const { user } = useAuth();
  const [activateImport, setActivateImport] = useState<boolean>(false);
  const [saveToast, setSaveToast] = useState<string | null>(null);

  useEffect(() => {
    const saved = localStorage.getItem("feature_activate_serial_import");
    // Default to true if not set, or read from localStorage
    setActivateImport(saved === "true");
  }, []);

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

      {/* Main Settings Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* Left 2 Cols: Main Feature Toggles */}
        <div className="lg:col-span-2 space-y-6">
          
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
