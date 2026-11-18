
import { useMemo, useState, useEffect } from "react";
import MetricCard from "../components/MetricCard";
import {
  convertToSnapshotCurrency,
  DEFAULT_SETTINGS,
  formatCurrency,
  getKnownCostAmount,
  getKnownRecordCurrency,
  getKnownSaleAmount,
  getKnownStockQuantity,
  getSavedExchangeRateSnapshot,
  getShopCurrency,
  isExchangeRateSnapshotExpired,
  refreshExchangeRateSnapshot,
  SETTINGS_STORAGE_KEY,
} from "../utils/currency";

import type {
  CurrencyCode,
  ExchangeRateSnapshot,
} from "../utils/currency";
import { getKnownPaymentMethod } from "../utils/sales";
import {
  ArrowRight,
  ArrowUpRight,
  CalendarDays,
  CircleAlert,
  Clock3,
  Download,
  Plus,
  ReceiptText,
  Smartphone,
  Wallet,
  Boxes as BoxesIcon,
  Wrench as WrenchIcon,
  Package,
  ShoppingCart,
} from "lucide-react";
import type { PageKey } from "../components/Sidebar";
interface OverviewProps {
  onNavigate: (page: PageKey) => void;
}

type InventoryRecord = {
  id: string;
  brand: string;
  model: string;
  identifier: string;
  status: "In shop" | "With middle-man" | "At repairer" | "Sold";
  colour?: string;
  storage?: string;
  costPrice?: string;
  sellingPrice?: string;
  currencyCode?: CurrencyCode;
  category?: "Device" | "Accessory / spare part";
  quantity?: number;
  updated: string;
};

type SaleRecord = {
  id: string;
  deviceId: string;
  deviceName: string;
  identifier: string;
  salePrice: number;
  paymentMethod: string;
  transactionDate: string;
  costPrice: number;
  currencyCode?: CurrencyCode;
  costCurrencyCode?: CurrencyCode;
};

const INVENTORY_KEY = "stockpilot-inventory";
const SALES_KEY = "stockpilot-sales";

type StoredArrayReadState<T> = {
  records: T[];
  hasValidSnapshot: boolean;
  readError: boolean;
};

function readStoredArray<T>(key: string): T[] | null {
  try {
    const saved = localStorage.getItem(key);
    if (saved === null) return [];

    const parsed: unknown = JSON.parse(saved);
    return Array.isArray(parsed) ? parsed as T[] : null;
  } catch {
    return null;
  }
}

function toStoredArrayReadState<T>(records: T[] | null): StoredArrayReadState<T> {
  return {
    records: records ?? [],
    hasValidSnapshot: records !== null,
    readError: records === null,
  };
}

function readInventory(): InventoryRecord[] | null {
  return readStoredArray<InventoryRecord>(INVENTORY_KEY);
}

function readSales(): SaleRecord[] | null {
  return readStoredArray<SaleRecord>(SALES_KEY);
}

function formatMoney(
  amount: number,
  currencyCode: CurrencyCode | null
): string {
  return formatCurrency(amount, currencyCode);
}

type SalesTotal = {
  amount: number;
  excludedCount: number;
  invalidAmountCount: number;
  unknownCurrencyCount: number;
  unavailableExchangeRateCount: number;
  totalCalculationFailureCount: number;
};

function describeSalesExclusions(total: SalesTotal): string {
  return `${total.excludedCount} record(s) excluded: ${total.invalidAmountCount} invalid amount(s), ${total.unknownCurrencyCount} with unavailable currency, ${total.unavailableExchangeRateCount} without an available exchange rate, and ${total.totalCalculationFailureCount} total calculation failure(s).`;
}

function getSalesTotal(
  records: SaleRecord[],
  snapshot: ExchangeRateSnapshot | null,
  targetCurrency: CurrencyCode
): SalesTotal {
  return records.reduce<SalesTotal>(
    (total, sale) => {
      const amount = getKnownSaleAmount(sale.salePrice);
      const sourceCurrency = getKnownRecordCurrency(sale.currencyCode);

      if (amount === null) {
        total.invalidAmountCount += 1;
      }
      if (!sourceCurrency) {
        total.unknownCurrencyCount += 1;
      }
      if (amount === null || !sourceCurrency) {
        total.excludedCount += 1;
        return total;
      }

      if (amount === 0) {
        return total;
      }

      const converted = convertOverviewAmount(
        amount,
        sourceCurrency,
        snapshot,
        targetCurrency
      );

      if (converted === null) {
        total.excludedCount += 1;
        total.unavailableExchangeRateCount += 1;
      } else {
        const updatedAmount = total.amount + converted;
        if (Number.isFinite(updatedAmount)) {
          total.amount = updatedAmount;
        } else {
          total.excludedCount += 1;
          total.totalCalculationFailureCount += 1;
        }
      }

      return total;
    },
    {
      amount: 0,
      excludedCount: 0,
      invalidAmountCount: 0,
      unknownCurrencyCount: 0,
      unavailableExchangeRateCount: 0,
      totalCalculationFailureCount: 0,
    }
  );
}

