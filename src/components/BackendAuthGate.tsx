import { useCallback, useEffect, useMemo, useState } from "react";
import type { FormEvent } from "react";
import type { Session } from "@supabase/supabase-js";
import { Building2, CheckCircle2, LogOut, Plus, ShieldCheck, XCircle } from "lucide-react";
import {
  createBranch,
  createShopForCurrentUser,
  loginWithEmail,
  logout,
  registerWithEmail,
  restoreSession,
  setMemberAccess,
  suspendMember,
} from "../lib/auth";
import { supabase } from "../lib/supabase";

type ShopRole = "owner" | "manager" | "sales_staff" | "inventory_staff";
type MembershipStatus = "active" | "suspended";

type ShopContext = {
  id: string;
  name: string;
  role: ShopRole;
};

type BranchOption = {
  id: string;
  name: string;
  is_primary: boolean;
};

type MemberRow = {
  user_id: string;
  role: ShopRole;
  status: MembershipStatus;
};

const roleLabels: Record<ShopRole, string> = {
  owner: "Owner",
  manager: "Manager",
  sales_staff: "Sales staff",
  inventory_staff: "Inventory staff",
};

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

export default function BackendAuthGate() {
  const client = supabase;
  const [session, setSession] = useState<Session | null>(null);
  const [sessionLoading, setSessionLoading] = useState(true);
  const [authMode, setAuthMode] = useState<"login" | "register">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [authBusy, setAuthBusy] = useState(false);
  const [authNotice, setAuthNotice] = useState("");
  const [authError, setAuthError] = useState("");

  const [shops, setShops] = useState<ShopContext[]>([]);
  const [shopsLoading, setShopsLoading] = useState(false);
  const [shopsError, setShopsError] = useState("");
  const [shopsForUserId, setShopsForUserId] = useState("");
  const [selectedShopId, setSelectedShopId] = useState("");
  const [branches, setBranches] = useState<BranchOption[]>([]);
  const [branchesLoading, setBranchesLoading] = useState(false);
  const [selectedBranchId, setSelectedBranchId] = useState("");
  const [branchesError, setBranchesError] = useState("");
  const [actionNotice, setActionNotice] = useState("");
  const [actionError, setActionError] = useState("");

  const [shopName, setShopName] = useState("");
  const [branchName, setBranchName] = useState("");
  const [memberUserId, setMemberUserId] = useState("");
  const [memberRole, setMemberRole] = useState<Exclude<ShopRole, "owner">>(
    "sales_staff",
  );
  const [memberBranchIds, setMemberBranchIds] = useState<string[]>([]);
  const [members, setMembers] = useState<MemberRow[]>([]);

  useEffect(() => {
    if (!client) {
      setSessionLoading(false);
      return;
    }

    let active = true;
    const { data } = client.auth.onAuthStateChange((_event, nextSession) => {
      if (!active) return;
      setSession(nextSession);
      setAuthError("");
      setAuthNotice("");
    });

    void restoreSession(client)
      .then(({ data: sessionData, error }) => {
        if (!active) return;
        if (error) setAuthError(error.message);
        setSession(sessionData.session);
      })
      .catch((error: unknown) => {
        if (active) {
          setAuthError(errorMessage(error, "Could not restore the saved session."));
        }
      })
      .finally(() => {
        if (active) setSessionLoading(false);
      });

    return () => {
      active = false;
      data.subscription.unsubscribe();
    };
  }, [client]);

  const loadShops = useCallback(async (isCurrent: () => boolean) => {
    if (!client || !session?.user.id) {
      setShops([]);
      setSelectedShopId("");
      setShopsError("");
      setShopsForUserId("");
      setShopsLoading(false);
      return;
    }

    setShopsLoading(true);
    setShopsError("");
    setShopsForUserId(session.user.id);
    setBranches([]);
    setSelectedBranchId("");
    setMemberBranchIds([]);
    setMembers([]);
    setSelectedShopId("");
    try {
      const { data: memberships, error: membershipError } = await client
        .from("shop_memberships")
        .select("shop_id, role")
        .eq("user_id", session.user.id)
        .eq("status", "active");

      if (!isCurrent()) return;
      if (membershipError) throw membershipError;
      const membershipRows = (memberships ?? []) as Array<{
        shop_id: string;
        role: ShopRole;
      }>;

      if (membershipRows.length === 0) {
        setShops([]);
        setSelectedShopId("");
        return;
      }

      const { data: shopRows, error: shopError } = await client
        .from("shops")
        .select("id, name")
        .in("id", membershipRows.map((membership) => membership.shop_id))
        .order("name");

      if (!isCurrent()) return;
      if (shopError) throw shopError;
      const roleByShop = new Map(
        membershipRows.map((membership) => [membership.shop_id, membership.role]),
      );
      const availableShops = (shopRows ?? []).map((shop) => ({
        id: String(shop.id),
        name: String(shop.name),
        role: roleByShop.get(String(shop.id)) ?? "sales_staff",
      }));

      setShops(availableShops);
      setSelectedShopId((current) =>
        availableShops.some((shop) => shop.id === current)
          ? current
          : availableShops.length === 1
            ? availableShops[0].id
            : "",
      );
    } catch (error) {
      if (isCurrent()) {
        setShopsError(errorMessage(error, "Could not load your shop memberships."));
      }
    } finally {
      if (isCurrent()) setShopsLoading(false);
    }
  }, [client, session?.user.id]);

  useEffect(() => {
    let active = true;
    void loadShops(() => active);
    return () => {
      active = false;
    };
  }, [loadShops]);

  const selectedShop = useMemo(
    () => shops.find((shop) => shop.id === selectedShopId) ?? null,
    [shops, selectedShopId],
  );

  useEffect(() => {
    if (!client || !selectedShopId) {
      setBranches([]);
      setSelectedBranchId("");
      setBranchesLoading(false);
      setMembers([]);
      setBranchesError("");
      return;
    }

    let active = true;
    setBranchesLoading(true);
    setBranches([]);
    setSelectedBranchId("");
    setMembers([]);
    setBranchesError("");

    void (async () => {
      try {
        const { data, error } = await client
          .from("branches")
          .select("id, name, is_primary")
          .eq("shop_id", selectedShopId)
          .eq("is_active", true)
          .order("is_primary", { ascending: false })
          .order("name");

        if (!active) return;
        if (error) throw error;
        const accessibleBranches = (data ?? []).map((branch) => ({
          id: String(branch.id),
          name: String(branch.name),
          is_primary: Boolean(branch.is_primary),
        }));
        setBranches(accessibleBranches);
        setSelectedBranchId((current) =>
          accessibleBranches.some((branch) => branch.id === current)
            ? current
            : accessibleBranches.length === 1
              ? accessibleBranches[0].id
              : "",
        );
      } catch (error) {
        if (active) {
          setBranchesError(errorMessage(error, "Could not load authorized branches."));
        }
      } finally {
        if (active) setBranchesLoading(false);
      }
    })();

    return () => {
      active = false;
    };
  }, [client, selectedShopId]);

  const [membersRevision, setMembersRevision] = useState(0);

  const loadMembers = useCallback(async (isCurrent: () => boolean) => {
    if (!client || !selectedShop || selectedShop.role !== "owner") {
      setMembers([]);
      return;
    }

    setMembers([]);
    try {
      const { data, error } = await client
        .from("shop_memberships")
        .select("user_id, role, status")
        .eq("shop_id", selectedShop.id)
        .order("created_at");

      if (!isCurrent()) return;
      if (error) {
        setActionError(error.message);
        return;
      }
      setMembers((data ?? []) as MemberRow[]);
    } catch (error) {
      if (isCurrent()) {
        setActionError(errorMessage(error, "Could not load shop memberships."));
      }
    }
  }, [client, selectedShop]);

  useEffect(() => {
    let active = true;
    void loadMembers(() => active);
    return () => {
      active = false;
    };
  }, [loadMembers, membersRevision]);

  const handleAuthSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!client) return;

    setAuthBusy(true);
    setAuthError("");
    setAuthNotice("");
    try {
      const response =
        authMode === "register"
          ? await registerWithEmail(client, email, password, displayName)
          : await loginWithEmail(client, email, password);

      if (response.error) throw response.error;

      if (authMode === "register" && !response.data.session) {
        setAuthNotice(
          "Account created. Confirm the email if required by this Supabase project, then sign in to create or select a shop.",
        );
      } else {
        setSession(response.data.session);
        setAuthNotice(authMode === "register" ? "Account created." : "Signed in.");
      }
    } catch (error) {
      setAuthError(errorMessage(error, "Authentication could not be completed."));
    } finally {
      setAuthBusy(false);
    }
  };

  const handleCreateShop = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!client || !shopName.trim()) return;
    setActionError("");
    setActionNotice("");
    try {
      const { data, error } = await createShopForCurrentUser(client, shopName);
      if (error) throw error;
      const createdShopId = String(data);
      setShops((current) => [
        ...current,
        { id: createdShopId, name: shopName.trim(), role: "owner" },
      ]);
      setSelectedShopId(createdShopId);
      setShopName("");
      setActionNotice("Shop created. You are its owner and its primary branch is ready.");
    } catch (error) {
      setActionError(errorMessage(error, "Could not create the shop."));
    }
  };

  const handleCreateBranch = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!client || !selectedShop || selectedShop.role !== "owner") return;
    setActionError("");
    setActionNotice("");
    try {
      const { data, error } = await createBranch(client, selectedShop.id, branchName);
      if (error) throw error;
      setBranches((current) => [
        ...current,
        { id: String(data), name: branchName.trim(), is_primary: false },
      ]);
      setBranchName("");
      setActionNotice("Branch created. Assign staff access before they can select it.");
    } catch (error) {
      setActionError(errorMessage(error, "Could not create the branch."));
    }
  };

  const handleMemberAccess = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!client || !selectedShop || selectedShop.role !== "owner") return;
    setActionError("");
    setActionNotice("");
    try {
      const { error } = await setMemberAccess(
        client,
        selectedShop.id,
        memberUserId,
        memberRole,
        memberBranchIds,
      );
      if (error) throw error;
      setMemberUserId("");
      setMemberBranchIds([]);
      setActionNotice("Member access saved for the selected branches.");
      setMembersRevision((revision) => revision + 1);
    } catch (error) {
      setActionError(errorMessage(error, "Could not update member access."));
    }
  };

  const handleSuspendMember = async (userId: string) => {
    if (!client || !selectedShop || selectedShop.role !== "owner") return;
    setActionError("");
    setActionNotice("");
    try {
      const { error } = await suspendMember(client, selectedShop.id, userId);
      if (error) throw error;
      setActionNotice("Membership suspended and branch access removed.");
      setMembersRevision((revision) => revision + 1);
    } catch (error) {
      setActionError(errorMessage(error, "Could not suspend that membership."));
    }
  };

  const handleLogout = async () => {
    if (!client) return;
    setAuthError("");
    const { error } = await logout(client);
    if (error) setAuthError(error.message);
    else {
      setSession(null);
      setShops([]);
      setBranches([]);
      setSelectedShopId("");
      setSelectedBranchId("");
    }
  };

  const toggleMemberBranch = (branchId: string) => {
    setMemberBranchIds((current) =>
      current.includes(branchId)
        ? current.filter((id) => id !== branchId)
        : [...current, branchId],
    );
  };

  if (!client) {
    return (
      <BackendMessage
        title="Supabase client unavailable"
        message="Supabase is configured incompletely. Check the environment variables and restart Vite. Local prototype data was not opened."
      />
    );
  }

  if (sessionLoading) {
    return <BackendMessage title="Restoring session" message="Checking the saved Supabase session…" />;
  }

  return (
    <main className="backend-auth-page">
      <section className="surface-card backend-auth-card">
        <div className="eyebrow"><span className="eyebrow-line" /> STOCKPILOT BACKEND FOUNDATION</div>
        <div className="operations-heading">
          <div>
            <h1>{session ? "Shop access" : authMode === "register" ? "Create account" : "Sign in"}</h1>
            <p className="page-subtitle">
              This milestone provides email authentication and shop/branch context. Financial workflows remain in the separate LocalStorage prototype until their backend milestones are implemented.
            </p>
          </div>
          <div className="operations-heading-icon"><ShieldCheck size={22} /></div>
        </div>

        {(authError || shopsError || branchesError || actionError) && (
          <div className="operations-note backend-message-error" role="alert">
            <XCircle size={16} />
            <span>{authError || shopsError || branchesError || actionError}</span>
          </div>
        )}
        {(authNotice || actionNotice) && (
          <div className="operations-note backend-message-success" role="status">
            <CheckCircle2 size={16} />
            <span>{authNotice || actionNotice}</span>
          </div>
        )}

        {!session ? (
          <form className="operations-form backend-auth-form" onSubmit={handleAuthSubmit}>
            {authMode === "register" && (
              <label className="inventory-field">
                <span>Display name</span>
                <input
                  value={displayName}
                  onChange={(event) => setDisplayName(event.target.value)}
                  autoComplete="name"
                  maxLength={120}
                  required
                />
              </label>
            )}
            <label className="inventory-field">
              <span>Email</span>
              <input
                type="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                autoComplete="email"
                required
              />
            </label>
            <label className="inventory-field">
              <span>Password</span>
              <input
                type="password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                autoComplete={authMode === "register" ? "new-password" : "current-password"}
                minLength={8}
                required
              />
            </label>
            <button className="button button-primary" type="submit" disabled={authBusy}>
              {authBusy ? "Please wait…" : authMode === "register" ? "Register" : "Sign in"}
            </button>
            <button
              className="button button-secondary"
              type="button"
              onClick={() => {
                setAuthMode((current) => current === "login" ? "register" : "login");
                setAuthError("");
                setAuthNotice("");
              }}
            >
              {authMode === "login" ? "Create an account" : "Return to sign in"}
            </button>
          </form>
        ) : (
          <div className="backend-context">
            <div className="backend-user-row">
              <div>
                <strong>{session.user.email ?? "Authenticated user"}</strong>
                <small>Account ID: {session.user.id}</small>
              </div>
              <button className="button button-secondary" type="button" onClick={() => void handleLogout()}>
                <LogOut size={15} /> Sign out
              </button>
            </div>

            {shopsLoading || shopsForUserId !== session.user.id ? (
              <p role="status">Loading authorized shops…</p>
            ) : shopsError ? (
              <p className="inventory-notice notice-warning" role="status">
                Shop access is unavailable. Refresh the page to try again; no new shop was created.
              </p>
            ) : shops.length === 0 ? (
              <form className="operations-form" onSubmit={handleCreateShop}>
                <p>No active shop membership was found. Create a shop to receive its owner membership.</p>
                <label className="inventory-field">
                  <span>Business name</span>
                  <input value={shopName} onChange={(event) => setShopName(event.target.value)} maxLength={120} required />
                </label>
                <button className="button button-primary" type="submit"><Plus size={15} /> Create shop</button>
              </form>
            ) : (
              <>
                <div className="operations-form backend-selectors">
                  <label className="inventory-field">
                    <span>Business</span>
                    <select value={selectedShopId} onChange={(event) => {
                      setSelectedShopId(event.target.value);
                      setSelectedBranchId("");
                      setBranches([]);
                      setBranchesLoading(Boolean(event.target.value));
                      setBranchesError("");
                      setMemberBranchIds([]);
                      setMembers([]);
                      setActionError("");
                      setActionNotice("");
                    }}>
                      <option value="">Choose a business</option>
                      {shops.map((shop) => <option value={shop.id} key={shop.id}>{shop.name} · {roleLabels[shop.role]}</option>)}
                    </select>
                  </label>
                  {selectedShop && (
                    <label className="inventory-field">
                      <span>Authorized branch</span>
                      <select
                        value={selectedBranchId}
                        onChange={(event) => setSelectedBranchId(event.target.value)}
                        disabled={branchesLoading || branches.length === 0}
                      >
                        <option value="">Choose a branch</option>
                        {branches.map((branch) => <option value={branch.id} key={branch.id}>{branch.name}</option>)}
                      </select>
                    </label>
                  )}
                </div>

                {selectedShop && !branchesLoading && !branchesError && branches.length === 0 && (
                  <p className="inventory-notice notice-warning" role="status">
                    {selectedShop.role === "owner"
                      ? "No active branches are available in this shop. Create a branch to continue."
                      : "You have no active branch assignment in this shop. Ask an owner to assign your access."}
                  </p>
                )}

                {selectedShop?.role === "owner" && (
                  <div className="backend-owner-tools">
                    <form className="operations-form" onSubmit={handleCreateBranch}>
                      <h2><Building2 size={17} /> Create branch</h2>
                      <label className="inventory-field">
                        <span>Branch name</span>
                        <input value={branchName} onChange={(event) => setBranchName(event.target.value)} maxLength={120} required />
                      </label>
                      <button className="button button-secondary" type="submit"><Plus size={15} /> Add branch</button>
                    </form>

                    <form className="operations-form" onSubmit={handleMemberAccess}>
                      <h2>Assign a registered member</h2>
                      <p className="field-hint">Invitations are not part of this milestone. The person must register first and share their account ID.</p>
                      <label className="inventory-field">
                        <span>Member account ID</span>
                        <input value={memberUserId} onChange={(event) => setMemberUserId(event.target.value)} required />
                      </label>
                      <label className="inventory-field">
                        <span>Role</span>
                        <select value={memberRole} onChange={(event) => setMemberRole(event.target.value as Exclude<ShopRole, "owner">)}>
                          <option value="manager">Manager</option>
                          <option value="sales_staff">Sales staff</option>
                          <option value="inventory_staff">Inventory staff</option>
                        </select>
                      </label>
                      <fieldset className="backend-branch-assignments">
                        <legend>Authorized branches</legend>
                        {branches.map((branch) => (
                          <label key={branch.id}>
                            <input type="checkbox" checked={memberBranchIds.includes(branch.id)} onChange={() => toggleMemberBranch(branch.id)} />
                            <span>{branch.name}</span>
                          </label>
                        ))}
                      </fieldset>
                      <button className="button button-secondary" type="submit" disabled={memberBranchIds.length === 0}>
                        Save member access
                      </button>
                    </form>

                    <div className="backend-members" aria-label="Shop memberships">
                      <h2>Shop members</h2>
                      {members.map((member) => (
                        <div className="backend-member-row" key={member.user_id}>
                          <div>
                            <strong>{roleLabels[member.role]}</strong>
                            <small>{member.user_id}</small>
                            <small>{member.status}</small>
                          </div>
                          {member.role !== "owner" && member.status === "active" && (
                            <button className="button button-secondary" type="button" onClick={() => void handleSuspendMember(member.user_id)}>
                              Suspend
                            </button>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {selectedShop && selectedBranchId && (
                  <div className="inventory-info-banner surface-card" role="status">
                    <ShieldCheck size={18} />
                    <div>
                      <strong>{selectedShop.name} · {branches.find((branch) => branch.id === selectedBranchId)?.name}</strong>
                      <p>Signed in as {roleLabels[selectedShop.role]} with this branch selected.</p>
                    </div>
                  </div>
                )}
              </>
            )}
          </div>
        )}

        <div className="operations-note backend-scope-note" role="note">
          <ShieldCheck size={16} />
          <span>Milestone 1 provides identity and tenant context only. Sales, inventory, purchases, credit, reports, and closing are not yet connected to PostgreSQL and are not displayed in authenticated mode. Existing LocalStorage records remain untouched.</span>
        </div>
      </section>
    </main>
  );
}

function BackendMessage({ title, message }: { title: string; message: string }) {
  return (
    <main className="backend-auth-page">
      <section className="surface-card backend-auth-card" role="alert">
        <h1>{title}</h1>
        <p>{message}</p>
      </section>
    </main>
  );
}
