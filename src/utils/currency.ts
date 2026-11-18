
export type CurrencyCode = string;

export type ShopSettings = {
  shopName: string;
  currencyCode: CurrencyCode;
};

export type ShopSettingsSnapshot =
  | { status: "missing"; raw: null; settings: ShopSettings }
  | {
      status: "valid";
      raw: string;
      settings: ShopSettings;
      storedFields: Record<string, unknown>;
    }
  | {
      status: "invalid";
      raw: string;
      message: string;
      storedFields?: Record<string, unknown>;
    }
  | { status: "unavailable"; raw: null; message: string };

export type CurrencyOption = {
  code: CurrencyCode;
  label: string;
  decimalPlaces: number;
};

export type ExchangeRateSnapshot = {
  baseCode: CurrencyCode;
  rates: Record<string, number>;
  fetchedAt: string;
  lastUpdatedAt: string;
  nextUpdateAt: string;
  provider: string;
};

type ExchangeRateApiResponse = {
  result?: string;
  base_code?: string;
  rates?: Record<string, number>;
  time_last_update_utc?: string;
  time_next_update_utc?: string;
};

export const SETTINGS_STORAGE_KEY = "stockpilot-settings";
export const EXCHANGE_RATES_STORAGE_KEY =
  "stockpilot-exchange-rate-snapshots";

export const DEFAULT_SETTINGS: ShopSettings = {
  shopName: "Val Gadgets Demo",
  currencyCode: "UGX",
};

// Modern browsers provide their supported ISO currency codes
// through the internationalisation API.
function getSupportedCurrencyCodes(): string[] {
  const intlWithCurrencyList = Intl as unknown as {
    supportedValuesOf?: (key: "currency") => string[];
  };

  try {
    const codes = intlWithCurrencyList.supportedValuesOf?.("currency");

    if (codes && codes.length > 0) {
      return [...new Set([...codes, "UGX", "KWD", "AED", "CNY"])].sort();
    }
  } catch (error) {
    console.error("Could not load currency list:", error);
  }

  return [
    "AED", "AUD", "BDT", "BHD", "BIF", "BRL", "CAD",
    "CHF", "CNY", "DKK", "EGP", "EUR", "GBP", "GHS",
    "HKD", "IDR", "INR", "IQD", "JOD", "JPY", "KES",
    "KRW", "KWD", "LKR", "MUR", "MWK", "MYR", "NGN",
    "NOK", "NPR", "NZD", "OMR", "PHP", "PKR", "QAR",
    "RUB", "SAR", "SEK", "SGD", "SOS", "TZS", "UGX",
    "USD", "VND", "ZAR", "ZMW",
  ];
}

function getDecimalPlaces(code: CurrencyCode): number {
  try {
    return (
      new Intl.NumberFormat("en-US", {
        style: "currency",
        currency: code,
      }).resolvedOptions().maximumFractionDigits ?? 2
    );
  } catch {
    return 2;
  }
}

export const CURRENCY_OPTIONS: CurrencyOption[] =
  getSupportedCurrencyCodes().map((code) => ({
    code,
    label: code,
    decimalPlaces: getDecimalPlaces(code),
  }));

// Match the currencies presented by StockPilot, rather than accepting any
// three-letter code that Intl happens to format.
const SUPPORTED_CURRENCY_CODES = new Set(
  CURRENCY_OPTIONS.map((option) => option.code)
);

export function getShopSettingsSnapshot(): ShopSettingsSnapshot {
  try {
    const raw = localStorage.getItem(SETTINGS_STORAGE_KEY);

    if (raw === null) {
      return { status: "missing", raw, settings: DEFAULT_SETTINGS };
    }

    let parsed: unknown;

    try {
      parsed = JSON.parse(raw);
    } catch {
      return {
        status: "invalid",
        raw,
        message:
          "Saved shop settings are malformed and could not be parsed. Review them manually; the previous shop name cannot be recovered safely.",
      };
    }

    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return {
        status: "invalid",
        raw,
        message:
          "Saved shop settings have an invalid format. Review them manually; a previous shop name cannot be recovered safely.",
      };
    }

    const storedFields = parsed as Record<string, unknown>;
    const saved = parsed as Partial<ShopSettings>;

    if (!isCurrencyCode(saved.currencyCode)) {
      return {
        status: "invalid",
        raw,
        message:
          "Saved shop currency is missing or invalid. Safely parsed settings were preserved; choose a currency explicitly to repair them.",
        storedFields,
      };
    }

    if (typeof saved.shopName !== "string" || !saved.shopName.trim()) {
      return {
        status: "invalid",
        raw,
        message:
          "Saved shop name is missing or invalid. Safely parsed settings were preserved; enter a shop name and choose a currency explicitly to repair them.",
        storedFields,
      };
    }

    return {
      status: "valid",
      raw,
      settings: {
        shopName: saved.shopName,
        currencyCode: saved.currencyCode,
      },
      storedFields,
    };
  } catch (error) {
    console.error("Could not load shop settings:", error);
    return {
      status: "unavailable",
      raw: null,
      message: "Shop settings could not be read from browser storage.",
    };
  }
}

