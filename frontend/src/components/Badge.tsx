import React from "react";

interface BadgeProps {
  label?: string;
  children?: React.ReactNode;
  variant?:
    | "matched"
    | "unmatched"
    | "warning"
    | "error"
    | "indigo"
    | "default"
    | "green"
    | "blue"
    | "grey"
    | "red"
    | "amber";
  size?: "sm" | "md";
}

export const Badge: React.FC<BadgeProps> = ({ label, children, variant, size = "md" }) => {
  const text = label || (typeof children === "string" ? children : "");
  const norm = text.toLowerCase();

  let style = "bg-slate-100 text-slate-700 border-slate-200";

  if (
    variant === "matched" ||
    variant === "green" ||
    variant === "blue" ||
    norm.includes("matched") ||
    norm === "available" ||
    norm === "active" ||
    norm === "approved" ||
    norm === "in stock" ||
    norm.includes("staff")
  ) {
    style = "bg-emerald-50 text-emerald-700 border-emerald-200";
  } else if (
    variant === "unmatched" ||
    variant === "grey" ||
    norm.includes("recorded only") ||
    norm.includes("unmatched")
  ) {
    style = "bg-slate-100 text-slate-600 border-slate-300";
  } else if (
    variant === "warning" ||
    variant === "amber" ||
    norm.includes("warning") ||
    norm.includes("flagged") ||
    norm === "dispatched" ||
    norm.includes("repair")
  ) {
    style = "bg-amber-50 text-amber-700 border-amber-200";
  } else if (
    variant === "error" ||
    variant === "red" ||
    norm === "damaged" ||
    norm === "lost" ||
    norm === "deactivated"
  ) {
    style = "bg-rose-50 text-rose-700 border-rose-200";
  } else if (
    variant === "indigo" ||
    norm === "returned" ||
    norm.includes("admin")
  ) {
    style = "bg-[#EEF2FF] text-[#3C3489] border-[#C7D2FE]";
  }

  const sizeClasses = size === "sm" ? "px-2 py-0.5 text-[11px]" : "px-2.5 py-1 text-xs";

  return (
    <span
      className={`inline-flex items-center font-medium rounded-full border tracking-wide whitespace-nowrap transition-colors ${sizeClasses} ${style}`}
    >
      {label}
    </span>
  );
};