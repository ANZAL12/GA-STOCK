import React, { useEffect, useState } from "react";
import { apiRequest } from "../api/client";
import { useWebSocket } from "../api/useWebSocket";
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
  Trash2,
  RotateCcw,
  AlertCircle,
  ChevronRight,
  Sparkles
} from "lucide-react";

export const ShopsPage: React.FC = () => {
  const { isAdmin } = useAuth();
  const [shops, setShops] = useState<Shop[]>([]);
  const [search, setSearch] = useState("");
  const [filterStatus, setFilterStatus] = useState<"all" | "active" | "deactivated">("all");
  const [cleaningUp, setCleaningUp] = useState(false);

  // Shop Add / Edit Modal
  const [isShopModalOpen, setIsShopModalOpen] = useState(false);
  const [editingShop, setEditingShop] = useState<Shop | null>(null);
  const [shopForm, setShopForm] = useState({ name: "", city: "", phone: "", is_active: true });
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
    }
  };

  useEffect(() => {
    fetchShops();
  }, []);

  useWebSocket((event) => {
    if (event === "shop_created" || event === "shop_updated" || event === "shop_deleted") {
      fetchShops();
    }
  });

  const openAddShop = () => {
    setEditingShop(null);
    setShopForm({ name: "", city: "", phone: "", is_active: true });
    setShopFormError(null);
    setIsShopModalOpen(true);
  };

  const openEditShop = (s: Shop, e: React.MouseEvent) => {
    e.stopPropagation();
    setEditingShop(s);
    setShopForm({ name: s.name, city: s.city, phone: s.phone || "", is_active: s.is_active });
    setShopFormError(null);
    setIsShopModalOpen(true);
  };

  const handleShopSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setShopSubmitting(true);
    setShopFormError(null);

    try {
      if (editingShop) {
        const updated = await apiRequest<Shop>(`/shops/${editingShop.id}`, {
          method: "PUT",
          body: JSON.stringify(shopForm),
        });
        setShops((prev) => prev.map((s) => (s.id === updated.id ? updated : s)));
      } else {
        const created = await apiRequest<Shop>("/shops", {
          method: "POST",
          body: JSON.stringify({
            name: shopForm.name,
            city: shopForm.city,
            phone: shopForm.phone,
          }),
        });
        setShops((prev) => [created, ...prev.filter((s) => s.id !== created.id)]);
      }
      setIsShopModalOpen(false);
      await fetchShops();
    } catch (err: any) {
      setShopFormError(err.message || "Failed to save shop.");
    } finally {
      setShopSubmitting(false);
    }
  };

  // Toggle Activate / Deactivate
  const handleToggleActive = async (s: Shop, e: React.MouseEvent) => {
    e.stopPropagation();
    const actionLabel = s.is_active ? "Deactivate" : "Reactivate";
    const confirmMsg = s.is_active
      ? `Deactivate '${s.name}'? Staff will not see it on mobile scanner dispatch lists.`
      : `Reactivate '${s.name}'? It will immediately appear on mobile scanner dispatch lists.`;

    if (!window.confirm(confirmMsg)) return;

    try {
      await apiRequest(`/shops/${s.id}/toggle-active`, { method: "PATCH" });
      await fetchShops();
    } catch (err: any) {
      alert(err.message || `Failed to ${actionLabel.toLowerCase()} shop.`);
    }
  };

  // Permanent Delete
  const handleDelete = async (s: Shop, e: React.MouseEvent) => {
    e.stopPropagation();
    if (s.total_dispatched_count > 0) {
      alert(
        `Cannot permanently delete '${s.name}' because it has ${s.total_dispatched_count} recorded dispatch(es) in transaction history.\n\nPlease use the Deactivate button instead to hide it.`
      );
      return;
    }

    if (!window.confirm(`Permanently delete '${s.name}'? This cannot be undone.`)) {
      return;
    }

    try {
      await apiRequest(`/shops/${s.id}?permanent=true`, { method: "DELETE" });
      setShops((prev) => prev.filter((x) => x.id !== s.id));
      await fetchShops();
    } catch (err: any) {
      alert(err.message || "Failed to delete shop.");
    }
  };

  // Bulk Clean Unused Deactivated Shops
  const handleCleanupUnused = async () => {
    const unusedCount = shops.filter((s) => !s.is_active && s.total_dispatched_count === 0).length;
    if (unusedCount === 0) return;

    if (!window.confirm(`Clean up all ${unusedCount} deactivated test shop(s) with 0 dispatches?`)) {
      return;
    }

    setCleaningUp(true);
    try {
      const res: any = await apiRequest("/shops/cleanup/unused-deactivated", { method: "DELETE" });
      alert(res.message || "Cleanup completed successfully.");
      fetchShops();
    } catch (err: any) {
      alert(err.message || "Failed to clean up test shops.");
    } finally {
      setCleaningUp(false);
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

  const filtered = shops
    .filter((s) => {
      if (filterStatus === "active") return s.is_active;
      if (filterStatus === "deactivated") return !s.is_active;
      return true;
    })
    .filter(
      (s) =>
        s.name.toLowerCase().includes(search.toLowerCase()) ||
        s.city.toLowerCase().includes(search.toLowerCase())
    );

  const activeCount = shops.filter((s) => s.is_active).length;
  const deactivatedCount = shops.filter((s) => !s.is_active).length;
  const unusedDeactivatedCount = shops.filter((s) => !s.is_active && s.total_dispatched_count === 0).length;

  return (
    <div className="space-y-6 animate-fade-in pb-12">
      
      {/* Title & Actions */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            Destination Shops
          </h1>
          <p className="text-xs text-slate-500 font-medium mt-0.5">
            Registered retail shops for outward stock dispatch • Real-time status & delivery logs
          </p>
        </div>

        <div className="flex items-center gap-2 self-start sm:self-auto">
          {isAdmin && unusedDeactivatedCount > 0 && (
            <button
              onClick={handleCleanupUnused}
              disabled={cleaningUp}
              className="inline-flex items-center gap-1.5 px-3 py-2 rounded-xl bg-rose-50 text-rose-700 border border-rose-200 text-xs font-semibold hover:bg-rose-100 transition-all cursor-pointer disabled:opacity-50"
              title="Delete all deactivated test shops that have 0 dispatches"
            >
              <Sparkles size={14} className="text-rose-500" />
              <span>{cleaningUp ? "Cleaning..." : `Clean ${unusedDeactivatedCount} Test Shop${unusedDeactivatedCount > 1 ? "s" : ""}`}</span>
            </button>
          )}

          {isAdmin && (
            <button
              onClick={openAddShop}
              className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-[#3C3489] text-white text-xs font-semibold hover:bg-[#312B72] shadow-sm shadow-[#3C3489]/25 transition-all cursor-pointer"
            >
              <Plus size={16} />
              <span>Add Destination Shop</span>
            </button>
          )}
        </div>
      </div>

      {/* Filter Tabs & Search */}
      <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3">
        {/* Status Pills */}
        <div className="flex items-center gap-1 p-1 bg-slate-100 rounded-xl w-fit text-xs font-medium">
          <button
            onClick={() => setFilterStatus("all")}
            className={`px-3 py-1.5 rounded-lg transition-all cursor-pointer ${
              filterStatus === "all"
                ? "bg-white text-slate-900 font-semibold shadow-sm"
                : "text-slate-600 hover:text-slate-900"
            }`}
          >
            All Shops ({shops.length})
          </button>
          <button
            onClick={() => setFilterStatus("active")}
            className={`px-3 py-1.5 rounded-lg transition-all cursor-pointer flex items-center gap-1.5 ${
              filterStatus === "active"
                ? "bg-white text-emerald-700 font-semibold shadow-sm"
                : "text-slate-600 hover:text-slate-900"
            }`}
          >
            <span className="w-2 h-2 rounded-full bg-emerald-500 inline-block" />
            Active ({activeCount})
          </button>
          <button
            onClick={() => setFilterStatus("deactivated")}
            className={`px-3 py-1.5 rounded-lg transition-all cursor-pointer flex items-center gap-1.5 ${
              filterStatus === "deactivated"
                ? "bg-white text-rose-700 font-semibold shadow-sm"
                : "text-slate-600 hover:text-slate-900"
            }`}
          >
            <span className="w-2 h-2 rounded-full bg-rose-400 inline-block" />
            Deactivated ({deactivatedCount})
          </button>
        </div>

        {/* Search Input */}
        <div className="relative max-w-sm w-full sm:w-72">
          <Search size={15} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search by shop name or city..."
            className="w-full pl-9 pr-4 py-2 text-xs rounded-xl border border-slate-200 bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] text-slate-800 placeholder-slate-400"
          />
        </div>
      </div>

      {/* Shops Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
        {filtered.map((shop) => (
          <div
            key={shop.id}
            onClick={() => openDispatchedSerials(shop)}
            className={`bg-white border rounded-2xl p-5 shadow-sm space-y-4 cursor-pointer transition-all hover:shadow-md flex flex-col justify-between group ${
              shop.is_active ? "border-slate-200 hover:border-slate-300" : "border-slate-200/80 bg-slate-50/50 opacity-90"
            }`}
          >
            <div className="space-y-2">
              <div className="flex items-start justify-between gap-3">
                <span className="text-[11px] font-semibold text-slate-600 bg-slate-100 px-2.5 py-0.5 rounded-full flex items-center gap-1">
                  <MapPin size={11} className="text-slate-400" />
                  {shop.city}
                </span>

                {shop.is_active ? (
                  <span className="text-[11px] font-semibold text-emerald-700 bg-emerald-50 border border-emerald-200 px-2 py-0.5 rounded-full flex items-center gap-1">
                    <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
                    Active
                  </span>
                ) : (
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
                    {/* Edit */}
                    <button
                      onClick={(e) => openEditShop(shop, e)}
                      className="p-1.5 rounded-lg text-slate-400 hover:text-slate-700 hover:bg-slate-100 transition-colors cursor-pointer"
                      title="Edit Shop Details"
                    >
                      <Edit2 size={14} />
                    </button>

                    {/* Toggle Active / Deactivate */}
                    {shop.is_active ? (
                      <button
                        onClick={(e) => handleToggleActive(shop, e)}
                        className="p-1.5 rounded-lg text-slate-400 hover:text-amber-600 hover:bg-amber-50 transition-colors cursor-pointer"
                        title="Deactivate Shop (hide from scanner)"
                      >
                        <Archive size={14} />
                      </button>
                    ) : (
                      <button
                        onClick={(e) => handleToggleActive(shop, e)}
                        className="p-1.5 rounded-lg text-emerald-600 hover:text-emerald-700 hover:bg-emerald-50 transition-colors cursor-pointer"
                        title="Reactivate Shop"
                      >
                        <RotateCcw size={14} />
                      </button>
                    )}

                    {/* Permanent Delete */}
                    <button
                      onClick={(e) => handleDelete(shop, e)}
                      className="p-1.5 rounded-lg text-slate-400 hover:text-rose-600 hover:bg-rose-50 transition-colors cursor-pointer"
                      title={shop.total_dispatched_count === 0 ? "Permanently Delete Shop" : "Cannot delete shop with dispatch history"}
                    >
                      <Trash2 size={14} />
                    </button>
                  </>
                )}
                <div className="p-1.5 text-slate-400 group-hover:text-[#3C3489] transition-colors">
                  <ChevronRight size={16} />
                </div>
              </div>
            </div>
          </div>
        ))}

        {filtered.length === 0 && (
          <div className="col-span-full py-12 text-center text-xs text-slate-400 bg-white border border-slate-200 rounded-2xl">
            No shops found matching your filter or search query.
          </div>
        )}
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

          {editingShop && (
            <div className="pt-2">
              <label className="flex items-center gap-2.5 cursor-pointer p-2.5 rounded-xl border border-slate-200 bg-slate-50/50 hover:bg-slate-50 transition-colors">
                <input
                  type="checkbox"
                  checked={shopForm.is_active}
                  onChange={(e) => setShopForm({ ...shopForm, is_active: e.target.checked })}
                  className="rounded text-[#3C3489] focus:ring-[#3C3489] h-4 w-4 cursor-pointer"
                />
                <div>
                  <span className="text-xs font-semibold text-slate-800 block">
                    Shop is Active
                  </span>
                  <span className="text-[11px] text-slate-500 block">
                    Active shops appear on mobile scanners for outward dispatches.
                  </span>
                </div>
              </label>
            </div>
          )}

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