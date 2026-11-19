export type ShopBranchSelection = {
  shopId: string;
  branchId: string | null;
};

type SelectionStorage = Pick<Storage, "getItem" | "setItem" | "removeItem">;
type StoredSelection = ShopBranchSelection & { version: 1 };

const SELECTION_KEY_PREFIX = "stockpilot-authenticated-selection-v1:";

function browserStorage(): SelectionStorage | null {
  if (typeof window === "undefined") return null;

  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

function selectionKey(userId: string): string | null {
  const normalizedUserId = userId.trim();
  return normalizedUserId
    ? `${SELECTION_KEY_PREFIX}${encodeURIComponent(normalizedUserId)}`
    : null;
}

function isStoredSelection(value: unknown): value is StoredSelection {
  if (!value || typeof value !== "object") return false;

  const candidate = value as Record<string, unknown>;
  return (
    candidate.version === 1 &&
    typeof candidate.shopId === "string" &&
    candidate.shopId.trim().length > 0 &&
    (candidate.branchId === null ||
      (typeof candidate.branchId === "string" && candidate.branchId.trim().length > 0))
  );
}

export function readShopBranchSelection(
  userId: string,
  storage: SelectionStorage | null = browserStorage(),
): ShopBranchSelection | null {
  const key = selectionKey(userId);
  if (!key || !storage) return null;

  let raw: string | null;
  try {
    raw = storage.getItem(key);
  } catch {
    return null;
  }
  if (raw === null) return null;

  try {
    const parsed: unknown = JSON.parse(raw);
    if (isStoredSelection(parsed)) {
      return {
        shopId: parsed.shopId.trim(),
        branchId: parsed.branchId?.trim() || null,
      };
    }
  } catch {
    // Corrupted JSON is discarded below and treated as no saved selection.
  }

  try {
    storage.removeItem(key);
  } catch {
    // Storage can be unavailable or read-only; the invalid value is still ignored.
  }
  return null;
}

export function writeShopBranchSelection(
  userId: string,
  selection: ShopBranchSelection,
  storage: SelectionStorage | null = browserStorage(),
): boolean {
  const key = selectionKey(userId);
  const shopId = selection?.shopId?.trim();
  const branchId = selection?.branchId?.trim() || null;
  if (!key || !storage || !shopId) return false;

  const value: StoredSelection = { version: 1, shopId, branchId };
  try {
    storage.setItem(key, JSON.stringify(value));
    return true;
  } catch {
    return false;
  }
}

export function clearShopBranchSelection(
  userId: string,
  storage: SelectionStorage | null = browserStorage(),
): void {
  const key = selectionKey(userId);
  if (!key || !storage) return;

  try {
    storage.removeItem(key);
  } catch {
    // Ignore unavailable storage; authorization still comes from database queries.
  }
}

export function resolveAuthorizedShopId(
  savedSelection: ShopBranchSelection | null,
  authorizedShopIds: readonly string[],
): string {
  if (savedSelection && authorizedShopIds.includes(savedSelection.shopId)) {
    return savedSelection.shopId;
  }

  if (savedSelection && authorizedShopIds.length > 0) {
    return authorizedShopIds[0];
  }

  return authorizedShopIds.length === 1 ? authorizedShopIds[0] : "";
}

export function resolveAuthorizedBranchId(
  savedSelection: ShopBranchSelection | null,
  currentShopId: string,
  authorizedBranchIds: readonly string[],
): string {
  const savedBranchId =
    savedSelection?.shopId === currentShopId ? savedSelection.branchId : null;

  if (savedBranchId && authorizedBranchIds.includes(savedBranchId)) {
    return savedBranchId;
  }

  if (savedBranchId && authorizedBranchIds.length > 0) {
    return authorizedBranchIds[0];
  }

  return authorizedBranchIds.length === 1 ? authorizedBranchIds[0] : "";
}
