/**
 * GA STOCK - Fast Browser Cache & Real-Time Sync Engine
 * 
 * - Prevents repetitive network fetching & spinners when navigating between pages.
 * - Stale-While-Revalidate (SWR): renders cached data instantly, updates in background.
 * - Instant WebSocket Sync: automatically invalidates or updates cached resources on live events.
 * - Automatic Mutation Invalidation: POST, PUT, DELETE operations purge related caches.
 */

interface CacheEntry<T = any> {
  data: T;
  timestamp: number;
}

type CacheListener = (key: string, data?: any) => void;

class ApiCache {
  private cache = new Map<string, CacheEntry>();
  private inFlight = new Map<string, Promise<any>>();
  private listeners = new Set<CacheListener>();

  // 3 minutes default TTL for static and master catalogs (kept 100% fresh via SWR & WebSocket events)
  private defaultTtlMs = 3 * 60 * 1000;

  /**
   * Retrieves data from in-memory cache or sessionStorage if fresh.
   */
  get<T>(key: string, maxAgeMs = this.defaultTtlMs): T | null {
    const entry = this.cache.get(key);
    if (entry) {
      if (Date.now() - entry.timestamp <= maxAgeMs) {
        return entry.data as T;
      }
      // Expired in memory
      this.cache.delete(key);
    }

    // Try restoring from sessionStorage
    try {
      const stored = sessionStorage.getItem(`ga_cache_${key}`);
      if (stored) {
        const parsed = JSON.parse(stored) as CacheEntry<T>;
        if (Date.now() - parsed.timestamp <= maxAgeMs) {
          this.cache.set(key, parsed);
          return parsed.data;
        }
        sessionStorage.removeItem(`ga_cache_${key}`);
      }
    } catch {
      // ignore storage access errors
    }

    return null;
  }

  /**
   * Check if fresh cached data is already available.
   */
  hasValid(key: string, maxAgeMs = this.defaultTtlMs): boolean {
    return this.get(key, maxAgeMs) !== null;
  }

  /**
   * Stores data in memory and sessionStorage.
   */
  set<T>(key: string, data: T): void {
    const entry: CacheEntry<T> = { data, timestamp: Date.now() };
    this.cache.set(key, entry);

    // Save lightweight serializable responses to sessionStorage
    try {
      if (data && typeof data === "object") {
        sessionStorage.setItem(`ga_cache_${key}`, JSON.stringify(entry));
      }
    } catch {
      // ignore sessionStorage quota errors
    }

    this.notify(key, data);
  }

  getInFlight<T>(key: string): Promise<T> | undefined {
    return this.inFlight.get(key);
  }

  setInFlight<T>(key: string, promise: Promise<T>): void {
    this.inFlight.set(key, promise);
  }

  clearInFlight(key: string): void {
    this.inFlight.delete(key);
  }

  /**
   * Invalidate exact key or any key matching a prefix.
   */
  invalidate(patternOrKey: string): void {
    const isWildcard = patternOrKey.endsWith("*");
    const cleanPattern = patternOrKey.replace(/\*$/, "");

    for (const key of Array.from(this.cache.keys())) {
      if (key === cleanPattern || key.startsWith(cleanPattern) || (isWildcard && key.includes(cleanPattern))) {
        this.cache.delete(key);
        try {
          sessionStorage.removeItem(`ga_cache_${key}`);
        } catch {}
      }
    }

    // Clean sessionStorage matching keys
    try {
      for (let i = sessionStorage.length - 1; i >= 0; i--) {
        const k = sessionStorage.key(i);
        if (k && k.startsWith("ga_cache_") && (k.includes(cleanPattern) || k.startsWith(`ga_cache_${cleanPattern}`))) {
          sessionStorage.removeItem(k);
        }
      }
    } catch {}

    this.notify(cleanPattern, null);
  }

  /**
   * Purge the entire cache (e.g. on logout or master reset).
   */
  invalidateAll(): void {
    this.cache.clear();
    this.inFlight.clear();
    try {
      for (let i = sessionStorage.length - 1; i >= 0; i--) {
        const k = sessionStorage.key(i);
        if (k && k.startsWith("ga_cache_")) {
          sessionStorage.removeItem(k);
        }
      }
    } catch {}
    this.notify("*", null);
  }

  /**
   * Instantly synchronizes cache state based on incoming WebSocket events.
   */
  handleWsEvent(event: string, _data?: any): void {
    switch (event) {
      case "stock_updated":
        this.invalidate("/products");
        this.invalidate("/categories");
        this.invalidate("/outward/bills");
        this.invalidate("/reports");
        this.invalidate("/serials");
        break;

      case "product_created":
      case "product_updated":
      case "product_deleted":
        this.invalidate("/products");
        this.invalidate("/reports");
        break;

      case "category_created":
      case "category_updated":
      case "category_deleted":
        this.invalidate("/categories");
        this.invalidate("/products");
        break;

      case "shop_created":
      case "shop_updated":
      case "shop_deleted":
        this.invalidate("/shops");
        break;

      case "voucher_created":
      case "voucher_updated":
      case "voucher_processed":
        this.invalidate("/tally/sales-vouchers");
        this.invalidate("/outward/bills");
        this.invalidate("/reports");
        break;

      case "serial_registered":
      case "serial_updated":
      case "serial_deleted":
        this.invalidate("/serials");
        this.invalidate("/products");
        break;

      case "tally_settings_updated":
        this.invalidate("/tally/status");
        break;

      default:
        if (event.includes("stock") || event.includes("product")) {
          this.invalidate("/products");
        } else if (event.includes("shop")) {
          this.invalidate("/shops");
        }
        break;
    }
  }

  /**
   * Subscribe to cache invalidation and update notifications.
   */
  subscribe(listener: CacheListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private notify(key: string, data?: any): void {
    this.listeners.forEach((l) => {
      try {
        l(key, data);
      } catch {}
    });
  }
}

export const apiCache = new ApiCache();
