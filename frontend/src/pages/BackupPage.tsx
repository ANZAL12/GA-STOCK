import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  ClipboardCopy,
  Database,
  DatabaseBackup,
  Download,
  FileJson,
  Info,
  Layers,
  RefreshCw,
  RotateCcw,
  ShieldAlert,
  Trash2,
  Upload,
} from "lucide-react";
import { apiRequest } from "../api/client";

interface BackupSummaryResponse {
  generated_at: string;
  total_records: number;
  counts: Record<string, number>;
}

interface BackupPayload {
  backup_version?: number;
  app?: string;
  exported_at?: string;
  exported_by?: string;
  total_records?: number;
  counts?: Record<string, number>;
  data: Record<string, unknown[]>;
}

interface RestoreResponse {
  status: string;
  mode: "replace" | "merge";
  restored_at: string;
  total_records: number;
  counts: Record<string, number>;
}

const TABLE_LABELS: { key: string; label: string }[] = [
  { key: "users", label: "Users" },
  { key: "devices", label: "Devices" },
  { key: "categories", label: "Categories" },
  { key: "shops", label: "Shops" },
  { key: "products", label: "Models / Stock" },
  { key: "serial_numbers", label: "Serial Numbers" },
  { key: "inward_batches", label: "Inward Batches" },
  { key: "inward_lines", label: "Inward Lines" },
  { key: "outward_batches", label: "Outward Bills" },
  { key: "outward_lines", label: "Outward Lines" },
  { key: "returns", label: "Returns" },
  { key: "serial_history", label: "Serial History" },
  { key: "audit_log", label: "Audit Logs" },
  { key: "tally_configs", label: "Tally Configs" },
  { key: "tally_sales_vouchers", label: "Tally Bills" },
  { key: "tally_voucher_items", label: "Tally Bill Items" },
  { key: "tally_sync_histories", label: "Tally Sync Logs" },
];

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