export function getShopSettings(): ShopSettings | null {
  const snapshot = getShopSettingsSnapshot();
  return snapshot.status === "valid" || snapshot.status === "missing"
    ? snapshot.settings
    : null;
}

export function getShopCurrency(): CurrencyCode | null {
  const snapshot = getShopSettingsSnapshot();
  return snapshot.status === "valid" || snapshot.status === "missing"
    ? snapshot.settings.currencyCode
    : null;
}

export function saveShopSettings(
  settings: ShopSettings,
  expectedRaw: string | null,
  allowRepair = false,
): "saved" | "conflict" | "invalid" | "error" {
  try {
    const current = getShopSettingsSnapshot();

    if (current.status === "unavailable") {
      return "error";
    }

    if (current.raw !== expectedRaw) {
      return "conflict";
    }

    if (current.status === "invalid" && !allowRepair) {
      return "invalid";
    }

    if (!isCurrencyCode(settings.currencyCode)) {
      return "invalid";
    }

    const preservedFields =
      current.status === "valid" || current.status === "invalid"
        ? current.storedFields ?? {}
        : {};

    const settingsToSave = {
      ...preservedFields,
      shopName: settings.shopName.trim(),
      currencyCode: settings.currencyCode,
    };

    localStorage.setItem(
      SETTINGS_STORAGE_KEY,
      JSON.stringify(settingsToSave),
    );
    return "saved";
  } catch (error) {
    console.error("Could not save shop settings:", error);
    return "error";
  }
}

export function isCurrencyCode(value: unknown): value is CurrencyCode {
  return (
    typeof value === "string" &&
    SUPPORTED_CURRENCY_CODES.has(value)
  );
}

// Strict lookup for record snapshots. Unknown historical currency must not be
// treated as a real currency in display or financial calculations.
export function getKnownRecordCurrency(
  currencyCode: unknown,
): CurrencyCode | null {
  return isCurrencyCode(currencyCode) ? currencyCode : null;
}

// Backward-compatible fallback for callers whose business rule explicitly
// requires a default. Do not use this for historical financial records.
export function getRecordCurrency(
  currencyCode?: string | null,
): CurrencyCode {
  return isCurrencyCode(currencyCode) ? currencyCode : "UGX";
}

export function formatCurrency(
  amount: number,
  currencyCode?: string | null,
): string {
  const safeCurrency = getKnownRecordCurrency(currencyCode);

  if (!Number.isFinite(amount)) {
    return safeCurrency
      ? `Amount unavailable (${safeCurrency})`
      : "Amount and currency unavailable";
  }

  if (!safeCurrency) {
    const amountWithoutCurrency = new Intl.NumberFormat("en-US", {
      maximumFractionDigits: 20,
    }).format(amount);

    return `${amountWithoutCurrency} (currency unavailable)`;
  }

  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: safeCurrency,
    minimumFractionDigits: getDecimalPlaces(safeCurrency),
    maximumFractionDigits: getDecimalPlaces(safeCurrency),
  }).format(amount);
}

export function parseMoneyInput(value: string): number {
  const parsed = Number(value.replace(/,/g, "").trim());

  return Number.isFinite(parsed) ? parsed : 0;
}

