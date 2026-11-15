
export type CurrencyCode = "UGX" | "USD" | "KWD";

export type ShopSettings = {
  shopName: string;
  currencyCode: CurrencyCode;
};

export const SETTINGS_STORAGE_KEY = "stockpilot-settings";

export const DEFAULT_SETTINGS: ShopSettings = {
  shopName: "Val Gadgets Demo",
  currencyCode: "UGX",
};

export const CURRENCY_OPTIONS: {
  code: CurrencyCode;
  label: string;
  decimalPlaces: number;
}[] = [
  { code: "UGX", label: "Ugandan Shilling (UGX)", decimalPlaces: 0 },
  { code: "USD", label: "US Dollar (USD)", decimalPlaces: 2 },
  { code: "KWD", label: "Kuwaiti Dinar (KWD)", decimalPlaces: 3 },
];

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
    localStorage.setItem(SETTINGS_STORAGE_KEY, JSON.stringify(settings));
  } catch (error) {
    console.error("Could not save shop settings:", error);
  }
}

export function getShopCurrency(): CurrencyCode {
  return getShopSettings().currencyCode;
}

export function isCurrencyCode(value: unknown): value is CurrencyCode {
  return value === "UGX" || value === "USD" || value === "KWD";
}

// Legacy records without a currency code are treated as UGX.
export function getRecordCurrency(
  currencyCode?: string | null,
): CurrencyCode {
  return isCurrencyCode(currencyCode) ? currencyCode : "UGX";
}

export function formatCurrency(
  amount: number,
  currencyCode: CurrencyCode = "UGX",
): string {
  const currency = CURRENCY_OPTIONS.find(
    (option) => option.code === currencyCode,
  );

  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: currencyCode,
    minimumFractionDigits: currency?.decimalPlaces ?? 0,
    maximumFractionDigits: currency?.decimalPlaces ?? 0,
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
  const decimalPlaces =
    CURRENCY_OPTIONS.find((option) => option.code === currencyCode)
      ?.decimalPlaces ?? 0;

  const cleaned = value.replace(/,/g, "").replace(/[^\d.]/g, "");
  const parts = cleaned.split(".");
  const integerPart = parts[0] ?? "";
  const decimalPart = parts[1]?.slice(0, decimalPlaces);

  const groupedInteger = integerPart.replace(
    /\B(?=(\d{3})+(?!\d))/g,
    ",",
  );

  if (decimalPlaces === 0) {
    return groupedInteger;
  }

  return parts.length > 1
    ? `${groupedInteger}.${decimalPart ?? ""}`
    : groupedInteger;
}
