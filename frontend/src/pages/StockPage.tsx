import React, { useEffect, useState, useRef } from "react";
import * as XLSX from "xlsx";
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
  RotateCcw,
  AlertCircle,
  FolderPlus,
  Trash2,
  Copy,
  Check,
  Barcode,
  X,
  Building2,
  Package,
  FileSpreadsheet,
  Upload
} from "lucide-react";

export const StockPage: React.FC = () => {
  const { isAdmin } = useAuth();
  const [products, setProducts] = useState<Product[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<string>("all");
  const [search, setSearch] = useState("");
  const [filterStatus, setFilterStatus] = useState<"all" | "active" | "deactivated">("all");
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
    is_active: true,
  });
  const [formError, setFormError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // Bulk / Parcel Modal state
  const [modalMode, setModalMode] = useState<"single" | "bulk">("single");
  const [bulkCategory, setBulkCategory] = useState<string>("");
  const [bulkBrand, setBulkBrand] = useState<string>("");
  const [bulkText, setBulkText] = useState<string>("");
  const [bulkOpeningQty, setBulkOpeningQty] = useState<number>(0);
  const [bulkDescription, setBulkDescription] = useState<string>("");
  const [bulkResult, setBulkResult] = useState<{
    created_count: number;
    skipped_count: number;
    skipped_models: string[];
  } | null>(null);

  // Compute parsed unique model numbers from bulkText
  const parsedBulkModels = React.useMemo(() => {
    if (!bulkText.trim()) return [];
    const lines = bulkText
      .split(/[\n,;]+/)
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
    return Array.from(new Set(lines));
  }, [bulkText]);

  // Unique list of existing brands for quick selection
  const existingBrands = React.useMemo(() => {
    const list = Array.from(new Set(products.map((p) => p.brand.trim()).filter(Boolean)));
    list.sort((a, b) => a.localeCompare(b));
    return list;
  }, [products]);

  // Excel File Parser state
  const [excelFileName, setExcelFileName] = useState<string | null>(null);
  const [excelWorkbook, setExcelWorkbook] = useState<XLSX.WorkBook | null>(null);
  const [excelSheets, setExcelSheets] = useState<string[]>([]);
  const [excelSelectedSheet, setExcelSelectedSheet] = useState<string>("");
  const [excelColumns, setExcelColumns] = useState<string[]>([]);
  const [excelSelectedColumn, setExcelSelectedColumn] = useState<string>("");
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const parseSheetData = (wb: XLSX.WorkBook, sheetName: string, targetColName?: string) => {
    const worksheet = wb.Sheets[sheetName];
    if (!worksheet) return;

    const rows = XLSX.utils.sheet_to_json<any[]>(worksheet, { header: 1, defval: "" });
    if (!rows || rows.length === 0) {
      setFormError("The selected Excel sheet appears to be empty.");
      return;
    }

    // Determine header row from the first row that has non-empty values
    let headerRowIdx = 0;
    for (let i = 0; i < Math.min(6, rows.length); i++) {
      if (rows[i] && rows[i].some((cell: any) => String(cell || "").trim().length > 0)) {
        headerRowIdx = i;
        break;
      }
    }

    const headerRow = rows[headerRowIdx] || [];
    const colNames: string[] = headerRow.map((cell: any, idx: number) => {
      const str = String(cell || "").trim();
      return str || `Column ${idx + 1}`;
    });

    setExcelColumns(colNames);

    // Auto-detect model column if not explicitly given
    let colIdx = 0;
    if (targetColName && colNames.includes(targetColName)) {
      colIdx = colNames.indexOf(targetColName);
    } else {
      const keywords = ["model", "model no", "model number", "model code", "item model", "product model", "code", "item code", "item", "description"];
      const match = colNames.findIndex((c) =>
        keywords.some((kw) => c.toLowerCase().includes(kw))
      );
      if (match !== -1) {
        colIdx = match;
      }
    }

    const chosenCol = colNames[colIdx] || colNames[0];
    setExcelSelectedColumn(chosenCol);

    // Extract values from that column starting after the header row
    const extracted: string[] = [];
    for (let r = headerRowIdx + 1; r < rows.length; r++) {
      const val = rows[r]?.[colIdx];
      if (val !== undefined && val !== null) {
        const strVal = String(val).trim();
        if (
          strVal &&
          !strVal.toLowerCase().startsWith("model") &&
          !strVal.toLowerCase().startsWith("total")
        ) {
          extracted.push(strVal);
        }
      }
    }

    const uniqueExtracted = Array.from(new Set(extracted));
    setBulkText(uniqueExtracted.join("\n"));
    setFormError(null);
  };

  const handleExcelFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setExcelFileName(file.name);
    const reader = new FileReader();
    reader.onload = (evt) => {
      try {
        const buffer = evt.target?.result as ArrayBuffer;
        const wb = XLSX.read(buffer, { type: "array" });
        const sheets = wb.SheetNames;
        if (!sheets || sheets.length === 0) {
          setFormError("No sheets found in Excel file.");
          return;
        }
        setExcelWorkbook(wb);
        setExcelSheets(sheets);
        setExcelSelectedSheet(sheets[0]);
        parseSheetData(wb, sheets[0]);
      } catch (err: any) {
        setFormError("Failed to parse Excel file: " + (err.message || String(err)));
      }
    };
    reader.readAsArrayBuffer(file);
    if (e.target) e.target.value = "";
  };

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
        setProducts((prev) => prev.map((p) => (p.id === data.id ? { ...p, ...(data as Product) } : p)));
      } else if (event === "product_deleted" && data && data.id) {
        if (isAdmin) {
          setProducts((prev) => prev.map((p) => (p.id === data.id ? { ...p, is_active: false } : p)));
        } else {
          setProducts((prev) => prev.filter((p) => p.id !== data.id));
        }
      }
      fetchStock();
    }
  });

  const openAddModal = (mode: "single" | "bulk" = "single") => {
    setEditingProduct(null);
    setModalMode(mode);
    const defaultCat = (selectedCategory !== "all" ? selectedCategory : categories[0]?.id) || "";
    setFormData({
      name: "",
      sku: "",
      category_id: defaultCat,
      brand: "",
      model: "",
      size_capacity: "",
      unit: "piece",
      opening_stock_qty: 0,
      description: "",
      is_active: true,
    });
    setBulkCategory(defaultCat);
    setBulkBrand("");
    setBulkText("");
    setBulkOpeningQty(0);
    setBulkDescription("");
    setBulkResult(null);
    setExcelFileName(null);
    setExcelWorkbook(null);
    setExcelSheets([]);
    setExcelSelectedSheet("");
    setExcelColumns([]);
    setExcelSelectedColumn("");
    setFormError(null);
    setIsModalOpen(true);
  };

  const openEditModal = (p: Product) => {
    setEditingProduct(p);
    setModalMode("single");
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
      is_active: p.is_active,
    });
    setFormError(null);
    setIsModalOpen(true);
  };

  const handleBulkSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!bulkCategory) {
      setFormError("Please select a category.");
      return;
    }
    if (!bulkBrand.trim()) {
      setFormError("Please enter a brand name.");
      return;
    }
    if (parsedBulkModels.length === 0) {
      setFormError("Please paste or write at least one model number.");
      return;
    }

    setSubmitting(true);
    setFormError(null);
    setBulkResult(null);

    try {
      const res = await apiRequest<{
        created_count: number;
        skipped_count: number;
        created: Product[];
        skipped_models: string[];
      }>("/products/bulk", {
        method: "POST",
        body: JSON.stringify({
          category_id: bulkCategory,
          brand: bulkBrand.trim(),
          models: parsedBulkModels,
          opening_stock_qty: Number(bulkOpeningQty) || 0,
          description: bulkDescription.trim() || null,
        }),
      });

      setBulkResult({
        created_count: res.created_count,
        skipped_count: res.skipped_count,
        skipped_models: res.skipped_models || [],
      });

      if (res.created && res.created.length > 0) {
        setProducts((prev) => [
          ...res.created,
          ...prev.filter((p) => !res.created.some((c) => c.id === p.id)),
        ]);
        if (selectedCategory !== "all" && selectedCategory !== bulkCategory) {
          setSelectedCategory("all");
        }
      }

      await fetchStock();

      if (res.skipped_count === 0) {
        setIsModalOpen(false);
      }
    } catch (err: any) {
      setFormError(err.message || "Failed to bulk add models.");
    } finally {
      setSubmitting(false);
    }
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setFormError(null);

    const finalName = `${formData.brand.trim()} ${formData.model.trim()}`.trim();

    if (
      isAdmin &&
      editingProduct &&
      editingProduct.has_had_inward &&
      Number(formData.opening_stock_qty) !== editingProduct.opening_stock_qty
    ) {
      const oldQty = editingProduct.opening_stock_qty;
      const newQty = Number(formData.opening_stock_qty) || 0;
      const diff = newQty - oldQty;
      const diffStr = diff > 0 ? `+${diff}` : `${diff}`;
      const confirmMsg =
        `⚠️ CONFIRM STOCK ADJUSTMENT\n\n` +
        `Scanning has already started for "${editingProduct.brand} ${editingProduct.model}".\n\n` +
        `• Old Opening Stock: ${oldQty}\n` +
        `• New Opening Stock: ${newQty}\n` +
        `• Live Stock Adjustment: ${diffStr} unit(s)\n\n` +
        `Are you sure you want to proceed with this stock adjustment?`;

      if (!window.confirm(confirmMsg)) {
        setSubmitting(false);
        return;
      }
    }

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
            opening_stock_qty: Number(formData.opening_stock_qty) || 0,
            is_active: formData.is_active,
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
    if (!window.confirm(`Deactivate '${name}'? Deactivated models are hidden from staff scanning but remain in admin for tracking.`)) {
      return;
    }
    try {
      await apiRequest(`/products/${id}`, { method: "DELETE" });
      setProducts((prev) => prev.map((p) => (p.id === id ? { ...p, is_active: false } : p)));
      await fetchStock();
    } catch (e: any) {
      alert(e.message || "Failed to deactivate");
    }
  };

  const handleReactivate = async (id: string, name: string) => {
    if (!window.confirm(`Reactivate '${name}'? This will make the model active and available for inward/outward scanning.`)) {
      return;
    }
    try {
      await apiRequest(`/products/${id}/reactivate`, { method: "POST" });
      setProducts((prev) => prev.map((p) => (p.id === id ? { ...p, is_active: true } : p)));
      await fetchStock();
    } catch (e: any) {
      alert(e.message || "Failed to reactivate");
    }
  };

  const activeCount = products.filter((p) => p.is_active).length;
  const deactivatedCount = products.filter((p) => !p.is_active).length;

  const filtered = products.filter((p) => {
    if (isAdmin) {
      if (filterStatus === "active" && !p.is_active) return false;
      if (filterStatus === "deactivated" && p.is_active) return false;
    } else {
      if (!p.is_active) return false;
    }
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
          <div className="flex items-center gap-2 self-start sm:self-auto flex-wrap">
            <button
              onClick={() => {
                setCategoryError(null);
                setNewCategoryName("");
                setIsCategoryModalOpen(true);
              }}
              className="inline-flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl border border-slate-200 bg-white text-slate-700 text-xs font-semibold hover:bg-slate-50 shadow-xs transition-all cursor-pointer"
            >
              <FolderPlus size={15} className="text-[#3C3489]" />
              <span>Add Category</span>
            </button>
            <button
              onClick={() => openAddModal("single")}
              className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-[#3C3489] text-white text-xs font-semibold hover:bg-[#312B72] shadow-xs shadow-[#3C3489]/25 transition-all cursor-pointer"
            >
              <Plus size={16} />
              <span>Add Product Model</span>
            </button>
          </div>
        )}
      </div>

      {/* Filter Tabs & Search */}
      <div className="space-y-3">
        <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3">
          {/* Status Pills for Admin */}
          {isAdmin ? (
            <div className="flex items-center gap-1 p-1 bg-slate-100 rounded-xl w-fit text-xs font-medium">
              <button
                type="button"
                onClick={() => setFilterStatus("all")}
                className={`px-3 py-1.5 rounded-lg transition-all cursor-pointer ${
                  filterStatus === "all"
                    ? "bg-white text-slate-900 font-semibold shadow-xs"
                    : "text-slate-600 hover:text-slate-900"
                }`}
              >
                All Models ({products.length})
              </button>
              <button
                type="button"
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
                type="button"
                onClick={() => setFilterStatus("deactivated")}
                className={`px-3 py-1.5 rounded-lg transition-all cursor-pointer flex items-center gap-1.5 ${
                  filterStatus === "deactivated"
                    ? "bg-white text-amber-800 font-semibold shadow-xs"
                    : "text-slate-600 hover:text-slate-900"
                }`}
              >
                <span className={`w-2 h-2 rounded-full ${deactivatedCount > 0 ? "bg-amber-500" : "bg-slate-400"} inline-block`} />
                Deactivated ({deactivatedCount})
              </button>
            </div>
          ) : (
            <div />
          )}

          <div className="relative w-full sm:w-72 shrink-0">
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

        {/* Category Pills */}
        <div className="flex items-center gap-1.5 overflow-x-auto pb-1 max-w-full">
          <button
            onClick={() => setSelectedCategory("all")}
            className={`px-3.5 py-1.5 rounded-full text-xs font-medium whitespace-nowrap transition-colors cursor-pointer ${
              selectedCategory === "all"
                ? "bg-[#3C3489] text-white shadow-sm"
                : "bg-white text-slate-600 border border-slate-200 hover:bg-slate-50"
            }`}
          >
            All Categories ({products.filter((p) => {
              if (isAdmin) {
                if (filterStatus === "active" && !p.is_active) return false;
                if (filterStatus === "deactivated" && p.is_active) return false;
              }
              return true;
            }).length})
          </button>
          {categories.map((c) => {
            const count = products.filter((p) => {
              if (p.category_id !== c.id) return false;
              if (isAdmin) {
                if (filterStatus === "active" && !p.is_active) return false;
                if (filterStatus === "deactivated" && p.is_active) return false;
              }
              return true;
            }).length;
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
      </div>

      {/* Products Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
        {filtered.map((p) => (
          <div
            key={p.id}
            onClick={() => openSerialModal(p)}
            className={`group bg-white border rounded-2xl p-5 shadow-xs space-y-4 hover:shadow-md transition-all flex flex-col justify-between cursor-pointer ${
              p.is_active
                ? "border-slate-200/90 hover:border-indigo-400/80"
                : "border-amber-200/90 bg-amber-50/20 hover:border-amber-400/80"
            }`}
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
                  {!p.is_active && (
                    <span className="text-[10px] font-bold text-amber-800 bg-amber-100 border border-amber-300 px-2.5 py-0.5 rounded-full flex items-center gap-1 shadow-2xs">
                      <Archive size={11} className="text-amber-700" />
                      Deactivated
                    </span>
                  )}
                </div>
                <span className="text-[11px] font-semibold text-indigo-600 opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-0.5">
                  View Serials →
                </span>
              </div>

              <div>
                <h3 className={`font-bold text-base tracking-tight leading-snug group-hover:text-indigo-900 transition-colors ${
                  p.is_active ? "text-slate-900" : "text-slate-700"
                }`}>
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
                    {p.is_active ? (
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
                    ) : (
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleReactivate(p.id, p.name);
                        }}
                        className="p-1.5 rounded-lg text-emerald-600 hover:text-emerald-700 hover:bg-emerald-50 transition-colors cursor-pointer"
                        title="Reactivate Product Model"
                      >
                        <RotateCcw size={15} />
                      </button>
                    )}
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
        title={editingProduct ? "Edit Product Model" : (modalMode === "bulk" ? "Excel & Bulk Model Parser" : "Add Product Model")}
        subtitle={editingProduct ? "Global Logistics Master Product Catalog" : (modalMode === "bulk" ? "Upload Excel (.xlsx, .csv) or paste model numbers under category & brand with default 0 opening stock" : "Global Logistics Master Product Catalog")}
        maxWidth={modalMode === "bulk" ? "2xl" : "lg"}
      >
        {!editingProduct && (
          <div className="flex items-center gap-2 border-b border-slate-100 pb-3 mb-4 -mt-1">
            <button
              type="button"
              onClick={() => { setModalMode("single"); setFormError(null); }}
              className={`px-3 py-1.5 text-xs font-semibold rounded-xl transition-all cursor-pointer ${
                modalMode === "single"
                  ? "bg-[#3C3489] text-white shadow-xs"
                  : "text-slate-600 hover:bg-slate-100"
              }`}
            >
              Single Model
            </button>
            <button
              type="button"
              onClick={() => { setModalMode("bulk"); setFormError(null); }}
              className={`px-3 py-1.5 text-xs font-semibold rounded-xl transition-all cursor-pointer flex items-center gap-1.5 ${
                modalMode === "bulk"
                  ? "bg-[#3C3489] text-white shadow-xs"
                  : "text-slate-600 hover:bg-slate-100"
              }`}
            >
              <FileSpreadsheet size={14} className={modalMode === "bulk" ? "text-emerald-300" : "text-emerald-600"} />
              <span>Excel & Bulk Parser</span>
              <span className={`text-[10px] px-1.5 py-0.2 rounded-full font-bold ${
                modalMode === "bulk" ? "bg-white/20 text-white" : "bg-emerald-100 text-emerald-800"
              }`}>
                Auto
              </span>
            </button>
          </div>
        )}

        {formError && (
          <div className="mb-4 p-3 rounded-xl bg-rose-50 border border-rose-200 text-rose-700 text-xs flex items-center gap-2">
            <AlertCircle size={15} />
            <span>{formError}</span>
          </div>
        )}

        {modalMode === "bulk" && !editingProduct ? (
          <form onSubmit={handleBulkSave} className="space-y-4">
            {bulkResult && (
              <div className="p-3.5 rounded-xl bg-emerald-50 border border-emerald-200 text-xs text-emerald-900 space-y-1 animate-fade-in">
                <p className="font-bold flex items-center gap-1.5 text-emerald-800">
                  <Check size={15} className="text-emerald-600" />
                  Successfully added {bulkResult.created_count} product model(s)!
                </p>
                {bulkResult.skipped_count > 0 && (
                  <p className="text-amber-800 text-[11px] bg-amber-50/80 p-2 rounded-lg border border-amber-200/60 mt-1">
                    ⚠️ {bulkResult.skipped_count} model(s) already existed and were skipped:{" "}
                    <span className="font-semibold">{bulkResult.skipped_models.join(", ")}</span>
                  </p>
                )}
              </div>
            )}

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {/* Category Selection */}
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
                  value={bulkCategory}
                  onChange={(e) => setBulkCategory(e.target.value)}
                  className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
                >
                  <option value="">Select Category...</option>
                  {categories.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name} {c.has_dual_serial ? "(Dual Serial)" : ""}
                    </option>
                  ))}
                </select>
              </div>

              {/* Brand Selection */}
              <div>
                <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
                  Brand Name *
                </label>
                <input
                  type="text"
                  required
                  value={bulkBrand}
                  onChange={(e) => setBulkBrand(e.target.value)}
                  placeholder="e.g. ROCKWELL, FORMENTY"
                  className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
                />
                {existingBrands.length > 0 && (
                  <div className="flex items-center gap-1.5 flex-wrap mt-1.5">
                    <span className="text-[10px] text-slate-400 font-medium">Quick select:</span>
                    {existingBrands.map((b) => (
                      <button
                        key={b}
                        type="button"
                        onClick={() => setBulkBrand(b)}
                        className={`text-[11px] px-2 py-0.5 rounded-md font-semibold transition-colors cursor-pointer ${
                          bulkBrand.trim().toLowerCase() === b.toLowerCase()
                            ? "bg-[#3C3489] text-white"
                            : "bg-slate-100 text-slate-600 hover:bg-slate-200"
                        }`}
                      >
                        {b}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            </div>

            {/* Excel File Upload & Auto-Parser Area */}
            <div className="p-3 sm:p-3.5 rounded-xl bg-gradient-to-br from-emerald-50/60 via-white to-indigo-50/40 border border-emerald-200/80 space-y-2.5">
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2.5">
                <div>
                  <h3 className="text-xs font-bold text-slate-900 flex items-center gap-1.5">
                    <FileSpreadsheet size={16} className="text-emerald-600" />
                    <span>Upload Excel File (.xlsx, .xls, .csv)</span>
                  </h3>
                  <p className="text-[11px] text-slate-500 mt-0.5">
                    Select your Excel sheet to automatically detect and extract model numbers.
                  </p>
                </div>

                <div>
                  <input
                    ref={fileInputRef}
                    type="file"
                    accept=".xlsx, .xls, .csv"
                    onChange={handleExcelFileChange}
                    className="hidden"
                  />
                  <button
                    type="button"
                    onClick={() => fileInputRef.current?.click()}
                    className="px-3.5 py-1.5 text-xs font-semibold rounded-xl bg-white border border-emerald-300 text-emerald-800 hover:bg-emerald-50 shadow-2xs transition-all cursor-pointer flex items-center gap-1.5 shrink-0"
                  >
                    <Upload size={13} className="text-emerald-600" />
                    <span>{excelFileName ? "Choose Different Excel" : "Browse Excel File"}</span>
                  </button>
                </div>
              </div>

              {/* If Excel file loaded */}
              {excelFileName && (
                <div className="pt-2.5 border-t border-emerald-100 flex flex-wrap items-center justify-between gap-3 text-xs animate-fade-in">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-semibold text-slate-700 bg-white px-2.5 py-1 rounded-lg border border-slate-200 flex items-center gap-1.5 shadow-2xs">
                      <FileSpreadsheet size={13} className="text-emerald-600" />
                      {excelFileName}
                    </span>
                    <span className="text-[11px] font-bold text-emerald-700 bg-emerald-100/70 px-2.5 py-0.5 rounded-full border border-emerald-300/80">
                      ✓ {parsedBulkModels.length} model(s) extracted
                    </span>
                  </div>

                  <div className="flex items-center gap-2.5 flex-wrap">
                    {/* Sheet selector if multiple */}
                    {excelSheets.length > 1 && (
                      <div className="flex items-center gap-1.5">
                        <span className="text-[11px] text-slate-500 font-medium">Sheet:</span>
                        <select
                          value={excelSelectedSheet}
                          onChange={(e) => {
                            const s = e.target.value;
                            setExcelSelectedSheet(s);
                            if (excelWorkbook) parseSheetData(excelWorkbook, s);
                          }}
                          className="text-xs px-2.5 py-1 bg-white border border-slate-200 rounded-lg focus:outline-none focus:ring-1 focus:ring-emerald-500 font-medium"
                        >
                          {excelSheets.map((sh) => (
                            <option key={sh} value={sh}>{sh}</option>
                          ))}
                        </select>
                      </div>
                    )}

                    {/* Column selector */}
                    {excelColumns.length > 0 && (
                      <div className="flex items-center gap-1.5">
                        <span className="text-[11px] text-slate-500 font-medium">Model Column:</span>
                        <select
                          value={excelSelectedColumn}
                          onChange={(e) => {
                            const col = e.target.value;
                            setExcelSelectedColumn(col);
                            if (excelWorkbook && excelSelectedSheet) {
                              parseSheetData(excelWorkbook, excelSelectedSheet, col);
                            }
                          }}
                          className="text-xs font-semibold px-2.5 py-1 bg-white border border-emerald-400 rounded-lg text-emerald-950 focus:outline-none focus:ring-1 focus:ring-emerald-500"
                        >
                          {excelColumns.map((c) => (
                            <option key={c} value={c}>{c}</option>
                          ))}
                        </select>
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>

            {/* Model Numbers Textarea (Parcel) */}
            <div>
              <div className="flex items-center justify-between mb-1">
                <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600">
                  Model Numbers (Extracted from Excel or paste manually) *
                </label>
                {parsedBulkModels.length > 0 && (
                  <span className="text-xs font-bold text-emerald-700 bg-emerald-50 px-2.5 py-0.5 rounded-full border border-emerald-200 flex items-center gap-1">
                    <Package size={13} />
                    {parsedBulkModels.length} Model{parsedBulkModels.length > 1 ? "s" : ""} Ready
                  </span>
                )}
              </div>
              <textarea
                required
                rows={4}
                value={bulkText}
                onChange={(e) => setBulkText(e.target.value)}
                placeholder={"Model numbers extracted from your Excel sheet will appear here, or you can paste directly.\nExample:\nGFR1210F\nGFR 450 DDUC-5S\nGFR 550 DDUC5S"}
                className="w-full font-mono text-xs px-3.5 py-2 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] leading-relaxed placeholder:font-sans placeholder:text-slate-400"
              />
              <p className="text-[11px] text-slate-500 mt-0.5">
                You can review, edit, or delete any model above before saving. Duplicates are filtered out automatically.
              </p>
            </div>

            {/* Preview Chip Tags */}
            {parsedBulkModels.length > 0 && (
              <div className="p-3 rounded-xl bg-slate-50 border border-slate-200/80 space-y-1.5 max-h-32 overflow-y-auto">
                <div className="flex items-center justify-between text-[11px] text-slate-500 font-medium">
                  <span>Parsed Models Preview ({parsedBulkModels.length}):</span>
                  {bulkBrand.trim() && (
                    <span className="text-indigo-700 font-semibold">
                      Full Name: "{bulkBrand.trim()} &lt;Model&gt;"
                    </span>
                  )}
                </div>
                <div className="flex flex-wrap gap-1.5">
                  {parsedBulkModels.slice(0, 30).map((m, idx) => (
                    <span
                      key={idx}
                      className="text-[11px] font-mono font-medium bg-white border border-slate-200 px-2 py-0.5 rounded-md text-slate-800 shadow-2xs"
                    >
                      {m}
                    </span>
                  ))}
                  {parsedBulkModels.length > 30 && (
                    <span className="text-[11px] font-medium bg-slate-200 text-slate-600 px-2 py-0.5 rounded-md">
                      +{parsedBulkModels.length - 30} more
                    </span>
                  )}
                </div>
              </div>
            )}

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {/* Old Stock Number (Opening Qty) */}
              <div>
                <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
                  Old Stock Number (Opening Qty)
                </label>
                <input
                  type="number"
                  min="0"
                  value={bulkOpeningQty}
                  onChange={(e) => setBulkOpeningQty(parseInt(e.target.value) || 0)}
                  placeholder="0 (Default)"
                  className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
                />
                <span className="text-[11px] text-slate-500 mt-0.5 block">
                  Defaults to 0. Applied as opening stock for all models in this parcel.
                </span>
              </div>

              {/* Description */}
              <div>
                <label className="block text-xs font-semibold uppercase tracking-wider text-slate-600 mb-1">
                  Description / Remarks (Optional)
                </label>
                <input
                  type="text"
                  value={bulkDescription}
                  onChange={(e) => setBulkDescription(e.target.value)}
                  placeholder="e.g. 2026 Models, standard warranty"
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
                disabled={submitting || parsedBulkModels.length === 0}
                className="px-5 py-2 text-xs font-semibold text-white bg-[#3C3489] hover:bg-[#312B72] rounded-xl shadow-xs transition-colors cursor-pointer disabled:opacity-50 flex items-center gap-1.5"
              >
                {submitting ? (
                  "Adding Models..."
                ) : (
                  <>
                    <Layers size={14} />
                    <span>
                      Add {parsedBulkModels.length > 0 ? `${parsedBulkModels.length} Models` : "Models"}
                    </span>
                  </>
                )}
              </button>
            </div>
          </form>
        ) : (
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
                  disabled={editingProduct?.has_had_inward && !isAdmin}
                  value={formData.opening_stock_qty}
                  onChange={(e) => setFormData({ ...formData, opening_stock_qty: parseInt(e.target.value) || 0 })}
                  placeholder="0"
                  className="w-full px-3 py-2 text-sm rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] disabled:bg-slate-50 disabled:text-slate-400"
                />
                {editingProduct?.has_had_inward && (
                  isAdmin ? (
                    <span className="text-[11px] text-amber-700 font-medium mt-1.5 flex items-center gap-1.5 bg-amber-50 px-2.5 py-1.5 rounded-lg border border-amber-200">
                      <AlertCircle className="w-3.5 h-3.5 text-amber-600 shrink-0" />
                      Scanning has started. Changing this will recalculate live stock with confirmation.
                    </span>
                  ) : (
                    <span className="text-[11px] text-slate-400 mt-1 block">
                      Locked: inward transactions have started (Admin only).
                    </span>
                  )
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

              {editingProduct && isAdmin && (
                <div className="sm:col-span-2 p-3 bg-slate-50 border border-slate-200 rounded-xl">
                  <label className="flex items-center gap-2.5 cursor-pointer select-none">
                    <input
                      type="checkbox"
                      checked={formData.is_active}
                      onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
                      className="w-4 h-4 rounded text-[#3C3489] focus:ring-[#3C3489] cursor-pointer"
                    />
                    <div>
                      <span className="text-xs font-semibold text-slate-800">
                        {formData.is_active ? "Model is Active" : "Model is Deactivated"}
                      </span>
                      <p className="text-[11px] text-slate-500">
                        {formData.is_active
                          ? "Available for staff inward & outward scanning."
                          : "Deactivated: hidden from staff scanning while preserving history."}
                      </p>
                    </div>
                  </label>
                </div>
              )}
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
        )}
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
                                    {sn.shop_name}{sn.shop_city ? ` (${sn.shop_city})` : ""}
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