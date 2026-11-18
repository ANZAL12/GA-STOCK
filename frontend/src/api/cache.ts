interface CacheEntry<T = unknown> {
  data: T;
  timestamp: number;
  ttlMs: number;
}

const STORAGE_PREFIX = "ga_cache_v1:";
const DEFAULT_TTL_MS = 5 * 60 * 1000; // 5 minutes
const MAX_MEMORY_ENTRIES = 120;
const MAX_STORAGE_BYTES = 400 * 1024; // 400 KB per entry cap for sessionStorage

const memoryCache = new Map<string, CacheEntry>();

const NON_CACHEABLE_PATTERNS = [
  "/auth/",
  "/print/",
  "/export",
  "format=csv",
  "format=xlsx",
  "format=pdf",
];

export function isCacheableEndpoint(endpoint: string): boolean {
  const lower = endpoint.toLowerCase();
  return !NON_CACHEABLE_PATTERNS.some((pattern) => lower.includes(pattern));
}

function isFresh(entry: CacheEntry): boolean {
  return Date.now() - entry.timestamp < entry.ttlMs;
}

function readFromSessionStorage<T>(endpoint: string): CacheEntry<T> | null {
  try {
    const raw = sessionStorage.getItem(`${STORAGE_PREFIX}${endpoint}`);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as CacheEntry<T>;
    if (!parsed || typeof parsed.timestamp !== "number" || typeof parsed.ttlMs !== "number") {
      sessionStorage.removeItem(`${STORAGE_PREFIX}${endpoint}`);
      return null;
    }
    if (!isFresh(parsed)) {
      sessionStorage.removeItem(`${STORAGE_PREFIX}${endpoint}`);
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

function writeToSessionStorage<T>(endpoint: string, entry: CacheEntry<T>): void {
  try {
    const serialized = JSON.stringify(entry);
    if (serialized.length > MAX_STORAGE_BYTES) return;
    sessionStorage.setItem(`${STORAGE_PREFIX}${endpoint}`, serialized);
  } catch {
    // Ignore sessionStorage quota or private-mode errors
  }
}

export function getCachedResponse<T>(endpoint: string): T | null {
  if (!isCacheableEndpoint(endpoint)) return null;

  const mem = memoryCache.get(endpoint);
  if (mem) {
    if (isFresh(mem)) {
      // Refresh LRU position
      memoryCache.delete(endpoint);
      memoryCache.set(endpoint, mem);
      return mem.data as T;
    }
    memoryCache.delete(endpoint);
  }

  const stored = readFromSessionStorage<T>(endpoint);
  if (stored) {
    memoryCache.set(endpoint, stored);
    return stored.data;
  }

  return null;
}

export function setCachedResponse<T>(
  endpoint: string,
  data: T,
  ttlMs: number = DEFAULT_TTL_MS
): void {
  if (!isCacheableEndpoint(endpoint)) return;

  const entry: CacheEntry<T> = {
    data,
    timestamp: Date.now(),
    ttlMs,
  };

  if (memoryCache.has(endpoint)) {
    memoryCache.delete(endpoint);
  } else if (memoryCache.size >= MAX_MEMORY_ENTRIES) {
    const oldestKey = memoryCache.keys().next().value;
    if (oldestKey) memoryCache.delete(oldestKey);
  }

  memoryCache.set(endpoint, entry);
  writeToSessionStorage(endpoint, entry);
}

export function invalidateCachePrefixes(prefixes: string[]): void {
  if (prefixes.length === 0) return;

  for (const key of Array.from(memoryCache.keys())) {
    if (prefixes.some((prefix) => key.startsWith(prefix))) {
      memoryCache.delete(key);
    }
  }

  try {
    const toRemove: string[] = [];
    for (let i = 0; i < sessionStorage.length; i++) {
      const storageKey = sessionStorage.key(i);
      if (!storageKey || !storageKey.startsWith(STORAGE_PREFIX)) continue;
      const endpoint = storageKey.slice(STORAGE_PREFIX.length);
      if (prefixes.some((prefix) => endpoint.startsWith(prefix))) {
        toRemove.push(storageKey);
      }
    }
    for (const k of toRemove) {
      sessionStorage.removeItem(k);
    }
  } catch {
    // Ignore sessionStorage errors
  }
}

export function clearApiCache(): void {
  memoryCache.clear();
  try {
    const toRemove: string[] = [];
    for (let i = 0; i < sessionStorage.length; i++) {
      const storageKey = sessionStorage.key(i);
      if (storageKey && storageKey.startsWith(STORAGE_PREFIX)) {
        toRemove.push(storageKey);
      }
    }
    for (const k of toRemove) {
      sessionStorage.removeItem(k);
    }
  } catch {
    // Ignore sessionStorage errors
  }
}

export function invalidateCacheForMutation(endpoint: string): void {
  const path = endpoint.split("?")[0];
  if (
    path.startsWith("/outward") ||
    path.startsWith("/inward") ||
    path.startsWith("/returns")
  ) {
    invalidateCachePrefixes(["/outward", "/serials", "/products", "/reports", "/shops", "/audit"]);
  } else if (path.startsWith("/products") || path.startsWith("/categories")) {
    invalidateCachePrefixes(["/products", "/categories", "/reports", "/serials", "/audit"]);
  } else if (path.startsWith("/shops")) {
    invalidateCachePrefixes(["/shops", "/reports", "/outward", "/audit"]);
  } else if (path.startsWith("/serials")) {
    invalidateCachePrefixes(["/serials", "/products", "/reports", "/outward", "/audit"]);
  } else if (path.startsWith("/users")) {
    invalidateCachePrefixes(["/users", "/audit"]);
  } else if (path.startsWith("/devices")) {
    invalidateCachePrefixes(["/devices", "/reports", "/audit"]);
  } else if (path.startsWith("/settings")) {
    invalidateCachePrefixes(["/settings"]);
  } else if (!path.startsWith("/auth/")) {
    clearApiCache();
  }
}

export function invalidateCacheForWebSocketEvent(event: string): void {
  switch (event) {
    case "stock_updated":
    case "serial_created":
    case "serial_updated":
    case "serial_deleted":
      invalidateCachePrefixes(["/reports", "/products", "/serials", "/outward", "/shops", "/audit"]);
      break;
    case "product_created":
    case "product_updated":
    case "product_deleted":
      invalidateCachePrefixes(["/products", "/reports", "/serials", "/audit"]);
      break;
    case "category_created":
    case "category_updated":
    case "category_deleted":
      invalidateCachePrefixes(["/categories", "/products", "/reports", "/audit"]);
      break;
    case "shop_created":
    case "shop_updated":
    case "shop_deleted":
      invalidateCachePrefixes(["/shops", "/reports", "/outward", "/audit"]);
      break;
    case "device_registered":
    case "device_approved":
    case "device_deactivated":
      invalidateCachePrefixes(["/devices", "/reports", "/audit"]);
      break;
    case "settings_updated":
      invalidateCachePrefixes(["/settings"]);
      break;
    default:
      break;
  }
}

