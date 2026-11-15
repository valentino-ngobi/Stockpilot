
export type CurrencyCode = string;

export type ShopSettings = {
  shopName: string;
  currencyCode: CurrencyCode;
};

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

export function getShopSettings(): ShopSettings {
  try {
    const saved = localStorage.getItem(SETTINGS_STORAGE_KEY);

    if (saved) {
      const parsed = JSON.parse(saved) as Partial<ShopSettings>;

      return {
        shopName: parsed.shopName || DEFAULT_SETTINGS.shopName,
        currencyCode: isCurrencyCode(parsed.currencyCode)
          ? parsed.currencyCode
          : DEFAULT_SETTINGS.currencyCode,
      };
    }
  } catch (error) {
    console.error("Could not load shop settings:", error);
  }

  return DEFAULT_SETTINGS;
}

export function saveShopSettings(settings: ShopSettings): void {
  try {
    const settingsToSave: ShopSettings = {
      shopName: settings.shopName.trim(),
      currencyCode: settings.currencyCode,
    };

    localStorage.setItem(
      SETTINGS_STORAGE_KEY,
      JSON.stringify(settingsToSave),
    );
  } catch (error) {
    console.error("Could not save shop settings:", error);
  }
}

export function getShopCurrency(): CurrencyCode {
  return getShopSettings().currencyCode;
}

export function isCurrencyCode(value: unknown): value is CurrencyCode {
  if (typeof value !== "string" || !/^[A-Z]{3}$/.test(value)) {
    return false;
  }

  try {
    new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: value,
    });

    return true;
  } catch {
    return false;
  }
}

// Existing records without a currency code remain UGX.
export function getRecordCurrency(
  currencyCode?: string | null,
): CurrencyCode {
  return isCurrencyCode(currencyCode) ? currencyCode : "UGX";
}

export function formatCurrency(
  amount: number,
  currencyCode: CurrencyCode = "UGX",
): string {
  const safeCurrency = getRecordCurrency(currencyCode);

  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: safeCurrency,
    minimumFractionDigits: getDecimalPlaces(safeCurrency),
    maximumFractionDigits: getDecimalPlaces(safeCurrency),
  }).format(Number.isFinite(amount) ? amount : 0);
}

export function parseMoneyInput(value: string): number {
  const parsed = Number(value.replace(/,/g, "").trim());

  return Number.isFinite(parsed) ? parsed : 0;
}

export function formatMoneyInput(
  value: string,
  currencyCode: CurrencyCode,
): string {
  const decimalPlaces = getDecimalPlaces(
    getRecordCurrency(currencyCode),
  );

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

    const parsed = JSON.parse(saved) as Record<
      string,
      ExchangeRateSnapshot
    >;

    const snapshot = parsed[baseCode];

    if (
      !snapshot ||
      snapshot.baseCode !== baseCode ||
      typeof snapshot.rates !== "object" ||
      !snapshot.rates
    ) {
      return null;
    }

    return snapshot;
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
    const allSnapshots = saved
      ? (JSON.parse(saved) as Record<string, ExchangeRateSnapshot>)
      : {};

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
  fromCode: CurrencyCode,
  snapshot: ExchangeRateSnapshot,
): number | null {
  if (!Number.isFinite(amount)) return null;

  const sourceCode = getRecordCurrency(fromCode);
  const baseCode = snapshot.baseCode;

  if (sourceCode === baseCode) return amount;

  const sourceRate = snapshot.rates[sourceCode];

  if (
    typeof sourceRate !== "number" ||
    !Number.isFinite(sourceRate) ||
    sourceRate <= 0
  ) {
    return null;
  }

  return amount / sourceRate;
}
