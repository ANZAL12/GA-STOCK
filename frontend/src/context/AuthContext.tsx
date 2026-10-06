import React, { createContext, useContext, useState, useEffect } from "react";
import type { User } from "../types";
import { apiRequest } from "../api/client";

interface AuthContextType {
  user: User | null;
  token: string | null;
  isLoading: boolean;
  isAdmin: boolean;
  login: (username: string, password: string) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(() => {
    const saved = localStorage.getItem("user");
    return saved ? JSON.parse(saved) : null;
  });
  const [token, setToken] = useState<string | null>(() => localStorage.getItem("access_token"));
  const [isLoading, setIsLoading] = useState<boolean>(true);

  useEffect(() => {
    const verifyUser = async () => {
      const savedToken = localStorage.getItem("access_token");
      if (savedToken) {
        try {
          const profile = await apiRequest<User>("/auth/me");
          setUser(profile);
          localStorage.setItem("user", JSON.stringify(profile));
        } catch {
          setUser(null);
          setToken(null);
        }
      }
      setIsLoading(false);
    };

    verifyUser();
  }, []);

  const login = async (username: string, password: string) => {
    const res = await apiRequest<{
      access_token: string;
      refresh_token: string;
      user: User;
    }>("/auth/login", {
      method: "POST",
      body: JSON.stringify({ username, password }),
    });

    localStorage.setItem("access_token", res.access_token);
    localStorage.setItem("refresh_token", res.refresh_token);
    localStorage.setItem("user", JSON.stringify(res.user));
    setToken(res.access_token);
    setUser(res.user);
  };

  const logout = () => {
    localStorage.removeItem("access_token");
    localStorage.removeItem("refresh_token");
    localStorage.removeItem("user");
    setToken(null);
    setUser(null);
  };

  const isAdmin = user?.role === "admin";

  return (
    <AuthContext.Provider value={{ user, token, isLoading, isAdmin, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return context;
};