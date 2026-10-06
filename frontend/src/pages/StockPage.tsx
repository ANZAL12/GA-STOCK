import React, { useEffect, useState } from "react";
import { apiRequest } from "../api/client";
import { useWebSocket } from "../api/useWebSocket";
import { useAuth } from "../context/AuthContext";
import type { Product, Category } from "../types";

import { Modal } from "../components/Modal";
import { 
  Search, 
  Plus, 
  Layers, 
  Edit2, 
  Archive, 
  AlertCircle,
  FolderPlus
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
  const [categorySubmitting, setCategorySubmitting] = useState(false);
  const [categoryError, setCategoryError] = useState<string | null>(null);

  const handleCreateCategory = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newCategoryName.trim()) return;
    setCategorySubmitting(true);
    setCategoryError(null);
    try {
      const created = await apiRequest<Category>("/categories", {
        method: "POST",
        body: JSON.stringify({ name: newCategoryName.trim() }),
      });
      await fetchStock();
      setFormData((prev) => ({ ...prev, category_id: created.id }));
      setNewCategoryName("");
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

  useWebSocket((event) => {
    if (
      event === "product_created" ||
      event === "product_updated" ||
      event === "product_deleted" ||
      event === "category_created" ||
      event === "category_updated" ||
      event === "category_deleted" ||
      event === "stock_updated"
    ) {
      fetchStock();
    }
  });

  const openAddModal = () => {
    setEditingProduct(null);
    setFormData({
      name: "",
      sku: "",
      category_id: categories[0]?.id || "",
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
        await apiRequest(`/products/${editingProduct.id}`, {
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
      } else {
        await apiRequest("/products", {
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
      }
      setIsModalOpen(false);
      fetchStock();
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
      fetchStock();
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
                className={`px-3.5 py-1.5 rounded-full text-xs font-medium whitespace-nowrap transition-colors cursor-pointer ${
                  selectedCategory === c.id
                    ? "bg-[#3C3489] text-white shadow-sm"
                    : "bg-white text-slate-600 border border-slate-200 hover:bg-slate-50"
                }`}
              >
                {c.name} ({count})
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
            className="bg-white border border-slate-200 rounded-2xl p-5 shadow-sm space-y-4 hover:border-slate-300 transition-all flex flex-col justify-between"
          >
            <div className="space-y-2">
              <div className="flex items-start justify-between gap-3">
                <span className="text-[11px] font-semibold text-[#3C3489] bg-[#EEF2FF] px-2.5 py-0.5 rounded-full uppercase tracking-wider">
                  {p.category_name}
                </span>

                {p.out_of_stock_reminder && (
                  <span className="text-[11px] font-semibold text-amber-800 bg-amber-50 border border-amber-200 px-2 py-0.5 rounded-full">
                    No tracked stock left
                  </span>
                )}
              </div>

              <div>
                <h3 className="font-bold text-base text-slate-900 tracking-tight leading-snug">
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
                <span className="text-lg font-bold text-slate-900">
                  {p.current_stock_qty} <span className="text-xs font-normal text-slate-500">{p.unit}s</span>
                </span>
              </div>

              {isAdmin && (
                <div className="flex items-center gap-1">
                  <button
                    onClick={() => openEditModal(p)}
                    className="p-1.5 rounded-lg text-slate-500 hover:text-slate-800 hover:bg-slate-100 transition-colors cursor-pointer"
                    title="Edit Product"
                  >
                    <Edit2 size={15} />
                  </button>
                  <button
                    onClick={() => handleDeactivate(p.id, p.name)}
                    className="p-1.5 rounded-lg text-slate-400 hover:text-rose-600 hover:bg-rose-50 transition-colors cursor-pointer"
                    title="Deactivate Product"
                  >
                    <Archive size={15} />
                  </button>
                </div>
              )}
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
        subtitle="Global Agencies Master Product Catalog"
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
        subtitle="Global Agencies Master Product Catalog"
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
              placeholder="e.g. Microwave Oven, Dishwasher, Water Purifier"
              className="w-full px-3 py-2.5 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
            />
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

    </div>
  );
};