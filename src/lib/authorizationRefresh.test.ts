import { describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  createAuthorizationRefreshQueue,
  sameBranchOptions,
  sameMemberRows,
  sameShopContexts,
  watchAuthorizationChanges,
} from "./authorizationRefresh";

function createEventTarget() {
  const listeners = new Map<string, () => void>();
  return {
    addEventListener: vi.fn((type: string, listener: () => void) => listeners.set(type, listener)),
    removeEventListener: vi.fn((type: string) => listeners.delete(type)),
    dispatch: (type: string) => listeners.get(type)?.(),
    listeners,
  };
}

describe("authorization refresh watcher", () => {
  it("rechecks on the user's membership update, focus, visibility, and fallback interval", () => {
    const channel = {
      on: vi.fn().mockReturnThis(),
      subscribe: vi.fn().mockReturnThis(),
    };
    const client = {
      channel: vi.fn(() => channel),
      removeChannel: vi.fn().mockResolvedValue("ok"),
    } as unknown as SupabaseClient;
    let intervalCallback: (() => void) | undefined;
    const browserWindow = Object.assign(createEventTarget(), {
      setInterval: vi.fn((callback: () => void, delayMs: number): number => {
        expect(delayMs).toBe(15_000);
        intervalCallback = callback;
        return 7;
      }),
      clearInterval: vi.fn((_id: number) => undefined),
    });
    const browserDocument = Object.assign(createEventTarget(), { visibilityState: "visible" });
    const onAuthorizationChange = vi.fn();

    const unsubscribe = watchAuthorizationChanges(
      client,
      "user-a",
      onAuthorizationChange,
      browserWindow,
      browserDocument,
    );

    expect(client.channel).toHaveBeenCalledWith("stockpilot-authorization:user-a");
    expect(channel.on).toHaveBeenCalledWith(
      "postgres_changes",
      {
        event: "UPDATE",
        schema: "public",
        table: "shop_memberships",
        filter: "user_id=eq.user-a",
      },
      expect.any(Function),
    );
    const realtimeHandler = channel.on.mock.calls[0][2] as () => void;
    realtimeHandler();
    browserWindow.dispatch("focus");
    browserDocument.dispatch("visibilitychange");
    intervalCallback?.();
    expect(onAuthorizationChange).toHaveBeenCalledTimes(4);

    browserDocument.visibilityState = "hidden";
    browserWindow.dispatch("focus");
    intervalCallback?.();
    expect(onAuthorizationChange).toHaveBeenCalledTimes(4);

    unsubscribe();
    expect(browserWindow.removeEventListener).toHaveBeenCalledWith("focus", expect.any(Function));
    expect(browserDocument.removeEventListener).toHaveBeenCalledWith("visibilitychange", expect.any(Function));
    expect(browserWindow.clearInterval).toHaveBeenCalledWith(7);
    expect(client.removeChannel).toHaveBeenCalledWith(channel);
  });
});

describe("authorization refresh queue", () => {
  it("recognizes unchanged access snapshots without replacing their state", () => {
    expect(
      sameShopContexts(
        [{ id: "shop-a", name: "Shop A", role: "owner" }],
        [{ id: "shop-a", name: "Shop A", role: "owner" }],
      ),
    ).toBe(true);
    expect(
      sameShopContexts(
        [{ id: "shop-a", name: "Shop A", role: "owner" }],
        [{ id: "shop-a", name: "Shop A", role: "manager" }],
      ),
    ).toBe(false);
    expect(
      sameBranchOptions(
        [{ id: "branch-a", name: "Main", is_primary: true }],
        [{ id: "branch-a", name: "Main", is_primary: true }],
      ),
    ).toBe(true);
    expect(
      sameBranchOptions(
        [{ id: "branch-a", name: "Main", is_primary: true }],
        [{ id: "branch-b", name: "Kampala", is_primary: false }],
      ),
    ).toBe(false);
    expect(
      sameMemberRows(
        [{ user_id: "user-a", role: "manager", status: "active" }],
        [{ user_id: "user-a", role: "manager", status: "active" }],
      ),
    ).toBe(true);
  });

  it("coalesces overlapping signals and discards a stale snapshot before applying it", async () => {
    let releaseFirstLoad!: (value: string) => void;
    const firstLoad = new Promise<string>((resolve) => {
      releaseFirstLoad = resolve;
    });
    let activeLoads = 0;
    let maximumActiveLoads = 0;
    const load = vi.fn()
      .mockImplementationOnce(async () => {
        activeLoads += 1;
        maximumActiveLoads = Math.max(maximumActiveLoads, activeLoads);
        try {
          return await firstLoad;
        } finally {
          activeLoads -= 1;
        }
      })
      .mockImplementationOnce(async () => {
        activeLoads += 1;
        maximumActiveLoads = Math.max(maximumActiveLoads, activeLoads);
        try {
          return "latest authorization";
        } finally {
          activeLoads -= 1;
        }
      });
    const apply = vi.fn();
    const onError = vi.fn();
    const refresh = createAuthorizationRefreshQueue(load, apply, onError, () => true);

    const firstRequest = refresh();
    await Promise.resolve();
    await refresh();
    await refresh();

    expect(load).toHaveBeenCalledOnce();
    releaseFirstLoad("stale authorization");
    await firstRequest;

    expect(load).toHaveBeenCalledTimes(2);
    expect(maximumActiveLoads).toBe(1);
    expect(apply).toHaveBeenCalledOnce();
    expect(apply).toHaveBeenCalledWith("latest authorization");
    expect(apply).not.toHaveBeenCalledWith("stale authorization");
    expect(onError).not.toHaveBeenCalled();
  });

  it("fails closed through the error callback when a current refresh fails", async () => {
    const error = new Error("membership query failed");
    const apply = vi.fn();
    const onError = vi.fn();
    const refresh = createAuthorizationRefreshQueue(
      async () => { throw error; },
      apply,
      onError,
      () => true,
    );

    await refresh();

    expect(apply).not.toHaveBeenCalled();
    expect(onError).toHaveBeenCalledOnce();
    expect(onError).toHaveBeenCalledWith(error);
  });

  it("does not apply a response after the authenticated view becomes inactive", async () => {
    let releaseLoad!: (value: string) => void;
    let active = true;
    const apply = vi.fn();
    const onError = vi.fn();
    const refresh = createAuthorizationRefreshQueue(
      () => new Promise<string>((resolve) => { releaseLoad = resolve; }),
      apply,
      onError,
      () => active,
    );

    const pendingRefresh = refresh();
    await Promise.resolve();
    active = false;
    releaseLoad("previous account authorization");
    await pendingRefresh;

    expect(apply).not.toHaveBeenCalled();
    expect(onError).not.toHaveBeenCalled();
  });
});
