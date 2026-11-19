import { beforeEach, describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  createBranch,
  createShopForCurrentUser,
  loginWithEmail,
  logout,
  registerWithEmail,
  restoreSession,
  setMemberAccess,
  suspendMember,
} from "./auth";
import { resolveSupabaseConfiguration } from "./supabaseConfig";

function createClientMock() {
  const client = {
    auth: {
      signUp: vi.fn(),
      signInWithPassword: vi.fn(),
      getSession: vi.fn(),
      signOut: vi.fn(),
    },
    rpc: vi.fn(),
  };

  return client as unknown as SupabaseClient & typeof client;
}

describe("Supabase configuration mode", () => {
  it("keeps the prototype mode when neither setting is present", () => {
    expect(resolveSupabaseConfiguration(undefined, undefined)).toEqual({
      mode: "prototype",
    });
  });

  it("fails closed when only one setting is present", () => {
    expect(resolveSupabaseConfiguration("https://example.supabase.co", "").mode)
      .toBe("invalid");
  });

  it("rejects Supabase secret and service-role keys in browser configuration", () => {
    expect(
      resolveSupabaseConfiguration("https://example.supabase.co", "sb_secret_example").mode,
    ).toBe("invalid");
    const serviceRoleJwt = `header.${btoa(JSON.stringify({ role: "service_role" }))}.signature`;
    expect(
      resolveSupabaseConfiguration("https://example.supabase.co", serviceRoleJwt).mode,
    ).toBe("invalid");
  });

  it("accepts a complete HTTPS configuration", () => {
    expect(
      resolveSupabaseConfiguration(
        "https://example.supabase.co",
        "public-test-key",
      ),
    ).toEqual({
      mode: "configured",
      url: "https://example.supabase.co",
      publishableKey: "public-test-key",
    });
  });

  it("allows local HTTP only for local development", () => {
    expect(
      resolveSupabaseConfiguration("http://127.0.0.1:54321", "local-key").mode,
    ).toBe("configured");
    expect(
      resolveSupabaseConfiguration("http://example.com", "public-test-key").mode,
    ).toBe("invalid");
  });
});

describe("authentication and tenant service calls", () => {
  let client: ReturnType<typeof createClientMock>;

  beforeEach(() => {
    client = createClientMock();
  });

  it("registers an email user with display-name metadata", () => {
    registerWithEmail(client, " user@example.test ", "fictional-passphrase", " Demo User ");

    expect(client.auth.signUp).toHaveBeenCalledWith({
      email: "user@example.test",
      password: "fictional-passphrase",
      options: { data: { display_name: "Demo User" } },
    });
  });

  it("logs in by email and password", () => {
    loginWithEmail(client, " user@example.test ", "fictional-passphrase");

    expect(client.auth.signInWithPassword).toHaveBeenCalledWith({
      email: "user@example.test",
      password: "fictional-passphrase",
    });
  });

  it("restores the Supabase session", () => {
    restoreSession(client);
    expect(client.auth.getSession).toHaveBeenCalledOnce();
  });

  it("logs out through Supabase Auth", () => {
    logout(client);
    expect(client.auth.signOut).toHaveBeenCalledOnce();
  });

  it("creates a shop only through the owner-onboarding RPC", () => {
    createShopForCurrentUser(client, "  Fictional Shop  ");
    expect(client.rpc).toHaveBeenCalledWith("create_shop_for_current_user", {
      p_name: "Fictional Shop",
    });
  });

  it("uses scoped database functions for branch and member changes", () => {
    createBranch(client, "shop-id", " Branch Two ");
    setMemberAccess(client, "shop-id", "registered-user-id", "sales_staff", ["branch-id"]);
    suspendMember(client, "shop-id", "registered-user-id");

    expect(client.rpc).toHaveBeenNthCalledWith(1, "create_branch", {
      p_shop_id: "shop-id",
      p_name: "Branch Two",
    });
    expect(client.rpc).toHaveBeenNthCalledWith(2, "owner_set_member_access", {
      p_shop_id: "shop-id",
      p_user_id: "registered-user-id",
      p_role: "sales_staff",
      p_branch_ids: ["branch-id"],
    });
    expect(client.rpc).toHaveBeenNthCalledWith(3, "owner_suspend_shop_member", {
      p_shop_id: "shop-id",
      p_user_id: "registered-user-id",
    });
  });
});
