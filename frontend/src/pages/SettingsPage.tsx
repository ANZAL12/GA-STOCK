import React, { useState, useEffect } from "react";
import { Link } from "react-router-dom";
import {
  Settings as SettingsIcon,
  Receipt,
  CheckCircle2,
  ShieldCheck,
  Info,
  ArrowRight,
} from "lucide-react";
import { useAuth } from "../context/AuthContext";
import { useWebSocket } from "../api/useWebSocket";
import {
  isBillEditDeleteEnabled,
  setBillEditDeleteEnabled,
  fetchBillEditDeleteSetting,
  saveBillEditDeleteSetting,
  BILL_EDIT_DELETE_SETTING_KEY,
  SETTINGS_CHANGED_EVENT,
} from "../utils/settings";

export const SettingsPage: React.FC = () => {
  const { user } = useAuth();
  const [billEditDeleteActive, setBillEditDeleteActive] = useState<boolean>(() =>
    isBillEditDeleteEnabled()
  );
  const [saving, setSaving] = useState(false);
  const [saveToast, setSaveToast] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    fetchBillEditDeleteSetting().then((enabled) => {
      if (active) setBillEditDeleteActive(enabled);
    });

    const sync = (e?: Event) => {
      if (e instanceof StorageEvent && e.key !== BILL_EDIT_DELETE_SETTING_KEY) return;
      setBillEditDeleteActive(isBillEditDeleteEnabled());
    };
    window.addEventListener("storage", sync);
    window.addEventListener(SETTINGS_CHANGED_EVENT, sync);
    return () => {
      active = false;
      window.removeEventListener("storage", sync);
      window.removeEventListener(SETTINGS_CHANGED_EVENT, sync);
    };
  }, []);

  useWebSocket((event, data) => {
    if (event === "settings_updated" && typeof data?.bill_edit_delete_enabled === "boolean") {
      setBillEditDeleteActive(data.bill_edit_delete_enabled);
      setBillEditDeleteEnabled(data.bill_edit_delete_enabled);
    }
  });

  const handleToggleBillEditDelete = async () => {
    if (saving) return;
    const nextVal = !billEditDeleteActive;
    setSaving(true);
    setBillEditDeleteActive(nextVal);
    try {
      const persisted = await saveBillEditDeleteSetting(nextVal);
      setBillEditDeleteActive(persisted);
      setSaveToast(
        persisted
          ? "Bill Edit & Delete Option Activated. Edit and Delete icons are now visible inside specific bill details."
          : "Bill Edit & Delete Option Deactivated. Edit and Delete icons are now removed from specific bill details."
      );
    } finally {
      setSaving(false);
    }
  };

  useEffect(() => {
    if (!saveToast) return;
    const timer = setTimeout(() => setSaveToast(null), 4000);
    return () => clearTimeout(timer);
  }, [saveToast]);

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 pb-5 border-b border-slate-200">
        <div>
          <div className="flex items-center gap-2">
            <span className="p-2 rounded-xl bg-[#EEF2FF] text-[#3C3489]">
              <SettingsIcon size={22} />
            </span>
            <h1 className="text-2xl font-bold text-slate-900 tracking-tight">
              System Settings
            </h1>
          </div>
          <p className="text-sm text-slate-500 mt-1">
            Control administrative options and bill management permissions across the portal.
          </p>
        </div>

        <Link
          to="/bills"
          className="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-semibold text-[#3C3489] bg-[#EEF2FF] hover:bg-indigo-100 border border-[#C7D2FE] transition-colors self-start sm:self-auto"
        >
          <Receipt size={14} />
          Go to Bills Page
          <ArrowRight size={13} />
        </Link>
      </div>

      {/* Save Toast Banner */}
      {saveToast && (
        <div className="p-4 rounded-2xl bg-emerald-50 border border-emerald-200 text-emerald-800 text-xs font-semibold flex items-center gap-2.5 shadow-xs animate-in fade-in">
          <CheckCircle2 size={18} className="text-emerald-600 shrink-0" />
          <span>{saveToast}</span>
        </div>
      )}

      {/* Main Settings Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left 2 Cols: Bill Page Controls */}
        <div className="lg:col-span-2 space-y-6">
          <div className="bg-white rounded-2xl border border-slate-200 shadow-xs overflow-hidden">
            <div className="p-5 bg-gradient-to-r from-[#1E1B4B] to-[#3C3489] text-white flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-xl bg-white/15 text-indigo-100">
                  <Receipt size={20} />
                </div>
                <div>
                  <h2 className="text-base font-bold text-white">Bills Page Controls</h2>
                  <p className="text-xs text-indigo-200">
                    Manage serial-level edit and delete actions inside specific bill views
                  </p>
                </div>
              </div>
            </div>

            <div className="p-6 space-y-6 divide-y divide-slate-100">
              {/* Toggle Row: Bill Edit & Delete Option */}
              <div className="flex items-start justify-between gap-6">
                <div className="space-y-1.5 max-w-xl">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-bold text-sm text-slate-900">
                      Bill Serial Edit &amp; Delete Option
                    </span>
                    {billEditDeleteActive ? (
                      <span className="text-[10px] font-bold px-2.5 py-0.5 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-200">
                        ACTIVE
                      </span>
                    ) : (
                      <span className="text-[10px] font-bold px-2.5 py-0.5 rounded-full bg-slate-100 text-slate-600 border border-slate-200">
                        DEACTIVATED
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-slate-500 leading-relaxed">
                    Controls whether the <strong>Edit</strong> and <strong>Delete</strong> action
                    buttons are shown when an admin opens a specific bill on the{" "}
                    <strong>Bills</strong> page. When deactivated, both buttons are completely
                    removed to prevent accidental serial edits or deletions.
                  </p>
                </div>

                {/* Accessible Toggle Switch */}
                <button
                  type="button"
                  role="switch"
                  aria-checked={billEditDeleteActive}
                  aria-label="Toggle Bill Serial Edit and Delete Option"
                  disabled={saving}
                  onClick={handleToggleBillEditDelete}
                  className={`relative inline-flex h-7 w-13 shrink-0 cursor-pointer items-center rounded-full border-2 border-transparent transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489] focus:ring-offset-2 disabled:opacity-60 ${
                    billEditDeleteActive ? "bg-[#3C3489]" : "bg-slate-300 hover:bg-slate-400"
                  }`}
                  title={billEditDeleteActive ? "Click to deactivate" : "Click to activate"}
                >
                  <span
                    className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow-sm transition duration-200 ${
                      billEditDeleteActive ? "translate-x-6" : "translate-x-1"
                    }`}
                  />
                </button>
              </div>

              {/* Behavior Info Box */}
              <div className="pt-5">
                <div className="p-4 rounded-xl bg-slate-50 border border-slate-200/80 flex items-start gap-3">
                  <Info size={18} className="text-[#3C3489] shrink-0 mt-0.5" />
                  <div className="text-xs text-slate-600 space-y-1.5">
                    <p className="font-semibold text-slate-800">What this setting controls:</p>
                    <ul className="list-disc pl-4 space-y-1 text-slate-600">
                      <li>
                        <strong>When Active:</strong> Opening an active bill on the Bills page displays
                        the <strong>Action</strong> column with <strong>Edit</strong> and{" "}
                        <strong>Delete</strong> icons for each scanned serial line.
                      </li>
                      <li>
                        <strong>When Deactivated:</strong> The <strong>Action</strong> column and its{" "}
                        <strong>Edit / Delete</strong> icons are completely removed from specific bill
                        details (view, print, and PDF download remain available).
                      </li>
                    </ul>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Right 1 Col: Admin Info */}
        <div className="space-y-6">
          <div className="bg-white rounded-2xl border border-slate-200 shadow-xs p-6 space-y-4">
            <div className="flex items-center gap-2.5 text-slate-900 font-bold text-sm">
              <ShieldCheck className="text-emerald-600" size={18} />
              <span>Administrator Controls</span>
            </div>
            <p className="text-xs text-slate-500 leading-relaxed">
              Signed in as{" "}
              <span className="font-semibold text-slate-700">
                {user?.full_name || user?.username || "Admin"}
              </span>
              . Changes sync immediately across all sessions on the Bills page.
            </p>
            <div className="pt-3 border-t border-slate-100 flex items-center justify-between text-xs text-slate-500">
              <span>Bill Edit / Delete</span>
              <span
                className={`font-bold ${
                  billEditDeleteActive ? "text-emerald-700" : "text-slate-500"
                }`}
              >
                {billEditDeleteActive ? "Active" : "Deactivated"}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default SettingsPage;