// A numeric zero is a known cost; missing, malformed, non-finite, and negative
// values remain unknown instead of being treated as zero.
export function getKnownCostAmount(value: unknown): number | null {
  if (typeof value === "number") {
    return Number.isFinite(value) && value >= 0 ? value : null;
  }

  if (typeof value !== "string") {
    return null;
  }

  const normalized = value.trim();
  if (
    normalized === "" ||
    !/^(?:\d+(?:\.\d*)?|\.\d+)$/.test(normalized)
  ) {
    return null;
  }

  const amount = Number(normalized);
  return Number.isFinite(amount) && amount >= 0 ? amount : null;
}

export function getKnownNonNegativeAmount(value: unknown): number | null {
  return typeof value === "number" &&
    Number.isFinite(value) &&
    value >= 0
    ? value
    : null;
}

export function getKnownOutstandingBalance(
  principal: unknown,
  paid: unknown,
): number | null {
  const knownPrincipal = getKnownNonNegativeAmount(principal);
  const knownPaid = getKnownNonNegativeAmount(paid);

  if (
    knownPrincipal === null ||
    knownPaid === null ||
    knownPaid > knownPrincipal
  ) {
    return null;
  }

  const balance = knownPrincipal - knownPaid;
  return Number.isFinite(balance) ? balance : null;
}

export function getKnownSaleAmount(value: unknown): number | null {
  return getKnownNonNegativeAmount(value);
}

export function getKnownStockQuantity(value: unknown): number | null {
  return typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= 0
    ? value
    : null;
}

export function formatMoneyInput(
  value: string,
  currencyCode: CurrencyCode,
): string {
  const knownCurrency = getKnownRecordCurrency(currencyCode);
  const decimalPlaces = knownCurrency ? getDecimalPlaces(knownCurrency) : 2;

  const cleaned = value
    .replace(/,/g, "")
    .replace(/[^\d.]/g, "");

  const parts = cleaned.split(".");
  const integerPart = parts[0] ?? "";
  const decimalPart = parts.slice(1).join("").slice(0, decimalPlaces);

  const groupedInteger = integerPart.replace(
    /\B(?=(\d{3})+(?!\d))/g,
    ",",
  );

  if (decimalPlaces === 0) {
    return groupedInteger;
  }

  return parts.length > 1
    ? `${groupedInteger}.${decimalPart}`
    : groupedInteger;
}

// Read previously saved exchange-rate snapshots without changing them.
export function getSavedExchangeRateSnapshot(
  baseCode: CurrencyCode,
): ExchangeRateSnapshot | null {
  try {
    const saved = localStorage.getItem(EXCHANGE_RATES_STORAGE_KEY);

    if (!saved) return null;

    const parsed: unknown = JSON.parse(saved);
    if (
      parsed === null ||
      typeof parsed !== "object" ||
      Array.isArray(parsed)
    ) {
      return null;
    }

    const snapshot = (parsed as Record<string, unknown>)[baseCode];

    if (
      snapshot === null ||
      typeof snapshot !== "object" ||
      Array.isArray(snapshot)
    ) {
      return null;
    }

    const candidate = snapshot as Record<string, unknown>;
    const rates = candidate.rates;
    if (
      candidate.baseCode !== baseCode ||
      typeof candidate.fetchedAt !== "string" ||
      !Number.isFinite(Date.parse(candidate.fetchedAt)) ||
      typeof candidate.lastUpdatedAt !== "string" ||
      !Number.isFinite(Date.parse(candidate.lastUpdatedAt)) ||
      typeof candidate.nextUpdateAt !== "string" ||
      !Number.isFinite(Date.parse(candidate.nextUpdateAt)) ||
      typeof candidate.provider !== "string" ||
      !candidate.provider.trim() ||
      rates === null ||
      typeof rates !== "object" ||
      Array.isArray(rates)
    ) {
      return null;
    }

    const knownRates: Record<string, number> = {};
    for (const [code, rate] of Object.entries(rates)) {
      if (
        !isCurrencyCode(code) ||
        typeof rate !== "number" ||
        !Number.isFinite(rate) ||
        rate <= 0
      ) {
        return null;
      }
      knownRates[code] = rate;
    }

    return {
      baseCode,
      rates: knownRates,
      fetchedAt: candidate.fetchedAt,
      lastUpdatedAt: candidate.lastUpdatedAt,
      nextUpdateAt: candidate.nextUpdateAt,
      provider: candidate.provider,
    };
  } catch (error) {
    console.error("Could not read exchange-rate snapshot:", error);
    return null;
  }
}

