export type UserRole = "admin" | "staff";

export interface User {
  id: string;
  username: string;
  full_name: string;
  role: UserRole;
  is_active: boolean;
  created_at: string;
}

export interface Device {
  id: string;
  device_uid: string;
  label?: string | null;
  approved_by_id?: string | null;
  approved_at?: string | null;
  is_active: boolean;
  created_at: string;
}

export interface Category {
  id: string;
  name: string;
  is_active: boolean;
  created_at: string;
  product_count: number;
}

export interface Product {
  id: string;
  name: string;
  sku?: string | null;
  category_id: string;
  category_name?: string | null;
  brand: string;
  model: string;
  size_capacity?: string | null;
  unit: string;
  serial_number_required: boolean;
  description?: string | null;
  opening_stock_qty: number;
  current_stock_qty: number;
  has_had_inward: boolean;
  is_active: boolean;
  out_of_stock_reminder: boolean;
  stock_status_label: string;
  created_at: string;
  updated_at: string;
}

export interface Shop {
  id: string;
  name: string;
  city: string;
  phone?: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
  total_dispatched_count: number;
}

export interface ShopDispatchedSerial {
  serial_text: string;
  product_id: string;
  product_name: string;
  brand: string;
  model: string;
  transaction_date: string;
  delivery_reference?: string | null;
  is_matched: boolean;
  is_flagged_for_review: boolean;
  status_label: string;
}

export interface NeedsAttentionPills {
  out_of_stock_models: number;
  flagged_outward_reviews: number;
  damaged_units: number;
  under_repair_units: number;
  pending_devices: number;
  all_clear: boolean;
}

export interface OverviewSummary {
  tracked_items_on_shelves: number;
  received_since_golive: number;
  inward_today: number;
  outward_today: number;
  recorded_only_today: number;
  needs_attention: NeedsAttentionPills;
}

export interface StockByModelItem {
  product_id: string;
  name: string;
  brand: string;
  model: string;
  category_name: string;
  sku?: string | null;
  available_count: number;
  dispatched_count: number;
  damaged_count: number;
  total_received: number;
  unmatched_dispatched_count: number;
  current_stock_qty: number;
  out_of_stock_reminder: boolean;
  reminder_label?: string | null;
}

export interface TodayTimelineItem {
  id: string;
  timestamp: string;
  action: string;
  serial_number: string;
  product_name: string;
  shop_name?: string | null;
  user_name: string;
  dot_color: "green" | "amber" | "red" | "indigo";
  description: string;
}

export interface SerialHistoryItem {
  id: string;
  created_at: string;
  action: string;
  from_status?: string | null;
  to_status?: string | null;
  shop_id?: string | null;
  shop_name?: string | null;
  shop_city?: string | null;
  is_matched?: boolean | null;
  user_name: string;
  remarks?: string | null;
}

export interface SerialDetail {
  serial_number: string;
  serial_number_id?: string | null;
  is_tracked: boolean;
  status?: string | null;
  product_id?: string | null;
  product_name?: string | null;
  brand?: string | null;
  model?: string | null;
  last_shop_id?: string | null;
  last_shop_name?: string | null;
  last_shop_city?: string | null;
  status_label: string;
  history: SerialHistoryItem[];
}

export interface AuditLogItem {
  id: string;
  created_at: string;
  user_id?: string | null;
  user_name?: string | null;
  device_id?: string | null;
  device_label?: string | null;
  action: string;
  entity_type: string;
  entity_id?: string | null;
  details?: Record<string, any> | null;
  ip_address?: string | null;
}

export interface StockOutReportItem {
  id: string;
  transaction_date: string;
  serial_number: string;
  product_name: string;
  brand: string;
  model: string;
  shop_name: string;
  shop_city: string;
  delivery_reference?: string | null;
  is_matched: boolean;
  status_label: string;
  dispatcher_name: string;
}

export interface DamagedReportItem {
  id: string;
  serial_number: string;
  product_name: string;
  brand: string;
  model: string;
  status: string;
  last_shop_name?: string | null;
  updated_at: string;
}