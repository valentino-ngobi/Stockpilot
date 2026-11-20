import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { FormEvent } from "react";
import type { Session } from "@supabase/supabase-js";
import { Building2, CheckCircle2, LogOut, Plus, ShieldCheck, XCircle } from "lucide-react";
import {
  createBranch,
  createShopForCurrentUser,
  loginWithEmail,
  logout,
  reactivateMember,
  registerWithEmail,
  restoreSession,
  setMemberAccess,
  suspendMember,
} from "../lib/auth";
import {
  clearShopBranchSelection,
  readShopBranchSelection,
  resolveAuthorizedBranchId,
  resolveAuthorizedShopId,
  writeShopBranchSelection,
} from "../lib/selectionPreference";
import {
  createAuthorizationRefreshQueue,
  sameBranchOptions,
  sameMemberRows,
  sameShopContexts,
  watchAuthorizationChanges,
} from "../lib/authorizationRefresh";
import { resetPasswordEntry } from "../lib/passwordState";
import { supabase } from "../lib/supabase";
import { togglePasswordVisibility } from "../lib/passwordVisibility";
import PasswordVisibilityControl from "./PasswordVisibilityControl";

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

type AuthorizationSnapshot = {
  userId: string;
  shops: ShopContext[];
  selectedShopId: string;
  branches: BranchOption[];
  selectedBranchId: string;
  members: MemberRow[];
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
  const [passwordVisible, setPasswordVisible] = useState(false);
  const [displayName, setDisplayName] = useState("");
  const [authBusy, setAuthBusy] = useState(false);
  const [authNotice, setAuthNotice] = useState("");
  const [authError, setAuthError] = useState("");

  const [shops, setShops] = useState<ShopContext[]>([]);
  const shopsRef = useRef(shops);
  shopsRef.current = shops;
  const [authorizationRefreshing, setAuthorizationRefreshing] = useState(false);
  const authorizationRefreshRequestRef = useRef<(() => Promise<void>) | null>(null);
  const activeAuthorizationUserRef = useRef("");
  const sessionUserIdRef = useRef("");
  const selectedShopIdRef = useRef("");
  const selectedShopUserIdRef = useRef("");
  const selectedBranchIdRef = useRef("");
  sessionUserIdRef.current = session?.user.id ?? "";
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
  const [reactivationTargetUserId, setReactivationTargetUserId] = useState("");
  const [reactivationBranchIds, setReactivationBranchIds] = useState<string[]>([]);

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

  useEffect(() => {
    resetPasswordEntry(setPassword, setPasswordVisible);
    setReactivationTargetUserId("");
    setReactivationBranchIds([]);
  }, [session?.user.id]);

  const loadAuthorizationSnapshot = useCallback(async (): Promise<AuthorizationSnapshot> => {
    if (!client || !session?.user.id) {
      throw new Error("An authenticated session is required to verify authorization.");
    }

    const userId = session.user.id;
    const { data: memberships, error: membershipError } = await client
      .from("shop_memberships")
      .select("shop_id, role")
      .eq("user_id", userId)
      .eq("status", "active");
    if (membershipError) throw membershipError;

    const membershipRows = (memberships ?? []) as Array<{
      shop_id: string;
      role: ShopRole;
    }>;
    let availableShops: ShopContext[] = [];
    if (membershipRows.length > 0) {
      const { data: shopRows, error: shopError } = await client
        .from("shops")
        .select("id, name")
        .in("id", membershipRows.map((membership) => membership.shop_id))
        .order("name")
        .order("id");
      if (shopError) throw shopError;

      const roleByShop = new Map(
        membershipRows.map((membership) => [membership.shop_id, membership.role]),
      );
      availableShops = (shopRows ?? []).map((shop) => ({
        id: String(shop.id),
        name: String(shop.name),
        role: roleByShop.get(String(shop.id)) ?? "sales_staff",
      }));
    }

    const savedSelection = readShopBranchSelection(userId);
    const authorizedShopIds = availableShops.map((shop) => shop.id);
    const currentShopId = selectedShopUserIdRef.current === userId
      ? selectedShopIdRef.current
      : "";
    const currentSelection = authorizedShopIds.includes(currentShopId)
      ? {
          shopId: currentShopId,
          branchId: selectedBranchIdRef.current || (
            savedSelection?.shopId === currentShopId ? savedSelection.branchId : null
          ),
        }
      : savedSelection;
    const resolvedShopId = resolveAuthorizedShopId(currentSelection, authorizedShopIds);

    let availableBranches: BranchOption[] = [];
    if (resolvedShopId) {
      const { data, error } = await client
        .from("branches")
        .select("id, name, is_primary")
        .eq("shop_id", resolvedShopId)
        .eq("is_active", true)
        .order("is_primary", { ascending: false })
        .order("name");
      if (error) throw error;
      availableBranches = (data ?? []).map((branch) => ({
        id: String(branch.id),
        name: String(branch.name),
        is_primary: Boolean(branch.is_primary),
      }));
    }

    const branchSelection = currentSelection?.shopId === resolvedShopId
      ? currentSelection
      : savedSelection;
    const resolvedBranchId = resolvedShopId
      ? resolveAuthorizedBranchId(
          branchSelection,
          resolvedShopId,
          availableBranches.map((branch) => branch.id),
        )
      : "";

    let availableMembers: MemberRow[] = [];
    if (availableShops.find((shop) => shop.id === resolvedShopId)?.role === "owner") {
      const { data, error } = await client
        .from("shop_memberships")
        .select("user_id, role, status")
        .eq("shop_id", resolvedShopId)
        .order("created_at")
        .order("user_id");
      if (error) throw error;
      availableMembers = (data ?? []) as MemberRow[];
    }

    return {
      userId,
      shops: availableShops,
      selectedShopId: resolvedShopId,
      branches: availableBranches,
      selectedBranchId: resolvedBranchId,
      members: availableMembers,
    };
  }, [client, session?.user.id]);

  const applyAuthorizationSnapshot = useCallback((snapshot: AuthorizationSnapshot) => {
    if (!session?.user.id || snapshot.userId !== session.user.id) return;

    const previousShop = shopsRef.current.find((shop) => shop.id === selectedShopIdRef.current);
    const nextShop = snapshot.shops.find((shop) => shop.id === snapshot.selectedShopId);
    const shopContextChanged =
      selectedShopIdRef.current !== snapshot.selectedShopId ||
      previousShop?.role !== nextShop?.role;

    setShops((current) => sameShopContexts(current, snapshot.shops) ? current : snapshot.shops);
    selectedShopIdRef.current = snapshot.selectedShopId;
    selectedShopUserIdRef.current = snapshot.userId;
    selectedBranchIdRef.current = snapshot.selectedBranchId;
    setSelectedShopId(snapshot.selectedShopId);
    setBranches((current) => sameBranchOptions(current, snapshot.branches) ? current : snapshot.branches);
    setSelectedBranchId(snapshot.selectedBranchId);
    setBranchesLoading(false);
    setShopsForUserId(snapshot.userId);
    setShopsError("");
    setBranchesError("");
    setAuthorizationRefreshing(false);
    setMembers((current) => sameMemberRows(current, snapshot.members) ? current : snapshot.members);
    if (shopContextChanged) {
      setMemberBranchIds([]);
      setReactivationTargetUserId("");
      setReactivationBranchIds([]);
    } else {
      setMemberBranchIds((current) => {
        const next = current.filter((branchId) => snapshot.branches.some((branch) => branch.id === branchId));
        return next.length === current.length ? current : next;
      });
      setReactivationBranchIds((current) => {
        const next = current.filter((branchId) => snapshot.branches.some((branch) => branch.id === branchId));
        return next.length === current.length ? current : next;
      });
      setReactivationTargetUserId((current) => (
        current && snapshot.members.some((member) =>
          member.user_id === current && member.status === "suspended" && member.role !== "owner"
        )
          ? current
          : ""
      ));
    }

    const savedSelection = readShopBranchSelection(snapshot.userId);
    if (!snapshot.selectedShopId) {
      clearShopBranchSelection(snapshot.userId);
    } else if (
      savedSelection?.shopId !== snapshot.selectedShopId ||
      (savedSelection.branchId ?? null) !== (snapshot.selectedBranchId || null)
    ) {
      writeShopBranchSelection(snapshot.userId, {
        shopId: snapshot.selectedShopId,
        branchId: snapshot.selectedBranchId || null,
      });
    }
  }, [session?.user.id]);

  const authorizationLoaderRef = useRef(loadAuthorizationSnapshot);
  const authorizationApplierRef = useRef(applyAuthorizationSnapshot);
  const authorizationErrorHandlerRef = useRef<(error: unknown) => void>(() => undefined);
  authorizationLoaderRef.current = loadAuthorizationSnapshot;
  authorizationApplierRef.current = applyAuthorizationSnapshot;
  authorizationErrorHandlerRef.current = (error) => {
    if (
      !activeAuthorizationUserRef.current ||
      activeAuthorizationUserRef.current !== sessionUserIdRef.current
    ) return;
    setShopsError(errorMessage(error, "Could not verify your shop and branch access."));
    setAuthorizationRefreshing(false);
  };
  if (!authorizationRefreshRequestRef.current) {
    authorizationRefreshRequestRef.current = createAuthorizationRefreshQueue(
      () => authorizationLoaderRef.current(),
      (snapshot) => authorizationApplierRef.current(snapshot),
      (error) => authorizationErrorHandlerRef.current(error),
      () => Boolean(activeAuthorizationUserRef.current) &&
        activeAuthorizationUserRef.current === sessionUserIdRef.current,
    );
  }

  useEffect(() => {
    if (!client || !session?.user.id) {
      activeAuthorizationUserRef.current = "";
      selectedShopIdRef.current = "";
      selectedShopUserIdRef.current = "";
      selectedBranchIdRef.current = "";
      setAuthorizationRefreshing(false);
      setShops([]);
      setShopsError("");
      setShopsForUserId("");
      setSelectedShopId("");
      setBranches([]);
      setBranchesLoading(false);
      setSelectedBranchId("");
      setBranchesError("");
      setMembers([]);
      return;
    }

    const userId = session.user.id;
    if (activeAuthorizationUserRef.current !== userId) {
      activeAuthorizationUserRef.current = userId;
      selectedShopIdRef.current = "";
      selectedShopUserIdRef.current = userId;
      selectedBranchIdRef.current = "";
      setShops([]);
      setShopsForUserId(userId);
      setSelectedShopId("");
      setBranches([]);
      setBranchesLoading(true);
      setSelectedBranchId("");
      setMembers([]);
      setMemberBranchIds([]);
      setAuthorizationRefreshing(true);
      setShopsError("");
      setBranchesError("");
    }

    const requestRefresh = authorizationRefreshRequestRef.current;
    if (!requestRefresh) return;
    void requestRefresh();
    const unsubscribe = watchAuthorizationChanges(
      client,
      userId,
      () => void requestRefresh(),
      window,
      document,
    );

    return () => {
      if (activeAuthorizationUserRef.current === userId) activeAuthorizationUserRef.current = "";
      unsubscribe();
    };
  }, [client, session?.user.id]);

  const selectedShop = useMemo(
    () => shops.find((shop) => shop.id === selectedShopId) ?? null,
    [shops, selectedShopId],
  );

  const handleAuthSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!client) return;

    setPasswordVisible(false);
    setAuthBusy(true);
    setAuthError("");
    setAuthNotice("");
    try {
      const response =
        authMode === "register"
          ? await registerWithEmail(client, email, password, displayName)
          : await loginWithEmail(client, email, password);

      if (response.error) throw response.error;
      resetPasswordEntry(setPassword, setPasswordVisible);

      if (authMode === "register" && !response.data.session) {
        setAuthNotice(
          "Account created. Confirm the email if required by this Supabase project, then sign in to create or select a shop.",
        );
      } else {
        setSession(response.data.session);
        setAuthNotice(authMode === "register" ? "Account created." : "Signed in.");
      }
    } catch {
      // Auth provider errors can be shown without echoing any submitted credential.
      setAuthError("Authentication could not be completed. Check your details and try again.");
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
      selectedShopIdRef.current = createdShopId;
      selectedShopUserIdRef.current = session?.user.id ?? "";
      selectedBranchIdRef.current = "";
      setSelectedShopId(createdShopId);
      setBranchesLoading(true);
      if (session?.user.id) {
        writeShopBranchSelection(session.user.id, {
          shopId: createdShopId,
          branchId: null,
        });
      }
      void authorizationRefreshRequestRef.current?.();
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
      void authorizationRefreshRequestRef.current?.();
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
      setReactivationTargetUserId("");
      setReactivationBranchIds([]);
      void authorizationRefreshRequestRef.current?.();
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
      setActionNotice("Membership suspended. Its saved branch access remains blocked until reactivation.");
      void authorizationRefreshRequestRef.current?.();
    } catch (error) {
      setActionError(errorMessage(error, "Could not suspend that membership."));
    }
  };

  const handleReactivateMember = async (userId: string) => {
    if (!client || !selectedShop || selectedShop.role !== "owner") return;
    setActionError("");
    setActionNotice("");
    const restoringExplicitBranches = reactivationTargetUserId === userId;
    try {
      const { error } = await reactivateMember(
        client,
        selectedShop.id,
        userId,
        restoringExplicitBranches ? reactivationBranchIds : undefined,
      );
      if (error) {
        if (!restoringExplicitBranches && error.message.includes("No branch assignments are saved.")) {
          setReactivationTargetUserId(userId);
          setReactivationBranchIds([]);
          setActionError(
            "This older suspension has no saved branch assignments. Select the member's previous branches below; their role will remain unchanged.",
          );
          return;
        }
        throw error;
      }
      setReactivationTargetUserId("");
      setReactivationBranchIds([]);
      setActionNotice("Membership reactivated with its existing role and branch access.");
      void authorizationRefreshRequestRef.current?.();
    } catch (error) {
      setActionError(errorMessage(error, "Could not reactivate that member."));
    }
  };

  const handleLogout = async () => {
    if (!client) return;
    setAuthError("");
    const { error } = await logout(client);
    if (error) setAuthError(error.message);
    else {
      resetPasswordEntry(setPassword, setPasswordVisible);
      selectedShopIdRef.current = "";
      selectedShopUserIdRef.current = "";
      selectedBranchIdRef.current = "";
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
            <div className="inventory-field">
              <span id="auth-password-label">Password</span>
              <PasswordVisibilityControl
                id="auth-password"
                labelledBy="auth-password-label"
                value={password}
                visible={passwordVisible}
                onChange={(event) => setPassword(event.target.value)}
                onToggle={() => setPasswordVisible((visible) => togglePasswordVisibility(visible))}
                autoComplete={authMode === "register" ? "new-password" : "current-password"}
              />
            </div>
            <button className="button button-primary" type="submit" disabled={authBusy}>
              {authBusy ? "Please wait…" : authMode === "register" ? "Register" : "Sign in"}
            </button>
            <button
              className="button button-secondary"
              type="button"
              onClick={() => {
                setAuthMode((current) => current === "login" ? "register" : "login");
                setPasswordVisible(false);
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

            {shopsError || branchesError ? (
              <p className="inventory-notice notice-warning" role="status">
                Authorization could not be verified. Shop and branch tools are unavailable; refresh the page to try again.
              </p>
            ) : authorizationRefreshing || branchesLoading || shopsForUserId !== session.user.id ? (
              <p role="status">Refreshing authorized shop and branch access…</p>
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
                      const nextShopId = event.target.value;
                      if (nextShopId && !shops.some((shop) => shop.id === nextShopId)) return;
                      selectedShopIdRef.current = nextShopId;
                      selectedShopUserIdRef.current = session?.user.id ?? "";
                      selectedBranchIdRef.current = "";
                      setSelectedShopId(nextShopId);
                      setSelectedBranchId("");
                      setBranches([]);
                      setBranchesLoading(Boolean(event.target.value));
                      setBranchesError("");
                      setMemberBranchIds([]);
                      setMembers([]);
                      setActionError("");
                      setActionNotice("");
                      setReactivationTargetUserId("");
                      setReactivationBranchIds([]);
                      if (nextShopId && session?.user.id) {
                        writeShopBranchSelection(session.user.id, {
                          shopId: nextShopId,
                          branchId: null,
                        });
                      } else if (session?.user.id) {
                        clearShopBranchSelection(session.user.id);
                      }
                      if (nextShopId) void authorizationRefreshRequestRef.current?.();
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
                        onChange={(event) => {
                          const nextBranchId = event.target.value;
                          if (nextBranchId && !branches.some((branch) => branch.id === nextBranchId)) return;
                          selectedBranchIdRef.current = nextBranchId;
                          setSelectedBranchId(nextBranchId);
                          if (session?.user.id && shops.some((shop) => shop.id === selectedShopId)) {
                            writeShopBranchSelection(session.user.id, {
                              shopId: selectedShopId,
                              branchId: nextBranchId || null,
                            });
                          }
                          void authorizationRefreshRequestRef.current?.();
                        }}
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
                          {member.role !== "owner" && (
                            member.status === "active" ? (
                              <button className="button button-secondary" type="button" onClick={() => void handleSuspendMember(member.user_id)}>
                                Suspend
                              </button>
                            ) : (
                              <button
                                className="button button-secondary"
                                type="button"
                                disabled={reactivationTargetUserId === member.user_id && reactivationBranchIds.length === 0}
                                onClick={() => void handleReactivateMember(member.user_id)}
                              >
                                {reactivationTargetUserId === member.user_id
                                  ? "Reactivate with selected branches"
                                  : "Reactivate"}
                              </button>
                            )
                          )}
                          {member.status === "suspended" && reactivationTargetUserId === member.user_id && (
                            <fieldset className="backend-branch-assignments backend-reactivation-branches">
                              <legend>Select the previously authorized branches to restore</legend>
                              {branches.map((branch) => (
                                <label key={branch.id}>
                                  <input
                                    type="checkbox"
                                    checked={reactivationBranchIds.includes(branch.id)}
                                    onChange={() => setReactivationBranchIds((current) =>
                                      current.includes(branch.id)
                                        ? current.filter((id) => id !== branch.id)
                                        : [...current, branch.id],
                                    )}
                                  />
                                  <span>{branch.name}</span>
                                </label>
                              ))}
                            </fieldset>
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
