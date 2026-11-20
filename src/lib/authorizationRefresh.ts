import type { SupabaseClient } from "@supabase/supabase-js";

type RefreshEventTarget = {
  addEventListener: (type: string, listener: () => void) => void;
  removeEventListener: (type: string, listener: () => void) => void;
};

type RefreshWindow = RefreshEventTarget & {
  setInterval: (callback: () => void, delayMs: number) => number;
  clearInterval: (id: number) => void;
};

type RefreshDocument = RefreshEventTarget & { visibilityState: string };

export function sameShopContexts<T extends { id: string; name: string; role: string }>(
  current: readonly T[],
  next: readonly T[],
): boolean {
  return current.length === next.length && current.every((shop, index) => {
    const candidate = next[index];
    return candidate !== undefined && shop.id === candidate.id && shop.name === candidate.name && shop.role === candidate.role;
  });
}

export function sameBranchOptions<T extends { id: string; name: string; is_primary: boolean }>(
  current: readonly T[],
  next: readonly T[],
): boolean {
  return current.length === next.length && current.every((branch, index) => {
    const candidate = next[index];
    return candidate !== undefined && branch.id === candidate.id && branch.name === candidate.name && branch.is_primary === candidate.is_primary;
  });
}

export function sameMemberRows<T extends { user_id: string; role: string; status: string }>(
  current: readonly T[],
  next: readonly T[],
): boolean {
  return current.length === next.length && current.every((member, index) => {
    const candidate = next[index];
    return candidate !== undefined && member.user_id === candidate.user_id && member.role === candidate.role && member.status === candidate.status;
  });
}

export function createAuthorizationRefreshQueue<T>(
  load: () => Promise<T>,
  apply: (snapshot: T) => void,
  onError: (error: unknown) => void,
  isActive: () => boolean,
): () => Promise<void> {
  let inFlight = false;
  let refreshQueued = false;

  const run = async (): Promise<void> => {
    if (!isActive()) return;
    if (inFlight) {
      refreshQueued = true;
      return;
    }

    inFlight = true;
    try {
      do {
        refreshQueued = false;
        let snapshot: T;
        try {
          snapshot = await load();
        } catch (error) {
          if (!isActive()) return;
          if (refreshQueued) continue;
          onError(error);
          return;
        }

        if (!isActive()) return;
        if (refreshQueued) continue;
        apply(snapshot);
      } while (refreshQueued && isActive());
    } finally {
      inFlight = false;
      if (refreshQueued && isActive()) {
        refreshQueued = false;
        void run();
      }
    }
  };

  return run;
}

export function watchAuthorizationChanges(
  client: SupabaseClient,
  userId: string,
  onAuthorizationChange: () => void,
  browserWindow: RefreshWindow,
  browserDocument: RefreshDocument,
): () => void {
  const refreshIfVisible = () => {
    if (browserDocument.visibilityState === "visible") onAuthorizationChange();
  };

  const channel = client
    .channel(`stockpilot-authorization:${userId}`)
    .on(
      "postgres_changes",
      {
        event: "UPDATE",
        schema: "public",
        table: "shop_memberships",
        filter: `user_id=eq.${userId}`,
      },
      refreshIfVisible,
    )
    .subscribe();

  browserWindow.addEventListener("focus", refreshIfVisible);
  browserDocument.addEventListener("visibilitychange", refreshIfVisible);
  const intervalId = browserWindow.setInterval(refreshIfVisible, 15_000);

  return () => {
    browserWindow.removeEventListener("focus", refreshIfVisible);
    browserDocument.removeEventListener("visibilitychange", refreshIfVisible);
    browserWindow.clearInterval(intervalId);
    void client.removeChannel(channel).catch(() => undefined);
  };
}