function formatTimestamp(iso?: string): string {
  if (!iso) return "Unknown";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

function parseBackupText(rawText: string) {
  const trimmed = rawText.trim();
  if (!trimmed) {
    return {
      valid: false,
      error: null as string | null,
      payload: null as BackupPayload | null,
      counts: {} as Record<string, number>,
      total: 0,
    };
  }
  try {
    const obj = JSON.parse(trimmed) as BackupPayload;
    if (!obj || typeof obj !== "object" || !obj.data || typeof obj.data !== "object") {
      return {
        valid: false,
        error: "Invalid backup format: missing top-level 'data' object.",
        payload: null,
        counts: {},
        total: 0,
      };
    }
    const counts: Record<string, number> = {};
    let total = 0;
    let recognizedTables = 0;
    for (const { key } of TABLE_LABELS) {
      if (key in obj.data) {
        const arr = obj.data[key];
        if (!Array.isArray(arr)) {
          return {
            valid: false,
            error: `Invalid backup format: 'data.${key}' must be an array.`,
            payload: null,
            counts: {},
            total: 0,
          };
        }
        counts[key] = arr.length;
        total += arr.length;
        recognizedTables++;
      } else {
        counts[key] = 0;
      }
    }
    if (recognizedTables === 0) {
      return {
        valid: false,
        error: "No recognized GA STOCK database tables found in 'data'.",
        payload: null,
        counts: {},
        total: 0,
      };
    }
    return { valid: true, error: null, payload: obj, counts, total };
  } catch (err: any) {
    return {
      valid: false,
      error: `Invalid JSON: ${err.message || "Could not parse backup text"}`,
      payload: null,
      counts: {},
      total: 0,
    };
  }
}

export const BackupPage: React.FC = () => {
  const [summary, setSummary] = useState<BackupSummaryResponse | null>(null);
  const [loadingSummary, setLoadingSummary] = useState(true);
  const [exporting, setExporting] = useState(false);
  const [copying, setCopying] = useState(false);
  const [copiedBanner, setCopiedBanner] = useState(false);
  const [lastExportInfo, setLastExportInfo] = useState<{
    filename: string;
    exportedAt: string;
    totalRecords: number;
    sizeBytes: number;
  } | null>(null);

  // Restore state
  const [rawText, setRawText] = useState("");
  const [sourceLabel, setSourceLabel] = useState<string | null>(null);
  const [restoreMode, setRestoreMode] = useState<"replace" | "merge">("replace");
  const [confirmKeyword, setConfirmKeyword] = useState("");
  const [isDragging, setIsDragging] = useState(false);
  const [restoring, setRestoring] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [restoreResult, setRestoreResult] = useState<RestoreResponse | null>(null);

  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const fetchSummary = useCallback(async () => {
    try {
      setLoadingSummary(true);
      const data = await apiRequest<BackupSummaryResponse>("/backup/summary");
      setSummary(data);
    } catch (err: any) {
      setErrorMsg(err.message || "Failed to load database summary.");
    } finally {
      setLoadingSummary(false);
    }
  }, []);

  useEffect(() => {
    let active = true;
    apiRequest<BackupSummaryResponse>("/backup/summary")
      .then((data) => {
        if (active) setSummary(data);
      })
      .catch((err: any) => {
        if (active) setErrorMsg(err.message || "Failed to load database summary.");
      })
      .finally(() => {
        if (active) setLoadingSummary(false);
      });
    return () => {
      active = false;
    };
  }, []);

  const parsedPreview = useMemo(() => parseBackupText(rawText), [rawText]);

  const handleDownloadBackup = async () => {
    try {
      setExporting(true);
      setErrorMsg(null);
      const payload = await apiRequest<BackupPayload>("/backup/export");
      const jsonStr = JSON.stringify(payload, null, 2);
      const blob = new Blob([jsonStr], { type: "application/json" });
      const now = new Date();
      const pad = (n: number) => String(n).padStart(2, "0");
      const filename = `ga-stock-backup-${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}_${pad(now.getHours())}-${pad(now.getMinutes())}-${pad(now.getSeconds())}.json`;

      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);

      setLastExportInfo({
        filename,
        exportedAt: payload.exported_at || now.toISOString(),
        totalRecords: payload.total_records ?? 0,
        sizeBytes: blob.size,
      });
    } catch (err: any) {
      setErrorMsg(err.message || "Failed to export backup.");
    } finally {
      setExporting(false);
    }
  };

  const handleCopyBackup = async () => {
    try {
      setCopying(true);
      setErrorMsg(null);
      const payload = await apiRequest<BackupPayload>("/backup/export");
      const jsonStr = JSON.stringify(payload, null, 2);
      await navigator.clipboard.writeText(jsonStr);
      setCopiedBanner(true);
      setLastExportInfo({
        filename: "Copied to Clipboard",
        exportedAt: payload.exported_at || new Date().toISOString(),
        totalRecords: payload.total_records ?? 0,
        sizeBytes: new Blob([jsonStr]).size,
      });
      setTimeout(() => setCopiedBanner(false), 3500);
    } catch (err: any) {
      setErrorMsg(err.message || "Failed to copy backup JSON to clipboard.");
    } finally {
      setCopying(false);
    }
  };

  const loadBackupFile = useCallback(async (file: File) => {
    setErrorMsg(null);
    setRestoreResult(null);
    try {
      const text = await file.text();
      setRawText(text);
      setSourceLabel(`${file.name} (${formatBytes(file.size)})`);
    } catch {
      setErrorMsg(`Could not read file "${file.name}".`);
    }
  }, []);

  const handleFileInputChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      await loadBackupFile(file);
    }
    e.target.value = "";
  };

  const handleDrop = async (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);
    const file = e.dataTransfer.files?.[0];
    if (file) {
      await loadBackupFile(file);
    }
  };

  const handlePaste = async (e: React.ClipboardEvent<HTMLDivElement | HTMLTextAreaElement>) => {
    // Support pasting a copied .json file directly from File Explorer!
    const files = e.clipboardData?.files;
    if (files && files.length > 0) {
      e.preventDefault();
      await loadBackupFile(files[0]);
      return;
    }

    // If pasted onto the outer container (not the textarea itself), read pasted text
    if (e.target instanceof HTMLTextAreaElement) {
      setSourceLabel("Pasted JSON");
      setRestoreResult(null);
      setErrorMsg(null);
      return;
    }

    const text = e.clipboardData?.getData("text");
    if (text) {
      e.preventDefault();
      setRawText(text);
      setSourceLabel("Pasted JSON");
      setRestoreResult(null);
      setErrorMsg(null);
    }
  };

  const handleClearRestore = () => {
    setRawText("");
    setSourceLabel(null);
    setConfirmKeyword("");
    setErrorMsg(null);
    setRestoreResult(null);
  };

  const handleRestore = async () => {
    if (!parsedPreview.valid || !parsedPreview.payload) {
      setErrorMsg(parsedPreview.error || "Please paste or load a valid backup file first.");
      return;
    }

    if (restoreMode === "replace" && confirmKeyword.trim().toUpperCase() !== "RESTORE") {
      setErrorMsg('Please type "RESTORE" in the confirmation box to proceed with Full Replace.');
      return;
    }

    try {
      setRestoring(true);
      setErrorMsg(null);
      setRestoreResult(null);

      const res = await apiRequest<RestoreResponse>("/backup/restore", {
        method: "POST",
        body: JSON.stringify({
          backup: parsedPreview.payload,
          mode: restoreMode,
        }),
      });

      setRestoreResult(res);
      setConfirmKeyword("");
      await fetchSummary();
    } catch (err: any) {
      setErrorMsg(err.message || "Restore failed. Existing database records were not modified.");
    } finally {
      setRestoring(false);
    }
  };

  const canSubmitRestore =
    parsedPreview.valid &&
    !restoring &&
    (restoreMode === "merge" || confirmKeyword.trim().toUpperCase() === "RESTORE");

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 bg-white border border-slate-200/80 rounded-2xl p-6 shadow-sm">
        <div>
          <div className="flex items-center gap-2">
            <span className="text-[11px] font-bold px-2.5 py-0.5 rounded-full bg-indigo-50 text-[#3C3489] border border-indigo-200 uppercase tracking-wider">
              Administration
            </span>
            <span className="text-[11px] font-bold px-2.5 py-0.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200 uppercase tracking-wider">
              Full Snapshot
            </span>
          </div>
          <h1 className="text-2xl font-extrabold text-slate-900 tracking-tight mt-1.5 flex items-center gap-2.5">
            <DatabaseBackup className="text-[#3C3489]" size={26} />
            Database Backup & Restore
          </h1>
          <p className="text-xs text-slate-500 mt-1">
            Export a complete JSON backup of all warehouse records, or paste / upload a backup file on this page to restore data.
          </p>
        </div>

        <button
          type="button"
          onClick={fetchSummary}
          disabled={loadingSummary}
          className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs font-semibold bg-slate-100 hover:bg-slate-200 text-slate-700 border border-slate-200 transition-colors cursor-pointer disabled:opacity-50 self-start sm:self-auto"
        >
          <RefreshCw size={14} className={loadingSummary ? "animate-spin" : ""} />
          Refresh Live Counts
        </button>
      </div>

      {/* Global Error / Success Alerts */}
      {errorMsg && (
        <div className="p-4 rounded-xl bg-rose-50 border border-rose-200 text-rose-800 text-sm font-medium flex items-start gap-3 shadow-sm">
          <AlertTriangle size={18} className="text-rose-600 shrink-0 mt-0.5" />
          <div className="flex-1">{errorMsg}</div>
        </div>
      )}

      {copiedBanner && (
        <div className="p-4 rounded-xl bg-emerald-50 border border-emerald-200 text-emerald-800 text-sm font-medium flex items-center gap-3 shadow-sm">
          <CheckCircle2 size={18} className="text-emerald-600 shrink-0" />
          <span>Full backup JSON copied to clipboard. You can paste it directly into the Restore box or save it in a file.</span>
        </div>
      )}

      {restoreResult && (
        <div className="p-5 rounded-2xl bg-emerald-50 border border-emerald-200 text-emerald-900 shadow-sm space-y-3">
          <div className="flex items-center gap-2.5 font-bold text-sm">
            <CheckCircle2 size={20} className="text-emerald-600 shrink-0" />
            <span>
              Backup Restored Successfully ({restoreResult.mode === "replace" ? "Full Replace" : "Merge"} •{" "}
              {restoreResult.total_records.toLocaleString()} records loaded)
            </span>
          </div>
          <div className="flex flex-wrap gap-2">
            {TABLE_LABELS.map(({ key, label }) => {
              const count = restoreResult.counts[key] ?? 0;
              if (count === 0) return null;
              return (
                <span
                  key={key}
                  className="text-xs px-2.5 py-1 rounded-lg bg-white border border-emerald-200 text-emerald-800 font-semibold"
                >
                  {label}: {count.toLocaleString()}
                </span>
              );
            })}
          </div>
        </div>
      )}

      {/* Live Database Summary */}
      <div className="bg-white border border-slate-200/80 rounded-2xl p-5 shadow-sm space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <Database size={16} className="text-[#3C3489]" />
            <h2 className="text-sm font-bold text-slate-900">Current Live Database</h2>
          </div>
          <span className="text-xs font-semibold px-3 py-1 rounded-full bg-slate-100 text-slate-700 border border-slate-200">
            Total Records: {loadingSummary ? "..." : (summary?.total_records ?? 0).toLocaleString()}
          </span>
        </div>

        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-2.5">
          {TABLE_LABELS.map(({ key, label }) => (
            <div
              key={key}
              className="px-3 py-2.5 rounded-xl bg-slate-50 border border-slate-200/80 flex items-center justify-between gap-2"
            >
              <span className="text-xs text-slate-600 font-medium truncate">{label}</span>
              <span className="text-xs font-bold text-slate-900 tabular-nums">
                {loadingSummary ? "–" : (summary?.counts?.[key] ?? 0).toLocaleString()}
              </span>
            </div>
          ))}
        </div>
      </div>

      {/* Main 2-Column Backup & Restore Workspace */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        {/* Left Column: Export / Take Backup */}
        <div className="lg:col-span-5 bg-white border border-slate-200/80 rounded-2xl shadow-sm overflow-hidden">
          <div className="p-5 bg-gradient-to-r from-slate-900 to-[#3C3489] text-white flex items-center gap-3">
            <div className="p-2.5 rounded-xl bg-white/10 text-indigo-200">
              <Download size={20} />
            </div>
            <div>
              <h2 className="text-base font-bold">1. Take Full Backup</h2>
              <p className="text-xs text-slate-300">Download or copy all warehouse tables into one file</p>
            </div>
          </div>

          <div className="p-6 space-y-5">
            <div className="p-4 rounded-xl bg-slate-50 border border-slate-200/80 flex items-start gap-3">
              <Info size={18} className="text-[#3C3489] shrink-0 mt-0.5" />
              <div className="text-xs text-slate-600 space-y-1.5 leading-relaxed">
                <p className="font-semibold text-slate-800">What is backed up:</p>
                <p>
                  Users, approved devices, categories, shops, products &amp; stock levels, all serial numbers,
                  inward batches, outward bills, returns, full serial history, audit logs, and Tally sync vouchers.
                </p>
              </div>
            </div>

            <div className="flex flex-col sm:flex-row gap-3">
              <button
                type="button"
                onClick={handleDownloadBackup}
                disabled={exporting || copying}
                className="flex-1 inline-flex items-center justify-center gap-2 px-4 py-3 rounded-xl text-sm font-bold bg-[#3C3489] hover:bg-[#312a73] text-white shadow-sm transition-colors cursor-pointer disabled:opacity-50"
              >
                <Download size={16} />
                {exporting ? "Preparing Backup..." : "Download Backup (.json)"}
              </button>

              <button
                type="button"
                onClick={handleCopyBackup}
                disabled={exporting || copying}
                className="inline-flex items-center justify-center gap-2 px-4 py-3 rounded-xl text-sm font-semibold bg-slate-100 hover:bg-slate-200 text-slate-800 border border-slate-200 transition-colors cursor-pointer disabled:opacity-50"
              >
                <ClipboardCopy size={16} />
                {copying ? "Copying..." : "Copy JSON"}
              </button>
            </div>

            {lastExportInfo && (
              <div className="p-4 rounded-xl bg-indigo-50/70 border border-indigo-200/80 space-y-1.5 text-xs">
                <div className="font-bold text-[#3C3489] flex items-center gap-1.5">
                  <FileJson size={15} />
                  Last Backup Exported
                </div>
                <div className="text-slate-700 font-mono break-all">{lastExportInfo.filename}</div>
                <div className="text-slate-600 flex flex-wrap gap-x-4 gap-y-1">
                  <span>Records: <strong>{lastExportInfo.totalRecords.toLocaleString()}</strong></span>
                  <span>Size: <strong>{formatBytes(lastExportInfo.sizeBytes)}</strong></span>
                  <span>Time: <strong>{formatTimestamp(lastExportInfo.exportedAt)}</strong></span>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Right Column: Restore from Pasted File or JSON */}
        <div
          className="lg:col-span-7 bg-white border border-slate-200/80 rounded-2xl shadow-sm overflow-hidden"
          onPaste={handlePaste}
        >
          <div className="p-5 bg-gradient-to-r from-slate-900 to-slate-800 text-white flex items-center justify-between gap-3">
            <div className="flex items-center gap-3">
              <div className="p-2.5 rounded-xl bg-white/10 text-amber-300">
                <RotateCcw size={20} />
              </div>
              <div>
                <h2 className="text-base font-bold">2. Restore Backup</h2>
                <p className="text-xs text-slate-300">Paste your backup file / JSON text or drop a .json file below to load data</p>
              </div>
            </div>

            {rawText && (
              <button
                type="button"
                onClick={handleClearRestore}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold bg-white/10 hover:bg-white/20 text-white transition-colors cursor-pointer"
              >
                <Trash2 size={13} />
                Clear
              </button>
            )}
          </div>

          <div className="p-6 space-y-5">
            {/* Drag & Drop / Paste / File Picker Zone */}
            <div
              onDragOver={(e) => {
                e.preventDefault();
                setIsDragging(true);
              }}
              onDragLeave={() => setIsDragging(false)}
              onDrop={handleDrop}
              className={`rounded-2xl border-2 border-dashed p-5 text-center transition-colors ${
                isDragging
                  ? "border-[#3C3489] bg-indigo-50/70"
                  : "border-slate-300 bg-slate-50/70 hover:border-slate-400"
              }`}
            >
              <input
                ref={fileInputRef}
                type="file"
                accept=".json,application/json"
                onChange={handleFileInputChange}
                className="hidden"
              />

              <div className="flex flex-col items-center gap-2">
                <div className="w-10 h-10 rounded-xl bg-white border border-slate-200 flex items-center justify-center text-[#3C3489] shadow-sm">
                  <Upload size={18} />
                </div>
                <div className="text-sm font-bold text-slate-800">
                  Drop or Paste (<kbd className="px-1.5 py-0.5 rounded bg-white border border-slate-300 text-[11px] font-mono">Ctrl+V</kbd>) your backup <code className="text-[#3C3489]">.json</code> file here
                </div>
                <p className="text-xs text-slate-500">
                  You can paste a copied <code className="font-mono">.json</code> file from Explorer, drag &amp; drop it, or browse from your computer.
                </p>
                <button
                  type="button"
                  onClick={() => fileInputRef.current?.click()}
                  className="mt-1 inline-flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold bg-white hover:bg-slate-100 text-slate-800 border border-slate-300 shadow-xs transition-colors cursor-pointer"
                >
                  <FileJson size={14} className="text-[#3C3489]" />
                  Choose Backup .json File
                </button>
              </div>
            </div>

            {/* Direct JSON Paste Box */}
            <div className="space-y-1.5">
              <div className="flex items-center justify-between">
                <label className="text-xs font-bold text-slate-700">
                  Or Paste Backup JSON Content Directly
                </label>
                {sourceLabel && (
                  <span className="text-[11px] font-semibold px-2 py-0.5 rounded bg-indigo-50 text-[#3C3489] border border-indigo-200">
                    Loaded: {sourceLabel}
                  </span>
                )}
              </div>
              <textarea
                value={rawText}
                onChange={(e) => {
                  setRawText(e.target.value);
                  setSourceLabel("Pasted JSON");
                  setRestoreResult(null);
                  setErrorMsg(null);
                }}
                rows={6}
                placeholder='Paste your GA STOCK backup JSON here (starts with { "backup_version": 1, "data": { ... } })...'
                className="w-full rounded-xl border border-slate-300 bg-slate-50 px-3.5 py-2.5 text-xs font-mono text-slate-800 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/30 focus:border-[#3C3489]"
              />
            </div>

            {/* Validation / Preview Box */}
            {rawText.trim() && parsedPreview.error && (
              <div className="p-3.5 rounded-xl bg-rose-50 border border-rose-200 text-rose-700 text-xs font-medium flex items-center gap-2">
                <AlertTriangle size={15} className="shrink-0" />
                <span>{parsedPreview.error}</span>
              </div>
            )}

            {parsedPreview.valid && parsedPreview.payload && (
              <div className="p-4 rounded-xl bg-indigo-50/50 border border-indigo-200 space-y-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="flex items-center gap-2 text-xs font-bold text-[#3C3489]">
                    <Layers size={15} />
                    Backup Ready to Restore
                  </div>
                  <span className="text-xs font-bold px-2.5 py-0.5 rounded-full bg-white border border-indigo-200 text-[#3C3489]">
                    {parsedPreview.total.toLocaleString()} records
                  </span>
                </div>

                <div className="flex flex-wrap gap-x-5 gap-y-1 text-xs text-slate-600">
                  <span>
                    Exported: <strong className="text-slate-800">{formatTimestamp(parsedPreview.payload.exported_at)}</strong>
                  </span>
                  {parsedPreview.payload.exported_by && (
                    <span>
                      By: <strong className="text-slate-800">{parsedPreview.payload.exported_by}</strong>
                    </span>
                  )}
                  <span>
                    Format: <strong className="text-slate-800">v{parsedPreview.payload.backup_version ?? 1}</strong>
                  </span>
                </div>

                <div className="flex flex-wrap gap-1.5">
                  {TABLE_LABELS.map(({ key, label }) => {
                    const count = parsedPreview.counts[key] ?? 0;
                    return (
                      <span
                        key={key}
                        className={`text-[11px] px-2 py-0.5 rounded-md border font-medium ${
                          count > 0
                            ? "bg-white border-indigo-200 text-slate-800"
                            : "bg-slate-100/70 border-slate-200 text-slate-400"
                        }`}
                      >
                        {label}: {count.toLocaleString()}
                      </span>
                    );
                  })}
                </div>
              </div>
            )}

            {/* Restore Mode Selector */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <button
                type="button"
                onClick={() => setRestoreMode("replace")}
                className={`p-3.5 rounded-xl border text-left transition-all cursor-pointer ${
                  restoreMode === "replace"
                    ? "border-[#3C3489] bg-indigo-50/60 ring-2 ring-[#3C3489]/15"
                    : "border-slate-200 bg-white hover:border-slate-300"
                }`}
              >
                <div className="text-xs font-bold text-slate-900">Full Replace (Exact Snapshot)</div>
                <div className="text-[11px] text-slate-500 mt-0.5">
                  Clears existing records and restores the exact backed-up state atomically.
                </div>
              </button>

              <button
                type="button"
                onClick={() => setRestoreMode("merge")}
                className={`p-3.5 rounded-xl border text-left transition-all cursor-pointer ${
                  restoreMode === "merge"
                    ? "border-[#3C3489] bg-indigo-50/60 ring-2 ring-[#3C3489]/15"
                    : "border-slate-200 bg-white hover:border-slate-300"
                }`}
              >
                <div className="text-xs font-bold text-slate-900">Merge / Skip Existing</div>
                <div className="text-[11px] text-slate-500 mt-0.5">
                  Loads only missing records from the backup while keeping existing rows untouched.
                </div>
              </button>
            </div>

            {/* Confirmation Input for Full Replace */}
            {restoreMode === "replace" && (
              <div className="p-4 rounded-xl bg-amber-50 border border-amber-200 space-y-2.5">
                <div className="flex items-start gap-2.5 text-xs text-amber-900">
                  <ShieldAlert size={16} className="text-amber-600 shrink-0 mt-0.5" />
                  <div>
                    <span className="font-bold">Warning:</span> Full Replace overwrites all current live data with the backup snapshot inside a single transaction. Type <code className="font-mono font-bold px-1 py-0.5 rounded bg-amber-100">RESTORE</code> below to confirm.
                  </div>
                </div>
                <input
                  type="text"
                  value={confirmKeyword}
                  onChange={(e) => setConfirmKeyword(e.target.value)}
                  placeholder='Type RESTORE to unlock'
                  className="w-full sm:w-64 rounded-lg border border-amber-300 bg-white px-3 py-2 text-xs font-mono font-bold text-slate-900 focus:outline-none focus:ring-2 focus:ring-amber-400"
                />
              </div>
            )}

            {/* Submit Restore Button */}
            <button
              type="button"
              onClick={handleRestore}
              disabled={!canSubmitRestore}
              className="w-full inline-flex items-center justify-center gap-2 px-5 py-3 rounded-xl text-sm font-bold bg-[#3C3489] hover:bg-[#312a73] text-white shadow-sm transition-colors cursor-pointer disabled:opacity-45 disabled:cursor-not-allowed"
            >
              <RotateCcw size={16} className={restoring ? "animate-spin" : ""} />
              {restoring
                ? "Restoring Database..."
                : restoreMode === "replace"
                  ? "Restore Full Backup Snapshot"
                  : "Merge Backup Data into Database"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default BackupPage;
