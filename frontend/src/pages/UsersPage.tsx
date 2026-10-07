import React, { useEffect, useState } from "react";
import { apiRequest } from "../api/client";
import { useAuth } from "../context/AuthContext";
import { Badge } from "../components/Badge";
import type { User, UserRole } from "../types";

export const UsersPage: React.FC = () => {
  const { user: currentUser } = useAuth();
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [filterActiveOnly, setFilterActiveOnly] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  // Modal state
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingUser, setEditingUser] = useState<User | null>(null);
  const [formData, setFormData] = useState({
    username: "",
    full_name: "",
    password: "",
    role: "staff" as UserRole,
  });
  const [submitting, setSubmitting] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [showPassword, setShowPassword] = useState(false);

  const fetchUsers = async () => {
    try {
      setLoading(true);
      const data = await apiRequest<User[]>(
        `/users${filterActiveOnly ? "?active_only=true" : ""}`
      );
      setUsers(data);
      setError(null);
    } catch (err: any) {
      setError(err.message || "Failed to load users");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchUsers();
  }, [filterActiveOnly]);

  const openAddModal = () => {
    setEditingUser(null);
    setFormData({
      username: "",
      full_name: "",
      password: "",
      role: "staff",
    });
    setShowPassword(false);
    setFormError(null);
    setIsModalOpen(true);
  };

  const openEditModal = (u: User) => {
    setEditingUser(u);
    setFormData({
      username: u.username,
      full_name: u.full_name,
      password: "",
      role: u.role,
    });
    setShowPassword(false);
    setFormError(null);
    setIsModalOpen(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setFormError(null);

    try {
      if (editingUser) {
        // Update user
        const payload: Record<string, any> = {
          full_name: formData.full_name.trim(),
          role: formData.role,
        };
        if (formData.password.trim()) {
          payload.password = formData.password.trim();
        }
        await apiRequest(`/users/${editingUser.id}`, {
          method: "PUT",
          body: JSON.stringify(payload),
        });
        setSuccessMsg(`User "${editingUser.full_name}" updated successfully.`);
      } else {
        // Create user
        if (!formData.username.trim() || !formData.password.trim()) {
          setFormError("Username and initial password are required.");
          setSubmitting(false);
          return;
        }
        await apiRequest("/users", {
          method: "POST",
          body: JSON.stringify({
            username: formData.username.trim().toLowerCase(),
            full_name: formData.full_name.trim(),
            password: formData.password.trim(),
            role: formData.role,
          }),
        });
        setSuccessMsg(`User "${formData.full_name}" created successfully.`);
      }

      setIsModalOpen(false);
      fetchUsers();
      setTimeout(() => setSuccessMsg(null), 4000);
    } catch (err: any) {
      setFormError(err.message || "Failed to save user account.");
    } finally {
      setSubmitting(false);
    }
  };

  const handleToggleActive = async (u: User) => {
    if (u.id === currentUser?.id) {
      alert("You cannot deactivate your own current administrator session.");
      return;
    }

    const actionText = u.is_active ? "deactivate" : "reactivate";
    if (!window.confirm(`Are you sure you want to ${actionText} ${u.full_name}?`)) {
      return;
    }

    try {
      if (u.is_active) {
        await apiRequest(`/users/${u.id}`, { method: "DELETE" });
      } else {
        await apiRequest(`/users/${u.id}`, {
          method: "PUT",
          body: JSON.stringify({ is_active: true }),
        });
      }
      setSuccessMsg(`User "${u.full_name}" status updated.`);
      fetchUsers();
      setTimeout(() => setSuccessMsg(null), 4000);
    } catch (err: any) {
      alert(err.message || "Failed to change user status.");
    }
  };

  const filteredUsers = users.filter((u) => {
    const q = search.toLowerCase();
    return (
      u.full_name.toLowerCase().includes(q) ||
      u.username.toLowerCase().includes(q) ||
      u.role.toLowerCase().includes(q)
    );
  });

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 bg-white border border-slate-200/80 rounded-2xl p-6 shadow-sm">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-xl font-bold text-slate-900 tracking-tight">User Accounts & Staff</h1>
            <span className="text-xs px-2.5 py-0.5 rounded-full bg-indigo-50 text-indigo-700 font-semibold border border-indigo-100">
              Admin Control
            </span>
          </div>
          <p className="text-xs text-slate-500 mt-1">
            Manage login credentials, warehouse floor permissions, and staff accounts.
          </p>
        </div>

        <button
          onClick={openAddModal}
          className="inline-flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-indigo-900 text-white text-xs font-semibold hover:bg-indigo-800 transition-colors shadow-sm cursor-pointer"
        >
          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
          </svg>
          Add Staff Account
        </button>
      </div>

      {/* Mobile Staff App Login Info Card */}
      <div className="bg-gradient-to-r from-indigo-50/80 via-blue-50/60 to-slate-50 border border-indigo-100 rounded-2xl p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3 shadow-xs">
        <div className="flex items-start gap-3">
          <div className="w-9 h-9 rounded-xl bg-indigo-600/10 text-indigo-800 flex items-center justify-center shrink-0 mt-0.5">
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z" />
            </svg>
          </div>
          <div>
            <h2 className="text-xs font-bold text-slate-900">Mobile Scanner App Staff Login</h2>
            <p className="text-[11px] text-slate-600 mt-0.5">
              Staff members use these login credentials on the mobile APK. Default staff account: username <span className="font-mono font-bold text-indigo-950 bg-indigo-100/80 px-1.5 py-0.5 rounded">staff</span>, password <span className="font-mono font-bold text-indigo-950 bg-indigo-100/80 px-1.5 py-0.5 rounded">Staff@12345</span>.
            </p>
          </div>
        </div>
        <button
          onClick={openAddModal}
          className="self-start sm:self-auto px-3.5 py-1.5 rounded-xl bg-indigo-900 text-white text-xs font-semibold hover:bg-indigo-800 transition-colors shadow-xs cursor-pointer shrink-0"
        >
          + Add Staff Account
        </button>
      </div>

      {/* Success Notification */}
      {successMsg && (
        <div className="p-3.5 bg-emerald-50 border border-emerald-200 text-emerald-800 text-xs font-medium rounded-xl flex items-center gap-2 transition-all">
          <svg className="w-4 h-4 text-emerald-600 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
          </svg>
          {successMsg}
        </div>
      )}

      {/* Error Alert */}
      {error && (
        <div className="p-3.5 bg-rose-50 border border-rose-200 text-rose-800 text-xs font-medium rounded-xl flex items-center gap-2">
          <svg className="w-4 h-4 text-rose-600 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          {error}
        </div>
      )}

      {/* Filters & Search */}
      <div className="flex flex-col sm:flex-row items-center justify-between gap-3 bg-white border border-slate-200 rounded-xl p-3 shadow-xs">
        <div className="relative w-full sm:w-80">
          <svg className="w-4 h-4 absolute left-3 top-2.5 text-slate-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
          <input
            type="text"
            placeholder="Search by name or username..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-3 py-1.5 text-xs bg-slate-50 border border-slate-200 rounded-lg text-slate-900 focus:outline-none focus:ring-1 focus:ring-indigo-800 focus:bg-white transition-all"
          />
        </div>

        <label className="flex items-center gap-2 text-xs font-medium text-slate-600 cursor-pointer self-start sm:self-auto select-none">
          <input
            type="checkbox"
            checked={filterActiveOnly}
            onChange={(e) => setFilterActiveOnly(e.target.checked)}
            className="rounded border-slate-300 text-indigo-900 focus:ring-indigo-800"
          />
          Active Accounts Only
        </label>
      </div>

      {/* Users Table / Grid */}
      <div className="bg-white border border-slate-200 rounded-2xl shadow-xs overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-xs text-slate-400">Loading user accounts...</div>
        ) : filteredUsers.length === 0 ? (
          <div className="p-12 text-center text-xs text-slate-400">
            No user accounts found matching your filters.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse text-xs">
              <thead>
                <tr className="bg-slate-50/75 border-b border-slate-200 text-slate-500 font-semibold uppercase tracking-wider">
                  <th className="py-3 px-4">User</th>
                  <th className="py-3 px-4">Role</th>
                  <th className="py-3 px-4">Status</th>
                  <th className="py-3 px-4">Created</th>
                  <th className="py-3 px-4 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                {filteredUsers.map((u) => {
                  const isCurrent = u.id === currentUser?.id;
                  const initials = u.full_name
                    .split(" ")
                    .map((n) => n[0])
                    .join("")
                    .slice(0, 2)
                    .toUpperCase();

                  return (
                    <tr key={u.id} className="hover:bg-slate-50/80 transition-colors">
                      <td className="py-3.5 px-4">
                        <div className="flex items-center gap-3">
                          <div className="w-8 h-8 rounded-full bg-gradient-to-tr from-indigo-900 to-indigo-700 text-white text-[11px] font-bold flex items-center justify-center shadow-xs shrink-0">
                            {initials}
                          </div>
                          <div>
                            <div className="font-semibold text-slate-900 flex items-center gap-1.5">
                              {u.full_name}
                              {isCurrent && (
                                <span className="text-[10px] px-1.5 py-0.2 rounded bg-slate-100 text-slate-600 font-normal">
                                  You
                                </span>
                              )}
                            </div>
                            <div className="text-[11px] text-slate-400 font-mono">@{u.username}</div>
                          </div>
                        </div>
                      </td>
                      <td className="py-3.5 px-4">
                        {u.role === "admin" ? (
                          <Badge variant="indigo">Administrator</Badge>
                        ) : (
                          <Badge variant="green">Warehouse Staff</Badge>
                        )}
                      </td>
                      <td className="py-3.5 px-4">
                        {u.is_active ? (
                          <span className="inline-flex items-center gap-1.5 text-emerald-700 font-semibold text-[11px]">
                            <span className="w-1.5 h-1.5 rounded-full bg-emerald-500"></span>
                            Active
                          </span>
                        ) : (
                          <span className="inline-flex items-center gap-1.5 text-slate-400 font-semibold text-[11px]">
                            <span className="w-1.5 h-1.5 rounded-full bg-slate-300"></span>
                            Deactivated
                          </span>
                        )}
                      </td>
                      <td className="py-3.5 px-4 text-slate-500 text-[11px]">
                        {new Date(u.created_at).toLocaleDateString("en-IN", {
                          day: "numeric",
                          month: "short",
                          year: "numeric",
                        })}
                      </td>
                      <td className="py-3.5 px-4 text-right">
                        <div className="inline-flex items-center gap-2">
                          <button
                            onClick={() => openEditModal(u)}
                            className="px-2.5 py-1 text-[11px] font-semibold text-indigo-900 hover:text-indigo-800 bg-indigo-50/60 hover:bg-indigo-50 border border-indigo-100 rounded-lg transition-colors cursor-pointer"
                          >
                            Edit
                          </button>
                          {!isCurrent && (
                            <button
                              onClick={() => handleToggleActive(u)}
                              className={`px-2.5 py-1 text-[11px] font-semibold rounded-lg border transition-colors cursor-pointer ${
                                u.is_active
                                  ? "text-rose-700 hover:text-rose-800 bg-rose-50/50 hover:bg-rose-50 border-rose-200"
                                  : "text-emerald-700 hover:text-emerald-800 bg-emerald-50/50 hover:bg-emerald-50 border-emerald-200"
                              }`}
                            >
                              {u.is_active ? "Deactivate" : "Reactivate"}
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Add / Edit Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40 backdrop-blur-xs animate-in fade-in duration-150">
          <div className="bg-white rounded-2xl border border-slate-200 shadow-xl max-w-md w-full overflow-hidden">
            <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between">
              <h2 className="text-sm font-bold text-slate-900">
                {editingUser ? `Edit Account: ${editingUser.full_name}` : "Create New User Account"}
              </h2>
              <button
                onClick={() => setIsModalOpen(false)}
                className="text-slate-400 hover:text-slate-600 text-lg leading-none p-1 cursor-pointer"
              >
                &times;
              </button>
            </div>

            <form onSubmit={handleSubmit} className="p-6 space-y-4 text-xs">
              {formError && (
                <div className="p-3 bg-rose-50 border border-rose-200 text-rose-700 rounded-xl text-xs">
                  {formError}
                </div>
              )}

              <div>
                <label className="block text-slate-700 font-semibold mb-1">
                  Username <span className="text-slate-400 font-normal">(@tag for login)</span>
                </label>
                <input
                  type="text"
                  required
                  disabled={!!editingUser}
                  placeholder="e.g. anzal, rahul"
                  value={formData.username}
                  onChange={(e) => setFormData({ ...formData, username: e.target.value })}
                  className={`w-full px-3 py-2 rounded-xl border text-xs transition-all ${
                    editingUser
                      ? "bg-slate-100 text-slate-400 border-slate-200 cursor-not-allowed"
                      : "bg-slate-50 border-slate-200 text-slate-900 focus:outline-none focus:ring-1 focus:ring-indigo-800 focus:bg-white"
                  }`}
                />
                {editingUser && (
                  <p className="text-[10px] text-slate-400 mt-1">Username cannot be changed after creation.</p>
                )}
              </div>

              <div>
                <label className="block text-slate-700 font-semibold mb-1">Full Name</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Anzal K (Staff)"
                  value={formData.full_name}
                  onChange={(e) => setFormData({ ...formData, full_name: e.target.value })}
                  className="w-full px-3 py-2 rounded-xl border border-slate-200 bg-slate-50 text-slate-900 text-xs focus:outline-none focus:ring-1 focus:ring-indigo-800 focus:bg-white"
                />
              </div>

              <div>
                <label className="block text-slate-700 font-semibold mb-1">User Role</label>
                <select
                  value={formData.role}
                  onChange={(e) => setFormData({ ...formData, role: e.target.value as UserRole })}
                  className="w-full px-3 py-2 rounded-xl border border-slate-200 bg-slate-50 text-slate-900 text-xs focus:outline-none focus:ring-1 focus:ring-indigo-800 focus:bg-white"
                >
                  <option value="staff">Warehouse Staff (Scanner App & Lookup)</option>
                  <option value="admin">Administrator (Full Dashboard & Approvals)</option>
                </select>
              </div>

              <div>
                <label className="block text-slate-700 font-semibold mb-1">
                  {editingUser ? "Reset Password" : "Password"}
                </label>
                <div className="relative">
                  <input
                    type={showPassword ? "text" : "password"}
                    required={!editingUser}
                    placeholder={editingUser ? "Leave empty to keep current password" : "Minimum 6 characters (e.g. Staff@12345)"}
                    value={formData.password}
                    onChange={(e) => setFormData({ ...formData, password: e.target.value })}
                    className="w-full pl-3 pr-10 py-2 rounded-xl border border-slate-200 bg-slate-50 text-slate-900 text-xs focus:outline-none focus:ring-1 focus:ring-indigo-800 focus:bg-white"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 p-1 cursor-pointer"
                    title={showPassword ? "Hide password" : "Show password"}
                  >
                    {showPassword ? (
                      <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l18 18" />
                      </svg>
                    ) : (
                      <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
                      </svg>
                    )}
                  </button>
                </div>
              </div>

              <div className="pt-3 border-t border-slate-100 flex items-center justify-end gap-2">
                <button
                  type="button"
                  onClick={() => setIsModalOpen(false)}
                  className="px-4 py-2 rounded-xl border border-slate-200 text-slate-600 hover:bg-slate-50 font-semibold cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submitting}
                  className="px-4 py-2 rounded-xl bg-indigo-900 text-white font-semibold hover:bg-indigo-800 transition-colors disabled:opacity-50 cursor-pointer"
                >
                  {submitting ? "Saving..." : editingUser ? "Save Changes" : "Create Account"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};