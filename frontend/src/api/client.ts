import {
  clearApiCache,
  getCachedResponse,
  invalidateCacheForMutation,
  invalidateCachePrefixes,
  isCacheableEndpoint,
  setCachedResponse,
} from "./cache";

export { clearApiCache, getCachedResponse, invalidateCachePrefixes };

const API_BASE = "/api/v1";
const inFlightRequests = new Map<string, Promise<unknown>>();

export interface ApiRequestOptions extends RequestInit {
  /** Cache GET JSON responses in browser cache (defaults to true for GET). */
  cacheResponse?: boolean;
  /** Bypass browser cache and fetch fresh data from the server. */
  forceRefresh?: boolean;
  /** Custom TTL in milliseconds for cached GET responses. */
  cacheTtlMs?: number;
}

export async function apiRequest<T>(
  endpoint: string,
  options: ApiRequestOptions = {}
): Promise<T> {
  const {
    cacheResponse,
    forceRefresh = false,
    cacheTtlMs,
    ...fetchOptions
  } = options;

  const method = (fetchOptions.method || "GET").toUpperCase();
  const shouldCache =
    method === "GET" &&
    cacheResponse !== false &&
    isCacheableEndpoint(endpoint);

  if (shouldCache && !forceRefresh) {
    const cached = getCachedResponse<T>(endpoint);
    if (cached !== null) {
      return cached;
    }

    const existing = inFlightRequests.get(endpoint);
    if (existing) {
      return existing as Promise<T>;
    }
  }

  const execute = async (): Promise<T> => {
    const token = localStorage.getItem("access_token");
    const isFormData = fetchOptions.body instanceof FormData;
    const headers: Record<string, string> = {
      ...(isFormData ? {} : { "Content-Type": "application/json" }),
      ...((fetchOptions.headers as Record<string, string>) || {}),
    };

    if (token) {
      headers["Authorization"] = `Bearer ${token}`;
    }

    const url = `${API_BASE}${endpoint}`;
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
            const data = await refreshRes.json();
            localStorage.setItem("access_token", data.access_token);
            headers["Authorization"] = `Bearer ${data.access_token}`;
            const retryRes = await fetch(url, { ...fetchOptions, headers });
            if (retryRes.ok) {
              const retryContentType = retryRes.headers.get("content-type");
              if (
                retryContentType &&
                (retryContentType.includes("application/pdf") ||
                  retryContentType.includes("spreadsheetml") ||
                  retryContentType.includes("text/csv"))
              ) {
                return retryRes.blob() as unknown as T;
              }
              const retryData = (await retryRes.json()) as T;
              if (shouldCache) {
                setCachedResponse(endpoint, retryData, cacheTtlMs);
              } else if (method !== "GET") {
                invalidateCacheForMutation(endpoint);
              }
              return retryData;
            }
          }
        } catch (e) {
          console.error("Token refresh failed", e);
        }
      }
      // Logout if refresh fails or unauthorized
      clearApiCache();
      localStorage.removeItem("access_token");
      localStorage.removeItem("refresh_token");
      localStorage.removeItem("user");
      window.location.href = "/login";
      throw new Error("Session expired. Please log in again.");
    }

    if (!response.ok) {
      let errorDetail = "An unexpected error occurred.";
      try {
        const errorJson = await response.json();
        errorDetail = errorJson.detail || errorDetail;
      } catch {
        // ignore
      }
      throw new Error(errorDetail);
    }

    // Handle blob/download if needed, otherwise json
    const contentType = response.headers.get("content-type");
    if (
      contentType &&
      (contentType.includes("application/pdf") ||
        contentType.includes("spreadsheetml") ||
        contentType.includes("text/csv"))
    ) {
      return response.blob() as unknown as T;
    }

    const result = (await response.json()) as T;

    if (shouldCache) {
      setCachedResponse(endpoint, result, cacheTtlMs);
    } else if (method !== "GET") {
      invalidateCacheForMutation(endpoint);
    }

    return result;
  };

  if (shouldCache) {
    const promise = execute().finally(() => {
      if (inFlightRequests.get(endpoint) === promise) {
        inFlightRequests.delete(endpoint);
      }
    });
    inFlightRequests.set(endpoint, promise);
    return promise;
  }

  return execute();
}
