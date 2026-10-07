import React from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { AuthProvider } from "./context/AuthContext";
import { ProtectedLayout } from "./components/ProtectedRoute";
import { LoginPage } from "./pages/LoginPage";
import { OverviewPage } from "./pages/OverviewPage";
import { StockPage } from "./pages/StockPage";
import { SerialsPage } from "./pages/SerialsPage";
import { ShopsPage } from "./pages/ShopsPage";
import { BillsPage } from "./pages/BillsPage";
import { ReportsPage } from "./pages/ReportsPage";
import { UsersPage } from "./pages/UsersPage";
import { DevicesPage } from "./pages/DevicesPage";

export const App: React.FC = () => {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<LoginPage />} />

          {/* Protected Routes (Staff and Admin) */}
          <Route element={<ProtectedLayout />}>
            <Route path="/" element={<OverviewPage />} />
            <Route path="/stock" element={<StockPage />} />
            <Route path="/serials" element={<SerialsPage />} />
            <Route path="/shops" element={<ShopsPage />} />
            <Route path="/bills" element={<BillsPage />} />
            <Route path="/reports" element={<ReportsPage />} />
          </Route>

          {/* Admin-only Routes */}
          <Route element={<ProtectedLayout requireAdmin={true} />}>
            <Route path="/users" element={<UsersPage />} />
            <Route path="/devices" element={<DevicesPage />} />
          </Route>

          {/* Fallback */}
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
};

export default App;