import { apiRequest } from "../api/client";

export const BILL_EDIT_DELETE_SETTING_KEY = "feature_bill_edit_delete_enabled";
export const SETTINGS_CHANGED_EVENT = "ga_stock_settings_changed";

export interface AppSettings {
  bill_edit_delete_enabled: boolean;
}

export function isBillEditDeleteEnabled(): boolean {
  try {
    return localStorage.getItem(BILL_EDIT_DELETE_SETTING_KEY) === "true";
  } catch {
    return false;
  }
}

export function setBillEditDeleteEnabled(enabled: boolean): void {
  try {
    localStorage.setItem(BILL_EDIT_DELETE_SETTING_KEY, String(enabled));
    window.dispatchEvent(new Event(SETTINGS_CHANGED_EVENT));
  } catch {
    // Ignore storage quota / privacy mode errors
  }
}

export async function fetchBillEditDeleteSetting(): Promise<boolean> {
  try {
    const res = await apiRequest<AppSettings>("/settings");
    const enabled = Boolean(res?.bill_edit_delete_enabled);
    setBillEditDeleteEnabled(enabled);
    return enabled;
  } catch {
    // Fallback to localStorage if backend endpoint is unavailable
    return isBillEditDeleteEnabled();
  }
}

export async function saveBillEditDeleteSetting(enabled: boolean): Promise<boolean> {
  // Update local cache immediately for instant UI response
  setBillEditDeleteEnabled(enabled);
  try {
    const res = await apiRequest<AppSettings>("/settings", {
      method: "PATCH",
      body: JSON.stringify({ bill_edit_delete_enabled: enabled }),
    });
    const persisted = Boolean(res?.bill_edit_delete_enabled);
    setBillEditDeleteEnabled(persisted);
    return persisted;
  } catch {
    // Keep local toggle active even if backend has not been restarted yet
    return enabled;
  }
}
