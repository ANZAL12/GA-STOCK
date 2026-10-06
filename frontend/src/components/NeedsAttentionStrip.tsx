import React from "react";
import { Link } from "react-router-dom";
import type { NeedsAttentionPills } from "../types";
import { 
  AlertTriangle, 
  CheckCircle2, 
  Flag, 
  Wrench, 
  Smartphone, 
  ArchiveX 
} from "lucide-react";

interface Props {
  data?: NeedsAttentionPills;
}

export const NeedsAttentionStrip: React.FC<Props> = ({ data }) => {
  if (!data) return null;

  if (data.all_clear) {
    return (
      <div className="bg-white border border-slate-200 rounded-2xl p-4 shadow-sm flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <span className="text-xs font-semibold uppercase tracking-wider text-slate-400">Status</span>
          <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium bg-emerald-50 text-emerald-700 border border-emerald-200">
            <CheckCircle2 size={13} className="text-emerald-600" />
            All clear — no items need attention
          </span>
        </div>
        <span className="text-xs text-slate-400">Everything in order</span>
      </div>
    );
  }

  return (
    <div className="bg-white border border-slate-200 rounded-2xl p-4 shadow-sm flex flex-wrap items-center justify-between gap-3">
      <div className="flex items-center gap-2">
        <div className="w-2 h-2 rounded-full bg-amber-500 animate-pulse" />
        <span className="text-xs font-semibold uppercase tracking-wider text-slate-500">
          Needs Attention
        </span>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        {data.out_of_stock_models > 0 && (
          <Link
            to="/stock?filter=oos"
            className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium bg-amber-50 text-amber-800 border border-amber-200 hover:bg-amber-100 transition-colors"
          >
            <ArchiveX size={13} className="text-amber-600" />
            <span>{data.out_of_stock_models} model{data.out_of_stock_models > 1 ? "s" : ""} out of stock</span>
          </Link>
        )}

        {data.flagged_outward_reviews > 0 && (
          <Link
            to="/reports?tab=stock-out&filter=flagged"
            className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium bg-amber-50 text-amber-800 border border-amber-200 hover:bg-amber-100 transition-colors"
          >
            <Flag size={13} className="text-amber-600" />
            <span>{data.flagged_outward_reviews} dispatch{data.flagged_outward_reviews > 1 ? "es" : ""} flagged for review</span>
          </Link>
        )}

        {data.damaged_units > 0 && (
          <Link
            to="/reports?tab=damaged"
            className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium bg-rose-50 text-rose-800 border border-rose-200 hover:bg-rose-100 transition-colors"
          >
            <AlertTriangle size={13} className="text-rose-600" />
            <span>{data.damaged_units} damaged unit{data.damaged_units > 1 ? "s" : ""}</span>
          </Link>
        )}

        {data.under_repair_units > 0 && (
          <Link
            to="/reports?tab=damaged"
            className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium bg-indigo-50 text-indigo-800 border border-indigo-200 hover:bg-indigo-100 transition-colors"
          >
            <Wrench size={13} className="text-indigo-600" />
            <span>{data.under_repair_units} under repair</span>
          </Link>
        )}

        {data.pending_devices > 0 && (
          <Link
            to="/devices"
            className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium bg-purple-50 text-purple-800 border border-purple-200 hover:bg-purple-100 transition-colors"
          >
            <Smartphone size={13} className="text-purple-600" />
            <span>{data.pending_devices} phone{data.pending_devices > 1 ? "s" : ""} awaiting approval</span>
          </Link>
        )}
      </div>
    </div>
  );
};