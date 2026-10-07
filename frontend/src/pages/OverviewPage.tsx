import React, { useEffect, useState } from "react";
import { apiRequest } from "../api/client";
import { useWebSocket } from "../api/useWebSocket";
import type { 
  OverviewSummary, 
  StockByModelItem, 
  TodayTimelineItem, 
  SerialDetail 
} from "../types";
import { NeedsAttentionStrip } from "../components/NeedsAttentionStrip";
import { Badge } from "../components/Badge";
import { 
  Barcode, 
  ArrowUpRight, 
  ArrowDownRight, 
  Layers, 
  Clock, 
  X, 
  Building2,
  AlertCircle
} from "lucide-react";

export const OverviewPage: React.FC = () => {
  const [summary, setSummary] = useState<OverviewSummary | null>(null);
  const [stockByModel, setStockByModel] = useState<StockByModelItem[]>([]);
  const [timeline, setTimeline] = useState<TodayTimelineItem[]>([]);
  const [loading, setLoading] = useState(true);

  // Search state
  const [searchQuery, setSearchQuery] = useState("");
  const [searchLoading, setSearchLoading] = useState(false);
  const [searchResult, setSearchResult] = useState<SerialDetail | null>(null);
  const [searchError, setSearchError] = useState<string | null>(null);

  const fetchOverviewData = () => {
    Promise.all([
      apiRequest<OverviewSummary>("/reports/overview"),
      apiRequest<StockByModelItem[]>("/reports/stock-by-model"),
      apiRequest<TodayTimelineItem[]>("/reports/today-timeline"),
    ])
      .then(([sum, sbm, tl]) => {
        setSummary(sum);
        setStockByModel(sbm);
        setTimeline(tl);
      })
      .catch(console.error)
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    fetchOverviewData();
  }, []);

  useWebSocket((event) => {
    if (
      event === "stock_updated" ||
      event === "product_created" ||
      event === "product_updated" ||
      event === "product_deleted"
    ) {
      fetchOverviewData();
    }
  });

  const handleSearch = async (e: React.FormEvent) => {
    e.preventDefault();
    const query = searchQuery.trim();
    if (!query) return;

    setSearchLoading(true);
    setSearchError(null);
    setSearchResult(null);

    try {
      const res = await apiRequest<SerialDetail>(`/serials/lookup?serial_number=${encodeURIComponent(query)}`);
      setSearchResult(res);
    } catch (err: any) {
      setSearchError(err.message || "Serial number not found.");
    } finally {
      setSearchLoading(false);
    }
  };

  const clearSearch = () => {
    setSearchQuery("");
    setSearchResult(null);
    setSearchError(null);
  };

  return (
    <div className="space-y-8 animate-fade-in pb-12">
      
      {/* 1. Header & Large Headline Sentence (§11) */}
      <div className="space-y-3">
        <p className="text-xs font-semibold uppercase tracking-wider text-slate-400">
          Warehouse Inventory Overview
        </p>
        
        <div className="flex flex-wrap items-baseline gap-3">
          <h1 className="text-3xl sm:text-4xl font-bold tracking-tight text-slate-900">
            {loading ? "..." : `${summary?.tracked_items_on_shelves.toLocaleString()} items tracked on the shelves`}
          </h1>
          <span className="text-xs font-medium text-slate-500 bg-slate-100 px-3 py-1 rounded-full border border-slate-200">
            received since go-live: {summary?.received_since_golive.toLocaleString() || 0}
          </span>
        </div>

        {/* Movement Pills */}
        <div className="flex flex-wrap items-center gap-2 pt-1">
          <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200">
            <ArrowDownRight size={13} className="text-emerald-600" />
            {summary?.inward_today || 0} in today
          </span>
          <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-amber-50 text-amber-700 border border-amber-200">
            <ArrowUpRight size={13} className="text-amber-600" />
            {summary?.outward_today || 0} out today
          </span>
          <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-slate-100 text-slate-600 border border-slate-200">
            {summary?.recorded_only_today || 0} recorded only
          </span>
        </div>
      </div>

      {/* 2. Large Rounded Search Bar with Scan Icon (§11) */}
      <div className="space-y-4">
        <form onSubmit={handleSearch} className="relative max-w-3xl">
          <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none text-slate-400">
            <Barcode size={20} />
          </div>
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Scan barcode or enter serial number (e.g. SMTV004512)..."
            className="w-full pl-12 pr-28 py-3.5 text-sm rounded-2xl border border-slate-200/90 bg-white shadow-sm focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] transition-all text-slate-800 placeholder-slate-400"
          />
          <div className="absolute inset-y-0 right-0 pr-2 flex items-center gap-1">
            {searchQuery && (
              <button
                type="button"
                onClick={clearSearch}
                className="p-1.5 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-100 transition-colors"
              >
                <X size={16} />
              </button>
            )}
            <button
              type="submit"
              disabled={searchLoading || !searchQuery.trim()}
              className="px-4 py-2 rounded-xl bg-[#3C3489] text-white text-xs font-medium hover:bg-[#312B72] transition-colors disabled:opacity-50 cursor-pointer"
            >
              {searchLoading ? "Searching..." : "Search"}
            </button>
          </div>
        </form>

        {/* Search Result Card (§11) */}
        {searchError && (
          <div className="max-w-3xl p-4 bg-white border border-rose-200 rounded-2xl shadow-sm flex items-center gap-3 text-rose-700 text-xs">
            <AlertCircle size={16} className="text-rose-500 shrink-0" />
            <span>{searchError}</span>
          </div>
        )}

        {searchResult && (
          <div className="max-w-3xl bg-white border border-slate-200 rounded-2xl p-5 shadow-sm space-y-4 animate-fade-in">
            <div className="flex items-start justify-between gap-4">
              <div>
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-mono font-bold text-base text-slate-900">
                    {searchResult.serial_number}
                  </span>
                  {searchResult.unit_type && (
                    <span className={`text-xs font-semibold ${
                      searchResult.unit_type.toLowerCase() === 'indoor' ? 'text-indigo-600' : 'text-teal-600'
                    }`}>
                      ({searchResult.unit_type.charAt(0).toUpperCase() + searchResult.unit_type.slice(1).toLowerCase()})
                    </span>
                  )}
                  <Badge label={searchResult.status_label} />
                  <Badge 
                    label={searchResult.is_tracked ? "Matched" : "Recorded only"} 
                    variant={searchResult.is_tracked ? "matched" : "unmatched"} 
                  />
                </div>
                <p className="text-sm font-medium text-slate-700 mt-1">
                  {searchResult.product_name}
                </p>
                <p className="text-xs text-slate-400">
                  {searchResult.brand} • {searchResult.model}
                </p>
              </div>

              {searchResult.last_shop_name && (
                <div className="text-right">
                  <span className="text-[11px] uppercase font-semibold text-slate-400 block">Dispatched To</span>
                  <span className="text-xs font-medium text-slate-800 flex items-center gap-1 mt-0.5 justify-end">
                    <Building2 size={13} className="text-slate-400" />
                    {searchResult.last_shop_name} ({searchResult.last_shop_city})
                  </span>
                </div>
              )}
            </div>

            {/* Vertical History List (§11) */}
            <div className="border-t border-slate-100 pt-3">
              <span className="text-[11px] uppercase tracking-wider font-semibold text-slate-400 block mb-2.5">
                Serial History Timeline
              </span>
              <div className="space-y-2 max-h-48 overflow-y-auto pr-2">
                {searchResult.history.map((h) => (
                  <div key={h.id} className="flex items-start justify-between text-xs py-1 border-b border-slate-50 last:border-0">
                    <div className="space-y-0.5">
                      <div className="flex items-center gap-2">
                        <span className="font-medium text-slate-800 capitalize">
                          {h.action.replace(/_/g, " ")}
                        </span>
                        {h.shop_name && (
                          <span className="text-slate-500">→ {h.shop_name}</span>
                        )}
                      </div>
                      {h.remarks && <p className="text-[11px] text-slate-500">{h.remarks}</p>}
                    </div>
                    <div className="text-right shrink-0 text-slate-400 text-[11px]">
                      <div>{new Date(h.created_at).toLocaleDateString("en-IN", { month: "short", day: "numeric", year: "numeric" })}</div>
                      <div className="text-[10px] text-slate-400">{h.user_name}</div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>

      {/* 3. Main Area in Two Columns (§11) */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
        
        {/* Left Column: Stock by Model (7 cols) */}
        <div className="lg:col-span-7 bg-white border border-slate-200 rounded-2xl p-6 shadow-sm space-y-5">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-bold uppercase tracking-wider text-slate-600 flex items-center gap-2">
              <Layers size={16} className="text-[#3C3489]" />
              Stock by Model
            </h2>
            <span className="text-xs text-slate-400 font-medium">
              {stockByModel.length} product model{stockByModel.length > 1 ? "s" : ""}
            </span>
          </div>

          <div className="divide-y divide-slate-100">
            {stockByModel.map((item) => {
              const total = Math.max(item.total_received, 1);
              const availPct = Math.round((item.available_count / total) * 100);
              const dispPct = Math.round((item.dispatched_count / total) * 100);
              const damPct = Math.round((item.damaged_count / total) * 100);

              return (
                <div key={item.product_id} className="py-4 first:pt-0 last:pb-0 space-y-2">
                  <div className="flex items-start justify-between gap-4">
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="font-semibold text-sm text-slate-900">{item.name}</span>
                        {item.out_of_stock_reminder && (
                          <span className="px-2 py-0.5 rounded-full text-[11px] font-semibold bg-amber-50 text-amber-800 border border-amber-200">
                            No tracked stock left
                          </span>
                        )}
                      </div>
                      <span className="text-xs text-slate-400">{item.brand} • {item.model}</span>
                    </div>

                    <div className="text-right">
                      <span className="text-sm font-bold text-slate-900 block leading-none">
                        {item.available_count} available
                      </span>
                      <span className="text-[11px] text-slate-400 mt-1 block">
                        of {item.total_received} received
                      </span>
                    </div>
                  </div>

                  {/* Thin Stacked Bar (Green / Amber / Red) */}
                  <div className="w-full h-1.5 bg-slate-100 rounded-full overflow-hidden flex">
                    <div style={{ width: `${availPct}%` }} className="bg-emerald-500 h-full transition-all duration-300" title={`Available: ${item.available_count}`} />
                    <div style={{ width: `${dispPct}%` }} className="bg-amber-400 h-full transition-all duration-300" title={`Dispatched: ${item.dispatched_count}`} />
                    <div style={{ width: `${damPct}%` }} className="bg-rose-500 h-full transition-all duration-300" title={`Damaged: ${item.damaged_count}`} />
                  </div>

                  {/* Small muted line where relevant */}
                  {item.unmatched_dispatched_count > 0 && (
                    <p className="text-[11px] text-slate-400">
                      {item.unmatched_dispatched_count} dispatched without inward record
                    </p>
                  )}
                </div>
              );
            })}
          </div>
        </div>

        {/* Right Column: Today Movements Timeline (5 cols) */}
        <div className="lg:col-span-5 bg-white border border-slate-200 rounded-2xl p-6 shadow-sm space-y-4 flex flex-col max-h-[640px]">
          <div className="flex items-center justify-between shrink-0 pb-1">
            <h2 className="text-sm font-bold uppercase tracking-wider text-slate-600 flex items-center gap-2">
              <Clock size={16} className="text-[#3C3489]" />
              Today Movements
            </h2>
            <span className="text-xs text-slate-400 font-medium">
              {timeline.length} event{timeline.length > 1 ? "s" : ""}
            </span>
          </div>

          {timeline.length === 0 ? (
            <div className="py-8 text-center text-xs text-slate-400">
              No movements recorded yet today.
            </div>
          ) : (
            <div className="overflow-y-auto flex-1 pr-3 -mr-2 pl-2">
              <div className="relative pl-6 space-y-4 py-1.5 before:absolute before:left-2 before:top-2 before:bottom-2 before:w-0.5 before:bg-slate-200">
                {timeline.map((event) => {
                  const dotColors = {
                    green: "bg-emerald-500 ring-emerald-100",
                    amber: "bg-amber-500 ring-amber-100",
                    red: "bg-rose-500 ring-rose-100",
                    indigo: "bg-[#3C3489] ring-[#EEF2FF]",
                  }[event.dot_color];

                  return (
                    <div key={event.id} className="relative group text-xs">
                      {/* Timeline Dot */}
                      <div className={`absolute -left-6 top-1 w-2.5 h-2.5 rounded-full ring-4 ${dotColors}`} />
                      
                      <div className="space-y-0.5">
                        <p className="text-slate-800 font-medium leading-snug">
                          {event.description}
                        </p>
                        <div className="flex items-center gap-2 text-[11px] text-slate-400">
                          <span>{new Date(event.timestamp).toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" })}</span>
                          <span>•</span>
                          <span>{event.user_name}</span>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </div>

      </div>

      {/* 4. Bottom Needs Attention Strip (§11) */}
      <NeedsAttentionStrip data={summary?.needs_attention} />

    </div>
  );
};