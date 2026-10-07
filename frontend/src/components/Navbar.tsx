import React from "react";
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
  LogOut
} from "lucide-react";

import logoImg from "../assets/Global Logistics Warehouse Emblem.png";

export const Navbar: React.FC = () => {
  const { user, logout, isAdmin } = useAuth();
  const navigate = useNavigate();

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
    ...(isAdmin ? [{ label: "Users", path: "/users", icon: Users }] : []),
    ...(isAdmin ? [{ label: "Devices", path: "/devices", icon: Smartphone }] : []),
  ];

  return (
    <header className="sticky top-0 z-40 bg-white/80 backdrop-blur-md border-b border-slate-200">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
        
        {/* Brand Logo */}
        <div className="flex items-center gap-3">
          <img
            src={logoImg}
            alt="Global Logistics Emblem"
            className="w-12 h-12 object-contain drop-shadow-sm shrink-0"
          />
          <div>
            <span className="font-extrabold text-base tracking-tight text-slate-900 block leading-none">
              GLOBAL LOGISTICS
            </span>
            <span className="text-[10px] font-semibold text-slate-500 uppercase tracking-wider block mt-1">
              Warehouse Management System
            </span>
          </div>
        </div>

        {/* Centered Pill Navigation */}
        <nav className="hidden md:flex items-center gap-1 bg-slate-100/80 p-1.5 rounded-full border border-slate-200/80">
          {navItems.map((item) => {
            const Icon = item.icon;
            return (
              <NavLink
                key={item.path}
                to={item.path}
                end={item.path === "/"}
                className={({ isActive }) =>
                  `flex items-center gap-1.5 px-3.5 py-1.5 rounded-full text-xs font-medium transition-all duration-150 ${
                    isActive
                      ? "bg-[#3C3489] text-white shadow-sm shadow-[#3C3489]/25"
                      : "text-slate-600 hover:text-slate-900 hover:bg-slate-200/60"
                  }`
                }
              >
                <Icon size={14} className="opacity-90" />
                {item.label}
              </NavLink>
            );
          })}
        </nav>

        {/* Right User Avatar & Controls */}
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-slate-100 border border-slate-200 text-xs text-slate-700">
            <div className="w-5 h-5 rounded-full bg-[#EEF2FF] text-[#3C3489] flex items-center justify-center font-medium text-[10px]">
              {user?.full_name ? user.full_name[0].toUpperCase() : "U"}
            </div>
            <span className="font-medium max-w-[120px] truncate">{user?.full_name || user?.username}</span>
            <span className="px-1.5 py-0.5 rounded text-[10px] font-semibold bg-white text-slate-500 border border-slate-200 uppercase tracking-wider">
              {user?.role}
            </span>
          </div>

          <button
            onClick={handleLogout}
            title="Log Out"
            className="p-2 rounded-xl text-slate-500 hover:text-rose-600 hover:bg-rose-50 transition-colors"
          >
            <LogOut size={16} />
          </button>
        </div>

      </div>
    </header>
  );
};