// Check whether the saved snapshot has reached its provider update time.
export function isExchangeRateSnapshotExpired(
  snapshot: ExchangeRateSnapshot,
): boolean {
  const nextUpdate = new Date(snapshot.nextUpdateAt).getTime();

  if (!Number.isFinite(nextUpdate)) return true;

  return Date.now() >= nextUpdate;
}

// Fetch a fresh daily reference-rate table and save its snapshot.
// This function does not modify any purchase, credit, or payment records.
export async function refreshExchangeRateSnapshot(
  baseCode: CurrencyCode,
): Promise<ExchangeRateSnapshot> {
  if (!isCurrencyCode(baseCode)) {
    throw new Error("The selected operating currency is invalid.");
  }

  const response = await fetch(
    `https://open.er-api.com/v6/latest/${baseCode}`,
  );

  if (!response.ok) {
    throw new Error(
      `Exchange-rate service returned HTTP ${response.status}.`,
    );
  }

  const data = (await response.json()) as ExchangeRateApiResponse;

  if (
    data.result !== "success" ||
    data.base_code !== baseCode ||
    !data.rates ||
    typeof data.rates !== "object"
  ) {
    throw new Error(
      "The exchange-rate service returned an invalid response.",
    );
  }

  const rates: Record<string, number> = {};

  Object.entries(data.rates).forEach(([code, rate]) => {
    if (
      isCurrencyCode(code) &&
      typeof rate === "number" &&
      Number.isFinite(rate) &&
      rate > 0
    ) {
      rates[code] = rate;
    }
  });

  rates[baseCode] = 1;

  const now = new Date();
  const lastUpdatedAt =
    data.time_last_update_utc &&
    Number.isFinite(Date.parse(data.time_last_update_utc))
      ? new Date(data.time_last_update_utc).toISOString()
      : now.toISOString();

  const nextUpdateAt =
    data.time_next_update_utc &&
    Number.isFinite(Date.parse(data.time_next_update_utc))
      ? new Date(data.time_next_update_utc).toISOString()
      : new Date(now.getTime() + 24 * 60 * 60 * 1000).toISOString();

  const snapshot: ExchangeRateSnapshot = {
    baseCode,
    rates,
    fetchedAt: now.toISOString(),
    lastUpdatedAt,
    nextUpdateAt,
    provider: "ExchangeRate-API Open Access",
  };

  try {
    const saved = localStorage.getItem(EXCHANGE_RATES_STORAGE_KEY);
    let allSnapshots: Record<string, unknown> = {};

    if (saved !== null) {
      const parsed: unknown = JSON.parse(saved);
      if (
        parsed === null ||
        typeof parsed !== "object" ||
        Array.isArray(parsed)
      ) {
        throw new Error("Saved exchange-rate snapshots have an invalid format.");
      }
      allSnapshots = parsed as Record<string, unknown>;
    }

    allSnapshots[baseCode] = snapshot;

    localStorage.setItem(
      EXCHANGE_RATES_STORAGE_KEY,
      JSON.stringify(allSnapshots),
    );
  } catch (error) {
    console.error("Could not save exchange-rate snapshot:", error);
    throw new Error("Could not save exchange rates in browser storage.");
  }

  return snapshot;
}

// Convert an amount into the snapshot's base currency.
// The rate table is based on 1 unit of the base currency.
// Example: if 1 UGX = 0.00028 AED, AED is divided by that rate
// to calculate its UGX equivalent.
export function convertToSnapshotCurrency(
  amount: number,
  fromCode: string | null | undefined,
  snapshot: ExchangeRateSnapshot,
): number | null {
  if (!Number.isFinite(amount)) return null;

  const sourceCode = getKnownRecordCurrency(fromCode);
  const baseCode = getKnownRecordCurrency(snapshot.baseCode);

  if (!sourceCode || !baseCode) return null;

  if (sourceCode === baseCode) return amount;

  const sourceRate = snapshot.rates[sourceCode];

  if (
    typeof sourceRate !== "number" ||
    !Number.isFinite(sourceRate) ||
    sourceRate <= 0
  ) {
    return null;
  }

  const converted = amount / sourceRate;
  return Number.isFinite(converted) ? converted : null;
}
