import DailyClosing from "./DailyClosing";
import Settings from "./Settings";
import Purchases from "./Purchases";
import SupplierCredit from "./SupplierCredit";
import { useEffect, useMemo, useState } from "react";
import {
  ArrowLeftRight,
  Banknote,
  BarChart3,
  Building2,
  CalendarClock,
  CheckCircle2,
  ClipboardCheck,
  FileText,
  Package,
  Plus,
  Receipt,
  ShieldCheck,
  ShoppingCart,
  Smartphone,
  TrendingUp,
  Users,
  Wallet,
  Wrench,
} from "lucide-react";
import type { PageKey } from "../components/Sidebar";
import {
  convertToSnapshotCurrency,
  DEFAULT_SETTINGS,
  EXCHANGE_RATES_STORAGE_KEY,
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
import {
  getKnownPaymentMethod,
  type PaymentMethod,
} from "../utils/sales";

type OperationRecord = {
  id: number;
  primary: string;
  secondary: string;
  status: string;
  amount?: string;
};

type InventoryRecord = {
  id: string;
  brand: string;
  model: string;
  identifier: string;
  status: "In shop" | "With middle-man" | "At repairer" | "Sold";
  category?: "Device" | "Accessory / spare part";
  quantity?: number;
  costPrice?: string;
  currencyCode?: CurrencyCode;
};

type SaleRecord = {
  id: string;
  deviceId: string;
  deviceName: string;
  identifier: string;
  salePrice: number;
  paymentMethod: PaymentMethod;
  transactionDate: string;
  costPrice?: number | null;
  category?: "Device" | "Accessory / spare part";
  quantitySold?: number;
  unitPrice?: number;
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

function readStorage<T>(key: string): T[] | null {
  try {
    const saved = localStorage.getItem(key);
    if (saved === null) return [];

    const parsed: unknown = JSON.parse(saved);
    return Array.isArray(parsed) ? (parsed as T[]) : null;
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

function formatMoney(
  amount: number,
  currencyCode: CurrencyCode | null
) {
  return formatCurrency(amount, currencyCode);
}

function convertReportAmount(
  amount: number,
  sourceCurrency: string | null | undefined,
  targetCurrency: CurrencyCode,
  snapshot: ExchangeRateSnapshot | null
): number | null {
  const safeAmount = Number(amount);

  if (!Number.isFinite(safeAmount)) return null;

  const sourceCode = getKnownRecordCurrency(sourceCurrency);
  if (!sourceCode) return null;

  if (sourceCode === targetCurrency) {
    return safeAmount;
  }

  if (!snapshot || snapshot.baseCode !== targetCurrency) {
    return null;
  }

  return convertToSnapshotCurrency(
    safeAmount,
    sourceCode,
    snapshot
  );
}

function getSaleCategory(sale: SaleRecord) {
  return sale.category === "Accessory / spare part"
    ? "Accessory / spare part"
    : "Device";
}

function getSaleQuantity(sale: SaleRecord) {
  return getSaleCategory(sale) === "Device"
    ? 1
    : getKnownStockQuantity(sale.quantitySold);
}

function getLocalDateKey(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function ReportsView() {
  const [inventoryReadState, setInventoryReadState] = useState(() =>
    toStoredArrayReadState(readStorage<InventoryRecord>(INVENTORY_KEY))
  );
  const inventory = inventoryReadState.records;

  const [salesReadState, setSalesReadState] = useState(() =>
    toStoredArrayReadState(readStorage<SaleRecord>(SALES_KEY))
  );
  const sales = salesReadState.records;

  const [period, setPeriod] = useState<"7" | "30" | "all">("7");

  const [shopCurrency, setShopCurrency] = useState<CurrencyCode>(
    () => getShopCurrency() ?? DEFAULT_SETTINGS.currencyCode
  );
  const [currencySettingsInvalid, setCurrencySettingsInvalid] = useState(
    () => getShopCurrency() === null
  );

  const [rateSnapshot, setRateSnapshot] =
    useState<ExchangeRateSnapshot | null>(() =>
      getSavedExchangeRateSnapshot(
        getShopCurrency() ?? DEFAULT_SETTINGS.currencyCode
      )
    );
  const [rateNotice, setRateNotice] = useState("");

  useEffect(() => {
    const refreshData = (event?: StorageEvent) => {
      if (
        event &&
        event.key !== INVENTORY_KEY &&
        event.key !== SALES_KEY &&
        event.key !== SETTINGS_STORAGE_KEY &&
        event.key !== EXCHANGE_RATES_STORAGE_KEY &&
        event.key !== null
      ) {
        return;
      }

      if (!event || event.key === INVENTORY_KEY || event.key === null) {
        const latestInventory = readStorage<InventoryRecord>(INVENTORY_KEY);
        setInventoryReadState((current) =>
          latestInventory === null
            ? { ...current, readError: true }
            : {
                records: latestInventory,
                hasValidSnapshot: true,
                readError: false,
              }
        );
      }
      if (!event || event.key === SALES_KEY || event.key === null) {
        const latestSales = readStorage<SaleRecord>(SALES_KEY);
        setSalesReadState((current) =>
          latestSales === null
            ? { ...current, readError: true }
            : {
                records: latestSales,
                hasValidSnapshot: true,
                readError: false,
              }
        );
      }
      if (
        !event ||
        event.key === SETTINGS_STORAGE_KEY ||
        event.key === null
      ) {
        const currentShopCurrency = getShopCurrency();
        setCurrencySettingsInvalid(currentShopCurrency === null);
        setShopCurrency(
          currentShopCurrency ?? DEFAULT_SETTINGS.currencyCode
        );
      }
      if (
        !event ||
        event.key === EXCHANGE_RATES_STORAGE_KEY ||
        event.key === SETTINGS_STORAGE_KEY ||
        event.key === null
      ) {
        const currentShopCurrency =
          getShopCurrency() ?? DEFAULT_SETTINGS.currencyCode;
        const latestSnapshot =
          getSavedExchangeRateSnapshot(currentShopCurrency);
        setRateSnapshot((current) =>
          JSON.stringify(current) === JSON.stringify(latestSnapshot)
            ? current
            : latestSnapshot
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
  }, [shopCurrency]);

  const hasInventorySnapshot = inventoryReadState.hasValidSnapshot;
  const hasSalesSnapshot = salesReadState.hasValidSnapshot;

  useEffect(() => {
    let active = true;

    if (currencySettingsInvalid) {
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
        console.error("Could not refresh Operations exchange rates:", error);
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
  }, [shopCurrency, currencySettingsInvalid]);

  const filteredSales = useMemo(() => {
    const now = new Date();

    return sales.filter((sale) => {
      const date = new Date(sale.transactionDate);

      if (Number.isNaN(date.getTime())) return false;

      if (period === "all") return true;

      const days = Number(period);
      const start = new Date(now);
      start.setHours(0, 0, 0, 0);
      start.setDate(start.getDate() - (days - 1));

      return date >= start && date <= now;
    });
  }, [sales, period]);

  
  const report = useMemo(() => {
    let revenue = 0;
    let costOfGoods = 0;
    let unconvertedRevenue = 0;
    let unconvertedCosts = 0;
    let unknownCurrencyRevenue = 0;
    let unknownCurrencyCosts = 0;
    let unknownCostAmounts = 0;
    let invalidSaleAmounts = 0;
    let invalidSaleQuantities = 0;
    let invalidSaleQuantityTotals = 0;
    let saleQuantityTotalInvalidated = false;
    let unknownPaymentMethods = 0;
    let invalidTotalCalculations = 0;
    let revenueTotalInvalidated = false;
    let costTotalInvalidated = false;
    let unavailableRateRevenue = 0;
    let unavailableRateCosts = 0;

    const paymentTotals: Record<string, number> = {};
    const categoryTotals = {
      devices: 0,
      accessories: 0,
    };

    const deviceSales = filteredSales.filter(
      (sale) => getSaleCategory(sale) === "Device"
    );

    const accessorySales = filteredSales.filter(
      (sale) => getSaleCategory(sale) === "Accessory / spare part"
    );

    let accessoryUnits = 0;

    filteredSales.forEach((sale) => {
      const knownSaleAmount = getKnownSaleAmount(sale.salePrice);
      if (knownSaleAmount === null) invalidSaleAmounts += 1;
      const method = getKnownPaymentMethod(sale.paymentMethod);
      if (!method) unknownPaymentMethods += 1;

      const saleCurrency = getKnownRecordCurrency(sale.currencyCode);
      if (!saleCurrency) unknownCurrencyRevenue += 1;

      const saleAmount =
        knownSaleAmount === null
          ? null
          : convertReportAmount(
              knownSaleAmount,
              saleCurrency,
              shopCurrency,
              rateSnapshot
            );

      if (saleAmount === null) {
        unconvertedRevenue += 1;
        if (
          knownSaleAmount !== null &&
          saleCurrency &&
          saleCurrency !== shopCurrency
        ) {
          unavailableRateRevenue += 1;
        }
      } else {
        const nextRevenue = revenue + saleAmount;
        const nextCategory =
          getSaleCategory(sale) === "Device"
              ? categoryTotals.devices + saleAmount
              : categoryTotals.accessories + saleAmount;
        const nextPaymentTotal = method
          ? (paymentTotals[method] || 0) + saleAmount
          : 0;

        if (
          !Number.isFinite(nextRevenue) ||
          !Number.isFinite(nextCategory) ||
          !Number.isFinite(nextPaymentTotal)
        ) {
          revenue = Number.NaN;
          if (getSaleCategory(sale) === "Device") {
              categoryTotals.devices = Number.NaN;
          } else {
              categoryTotals.accessories = Number.NaN;
          }
          if (method) paymentTotals[method] = Number.NaN;
          if (!revenueTotalInvalidated) {
              invalidTotalCalculations += 1;
              revenueTotalInvalidated = true;
          }
        } else {
          revenue = nextRevenue;
          if (getSaleCategory(sale) === "Device") {
              categoryTotals.devices = nextCategory;
          } else {
              categoryTotals.accessories = nextCategory;
          }
          if (method) paymentTotals[method] = nextPaymentTotal;
        }
      }

      const saleCostCurrency = getKnownRecordCurrency(
        sale.costCurrencyCode
      );
      if (!saleCostCurrency) unknownCurrencyCosts += 1;

      const saleCostAmount = getKnownCostAmount(sale.costPrice);
      if (saleCostAmount === null) unknownCostAmounts += 1;

      const costAmount =
        saleCostAmount === null
          ? null
          : convertReportAmount(
              saleCostAmount,
              saleCostCurrency,
              shopCurrency,
              rateSnapshot
            );

      if (costAmount === null) {
        unconvertedCosts += 1;
        if (
          saleCostAmount !== null &&
          saleCostCurrency &&
          saleCostCurrency !== shopCurrency
        ) {
          unavailableRateCosts += 1;
        }
      } else {
        const updatedCostOfGoods = costOfGoods + costAmount;
        if (Number.isFinite(updatedCostOfGoods)) {
          costOfGoods = updatedCostOfGoods;
        } else {
          costOfGoods = Number.NaN;
          if (!costTotalInvalidated) {
            invalidTotalCalculations += 1;
            costTotalInvalidated = true;
          }
        }
      }

      if (getSaleCategory(sale) === "Accessory / spare part") {
        const quantity = getSaleQuantity(sale);
        if (quantity === null) {
          invalidSaleQuantities += 1;
        } else {
          const updatedUnits = accessoryUnits + quantity;
          if (Number.isSafeInteger(updatedUnits)) {
            accessoryUnits = updatedUnits;
          } else {
            accessoryUnits = Number.NaN;
            if (!saleQuantityTotalInvalidated) {
              invalidSaleQuantityTotals += 1;
              saleQuantityTotalInvalidated = true;
            }
          }
        }
      }
    });

    const grossProfit =
      unconvertedRevenue > 0 ||
      unconvertedCosts > 0 ||
      invalidTotalCalculations > 0
        ? null
        : revenue - costOfGoods;

    return {
      revenue,
      costOfGoods,
      grossProfit,
      unconvertedRevenue,
      unconvertedCosts,
      unknownCurrencyRevenue,
      unknownCurrencyCosts,
      unknownCostAmounts,
      invalidSaleAmounts,
      invalidSaleQuantities,
      invalidSaleQuantityTotals,
      unknownPaymentMethods,
      invalidTotalCalculations,
      unavailableRateRevenue,
      unavailableRateCosts,
      categoryTotals,
      transactionCount: filteredSales.length,
      deviceCount: deviceSales.length,
      accessoryCount: accessorySales.length,
      accessoryUnits,
      paymentTotals,
    };
  }, [filteredSales, shopCurrency, rateSnapshot]);


 
  const stock = useMemo(() => {
    const available = inventory.filter(
      (item) => item.status !== "Sold"
    );

    const devices = available.filter(
      (item) => item.category !== "Accessory / spare part"
    );

    const accessories = available.filter(
      (item) => item.category === "Accessory / spare part"
    );

    let unknownQuantityValuation = 0;
    let invalidStockQuantityTotals = 0;
    let stockQuantityTotalInvalidated = false;
    const accessoryUnits = accessories.reduce((total, item) => {
      const quantity = getKnownStockQuantity(item.quantity);
      if (quantity === null) {
        unknownQuantityValuation += 1;
        return total;
      }
      const updated = total + quantity;
      if (Number.isSafeInteger(updated)) return updated;
      if (!stockQuantityTotalInvalidated) {
        invalidStockQuantityTotals += 1;
        stockQuantityTotalInvalidated = true;
      }
      return Number.NaN;
    }, 0);

    let valuation = 0;
    let unconvertedValuation = 0;
    let unknownCurrencyValuation = 0;
    let unknownCostValuation = 0;
    let unavailableRateValuation = 0;
    let invalidValuationTotals = 0;
    let valuationTotalInvalidated = false;

    available.forEach((item) => {
      const quantity =
        item.category === "Accessory / spare part"
          ? getKnownStockQuantity(item.quantity)
          : 1;

      const costAmount = getKnownCostAmount(item.costPrice);
      const sourceCurrency = getKnownRecordCurrency(item.currencyCode);
      if (!sourceCurrency) unknownCurrencyValuation += 1;
      if (costAmount === null) unknownCostValuation += 1;

      if (costAmount === null || !sourceCurrency || quantity === null) {
        unconvertedValuation += 1;
        return;
      }

      const inventoryCost = costAmount * quantity;
      if (!Number.isFinite(inventoryCost)) {
        unconvertedValuation += 1;
        return;
      }

      const convertedCost = convertReportAmount(
        inventoryCost,
        sourceCurrency,
        shopCurrency,
        rateSnapshot
      );

      if (convertedCost === null) {
        unconvertedValuation += 1;
        unavailableRateValuation += 1;
      } else {
        const updated = valuation + convertedCost;
        if (Number.isFinite(updated)) {
          valuation = updated;
        } else {
          valuation = Number.NaN;
          if (!valuationTotalInvalidated) {
            unconvertedValuation += 1;
            invalidValuationTotals += 1;
            valuationTotalInvalidated = true;
          }
        }
      }
    });

    return {
      deviceCount: devices.length,
      accessoryTypes: accessories.length,
      accessoryUnits,
      totalUnits: devices.length + accessoryUnits,
      valuation,
      unconvertedValuation,
      unknownCurrencyValuation,
      unknownCostValuation,
      unknownQuantityValuation,
      unavailableRateValuation,
      invalidValuationTotals,
      invalidStockQuantityTotals,
      withMiddleMan: available.filter(
        (item) => item.status === "With middle-man"
      ).length,
      atRepairer: available.filter(
        (item) => item.status === "At repairer"
      ).length,
    };
  }, [inventory, shopCurrency, rateSnapshot]);


 const dailySales = useMemo(() => {
  const days = period === "30" ? 30 : 7;
  const now = new Date();

  return Array.from({ length: days }, (_, index) => {
    const date = new Date(now);
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() - (days - index - 1));

    const key = getLocalDateKey(date);

    const daySales = filteredSales.filter((sale) => {
      const saleDate = new Date(sale.transactionDate);

      return (
        !Number.isNaN(saleDate.getTime()) &&
        getLocalDateKey(saleDate) === key
      );
    });

    let total = 0;
    let unconvertedCount = 0;

    daySales.forEach((sale) => {
      const amount = getKnownSaleAmount(sale.salePrice);
      const convertedAmount =
        amount === null
          ? null
          : convertReportAmount(
              amount,
              sale.currencyCode,
              shopCurrency,
              rateSnapshot
            );

      if (convertedAmount === null) {
        unconvertedCount += 1;
      } else {
        const updated = total + convertedAmount;
        if (Number.isFinite(updated)) {
          total = updated;
        } else {
          total = Number.NaN;
          unconvertedCount += 1;
        }
      }
    });

    return {
      key,
      label: date.toLocaleDateString("en-UG", {
        day: "numeric",
        month: "short",
      }),
      total,
      unconvertedCount,
    };
  });
}, [filteredSales, period, shopCurrency, rateSnapshot]);

  const highestDailySale = Math.max(
    ...dailySales.map((day) =>
      Number.isFinite(day.total) ? day.total : 0
    ),
    1
  );

  const recentSales = [...filteredSales]
    .sort(
      (a, b) =>
        new Date(b.transactionDate).getTime() -
        new Date(a.transactionDate).getTime()
    )
    .slice(0, 6);

  const periodLabel =
    period === "7"
      ? "Last 7 days"
      : period === "30"
        ? "Last 30 days"
        : "All recorded time";
  const invalidDateSalesCount = sales.filter((sale) =>
    Number.isNaN(new Date(sale.transactionDate).getTime())
  ).length;

  return (
    <section className="operations-page page-content">
      <div className="eyebrow">
        <span className="eyebrow-line" /> INSIGHTS & REPORTING
      </div>

      <div className="operations-heading">
        <div>
          <h1>Business reports</h1>
          <p className="page-subtitle">
            Understand your sales performance, stock position and estimated
            gross profit using your saved records.
          </p>
        </div>
        <div className="operations-heading-icon">
          <BarChart3 size={22} />
        </div>
      </div>

      {(inventoryReadState.readError || salesReadState.readError) && (
        <div className="operations-note" role="alert">
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

      {currencySettingsInvalid && (
        <div className="operations-note" role="status">
          Shop currency settings are invalid or unavailable. Report currency
          totals use {shopCurrency} as the configured default conversion basis;
          this may not match the shop's intended currency.
        </div>
      )}

      {rateNotice && (
        <div className="operations-note" role="status">
          {rateNotice}
        </div>
      )}

      <div className="operations-report-toolbar">
        <div>
          <span className="card-kicker">REPORTING PERIOD</span>
          <strong>{periodLabel}</strong>
        </div>

        <div className="operations-report-periods">
          <button
            className={period === "7" ? "is-active" : ""}
            onClick={() => setPeriod("7")}
          >
            7 days
          </button>
          <button
            className={period === "30" ? "is-active" : ""}
            onClick={() => setPeriod("30")}
          >
            30 days
          </button>
          <button
            className={period === "all" ? "is-active" : ""}
            onClick={() => setPeriod("all")}
          >
            All time
          </button>
        </div>
      </div>

      <div className="operations-report-metrics">
        <article className="surface-card operations-stat">
          <div className="operations-report-icon">
            <Banknote size={19} />
          </div>
          <span>Sales revenue</span>
          <strong>
            {hasSalesSnapshot && !currencySettingsInvalid
              ? formatMoney(report.revenue, shopCurrency)
              : "Unavailable"}
          </strong>
          <small>
            {hasSalesSnapshot
              ? `${report.transactionCount} transactions`
              : "Sales data is unavailable."}
            {hasSalesSnapshot && report.unconvertedRevenue > 0
              ? " · " + report.unconvertedRevenue + " excluded/unconverted"
              : ""}
          </small>
        </article>

        <article className="surface-card operations-stat">
          <div className="operations-report-icon">
            <TrendingUp size={19} />
          </div>
          <span>Estimated gross profit</span>
          <strong className={
            report.grossProfit !== null && report.grossProfit < 0
              ? "report-negative"
              : ""
           }>
            {!hasSalesSnapshot || currencySettingsInvalid
            ? "Unavailable"
            : report.grossProfit === null
            ? "Unavailable"
            : formatMoney(report.grossProfit, shopCurrency)}
          </strong>
          <small>
            Unavailable while selected revenue or cost records cannot be
            converted reliably.
          </small>
        </article>

        <article className="surface-card operations-stat">
          <div className="operations-report-icon">
            <Wallet size={19} />
          </div>
          <span>Cost of goods sold</span>
          <strong>
            {hasSalesSnapshot && !currencySettingsInvalid
              ? formatMoney(report.costOfGoods, shopCurrency)
              : "Unavailable"}
          </strong>
          <small>
            {hasSalesSnapshot
              ? "Cost attached to recorded sales"
              : "Sales data is unavailable."}
            {hasSalesSnapshot && report.unconvertedCosts > 0
              ? " · " + report.unconvertedCosts + " excluded/unconverted"
              : ""}
          </small>
        </article>

        <article className="surface-card operations-stat">
          <div className="operations-report-icon">
            <Package size={19} />
          </div>
          <span>Current stock value</span>
          <strong>
            {hasInventorySnapshot && !currencySettingsInvalid
              ? formatMoney(stock.valuation, shopCurrency)
              : "Unavailable"}
          </strong>
          <small>
            {hasInventorySnapshot
              ? Number.isFinite(stock.totalUnits)
                ? `${stock.totalUnits} units still in stock`
                : "Stock unit total unavailable"
              : "Inventory data is unavailable."}
            {hasInventorySnapshot && stock.unconvertedValuation > 0
              ? " · " +
                stock.unconvertedValuation +
                " valuation record(s) excluded/unconverted"
              : ""}
          </small>
        </article>
      </div>

      {((hasSalesSnapshot &&
        (report.unconvertedRevenue > 0 ||
          report.unconvertedCosts > 0 ||
          report.invalidSaleQuantities > 0 ||
          report.invalidSaleQuantityTotals > 0 ||
          report.invalidTotalCalculations > 0 ||
          report.unknownPaymentMethods > 0 ||
          invalidDateSalesCount > 0)) ||
        (hasInventorySnapshot && stock.unconvertedValuation > 0)) && (
        <div className="operations-note" role="status">
          <strong>These reports are incomplete.</strong>{" "}
          {hasSalesSnapshot && report.unknownCurrencyRevenue > 0 && (
            <span>
              {report.unknownCurrencyRevenue} sale(s) with unavailable
              currency were excluded from revenue.
            </span>
          )}{" "}
          {hasSalesSnapshot && report.unknownCurrencyCosts > 0 && (
            <span>
              {report.unknownCurrencyCosts} sale cost(s) with unavailable
              currency were excluded from cost of goods and gross profit.
            </span>
          )}{" "}
          {hasSalesSnapshot && report.unknownCostAmounts > 0 && (
            <span>
              {report.unknownCostAmounts} sale(s) with unavailable cost amounts
              were excluded from cost of goods and gross profit.
            </span>
          )}{" "}
          {hasSalesSnapshot && report.invalidSaleAmounts > 0 && (
            <span>
              {report.invalidSaleAmounts} sale(s) with invalid, negative, or
              non-finite amounts were excluded from revenue; gross profit is
              unavailable.
            </span>
          )}{" "}
          {hasSalesSnapshot && report.invalidSaleQuantities > 0 && (
            <span>
              {report.invalidSaleQuantities} accessory sale(s) have invalid
              quantities and were excluded from unit counts.
            </span>
          )}{" "}
          {hasSalesSnapshot && report.invalidSaleQuantityTotals > 0 && (
            <span>
              Accessory sale-unit totals exceeded the supported numeric range
              and are unavailable.
            </span>
          )}{" "}
          {hasSalesSnapshot && report.invalidTotalCalculations > 0 && (
            <span>
              {report.invalidTotalCalculations} financial total calculation(s)
              exceeded the supported numeric range.
            </span>
          )}{" "}
          {hasSalesSnapshot && report.unknownPaymentMethods > 0 && (
            <span>
              {report.unknownPaymentMethods} sale(s) have an unsupported or
              missing payment method; they are excluded from the payment
              method breakdown.
            </span>
          )}{" "}
          {hasSalesSnapshot && report.unavailableRateRevenue > 0 && (
            <span>
              {report.unavailableRateRevenue} sale(s) were not converted because
              an exchange rate is unavailable.
            </span>
          )}{" "}
          {hasSalesSnapshot && report.unavailableRateCosts > 0 && (
            <span>
              {report.unavailableRateCosts} sale cost(s) were not converted
              because an exchange rate is unavailable.
            </span>
          )}{" "}
          {hasSalesSnapshot && invalidDateSalesCount > 0 && (
            <span>
              {invalidDateSalesCount} sale(s) with invalid dates cannot be
              assigned to a reporting period.
            </span>
          )}{" "}
          {hasInventorySnapshot && stock.unknownCurrencyValuation > 0 && (
            <span>
              {stock.unknownCurrencyValuation} inventory valuation record(s)
              with unavailable currency were excluded.
            </span>
          )}{" "}
          {hasInventorySnapshot && stock.unknownCostValuation > 0 && (
            <span>
              {stock.unknownCostValuation} inventory valuation record(s) with
              unavailable cost amounts were excluded.
            </span>
          )}{" "}
          {hasInventorySnapshot && stock.unknownQuantityValuation > 0 && (
            <span>
              {stock.unknownQuantityValuation} accessory record(s) with invalid
              quantities were excluded from stock counts and valuation.
            </span>
          )}{" "}
          {hasInventorySnapshot && stock.unavailableRateValuation > 0 && (
            <span>
              {stock.unavailableRateValuation} inventory valuation record(s)
              could not be converted because an exchange rate is unavailable.
            </span>
          )}{" "}
          {hasInventorySnapshot && stock.invalidValuationTotals > 0 && (
            <span>
              Inventory valuation total exceeded the supported numeric range.
            </span>
          )}{" "}
          {hasInventorySnapshot && stock.invalidStockQuantityTotals > 0 && (
            <span>
              Accessory unit total exceeded the supported numeric range.
            </span>
          )}{" "}
          Some records may be excluded because amounts, currencies,
          quantities, or exchange rates are invalid or unavailable. Gross
          profit is not shown when revenue or costs cannot be converted
          reliably. Issue categories can overlap; each record is excluded only
          once from a particular subtotal.
        </div>
      )}

      <div className="operations-report-grid">
        <section className="surface-card operations-report-card">
          <div className="inventory-card-heading">
            <div>
              <div className="card-kicker">SALES PERFORMANCE</div>
              <h2>Daily sales</h2>
            </div>
            <CalendarClock size={19} />
          </div>

          {!hasSalesSnapshot || currencySettingsInvalid ? (
            <div className="inventory-empty">
              <BarChart3 size={25} />
              <strong>Sales report unavailable</strong>
              <span>
                {!hasSalesSnapshot
                  ? "Browser sales data could not be read."
                  : "Shop currency settings are invalid or unavailable."}
              </span>
            </div>
          ) : report.transactionCount === 0 ? (
            <div className="inventory-empty">
              <BarChart3 size={25} />
              <strong>No sales in this period</strong>
              <span>Completed transactions will appear here.</span>
            </div>
          ) : (
            <div className="operations-report-chart">
              {dailySales.map((day) => (
                <div className="operations-report-bar-row" key={day.key}>
                  <span>{day.label}</span>
                  <div className="operations-report-bar-track">
                    <div
                      className="operations-report-bar-fill"
                      style={{
                        width: `${
                          Number.isFinite(day.total)
                            ? (day.total / highestDailySale) * 100
                            : 0
                        }%`,
                      }}
                    />
                  </div>
                  <strong>{formatMoney(day.total, shopCurrency)}</strong>
                </div>
              ))}
            </div>
          )}
        </section>

        <section className="surface-card operations-report-card">
  <div className="inventory-card-heading">
    <div>
      <div className="card-kicker">PRODUCT PERFORMANCE</div>
      <h2>Sales by category</h2>
    </div>
    <ShoppingCart size={19} />
  </div>

  {!hasSalesSnapshot || currencySettingsInvalid ? (
    <p className="operations-report-empty">Sales report unavailable.</p>
  ) : (
  <>
  <div className="operations-report-breakdown">
    <div className="operations-report-breakdown-row">
      <div className="operations-report-breakdown-icon">
        <Smartphone size={18} />
      </div>

      <div>
        <strong>Phones & devices</strong>
        <span>{report.deviceCount} transactions</span>
      </div>

      <strong>
        {currencySettingsInvalid
          ? "Unavailable"
          : formatMoney(report.categoryTotals.devices, shopCurrency)}
      </strong>
    </div>

    <div className="operations-report-breakdown-row">
      <div className="operations-report-breakdown-icon">
        <Package size={18} />
      </div>

      <div>
        <strong>Accessories & parts</strong>
        <span>
          {report.accessoryCount} transactions · {report.accessoryUnits} units
        </span>
      </div>

      <strong>
        {currencySettingsInvalid
          ? "Unavailable"
          : formatMoney(report.categoryTotals.accessories, shopCurrency)}
      </strong>
    </div>
  </div>

  <div className="operations-report-divider" />

  <div className="card-kicker">RECORDED SALE VALUE BY PAYMENT METHOD</div>
  <p className="operations-report-empty">
    The selected payment method applies to the full sale amount. Partial
    customer payments are not supported.
  </p>

  {Object.keys(report.paymentTotals).length === 0 ? (
    <p className="operations-report-empty">
      No payment records for this period.
    </p>
  ) : (
    <div className="operations-report-payments">
      {Object.entries(report.paymentTotals).map(([method, total]) => (
        <div className="operations-report-payment" key={method}>
          <span>{method}</span>
          <strong>
            {currencySettingsInvalid
              ? "Unavailable"
              : formatMoney(total, shopCurrency)}
          </strong>
        </div>
      ))}
    </div>
  )}
  </>
  )}
</section>
      </div>

      <section className="surface-card operations-report-card">
        <div className="inventory-card-heading">
          <div>
            <div className="card-kicker">CURRENT INVENTORY</div>
            <h2>Stock position</h2>
          </div>
          <Package size={19} />
        </div>

        <div className="operations-report-stock-grid">
          <div>
            <Smartphone size={19} />
            <span>Devices in stock</span>
            <strong>{hasInventorySnapshot ? stock.deviceCount : "Unavailable"}</strong>
          </div>

          <div>
            <Package size={19} />
            <span>Accessory types</span>
            <strong>{hasInventorySnapshot ? stock.accessoryTypes : "Unavailable"}</strong>
          </div>

          <div>
            <ShoppingCart size={19} />
            <span>Accessory units</span>
            <strong>
              {hasInventorySnapshot && Number.isFinite(stock.accessoryUnits)
                ? stock.accessoryUnits
                : "Unavailable"}
            </strong>
          </div>

          <div>
            <ArrowLeftRight size={19} />
            <span>With middle-men</span>
            <strong>{hasInventorySnapshot ? stock.withMiddleMan : "Unavailable"}</strong>
          </div>

          <div>
            <Wrench size={19} />
            <span>At repairers</span>
            <strong>{hasInventorySnapshot ? stock.atRepairer : "Unavailable"}</strong>
          </div>
        </div>

        <p className="inventory-disclaimer">
          Stock valuation uses recorded purchase cost and remaining quantities.
          Sold items are excluded. Devices are counted individually.
        </p>
      </section>

      <section className="surface-card operations-report-card">
  <div className="inventory-card-heading">
    <div>
      <div className="card-kicker">TRANSACTION HISTORY</div>
      <h2>Recent sales</h2>
    </div>

    <span className="inventory-count">
      {hasSalesSnapshot ? `${filteredSales.length} transactions` : "Unavailable"}
    </span>
  </div>

  {!hasSalesSnapshot ? (
    <div className="inventory-empty">
      <Receipt size={25} />
      <strong>Sales records unavailable</strong>
      <span>Browser sales data could not be read.</span>
    </div>
  ) : recentSales.length === 0 ? (
    <div className="inventory-empty">
      <Receipt size={25} />
      <strong>
        {salesReadState.readError
          ? "No transactions in the last successful read"
          : "No transactions to display"}
      </strong>
      <span>
        {salesReadState.readError
          ? "Current sales data could not be verified."
          : "Record a sale to start building your reports."}
      </span>
    </div>
  ) : (
    <div className="operations-record-list">
      {recentSales.map((sale) => {
        const accessory =
          getSaleCategory(sale) === "Accessory / spare part";
        const saleQuantity = getSaleQuantity(sale);

        return (
          <article className="operations-record" key={sale.id}>
            <div className="operations-record-icon">
              {accessory ? (
                <Package size={17} />
              ) : (
                <Smartphone size={17} />
              )}
            </div>

            <div className="operations-record-copy">
              <strong>{sale.deviceName || "Unnamed item"}</strong>

              <span>
                {accessory
                  ? `${saleQuantity ?? "Unavailable"} units`
                  : sale.identifier || "Device sale"}
                {" · "}
                {new Date(sale.transactionDate).toLocaleString("en-UG")}
              </span>

              <span>
                {getKnownPaymentMethod(sale.paymentMethod) ??
                  "Payment method unavailable"}
              </span>
            </div>

            <strong className="operations-amount">
              {formatMoney(
                getKnownSaleAmount(sale.salePrice) ?? Number.NaN,
                getKnownRecordCurrency(sale.currencyCode)
              )}
            </strong>
          </article>
        );
      })}
    </div>
  )}
</section>

      <div className="operations-note">
        <ShieldCheck size={16} />
        <span>
          Reports are calculated from this browser's local StockPilot records.
          Gross profit is an estimate before expenses, taxes, operating costs
          and any unrecorded discounts or refunds. These reports are not yet
          cloud-synchronised or backed by a secure database.
        </span>
      </div>
    </section>
  );
}

const config: Partial<
  Record<
    PageKey,
    {
      title: string;
      description: string;
      eyebrow: string;
      icon: typeof Package;
      action: string;
      fields: { label: string; placeholder: string; type?: string }[];
      records: OperationRecord[];
      note: string;
    }
  >
> = {
  Sales: {
    title: "Express checkout",
    eyebrow: "POINT OF SALE",
    description:
      "Find a serialized device or accessory, record payment and prepare a digital receipt.",
    icon: ShoppingCart,
    action: "Record demo sale",
    fields: [
      { label: "IMEI, serial or product", placeholder: "Scan or enter device identifier" },
      { label: "Selling price (UGX)", placeholder: "e.g. 850000", type: "number" },
      { label: "Payment method", placeholder: "Cash / MTN MoMo / Airtel Money / Bank transfer" },
      { label: "Customer WhatsApp (optional)", placeholder: "+256…" },
    ],
    records: [
      {
        id: 1,
        primary: "Demo iPhone 15 · 128 GB",
        secondary: "DEMO-IMEI-001 · Today 09:12",
        status: "Paid",
        amount: "UGX 850,000",
      },
      {
        id: 2,
        primary: "USB-C charger · 2 units",
        secondary: "Demo transaction · Yesterday",
        status: "Paid",
        amount: "UGX 60,000",
      },
    ],
    note: "Demo only: no payment is processed and no WhatsApp/SMS is sent. PDF generation and real receipt delivery require implementation and testing.",
  },
  Custody: {
    title: "Device custody ledger",
    eyebrow: "MIDDLE-MAN TRACKING",
    description:
      "Track which device was entrusted to whom, when it left, and whether it was sold or returned.",
    icon: ArrowLeftRight,
    action: "Add demo custody record",
    fields: [
      { label: "IMEI or serial", placeholder: "Scan or enter identifier" },
      { label: "Person / middle-man", placeholder: "Name" },
      { label: "Contact", placeholder: "Phone number" },
      { label: "Expected return date", placeholder: "YYYY-MM-DD", type: "date" },
    ],
    records: [
      {
        id: 1,
        primary: "DEMO-IMEI-002 · Galaxy A15",
        secondary: "Assigned to Demo Agent · Today",
        status: "With middle-man",
      },
      {
        id: 2,
        primary: "DEMO-IMEI-004 · iPhone 13",
        secondary: "Assigned to Demo Agent B · Yesterday",
        status: "Follow-up due",
      },
    ],
    note: "Ownership and location should remain separate: a phone with a middle-man is still owned stock until a sale or other disposal is confirmed.",
  },
  Repairs: {
    title: "Repair tracking",
    eyebrow: "SERVICE WORKFLOW",
    description:
      "Record devices sent to technicians and track diagnosis, repair cost and return to shop.",
    icon: Wrench,
    action: "Add demo repair job",
    fields: [
      { label: "IMEI or serial", placeholder: "Scan or enter identifier" },
      { label: "Technician / repair shop", placeholder: "Technician name" },
      { label: "Reported issue", placeholder: "e.g. damaged screen" },
      { label: "Estimated repair cost (UGX)", placeholder: "Optional estimate", type: "number" },
    ],
    records: [
      {
        id: 1,
        primary: "DEMO-IMEI-003 · Tecno Spark 20",
        secondary: "Charging port diagnosis · Yesterday",
        status: "At repairer",
      },
      {
        id: 2,
        primary: "DEMO-SERIAL-005 · Samsung A-series",
        secondary: "Screen replacement · Today",
        status: "Awaiting quote",
      },
    ],
    note: "Repair costs should be logged separately from device wholesale cost and sale revenue. This demo does not contact technicians.",
  },
  "Daily closing": {
    title: "Daily cash reconciliation",
    eyebrow: "END-OF-DAY CONTROL",
    description:
      "Compare expected cash with the physical count and record discrepancies for owner review.",
    icon: ClipboardCheck,
    action: "Save demo closing",
    fields: [
      { label: "Opening cash (UGX)", placeholder: "0", type: "number" },
      { label: "Cash received (UGX)", placeholder: "0", type: "number" },
      { label: "Cash paid out (UGX)", placeholder: "0", type: "number" },
      { label: "Actual cash counted (UGX)", placeholder: "0", type: "number" },
    ],
    records: [
      {
        id: 1,
        primary: "Demo closing · 26 Oct",
        secondary: "Cash and non-cash payments reviewed",
        status: "Sample",
      },
    ],
    note: "Expected cash = opening cash + cash received − cash paid out. Mobile money and bank transfers are not physical cash.",
  },
  Reports: {
    title: "Business reports",
    eyebrow: "INSIGHTS & REPORTING",
    description: "Live reports calculated from saved transactions and inventory.",
    icon: FileText,
    action: "",
    fields: [],
    records: [],
    note: "",
  },
  "Suppliers & credit": {
    title: "Supplier credit & customer layaway",
    eyebrow: "CREDIT LEDGERS",
    description:
      "Track what the shop owes suppliers and what customers still owe on reserved devices.",
    icon: Banknote,
    action: "Add demo credit entry",
    fields: [
      { label: "Entry type", placeholder: "Supplier payable / Customer layaway" },
      { label: "Supplier or customer", placeholder: "Name" },
      { label: "Device IMEI / reference", placeholder: "Identifier or invoice reference" },
      { label: "Amount due (UGX)", placeholder: "e.g. 300000", type: "number" },
      { label: "Due date", placeholder: "YYYY-MM-DD", type: "date" },
    ],
    records: [
      {
        id: 1,
        primary: "Demo supplier payable",
        secondary: "Supplier A · Example balance UGX 450,000 · Due 30 Oct",
        status: "Part-paid",
      },
      {
        id: 2,
        primary: "Demo customer layaway",
        secondary: "Reserved DEMO-IMEI-007 · Deposit UGX 200,000",
        status: "Balance due",
      },
    ],
    note: "The real workflow must record every payment, calculate remaining balance, and prevent a reserved device from being released before the shop's rules are satisfied. These sample entries are not financial records.",
  },
  "Team & shops": {
    title: "Team & shop access",
    eyebrow: "PEOPLE & LOCATIONS",
    description:
      "Plan shop membership, branch workspaces and least-privilege staff access.",
    icon: Users,
    action: "Add demo team member",
    fields: [
      { label: "Staff display name", placeholder: "Name" },
      { label: "Role", placeholder: "Owner / Admin / Attendant / Clerk" },
      { label: "Shop or branch", placeholder: "Shop A / Shop B / Warehouse" },
    ],
    records: [
      {
        id: 1,
        primary: "Demo Owner",
        secondary: "Val Gadgets Demo · All owner controls",
        status: "Owner",
      },
      {
        id: 2,
        primary: "Demo Attendant",
        secondary: "Shop A · POS and stock lookup only",
        status: "Clerk",
      },
      {
        id: 3,
        primary: "Branch transfer · Shop A → Shop B",
        secondary: "Example transfer awaiting destination confirmation",
        status: "In-transit",
      },
      {
        id: 4,
        primary: "Audit event · Demo Clerk",
        secondary: "Sample action log · no real staff data",
        status: "Logged",
      },
    ],
    note: "This screen is a design prototype only. Real role enforcement must be implemented in the backend/database; hiding fields in the interface is not security. Transfers need Request → In-transit → Received states and audit events must be append-only.",
  },
  Settings: {
    title: "Workspace settings",
    eyebrow: "PREFERENCES & CONTROLS",
    description:
      "Configure shop identity, currency, alerts and planned offline operation.",
    icon: Building2,
    action: "Save demo preference",
    fields: [
      { label: "Shop name", placeholder: "Val Gadgets Demo" },
      { label: "Default currency", placeholder: "UGX / KWD / USD" },
      { label: "Aging stock threshold (days)", placeholder: "30", type: "number" },
    ],
    records: [
      {
        id: 1,
        primary: "Manual model entry",
        secondary: "Always available if lookup fails or internet is slow",
        status: "Required",
      },
      {
        id: 2,
        primary: "Offline queue and sync",
        secondary: "Local persistence, conflict handling and retry policy",
        status: "Planned",
      },
    ],
    note: "Offline support requires durable local storage and carefully tested synchronisation; it is not enabled by this settings mockup.",
  },
};

export default function Operations({ page }: { page: PageKey }) {
  const details = config[page];

  const [records, setRecords] = useState<OperationRecord[]>(
    details?.records ?? []
  );
  const [values, setValues] = useState<string[]>(
    details?.fields.map(() => "") ?? []
  );
  const [notice, setNotice] = useState("");

if (page === "Daily closing") {
  return <DailyClosing />;
}

if (page === "Suppliers & credit") {
  return <SupplierCredit />;
}

if (page === "Purchases") {
  return <Purchases />;
}

if (page === "Reports") {
  return <ReportsView />;
}
if (page === "Settings") {
  return <Settings />;
}

  if (!details) return null;

  const Icon = details.icon;

  const submit = () => {
    const first = values.find((value) => value.trim());

    if (!first) {
      setNotice("Enter at least one field before adding a demo record.");
      return;
    }

    setRecords((current) => [
      {
        id: Date.now(),
        primary: first,
        secondary:
          values.filter(Boolean).slice(1).join(" · ") || "Demo entry · Just now",
        status: "Demo",
      },
      ...current,
    ]);

    setValues(details.fields.map(() => ""));
    setNotice("Demo record added in this page session. It is not saved to a database.");
  };

  return (
    <section className="operations-page page-content">
      <div className="eyebrow">
        <span className="eyebrow-line" /> {details.eyebrow}
      </div>

      <div className="operations-heading">
        <div>
          <h1>{details.title}</h1>
          <p className="page-subtitle">{details.description}</p>
        </div>
        <div className="operations-heading-icon">
          <Icon size={22} />
        </div>
      </div>

      <div className="operations-grid">
        <section className="surface-card operations-form-card">
          <div className="card-kicker">QUICK ACTION</div>
          <h2>{details.action}</h2>

          <div className="operations-form">
            {details.fields.map((field, index) => (
              <label className="inventory-field" key={field.label}>
                <span>{field.label}</span>
                <input
                  type={field.type ?? "text"}
                  placeholder={field.placeholder}
                  value={values[index] ?? ""}
                  onChange={(event) =>
                    setValues((current) =>
                      current.map((value, position) =>
                        position === index ? event.target.value : value
                      )
                    )
                  }
                />
              </label>
            ))}
          </div>

          {notice && (
            <p className="operations-notice" role="status">
              <CheckCircle2 size={15} /> {notice}
            </p>
          )}

          <button className="button button-primary" onClick={submit}>
            <Plus size={16} /> {details.action}
          </button>

          <p className="inventory-disclaimer">
            Prototype only · fictional data · no persistent storage or real
            message/payment integration.
          </p>
        </section>

        <section className="surface-card operations-list-card">
          <div className="inventory-card-heading">
            <div>
              <div className="card-kicker">WORKSPACE REGISTER</div>
              <h2>Recent demo records</h2>
            </div>
            <span className="inventory-count">{records.length} records</span>
          </div>

          <div className="operations-record-list">
            {records.map((record) => (
              <article className="operations-record" key={record.id}>
                <div className="operations-record-icon">
                  <Receipt size={17} />
                </div>
                <div className="operations-record-copy">
                  <strong>{record.primary}</strong>
                  <span>{record.secondary}</span>
                </div>
                <span className="inventory-device-status status-available">
                  {record.status}
                </span>
                {record.amount && (
                  <strong className="operations-amount">{record.amount}</strong>
                )}
              </article>
            ))}
          </div>

          <div className="operations-note">
            <ShieldCheck size={16} />
            <span>{details.note}</span>
          </div>
        </section>
      </div>
    </section>
  );
}