function formatSaleAmount(sale: SaleRecord): string {
  const amount = getKnownSaleAmount(sale.salePrice);
  return amount === null
    ? "Amount unavailable"
    : formatMoney(amount, getKnownRecordCurrency(sale.currencyCode));
}

function formatInventoryPrice(item: InventoryRecord): string {
  const amount = getKnownCostAmount(item.sellingPrice);
  return amount === null
    ? "Price unavailable"
    : formatMoney(amount, getKnownRecordCurrency(item.currencyCode));
}

function convertOverviewAmount(
  amount: number,
  sourceCurrency: CurrencyCode,
  snapshot: ExchangeRateSnapshot | null,
  targetCurrency: CurrencyCode
): number | null {
  if (sourceCurrency === targetCurrency) {
    return amount;
  }

  if (!snapshot) {
    return null;
  }

  if (snapshot.baseCode !== targetCurrency) {
    return null;
  }

  return convertToSnapshotCurrency(
    amount,
    sourceCurrency,
    snapshot
  );
}

function localDateKey(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function formatCompact(amount: number): string {
  if (amount >= 1_000_000) {
    return `${(amount / 1_000_000).toFixed(1)}M`;
  }

  if (amount >= 1_000) {
    return `${(amount / 1_000).toFixed(0)}K`;
  }

  return String(Math.round(amount));
}

function getStatusClass(status: InventoryRecord["status"]): string {
  if (status === "In shop") return "available";
  if (status === "With middle-man") return "custody";
  if (status === "At repairer") return "repair";
  return "sold";
}

export default function Overview({ onNavigate }: OverviewProps) {
  const [inventoryReadState, setInventoryReadState] = useState(() =>
    toStoredArrayReadState(readInventory())
  );
  const [salesReadState, setSalesReadState] = useState(() =>
    toStoredArrayReadState(readSales())
  );
  const inventory = inventoryReadState.records;
  const sales = salesReadState.records;
  const [now, setNow] = useState(new Date());

  const [currencySettings, setCurrencySettings] = useState(() => {
    const configuredCurrency = getShopCurrency();
    return {
      shopCurrency: configuredCurrency ?? DEFAULT_SETTINGS.currencyCode,
      invalid: configuredCurrency === null,
    };
  });
  const shopCurrency = currencySettings.shopCurrency;

  const [rateSnapshot, setRateSnapshot] =
    useState<ExchangeRateSnapshot | null>(() =>
      getSavedExchangeRateSnapshot(shopCurrency)
    );
  const [rateNotice, setRateNotice] = useState("");

  useEffect(() => {
    const refreshData = (event?: StorageEvent) => {
      if (
        event &&
        event.key !== INVENTORY_KEY &&
        event.key !== SALES_KEY &&
        event.key !== SETTINGS_STORAGE_KEY &&
        event.key !== null
      ) {
        return;
      }

      const latestInventory = readInventory();
      setInventoryReadState((current) =>
        latestInventory === null
          ? { ...current, readError: true }
          : {
              records: latestInventory,
              hasValidSnapshot: true,
              readError: false,
            }
      );

      const latestSales = readSales();
      setSalesReadState((current) =>
        latestSales === null
          ? { ...current, readError: true }
          : {
              records: latestSales,
              hasValidSnapshot: true,
              readError: false,
            }
      );
      setNow(new Date());

      if (
        !event ||
        event.key === SETTINGS_STORAGE_KEY ||
        event.key === null
      ) {
        const configuredCurrency = getShopCurrency();
        setCurrencySettings((current) =>
          current.shopCurrency ===
            (configuredCurrency ?? DEFAULT_SETTINGS.currencyCode) &&
          current.invalid === (configuredCurrency === null)
            ? current
            : {
                shopCurrency:
                  configuredCurrency ?? DEFAULT_SETTINGS.currencyCode,
                invalid: configuredCurrency === null,
              }
        );
      }
    };
    const refreshOnFocus = () => refreshData();

    window.addEventListener("focus", refreshOnFocus);
    window.addEventListener("storage", refreshData);

    return () => {
      window.removeEventListener("focus", refreshOnFocus);
      window.removeEventListener("storage", refreshData);
    };
  }, []);

  useEffect(() => {
    let active = true;

    if (currencySettings.invalid) {
      setRateSnapshot(null);
      setRateNotice(
        "Shop currency settings are unavailable. Financial totals that require a shop-currency basis cannot be calculated."
      );
      return () => {
        active = false;
      };
    }

    const savedSnapshot =
      getSavedExchangeRateSnapshot(shopCurrency);

    if (savedSnapshot) {
      setRateSnapshot(savedSnapshot);
    }

    refreshExchangeRateSnapshot(shopCurrency)
      .then((snapshot) => {
        if (active) {
          setRateSnapshot(snapshot);
          setRateNotice("");
        }
      })
      .catch((error: unknown) => {
        console.error("Could not refresh Overview exchange rates:", error);
        if (active) {
          const fallbackSnapshot =
            getSavedExchangeRateSnapshot(shopCurrency);
          setRateSnapshot(fallbackSnapshot);
          setRateNotice(
            fallbackSnapshot
              ? `Live exchange rates could not be refreshed. Using the saved snapshot last updated ${new Date(
                  fallbackSnapshot.lastUpdatedAt
                ).toLocaleString()}${
                  isExchangeRateSnapshotExpired(fallbackSnapshot)
                    ? " (expired)."
                    : "."
                }`
              : "Exchange rates are unavailable. Records in other currencies are excluded from converted totals."
          );
        }
      });

    return () => {
      active = false;
    };
  }, [shopCurrency, currencySettings.invalid]);

  const todayKey = localDateKey(now);

   const stock = useMemo(() => {
    const active = inventory.filter((item) => item.status !== "Sold");

    const units = (item: InventoryRecord) =>
      item.category === "Accessory / spare part"
        ? getKnownStockQuantity(item.quantity)
        : 1;

    let stockValue = 0;
    let unknownCostValuation = 0;
    let unknownCurrencyValuation = 0;
    let unknownQuantityValuation = 0;
    let unconvertedValuation = 0;
    let unavailableRateValuation = 0;
    let invalidValuationTotals = 0;
    let stockValueInvalidated = false;

    active.forEach((item) => {
      const cost = getKnownCostAmount(item.costPrice);
      const sourceCurrency = getKnownRecordCurrency(item.currencyCode);
      const quantity = units(item);

      if (cost === null) {
        unknownCostValuation += 1;
      }
      if (!sourceCurrency) {
        unknownCurrencyValuation += 1;
      }
      if (quantity === null) {
        unknownQuantityValuation += 1;
      }
      if (cost === null || !sourceCurrency || quantity === null) {
        unconvertedValuation += 1;
        return;
      }

      const inventoryCost = cost * quantity;
      if (!Number.isFinite(inventoryCost)) {
        unconvertedValuation += 1;
        return;
      }

      const converted = convertOverviewAmount(
        inventoryCost,
        sourceCurrency,
        rateSnapshot,
        shopCurrency
      );

      if (converted === null) {
        unconvertedValuation += 1;
        unavailableRateValuation += 1;
      } else if (!stockValueInvalidated) {
        const updatedValue = stockValue + converted;
        if (Number.isFinite(updatedValue)) {
          stockValue = updatedValue;
        } else {
          stockValue = Number.NaN;
          unconvertedValuation += 1;
          invalidValuationTotals += 1;
          stockValueInvalidated = true;
        }
      }
    });

    return {
      totalUnits: active.reduce(
        (total, item) => total + (units(item) ?? 0),
        0
      ),

      totalDevices: active.filter(
        (item) => item.category !== "Accessory / spare part"
      ).length,

      accessoryUnits: active
        .filter((item) => item.category === "Accessory / spare part")
        .reduce((total, item) => total + (units(item) ?? 0), 0),

      inShop: active
        .filter((item) => item.status === "In shop")
        .reduce((total, item) => total + (units(item) ?? 0), 0),

      withMiddleman: active
        .filter((item) => item.status === "With middle-man")
        .reduce((total, item) => total + (units(item) ?? 0), 0),

      atRepairer: active
        .filter((item) => item.status === "At repairer")
        .reduce((total, item) => total + (units(item) ?? 0), 0),

      stockValue,
      unknownCostValuation,
      unknownCurrencyValuation,
      unknownQuantityValuation,
      unconvertedValuation,
      unavailableRateValuation,
      invalidValuationTotals,
    };
  }, [inventory, rateSnapshot, shopCurrency]);

    const todaySales = useMemo(
    () =>
      sales.filter((sale) => {
        const date = new Date(sale.transactionDate);

        return (
          !Number.isNaN(date.getTime()) &&
          localDateKey(date) === todayKey
        );
      }),
    [sales, todayKey]
  );

  const todayRevenue = useMemo(
    () => getSalesTotal(todaySales, rateSnapshot, shopCurrency),
    [todaySales, rateSnapshot, shopCurrency]
  );
  const invalidDateSalesCount = sales.filter((sale) =>
    Number.isNaN(new Date(sale.transactionDate).getTime())
  ).length;

  const cashReceived = useMemo(
    () => getSalesTotal(
      todaySales.filter((sale) => sale.paymentMethod === "Cash"),
      rateSnapshot,
      shopCurrency
    ),
    [todaySales, rateSnapshot, shopCurrency]
  );
  const unknownPaymentMethodCountToday = todaySales.filter(
    (sale) => getKnownPaymentMethod(sale.paymentMethod) === null
  ).length;

  const followUpCount = stock.withMiddleman + stock.atRepairer;

  const lastSevenDays = useMemo(() => {
    return Array.from({ length: 7 }, (_, index) => {
      const date = new Date(now);
      date.setDate(now.getDate() - (6 - index));

      const key = localDateKey(date);

      const daySales = sales.filter((sale) => {
          const saleDate = new Date(sale.transactionDate);

          return (
            !Number.isNaN(saleDate.getTime()) &&
            localDateKey(saleDate) === key
          );
        });

      const dailyTotal = getSalesTotal(daySales, rateSnapshot, shopCurrency);

      return {
        label: date.toLocaleDateString("en-UG", {
          weekday: "short",
        }),
        total: dailyTotal.amount,
        excludedCount: dailyTotal.excludedCount,
        invalidAmountCount: dailyTotal.invalidAmountCount,
        unknownCurrencyCount: dailyTotal.unknownCurrencyCount,
        unavailableExchangeRateCount:
          dailyTotal.unavailableExchangeRateCount,
        totalCalculationFailureCount:
          dailyTotal.totalCalculationFailureCount,
      };
    });
  }, [sales, now, rateSnapshot, shopCurrency]);

  const hasInventorySnapshot = inventoryReadState.hasValidSnapshot;
  const hasSalesSnapshot = salesReadState.hasValidSnapshot;
  const localDataConnected =
    hasInventorySnapshot &&
    hasSalesSnapshot &&
    !inventoryReadState.readError &&
    !salesReadState.readError;

  const weeklySalesTotal = lastSevenDays.reduce<SalesTotal>(
    (total, day) => {
      const amount = total.amount + day.total;
      const validAmount = Number.isFinite(amount);
      return {
        amount: validAmount ? amount : Number.NaN,
        excludedCount: total.excludedCount + day.excludedCount +
          (validAmount ? 0 : 1),
        invalidAmountCount:
          total.invalidAmountCount + day.invalidAmountCount,
        unknownCurrencyCount:
          total.unknownCurrencyCount + day.unknownCurrencyCount,
        unavailableExchangeRateCount:
          total.unavailableExchangeRateCount +
          day.unavailableExchangeRateCount,
        totalCalculationFailureCount:
          total.totalCalculationFailureCount +
          day.totalCalculationFailureCount +
          (validAmount ? 0 : 1),
      };
    },
    {
      amount: 0,
      excludedCount: 0,
      invalidAmountCount: 0,
      unknownCurrencyCount: 0,
      unavailableExchangeRateCount: 0,
      totalCalculationFailureCount: 0,
    }
  );
  const weeklyRevenue = weeklySalesTotal.amount;
  const weeklyExcludedCount = weeklySalesTotal.excludedCount;

  const previousSevenDaysRevenue = useMemo(() => {
    const start = new Date(now);
    start.setDate(now.getDate() - 13);
    start.setHours(0, 0, 0, 0);

    const end = new Date(now);
    end.setDate(now.getDate() - 7);
    end.setHours(0, 0, 0, 0);

    const previousSales = sales.filter((sale) => {
        const date = new Date(sale.transactionDate);

        return (
          !Number.isNaN(date.getTime()) &&
          date >= start &&
          date < new Date(end.getTime() + 86400000)
        );
      });
    return getSalesTotal(previousSales, rateSnapshot, shopCurrency);
  }, [sales, now, rateSnapshot, shopCurrency]);

  const weeklyChange =
    previousSevenDaysRevenue.amount > 0 &&
    weeklyExcludedCount === 0 &&
    previousSevenDaysRevenue.excludedCount === 0 &&
    invalidDateSalesCount === 0 &&
    !currencySettings.invalid
      ? ((weeklyRevenue - previousSevenDaysRevenue.amount) /
          previousSevenDaysRevenue.amount) * 100
      : null;
  const hasIncompleteFinancialTotals =
    todayRevenue.excludedCount > 0 ||
    cashReceived.excludedCount > 0 ||
    unknownPaymentMethodCountToday > 0 ||
    weeklyExcludedCount > 0 ||
    previousSevenDaysRevenue.excludedCount > 0 ||
    weeklySalesTotal.totalCalculationFailureCount > 0 ||
    invalidDateSalesCount > 0 ||
    currencySettings.invalid ||
    stock.unknownCostValuation > 0 ||
    stock.unknownCurrencyValuation > 0 ||
    stock.unknownQuantityValuation > 0 ||
    stock.unconvertedValuation > 0;

  const maxChartValue = Math.max(
    ...lastSevenDays.map((day) =>
      Number.isFinite(day.total) ? day.total : 0
    ),
    1
    );
  const inShopPercent =
    stock.totalUnits > 0 ? (stock.inShop / stock.totalUnits) * 100 : 0;
  const withMiddlemanPercent =
    stock.totalUnits > 0
      ? (stock.withMiddleman / stock.totalUnits) * 100
      : 0;
  const repairPercent =
    stock.totalUnits > 0
      ? (stock.atRepairer / stock.totalUnits) * 100
      : 0;
  const stockRingBackground =
    stock.totalUnits > 0
      ? `conic-gradient(#7886ff 0 ${inShopPercent}%, #a58bfa ${inShopPercent}% ${
          inShopPercent + withMiddlemanPercent
        }%, #f4bd67 ${
          inShopPercent + withMiddlemanPercent
        }% ${inShopPercent + withMiddlemanPercent + repairPercent}%)`
      : "conic-gradient(var(--surface-raised) 0 100%)";
  const recentSales = sales.slice(0, 5);

  const recentInventory = [...inventory]
    .filter((item) => item.status !== "Sold")
    .slice(-5)
    .reverse();

  const greeting =
    now.getHours() < 12
      ? "Good morning"
      : now.getHours() < 17
        ? "Good afternoon"
        : "Good evening";

  return (
    <div className="page-content">
      <section className="welcome-row">
        <div>
          <div className="eyebrow">
            <span className="eyebrow-line" />
            {now.toLocaleDateString("en-UG", {
              weekday: "long",
              day: "numeric",
              month: "long",
              year: "numeric",
            }).toUpperCase()}
          </div>
          <h1>{greeting}, <span>Val.</span></h1>
          <p className="page-subtitle">
            Here's what's happening across your shop today.
          </p>
        </div>

        <div className="welcome-actions">
          <button
            className="button button-secondary"
            onClick={() => onNavigate("Reports")}
          >
            <Download size={16} /> Reports
          </button>
          <button
            className="button button-primary"
            onClick={() => onNavigate("Inventory")}
          >
            <Plus size={17} /> Add stock
          </button>
        </div>
      </section>

      {currencySettings.invalid && (
        <div className="inventory-notice notice-warning" role="status">
          Shop currency settings are invalid or unavailable. Overview totals use
          {" "}{shopCurrency} as the default conversion basis, which may not match
          the shop's intended currency.
        </div>
      )}

      {rateNotice && (
        <div className="inventory-notice notice-warning" role="status">
          {rateNotice}
        </div>
      )}

      {(inventoryReadState.readError || salesReadState.readError) && (
        <div className="inventory-notice notice-warning" role="alert">
          <strong>Some browser data could not be read.</strong>{" "}
          {inventoryReadState.readError && (
            <span>
              {hasInventorySnapshot
                ? "The latest inventory read failed; showing the last successfully loaded inventory, so its figures may be out of date. "
                : "Inventory data is unavailable. "}
            </span>
          )}
          {salesReadState.readError && (
            <span>
              {hasSalesSnapshot
                ? "The latest sales read failed; showing the last successfully loaded sales, so its figures may be out of date."
                : "Sales data is unavailable."}
            </span>
          )}
        </div>
      )}

      {hasIncompleteFinancialTotals && (
        <div className="inventory-notice notice-warning" role="status">
          <strong>Some financial totals are incomplete.</strong>{" "}
          {hasSalesSnapshot && todayRevenue.excludedCount > 0 && (
            <span>
              Today&apos;s sales: {describeSalesExclusions(todayRevenue)}{" "}
            </span>
          )}
          {hasSalesSnapshot && cashReceived.excludedCount > 0 && (
            <span>
              Cash received: {describeSalesExclusions(cashReceived)}{" "}
            </span>
          )}
          {hasSalesSnapshot && unknownPaymentMethodCountToday > 0 && (
            <span>
              Cash received excludes {unknownPaymentMethodCountToday} sale(s)
              whose payment method is unavailable; they cannot safely be
              assigned to physical cash.{" "}
            </span>
          )}
          {hasSalesSnapshot && weeklyExcludedCount > 0 && (
            <span>
              Seven-day sales: {describeSalesExclusions(weeklySalesTotal)}{" "}
            </span>
          )}
          {hasSalesSnapshot && previousSevenDaysRevenue.excludedCount > 0 && (
            <span>
              Previous-week comparison:{" "}
              {describeSalesExclusions(previousSevenDaysRevenue)}{" "}
            </span>
          )}
          {hasSalesSnapshot && invalidDateSalesCount > 0 && (
            <span>
              {invalidDateSalesCount} sale(s) have invalid dates and cannot be
              assigned to a reporting period; weekly comparisons are
              suppressed.{" "}
            </span>
          )}
          {hasSalesSnapshot &&
            (todayRevenue.excludedCount > 0 ||
              cashReceived.excludedCount > 0 ||
              weeklyExcludedCount > 0 ||
              previousSevenDaysRevenue.excludedCount > 0) && (
            <span>
              Issue counts may overlap when one sale has multiple data problems.
            </span>
          )}
          {hasInventorySnapshot && stock.unknownCostValuation > 0 && (
            <span>
              Inventory-at-cost excludes {stock.unknownCostValuation} record(s)
              with unknown or invalid costs.{" "}
            </span>
          )}
          {hasInventorySnapshot && stock.unknownCurrencyValuation > 0 && (
            <span>
              Inventory-at-cost excludes {stock.unknownCurrencyValuation}{" "}
              record(s) with unavailable currency.{" "}
            </span>
          )}
          {hasInventorySnapshot && stock.unknownQuantityValuation > 0 && (
            <span>
              Inventory counts and valuation exclude{" "}
              {stock.unknownQuantityValuation} accessory record(s) with an
              invalid quantity.{" "}
            </span>
          )}
          {hasInventorySnapshot && stock.unconvertedValuation > 0 && (
            <span>
              Inventory-at-cost excludes {stock.unavailableRateValuation}{" "}
              record(s) because an exchange rate is unavailable.
            </span>
          )}
          {hasInventorySnapshot && stock.invalidValuationTotals > 0 && (
            <span>
              Inventory-at-cost includes {stock.invalidValuationTotals} total
              calculation failure(s) due to numeric overflow.
            </span>
          )}
        </div>
      )}

      <section className="status-strip" aria-label="System status">
        <div className="status-left">
          {localDataConnected ? <span className="status-pulse" /> : <CircleAlert size={14} />}
          <span className="status-title">
            {localDataConnected ? "Local data connected" : "Local data unavailable"}
          </span>
          <span className="status-divider" />
          <span className="status-detail">
            {localDataConnected ? "Browser storage" : "See data warning"}
          </span>
        </div>
        <div className="status-right">
          <Clock3 size={14} />
          {localDataConnected ? "Updated just now" : "Latest read unavailable"}
        </div>
      </section>

            <section className="metrics-grid" aria-label="Shop metrics">
        <MetricCard
          label="Inventory at cost"
          value={
            hasInventorySnapshot && !currencySettings.invalid
              ? formatMoney(stock.stockValue, shopCurrency)
              : "Unavailable"
          }
          note={
            !hasInventorySnapshot
              ? "Inventory data is unavailable."
              : currencySettings.invalid
                ? "Shop currency is unavailable; valuation cannot be converted safely."
              : stock.unknownCostValuation > 0 ||
                  stock.unknownCurrencyValuation > 0 ||
                  stock.unconvertedValuation > 0
              ? "Some records excluded; see the warning above."
              : "Unsold stock at recorded cost"
          }
          icon={BoxesIcon}
          tone="blue"
        />

        <MetricCard
          label="Sales today"
          value={hasSalesSnapshot && !currencySettings.invalid ? formatMoney(todayRevenue.amount, shopCurrency) : "Unavailable"}
          note={hasSalesSnapshot ? `${todaySales.length} recorded transactions` : "Sales data is unavailable."}
          icon={ReceiptText}
          tone="violet"
        />

        <MetricCard
          label="Cash received today"
          value={hasSalesSnapshot && !currencySettings.invalid ? formatMoney(cashReceived.amount, shopCurrency) : "Unavailable"}
          note={
            !hasSalesSnapshot
              ? "Sales data is unavailable."
              : unknownPaymentMethodCountToday > 0
                ? `${unknownPaymentMethodCountToday} sale(s) with unknown payment method excluded.`
                : "Cash payments only"
          }
          icon={Wallet}
          tone="cyan"
        />

        <MetricCard
          label="Needs follow-up"
          value={hasInventorySnapshot ? `${followUpCount} items` : "Unavailable"}
          note={
            hasInventorySnapshot
              ? `${stock.withMiddleman} with middle-men · ${stock.atRepairer} at repairers`
              : "Inventory data is unavailable."
          }
          icon={CircleAlert}
          tone="amber"
        />
      </section>

      <section className="main-grid">
        <article className="surface-card sales-card">
          <div className="card-heading">
            <div>
              <div className="card-kicker">PERFORMANCE</div>
              <h2>Sales overview</h2>
            </div>
            <div className="select-button">
              <CalendarDays size={15} /> Last 7 days
            </div>
          </div>

          <div className="sales-summary">
            <div>
              <div className="sales-total">
                {hasSalesSnapshot && !currencySettings.invalid
                  ? formatMoney(weeklyRevenue, shopCurrency)
                  : "Unavailable"}
              </div>
              <div className="sales-comparison">
                {!hasSalesSnapshot ? (
                  <span>Sales data is unavailable; comparison cannot be calculated.</span>
                ) : currencySettings.invalid ||
                  weeklyExcludedCount > 0 ||
                  previousSevenDaysRevenue.excludedCount > 0 ||
                  invalidDateSalesCount > 0 ||
                  weeklySalesTotal.totalCalculationFailureCount > 0 ? (
                  <span>
                    Comparison unavailable: one or more periods have excluded
                    or undated sales, invalid amounts, unavailable currencies
                    or rates, or totals outside the supported numeric range.
                  </span>
                ) : weeklyChange === null ? (
                  <span>No previous-week comparison yet</span>
                ) : (
                  <>
                    <span className={weeklyChange >= 0 ? "positive" : ""}>
                      <ArrowUpRight size={14} />
                      {Math.abs(weeklyChange).toFixed(1)}%
                    </span>
                    <span>vs previous 7 days</span>
                  </>
                )}
              </div>
            </div>
            <div className="sales-legend">
              <span className="legend-dot legend-current" /> This week
            </div>
          </div>

          {hasSalesSnapshot && !currencySettings.invalid ? (
          <div className="chart-area" role="img" aria-label="Actual sales for the last seven days">
            <div className="chart-y-labels">
              <span>{formatCompact(maxChartValue)}</span>
              <span>{formatCompact(maxChartValue * 0.75)}</span>
              <span>{formatCompact(maxChartValue * 0.5)}</span>
              <span>{formatCompact(maxChartValue * 0.25)}</span>
              <span>0</span>
            </div>

            <div className="chart-plot">
              <div className="chart-grid-lines">
                <i /><i /><i /><i /><i />
              </div>

              <div
                style={{
                  position: "absolute",
                  inset: "8px 0 25px",
                  display: "flex",
                  alignItems: "flex-end",
                  justifyContent: "space-around",
                  gap: "10px",
                  padding: "0 8px",
                }}
              >
                {lastSevenDays.map((day) => (
                  <div
                    key={day.label}
                    title={`${day.label}: ${formatMoney(day.total, shopCurrency)}`}
                    style={{
                      flex: 1,
                      maxWidth: "48px",
                      height: `${Math.max((day.total / maxChartValue) * 100, 2)}%`,
                      minHeight: "2px",
                      borderRadius: "5px 5px 0 0",
                      background: "linear-gradient(180deg, #8b91ff, #5968d9)",
                    }}
                  />
                ))}
              </div>

              <div className="chart-x-labels">
                {lastSevenDays.map((day, index) => (
                  <span key={`${day.label}-${index}`}>{day.label}</span>
                ))}
              </div>
            </div>
          </div>
          ) : (
            <div className="chart-area" role="status">
              <div className="inventory-empty">
                <ReceiptText size={24} />
                <strong>Sales chart unavailable</strong>
                <span>
                  {hasSalesSnapshot
                    ? "Shop currency settings are invalid or unavailable."
                    : "Browser sales data could not be read."}
                </span>
              </div>
            </div>
          )}

          <div className="chart-footer">
            <span>
              <span className="footer-dot" /> Based on recorded transactions
            </span>
            <button
              className="text-button"
              onClick={() => onNavigate("Reports")}
            >
              View reports <ArrowRight size={15} />
            </button>
          </div>
        </article>

        <article className="surface-card stock-card">
          <div className="card-heading">
            <div>
              <div className="card-kicker">INVENTORY HEALTH</div>
              <h2>Stock at a glance</h2>
            </div>
            <button
              className="icon-button"
              aria-label="Open inventory"
              onClick={() => onNavigate("Inventory")}
            >
              <ArrowUpRight size={17} />
            </button>
          </div>

          <div className="stock-hero">
            <div
              className="stock-ring"
              style={{ background: stockRingBackground }}
              aria-label={`Stock distribution: ${stock.inShop} in shop, ${stock.withMiddleman} with middle-men, ${stock.atRepairer} at repairers`}
            >
              <div>
                <strong>{hasInventorySnapshot ? stock.totalUnits : "Unavailable"}</strong>
                <span>{hasInventorySnapshot ? "stock units" : "inventory data"}</span>
              </div>
            </div>

            <div className="stock-legend">
              <div>
                <span className="stock-key key-blue" />
                <span>In shop</span>
                <strong>{hasInventorySnapshot ? stock.inShop : "Unavailable"}</strong>
              </div>
              <div>
                <span className="stock-key key-violet" />
                <span>With middle-men</span>
                <strong>{hasInventorySnapshot ? stock.withMiddleman : "Unavailable"}</strong>
              </div>
              <div>
                <span className="stock-key key-amber" />
                <span>At repairers</span>
                <strong>{hasInventorySnapshot ? stock.atRepairer : "Unavailable"}</strong>
              </div>
            </div>
          </div>

          <div className="stock-note">
            <div className="stock-note-icon">
              <Smartphone size={16} />
            </div>
            <div>
              <strong>
                {hasInventorySnapshot
                  ? `${stock.totalDevices} devices · ${stock.accessoryUnits} accessory units`
                  : "Inventory data unavailable"}
              </strong>
              <span>
                {hasInventorySnapshot
                  ? "Sold stock is excluded from current stock totals."
                  : "Browser inventory data could not be read."}
              </span>
            </div>
          </div>

          <button
            className="button button-secondary button-full"
            onClick={() => onNavigate("Inventory")}
          >
            Open inventory <ArrowRight size={16} />
          </button>
        </article>
      </section>

      <section className="bottom-grid">
                <article className="surface-card activity-card">
          <div className="card-heading">
            <div>
              <div className="card-kicker">TRANSACTION FEED</div>
              <h2>Recent sales</h2>
            </div>
            <button
              className="text-button"
              onClick={() => onNavigate("Sales")}
            >
              View all <ArrowRight size={15} />
            </button>
          </div>

          {!hasSalesSnapshot ? (
            <div className="inventory-empty">
              <ReceiptText size={24} />
              <strong>Sales records unavailable</strong>
              <span>Browser sales data could not be read.</span>
            </div>
          ) : recentSales.length === 0 ? (
            <div className="inventory-empty">
              <ReceiptText size={24} />
              <strong>
                {salesReadState.readError
                  ? "No sales in the last successful read"
                  : "No sales recorded yet"}
              </strong>
              <span>
                {salesReadState.readError
                  ? "The current sales data could not be verified."
                  : "Completed sales will appear here."}
              </span>
            </div>
          ) : (
            <div className="operations-record-list">
              {recentSales.map((sale) => (
                <article className="operations-record" key={sale.id}>
                  <div className="operations-record-icon">
                    <ShoppingCart size={17} />
                  </div>

                  <div className="operations-record-copy">
                    <strong>{sale.deviceName}</strong>
                    <span>{sale.identifier}</span>
                    <span>
                      {new Date(sale.transactionDate).toLocaleString()}
                    </span>
                  </div>

                  <strong className="operations-amount">
                    {formatSaleAmount(sale)}
                  </strong>
                </article>
              ))}
            </div>
          )}
        </article>

        <article className="surface-card attention-card">
          <div className="card-heading">
            <div>
              <div className="card-kicker">ACTION REQUIRED</div>
              <h2>Needs your attention</h2>
            </div>
            <span className="attention-count">
              {hasInventorySnapshot ? followUpCount : "Unavailable"}
            </span>
          </div>

          {!hasInventorySnapshot ? (
            <div className="inventory-empty">
              <CircleAlert size={22} />
              <strong>Follow-up data unavailable</strong>
              <span>Browser inventory data could not be read.</span>
            </div>
          ) : (
            <>
          {stock.withMiddleman > 0 && (
            <button
              className="attention-item"
              onClick={() => onNavigate("Custody")}
            >
              <span className="attention-symbol symbol-violet">
                <ArrowUpRight size={17} />
              </span>
              <span className="attention-copy">
                <strong>Middle-man follow-up</strong>
                <small>{stock.withMiddleman} stock units away</small>
              </span>
              <ArrowRight size={16} className="attention-arrow" />
            </button>
          )}

          {stock.atRepairer > 0 && (
            <button
              className="attention-item"
              onClick={() => onNavigate("Repairs")}
            >
              <span className="attention-symbol symbol-amber">
                <WrenchIcon size={17} />
              </span>
              <span className="attention-copy">
                <strong>Repair tracking</strong>
                <small>{stock.atRepairer} stock units at repairers</small>
              </span>
              <ArrowRight size={16} className="attention-arrow" />
            </button>
          )}

          {followUpCount === 0 && (
            <div className="inventory-empty">
              <CircleAlert size={22} />
              <strong>
                {inventoryReadState.readError
                  ? "No follow-ups in the last successful read"
                  : "No stock follow-ups"}
              </strong>
              <span>
                {inventoryReadState.readError
                  ? "Current inventory data could not be verified."
                  : "No devices are currently marked away."}
              </span>
            </div>
          )}
            </>
          )}

          <div className="stock-note">
            <div className="stock-note-icon">
              <Wallet size={16} />
            </div>
            <div>
              <strong>Cash closing</strong>
              <span>Reconcile today&apos;s sales and physical cash by currency.</span>
              <button
                className="text-button"
                onClick={() => onNavigate("Daily closing")}
              >
                Open daily closing <ArrowRight size={14} />
              </button>
            </div>
          </div>
        </article>
      </section>

            <section className="devices-section surface-card">
        <div className="card-heading">
          <div>
            <div className="card-kicker">INVENTORY RECORDS</div>
            <h2>Recently added stock</h2>
          </div>
          <button
            className="text-button"
            onClick={() => onNavigate("Inventory")}
          >
            View inventory <ArrowRight size={15} />
          </button>
        </div>

        {!hasInventorySnapshot ? (
          <div className="inventory-empty">
            <Package size={24} />
            <strong>Inventory records unavailable</strong>
            <span>Browser inventory data could not be read.</span>
          </div>
        ) : recentInventory.length === 0 ? (
          <div className="inventory-empty">
            <Package size={24} />
            <strong>
              {inventoryReadState.readError
                ? "No inventory in the last successful read"
                : "No inventory records yet"}
            </strong>
            <span>
              {inventoryReadState.readError
                ? "The current inventory data could not be verified."
                : "Add stock to see your inventory here."}
            </span>
          </div>
        ) : (
          <div className="table-wrap">
            <table className="inventory-table">
              <thead>
                <tr>
                  <th>ITEM</th>
                  <th>IDENTIFIER</th>
                  <th>STATUS</th>
                  <th>SELLING PRICE</th>
                  <th>UPDATED</th>
                  <th />
                </tr>
              </thead>

              <tbody>
                {recentInventory.map((item) => (
                  <tr key={item.id}>
                    <td>
                      <div className="device-cell">
                        <div className="device-thumbnail">
                          {item.category === "Accessory / spare part" ? (
                            <Package size={18} />
                          ) : (
                            <Smartphone size={18} />
                          )}
                        </div>

                        <div>
                          <strong>{item.brand} {item.model}</strong>
                          <span>
                            {item.category === "Accessory / spare part"
                              ? `Accessory · Qty ${
                                  getKnownStockQuantity(item.quantity) ??
                                  "Unavailable"
                                }`
                              : item.storage ?? "Device"}
                          </span>
                        </div>
                      </div>
                    </td>

                    <td className="identifier-cell">{item.identifier}</td>

                    <td>
                      <span className={`status-pill status-${getStatusClass(item.status)}`}>
                        <i />{item.status}
                      </span>
                    </td>

                    <td className="price-cell">
                      {formatInventoryPrice(item)}
                    </td>

                    <td className="updated-cell">{item.updated}</td>

                    <td>
                      <button
                        className="row-more"
                        aria-label={`Open ${item.model}`}
                        onClick={() => onNavigate("Inventory")}
                      >
                        ···
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <div className="table-footnote">
          <span>
            <CircleAlert size={14} />{" "}
            {inventoryReadState.readError
              ? "Showing the last successfully read inventory data."
              : hasInventorySnapshot
                ? "Data shown comes from this browser's inventory records."
                : "Inventory data is unavailable."}
          </span>
          <button
            className="text-button"
            onClick={() => onNavigate("Inventory")}
          >
            Open full inventory <ArrowRight size={15} />
          </button>
        </div>
      </section>

      <div className="prototype-disclaimer">
        StockPilot prototype · Dashboard figures are calculated from locally stored inventory and sales records.
      </div>
    </div>
  );
}
