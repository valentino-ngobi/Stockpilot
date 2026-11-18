
import { useEffect, useMemo, useState } from "react";
import {
  CalendarClock,
  CheckCircle2,
  ClipboardCheck,
  History,
  Wallet,
} from "lucide-react";
import {
  formatCurrency,
  getKnownSaleAmount,
  getKnownRecordCurrency,
  getShopCurrency,
  SETTINGS_STORAGE_KEY,
  type CurrencyCode,
} from "../utils/currency";
import { getKnownPaymentMethod } from "../utils/sales";

const SALES_KEY = "stockpilot-sales";
const CLOSINGS_KEY = "stockpilot-daily-closings";

type SaleRecord = {
  id: string;
  salePrice: number;
  paymentMethod: string;
  transactionDate: string;
  currencyCode?: CurrencyCode;
};

type CurrencyClosingSummary = {
  currencyCode: CurrencyCode | null;
  openingCash: number;
  cashReceived: number;
  cashPaidOut: number;
  expectedCash: number;
  actualCash: number;
  difference: number;
  totalSales: number;
  transactionCount: number;
  paymentTotals: Record<string, number>;
};

type ClosingRecord = {
  id: string;
  date: string;
  closedAt: string;
  currencySummaries?: CurrencyClosingSummary[];

  // Legacy fields retained for previously saved closings.
  openingCash?: number;
  cashReceived?: number;
  cashPaidOut?: number;
  expectedCash?: number;
  actualCash?: number;
  difference?: number;
  totalSales?: number;
  transactionCount?: number;
  paymentTotals?: Record<string, number>;
};

type CashInputs = {
  openingCash: string;
  cashPaidOut: string;
  actualCash: string;
};

type CurrencySalesSummary = {
  currencyCode: CurrencyCode;
  paymentTotals: Record<string, number>;
  totalSales: number;
  cashReceived: number;
  nonCashReceived: number;
  transactionCount: number;
};

type StoredArraySnapshot<T> = {
  raw: string | null;
  records: T[];
};

type StoredArrayReadState<T> = {
  records: T[];
  hasValidSnapshot: boolean;
  readError: boolean;
};

function readStoredArray<T>(key: string): StoredArraySnapshot<T> | null {
  try {
    const raw = localStorage.getItem(key);
    if (raw === null) return { raw, records: [] };

    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return null;

    return { raw, records: parsed as T[] };
  } catch {
    return null;
  }
}

function toStoredArrayReadState<T>(
  snapshot: StoredArraySnapshot<T> | null
): StoredArrayReadState<T> {
  return {
    records: snapshot?.records ?? [],
    hasValidSnapshot: snapshot !== null,
    readError: snapshot === null,
  };
}

function getLocalDateKey(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");

  return `${year}-${month}-${day}`;
}

function formatMoney(amount: number, currencyCode: CurrencyCode | null) {
  return formatCurrency(amount, currencyCode);
}

function getCurrencyLabel(currencyCode: CurrencyCode | null) {
  return currencyCode ?? "Currency unavailable";
}

function getStoredAmount(value: unknown, allowNegative = false): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return Number.NaN;
  }
  return allowNegative || value >= 0 ? value : Number.NaN;
}

function getStoredCount(value: unknown): number {
  return typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= 0
    ? value
    : Number.NaN;
}

function getStoredPaymentTotals(value: unknown): Record<string, number> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }

  return Object.fromEntries(
    Object.entries(value).map(([method, amount]) => [
      method,
      getStoredAmount(amount),
    ])
  );
}

