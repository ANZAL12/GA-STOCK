import React, { useState } from "react";
import { NavLink, useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import {
  Boxes,
  Layers,
  Barcode,
  Store,
  Receipt,
  FileText,
  Users,
  Smartphone,
  LogOut,
  FileSpreadsheet,
  Settings,
  DatabaseBackup,
  Menu,
  X,
} from "lucide-react";

import logoImg from "../assets/GLOBAL2.png";

export const Navbar: React.FC = () => {
  const { user, logout, isAdmin } = useAuth();
  const navigate = useNavigate();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  const handleLogout = () => {
    logout();
    navigate("/login");
  };

  const navItems = [
    { label: "Overview", path: "/", icon: Boxes },
    { label: "Stock", path: "/stock", icon: Layers },
    { label: "Serials", path: "/serials", icon: Barcode },
    { label: "Shops", path: "/shops", icon: Store },
    { label: "Bills", path: "/bills", icon: Receipt },
    { label: "Reports", path: "/reports", icon: FileText },
    ...(isAdmin ? [{ label: "Import Serials", path: "/import-serials", icon: FileSpreadsheet }] : []),
    ...(isAdmin ? [{ label: "Users", path: "/users", icon: Users }] : []),
    ...(isAdmin ? [{ label: "Devices", path: "/devices", icon: Smartphone }] : []),
    ...(isAdmin ? [{ label: "Settings", path: "/settings", icon: Settings }] : []),
    ...(isAdmin ? [{ label: "Backup", path: "/backup", icon: DatabaseBackup }] : []),
  ];

  return (
    <header className="sticky top-0 z-40 bg-white/85 backdrop-blur-md border-b border-slate-200">
      <div className="w-full max-w-[1720px] mx-auto px-3 sm:px-5 lg:px-6 h-16 flex items-center justify-between gap-3">
        {/* Brand Logo */}
        <div className="flex items-center gap-2.5 shrink-0">
          <img
            src={logoImg}
            alt="Global Logistics Emblem"
            className="w-9 h-9 object-contain shrink-0"
          />
          <div className="whitespace-nowrap">
            <span className="font-extrabold text-sm xl:text-base tracking-tight text-slate-900 block leading-none">
              GLOBAL LOGISTICS
            </span>
            <span className="text-[9px] xl:text-[10px] font-semibold text-slate-500 uppercase tracking-wider block mt-1">
              Warehouse Management System
            </span>
          </div>
        </div>

        {/* Centered Pill Navigation */}
        <nav className="hidden md:flex items-center gap-0.5 bg-slate-100/80 p-1 rounded-full border border-slate-200/80 min-w-0 max-w-fit overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          {navItems.map((item) => {
            const Icon = item.icon;
            return (
              <NavLink
                key={item.path}
                to={item.path}
                end={item.path === "/"}
                className={({ isActive }) =>
                  `flex items-center gap-1.5 px-2.5 2xl:px-3.5 py-1.5 rounded-full text-[11.5px] xl:text-xs font-medium whitespace-nowrap shrink-0 transition-all duration-150 ${
                    isActive
                      ? "bg-[#3C3489] text-white shadow-sm shadow-[#3C3489]/25"
                      : "text-slate-600 hover:text-slate-900 hover:bg-slate-200/60"
                  }`
                }
              >
                <Icon size={13} className="opacity-90 shrink-0" />
                {item.label}
              </NavLink>
            );
          })}
        </nav>

        {/* Right User Avatar & Controls */}
        <div className="flex items-center gap-2 shrink-0">
          <div className="flex items-center gap-2 px-2.5 py-1.5 rounded-full bg-slate-100 border border-slate-200 text-xs text-slate-700">
            <div className="w-5 h-5 rounded-full bg-[#EEF2FF] text-[#3C3489] flex items-center justify-center font-medium text-[10px] shrink-0">
              {user?.full_name ? user.full_name[0].toUpperCase() : "U"}
            </div>
            <span className="hidden sm:inline font-medium max-w-[90px] 2xl:max-w-[140px] truncate">
              {user?.full_name || user?.username}
            </span>
            <span className="px-1.5 py-0.5 rounded text-[10px] font-semibold bg-white text-slate-500 border border-slate-200 uppercase tracking-wider shrink-0">
              {user?.role}
            </span>
          </div>

          <button
            onClick={handleLogout}
            title="Log Out"
            className="p-2 rounded-xl text-slate-500 hover:text-rose-600 hover:bg-rose-50 transition-colors cursor-pointer"
          >
            <LogOut size={16} />
          </button>

          <button
            type="button"
            onClick={() => setMobileMenuOpen((v) => !v)}
            aria-label="Toggle navigation menu"
            className="md:hidden p-2 rounded-xl text-slate-600 hover:text-slate-900 hover:bg-slate-100 transition-colors cursor-pointer"
          >
            {mobileMenuOpen ? <X size={18} /> : <Menu size={18} />}
          </button>
        </div>
      </div>

      {/* Mobile Navigation Drawer */}
      {mobileMenuOpen && (
        <nav className="md:hidden border-t border-slate-200 bg-white px-4 py-3 grid grid-cols-2 gap-1.5">
          {navItems.map((item) => {
            const Icon = item.icon;
            return (
              <NavLink
                key={item.path}
                to={item.path}
                end={item.path === "/"}
                onClick={() => setMobileMenuOpen(false)}
                className={({ isActive }) =>
                  `flex items-center gap-2 px-3 py-2 rounded-xl text-xs font-medium whitespace-nowrap transition-colors ${
                    isActive
                      ? "bg-[#3C3489] text-white"
                      : "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
                  }`
                }
              >
                <Icon size={14} className="shrink-0" />
                <span className="truncate">{item.label}</span>
              </NavLink>
            );
          })}
        </nav>
      )}
    </header>
  );
};
