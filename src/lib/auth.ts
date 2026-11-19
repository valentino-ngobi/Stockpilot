import type { SupabaseClient } from "@supabase/supabase-js";

export function registerWithEmail(
  client: SupabaseClient,
  email: string,
  password: string,
  displayName: string,
) {
  return client.auth.signUp({
    email: email.trim(),
    password,
    options: {
      data: { display_name: displayName.trim() },
    },
  });
}

export function loginWithEmail(
  client: SupabaseClient,
  email: string,
  password: string,
) {
  return client.auth.signInWithPassword({
    email: email.trim(),
    password,
  });
}

export function restoreSession(client: SupabaseClient) {
  return client.auth.getSession();
}

export function logout(client: SupabaseClient) {
  return client.auth.signOut();
}

export function createShopForCurrentUser(
  client: SupabaseClient,
  name: string,
) {
  return client.rpc("create_shop_for_current_user", {
    p_name: name.trim(),
  });
}

export function createBranch(
  client: SupabaseClient,
  shopId: string,
  name: string,
) {
  return client.rpc("create_branch", {
    p_shop_id: shopId,
    p_name: name.trim(),
  });
}

export function setMemberAccess(
  client: SupabaseClient,
  shopId: string,
  userId: string,
  role: "manager" | "sales_staff" | "inventory_staff",
  branchIds: string[],
) {
  return client.rpc("owner_set_member_access", {
    p_shop_id: shopId,
    p_user_id: userId.trim(),
    p_role: role,
    p_branch_ids: branchIds,
  });
}

export function suspendMember(
  client: SupabaseClient,
  shopId: string,
  userId: string,
) {
  return client.rpc("owner_suspend_shop_member", {
    p_shop_id: shopId,
    p_user_id: userId,
  });
}

export function reactivateMember(
  client: SupabaseClient,
  shopId: string,
  userId: string,
  branchIds?: string[],
) {
  return client.rpc("owner_reactivate_shop_member", {
    p_shop_id: shopId,
    p_user_id: userId,
    p_branch_ids: branchIds ?? null,
  });
}
