const API_BASE = "/api/v1";

export async function apiRequest<T>(
  endpoint: string,
  options: RequestInit = {}
): Promise<T> {
  const token = localStorage.getItem("access_token");
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(options.headers as Record<string, string> || {}),
  };

  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  const url = `${API_BASE}${endpoint}`;
  const response = await fetch(url, {
    ...options,
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
          const retryRes = await fetch(url, { ...options, headers });
          if (retryRes.ok) {
            return retryRes.json();
          }
        }
      } catch (e) {
        console.error("Token refresh failed", e);
      }
    }
    // Logout if refresh fails or unauthorized
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
  if (contentType && (contentType.includes("application/pdf") || contentType.includes("spreadsheetml") || contentType.includes("text/csv"))) {
    return response.blob() as unknown as T;
  }

  return response.json();
}