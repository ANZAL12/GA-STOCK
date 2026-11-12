import React, { useEffect, useState } from "react";
import { apiRequest } from "../api/client";
import { useWebSocket } from "../api/useWebSocket";
import { useAuth } from "../context/AuthContext";
import type { Shop, ShopDispatchedSerial } from "../types";
import { Badge } from "../components/Badge";
import { Modal } from "../components/Modal";
import { 
  Search, 
  MapPin, 
  Phone, 
  Edit2, 
  Archive, 
  Trash2, 
  RotateCcw, 
  AlertCircle, 
  ChevronRight, 
  Sparkles, 
  Copy, 
  Check, 
  Mail, 
  User as UserIcon
} from "lucide-react";

export const ShopsPage: React.FC = () => {
  const { isAdmin } = useAuth();
  const [shops, setShops] = useState<Shop[]>([]);
  const [search, setSearch] = useState("");
  const [filterStatus, setFilterStatus] = useState<"all" | "active" | "deactivated">("all");
  const [cleaningUp, setCleaningUp] = useState(false);

  // Shop Edit Modal (for existing shops)
  const [isShopModalOpen, setIsShopModalOpen] = useState(false);
  const [editingShop, setEditingShop] = useState<Shop | null>(null);
  const [shopForm, setShopForm] = useState({
    name: "",
    city: "",
    phone: "",
    gstin: "",
    address: "",
    state: "",
    pincode: "",
    contact_person: "",
    email: "",
    is_active: true,
  });
  const [shopFormError, setShopFormError] = useState<string | null>(null);
  const [shopSubmitting, setShopSubmitting] = useState(false);

  // Complete Shop Details & Dispatched Serials Modal
  const [selectedShop, setSelectedShop] = useState<Shop | null>(null);
  const [dispatchedSerials, setDispatchedSerials] = useState<ShopDispatchedSerial[]>([]);
  const [serialsLoading, setSerialsLoading] = useState(false);
  const [copiedGstin, setCopiedGstin] = useState(false);
  const [copiedPhone, setCopiedPhone] = useState(false);

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

  const openEditShop = (s: Shop, e: React.MouseEvent) => {
    e.stopPropagation();
    setEditingShop(s);
    setShopForm({
      name: s.name,
      city: s.city || "",
      phone: s.phone || "",
      gstin: s.gstin || "",
      address: s.address || "",
      state: s.state || "",
      pincode: s.pincode || "",
      contact_person: s.contact_person || "",
      email: s.email || "",
      is_active: s.is_active,
    });
    setShopFormError(null);
    setIsShopModalOpen(true);
  };

  const handleShopSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingShop) return;
    setShopSubmitting(true);
    setShopFormError(null);

    try {
      const updated = await apiRequest<Shop>(`/shops/${editingShop.id}`, {
        method: "PUT",
        body: JSON.stringify({
          name: shopForm.name.trim(),
          city: shopForm.city.trim() || null,
          phone: shopForm.phone.trim() || null,
          gstin: shopForm.gstin.trim() || null,
          address: shopForm.address.trim() || null,
          state: shopForm.state.trim() || null,
          pincode: shopForm.pincode.trim() || null,
          contact_person: shopForm.contact_person.trim() || null,
          email: shopForm.email.trim() || null,
          is_active: shopForm.is_active,
        }),
      });
      setShops((prev) => prev.map((s) => (s.id === updated.id ? updated : s)));
      if (selectedShop && selectedShop.id === updated.id) {
        setSelectedShop(updated);
      }
      setIsShopModalOpen(false);
      await fetchShops();
    } catch (err: any) {
      setShopFormError(err.message || "Failed to save shop details.");
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

  const openShopDetails = async (s: Shop) => {
    setSelectedShop(s);
    setSerialsLoading(true);
    setCopiedGstin(false);
    setCopiedPhone(false);
    try {
      const serials = await apiRequest<ShopDispatchedSerial[]>(`/shops/${s.id}/dispatched-serials`);
      setDispatchedSerials(serials);
    } catch (err) {
      console.error(err);
    } finally {
      setSerialsLoading(false);
    }
  };

  const copyToClipboard = (text: string, type: "gstin" | "phone") => {
    navigator.clipboard.writeText(text);
    if (type === "gstin") {
      setCopiedGstin(true);
      setTimeout(() => setCopiedGstin(false), 2000);
    } else {
      setCopiedPhone(true);
      setTimeout(() => setCopiedPhone(false), 2000);
    }
  };

  const filtered = shops
    .filter((s) => {
      if (filterStatus === "active") return s.is_active;
      if (filterStatus === "deactivated") return !s.is_active;
      return true;
    })
    .filter((s) => {
      const q = search.toLowerCase();
      return (
        s.name.toLowerCase().includes(q) ||
        (s.city && s.city.toLowerCase().includes(q)) ||
        (s.gstin && s.gstin.toLowerCase().includes(q)) ||
        (s.address && s.address.toLowerCase().includes(q)) ||
        (s.phone && s.phone.toLowerCase().includes(q))
      );
    });

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
            Registered retail shops & dispatch locations • Complete customer profile & delivery logs
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
                ? "bg-white text-slate-900 font-semibold shadow-xs"
                : "text-slate-600 hover:text-slate-900"
            }`}
          >
            All Shops ({shops.length})
          </button>
          <button
            onClick={() => setFilterStatus("active")}
            className={`px-3 py-1.5 rounded-lg transition-all cursor-pointer flex items-center gap-1.5 ${
              filterStatus === "active"
                ? "bg-white text-emerald-700 font-semibold shadow-xs"
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
                ? "bg-white text-rose-700 font-semibold shadow-xs"
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
            placeholder="Search by name, GSTIN, city..."
            className="w-full pl-9 pr-4 py-2 text-xs rounded-xl border border-slate-200 bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] text-slate-800 placeholder-slate-400"
          />
        </div>
      </div>

      {/* Shops Grid with Complete Details on Each Card */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
        {filtered.map((shop) => (
          <div
            key={shop.id}
            onClick={() => openShopDetails(shop)}
            className={`bg-white border rounded-2xl p-5 shadow-xs space-y-4 cursor-pointer transition-all hover:shadow-md flex flex-col justify-between group ${
              shop.is_active ? "border-slate-200/90 hover:border-indigo-400/80" : "border-slate-200/80 bg-slate-50/50 opacity-90"
            }`}
          >
            <div className="space-y-3">
              {/* Card Header: Location & Status */}
              <div className="flex items-start justify-between gap-2 flex-wrap">
                <div className="flex items-center gap-1.5 flex-wrap">
                  {shop.city && (
                    <span className="text-[11px] font-semibold text-slate-600 bg-slate-100 px-2.5 py-0.5 rounded-full flex items-center gap-1">
                      <MapPin size={11} className="text-slate-400" />
                      {shop.city}
                    </span>
                  )}
                  {shop.state && shop.state !== shop.city && (
                    <span className="text-[10px] font-medium text-slate-500 bg-slate-50 border border-slate-200 px-2 py-0.5 rounded-full">
                      {shop.state}
                    </span>
                  )}
                </div>

                {shop.is_active ? (
                  <span className="text-[11px] font-semibold text-emerald-700 bg-emerald-50 border border-emerald-200 px-2.5 py-0.5 rounded-full flex items-center gap-1">
                    <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
                    Active
                  </span>
                ) : (
                  <span className="text-[11px] font-semibold text-rose-700 bg-rose-50 border border-rose-200 px-2.5 py-0.5 rounded-full">
                    Deactivated
                  </span>
                )}
              </div>

              {/* Shop Name & GSTIN */}
              <div>
                <h3 className="font-bold text-base text-slate-900 tracking-tight group-hover:text-[#3C3489] transition-colors leading-snug">
                  {shop.name}
                </h3>
                {shop.gstin ? (
                  <div className="mt-1.5 inline-flex items-center gap-1.5 bg-indigo-50 border border-indigo-200/80 px-2 py-0.5 rounded-md">
                    <span className="text-[10px] font-bold uppercase tracking-wider text-indigo-700 font-mono">
                      GSTIN: {shop.gstin}
                    </span>
                  </div>
                ) : null}
              </div>

              {/* Complete Delivery Address */}
              {shop.address && (
                <p className="text-xs text-slate-600 line-clamp-2 leading-relaxed flex items-start gap-1.5 pt-0.5">
                  <MapPin size={13} className="text-slate-400 shrink-0 mt-0.5" />
                  <span>
                    {shop.address}
                    {shop.pincode ? ` - ${shop.pincode}` : ""}
                  </span>
                </p>
              )}

              {/* Phone & Contact Person */}
              <div className="flex items-center gap-3 text-xs text-slate-500 flex-wrap pt-0.5">
                {shop.phone && (
                  <span className="flex items-center gap-1 font-medium text-slate-700">
                    <Phone size={12} className="text-emerald-600" />
                    {shop.phone}
                  </span>
                )}
                {shop.contact_person && (
                  <span className="text-slate-500 text-[11px] flex items-center gap-1">
                    <UserIcon size={11} className="text-slate-400" />
                    <span>{shop.contact_person}</span>
                  </span>
                )}
              </div>
            </div>

            {/* Bottom Bar: Dispatched Counts & Actions */}
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
                      className="p-1.5 rounded-lg text-slate-400 hover:text-slate-700 hover:bg-slate-100 transition-colors cursor-pointer"
                      title="Edit Shop Details"
                    >
                      <Edit2 size={14} />
                    </button>
                    {shop.is_active ? (
                      <button
                        onClick={(e) => handleToggleActive(shop, e)}
                        className="p-1.5 rounded-lg text-slate-400 hover:text-amber-600 hover:bg-amber-50 transition-colors cursor-pointer"
                        title="Deactivate Shop"
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
            No shops found matching your search.
          </div>
        )}
      </div>

      {/* Complete Shop Details & Dispatched Serials Modal */}
      <Modal
        isOpen={Boolean(selectedShop)}
        onClose={() => setSelectedShop(null)}
        title={selectedShop ? selectedShop.name : "Shop Details"}
        subtitle="Complete Shop Profile & Dispatch History"
        maxWidth="2xl"
      >
        {selectedShop && (
          <div className="space-y-5">
            {/* Complete Shop Details Card */}
            <div className="bg-slate-50 border border-slate-200 rounded-2xl p-4.5 space-y-3.5">
              <div className="flex items-start justify-between gap-3 flex-wrap">
                <div>
                  <h4 className="font-bold text-lg text-slate-900 leading-tight">
                    {selectedShop.name}
                  </h4>
                  <div className="flex items-center gap-2 mt-1 flex-wrap">
                    {selectedShop.city && (
                      <span className="text-xs font-semibold text-slate-600 bg-white border border-slate-200 px-2.5 py-0.5 rounded-full flex items-center gap-1">
                        <MapPin size={11} className="text-slate-400" />
                        {selectedShop.city}
                      </span>
                    )}
                    {selectedShop.is_active ? (
                      <span className="text-[10px] font-bold text-emerald-700 bg-emerald-100/80 px-2 py-0.5 rounded-full">
                        Active
                      </span>
                    ) : (
                      <span className="text-[10px] font-bold text-rose-700 bg-rose-100/80 px-2 py-0.5 rounded-full">
                        Deactivated
                      </span>
                    )}
                  </div>
                </div>

                {selectedShop.gstin && (
                  <div className="flex items-center gap-2 bg-white border border-indigo-200 px-3 py-1.5 rounded-xl shadow-2xs">
                    <div>
                      <span className="text-[9px] font-bold uppercase tracking-wider text-slate-400 block leading-none">
                        GSTIN
                      </span>
                      <span className="text-xs font-mono font-bold text-indigo-700">
                        {selectedShop.gstin}
                      </span>
                    </div>
                    <button
                      type="button"
                      onClick={() => copyToClipboard(selectedShop.gstin || "", "gstin")}
                      className="p-1 rounded text-slate-400 hover:text-indigo-600 transition-colors cursor-pointer"
                      title="Copy GSTIN"
                    >
                      {copiedGstin ? <Check size={14} className="text-emerald-600" /> : <Copy size={14} />}
                    </button>
                  </div>
                )}
              </div>

              {/* Grid of Profile Details */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-xs pt-2 border-t border-slate-200/70">
                {/* Full Address */}
                <div className="space-y-1">
                  <span className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider block">
                    Delivery Address
                  </span>
                  <p className="text-slate-800 font-medium leading-relaxed">
                    {selectedShop.address || selectedShop.city || "No detailed address recorded"}
                  </p>
                  {(selectedShop.state || selectedShop.pincode) && (
                    <p className="text-slate-500">
                      {[selectedShop.state, selectedShop.pincode ? `PIN: ${selectedShop.pincode}` : null].filter(Boolean).join(" • ")}
                    </p>
                  )}
                </div>

                {/* Contact & Phone */}
                <div className="space-y-1.5">
                  <span className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider block">
                    Contact Information
                  </span>
                  {selectedShop.phone ? (
                    <div className="flex items-center gap-2">
                      <span className="font-semibold text-slate-900 flex items-center gap-1.5">
                        <Phone size={13} className="text-emerald-600" />
                        <a href={`tel:${selectedShop.phone}`} className="hover:underline text-slate-900">
                          {selectedShop.phone}
                        </a>
                      </span>
                      <button
                        type="button"
                        onClick={() => copyToClipboard(selectedShop.phone || "", "phone")}
                        className="p-0.5 text-slate-400 hover:text-slate-700 cursor-pointer"
                        title="Copy phone"
                      >
                        {copiedPhone ? <Check size={12} className="text-emerald-600" /> : <Copy size={12} />}
                      </button>
                    </div>
                  ) : (
                    <p className="text-slate-400 italic">No phone recorded</p>
                  )}

                  {selectedShop.contact_person && (
                    <p className="text-slate-600 flex items-center gap-1.5">
                      <UserIcon size={12} className="text-slate-400" />
                      <span>Contact: <strong className="text-slate-800">{selectedShop.contact_person}</strong></span>
                    </p>
                  )}

                  {selectedShop.email && (
                    <p className="text-slate-600 flex items-center gap-1.5">
                      <Mail size={12} className="text-slate-400" />
                      <a href={`mailto:${selectedShop.email}`} className="text-indigo-600 hover:underline">
                        {selectedShop.email}
                      </a>
                    </p>
                  )}
                </div>
              </div>
            </div>

            {/* Dispatched History Section */}
            <div>
              <div className="flex items-center justify-between pb-2.5 border-b border-slate-100">
                <h5 className="font-bold text-xs uppercase tracking-wider text-slate-700">
                  Dispatched Serials History ({dispatchedSerials.length})
                </h5>
                <span className="text-[11px] font-semibold text-indigo-700 bg-indigo-50 px-2 py-0.5 rounded-full">
                  Total Dispatched: {selectedShop.total_dispatched_count} units
                </span>
              </div>

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
                <div className="space-y-2 max-h-[50vh] overflow-y-auto pr-1 mt-2">
                  <div className="divide-y divide-slate-100">
                    {dispatchedSerials.map((s, idx) => (
                      <div key={idx} className="py-3 flex items-start justify-between gap-4 text-xs">
                        <div>
                          <div className="flex items-center gap-2">
                            <span className="font-mono font-bold text-slate-900">{s.serial_text}</span>
                            <Badge label={s.is_matched ? "VERIFIED" : "DISPATCHED"} />
                          </div>
                          <p className="font-medium text-slate-700 mt-0.5">{s.product_name}</p>
                          <p className="text-[11px] text-slate-400">{s.brand} • {s.model}</p>
                        </div>

                        <div className="text-right shrink-0 text-slate-400">
                          <div>
                            {new Date(s.transaction_date).toLocaleDateString("en-IN", {
                              month: "short",
                              day: "numeric",
                              year: "numeric",
                            })}
                          </div>
                          {s.delivery_reference && (
                            <div className="text-[11px] text-slate-500 font-mono mt-0.5">
                              Ref: {s.delivery_reference}
                            </div>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>
        )}
      </Modal>

      {/* Shop Edit Modal (for existing shops) */}
      <Modal
        isOpen={isShopModalOpen}
        onClose={() => setIsShopModalOpen(false)}
        title="Edit Destination Shop"
        subtitle="Manage dispatch location details"
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
              className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
            />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
                GSTIN
              </label>
              <input
                type="text"
                value={shopForm.gstin}
                onChange={(e) => setShopForm({ ...shopForm, gstin: e.target.value })}
                placeholder="22AAAAA0000A1Z5"
                className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 font-mono uppercase focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
                Phone
              </label>
              <input
                type="text"
                value={shopForm.phone}
                onChange={(e) => setShopForm({ ...shopForm, phone: e.target.value })}
                placeholder="9876543210"
                className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
              Address
            </label>
            <textarea
              rows={2}
              value={shopForm.address}
              onChange={(e) => setShopForm({ ...shopForm, address: e.target.value })}
              className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
            />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div>
              <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
                City
              </label>
              <input
                type="text"
                value={shopForm.city}
                onChange={(e) => setShopForm({ ...shopForm, city: e.target.value })}
                className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
                State
              </label>
              <input
                type="text"
                value={shopForm.state}
                onChange={(e) => setShopForm({ ...shopForm, state: e.target.value })}
                className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
                Pincode
              </label>
              <input
                type="text"
                value={shopForm.pincode}
                onChange={(e) => setShopForm({ ...shopForm, pincode: e.target.value })}
                className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
              />
            </div>
          </div>

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
              className="px-4 py-2 text-xs font-semibold text-white bg-[#3C3489] hover:bg-[#312B72] rounded-xl shadow-xs transition-colors cursor-pointer disabled:opacity-50"
            >
              {shopSubmitting ? "Saving..." : "Save Details"}
            </button>
          </div>
        </form>
      </Modal>

    </div>
  );
};
