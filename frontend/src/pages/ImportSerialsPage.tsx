import React, { useState, useEffect, useRef, useMemo } from "react";
import { useNavigate } from "react-router-dom";
import * as XLSX from "xlsx";
import { apiRequest } from "../api/client";
import { useWebSocket } from "../api/useWebSocket";
import type { 
  Product, 
  Category, 
  BulkSerialCheckResponse, 
  BulkSerialCheckItem, 
  ExcelSerialImportRequest, 
  ExcelSerialImportResponse 
} from "../types";
import { Modal } from "../components/Modal";
import {
  FileSpreadsheet,
  UploadCloud,
  CheckCircle2,
  RotateCcw,
  Download,
  Database,
  Barcode,
  Search,
  Check,
  Sparkles,
  Info,
  ChevronRight,
  ShieldCheck,
  AlertCircle,
  Trash2,
  Undo2
} from "lucide-react";

interface ParsedRow {
  id: string;
  rowIndex: number;
  serialNumber: string;
  rawSerial: string;
  extractedModel?: string;
  extractedUnitType?: string;
  matchedProduct?: Product;
  dbStatus?: BulkSerialCheckItem;
  isInFileDuplicate: boolean;
  isValid: boolean;
  invalidReason?: string;
}

export const ImportSerialsPage: React.FC = () => {
  const navigate = useNavigate();

  // Reference Data
  const [products, setProducts] = useState<Product[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [isLoadingCatalog, setIsLoadingCatalog] = useState(true);

  // File & Sheet State
  const [file, setFile] = useState<File | null>(null);
  const [workbook, setWorkbook] = useState<XLSX.WorkBook | null>(null);
  const [sheets, setSheets] = useState<string[]>([]);
  const [selectedSheet, setSelectedSheet] = useState<string>("");
  const [rawRows, setRawRows] = useState<any[][]>([]);
  const [columns, setColumns] = useState<string[]>([]);
  const [headerRowIndex, setHeaderRowIndex] = useState<number>(0);

  // Column Mappings & Form Inputs
  const [serialColumn, setSerialColumn] = useState<string>("");
  const [mappingMode, setMappingMode] = useState<"single" | "column">("single");
  const [selectedProductId, setSelectedProductId] = useState<string>("");
  const [modelColumn, setModelColumn] = useState<string>("");
  const [unitTypeMode, setUnitTypeMode] = useState<"auto" | "single_unit" | "indoor" | "outdoor" | "column">("auto");
  const [unitTypeColumn, setUnitTypeColumn] = useState<string>("");
  const [inwardRef, setInwardRef] = useState<string>("");
  const [skipExisting, setSkipExisting] = useState<boolean>(true);

  // Deleted & Selected Row IDs
  const [deletedRowIds, setDeletedRowIds] = useState<Set<string>>(new Set());
  const [selectedRowIds, setSelectedRowIds] = useState<Set<string>>(new Set());

  // Search & Filtering within Preview Table
  const [previewFilter, setPreviewFilter] = useState<"all" | "ready" | "duplicates" | "existing">("all");
  const [previewSearch, setPreviewSearch] = useState<string>("");

  // Product Selection Filter
  const [productCategoryFilter, setProductCategoryFilter] = useState<string>("all");
  const [productSearch, setProductSearch] = useState<string>("");

  // DB Verification State
  const [checkingDb, setCheckingDb] = useState<boolean>(false);
  const [dbCheckMap, setDbCheckMap] = useState<Record<string, BulkSerialCheckItem>>({});

  // Import Submission & Results
  const [isImporting, setIsImporting] = useState<boolean>(false);
  const [importError, setImportError] = useState<string | null>(null);
  const [importResult, setImportResult] = useState<ExcelSerialImportResponse | null>(null);
  const [isResultModalOpen, setIsResultModalOpen] = useState<boolean>(false);

  const fileInputRef = useRef<HTMLInputElement | null>(null);

  // Fetch products & categories on load
  const loadInitialData = async () => {
    try {
      setIsLoadingCatalog(true);
      const [prodRes, catRes] = await Promise.all([
        apiRequest<Product[]>("/products?active_only=true"),
        apiRequest<Category[]>("/categories?active_only=true"),
      ]);
      setProducts(prodRes);
      setCategories(catRes);
    } catch (err) {
      console.error("Failed to load initial inventory catalog:", err);
    } finally {
      setIsLoadingCatalog(false);
    }
  };

  useEffect(() => {
    loadInitialData();
  }, []);

  useWebSocket((event) => {
    if (event === "product_created" || event === "product_updated" || event === "stock_updated") {
      loadInitialData();
    }
  });

  // Selected Product Details
  const currentProduct = useMemo(() => {
    return products.find((p) => p.id === selectedProductId) || null;
  }, [products, selectedProductId]);

  // Product Model Lookup Map for Sheet Column Mapping
  const modelLookupMap = useMemo(() => {
    const map = new Map<string, Product>();
    for (const p of products) {
      const cleanModel = p.model.trim().toUpperCase();
      map.set(cleanModel, p);
      const cleanName = p.name.trim().toUpperCase();
      map.set(cleanName, p);
      if (p.sku) {
        map.set(p.sku.trim().toUpperCase(), p);
      }
    }
    return map;
  }, [products]);

  // Handle File Upload
  const processFile = (uploadedFile: File) => {
    setFile(uploadedFile);
    setImportError(null);
    setImportResult(null);
    setDbCheckMap({});

    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const data = e.target?.result;
        const wb = XLSX.read(data, { type: "binary" });
        setWorkbook(wb);
        const sheetList = wb.SheetNames;
        setSheets(sheetList);
        if (sheetList.length > 0) {
          const firstSheet = sheetList[0];
          setSelectedSheet(firstSheet);
          loadSheetData(wb, firstSheet);
        }
      } catch (err: any) {
        console.error("Error reading Excel file:", err);
        setImportError("Unable to parse file. Please upload a valid .xlsx, .xls, or .csv document.");
      }
    };
    reader.readAsBinaryString(uploadedFile);
  };

  const handleFileDrop = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      processFile(e.dataTransfer.files[0]);
    }
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      processFile(e.target.files[0]);
    }
  };

  // Parse Sheet Data
  const loadSheetData = (wb: XLSX.WorkBook, sheetName: string) => {
    const ws = wb.Sheets[sheetName];
    if (!ws) return;

    setDeletedRowIds(new Set());
    setSelectedRowIds(new Set());

    const rows = XLSX.utils.sheet_to_json<any[]>(ws, { header: 1, defval: "" });
    if (!rows || rows.length === 0) {
      setImportError(`Sheet "${sheetName}" contains no rows.`);
      setColumns([]);
      setRawRows([]);
      return;
    }

    // Determine header row index
    let headerIdx = 0;
    for (let i = 0; i < Math.min(8, rows.length); i++) {
      if (rows[i] && rows[i].some((cell: any) => String(cell || "").trim().length > 0)) {
        headerIdx = i;
        break;
      }
    }
    setHeaderRowIndex(headerIdx);

    const headerRow = rows[headerIdx] || [];
    const detectedCols: string[] = headerRow.map((cell: any, idx: number) => {
      const s = String(cell || "").trim();
      return s || `Column ${idx + 1}`;
    });
    setColumns(detectedCols);
    setRawRows(rows);

    // Auto-detect Serial Number column
    const serialKeywords = ["serial", "sr", "s.no", "sn", "serial number", "serial no", "barcode", "bar code", "imei", "chasis"];
    const matchedSerialCol = detectedCols.find((col) =>
      serialKeywords.some((kw) => col.toLowerCase().includes(kw))
    );
    if (matchedSerialCol) {
      setSerialColumn(matchedSerialCol);
    } else if (detectedCols.length > 0) {
      setSerialColumn(detectedCols[0]);
    }

    // Auto-detect Model column
    const modelKeywords = ["model", "model no", "model number", "item model", "product model", "code", "item code", "description"];
    const matchedModelCol = detectedCols.find((col) =>
      modelKeywords.some((kw) => col.toLowerCase().includes(kw))
    );
    if (matchedModelCol && matchedModelCol !== matchedSerialCol) {
      setModelColumn(matchedModelCol);
    }

    // Auto-detect Unit Type column
    const unitKeywords = ["unit", "unit type", "indoor/outdoor", "type", "id/od"];
    const matchedUnitCol = detectedCols.find((col) =>
      unitKeywords.some((kw) => col.toLowerCase().includes(kw))
    );
    if (matchedUnitCol) {
      setUnitTypeColumn(matchedUnitCol);
      setUnitTypeMode("column");
    }
  };

  const handleSheetChange = (newSheet: string) => {
    setSelectedSheet(newSheet);
    if (workbook) {
      loadSheetData(workbook, newSheet);
    }
  };

  // Reset Everything
  const handleReset = () => {
    setFile(null);
    setWorkbook(null);
    setSheets([]);
    setSelectedSheet("");
    setRawRows([]);
    setColumns([]);
    setSerialColumn("");
    setModelColumn("");
    setUnitTypeColumn("");
    setDbCheckMap({});
    setDeletedRowIds(new Set());
    setSelectedRowIds(new Set());
    setImportError(null);
    setImportResult(null);
    if (fileInputRef.current) {
      fileInputRef.current.value = "";
    }
  };

  // Parse all rows based on chosen column
  const allParsedRows: ParsedRow[] = useMemo(() => {
    if (!serialColumn || rawRows.length <= headerRowIndex + 1) {
      return [];
    }

    const serialColIdx = columns.indexOf(serialColumn);
    if (serialColIdx === -1) return [];

    const modelColIdx = modelColumn ? columns.indexOf(modelColumn) : -1;
    const unitColIdx = unitTypeColumn ? columns.indexOf(unitTypeColumn) : -1;

    const seenSerials = new Set<string>();
    const results: ParsedRow[] = [];

    let dualSerialCounter = 0;

    for (let r = headerRowIndex + 1; r < rawRows.length; r++) {
      const row = rawRows[r];
      if (!row) continue;

      const rawVal = row[serialColIdx];
      if (rawVal === undefined || rawVal === null) continue;

      const rawSerialStr = String(rawVal).trim();
      if (!rawSerialStr) continue;

      // Filter out header repeat or summary rows
      const lower = rawSerialStr.toLowerCase();
      if (
        lower === "serial" ||
        lower === "serial number" ||
        lower.startsWith("total") ||
        lower.startsWith("count")
      ) {
        continue;
      }

      // Enforce strict UPPERCASE capitalization rule
      const upperSerial = rawSerialStr.toUpperCase().replace(/\s+/g, "");

      // Check duplicates within this Excel file
      const isDuplicate = seenSerials.has(upperSerial);
      seenSerials.add(upperSerial);

      // Model extraction & match
      let extractedModel = "";
      let matchedProd = currentProduct || undefined;

      if (mappingMode === "column" && modelColIdx !== -1) {
        const rawModelVal = row[modelColIdx];
        if (rawModelVal) {
          extractedModel = String(rawModelVal).trim().toUpperCase();
          if (modelLookupMap.has(extractedModel)) {
            matchedProd = modelLookupMap.get(extractedModel);
          }
        }
      }

      // Unit type resolution
      let extractedUnit = "";
      if (unitTypeMode === "column" && unitColIdx !== -1) {
        const rawUnit = String(row[unitColIdx] || "").trim().toLowerCase();
        if (rawUnit.includes("indoor") || rawUnit === "id" || rawUnit === "in") {
          extractedUnit = "indoor";
        } else if (rawUnit.includes("outdoor") || rawUnit === "od" || rawUnit === "out") {
          extractedUnit = "outdoor";
        } else {
          extractedUnit = "single";
        }
      } else if (unitTypeMode === "indoor") {
        extractedUnit = "indoor";
      } else if (unitTypeMode === "outdoor") {
        extractedUnit = "outdoor";
      } else if (unitTypeMode === "single_unit") {
        extractedUnit = "single";
      } else if (unitTypeMode === "auto") {
        const isDual = matchedProd?.has_dual_serial;
        if (isDual) {
          extractedUnit = dualSerialCounter % 2 === 0 ? "indoor" : "outdoor";
          dualSerialCounter++;
        } else {
          extractedUnit = "single";
        }
      }

      // Check DB Status from cache
      const dbInfo = dbCheckMap[upperSerial];

      let isValid = true;
      let invalidReason: string | undefined;

      if (upperSerial.length < 3) {
        isValid = false;
        invalidReason = "Serial length too short (< 3 chars)";
      } else if (!matchedProd && mappingMode === "column" && !selectedProductId) {
        isValid = false;
        invalidReason = `Unmatched model: "${extractedModel || 'N/A'}"`;
      }

      results.push({
        id: `row-${r + 1}-${upperSerial}-${results.length}`,
        rowIndex: r + 1,
        serialNumber: upperSerial,
        rawSerial: rawSerialStr,
        extractedModel,
        extractedUnitType: extractedUnit,
        matchedProduct: matchedProd,
        dbStatus: dbInfo,
        isInFileDuplicate: isDuplicate,
        isValid,
        invalidReason,
      });
    }

    return results;
  }, [
    rawRows,
    columns,
    serialColumn,
    modelColumn,
    unitTypeColumn,
    headerRowIndex,
    mappingMode,
    currentProduct,
    modelLookupMap,
    unitTypeMode,
    selectedProductId,
    dbCheckMap,
  ]);

  // Active parsed rows excluding user-deleted ones
  const parsedRows: ParsedRow[] = useMemo(() => {
    if (deletedRowIds.size === 0) return allParsedRows;
    return allParsedRows.filter((r) => !deletedRowIds.has(r.id));
  }, [allParsedRows, deletedRowIds]);

  // Bulk check serials in database whenever parsed rows change
  useEffect(() => {
    if (allParsedRows.length === 0) return;

    const uniqueSerials = Array.from(new Set(allParsedRows.map((r) => r.serialNumber)));
    // Filter out serials already present in dbCheckMap
    const toCheck = uniqueSerials.filter((s) => dbCheckMap[s] === undefined);

    if (toCheck.length === 0) return;

    let isMounted = true;
    setCheckingDb(true);

    const runCheck = async () => {
      try {
        const res = await apiRequest<BulkSerialCheckResponse>("/serials/check-bulk", {
          method: "POST",
          body: JSON.stringify({ serials: toCheck, serial_numbers: toCheck }),
        });

        if (isMounted) {
          setDbCheckMap((prev) => {
            const next = { ...prev };
            if (res.results && Array.isArray(res.results)) {
              for (const item of res.results) {
                next[item.serial_number] = { ...item, exists: true };
              }
            } else if (res.existing && typeof res.existing === "object") {
              for (const [sn, item] of Object.entries(res.existing)) {
                if (item && typeof item === "object") {
                  next[sn] = { ...item, exists: true };
                }
              }
            }
            return next;
          });
        }
      } catch (err) {
        console.error("Bulk serial check failed:", err);
      } finally {
        if (isMounted) setCheckingDb(false);
      }
    };

    runCheck();

    return () => {
      isMounted = false;
    };
  }, [allParsedRows]);

  // Delete single row from preview
  const handleDeleteRow = (rowId: string) => {
    setDeletedRowIds((prev) => {
      const next = new Set(prev);
      next.add(rowId);
      return next;
    });
    setSelectedRowIds((prev) => {
      const next = new Set(prev);
      next.delete(rowId);
      return next;
    });
  };

  // Delete multiple selected rows
  const handleDeleteSelected = () => {
    if (selectedRowIds.size === 0) return;
    setDeletedRowIds((prev) => {
      const next = new Set(prev);
      for (const id of selectedRowIds) {
        next.add(id);
      }
      return next;
    });
    setSelectedRowIds(new Set());
  };

  // Quick bulk delete: Remove in-file duplicates
  const handleDeleteDuplicates = () => {
    const dupeIds = parsedRows.filter((r) => r.isInFileDuplicate).map((r) => r.id);
    if (dupeIds.length === 0) return;
    setDeletedRowIds((prev) => {
      const next = new Set(prev);
      for (const id of dupeIds) {
        next.add(id);
      }
      return next;
    });
  };

  // Quick bulk delete: Remove serials already in DB
  const handleDeleteExistingInDb = () => {
    const existingIds = parsedRows.filter((r) => r.dbStatus?.exists).map((r) => r.id);
    if (existingIds.length === 0) return;
    setDeletedRowIds((prev) => {
      const next = new Set(prev);
      for (const id of existingIds) {
        next.add(id);
      }
      return next;
    });
  };

  // Quick bulk delete: Remove invalid rows
  const handleDeleteInvalid = () => {
    const invalidIds = parsedRows.filter((r) => !r.isValid).map((r) => r.id);
    if (invalidIds.length === 0) return;
    setDeletedRowIds((prev) => {
      const next = new Set(prev);
      for (const id of invalidIds) {
        next.add(id);
      }
      return next;
    });
  };

  // Restore all deleted rows
  const handleRestoreDeleted = () => {
    setDeletedRowIds(new Set());
  };

  // Toggle select row
  const handleToggleSelectRow = (rowId: string) => {
    setSelectedRowIds((prev) => {
      const next = new Set(prev);
      if (next.has(rowId)) {
        next.delete(rowId);
      } else {
        next.add(rowId);
      }
      return next;
    });
  };

  // Select all or deselect all visible rows in the table
  const handleToggleSelectAll = () => {
    const visibleIds = filteredPreviewRows.map((r) => r.id);
    const allSelected = visibleIds.length > 0 && visibleIds.every((id) => selectedRowIds.has(id));
    if (allSelected) {
      setSelectedRowIds((prev) => {
        const next = new Set(prev);
        for (const id of visibleIds) {
          next.delete(id);
        }
        return next;
      });
    } else {
      setSelectedRowIds((prev) => {
        const next = new Set(prev);
        for (const id of visibleIds) {
          next.add(id);
        }
        return next;
      });
    }
  };

  // Metrics computation
  const metrics = useMemo(() => {
    let total = parsedRows.length;
    let inFileDuplicates = 0;
    let alreadyInDb = 0;
    let readyToImport = 0;
    let invalidCount = 0;

    for (const row of parsedRows) {
      if (!row.isValid) {
        invalidCount++;
        continue;
      }
      if (row.isInFileDuplicate) {
        inFileDuplicates++;
        continue;
      }
      if (row.dbStatus?.exists) {
        alreadyInDb++;
        if (!skipExisting) {
          readyToImport++;
        }
      } else {
        readyToImport++;
      }
    }

    return { total, inFileDuplicates, alreadyInDb, readyToImport, invalidCount };
  }, [parsedRows, skipExisting]);

  // Filtered Rows for Preview Table
  const filteredPreviewRows = useMemo(() => {
    return parsedRows.filter((row) => {
      // Status filter
      if (previewFilter === "ready") {
        if (!row.isValid || row.isInFileDuplicate) return false;
        if (row.dbStatus?.exists && skipExisting) return false;
      } else if (previewFilter === "duplicates") {
        if (!row.isInFileDuplicate) return false;
      } else if (previewFilter === "existing") {
        if (!row.dbStatus?.exists) return false;
      }

      // Search query
      if (previewSearch.trim()) {
        const q = previewSearch.trim().toUpperCase();
        const matchSerial = row.serialNumber.includes(q);
        const matchModel = row.matchedProduct?.model.toUpperCase().includes(q) || (row.extractedModel && row.extractedModel.includes(q));
        const matchBrand = row.matchedProduct?.brand.toUpperCase().includes(q);
        if (!matchSerial && !matchModel && !matchBrand) return false;
      }

      return true;
    });
  }, [parsedRows, previewFilter, previewSearch, skipExisting]);

  // Download Sample Template
  const handleDownloadTemplate = () => {
    const wsData = [
      ["Serial Number", "Model", "Unit Type", "Reference"],
      ["SN-SPLIT-90812-A", "CS-XU18XKYF", "Indoor", "INV-2026-001"],
      ["SN-SPLIT-90812-B", "CS-XU18XKYF", "Outdoor", "INV-2026-001"],
      ["SN-INVERTER-4410", "FTKM50U", "Single", "INV-2026-001"],
      ["SN-INVERTER-4411", "FTKM50U", "Single", "INV-2026-001"],
    ];

    const ws = XLSX.utils.aoa_to_sheet(wsData);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "SerialsTemplate");
    XLSX.writeFile(wb, "serial_number_import_template.xlsx");
  };

  // Perform Final Bulk Import
  const handleExecuteImport = async () => {
    if (metrics.readyToImport === 0) {
      setImportError("There are no valid serial numbers ready to import.");
      return;
    }

    if (mappingMode === "single" && !selectedProductId) {
      setImportError("Please select a Product Model for the serials before importing.");
      return;
    }

    setIsImporting(true);
    setImportError(null);

    try {
      // Build import items
      const itemsToImport = parsedRows
        .filter((r) => {
          if (!r.isValid) return false;
          if (r.isInFileDuplicate) return false;
          if (r.dbStatus?.exists && skipExisting) return false;
          return true;
        })
        .map((r) => ({
          serial_number: r.serialNumber,
          product_id: r.matchedProduct?.id || (mappingMode === "single" ? selectedProductId : undefined),
          model_name: r.extractedModel || undefined,
          unit_type: r.extractedUnitType || undefined,
          row_index: r.rowIndex,
        }));

      const payload: ExcelSerialImportRequest = {
        items: itemsToImport,
        default_product_id: selectedProductId || undefined,
        inward_reference: inwardRef.trim() ? inwardRef.trim().toUpperCase() : undefined,
        skip_existing: skipExisting,
      };

      const result = await apiRequest<ExcelSerialImportResponse>("/serials/import-bulk", {
        method: "POST",
        body: JSON.stringify(payload),
      });

      setImportResult(result);
      setIsResultModalOpen(true);
    } catch (err: any) {
      console.error("Import failed:", err);
      setImportError(err.message || "Failed to import serial numbers. Please try again.");
    } finally {
      setIsImporting(false);
    }
  };

  // Products filtered for the single product picker
  const filteredProductsList = useMemo(() => {
    return products.filter((p) => {
      if (productCategoryFilter !== "all" && p.category_id !== productCategoryFilter) {
        return false;
      }
      if (productSearch.trim()) {
        const q = productSearch.trim().toUpperCase();
        return (
          p.model.toUpperCase().includes(q) ||
          p.brand.toUpperCase().includes(q) ||
          p.name.toUpperCase().includes(q) ||
          (p.sku && p.sku.toUpperCase().includes(q))
        );
      }
      return true;
    });
  }, [products, productCategoryFilter, productSearch]);

  return (
    <div className="w-full max-w-[1720px] mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      
      {/* Page Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 pb-6 border-b border-slate-200">
        <div>
          <div className="flex items-center gap-2 text-xs font-semibold text-slate-500 uppercase tracking-wider mb-1">
            <span>Admin Dashboard</span>
            <ChevronRight size={12} className="text-slate-400" />
            <span className="text-[#3C3489] font-bold">Serial Number Importer</span>
          </div>
          <h1 className="text-2xl sm:text-3xl font-extrabold text-slate-900 tracking-tight flex items-center gap-3">
            <span className="p-2.5 rounded-2xl bg-indigo-50 border border-indigo-100 text-[#3C3489]">
              <FileSpreadsheet size={26} />
            </span>
            Excel Serial Numbers Import
          </h1>
          <p className="text-sm text-slate-500 mt-1.5 max-w-2xl">
            Upload any Excel or CSV sheet, select the serial number column, map your product models, 
            and import inward inventory in bulk with automatic duplicate detection.
          </p>
        </div>

        <div className="flex items-center gap-3 shrink-0">
          <button
            onClick={handleDownloadTemplate}
            className="flex items-center gap-2 px-4 py-2.5 rounded-xl border border-slate-200 bg-white text-slate-700 text-xs font-semibold hover:bg-slate-50 hover:border-slate-300 transition-all shadow-sm"
          >
            <Download size={15} className="text-slate-500" />
            Sample Template
          </button>

          {file && (
            <button
              onClick={handleReset}
              className="flex items-center gap-2 px-4 py-2.5 rounded-xl border border-slate-200 bg-white text-slate-600 text-xs font-semibold hover:text-rose-600 hover:border-rose-200 hover:bg-rose-50/50 transition-all shadow-sm"
            >
              <RotateCcw size={15} />
              Reset All
            </button>
          )}
        </div>
      </div>

      {/* Main Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        
        {/* Left Column: Upload & Mapping Controls (4 cols on lg) */}
        <div className="lg:col-span-5 space-y-6">

          {/* STEP 1: Upload Card */}
          <div className="bg-white rounded-2xl border border-slate-200/90 shadow-sm p-5 space-y-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2.5">
                <span className="w-6 h-6 rounded-full bg-[#3C3489] text-white flex items-center justify-center text-xs font-bold">
                  1
                </span>
                <h3 className="font-bold text-slate-900 text-sm">Upload Spreadsheet</h3>
              </div>
              {file && (
                <span className="text-[11px] font-semibold text-emerald-600 bg-emerald-50 px-2.5 py-0.5 rounded-full border border-emerald-200">
                  Ready
                </span>
              )}
            </div>

            {/* Drag & Drop Area */}
            {!file ? (
              <div
                onDragOver={(e) => e.preventDefault()}
                onDrop={handleFileDrop}
                onClick={() => fileInputRef.current?.click()}
                className="group border-2 border-dashed border-slate-200 hover:border-[#3C3489]/50 hover:bg-indigo-50/20 rounded-2xl p-7 text-center cursor-pointer transition-all flex flex-col items-center justify-center gap-3"
              >
                <div className="w-14 h-14 rounded-2xl bg-indigo-50 text-[#3C3489] flex items-center justify-center group-hover:scale-105 transition-transform">
                  <UploadCloud size={28} />
                </div>
                <div>
                  <p className="text-sm font-bold text-slate-800">
                    Click to browse or drag & drop spreadsheet
                  </p>
                  <p className="text-xs text-slate-500 mt-1">
                    Supports Microsoft Excel (.xlsx, .xls) and CSV (.csv)
                  </p>
                </div>
                <input
                  ref={fileInputRef}
                  type="file"
                  accept=".xlsx, .xls, .csv"
                  onChange={handleFileChange}
                  className="hidden"
                />
              </div>
            ) : (
              <div className="p-4 rounded-xl bg-slate-50 border border-slate-200/80 space-y-3">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <div className="p-2.5 rounded-xl bg-emerald-500/10 text-emerald-600">
                      <FileSpreadsheet size={22} />
                    </div>
                    <div>
                      <p className="font-bold text-slate-900 text-xs truncate max-w-[220px]">
                        {file.name}
                      </p>
                      <p className="text-[11px] text-slate-500 mt-0.5">
                        {(file.size / 1024).toFixed(1)} KB &bull; {rawRows.length > 0 ? `${rawRows.length - 1} rows detected` : "Loading..."}
                      </p>
                    </div>
                  </div>
                  <button
                    onClick={handleReset}
                    className="text-xs text-slate-400 hover:text-rose-600 p-1"
                    title="Remove file"
                  >
                    <RotateCcw size={14} />
                  </button>
                </div>

                {/* Sheet Selector if multiple sheets */}
                {sheets.length > 1 && (
                  <div className="pt-2 border-t border-slate-200/60">
                    <label className="text-[11px] font-semibold text-slate-600 uppercase tracking-wider block mb-1">
                      Active Sheet
                    </label>
                    <div className="flex flex-wrap gap-1.5">
                      {sheets.map((sheet) => (
                        <button
                          key={sheet}
                          onClick={() => handleSheetChange(sheet)}
                          className={`px-3 py-1 text-xs font-semibold rounded-lg border transition-all ${
                            selectedSheet === sheet
                              ? "bg-[#3C3489] text-white border-[#3C3489]"
                              : "bg-white text-slate-700 border-slate-200 hover:bg-slate-100"
                          }`}
                        >
                          {sheet}
                        </button>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>

          {/* STEP 2: Column Selection Card */}
          {file && columns.length > 0 && (
            <div className="bg-white rounded-2xl border border-slate-200/90 shadow-sm p-5 space-y-5">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2.5">
                  <span className="w-6 h-6 rounded-full bg-[#3C3489] text-white flex items-center justify-center text-xs font-bold">
                    2
                  </span>
                  <h3 className="font-bold text-slate-900 text-sm">Select Columns & Product</h3>
                </div>
                <span className="text-[11px] font-semibold text-slate-500">
                  {columns.length} columns found
                </span>
              </div>

              {/* Serial Number Column Dropdown */}
              <div className="space-y-1.5">
                <label className="text-xs font-bold text-slate-700 flex items-center justify-between">
                  <span>Serial Number Column <span className="text-rose-500">*</span></span>
                  <span className="text-[10px] font-normal text-indigo-600 bg-indigo-50 px-2 py-0.5 rounded-full">
                    Auto-selected
                  </span>
                </label>
                <select
                  value={serialColumn}
                  onChange={(e) => setSerialColumn(e.target.value)}
                  className="w-full text-xs font-semibold px-3 py-2.5 rounded-xl border border-slate-200 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] transition-all"
                >
                  <option value="" disabled>-- Select Serial Number Column --</option>
                  {columns.map((col, idx) => (
                    <option key={idx} value={col}>
                      {col}
                    </option>
                  ))}
                </select>
                <p className="text-[11px] text-slate-500">
                  All serial numbers will be strictly converted to UPPERCASE as required.
                </p>
              </div>

              {/* Product Assignment Mode Toggle */}
              <div className="space-y-3 pt-3 border-t border-slate-100">
                <label className="text-xs font-bold text-slate-700 block">
                  Product Assignment Mode
                </label>
                <div className="grid grid-cols-2 gap-2">
                  <button
                    type="button"
                    onClick={() => setMappingMode("single")}
                    className={`p-3 rounded-xl border text-left transition-all ${
                      mappingMode === "single"
                        ? "border-[#3C3489] bg-indigo-50/40 ring-1 ring-[#3C3489]"
                        : "border-slate-200 hover:border-slate-300 bg-white"
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-slate-900">Single Product</span>
                      {mappingMode === "single" && <CheckCircle2 size={15} className="text-[#3C3489]" />}
                    </div>
                    <p className="text-[11px] text-slate-500 mt-1 leading-snug">
                      Apply one model to all serials in this sheet
                    </p>
                  </button>

                  <button
                    type="button"
                    onClick={() => setMappingMode("column")}
                    className={`p-3 rounded-xl border text-left transition-all ${
                      mappingMode === "column"
                        ? "border-[#3C3489] bg-indigo-50/40 ring-1 ring-[#3C3489]"
                        : "border-slate-200 hover:border-slate-300 bg-white"
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-slate-900">Map From Column</span>
                      {mappingMode === "column" && <CheckCircle2 size={15} className="text-[#3C3489]" />}
                    </div>
                    <p className="text-[11px] text-slate-500 mt-1 leading-snug">
                      Match model numbers row-by-row from sheet
                    </p>
                  </button>
                </div>
              </div>

              {/* MODE 1: Single Product Selector */}
              {mappingMode === "single" && (
                <div className="space-y-2 bg-slate-50/80 p-3.5 rounded-xl border border-slate-200/80">
                  <label className="text-xs font-bold text-slate-800 flex items-center justify-between">
                    <span>Target Product Model <span className="text-rose-500">*</span></span>
                    {currentProduct && (
                      <span className="text-[10px] font-semibold text-emerald-700 bg-emerald-100/80 px-2 py-0.5 rounded-full">
                        Current Stock: {currentProduct.current_stock_qty}
                      </span>
                    )}
                  </label>

                  {/* Category Filter for quick search */}
                  <div className="flex gap-2">
                    <select
                      value={productCategoryFilter}
                      onChange={(e) => setProductCategoryFilter(e.target.value)}
                      className="text-[11px] font-medium px-2 py-1.5 rounded-lg border border-slate-200 bg-white"
                    >
                      <option value="all">All Categories</option>
                      {categories.map((c) => (
                        <option key={c.id} value={c.id}>
                          {c.name}
                        </option>
                      ))}
                    </select>

                    <div className="relative flex-1">
                      <Search size={13} className="absolute left-2.5 top-2.5 text-slate-400" />
                      <input
                        type="text"
                        placeholder="Search model, brand..."
                        value={productSearch}
                        onChange={(e) => setProductSearch(e.target.value)}
                        className="w-full pl-8 pr-2 py-1.5 text-[11px] rounded-lg border border-slate-200 bg-white focus:outline-none"
                      />
                    </div>
                  </div>

                  {/* Product List Dropdown */}
                  <select
                    value={selectedProductId}
                    onChange={(e) => setSelectedProductId(e.target.value)}
                    disabled={isLoadingCatalog}
                    className="w-full text-xs font-semibold px-3 py-2.5 rounded-xl border border-slate-200 bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489] disabled:opacity-60"
                  >
                    <option value="">
                      {isLoadingCatalog ? "Loading catalog..." : "-- Choose Product Model --"}
                    </option>
                    {filteredProductsList.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.brand} - {p.model} ({p.name}) {p.has_dual_serial ? "[DUAL SERIAL]" : ""}
                      </option>
                    ))}
                  </select>

                  {/* Warning / Indicator for Dual Serial */}
                  {currentProduct?.has_dual_serial && (
                    <div className="flex items-center gap-2 p-2 rounded-lg bg-amber-50 border border-amber-200 text-amber-800 text-[11px]">
                      <Info size={14} className="shrink-0 text-amber-600" />
                      <span>
                        This model uses dual serials (Indoor + Outdoor). 2 serials = 1 complete set.
                      </span>
                    </div>
                  )}
                </div>
              )}

              {/* MODE 2: Map Model Column */}
              {mappingMode === "column" && (
                <div className="space-y-3 bg-slate-50/80 p-3.5 rounded-xl border border-slate-200/80">
                  <div className="space-y-1">
                    <label className="text-xs font-bold text-slate-800 block">
                      Excel Model / Item Code Column <span className="text-rose-500">*</span>
                    </label>
                    <select
                      value={modelColumn}
                      onChange={(e) => setModelColumn(e.target.value)}
                      className="w-full text-xs font-semibold px-3 py-2 rounded-xl border border-slate-200 bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20 focus:border-[#3C3489]"
                    >
                      <option value="">-- Select Model Column --</option>
                      {columns.map((col, idx) => (
                        <option key={idx} value={col}>
                          {col}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div className="space-y-1">
                    <label className="text-xs font-medium text-slate-600 block">
                      Fallback Product (if model cell is blank or unmapped)
                    </label>
                    <select
                      value={selectedProductId}
                      onChange={(e) => setSelectedProductId(e.target.value)}
                      className="w-full text-xs font-medium px-3 py-2 rounded-xl border border-slate-200 bg-white"
                    >
                      <option value="">-- No Fallback (Skip row if unmapped) --</option>
                      {products.map((p) => (
                        <option key={p.id} value={p.id}>
                          {p.brand} - {p.model}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>
              )}

              {/* Unit Type Handling for Dual Units */}
              <div className="space-y-1.5 pt-3 border-t border-slate-100">
                <label className="text-xs font-bold text-slate-700 block">
                  Unit Type Handling
                </label>
                <select
                  value={unitTypeMode}
                  onChange={(e: any) => setUnitTypeMode(e.target.value)}
                  className="w-full text-xs font-semibold px-3 py-2 rounded-xl border border-slate-200 bg-slate-50"
                >
                  <option value="auto">Automatic (Indoor/Outdoor alternation for Dual Models, Single for others)</option>
                  <option value="single_unit">All Single Units</option>
                  <option value="indoor">All Indoor Units</option>
                  <option value="outdoor">All Outdoor Units</option>
                  <option value="column">Map from Spreadsheet Column</option>
                </select>

                {unitTypeMode === "column" && (
                  <select
                    value={unitTypeColumn}
                    onChange={(e) => setUnitTypeColumn(e.target.value)}
                    className="w-full text-xs font-semibold px-3 py-2 mt-2 rounded-xl border border-slate-200 bg-white"
                  >
                    <option value="">-- Select Unit Type Column --</option>
                    {columns.map((col, idx) => (
                      <option key={idx} value={col}>
                        {col}
                      </option>
                    ))}
                  </select>
                )}
              </div>

              {/* Inward Reference & Options */}
              <div className="space-y-3 pt-3 border-t border-slate-100">
                <div>
                  <label className="text-xs font-bold text-slate-700 block mb-1">
                    Inward Batch / Invoice Reference <span className="text-slate-400 font-normal">(Optional)</span>
                  </label>
                  <input
                    type="text"
                    placeholder="e.g. INV-2026-OCT-884 or PO-99120"
                    value={inwardRef}
                    onChange={(e) => setInwardRef(e.target.value.toUpperCase())}
                    className="w-full text-xs font-medium px-3 py-2 rounded-xl border border-slate-200 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-[#3C3489]/20"
                  />
                </div>

                <div className="pt-1">
                  <label className="flex items-center gap-2 cursor-pointer select-none">
                    <input
                      type="checkbox"
                      checked={skipExisting}
                      onChange={(e) => setSkipExisting(e.target.checked)}
                      className="w-4 h-4 rounded text-[#3C3489] focus:ring-[#3C3489] border-slate-300"
                    />
                    <span className="text-xs font-semibold text-slate-700">
                      Skip serial numbers already existing in inventory
                    </span>
                  </label>
                  <p className="text-[11px] text-slate-400 ml-6 mt-0.5">
                    Recommended to avoid duplicate stock creation and error interruptions.
                  </p>
                </div>
              </div>
            </div>
          )}

        </div>

        {/* Right Column: Live Verification Table & Execution (7 cols on lg) */}
        <div className="lg:col-span-7 space-y-6">

          {/* Metric KPI Cards */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            
            <div className="bg-white p-4 rounded-2xl border border-slate-200/90 shadow-sm">
              <span className="text-[10px] font-bold text-slate-500 uppercase tracking-wider block">
                Total Rows
              </span>
              <div className="text-2xl font-extrabold text-slate-900 mt-1">
                {metrics.total}
              </div>
              <span className="text-[11px] text-slate-400 mt-0.5 block">
                Extracted from sheet
              </span>
            </div>

            <div className="bg-white p-4 rounded-2xl border border-emerald-200/90 shadow-sm bg-emerald-50/20">
              <span className="text-[10px] font-bold text-emerald-700 uppercase tracking-wider block">
                Ready to Import
              </span>
              <div className="text-2xl font-extrabold text-emerald-700 mt-1 flex items-center gap-2">
                {metrics.readyToImport}
                <CheckCircle2 size={18} className="text-emerald-500" />
              </div>
              <span className="text-[11px] text-emerald-600/80 mt-0.5 block font-medium">
                Valid new units
              </span>
            </div>

            <div className="bg-white p-4 rounded-2xl border border-amber-200/90 shadow-sm bg-amber-50/20">
              <span className="text-[10px] font-bold text-amber-700 uppercase tracking-wider block">
                In-Sheet Duplicates
              </span>
              <div className="text-2xl font-extrabold text-amber-700 mt-1">
                {metrics.inFileDuplicates}
              </div>
              <span className="text-[11px] text-amber-600/80 mt-0.5 block font-medium">
                Will be skipped
              </span>
            </div>

            <div className="bg-white p-4 rounded-2xl border border-indigo-200/90 shadow-sm bg-indigo-50/20">
              <span className="text-[10px] font-bold text-[#3C3489] uppercase tracking-wider block flex items-center justify-between">
                Already in DB (Any Model)
                {checkingDb && <span className="animate-spin text-xs">🌀</span>}
              </span>
              <div className="text-2xl font-extrabold text-[#3C3489] mt-1">
                {metrics.alreadyInDb}
              </div>
              <span className="text-[11px] text-indigo-600/80 mt-0.5 block font-medium">
                {skipExisting ? "Skipped safely across DB" : "Flagged"}
              </span>
            </div>

          </div>

          {/* Import Error Message */}
          {importError && (
            <div className="p-4 rounded-2xl bg-rose-50 border border-rose-200 text-rose-800 text-xs flex items-start gap-3">
              <AlertCircle size={18} className="text-rose-600 shrink-0 mt-0.5" />
              <div className="flex-1">
                <span className="font-bold block mb-0.5">Import Error</span>
                <span>{importError}</span>
              </div>
            </div>
          )}

          {/* Table Container */}
          <div className="bg-white rounded-2xl border border-slate-200/90 shadow-sm overflow-hidden flex flex-col">
            
            {/* Table Header Controls */}
            <div className="p-4 border-b border-slate-200 flex flex-col sm:flex-row sm:items-center justify-between gap-3 bg-slate-50/60">
              <div className="flex flex-wrap items-center gap-2">
                <Barcode size={18} className="text-[#3C3489]" />
                <h3 className="font-bold text-slate-900 text-sm">
                  Parsed Serials Preview
                </h3>
                <span className="text-xs text-slate-500 font-medium">
                  ({filteredPreviewRows.length} showing)
                </span>

                {deletedRowIds.size > 0 && (
                  <div className="flex items-center gap-1.5 ml-2">
                    <span className="text-[11px] font-semibold text-rose-700 bg-rose-50 border border-rose-200 px-2 py-0.5 rounded-full">
                      {deletedRowIds.size} deleted
                    </span>
                    <button
                      type="button"
                      onClick={handleRestoreDeleted}
                      className="flex items-center gap-1 text-[11px] font-bold text-[#3C3489] hover:text-[#322B73] hover:underline bg-indigo-50 hover:bg-indigo-100/70 border border-indigo-200 px-2 py-0.5 rounded-lg transition-all cursor-pointer"
                      title="Restore all deleted rows back to preview"
                    >
                      <Undo2 size={11} />
                      Restore All
                    </button>
                  </div>
                )}
              </div>

              {/* Filter Tabs */}
              <div className="flex items-center gap-1 bg-white p-1 rounded-xl border border-slate-200 text-xs">
                <button
                  onClick={() => setPreviewFilter("all")}
                  className={`px-2.5 py-1 rounded-lg font-medium transition-all ${
                    previewFilter === "all"
                      ? "bg-[#3C3489] text-white"
                      : "text-slate-600 hover:text-slate-900"
                  }`}
                >
                  All ({parsedRows.length})
                </button>
                <button
                  onClick={() => setPreviewFilter("ready")}
                  className={`px-2.5 py-1 rounded-lg font-medium transition-all ${
                    previewFilter === "ready"
                      ? "bg-emerald-600 text-white"
                      : "text-slate-600 hover:text-slate-900"
                  }`}
                >
                  Ready ({metrics.readyToImport})
                </button>
                <button
                  onClick={() => setPreviewFilter("existing")}
                  className={`px-2.5 py-1 rounded-lg font-medium transition-all ${
                    previewFilter === "existing"
                      ? "bg-indigo-600 text-white"
                      : "text-slate-600 hover:text-slate-900"
                  }`}
                >
                  In DB ({metrics.alreadyInDb})
                </button>
                <button
                  onClick={() => setPreviewFilter("duplicates")}
                  className={`px-2.5 py-1 rounded-lg font-medium transition-all ${
                    previewFilter === "duplicates"
                      ? "bg-amber-600 text-white"
                      : "text-slate-600 hover:text-slate-900"
                  }`}
                >
                  Dupes ({metrics.inFileDuplicates})
                </button>
              </div>
            </div>

            {/* Quick Actions & Selection Bar */}
            {selectedRowIds.size > 0 ? (
              <div className="px-4 py-2 bg-rose-50/80 border-b border-rose-200 flex items-center justify-between text-xs">
                <div className="flex items-center gap-2">
                  <span className="font-bold text-rose-800">
                    {selectedRowIds.size} row{selectedRowIds.size > 1 ? "s" : ""} selected
                  </span>
                  <span className="text-slate-400">&bull;</span>
                  <span className="text-slate-500">Ready to remove from this import batch</span>
                </div>
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={handleDeleteSelected}
                    className="flex items-center gap-1.5 px-3 py-1 rounded-lg bg-rose-600 text-white font-bold hover:bg-rose-700 shadow-sm transition-all cursor-pointer"
                  >
                    <Trash2 size={13} />
                    Delete Selected ({selectedRowIds.size})
                  </button>
                  <button
                    type="button"
                    onClick={() => setSelectedRowIds(new Set())}
                    className="px-2.5 py-1 text-slate-600 hover:text-slate-900 font-medium cursor-pointer"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            ) : (
              (metrics.inFileDuplicates > 0 || metrics.alreadyInDb > 0 || metrics.invalidCount > 0) && (
                <div className="px-4 py-1.5 bg-slate-50 border-b border-slate-100 flex flex-wrap items-center justify-between gap-2 text-xs">
                  <span className="text-[11px] font-medium text-slate-500">
                    Quick clean options:
                  </span>
                  <div className="flex flex-wrap items-center gap-2">
                    {metrics.inFileDuplicates > 0 && (
                      <button
                        type="button"
                        onClick={handleDeleteDuplicates}
                        className="flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-lg border border-amber-200 bg-amber-50 text-amber-800 hover:bg-amber-100 font-medium transition-all cursor-pointer"
                        title="Delete all in-sheet duplicate rows"
                      >
                        <Trash2 size={11} />
                        Delete {metrics.inFileDuplicates} Dupes
                      </button>
                    )}
                    {metrics.alreadyInDb > 0 && (
                      <button
                        type="button"
                        onClick={handleDeleteExistingInDb}
                        className="flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-lg border border-indigo-200 bg-indigo-50 text-[#3C3489] hover:bg-indigo-100 font-medium transition-all cursor-pointer"
                        title="Delete all serials that already exist in database"
                      >
                        <Trash2 size={11} />
                        Delete {metrics.alreadyInDb} in DB
                      </button>
                    )}
                    {metrics.invalidCount > 0 && (
                      <button
                        type="button"
                        onClick={handleDeleteInvalid}
                        className="flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-lg border border-rose-200 bg-rose-50 text-rose-800 hover:bg-rose-100 font-medium transition-all cursor-pointer"
                        title="Delete all invalid rows"
                      >
                        <Trash2 size={11} />
                        Delete {metrics.invalidCount} Invalid
                      </button>
                    )}
                  </div>
                </div>
              )
            )}

            {/* Quick Filter Search */}
            <div className="px-4 py-2 border-b border-slate-100 flex items-center gap-2">
              <Search size={14} className="text-slate-400 shrink-0" />
              <input
                type="text"
                placeholder="Filter serials or models in preview..."
                value={previewSearch}
                onChange={(e) => setPreviewSearch(e.target.value)}
                className="w-full text-xs bg-transparent border-none focus:outline-none text-slate-800"
              />
              {previewSearch && (
                <button
                  onClick={() => setPreviewSearch("")}
                  className="text-xs text-slate-400 hover:text-slate-600"
                >
                  Clear
                </button>
              )}
            </div>

            {/* Table Rows */}
            <div className="overflow-x-auto max-h-[460px] overflow-y-auto">
              <table className="w-full text-left border-collapse text-xs">
                <thead className="bg-slate-50/80 sticky top-0 z-10 border-b border-slate-200 text-slate-600 uppercase text-[10px] tracking-wider font-bold">
                  <tr>
                    <th className="py-2.5 px-3 w-8 text-center">
                      <input
                        type="checkbox"
                        checked={filteredPreviewRows.length > 0 && filteredPreviewRows.every((r) => selectedRowIds.has(r.id))}
                        onChange={handleToggleSelectAll}
                        className="w-3.5 h-3.5 rounded text-[#3C3489] focus:ring-[#3C3489] border-slate-300 cursor-pointer"
                        title="Select / Deselect all visible rows"
                      />
                    </th>
                    <th className="py-2.5 px-3 w-10 text-center">Row</th>
                    <th className="py-2.5 px-3">Serial Number</th>
                    <th className="py-2.5 px-3">Model / Product</th>
                    <th className="py-2.5 px-3">Unit</th>
                    <th className="py-2.5 px-3">DB Status</th>
                    <th className="py-2.5 px-3 text-right">Status</th>
                    <th className="py-2.5 px-3 w-12 text-center">Delete</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {filteredPreviewRows.length === 0 ? (
                    <tr>
                      <td colSpan={8} className="py-12 text-center text-slate-400">
                        {file ? "No serial rows match your search/filter criteria." : "Please upload a spreadsheet to preview extracted serial numbers."}
                      </td>
                    </tr>
                  ) : (
                    filteredPreviewRows.map((row) => {
                      const isReady = row.isValid && !row.isInFileDuplicate && (!row.dbStatus?.exists || !skipExisting);
                      return (
                        <tr
                          key={row.id}
                          className={`hover:bg-slate-50/80 transition-colors ${
                            !row.isValid
                              ? "bg-rose-50/30"
                              : row.isInFileDuplicate
                              ? "bg-amber-50/20"
                              : row.dbStatus?.exists
                              ? "bg-indigo-50/20"
                              : ""
                          }`}
                        >
                          <td className="py-2.5 px-3 text-center">
                            <input
                              type="checkbox"
                              checked={selectedRowIds.has(row.id)}
                              onChange={() => handleToggleSelectRow(row.id)}
                              className="w-3.5 h-3.5 rounded text-[#3C3489] focus:ring-[#3C3489] border-slate-300 cursor-pointer"
                            />
                          </td>
                          <td className="py-2.5 px-3 text-center text-slate-400 font-mono text-[11px]">
                            {row.rowIndex}
                          </td>
                          <td className="py-2.5 px-3 font-mono font-bold text-slate-900 tracking-wider">
                            {row.serialNumber}
                          </td>
                          <td className="py-2.5 px-3">
                            {row.matchedProduct ? (
                              <div>
                                <span className="font-semibold text-slate-800">
                                  {row.matchedProduct.brand} {row.matchedProduct.model}
                                </span>
                                {row.matchedProduct.category_name && (
                                  <span className="text-[10px] text-slate-400 block">
                                    {row.matchedProduct.category_name}
                                  </span>
                                )}
                              </div>
                            ) : (
                              <span className="text-amber-600 font-medium text-[11px]">
                                {row.extractedModel ? `Unmatched: ${row.extractedModel}` : "No product selected"}
                              </span>
                            )}
                          </td>
                          <td className="py-2.5 px-3">
                            <span className={`inline-block px-2 py-0.5 rounded text-[10px] font-semibold uppercase ${
                              row.extractedUnitType === "indoor"
                                ? "bg-sky-100 text-sky-800 border border-sky-200"
                                : row.extractedUnitType === "outdoor"
                                ? "bg-amber-100 text-amber-800 border border-amber-200"
                                : "bg-slate-100 text-slate-700"
                            }`}>
                              {row.extractedUnitType || "single"}
                            </span>
                          </td>
                          <td className="py-2.5 px-3">
                            {row.dbStatus?.exists ? (
                              <div className="space-y-0.5">
                                <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-indigo-100 text-[#3C3489] border border-indigo-200">
                                  <Database size={10} />
                                  Already in DB ({row.dbStatus.status_label || row.dbStatus.status || "Exists"})
                                </span>
                                {row.dbStatus.model && (
                                  <span className="text-[10px] text-slate-500 font-medium block">
                                    Existing: <span className="font-semibold text-slate-700">{row.dbStatus.brand} {row.dbStatus.model}</span>
                                  </span>
                                )}
                                {row.matchedProduct && row.dbStatus.model && row.matchedProduct.model.trim().toUpperCase() !== row.dbStatus.model.trim().toUpperCase() && (
                                  <span className="inline-block text-[9px] font-bold text-amber-800 bg-amber-50 border border-amber-200 px-1.5 py-0.5 rounded">
                                    ⚠️ Different model in DB ({row.dbStatus.brand} {row.dbStatus.model})
                                  </span>
                                )}
                              </div>
                            ) : (
                              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-100 text-emerald-800 border border-emerald-200">
                                <Sparkles size={10} />
                                New Unit
                              </span>
                            )}
                          </td>
                          <td className="py-2.5 px-3 text-right">
                            {isReady ? (
                              <span className="inline-block px-2 py-0.5 rounded font-bold text-[10px] bg-emerald-50 text-emerald-700 border border-emerald-200">
                                Will Import
                              </span>
                            ) : row.isInFileDuplicate ? (
                              <span className="inline-block px-2 py-0.5 rounded font-bold text-[10px] bg-amber-50 text-amber-700 border border-amber-200">
                                Skip Dupe
                              </span>
                            ) : row.dbStatus?.exists ? (
                              <span className="inline-block px-2 py-0.5 rounded font-bold text-[10px] bg-slate-100 text-slate-600">
                                Skip Existing
                              </span>
                            ) : (
                              <span className="inline-block px-2 py-0.5 rounded font-bold text-[10px] bg-rose-50 text-rose-700 border border-rose-200">
                                {row.invalidReason || "Invalid"}
                              </span>
                            )}
                          </td>
                          <td className="py-2.5 px-3 text-center">
                            <button
                              type="button"
                              onClick={() => handleDeleteRow(row.id)}
                              className="p-1.5 rounded-lg text-slate-400 hover:text-rose-600 hover:bg-rose-50 transition-colors cursor-pointer"
                              title="Delete this serial from preview"
                            >
                              <Trash2 size={14} />
                            </button>
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>

            {/* Bottom Actions Bar */}
            <div className="p-4 border-t border-slate-200 bg-slate-50 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
              <div className="text-xs text-slate-600">
                <span className="font-bold text-slate-900">{metrics.readyToImport}</span> serial numbers will be inwarded to warehouse stock.
                {deletedRowIds.size > 0 && (
                  <span className="text-slate-400 ml-1.5">
                    ({deletedRowIds.size} row{deletedRowIds.size > 1 ? "s" : ""} deleted)
                  </span>
                )}
              </div>

              <button
                disabled={metrics.readyToImport === 0 || isImporting || (mappingMode === "single" && !selectedProductId)}
                onClick={handleExecuteImport}
                className="flex items-center justify-center gap-2 px-6 py-2.5 rounded-xl bg-[#3C3489] text-white font-bold text-xs hover:bg-[#322B73] transition-all shadow-md shadow-[#3C3489]/20 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {isImporting ? (
                  <>
                    <span className="animate-spin">🌀</span>
                    Importing Serials...
                  </>
                ) : (
                  <>
                    <ShieldCheck size={16} />
                    Import {metrics.readyToImport} Serials Now
                  </>
                )}
              </button>
            </div>

          </div>

        </div>

      </div>

      {/* Post-Import Result Modal */}
      {importResult && (
        <Modal
          isOpen={isResultModalOpen}
          onClose={() => setIsResultModalOpen(false)}
          title="Import Completed Successfully"
          maxWidth="2xl"
        >
          <div className="space-y-5">
            <div className="flex items-center gap-3 p-4 rounded-2xl bg-emerald-50 border border-emerald-200 text-emerald-900">
              <div className="p-2.5 rounded-full bg-emerald-500 text-white shrink-0">
                <Check size={20} />
              </div>
              <div>
                <h4 className="font-bold text-sm">
                  {importResult.imported_count} Serial Numbers Successfully Inwarded!
                </h4>
                <p className="text-xs text-emerald-700 mt-0.5">
                  The serial numbers have been saved to inventory and product stock counts updated.
                </p>
              </div>
            </div>

            {/* Quick Metrics */}
            <div className="grid grid-cols-3 gap-3">
              <div className="p-3 rounded-xl bg-slate-50 border border-slate-200 text-center">
                <span className="text-[10px] font-bold text-slate-400 uppercase">Total Processed</span>
                <p className="text-lg font-extrabold text-slate-800">{importResult.total_processed}</p>
              </div>
              <div className="p-3 rounded-xl bg-emerald-50 border border-emerald-200 text-center">
                <span className="text-[10px] font-bold text-emerald-700 uppercase">Newly Created</span>
                <p className="text-lg font-extrabold text-emerald-700">{importResult.imported_count}</p>
              </div>
              <div className="p-3 rounded-xl bg-slate-50 border border-slate-200 text-center">
                <span className="text-[10px] font-bold text-slate-400 uppercase">Skipped</span>
                <p className="text-lg font-extrabold text-slate-700">
                  {importResult.skipped_existing_count + importResult.skipped_invalid_count}
                </p>
              </div>
            </div>

            {/* Products Updated Breakdown */}
            {importResult.products_updated && importResult.products_updated.length > 0 && (
              <div className="space-y-2">
                <h5 className="text-xs font-bold text-slate-700 uppercase tracking-wider">
                  Updated Product Stock
                </h5>
                <div className="border border-slate-200 rounded-xl overflow-hidden divide-y divide-slate-100">
                  {importResult.products_updated.map((p, idx) => (
                    <div key={idx} className="flex items-center justify-between p-3 bg-white text-xs">
                      <div>
                        <span className="font-bold text-slate-900">{p.model}</span>
                        <span className="text-slate-500 ml-1.5">({p.product_name})</span>
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="text-emerald-600 font-bold">+{p.added_count} Added</span>
                        <span className="text-slate-400">&bull;</span>
                        <span className="font-semibold text-slate-700">New Stock: {p.new_stock}</span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Modal Actions */}
            <div className="pt-4 border-t border-slate-200 flex flex-wrap items-center justify-end gap-3">
              <button
                onClick={() => {
                  setIsResultModalOpen(false);
                  handleReset();
                }}
                className="px-4 py-2 rounded-xl border border-slate-200 bg-white text-slate-700 text-xs font-semibold hover:bg-slate-50"
              >
                Import Another Sheet
              </button>
              <button
                onClick={() => navigate("/stock")}
                className="px-4 py-2 rounded-xl border border-slate-200 bg-white text-slate-700 text-xs font-semibold hover:bg-slate-50"
              >
                Go to Stock
              </button>
              <button
                onClick={() => navigate("/serials")}
                className="px-4 py-2 rounded-xl bg-[#3C3489] text-white text-xs font-bold hover:bg-[#322B73]"
              >
                View in Serials List
              </button>
            </div>
          </div>
        </Modal>
      )}

    </div>
  );
};

export default ImportSerialsPage;
