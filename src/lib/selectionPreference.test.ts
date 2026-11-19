import { describe, expect, it } from "vitest";
import {
  readShopBranchSelection,
  resolveAuthorizedBranchId,
  resolveAuthorizedShopId,
  writeShopBranchSelection,
} from "./selectionPreference";

function createMemoryStorage() {
  const values = new Map<string, string>();
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
    removeItem: (key: string) => values.delete(key),
    values,
  };
}

describe("authenticated shop and branch selection preference", () => {
  it("restores the selected branch after a refresh", () => {
    const storage = createMemoryStorage();
    expect(
      writeShopBranchSelection("user-a", { shopId: "shop-a", branchId: "branch-kampala" }, storage),
    ).toBe(true);

    const restored = readShopBranchSelection("user-a", storage);
    expect(restored).toEqual({ shopId: "shop-a", branchId: "branch-kampala" });
    expect(resolveAuthorizedBranchId(restored, "shop-a", ["branch-main", "branch-kampala"]))
      .toBe("branch-kampala");
  });

  it("restores the selected business while leaving branch selection empty", () => {
    const storage = createMemoryStorage();
    writeShopBranchSelection("user-a", { shopId: "shop-second", branchId: null }, storage);

    const restored = readShopBranchSelection("user-a", storage);
    expect(resolveAuthorizedShopId(restored, ["shop-main", "shop-second"]))
      .toBe("shop-second");
    expect(restored?.branchId).toBeNull();
  });

  it("does not share a saved selection between accounts using the same browser", () => {
    const storage = createMemoryStorage();
    writeShopBranchSelection("user-a", { shopId: "shop-a", branchId: "branch-a" }, storage);

    expect(readShopBranchSelection("user-b", storage)).toBeNull();
    expect(readShopBranchSelection("user-a", storage)).toEqual({
      shopId: "shop-a",
      branchId: "branch-a",
    });
  });

  it("rejects revoked shops and branches and chooses only authorized fallbacks", () => {
    const revokedShopSelection = { shopId: "shop-revoked", branchId: "branch-revoked" };
    const shopId = resolveAuthorizedShopId(revokedShopSelection, ["shop-authorized"]);
    expect(shopId).toBe("shop-authorized");

    const revokedBranchSelection = { shopId: "shop-authorized", branchId: "branch-revoked" };
    expect(resolveAuthorizedBranchId(revokedBranchSelection, shopId, ["branch-authorized"]))
      .toBe("branch-authorized");
    expect(resolveAuthorizedBranchId(revokedBranchSelection, shopId, [])).toBe("");
  });

  it("safely ignores missing or corrupted selection data", () => {
    const storage = createMemoryStorage();
    expect(readShopBranchSelection("user-a", storage)).toBeNull();

    const key = "stockpilot-authenticated-selection-v1:user-a";
    storage.setItem(key, "not-json");
    expect(readShopBranchSelection("user-a", storage)).toBeNull();
    expect(storage.getItem(key)).toBeNull();

    storage.setItem(key, JSON.stringify({ version: 1, shopId: "shop-a", branchId: 17 }));
    expect(readShopBranchSelection("user-a", storage)).toBeNull();
    expect(storage.getItem(key)).toBeNull();
  });

  it("preserves the same user's preference across sign-out and later sign-in", () => {
    const storage = createMemoryStorage();
    writeShopBranchSelection("user-a", { shopId: "shop-a", branchId: "branch-a" }, storage);

    // Sign-out clears authenticated UI state, not this user-scoped preference.
    const afterSignOut = readShopBranchSelection("user-a", storage);
    expect(afterSignOut?.branchId).toBe("branch-a");
    // A later sign-in restores it for the same account.
    expect(readShopBranchSelection("user-a", storage)).toEqual({
      shopId: "shop-a",
      branchId: "branch-a",
    });
    expect(readShopBranchSelection("user-b", storage)).toBeNull();
  });

  it("ignores a saved branch when storage cannot be read", () => {
    const unreadableStorage = {
      getItem: () => { throw new Error("storage unavailable"); },
      setItem: () => { throw new Error("storage unavailable"); },
      removeItem: () => { throw new Error("storage unavailable"); },
    };
    expect(readShopBranchSelection("user-a", unreadableStorage)).toBeNull();
  });
});
