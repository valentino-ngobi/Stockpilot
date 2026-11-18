import { afterEach, describe, expect, it, vi } from "vitest";
import {
  convertToSnapshotCurrency,
  EXCHANGE_RATES_STORAGE_KEY,
  formatCurrency,
  getKnownCostAmount,
  getKnownNonNegativeAmount,
  getKnownOutstandingBalance,
  getKnownSaleAmount,
  getKnownStockQuantity,
  getSavedExchangeRateSnapshot,
  type ExchangeRateSnapshot,
} from "./currency";

describe("financial value validation", () => {
  it("accepts non-negative finite numeric sale amounts, including zero", () => {
    expect(getKnownSaleAmount(0)).toBe(0);
    expect(getKnownSaleAmount(125.5)).toBe(125.5);
  });

  it.each([-1, Number.NaN, Number.POSITIVE_INFINITY, "12", null])(
    "rejects invalid sale amounts: %s",
    (value) => {
      expect(getKnownSaleAmount(value)).toBeNull();
    },
  );

  it("accepts known zero costs but leaves missing and invalid costs unknown", () => {
    expect(getKnownCostAmount(0)).toBe(0);
    expect(getKnownCostAmount("0")).toBe(0);
    expect(getKnownCostAmount("12.50")).toBe(12.5);
    expect(getKnownCostAmount("")).toBeNull();
    expect(getKnownCostAmount("not-a-number")).toBeNull();
    expect(getKnownCostAmount(Number.NaN)).toBeNull();
    expect(getKnownCostAmount(-1)).toBeNull();
    expect(getKnownCostAmount(undefined)).toBeNull();
  });

  it.each(["0x10", "1e3", "+12", "1,000"])(
    "rejects non-decimal cost strings: %s",
    (value) => {
      expect(getKnownCostAmount(value)).toBeNull();
    },
  );

  it("requires stored transaction amounts to be finite non-negative numbers", () => {
    expect(getKnownNonNegativeAmount(0)).toBe(0);
    expect(getKnownNonNegativeAmount(12.5)).toBe(12.5);
    expect(getKnownNonNegativeAmount("12.5")).toBeNull();
    expect(getKnownNonNegativeAmount(-1)).toBeNull();
    expect(getKnownNonNegativeAmount(Number.POSITIVE_INFINITY)).toBeNull();
  });

  it("rejects outstanding balances when payments exceed the principal", () => {
    expect(getKnownOutstandingBalance(100, 30)).toBe(70);
    expect(getKnownOutstandingBalance(100, 100)).toBe(0);
    expect(getKnownOutstandingBalance(100, 101)).toBeNull();
    expect(getKnownOutstandingBalance(100, Number.NaN)).toBeNull();
  });

  it("accepts non-negative safe integer stock quantities, including zero", () => {
    expect(getKnownStockQuantity(0)).toBe(0);
    expect(getKnownStockQuantity(12)).toBe(12);
  });

  it.each([-1, 1.5, Number.NaN, Number.POSITIVE_INFINITY, Number.MAX_SAFE_INTEGER + 1, "12"])(
    "rejects invalid stock quantities: %s",
    (value) => {
      expect(getKnownStockQuantity(value)).toBeNull();
    },
  );

  it("formats non-finite amounts as unavailable instead of zero", () => {
    expect(formatCurrency(Number.NaN, "UGX")).toBe(
      "Amount unavailable (UGX)",
    );
    expect(formatCurrency(Number.POSITIVE_INFINITY, null)).toBe(
      "Amount and currency unavailable",
    );
  });
});

describe("exchange-rate snapshots", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("ignores malformed snapshots without overwriting them", () => {
    const stored = JSON.stringify({
      UGX: {
        baseCode: "UGX",
        rates: { USD: Number.NaN },
        fetchedAt: "2026-01-01T00:00:00.000Z",
        lastUpdatedAt: "2026-01-01T00:00:00.000Z",
        nextUpdateAt: "2026-01-02T00:00:00.000Z",
        provider: "test",
      },
    });
    const values = new Map([[EXCHANGE_RATES_STORAGE_KEY, stored]]);
    vi.stubGlobal("localStorage", {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => values.set(key, value),
    });

    expect(getSavedExchangeRateSnapshot("UGX")).toBeNull();
    expect(values.get(EXCHANGE_RATES_STORAGE_KEY)).toBe(stored);
  });

  it("rejects snapshots with invalid timestamps", () => {
    const stored = JSON.stringify({
      UGX: {
        baseCode: "UGX",
        rates: { USD: 0.00026 },
        fetchedAt: "not-a-date",
        lastUpdatedAt: "2026-01-01T00:00:00.000Z",
        nextUpdateAt: "2026-01-02T00:00:00.000Z",
        provider: "test",
      },
    });
    const values = new Map([[EXCHANGE_RATES_STORAGE_KEY, stored]]);
    vi.stubGlobal("localStorage", {
      getItem: (key: string) => values.get(key) ?? null,
    });

    expect(getSavedExchangeRateSnapshot("UGX")).toBeNull();
    expect(values.get(EXCHANGE_RATES_STORAGE_KEY)).toBe(stored);
  });

  it("rejects conversions that overflow to a non-finite result", () => {
    const snapshot: ExchangeRateSnapshot = {
      baseCode: "UGX",
      rates: { UGX: 1, USD: Number.MIN_VALUE },
      fetchedAt: "2026-01-01T00:00:00.000Z",
      lastUpdatedAt: "2026-01-01T00:00:00.000Z",
      nextUpdateAt: "2026-01-02T00:00:00.000Z",
      provider: "test",
    };

    expect(
      convertToSnapshotCurrency(Number.MAX_VALUE, "USD", snapshot),
    ).toBeNull();
  });
});
