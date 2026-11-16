
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
  getRecordCurrency,
  getShopCurrency,
  type CurrencyCode,
} from "../utils/currency";

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
  currencyCode: CurrencyCode;
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

function readStorage<T>(key: string): T[] {
  try {
    const saved = localStorage.getItem(key);
    if (!saved) return [];

    const parsed: unknown = JSON.parse(saved);
    return Array.isArray(parsed) ? (parsed as T[]) : [];
  } catch {
    return [];
  }
}

function getLocalDateKey(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");

  return `${year}-${month}-${day}`;
}

function formatMoney(amount: number, currencyCode: CurrencyCode) {
  return formatCurrency(
    Number.isFinite(amount) ? amount : 0,
    currencyCode
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
    return closing.currencySummaries;
  }

  // Old closing records did not store a currency code.
  // Their amounts are treated as UGX without changing the saved data.
  return [
    {
      currencyCode: "UGX",
      openingCash: Number(closing.openingCash) || 0,
      cashReceived: Number(closing.cashReceived) || 0,
      cashPaidOut: Number(closing.cashPaidOut) || 0,
      expectedCash: Number(closing.expectedCash) || 0,
      actualCash: Number(closing.actualCash) || 0,
      difference: Number(closing.difference) || 0,
      totalSales: Number(closing.totalSales) || 0,
      transactionCount: Number(closing.transactionCount) || 0,
      paymentTotals: closing.paymentTotals || {},
    },
  ];
}

export default function DailyClosing() {
  const [sales, setSales] = useState<SaleRecord[]>(() =>
    readStorage<SaleRecord>(SALES_KEY)
  );

  const [closings, setClosings] = useState<ClosingRecord[]>(() =>
    readStorage<ClosingRecord>(CLOSINGS_KEY)
  );

  const [selectedDate, setSelectedDate] = useState(() =>
    getLocalDateKey(new Date())
  );

  const [cashInputs, setCashInputs] = useState<
    Record<string, CashInputs>
  >({});

  const [notice, setNotice] = useState("");

  useEffect(() => {
    const refreshData = () => {
      setSales(readStorage<SaleRecord>(SALES_KEY));
      setClosings(readStorage<ClosingRecord>(CLOSINGS_KEY));
    };

    window.addEventListener("focus", refreshData);
    window.addEventListener("storage", refreshData);

    return () => {
      window.removeEventListener("focus", refreshData);
      window.removeEventListener("storage", refreshData);
    };
  }, []);

  const dailySales = useMemo(() => {
    return sales.filter((sale) => {
      const date = new Date(sale.transactionDate);

      return (
        !Number.isNaN(date.getTime()) &&
        getLocalDateKey(date) === selectedDate
      );
    });
  }, [sales, selectedDate]);

  const currencySummaries = useMemo(() => {
    const grouped = new Map<string, CurrencySalesSummary>();

    dailySales.forEach((sale) => {
      const currencyCode = getRecordCurrency(sale.currencyCode);

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
      const amount = Number(sale.salePrice) || 0;
      const method = sale.paymentMethod || "Other";

      summary.paymentTotals[method] =
        (summary.paymentTotals[method] || 0) + amount;

      summary.totalSales += amount;
      summary.transactionCount += 1;

      if (method === "Cash") {
        summary.cashReceived += amount;
      } else {
        summary.nonCashReceived += amount;
      }
    });

    // Include the shop's operating currency even if there were no sales
    // in that currency, so the shop can still reconcile its cash drawer.
    const shopCurrency = getShopCurrency();

    if (!grouped.has(shopCurrency)) {
      grouped.set(shopCurrency, {
        currencyCode: shopCurrency,
        paymentTotals: {},
        totalSales: 0,
        cashReceived: 0,
        nonCashReceived: 0,
        transactionCount: 0,
      });
    }

    return Array.from(grouped.values()).sort((a, b) =>
      a.currencyCode.localeCompare(b.currencyCode)
    );
  }, [dailySales]);

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

    return {
      inputs,
      opening,
      paidOut,
      counted,
      validOpening,
      validPaidOut,
      validActual,
      expectedCash,
      difference,
    };
  };

  const saveClosing = () => {
    setNotice("");

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

    const latestClosings =
      readStorage<ClosingRecord>(CLOSINGS_KEY);

    if (
      latestClosings.some(
        (closing) => closing.date === selectedDate
      )
    ) {
      setClosings(latestClosings);
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
      const updated = [...latestClosings, record];

      localStorage.setItem(
        CLOSINGS_KEY,
        JSON.stringify(updated)
      );

      setClosings(updated);
      setNotice("Daily closing saved successfully.");
      setCashInputs({});
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

      <div className="daily-closing-grid">
        <section className="surface-card daily-closing-card">
          <div className="inventory-card-heading">
            <div>
              <div className="card-kicker">DAILY COLLECTIONS</div>
              <h2>Sales by currency</h2>
            </div>
            <Wallet size={19} />
          </div>

          {currencySummaries.map((summary) => (
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
                    <span>No sales recorded</span>
                    <strong>
                      {formatMoney(0, summary.currencyCode)}
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

          {currencySummaries.map((summary) => {
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
            disabled={Boolean(existingClosing)}
          >
            <CheckCircle2 size={16} />
            {existingClosing
              ? "Already closed"
              : "Save daily closing"}
          </button>
        </section>
      </div>

      {existingClosing && (
        <section className="surface-card daily-closing-card">
          <div className="card-kicker">SAVED RECONCILIATION</div>
          <h2>Closing summary</h2>

          {getClosingSummaries(existingClosing).map((summary) => (
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
            {closings.length} saved
          </span>
        </div>

        {sortedClosings.length === 0 ? (
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

                    {summaries.map((summary) => (
                      <span key={summary.currencyCode}>
                        {summary.currencyCode}:{" "}
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
                    {summaries.map((summary) => (
                      <strong
                        className={`operations-amount ${
                          summary.difference < 0
                            ? "report-negative"
                            : ""
                        }`}
                        key={summary.currencyCode}
                      >
                        {summary.currencyCode}:{" "}
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
