import React, { useEffect, useState } from "react";
import { apiRequest } from "../api/client";
import { useAuth } from "../context/AuthContext";
import type { Shop, ShopDispatchedSerial } from "../types";
import { Badge } from "../components/Badge";
import { Modal } from "../components/Modal";
import { 
  Plus, 
  Search, 
  MapPin, 
  Phone, 
  Edit2, 
  Archive, 
  AlertCircle,
  ChevronRight
} from "lucide-react";

export const ShopsPage: React.FC = () => {
  const { isAdmin } = useAuth();
  const [shops, setShops] = useState<Shop[]>([]);
  const [search, setSearch] = useState("");
  

  // Shop Add / Edit Modal
  const [isShopModalOpen, setIsShopModalOpen] = useState(false);
  const [editingShop, setEditingShop] = useState<Shop | null>(null);
  const [shopForm, setShopForm] = useState({ name: "", city: "", phone: "" });
  const [shopFormError, setShopFormError] = useState<string | null>(null);
  const [shopSubmitting, setShopSubmitting] = useState(false);

  // Dispatched Serials Drawer / Modal
  const [selectedShop, setSelectedShop] = useState<Shop | null>(null);
  const [dispatchedSerials, setDispatchedSerials] = useState<ShopDispatchedSerial[]>([]);
  const [serialsLoading, setSerialsLoading] = useState(false);

  const fetchShops = async () => {
    try {
      const data = await apiRequest<Shop[]>("/shops?active_only=false");
      setShops(data);
    } catch (e) {
      console.error(e);
    } finally {
      
    }
  };

  useEffect(() => {
    fetchShops();
  }, []);

  const openAddShop = () => {
    setEditingShop(null);
    setShopForm({ name: "", city: "", phone: "" });
    setShopFormError(null);
    setIsShopModalOpen(true);
  };

  const openEditShop = (s: Shop, e: React.MouseEvent) => {
    e.stopPropagation();
    setEditingShop(s);
    setShopForm({ name: s.name, city: s.city, phone: s.phone || "" });
    setShopFormError(null);
    setIsShopModalOpen(true);
  };

  const handleShopSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setShopSubmitting(true);
    setShopFormError(null);

    try {
      if (editingShop) {
        await apiRequest(`/shops/${editingShop.id}`, {
          method: "PUT",
          body: JSON.stringify(shopForm),
        });
      } else {
        await apiRequest("/shops", {
          method: "POST",
          body: JSON.stringify(shopForm),
        });
      }
      setIsShopModalOpen(false);
      fetchShops();
    } catch (err: any) {
      setShopFormError(err.message || "Failed to save shop.");
    } finally {
      setShopSubmitting(false);
    }
  };

  const handleDeactivate = async (s: Shop, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!window.confirm(`Deactivate '${s.name}'? Shops with dispatch history are soft-deactivated to preserve reports.`)) {
      return;
    }
    try {
      await apiRequest(`/shops/${s.id}`, { method: "DELETE" });
      fetchShops();
    } catch (err: any) {
      alert(err.message || "Failed to deactivate shop.");
    }
  };

  const openDispatchedSerials = async (s: Shop) => {
    setSelectedShop(s);
    setSerialsLoading(true);
    try {
      const serials = await apiRequest<ShopDispatchedSerial[]>(`/shops/${s.id}/dispatched-serials`);
      setDispatchedSerials(serials);
    } catch (err) {
      console.error(err);
    } finally {
      setSerialsLoading(false);
    }
  };

  const filtered = shops.filter(
    (s) =>
      s.name.toLowerCase().includes(search.toLowerCase()) ||
      s.city.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <div className="space-y-6 animate-fade-in pb-12">
      
      {/* Title & Actions */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            Destination Shops
          </h1>
          <p className="text-xs text-slate-500 font-medium mt-0.5">
            Registered retail shops for outward stock dispatch • View full delivery logs
          </p>
        </div>

        {isAdmin && (
          <button
            onClick={openAddShop}
            className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-[#3C3489] text-white text-xs font-semibold hover:bg-[#312B72] shadow-sm shadow-[#3C3489]/25 transition-all cursor-pointer self-start sm:self-auto"
          >
            <Plus size={16} />
            <span>Add Destination Shop</span>
          </button>
        )}
      </div>

      {/* Search Input */}
      <div className="relative max-w-sm">
        <Search size={15} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" />
        <input
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search by shop name or city..."
          className="w-full pl-9 pr-4 py-2 text-xs rounded-xl border border-slate-200 bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] text-slate-800 placeholder-slate-400"
        />
      </div>

      {/* Shops Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
        {filtered.map((shop) => (
          <div
            key={shop.id}
            onClick={() => openDispatchedSerials(shop)}
            className="bg-white border border-slate-200 hover:border-slate-300 rounded-2xl p-5 shadow-sm space-y-4 cursor-pointer transition-all hover:shadow-md flex flex-col justify-between group"
          >
            <div className="space-y-2">
              <div className="flex items-start justify-between gap-3">
                <span className="text-[11px] font-semibold text-slate-600 bg-slate-100 px-2.5 py-0.5 rounded-full flex items-center gap-1">
                  <MapPin size={11} className="text-slate-400" />
                  {shop.city}
                </span>

                {!shop.is_active && (
                  <span className="text-[11px] font-semibold text-rose-700 bg-rose-50 border border-rose-200 px-2 py-0.5 rounded-full">
                    Deactivated
                  </span>
                )}
              </div>

              <div>
                <h3 className="font-bold text-base text-slate-900 tracking-tight group-hover:text-[#3C3489] transition-colors">
                  {shop.name}
                </h3>
                {shop.phone ? (
                  <p className="text-xs text-slate-400 flex items-center gap-1 mt-1">
                    <Phone size={12} />
                    {shop.phone}
                  </p>
                ) : (
                  <p className="text-xs text-slate-400 mt-1">No phone recorded</p>
                )}
              </div>
            </div>

            <div className="border-t border-slate-100 pt-3 flex items-center justify-between">
              <div>
                <span className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider block">
                  Dispatched
                </span>
                <span className="text-sm font-bold text-slate-900">
                  {shop.total_dispatched_count} item{shop.total_dispatched_count === 1 ? "" : "s"}
                </span>
              </div>

              <div className="flex items-center gap-1">
                {isAdmin && (
                  <>
                    <button
                      onClick={(e) => openEditShop(shop, e)}
                      className="p-1.5 rounded-lg text-slate-400 hover:text-slate-700 hover:bg-slate-100 transition-colors"
                      title="Edit Shop"
                    >
                      <Edit2 size={14} />
                    </button>
                    {shop.is_active && (
                      <button
                        onClick={(e) => handleDeactivate(shop, e)}
                        className="p-1.5 rounded-lg text-slate-400 hover:text-rose-600 hover:bg-rose-50 transition-colors"
                        title="Deactivate Shop"
                      >
                        <Archive size={14} />
                      </button>
                    )}
                  </>
                )}
                <div className="p-1.5 text-slate-400 group-hover:text-[#3C3489] transition-colors">
                  <ChevronRight size={16} />
                </div>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Dispatched Serials Drawer / Modal (§11) */}
      <Modal
        isOpen={Boolean(selectedShop)}
        onClose={() => setSelectedShop(null)}
        title={selectedShop ? `Dispatched Serials • ${selectedShop.name}` : ""}
        subtitle={selectedShop ? `${selectedShop.city} • ${dispatchedSerials.length} total units dispatched` : ""}
        maxWidth="2xl"
      >
        {serialsLoading ? (
          <div className="py-12 text-center text-xs text-slate-400">
            <div className="w-6 h-6 border-2 border-[#3C3489] border-t-transparent rounded-full animate-spin mx-auto mb-2" />
            Loading dispatched history...
          </div>
        ) : dispatchedSerials.length === 0 ? (
          <div className="py-10 text-center text-xs text-slate-400">
            No serials have been dispatched to this shop yet.
          </div>
        ) : (
          <div className="space-y-2 max-h-[60vh] overflow-y-auto pr-2">
            <div className="divide-y divide-slate-100">
              {dispatchedSerials.map((s, idx) => (
                <div key={idx} className="py-3 flex items-start justify-between gap-4 text-xs">
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-mono font-bold text-slate-900">{s.serial_text}</span>
                      <Badge label={s.status_label} />
                    </div>
                    <p className="font-medium text-slate-700 mt-0.5">{s.product_name}</p>
                    <p className="text-[11px] text-slate-400">{s.brand} • {s.model}</p>
                  </div>

                  <div className="text-right shrink-0 text-slate-400">
                    <div>{new Date(s.transaction_date).toLocaleDateString("en-IN", { month: "short", day: "numeric", year: "numeric" })}</div>
                    {s.delivery_reference && (
                      <div className="text-[11px] text-slate-500 font-mono mt-0.5">Ref: {s.delivery_reference}</div>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </Modal>

      {/* Shop Add / Edit Modal */}
      <Modal
        isOpen={isShopModalOpen}
        onClose={() => setIsShopModalOpen(false)}
        title={editingShop ? "Edit Destination Shop" : "Add Destination Shop"}
        subtitle="Manage dispatch locations"
        maxWidth="md"
      >
        {shopFormError && (
          <div className="mb-4 p-3 rounded-xl bg-rose-50 border border-rose-200 text-rose-700 text-xs flex items-center gap-2">
            <AlertCircle size={15} />
            <span>{shopFormError}</span>
          </div>
        )}

        <form onSubmit={handleShopSubmit} className="space-y-4">
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
              Shop Name *
            </label>
            <input
              type="text"
              required
              value={shopForm.name}
              onChange={(e) => setShopForm({ ...shopForm, name: e.target.value })}
              placeholder="e.g. Sree Electronics"
              className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
              City / Location *
            </label>
            <input
              type="text"
              required
              value={shopForm.city}
              onChange={(e) => setShopForm({ ...shopForm, city: e.target.value })}
              placeholder="e.g. Malappuram"
              className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
              Phone Number
            </label>
            <input
              type="text"
              value={shopForm.phone}
              onChange={(e) => setShopForm({ ...shopForm, phone: e.target.value })}
              placeholder="e.g. +91 98470 12345"
              className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
            />
          </div>

          <div className="pt-3 border-t border-slate-100 flex items-center justify-end gap-2">
            <button
              type="button"
              onClick={() => setIsShopModalOpen(false)}
              className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl transition-colors cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={shopSubmitting}
              className="px-4 py-2 text-xs font-semibold text-white bg-[#3C3489] hover:bg-[#312B72] rounded-xl shadow-sm transition-colors cursor-pointer disabled:opacity-50"
            >
              {shopSubmitting ? "Saving..." : "Save Shop"}
            </button>
          </div>
        </form>
      </Modal>

    </div>
  );
};