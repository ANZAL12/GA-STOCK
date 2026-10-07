import React, { useEffect, useState } from "react";
import { apiRequest } from "../api/client";
import { useWebSocket } from "../api/useWebSocket";
import { useAuth } from "../context/AuthContext";
import type { Product, Category, ProductSerialItem } from "../types";

import { Modal } from "../components/Modal";
import { 
  Search, 
  Plus, 
  Layers, 
  Edit2, 
  Archive, 
  AlertCircle,
  FolderPlus,
  Trash2,
  Copy,
  Check,
  Barcode,
  X,
  Building2,
  Package
} from "lucide-react";

export const StockPage: React.FC = () => {
  const { isAdmin } = useAuth();
  const [products, setProducts] = useState<Product[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<string>("all");
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);

  // Modal state
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingProduct, setEditingProduct] = useState<Product | null>(null);
  const [formData, setFormData] = useState({
    name: "",
    sku: "",
    category_id: "",
    brand: "",
    model: "",
    size_capacity: "",
    unit: "piece",
    opening_stock_qty: 0,
    description: "",
  });
  const [formError, setFormError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // Category Modal state
  const [isCategoryModalOpen, setIsCategoryModalOpen] = useState(false);
  const [newCategoryName, setNewCategoryName] = useState("");
  const [newCategoryHasDualSerial, setNewCategoryHasDualSerial] = useState(false);
  const [categorySubmitting, setCategorySubmitting] = useState(false);
  const [categoryError, setCategoryError] = useState<string | null>(null);

  // Serial Numbers Modal state
  const [isSerialModalOpen, setIsSerialModalOpen] = useState(false);
  const [selectedProductForSerials, setSelectedProductForSerials] = useState<Product | null>(null);
  const [productSerials, setProductSerials] = useState<ProductSerialItem[]>([]);
  const [serialsLoading, setSerialsLoading] = useState(false);
  const [serialSearch, setSerialSearch] = useState("");
  const [serialStatusFilter, setSerialStatusFilter] = useState<"all" | "available" | "dispatched" | "other">("all");
  const [deletingSerialId, setDeletingSerialId] = useState<string | null>(null);
  const [serialActionMsg, setSerialActionMsg] = useState<{ type: "success" | "error"; text: string } | null>(null);
  const [copiedSerial, setCopiedSerial] = useState<string | null>(null);

  const openSerialModal = async (p: Product) => {
    setSelectedProductForSerials(p);
    setIsSerialModalOpen(true);
    setSerialsLoading(true);
    setSerialSearch("");
    setSerialStatusFilter("all");
    setSerialActionMsg(null);
    try {
      const list = await apiRequest<ProductSerialItem[]>(`/products/${p.id}/serials`);
      setProductSerials(list);
    } catch (err: any) {
      console.error("Failed to load serials", err);
      setSerialActionMsg({ type: "error", text: err.message || "Failed to load scanned serials" });
    } finally {
      setSerialsLoading(false);
    }
  };

  const handleDeleteSerial = async (item: ProductSerialItem) => {
    if (!selectedProductForSerials) return;
    const confirmPrompt = `Are you sure you want to delete serial number "${item.serial_number}"?\n\nThis will remove the scanned record and adjust stock count.`;
    if (!window.confirm(confirmPrompt)) return;

    setDeletingSerialId(item.id);
    setSerialActionMsg(null);

    try {
      const res = await apiRequest<{
        success: boolean;
        message: string;
        product_id: string;
        current_stock_qty: number;
      }>(`/serials/${encodeURIComponent(item.id)}`, {
        method: "DELETE",
      });

      // Remove from serials list
      setProductSerials((prev) => prev.filter((s) => s.id !== item.id));

      // Update current stock in product card and modal
      setSelectedProductForSerials((prev) =>
        prev ? { ...prev, current_stock_qty: res.current_stock_qty } : null
      );
      setProducts((prev) =>
        prev.map((p) =>
          p.id === selectedProductForSerials.id ? { ...p, current_stock_qty: res.current_stock_qty } : p
        )
      );

      setSerialActionMsg({ type: "success", text: `Serial "${item.serial_number}" deleted successfully.` });
      setTimeout(() => setSerialActionMsg(null), 4000);
    } catch (err: any) {
      setSerialActionMsg({ type: "error", text: err.message || "Failed to delete serial" });
    } finally {
      setDeletingSerialId(null);
    }
  };

  const handleCopySerial = (serial: string) => {
    navigator.clipboard.writeText(serial);
    setCopiedSerial(serial);
    setTimeout(() => setCopiedSerial(null), 2000);
  };

  const handleCreateCategory = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newCategoryName.trim()) return;
    setCategorySubmitting(true);
    setCategoryError(null);
    try {
      const created = await apiRequest<Category>("/categories", {
        method: "POST",
        body: JSON.stringify({ 
          name: newCategoryName.trim(),
          has_dual_serial: newCategoryHasDualSerial,
        }),
      });
      await fetchStock();
      setFormData((prev) => ({ ...prev, category_id: created.id }));
      setNewCategoryName("");
      setNewCategoryHasDualSerial(false);
      setIsCategoryModalOpen(false);
    } catch (err: any) {
      setCategoryError(err.message || "Failed to create category");
    } finally {
      setCategorySubmitting(false);
    }
  };

  const fetchStock = async () => {
    try {
      const [prods, cats] = await Promise.all([
        apiRequest<Product[]>("/products"),
        apiRequest<Category[]>("/categories"),
      ]);
      setProducts(prods);
      setCategories(cats);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchStock();
  }, []);

  useWebSocket((event, data) => {
    if (
      event === "product_created" ||
      event === "product_updated" ||
      event === "product_deleted" ||
      event === "category_created" ||
      event === "category_updated" ||
      event === "category_deleted" ||
      event === "stock_updated"
    ) {
      if (event === "product_created" && data && data.id) {
        setProducts((prev) => [data as Product, ...prev.filter((p) => p.id !== data.id)]);
      } else if (event === "product_updated" && data && data.id) {
        setProducts((prev) => prev.map((p) => (p.id === data.id ? (data as Product) : p)));
      } else if (event === "product_deleted" && data && data.id) {
        setProducts((prev) => prev.filter((p) => p.id !== data.id));
      }
      fetchStock();
    }
  });

  const openAddModal = () => {
    setEditingProduct(null);
    setFormData({
      name: "",
      sku: "",
      category_id: (selectedCategory !== "all" ? selectedCategory : categories[0]?.id) || "",
      brand: "",
      model: "",
      size_capacity: "",
      unit: "piece",
      opening_stock_qty: 0,
      description: "",
    });
    setFormError(null);
    setIsModalOpen(true);
  };

  const openEditModal = (p: Product) => {
    setEditingProduct(p);
    setFormData({
      name: p.name,
      sku: p.sku || "",
      category_id: p.category_id,
      brand: p.brand,
      model: p.model,
      size_capacity: p.size_capacity || "",
      unit: p.unit,
      opening_stock_qty: p.opening_stock_qty,
      description: p.description || "",
    });
    setFormError(null);
    setIsModalOpen(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setFormError(null);

    const finalName = `${formData.brand.trim()} ${formData.model.trim()}`.trim();

    try {
      if (editingProduct) {
        const updated = await apiRequest<Product>(`/products/${editingProduct.id}`, {
          method: "PUT",
          body: JSON.stringify({
            name: finalName,
            sku: null,
            category_id: formData.category_id,
            brand: formData.brand.trim(),
            model: formData.model.trim(),
            size_capacity: null,
            unit: "piece",
            description: formData.description?.trim() || null,
            ...(editingProduct.has_had_inward ? {} : { opening_stock_qty: Number(formData.opening_stock_qty) || 0 }),
          }),
        });
        setProducts((prev) => prev.map((p) => (p.id === updated.id ? updated : p)));
      } else {
        const created = await apiRequest<Product>("/products", {
          method: "POST",
          body: JSON.stringify({
            name: finalName,
            category_id: formData.category_id,
            brand: formData.brand.trim(),
            model: formData.model.trim(),
            sku: null,
            size_capacity: null,
            unit: "piece",
            description: formData.description?.trim() || null,
            opening_stock_qty: Number(formData.opening_stock_qty) || 0,
          }),
        });
        // Instantly display the newly added product on screen!
        setProducts((prev) => [created, ...prev.filter((p) => p.id !== created.id)]);
        // Switch to "all" if current category filter would hide the new product
        if (selectedCategory !== "all" && selectedCategory !== created.category_id) {
          setSelectedCategory("all");
        }
      }
      setIsModalOpen(false);
      await fetchStock();
    } catch (err: any) {
      setFormError(err.message || "Failed to save product.");
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeactivate = async (id: string, name: string) => {
    if (!window.confirm(`Deactivate '${name}'? Products with history are never deleted to preserve tracking.`)) {
      return;
    }
    try {
      await apiRequest(`/products/${id}`, { method: "DELETE" });
      setProducts((prev) => prev.filter((p) => p.id !== id));
      await fetchStock();
    } catch (e: any) {
      alert(e.message || "Failed to deactivate");
    }
  };

  const filtered = products.filter((p) => {
    const matchesCategory = selectedCategory === "all" || p.category_id === selectedCategory;
    const q = search.toLowerCase();
    const matchesSearch =
      p.name.toLowerCase().includes(q) ||
      p.brand.toLowerCase().includes(q) ||
      p.model.toLowerCase().includes(q);
    return matchesCategory && matchesSearch;
  });

  const filteredProductSerials = productSerials.filter((s) => {
    const q = serialSearch.trim().toLowerCase();
    const matchesSearch =
      !q ||
      s.serial_number.toLowerCase().includes(q) ||
      (s.shop_name && s.shop_name.toLowerCase().includes(q)) ||
      (s.inward_ref && s.inward_ref.toLowerCase().includes(q)) ||
      (s.delivery_ref && s.delivery_ref.toLowerCase().includes(q));

    if (serialStatusFilter === "all") return matchesSearch;
    if (serialStatusFilter === "available") return matchesSearch && s.status === "available";
    if (serialStatusFilter === "dispatched") return matchesSearch && s.status === "dispatched";
    if (serialStatusFilter === "other") return matchesSearch && s.status !== "available" && s.status !== "dispatched";
    return matchesSearch;
  });

  return (
    <div className="space-y-6 animate-fade-in pb-12">
      
      {/* Title & Actions Bar */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            Stock Inventory
          </h1>
          <p className="text-xs text-slate-500 font-medium mt-0.5">
            Real-time stock counts by model • Pre-go-live and tracked serials
          </p>
        </div>

        {isAdmin && (
          <div className="flex items-center gap-2 self-start sm:self-auto">
            <button
              onClick={() => {
                setCategoryError(null);
                setNewCategoryName("");
                setIsCategoryModalOpen(true);
              }}
              className="inline-flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl border border-slate-200 bg-white text-slate-700 text-xs font-semibold hover:bg-slate-50 shadow-sm transition-all cursor-pointer"
            >
              <FolderPlus size={15} className="text-[#3C3489]" />
              <span>Add Category</span>
            </button>
            <button
              onClick={openAddModal}
              className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-[#3C3489] text-white text-xs font-semibold hover:bg-[#312B72] shadow-sm shadow-[#3C3489]/25 transition-all cursor-pointer"
            >
              <Plus size={16} />
              <span>Add Product Model</span>
            </button>
          </div>
        )}
      </div>

      {/* Filter Tabs & Search */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div className="flex items-center gap-1.5 overflow-x-auto pb-1 max-w-full">
          <button
            onClick={() => setSelectedCategory("all")}
            className={`px-3.5 py-1.5 rounded-full text-xs font-medium whitespace-nowrap transition-colors cursor-pointer ${
              selectedCategory === "all"
                ? "bg-[#3C3489] text-white shadow-sm"
                : "bg-white text-slate-600 border border-slate-200 hover:bg-slate-50"
            }`}
          >
            All Products ({products.length})
          </button>
          {categories.map((c) => {
            const count = products.filter((p) => p.category_id === c.id).length;
            return (
              <button
                key={c.id}
                onClick={() => setSelectedCategory(c.id)}
                className={`px-3.5 py-1.5 rounded-full text-xs font-medium whitespace-nowrap transition-colors cursor-pointer flex items-center gap-1.5 ${
                  selectedCategory === c.id
                    ? "bg-[#3C3489] text-white shadow-sm"
                    : "bg-white text-slate-600 border border-slate-200 hover:bg-slate-50"
                }`}
              >
                <span>{c.name}</span>
                {c.has_dual_serial && (
                  <span className={`text-[10px] font-semibold px-1.5 py-0.2 rounded-full ${
                    selectedCategory === c.id ? "bg-white/20 text-white" : "bg-purple-100 text-purple-700"
                  }`}>
                    Dual
                  </span>
                )}
                <span className="opacity-70">({count})</span>
              </button>
            );
          })}
        </div>

        <div className="relative w-full md:w-72 shrink-0">
          <Search size={15} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Filter models, brand..."
            className="w-full pl-9 pr-4 py-2 text-xs rounded-xl border border-slate-200 bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] transition-all text-slate-800 placeholder-slate-400"
          />
        </div>
      </div>

      {/* Products Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
        {filtered.map((p) => (
          <div
            key={p.id}
            onClick={() => openSerialModal(p)}
            className="group bg-white border border-slate-200/90 rounded-2xl p-5 shadow-xs space-y-4 hover:border-indigo-400/80 hover:shadow-md transition-all flex flex-col justify-between cursor-pointer"
          >
            <div className="space-y-2">
              <div className="flex items-start justify-between gap-2 flex-wrap">
                <div className="flex items-center gap-1.5 flex-wrap">
                  <span className="text-[11px] font-semibold text-[#3C3489] bg-[#EEF2FF] px-2.5 py-0.5 rounded-full uppercase tracking-wider">
                    {p.category_name}
                  </span>
                  {p.has_dual_serial && (
                    <span className="text-[10px] font-semibold text-purple-700 bg-purple-50 border border-purple-200 px-2 py-0.5 rounded-full">
                      Dual Serial (Indoor / Outdoor)
                    </span>
                  )}
                </div>
                <span className="text-[11px] font-semibold text-indigo-600 opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-0.5">
                  View Serials →
                </span>
              </div>

              <div>
                <h3 className="font-bold text-base text-slate-900 tracking-tight leading-snug group-hover:text-indigo-900 transition-colors">
                  {p.brand} {p.model}
                </h3>
                <p className="text-xs text-slate-500 mt-0.5">
                  Model: <span className="font-medium text-slate-700">{p.model}</span>
                </p>
              </div>

              {p.description && (
                <p className="text-xs text-slate-600 line-clamp-2 pt-1 font-normal">
                  {p.description}
                </p>
              )}
            </div>

            {/* Bottom count & Actions */}
            <div className="border-t border-slate-100 pt-3 flex items-center justify-between">
              <div>
                <span className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider block">
                  Current Stock
                </span>
                <span className={`text-lg font-bold ${p.current_stock_qty < 0 ? 'text-rose-600' : 'text-slate-900'}`}>
                  {p.current_stock_qty} <span className={`text-xs font-normal ${p.current_stock_qty < 0 ? 'text-rose-500 font-semibold' : 'text-slate-500'}`}>{p.unit}s</span>
                </span>
              </div>

              <div className="flex items-center gap-1">
                <span className="text-[11px] text-slate-400 group-hover:text-indigo-600 font-medium px-2 py-1 rounded-lg bg-slate-50 group-hover:bg-indigo-50/60 transition-colors mr-1">
                  Click to inspect serials
                </span>
                {isAdmin && (
                  <>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        openEditModal(p);
                      }}
                      className="p-1.5 rounded-lg text-slate-500 hover:text-slate-800 hover:bg-slate-100 transition-colors cursor-pointer"
                      title="Edit Product"
                    >
                      <Edit2 size={15} />
                    </button>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        handleDeactivate(p.id, p.name);
                      }}
                      className="p-1.5 rounded-lg text-slate-400 hover:text-rose-600 hover:bg-rose-50 transition-colors cursor-pointer"
                      title="Deactivate Product"
                    >
                      <Archive size={15} />
                    </button>
                  </>
                )}
              </div>
            </div>
          </div>
        ))}
      </div>

      {filtered.length === 0 && !loading && (
        <div className="bg-white border border-slate-200 rounded-2xl p-12 text-center text-slate-400 space-y-2">
          <Layers size={32} className="mx-auto text-slate-300" />
          <p className="text-sm font-medium text-slate-600">No products match your filter.</p>
          <p className="text-xs text-slate-400">Try adjusting your search or category selection.</p>
        </div>
      )}

      {/* Product Add / Edit Modal */}
      <Modal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        title={editingProduct ? "Edit Product Model" : "Add Product Model"}
        subtitle="Global Logistics Master Product Catalog"
      >
        {formError && (
          <div className="mb-4 p-3 rounded-xl bg-rose-50 border border-rose-200 text-rose-700 text-xs flex items-center gap-2">
            <AlertCircle size={15} />
            <span>{formError}</span>
          </div>
        )}

        <form onSubmit={handleSave} className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
                Brand Name *
              </label>
              <input
                type="text"
                required
                value={formData.brand}
                onChange={(e) => setFormData({ ...formData, brand: e.target.value })}
                placeholder="e.g. Samsung, LG, IFB"
                className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
              />
            </div>

            <div>
              <div className="flex items-center justify-between mb-1">
                <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600">
                  Category *
                </label>
                {isAdmin && (
                  <button
                    type="button"
                    onClick={() => {
                      setCategoryError(null);
                      setNewCategoryName("");
                      setNewCategoryHasDualSerial(false);
                      setIsCategoryModalOpen(true);
                    }}
                    className="text-[11px] font-semibold text-[#3C3489] hover:underline cursor-pointer flex items-center gap-0.5"
                  >
                    <Plus size={11} /> New Category
                  </button>
                )}
              </div>
              <select
                required
                value={formData.category_id}
                onChange={(e) => setFormData({ ...formData, category_id: e.target.value })}
                className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
              >
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>{c.name}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
                Model Number *
              </label>
              <input
                type="text"
                required
                value={formData.model}
                onChange={(e) => setFormData({ ...formData, model: e.target.value })}
                placeholder="e.g. UA43T5350"
                className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
              />
            </div>

            <div>
              <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
                Old Stock Number (Opening Qty)
              </label>
              <input
                type="number"
                min="0"
                disabled={editingProduct?.has_had_inward}
                value={formData.opening_stock_qty}
                onChange={(e) => setFormData({ ...formData, opening_stock_qty: parseInt(e.target.value) || 0 })}
                placeholder="0"
                className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] disabled:bg-slate-50 disabled:text-slate-400"
              />
              {editingProduct?.has_had_inward && (
                <span className="text-[10px] text-slate-400 mt-1 block">Locked: inward transactions have started.</span>
              )}
            </div>

            <div className="sm:col-span-2">
              <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
                Description / Remarks
              </label>
              <textarea
                rows={3}
                value={formData.description}
                onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                placeholder="Optional notes or warranty details..."
                className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
              />
            </div>
          </div>

          <div className="pt-4 border-t border-slate-100 flex items-center justify-end gap-2">
            <button
              type="button"
              onClick={() => setIsModalOpen(false)}
              className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl transition-colors cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={submitting}
              className="px-4 py-2 text-xs font-semibold text-white bg-[#3C3489] hover:bg-[#312B72] rounded-xl shadow-sm transition-colors cursor-pointer disabled:opacity-50"
            >
              {submitting ? "Saving..." : "Save Product"}
            </button>
          </div>
        </form>
      </Modal>

      {/* Add Category Modal */}
      <Modal
        isOpen={isCategoryModalOpen}
        onClose={() => setIsCategoryModalOpen(false)}
        title="Add Appliance Category"
        subtitle="Global Logistics Master Product Catalog"
      >
        {categoryError && (
          <div className="mb-4 p-3 rounded-xl bg-rose-50 border border-rose-200 text-rose-700 text-xs flex items-center gap-2">
            <AlertCircle size={15} />
            <span>{categoryError}</span>
          </div>
        )}

        <form onSubmit={handleCreateCategory} className="space-y-4">
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
              Category Name *
            </label>
            <input
              type="text"
              required
              autoFocus
              value={newCategoryName}
              onChange={(e) => setNewCategoryName(e.target.value)}
              placeholder="e.g. Air Conditioners, Microwave Oven"
              className="w-full px-3 py-2.5 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
            />
          </div>

          <div className="flex items-center justify-between p-3.5 rounded-xl bg-purple-50/50 border border-purple-200/70">
            <div>
              <p className="text-xs font-semibold text-slate-800">Dual Serial Model</p>
              <p className="text-[11px] text-slate-500">
                Enable for AC (Separate Indoor & Outdoor unit serials)
              </p>
            </div>
            <label className="relative inline-flex items-center cursor-pointer">
              <input
                type="checkbox"
                checked={newCategoryHasDualSerial}
                onChange={(e) => setNewCategoryHasDualSerial(e.target.checked)}
                className="sr-only peer"
              />
              <div className="w-11 h-6 bg-slate-300 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-slate-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-[#3C3489]"></div>
            </label>
          </div>

          <div className="pt-3 border-t border-slate-100 flex items-center justify-end gap-2">
            <button
              type="button"
              onClick={() => setIsCategoryModalOpen(false)}
              className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl transition-colors cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={categorySubmitting}
              className="px-4 py-2 text-xs font-semibold text-white bg-[#3C3489] hover:bg-[#312B72] rounded-xl shadow-sm transition-colors cursor-pointer disabled:opacity-50"
            >
              {categorySubmitting ? "Creating..." : "Create Category"}
            </button>
          </div>
        </form>
      </Modal>

      {/* Product Scanned Serials & Delete Modal */}
      {isSerialModalOpen && selectedProductForSerials && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-5 bg-slate-900/50 backdrop-blur-xs animate-in fade-in duration-150">
          <div className="bg-white rounded-2xl border border-slate-200 shadow-2xl max-w-4xl w-full max-h-[90vh] flex flex-col overflow-hidden">
            
            {/* Modal Header */}
            <div className="p-5 bg-gradient-to-r from-slate-900 via-indigo-950 to-slate-900 text-white flex items-start justify-between gap-4 shrink-0">
              <div className="space-y-1">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-xs font-semibold px-2.5 py-0.5 rounded-full bg-indigo-500/30 text-indigo-200 border border-indigo-400/30 uppercase tracking-wider">
                    {selectedProductForSerials.category_name}
                  </span>
                  {selectedProductForSerials.has_dual_serial && (
                    <span className="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-purple-500/30 text-purple-200 border border-purple-400/30">
                      Dual Serial Model
                    </span>
                  )}
                  <span className="text-xs font-bold px-2.5 py-0.5 rounded-full bg-white/10 text-white">
                    Stock: {selectedProductForSerials.current_stock_qty} {selectedProductForSerials.unit}s
                  </span>
                </div>
                <h2 className="text-lg font-bold tracking-tight text-white flex items-center gap-2">
                  <Barcode size={20} className="text-indigo-400" />
                  {selectedProductForSerials.brand} {selectedProductForSerials.model}
                </h2>
                <p className="text-xs text-slate-300">
                  Inspect and manage all scanned serial units for this product. You can delete incorrect or test scans.
                </p>
              </div>

              <button
                onClick={() => setIsSerialModalOpen(false)}
                className="p-1.5 rounded-xl bg-white/10 text-slate-300 hover:text-white hover:bg-white/20 transition-colors cursor-pointer shrink-0"
                title="Close"
              >
                <X size={18} />
              </button>
            </div>

            {/* Notification Banner */}
            {serialActionMsg && (
              <div className={`p-3 text-xs font-medium flex items-center gap-2 border-b shrink-0 ${
                serialActionMsg.type === "success" 
                  ? "bg-emerald-50 text-emerald-800 border-emerald-200" 
                  : "bg-rose-50 text-rose-800 border-rose-200"
              }`}>
                {serialActionMsg.type === "success" ? <Check size={15} className="text-emerald-600" /> : <AlertCircle size={15} className="text-rose-600" />}
                <span>{serialActionMsg.text}</span>
              </div>
            )}

            {/* Filter and Search Toolbar */}
            <div className="p-4 border-b border-slate-100 bg-slate-50/70 flex flex-col sm:flex-row items-center justify-between gap-3 shrink-0">
              <div className="relative w-full sm:w-72">
                <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
                <input
                  type="text"
                  placeholder="Filter serials, shop..."
                  value={serialSearch}
                  onChange={(e) => setSerialSearch(e.target.value)}
                  className="w-full pl-8.5 pr-3 py-1.5 text-xs bg-white border border-slate-200 rounded-xl focus:outline-none focus:ring-1 focus:ring-indigo-800 focus:border-indigo-800 transition-all text-slate-800 placeholder-slate-400"
                />
              </div>

              {/* Status Filter Tabs */}
              <div className="flex items-center gap-1.5 overflow-x-auto w-full sm:w-auto">
                {(["all", "available", "dispatched", "other"] as const).map((tab) => {
                  const count = tab === "all"
                    ? productSerials.length
                    : tab === "available"
                    ? productSerials.filter((s) => s.status === "available").length
                    : tab === "dispatched"
                    ? productSerials.filter((s) => s.status === "dispatched").length
                    : productSerials.filter((s) => s.status !== "available" && s.status !== "dispatched").length;

                  const label = tab === "all" ? "All" : tab === "available" ? "In Stock" : tab === "dispatched" ? "Dispatched" : "Other";
                  const isActive = serialStatusFilter === tab;

                  return (
                    <button
                      key={tab}
                      onClick={() => setSerialStatusFilter(tab)}
                      className={`px-3 py-1 rounded-full text-xs font-semibold whitespace-nowrap transition-colors cursor-pointer ${
                        isActive
                          ? "bg-slate-900 text-white shadow-xs"
                          : "bg-white text-slate-600 border border-slate-200 hover:bg-slate-100"
                      }`}
                    >
                      {label} ({count})
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Serials Table Content */}
            <div className="overflow-y-auto flex-1 p-4">
              {serialsLoading ? (
                <div className="py-16 text-center text-xs text-slate-400 flex flex-col items-center justify-center gap-2">
                  <div className="w-6 h-6 border-2 border-indigo-900 border-t-transparent rounded-full animate-spin" />
                  <span>Loading scanned serial numbers...</span>
                </div>
              ) : filteredProductSerials.length === 0 ? (
                <div className="py-16 text-center text-slate-400 space-y-2">
                  <Package size={32} className="mx-auto text-slate-300" />
                  <p className="text-sm font-semibold text-slate-700">No scanned serial numbers found</p>
                  <p className="text-xs text-slate-400">
                    {productSerials.length === 0
                      ? "No serial numbers have been scanned for this product model yet."
                      : "No serial numbers match the current filter."}
                  </p>
                </div>
              ) : (
                <div className="border border-slate-200 rounded-xl overflow-hidden shadow-xs">
                  <table className="w-full text-left border-collapse text-xs">
                    <thead>
                      <tr className="bg-slate-50 border-b border-slate-200 text-slate-500 font-semibold uppercase tracking-wider text-[11px]">
                        <th className="py-2.5 px-3">Serial Number</th>
                        <th className="py-2.5 px-3">Unit Type</th>
                        <th className="py-2.5 px-3">Status</th>
                        <th className="py-2.5 px-3">Inward Details</th>
                        <th className="py-2.5 px-3">Outward Dispatch</th>
                        <th className="py-2.5 px-3 text-right">Action</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                      {filteredProductSerials.map((sn) => {
                        const isDeleting = deletingSerialId === sn.id;
                        return (
                          <tr key={sn.id} className="hover:bg-slate-50/80 transition-colors">
                            {/* Serial Number & Copy */}
                            <td className="py-2.5 px-3">
                              <div className="flex items-center gap-1.5">
                                <span className="font-mono font-bold text-slate-900 text-xs">
                                  {sn.serial_number}
                                </span>
                                <button
                                  onClick={() => handleCopySerial(sn.serial_number)}
                                  className="p-1 rounded text-slate-400 hover:text-slate-700 hover:bg-slate-100 transition-colors cursor-pointer"
                                  title="Copy Serial"
                                >
                                  {copiedSerial === sn.serial_number ? (
                                    <Check size={12} className="text-emerald-600" />
                                  ) : (
                                    <Copy size={12} />
                                  )}
                                </button>
                              </div>
                              <span className="text-[10px] text-slate-400 block mt-0.5">
                                Scanned: {new Date(sn.scanned_at).toLocaleDateString("en-IN", { month: "short", day: "numeric", year: "numeric" })}
                              </span>
                            </td>

                            {/* Unit Type */}
                            <td className="py-2.5 px-3">
                              {sn.unit_type ? (
                                <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full uppercase ${
                                  sn.unit_type.toLowerCase() === "indoor"
                                    ? "bg-indigo-50 text-indigo-700 border border-indigo-200"
                                    : "bg-teal-50 text-teal-700 border border-teal-200"
                                }`}>
                                  {sn.unit_type}
                                </span>
                              ) : (
                                <span className="text-slate-400 text-[11px]">-</span>
                              )}
                            </td>

                            {/* Status */}
                            <td className="py-2.5 px-3">
                              <span className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[11px] font-semibold border ${
                                sn.status === "available"
                                  ? "bg-emerald-50 text-emerald-700 border-emerald-200"
                                  : sn.status === "dispatched"
                                  ? "bg-amber-50 text-amber-700 border-amber-200"
                                  : sn.status === "damaged"
                                  ? "bg-rose-50 text-rose-700 border-rose-200"
                                  : "bg-slate-100 text-slate-700 border-slate-200"
                              }`}>
                                <span className={`w-1.5 h-1.5 rounded-full ${
                                  sn.status === "available"
                                    ? "bg-emerald-500"
                                    : sn.status === "dispatched"
                                    ? "bg-amber-500"
                                    : sn.status === "damaged"
                                    ? "bg-rose-500"
                                    : "bg-slate-400"
                                }`} />
                                {sn.status_label}
                              </span>
                            </td>

                            {/* Inward Details */}
                            <td className="py-2.5 px-3 text-[11px] text-slate-600">
                              {sn.inward_date ? (
                                <div>
                                  <div className="font-semibold text-slate-800">{sn.inward_date}</div>
                                  <div className="text-[10px] text-slate-400 font-mono">
                                    {sn.inward_ref ? `Ref: ${sn.inward_ref}` : "Inward Scan"}
                                  </div>
                                </div>
                              ) : (
                                <span className="text-slate-400 text-[10px] italic">Opening stock / Pre-go-live</span>
                              )}
                            </td>

                            {/* Outward Details */}
                            <td className="py-2.5 px-3 text-[11px] text-slate-600">
                              {sn.shop_name ? (
                                <div>
                                  <div className="font-semibold text-slate-800 flex items-center gap-1">
                                    <Building2 size={12} className="text-slate-400" />
                                    {sn.shop_name} ({sn.shop_city})
                                  </div>
                                  <div className="text-[10px] text-slate-400">
                                    {sn.outward_date} {sn.delivery_ref ? `• ${sn.delivery_ref}` : ""}
                                  </div>
                                </div>
                              ) : (
                                <span className="text-slate-400 text-[10px] italic">In Godown</span>
                              )}
                            </td>

                            {/* Action: Delete */}
                            <td className="py-2.5 px-3 text-right">
                              {isAdmin && (
                                <button
                                  onClick={() => handleDeleteSerial(sn)}
                                  disabled={isDeleting}
                                  className="inline-flex items-center gap-1 px-2.5 py-1 text-[11px] font-semibold text-rose-700 hover:text-white bg-rose-50 hover:bg-rose-600 border border-rose-200 rounded-lg transition-colors cursor-pointer disabled:opacity-50"
                                  title="Permanently delete serial"
                                >
                                  <Trash2 size={12} />
                                  <span>{isDeleting ? "Deleting..." : "Delete"}</span>
                                </button>
                              )}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </div>

            {/* Modal Footer */}
            <div className="p-4 bg-slate-50 border-t border-slate-100 flex items-center justify-between text-xs text-slate-500 shrink-0">
              <span>
                Showing {filteredProductSerials.length} of {productSerials.length} serials
              </span>
              <button
                onClick={() => setIsSerialModalOpen(false)}
                className="px-4 py-2 bg-slate-900 text-white font-semibold rounded-xl hover:bg-slate-800 transition-colors cursor-pointer"
              >
                Done
              </button>
            </div>

          </div>
        </div>
      )}

    </div>
  );
};