
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

export const SETTINGS_STORAGE_KEY = "stockpilot-settings";

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
      return [...new Set([...codes, "UGX", "KWD", "AED", "CNY"])]
        .sort();
    }
  } catch (error) {
    console.error("Could not load currency list:", error);
  }

  // Fallback for browsers without supportedValuesOf.
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