function formatDate(date: string) {
  return new Date(`${date}T00:00:00`).toLocaleDateString("en-UG", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}

function getDefaultInputs(): CashInputs {
  return {
    openingCash: "0",
    cashPaidOut: "0",
    actualCash: "",
  };
}

function getClosingSummaries(
  closing: ClosingRecord
): CurrencyClosingSummary[] {
  if (
    Array.isArray(closing.currencySummaries) &&
    closing.currencySummaries.length > 0
  ) {
    return closing.currencySummaries.map((value) => {
      const summary =
        value !== null && typeof value === "object"
          ? (value as unknown as Record<string, unknown>)
          : {};
      return {
        currencyCode: getKnownRecordCurrency(summary.currencyCode),
        openingCash: getStoredAmount(summary.openingCash),
        cashReceived: getStoredAmount(summary.cashReceived),
        cashPaidOut: getStoredAmount(summary.cashPaidOut),
        expectedCash: getStoredAmount(summary.expectedCash),
        actualCash: getStoredAmount(summary.actualCash),
        difference: getStoredAmount(summary.difference, true),
        totalSales: getStoredAmount(summary.totalSales),
        transactionCount: getStoredCount(summary.transactionCount),
        paymentTotals: getStoredPaymentTotals(summary.paymentTotals),
      };
    });
  }

  // Old closing records did not store a currency code, so their currency
  // cannot be recovered safely.
  return [
    {
      currencyCode: null,
      openingCash: getStoredAmount(closing.openingCash),
      cashReceived: getStoredAmount(closing.cashReceived),
      cashPaidOut: getStoredAmount(closing.cashPaidOut),
      expectedCash: getStoredAmount(closing.expectedCash),
      actualCash: getStoredAmount(closing.actualCash),
      difference: getStoredAmount(closing.difference, true),
      totalSales: getStoredAmount(closing.totalSales),
      transactionCount: getStoredCount(closing.transactionCount),
      paymentTotals: getStoredPaymentTotals(closing.paymentTotals),
    },
  ];
}

export default function DailyClosing() {
  const [salesReadState, setSalesReadState] = useState(() =>
    toStoredArrayReadState(readStoredArray<SaleRecord>(SALES_KEY))
  );
  const sales = salesReadState.records;

  const [closingsReadState, setClosingsReadState] = useState(() =>
    toStoredArrayReadState(readStoredArray<ClosingRecord>(CLOSINGS_KEY))
  );
  const closings = closingsReadState.records;
  const [shopCurrency, setShopCurrency] = useState<CurrencyCode | null>(
    () => getShopCurrency()
  );
  const [reviewRequired, setReviewRequired] = useState(false);

  const [selectedDate, setSelectedDate] = useState(() =>
    getLocalDateKey(new Date())
  );

  const [cashInputs, setCashInputs] = useState<
    Record<string, CashInputs>
  >({});

  const [notice, setNotice] = useState("");

  useEffect(() => {
    const refreshData = (event?: StorageEvent) => {
      if (
        event &&
        event.key !== SALES_KEY &&
        event.key !== CLOSINGS_KEY &&
        event.key !== SETTINGS_STORAGE_KEY &&
        event.key !== null
      ) {
        return;
      }

      if (!event || event.key === SALES_KEY || event.key === null) {
        const latestSales = readStoredArray<SaleRecord>(SALES_KEY);
        if (latestSales) {
          const salesChanged =
            JSON.stringify(latestSales.records) !== JSON.stringify(sales);
          setSalesReadState((current) => ({
            records: salesChanged ? latestSales.records : current.records,
            hasValidSnapshot: true,
            readError: false,
          }));

          if (salesChanged) {
            setReviewRequired(true);
            setNotice(
              "Sales changed in another tab. Review the updated figures and cash entries before saving the closing."
            );
          }
        } else {
          setSalesReadState((current) => ({ ...current, readError: true }));
        }
      }

      if (!event || event.key === CLOSINGS_KEY || event.key === null) {
        const latestClosings = readStoredArray<ClosingRecord>(CLOSINGS_KEY);
        if (latestClosings) {
          setClosingsReadState((current) => ({
            records:
              JSON.stringify(current.records) ===
              JSON.stringify(latestClosings.records)
                ? current.records
                : latestClosings.records,
            hasValidSnapshot: true,
            readError: false,
          }));
        } else {
          setClosingsReadState((current) => ({ ...current, readError: true }));
        }
      }

      if (!event || event.key === SETTINGS_STORAGE_KEY || event.key === null) {
        const latestShopCurrency = getShopCurrency();
        if (latestShopCurrency !== shopCurrency) {
          setShopCurrency(latestShopCurrency);
          setReviewRequired(true);
          setNotice(
            latestShopCurrency
              ? "Shop currency changed in another tab. Review the updated closing figures and cash entries before saving."
              : "Shop currency settings are invalid or unavailable. No closing can be saved until they are corrected."
          );
        }
      }
    };
    const refreshOnFocus = () => refreshData();

    window.addEventListener("focus", refreshOnFocus);
    window.addEventListener("storage", refreshData);

    return () => {
      window.removeEventListener("focus", refreshOnFocus);
      window.removeEventListener("storage", refreshData);
    };
  }, [sales, shopCurrency]);

  const hasSalesSnapshot = salesReadState.hasValidSnapshot;
  const hasClosingsSnapshot = closingsReadState.hasValidSnapshot;

  const dailySales = useMemo(() => {
    return sales.filter((sale) => {
      const date = new Date(sale.transactionDate);

      return (
        !Number.isNaN(date.getTime()) &&
        getLocalDateKey(date) === selectedDate
      );
    });
  }, [sales, selectedDate]);

  const unresolvedCurrencySales = useMemo(
    () => dailySales.filter((sale) => !getKnownRecordCurrency(sale.currencyCode)),
    [dailySales]
  );

  const invalidAmountSales = useMemo(
    () => dailySales.filter((sale) => getKnownSaleAmount(sale.salePrice) === null),
    [dailySales]
  );

  const unknownPaymentMethodSales = useMemo(
    () =>
      dailySales.filter(
        (sale) => getKnownPaymentMethod(sale.paymentMethod) === null
      ),
    [dailySales]
  );

  const currencySummaries = useMemo(() => {
    const grouped = new Map<string, CurrencySalesSummary>();

    dailySales.forEach((sale) => {
      const currencyCode = getKnownRecordCurrency(sale.currencyCode);
      if (!currencyCode) return;

      if (!grouped.has(currencyCode)) {
        grouped.set(currencyCode, {
          currencyCode,
          paymentTotals: {},
          totalSales: 0,
          cashReceived: 0,
          nonCashReceived: 0,
          transactionCount: 0,
        });
      }

      const summary = grouped.get(currencyCode)!;
      const amount = getKnownSaleAmount(sale.salePrice);
      if (amount === null) return;
      const method = getKnownPaymentMethod(sale.paymentMethod);
      const salesTotal = summary.totalSales + amount;
      if (!Number.isFinite(salesTotal)) {
        summary.totalSales = Number.NaN;
        return;
      }

      summary.totalSales = salesTotal;
      summary.transactionCount += 1;
      if (!method) return;

      const paymentTotal = (summary.paymentTotals[method] || 0) + amount;
      const receivedTotal =
        method === "Cash"
          ? summary.cashReceived + amount
          : summary.nonCashReceived + amount;
      if (
        !Number.isFinite(paymentTotal) ||
        !Number.isFinite(salesTotal) ||
        !Number.isFinite(receivedTotal)
      ) {
        summary.paymentTotals[method] = Number.NaN;
        summary.totalSales = Number.NaN;
        if (method === "Cash") summary.cashReceived = Number.NaN;
        else summary.nonCashReceived = Number.NaN;
        return;
      }

      summary.paymentTotals[method] = paymentTotal;

      if (method === "Cash") {
        summary.cashReceived = receivedTotal;
      } else {
        summary.nonCashReceived = receivedTotal;
      }
    });

    // Include the shop's operating currency even if there were no sales
    // in that currency, so the shop can still reconcile its cash drawer.
    if (shopCurrency && !grouped.has(shopCurrency)) {
      grouped.set(shopCurrency, {
        currencyCode: shopCurrency,
        paymentTotals: {},
        totalSales: 0,
        cashReceived: 0,
        nonCashReceived: 0,
        transactionCount: 0,
      });
    }

    // Keep cash entries visible and saveable if a cross-tab change removes
    // their currency from the current sales and shop-currency summaries.
    Object.keys(cashInputs).forEach((code) => {
      const currencyCode = code as CurrencyCode;
      if (!grouped.has(currencyCode)) {
        grouped.set(currencyCode, {
          currencyCode,
          paymentTotals: {},
          totalSales: 0,
          cashReceived: 0,
          nonCashReceived: 0,
          transactionCount: 0,
        });
      }
    });

    return Array.from(grouped.values()).sort((a, b) =>
      a.currencyCode.localeCompare(b.currencyCode)
    );
  }, [dailySales, shopCurrency, cashInputs]);

  const hasInvalidSummaryTotals = currencySummaries.some(
    (summary) =>
      !Number.isFinite(summary.totalSales) ||
      !Number.isFinite(summary.cashReceived) ||
      !Number.isFinite(summary.nonCashReceived) ||
      Object.values(summary.paymentTotals).some(
        (amount) => !Number.isFinite(amount)
      )
  );

  const existingClosing = closings.find(
    (closing) => closing.date === selectedDate
  );

  const sortedClosings = [...closings].sort((a, b) =>
    b.date.localeCompare(a.date)
  );

  const updateCashInput = (
    currencyCode: CurrencyCode,
    field: keyof CashInputs,
    value: string
  ) => {
    setCashInputs((previous) => ({
      ...previous,
      [currencyCode]: {
        ...getDefaultInputs(),
        ...previous[currencyCode],
        [field]: value,
      },
    }));
  };

  const getInputs = (currencyCode: CurrencyCode) => ({
    ...getDefaultInputs(),
    ...cashInputs[currencyCode],
  });

  const getReconciliation = (
    summary: CurrencySalesSummary
  ) => {
    const inputs = getInputs(summary.currencyCode);

    const opening = Number(inputs.openingCash);
    const paidOut = Number(inputs.cashPaidOut);
    const counted = Number(inputs.actualCash);

    const validOpening =
      inputs.openingCash.trim() !== "" &&
      Number.isFinite(opening) &&
      opening >= 0;

    const validPaidOut =
      inputs.cashPaidOut.trim() !== "" &&
      Number.isFinite(paidOut) &&
      paidOut >= 0;

    const validActual =
      inputs.actualCash.trim() !== "" &&
      Number.isFinite(counted) &&
      counted >= 0;

    const expectedCash =
      (validOpening ? opening : 0) +
      summary.cashReceived -
      (validPaidOut ? paidOut : 0);

    const difference = validActual
      ? counted - expectedCash
      : 0;
    const validExpected =
      Number.isFinite(expectedCash) && Number.isFinite(difference);

    return {
      inputs,
      opening,
      paidOut,
      counted,
      validOpening,
      validPaidOut,
      validActual,
      validExpected,
      expectedCash,
      difference,
    };
  };

  const saveClosing = () => {
    setNotice("");

    const latestSales = readStoredArray<SaleRecord>(SALES_KEY);
    const latestClosings = readStoredArray<ClosingRecord>(CLOSINGS_KEY);

    if (!latestSales || !latestClosings) {
      setNotice(
        "Could not safely read saved sales or closing records. No closing was saved; check browser storage before trying again."
      );
      return;
    }

    if (JSON.stringify(latestSales.records) !== JSON.stringify(sales)) {
      setSalesReadState({
        records: latestSales.records,
        hasValidSnapshot: true,
        readError: false,
      });
      setClosingsReadState({
        records: latestClosings.records,
        hasValidSnapshot: true,
        readError: false,
      });
      setReviewRequired(true);
      setNotice(
        "Sales changed in another tab. The latest sales were loaded; review the closing totals and save again."
      );
      return;
    }

    if (unresolvedCurrencySales.length > 0) {
      setNotice(
        `Cannot save this closing: ${unresolvedCurrencySales.length} sale(s) have no valid saved currency. Review those records before closing; they were excluded from currency totals.`
      );
      return;
    }

    if (invalidAmountSales.length > 0) {
      setNotice(
        `Cannot save this closing: ${invalidAmountSales.length} sale(s) have invalid, negative, or non-finite amounts. They were excluded from currency totals; review those records before closing.`
      );
      return;
    }

    if (unknownPaymentMethodSales.length > 0) {
      setNotice(
        `Cannot save this closing: ${unknownPaymentMethodSales.length} sale(s) have a missing or unsupported payment method. Resolve them before reconciling physical cash.`
      );
      return;
    }

    if (hasInvalidSummaryTotals) {
      setNotice(
        "Cannot save this closing: one or more currency totals are outside the supported numeric range."
      );
      return;
    }

    const latestShopCurrency = getShopCurrency();
    if (!latestShopCurrency) {
      setShopCurrency(null);
      setNotice(
        "Shop currency settings are invalid or unavailable. No closing was saved; review Workspace settings first."
      );
      return;
    }

    if (latestShopCurrency !== shopCurrency) {
      setShopCurrency(latestShopCurrency);
      setReviewRequired(true);
      setNotice(
        "Shop currency changed in another tab. Review the updated figures and cash entries, then save again."
      );
      return;
    }

    if (reviewRequired) {
      setNotice(
        "Review the updated sales figures and cash entries, then acknowledge before saving the closing."
      );
      return;
    }

    const reconciliations = currencySummaries.map((summary) => ({
      summary,
      reconciliation: getReconciliation(summary),
    }));

    const invalidOpening = reconciliations.some(
      ({ reconciliation }) => !reconciliation.validOpening
    );

    const invalidPaidOut = reconciliations.some(
      ({ reconciliation }) => !reconciliation.validPaidOut
    );

    const invalidActual = reconciliations.some(
      ({ reconciliation }) => !reconciliation.validActual
    );

    const negativeExpected = reconciliations.some(
      ({ reconciliation }) => reconciliation.expectedCash < 0
    );
    const invalidExpected = reconciliations.some(
      ({ reconciliation }) => !reconciliation.validExpected
    );

    if (invalidOpening || invalidPaidOut) {
      setNotice(
        "Enter valid, non-negative opening cash and cash paid out for every currency."
      );
      return;
    }

    if (invalidActual) {
      setNotice(
        "Enter the actual cash counted for every currency before saving."
      );
      return;
    }

    if (negativeExpected) {
      setNotice(
        "Expected cash cannot be negative. Check your entries."
      );
      return;
    }

    if (invalidExpected) {
      setNotice(
        "A cash reconciliation total is outside the supported numeric range. Check the sales and cash entries before saving."
      );
      return;
    }

    if (
      latestClosings.records.some(
        (closing) => closing.date === selectedDate
      )
    ) {
      setClosingsReadState({
        records: latestClosings.records,
        hasValidSnapshot: true,
        readError: false,
      });
      setNotice("A closing already exists for this date.");
      return;
    }

    const savedSummaries: CurrencyClosingSummary[] =
      reconciliations.map(({ summary, reconciliation }) => ({
        currencyCode: summary.currencyCode,
        openingCash: reconciliation.opening,
        cashReceived: summary.cashReceived,
        cashPaidOut: reconciliation.paidOut,
        expectedCash: reconciliation.expectedCash,
        actualCash: reconciliation.counted,
        difference: reconciliation.difference,
        totalSales: summary.totalSales,
        transactionCount: summary.transactionCount,
        paymentTotals: summary.paymentTotals,
      }));

    const record: ClosingRecord = {
      id: `CLOSE-${selectedDate}`,
      date: selectedDate,
      currencySummaries: savedSummaries,
      closedAt: new Date().toISOString(),
    };

    try {
      if (localStorage.getItem(CLOSINGS_KEY) !== latestClosings.raw) {
        const currentClosings = readStoredArray<ClosingRecord>(CLOSINGS_KEY);
        if (currentClosings) {
          setClosingsReadState({
            records: currentClosings.records,
            hasValidSnapshot: true,
            readError: false,
          });
        }
        setNotice(
          "Closing records changed in another tab. The latest records were loaded; review and try again."
        );
        return;
      }

      const updated = [...latestClosings.records, record];

      localStorage.setItem(
        CLOSINGS_KEY,
        JSON.stringify(updated)
      );

      setClosingsReadState({
        records: updated,
        hasValidSnapshot: true,
        readError: false,
      });
      setNotice("Daily closing saved successfully.");
      setCashInputs({});
      setReviewRequired(false);
    } catch {
      setNotice(
        "Unable to save closing. Check available browser storage."
      );
    }
  };

  return (
    <section className="operations-page page-content daily-closing-page">
      <div className="eyebrow">
        <span className="eyebrow-line" /> END-OF-DAY CONTROL
      </div>

      <div className="operations-heading">
        <div>
          <h1>Daily closing</h1>
          <p className="page-subtitle">
            Reconcile daily sales, payment methods and physical cash
            separately for each currency.
          </p>
        </div>

        <div className="operations-heading-icon">
          <ClipboardCheck size={22} />
        </div>
      </div>

      {(salesReadState.readError || closingsReadState.readError) && (
        <div className="operations-note" role="alert">
          <strong>Some daily closing data could not be read.</strong>{" "}
          {salesReadState.readError && (
            <span>
              {hasSalesSnapshot
                ? "The latest sales read failed; showing the last successfully loaded sales, so figures may be out of date. "
                : "Sales data is unavailable. "}
            </span>
          )}
          {closingsReadState.readError && (
            <span>
              {hasClosingsSnapshot
                ? "The latest closing-record read failed; showing the last successfully loaded closings, so they may be out of date."
                : "Closing records are unavailable."}
            </span>
          )}
        </div>
      )}

      <section className="surface-card daily-closing-date">
        <div>
          <div className="card-kicker">CLOSING DATE</div>
          <strong>{formatDate(selectedDate)}</strong>
        </div>

        <label className="daily-closing-date-input">
          <CalendarClock size={17} />
          <input
            type="date"
            value={selectedDate}
            onChange={(event) => {
              setSelectedDate(event.target.value);
              setNotice("");
            }}
          />
        </label>
      </section>

      {existingClosing && (
        <div className="daily-closing-existing" role="status">
          <CheckCircle2 size={18} />
          <div>
            <strong>This date has already been closed.</strong>
            <span>
              Saved on{" "}
              {new Date(existingClosing.closedAt).toLocaleString(
                "en-UG"
              )}
              . A second closing cannot be created for this date.
            </span>
          </div>
        </div>
      )}

      {unresolvedCurrencySales.length > 0 && (
        <div className="operations-note" role="alert">
          <strong>
            {unresolvedCurrencySales.length} sale(s) have an unavailable currency.
          </strong>
          <span>
            They are excluded from currency totals, and this closing cannot be
            saved until their currency is resolved.
          </span>
          <ul>
            {unresolvedCurrencySales.map((sale) => (
              <li key={sale.id}>
                {sale.id}: {formatMoney(sale.salePrice, null)}
              </li>
            ))}
          </ul>
        </div>
      )}

      {invalidAmountSales.length > 0 && (
        <div className="operations-note" role="alert">
          <strong>
            {invalidAmountSales.length} sale(s) have an invalid amount.
          </strong>
          <span>
            Invalid, negative, or non-finite amounts are excluded from totals.
            Resolve these records before saving this closing.
          </span>
          <ul>
            {invalidAmountSales.map((sale) => (
              <li key={sale.id}>
                {sale.id}:{" "}
                {formatMoney(
                  sale.salePrice,
                  getKnownRecordCurrency(sale.currencyCode)
                )}
              </li>
            ))}
          </ul>
        </div>
      )}

      {unknownPaymentMethodSales.length > 0 && (
        <div className="operations-note" role="alert">
          <strong>
            {unknownPaymentMethodSales.length} sale(s) have an unavailable
            payment method.
          </strong>
          <span>
            Their currency totals are included, but they cannot be assigned to
            cash or non-cash collections. Resolve these records before saving
            the closing.
          </span>
        </div>
      )}

      {hasInvalidSummaryTotals && (
        <div className="operations-note" role="alert">
          One or more currency totals exceed the supported numeric range.
          This closing cannot be saved until the contributing records are
          reviewed.
        </div>
      )}

      {!shopCurrency && (
        <div className="operations-note" role="status">
          Shop currency settings are invalid or unavailable. Daily closing is
          blocked until Workspace settings are corrected.
        </div>
      )}

      {reviewRequired && (
        <div className="operations-note" role="status">
          Sales or shop currency changed in another tab. Review the updated
          figures and recheck your cash entries. Your entered cash values have
          been kept.
          <button
            className="button button-secondary"
            type="button"
            onClick={() => {
              setReviewRequired(false);
              setNotice("Review acknowledged. Verify cash entries before saving.");
            }}
          >
            I reviewed the updated figures
          </button>
        </div>
      )}

      <div className="daily-closing-grid">
        <section className="surface-card daily-closing-card">
          <div className="inventory-card-heading">
            <div>
              <div className="card-kicker">DAILY COLLECTIONS</div>
              <h2>Sales by currency</h2>
              <p className="operations-report-empty">
                Each sale records one payment method for its full amount;
                partial customer payments are not supported.
              </p>
            </div>
            <Wallet size={19} />
          </div>

          {!hasSalesSnapshot ? (
            <div className="inventory-empty">
              <Wallet size={24} />
              <strong>Sales data unavailable</strong>
              <span>Browser sales data could not be read.</span>
            </div>
          ) : currencySummaries.map((summary) => (
            <div
              className="daily-closing-currency-section"
              key={summary.currencyCode}
            >
              <div className="operations-report-divider" />

              <div className="daily-closing-total">
                <strong>{summary.currencyCode}</strong>
                <strong>
                  {formatMoney(
                    summary.totalSales,
                    summary.currencyCode
                  )}
                </strong>
              </div>

              <div className="operations-report-payments">
                {Object.keys(summary.paymentTotals).length === 0 ? (
                  <div className="operations-report-payment">
                    <span>
                      {summary.transactionCount === 0
                        ? "No sales recorded"
                        : "No recognized payment methods"}
                    </span>
                    <strong>
                      {summary.transactionCount === 0
                        ? formatMoney(0, summary.currencyCode)
                        : "Unavailable"}
                    </strong>
                  </div>
                ) : (
                  Object.entries(summary.paymentTotals).map(
                    ([method, amount]) => (
                      <div
                        className="operations-report-payment"
                        key={method}
                      >
                        <span>{method}</span>
                        <strong>
                          {formatMoney(amount, summary.currencyCode)}
                        </strong>
                      </div>
                    )
                  )
                )}
              </div>

              <div className="operations-report-payment">
                <span>Cash received</span>
                <strong>
                  {formatMoney(
                    summary.cashReceived,
                    summary.currencyCode
                  )}
                </strong>
              </div>

              <div className="operations-report-payment">
                <span>Non-cash received</span>
                <strong>
                  {formatMoney(
                    summary.nonCashReceived,
                    summary.currencyCode
                  )}
                </strong>
              </div>

              <small>
                {summary.transactionCount} transactions
              </small>
            </div>
          ))}
        </section>

        <section className="surface-card daily-closing-card">
          <div className="inventory-card-heading">
            <div>
              <div className="card-kicker">CASH RECONCILIATION</div>
              <h2>Count your cash</h2>
            </div>
            <ClipboardCheck size={19} />
          </div>

          {!hasSalesSnapshot || !hasClosingsSnapshot ? (
            <div className="inventory-empty">
              <ClipboardCheck size={24} />
              <strong>Cash reconciliation unavailable</strong>
              <span>
                {!hasSalesSnapshot
                  ? "Sales data could not be read."
                  : "Closing records could not be read, so the existing closing status cannot be verified."}
              </span>
            </div>
          ) : currencySummaries.map((summary) => {
            const reconciliation = getReconciliation(summary);
            const {
              inputs,
              validActual,
              expectedCash,
              difference,
            } = reconciliation;

            return (
              <div
                className="daily-closing-currency-section"
                key={summary.currencyCode}
              >
                <div className="operations-report-divider" />

                <div className="daily-closing-total">
                  <strong>{summary.currencyCode}</strong>
                  <span>
                    {summary.transactionCount} transactions
                  </span>
                </div>

                <div className="daily-closing-fields">
                  <label className="inventory-field">
                    <span>
                      Opening cash ({summary.currencyCode})
                    </span>
                    <input
                      type="number"
                      min="0"
                      step="any"
                      value={inputs.openingCash}
                      disabled={Boolean(existingClosing)}
                      onChange={(event) =>
                        updateCashInput(
                          summary.currencyCode,
                          "openingCash",
                          event.target.value
                        )
                      }
                      placeholder="Enter opening cash"
                    />
                  </label>

                  <label className="inventory-field">
                    <span>
                      Cash paid out ({summary.currencyCode})
                    </span>
                    <input
                      type="number"
                      min="0"
                      step="any"
                      value={inputs.cashPaidOut}
                      disabled={Boolean(existingClosing)}
                      onChange={(event) =>
                        updateCashInput(
                          summary.currencyCode,
                          "cashPaidOut",
                          event.target.value
                        )
                      }
                      placeholder="Enter cash paid out"
                    />
                  </label>

                  <div className="daily-closing-calculation">
                    <span>Expected cash in drawer</span>
                    <strong>
                      {formatMoney(
                        expectedCash,
                        summary.currencyCode
                      )}
                    </strong>
                    <small>
                      Opening cash + cash received − cash paid out
                    </small>
                  </div>

                  <label className="inventory-field">
                    <span>
                      Actual cash counted ({summary.currencyCode})
                    </span>
                    <input
                      type="number"
                      min="0"
                      step="any"
                      value={inputs.actualCash}
                      disabled={Boolean(existingClosing)}
                      onChange={(event) =>
                        updateCashInput(
                          summary.currencyCode,
                          "actualCash",
                          event.target.value
                        )
                      }
                      placeholder="Enter physical cash count"
                    />
                  </label>

                  {validActual && (
                    <div
                      className={`daily-closing-difference ${
                        difference < 0
                          ? "is-short"
                          : difference > 0
                            ? "is-over"
                            : "is-balanced"
                      }`}
                    >
                      <span>
                        {difference < 0
                          ? "Cash shortage"
                          : difference > 0
                            ? "Cash surplus"
                            : "Cash balanced"}
                      </span>
                      <strong>
                        {difference > 0 ? "+" : ""}
                        {formatMoney(
                          difference,
                          summary.currencyCode
                        )}
                      </strong>
                    </div>
                  )}
                </div>
              </div>
            );
          })}

          {notice && (
            <p className="operations-notice" role="status">
              <CheckCircle2 size={15} /> {notice}
            </p>
          )}

          <button
            className="button button-primary"
            onClick={saveClosing}
            disabled={
              Boolean(existingClosing) ||
              unresolvedCurrencySales.length > 0 ||
              invalidAmountSales.length > 0 ||
              unknownPaymentMethodSales.length > 0 ||
              hasInvalidSummaryTotals ||
              !hasSalesSnapshot ||
              !hasClosingsSnapshot ||
              !shopCurrency
            }
          >
            <CheckCircle2 size={16} />
            {existingClosing
              ? "Already closed"
              : unresolvedCurrencySales.length > 0
                ? "Resolve sale currencies before closing"
                : invalidAmountSales.length > 0
                  ? "Resolve invalid sale amounts before closing"
                : unknownPaymentMethodSales.length > 0
                  ? "Resolve unknown payment methods before closing"
                : hasInvalidSummaryTotals
                  ? "Sales totals unavailable"
                : !hasSalesSnapshot || !hasClosingsSnapshot
                  ? "Storage data unavailable"
                : !shopCurrency
                  ? "Shop currency unavailable"
                  : "Save daily closing"}
          </button>
        </section>
      </div>

      {existingClosing && (
        <section className="surface-card daily-closing-card">
          <div className="card-kicker">SAVED RECONCILIATION</div>
          <h2>Closing summary</h2>

          {getClosingSummaries(existingClosing).map((summary, index) => (
            <div
              className="daily-closing-currency-section"
              key={(summary.currencyCode ?? "unknown") + "-" + index}
            >
              <div className="operations-report-divider" />

              <div className="daily-closing-total">
                <strong>{getCurrencyLabel(summary.currencyCode)}</strong>
                <strong>
                  {formatMoney(
                    summary.totalSales,
                    summary.currencyCode
                  )}
                </strong>
              </div>

              <div className="operations-report-payments">
                <div className="operations-report-payment">
                  <span>Opening cash</span>
                  <strong>
                    {formatMoney(
                      summary.openingCash,
                      summary.currencyCode
                    )}
                  </strong>
                </div>
                <div className="operations-report-payment">
                  <span>Cash received</span>
                  <strong>
                    {formatMoney(
                      summary.cashReceived,
                      summary.currencyCode
                    )}
                  </strong>
                </div>
                <div className="operations-report-payment">
                  <span>Cash paid out</span>
                  <strong>
                    {formatMoney(
                      summary.cashPaidOut,
                      summary.currencyCode
                    )}
                  </strong>
                </div>
                <div className="operations-report-payment">
                  <span>Expected cash</span>
                  <strong>
                    {formatMoney(
                      summary.expectedCash,
                      summary.currencyCode
                    )}
                  </strong>
                </div>
                <div className="operations-report-payment">
                  <span>Actual cash counted</span>
                  <strong>
                    {formatMoney(
                      summary.actualCash,
                      summary.currencyCode
                    )}
                  </strong>
                </div>
                <div className="operations-report-payment">
                  <span>Difference</span>
                  <strong>
                    {formatMoney(
                      summary.difference,
                      summary.currencyCode
                    )}
                  </strong>
                </div>
              </div>
            </div>
          ))}
        </section>
      )}

      <section className="surface-card daily-closing-card">
        <div className="inventory-card-heading">
          <div>
            <div className="card-kicker">CLOSING HISTORY</div>
            <h2>Previous closings</h2>
          </div>
          <span className="inventory-count">
            {hasClosingsSnapshot ? `${closings.length} saved` : "Unavailable"}
          </span>
        </div>

        {!hasClosingsSnapshot ? (
          <div className="inventory-empty">
            <History size={24} />
            <strong>Closing records unavailable</strong>
            <span>Browser closing data could not be read.</span>
          </div>
        ) : sortedClosings.length === 0 ? (
          <div className="inventory-empty">
            <History size={24} />
            <strong>No closing records yet</strong>
            <span>
              Your saved daily reconciliations will appear here.
            </span>
          </div>
        ) : (
          <div className="operations-record-list">
            {sortedClosings.map((closing) => {
              const summaries = getClosingSummaries(closing);

              return (
                <article
                  className="operations-record"
                  key={closing.id}
                >
                  <div className="operations-record-icon">
                    <ClipboardCheck size={17} />
                  </div>

                  <div className="operations-record-copy">
                    <strong>{formatDate(closing.date)}</strong>

                    {summaries.map((summary, index) => (
                      <span key={(summary.currencyCode ?? "unknown") + "-" + index}>
                        {getCurrencyLabel(summary.currencyCode)}:{" "}
                        {summary.transactionCount} transactions ·
                        Expected{" "}
                        {formatMoney(
                          summary.expectedCash,
                          summary.currencyCode
                        )}
                        {" · "}Actual{" "}
                        {formatMoney(
                          summary.actualCash,
                          summary.currencyCode
                        )}
                      </span>
                    ))}
                  </div>

                  <div className="operations-record-copy">
                    {summaries.map((summary, index) => (
                      <strong
                        className={`operations-amount ${
                          summary.difference < 0
                            ? "report-negative"
                            : ""
                        }`}
                        key={(summary.currencyCode ?? "unknown") + "-" + index}
                      >
                        {getCurrencyLabel(summary.currencyCode)}:{" "}
                        {summary.difference > 0 ? "+" : ""}
                        {formatMoney(
                          summary.difference,
                          summary.currencyCode
                        )}
                      </strong>
                    ))}
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </section>

      <div className="operations-note">
        <CheckCircle2 size={16} />
        <span>
          Daily closings are saved in this browser's local storage.
          Each currency is reconciled independently. Cash paid out is
          entered manually. Mobile money and bank transfers are
          excluded from physical cash reconciliation. These records
          are not yet cloud-synchronised.
        </span>
      </div>
    </section>
  );
}
