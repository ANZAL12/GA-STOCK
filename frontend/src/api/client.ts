import { apiCache } from "./cache";

const API_BASE = "/api/v1";

export interface ApiRequestOptions extends Omit<RequestInit, "cache"> {
  cache?: boolean | number;       // false to bypass cache, or number for custom TTL in ms
  forceRefresh?: boolean;         // if true, forces fresh network fetch and updates cache
  backgroundRevalidate?: boolean; // if true with cached data, fetches in background silently
}

export async function apiRequest<T>(
  endpoint: string,
  options: ApiRequestOptions = {}
): Promise<T> {
  const method = (options.method || "GET").toUpperCase();
  const isGet = method === "GET";
  const shouldCache = isGet && options.cache !== false;
  const maxAge = typeof options.cache === "number" ? options.cache : undefined;

  // 1. Fast Cache Hit for GET requests (Instant zero-lag page navigation + SWR background revalidate)
  if (shouldCache && !options.forceRefresh) {
    const cached = apiCache.get<T>(endpoint, maxAge);
    if (cached !== null) {
      // Revalidate in background to keep data in sync with database changes
      if (!apiCache.getInFlight<T>(endpoint)) {
        setTimeout(() => {
          apiRequest<T>(endpoint, { ...options, forceRefresh: true }).catch(() => {});
        }, 50);
      }
      return cached;
    }

    // Deduplicate in-flight requests for the exact same endpoint
    const inFlight = apiCache.getInFlight<T>(endpoint);
    if (inFlight) {
      return inFlight;
    }
  }

  // 2. Perform Fetch
  const token = localStorage.getItem("access_token");
  const isFormData = options.body instanceof FormData;
  const headers: Record<string, string> = {
    ...(isFormData ? {} : { "Content-Type": "application/json" }),
    ...(options.headers as Record<string, string> || {}),
  };

  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  const url = `${API_BASE}${endpoint}`;
  const { cache: _c, forceRefresh: _fr, backgroundRevalidate: _br, ...fetchOptions } = options;

  const fetchPromise = (async () => {
    try {
      const response = await fetch(url, {
        ...fetchOptions,
        headers,
      });

      if (response.status === 401) {
        // Attempt token refresh if refresh token exists
        const refreshToken = localStorage.getItem("refresh_token");
        if (refreshToken && !endpoint.includes("/auth/")) {
          try {
            const refreshRes = await fetch(`${API_BASE}/auth/refresh`, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ refresh_token: refreshToken }),
            });
            if (refreshRes.ok) {
              const refText = await refreshRes.text();
              let data: any = {};
              try { data = JSON.parse(refText); } catch {}
              if (data.access_token) {
                localStorage.setItem("access_token", data.access_token);
                headers["Authorization"] = `Bearer ${data.access_token}`;
                const retryRes = await fetch(url, { ...fetchOptions, headers });
                if (retryRes.ok) {
                  if (retryRes.status === 204) return {} as T;
                  const retryText = await retryRes.text();
                  let retryJson: any = {};
                  if (retryText && retryText.trim().length > 0) {
                    try {
                      retryJson = JSON.parse(retryText);
                    } catch {
                      retryJson = retryText;
                    }
                  }
                  if (shouldCache) {
                    apiCache.set(endpoint, retryJson);
                  }
                  return retryJson as T;
                }
              }
            }
          } catch (e) {
            console.error("Token refresh failed", e);
          }
        }
        // Logout if refresh fails or unauthorized
        apiCache.invalidateAll();
        localStorage.removeItem("access_token");
        localStorage.removeItem("refresh_token");
        localStorage.removeItem("user");
        window.location.href = "/login";
        throw new Error("Session expired. Please log in again.");
      }

      if (!response.ok) {
        let errorDetail = "An unexpected error occurred.";
        try {
          const errorText = await response.text();
          if (errorText && errorText.trim().length > 0) {
            try {
              const errorJson = JSON.parse(errorText);
              errorDetail = errorJson.detail || errorDetail;
            } catch {
              errorDetail = errorText.slice(0, 200);
            }
          }
        } catch {
          // ignore
        }
        throw new Error(errorDetail);
      }

      // Handle 204 No Content or empty responses
      if (response.status === 204) {
        if (!isGet) {
          autoInvalidateOnMutation(endpoint);
        }
        return {} as T;
      }

      // Handle blob/download if needed, otherwise json
      const contentType = response.headers.get("content-type");
      if (contentType && (contentType.includes("application/pdf") || contentType.includes("spreadsheetml") || contentType.includes("text/csv"))) {
        return (await response.blob()) as unknown as T;
      }

      const text = await response.text();
      let result: any = {};
      if (text && text.trim().length > 0) {
        try {
          result = JSON.parse(text);
        } catch {
          result = text;
        }
      }

      // Store in cache for GET requests
      if (shouldCache) {
        apiCache.set(endpoint, result);
      }

      // Automatically purge related caches on mutation operations
      if (!isGet) {
        autoInvalidateOnMutation(endpoint);
      }

      return result as T;
    } finally {
      if (shouldCache) {
        apiCache.clearInFlight(endpoint);
      }
    }
  })();

  if (shouldCache) {
    apiCache.setInFlight(endpoint, fetchPromise);
  }

  return fetchPromise;
}

function autoInvalidateOnMutation(endpoint: string) {
  if (endpoint.includes("/products")) {
    apiCache.invalidate("/products");
    apiCache.invalidate("/reports");
  }
  if (endpoint.includes("/categories")) {
    apiCache.invalidate("/categories");
    apiCache.invalidate("/products");
  }
  if (endpoint.includes("/shops")) {
    apiCache.invalidate("/shops");
  }
  if (endpoint.includes("/outward")) {
    apiCache.invalidate("/outward");
    apiCache.invalidate("/products");
    apiCache.invalidate("/serials");
    apiCache.invalidate("/reports");
  }
  if (endpoint.includes("/inward")) {
    apiCache.invalidate("/products");
    apiCache.invalidate("/serials");
    apiCache.invalidate("/reports");
  }
  if (endpoint.includes("/tally/sync")) {
    apiCache.invalidate("/products");
    apiCache.invalidate("/categories");
    apiCache.invalidate("/shops");
    apiCache.invalidate("/outward");
    apiCache.invalidate("/tally");
  }
  if (endpoint.includes("/tally/toggle-reading")) {
    apiCache.invalidate("/tally/status");
  }
  if (endpoint.includes("/serials")) {
    apiCache.invalidate("/serials");
    apiCache.invalidate("/products");
  }
  if (endpoint.includes("/devices")) {
    apiCache.invalidate("/devices");
  }
}
