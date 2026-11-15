
import { useEffect, useMemo, useState } from "react";
import {
  Banknote,
  CalendarClock,
  CheckCircle2,
  ClipboardCheck,
  History,
  Wallet,
} from "lucide-react";

const SALES_KEY = "stockpilot-sales";
const CLOSINGS_KEY = "stockpilot-daily-closings";

type SaleRecord = {
  id: string;
  salePrice: number;
  paymentMethod: string;
  transactionDate: string;
};

type ClosingRecord = {
  id: string;
  date: string;
  openingCash: number;
  cashReceived: number;
  cashPaidOut: number;
  expectedCash: number;
  actualCash: number;
  difference: number;
  totalSales: number;
  transactionCount: number;
  paymentTotals: Record<string, number>;
  closedAt: string;
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

function formatMoney(amount: number) {
  return new Intl.NumberFormat("en-UG", {
    style: "currency",
    currency: "UGX",
    maximumFractionDigits: 0,
  }).format(Number.isFinite(amount) ? amount : 0);
}

function formatDate(date: string) {
  return new Date(`${date}T00:00:00`).toLocaleDateString("en-UG", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });
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

  const [openingCash, setOpeningCash] = useState("0");
  const [cashPaidOut, setCashPaidOut] = useState("0");
  const [actualCash, setActualCash] = useState("");
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

  const summary = useMemo(() => {
    const paymentTotals = dailySales.reduce<Record<string, number>>(
      (totals, sale) => {
        const method = sale.paymentMethod || "Other";
        totals[method] =
          (totals[method] || 0) + (Number(sale.salePrice) || 0);

        return totals;
      },
      {}
    );

    const totalSales = dailySales.reduce(
      (total, sale) => total + (Number(sale.salePrice) || 0),
      0
    );

    const cashReceived = paymentTotals["Cash"] || 0;

    const nonCashReceived = Object.entries(paymentTotals)
      .filter(([method]) => method !== "Cash")
      .reduce((total, [, amount]) => total + amount, 0);

    return {
      paymentTotals,
      totalSales,
      cashReceived,
      nonCashReceived,
      transactionCount: dailySales.length,
    };
  }, [dailySales]);

  const opening = Number(openingCash);
  const paidOut = Number(cashPaidOut);
  const counted = Number(actualCash);

  const validOpening =
    openingCash.trim() !== "" &&
    Number.isFinite(opening) &&
    opening >= 0;

  const validPaidOut =
    cashPaidOut.trim() !== "" &&
    Number.isFinite(paidOut) &&
    paidOut >= 0;

  const expectedCash =
    (validOpening ? opening : 0) +
    summary.cashReceived -
    (validPaidOut ? paidOut : 0);

  const validActual =
    actualCash.trim() !== "" &&
    Number.isFinite(counted) &&
    counted >= 0;

  const difference = validActual ? counted - expectedCash : 0;

  const existingClosing = closings.find(
    (closing) => closing.date === selectedDate
  );

  const sortedClosings = [...closings].sort((a, b) =>
    b.date.localeCompare(a.date)
  );

  const saveClosing = () => {
    setNotice("");

    if (!validOpening || !validPaidOut) {
      setNotice("Enter valid, non-negative opening cash and cash paid out.");
      return;
    }

    if (!validActual) {
      setNotice("Enter the actual cash counted before saving.");
      return;
    }

    if (expectedCash < 0) {
      setNotice("Expected cash cannot be negative. Check your entries.");
      return;
    }

    const latestClosings = readStorage<ClosingRecord>(CLOSINGS_KEY);

    if (latestClosings.some((closing) => closing.date === selectedDate)) {
      setClosings(latestClosings);
      setNotice("A closing already exists for this date.");
      return;
    }

    const record: ClosingRecord = {
      id: `CLOSE-${selectedDate}`,
      date: selectedDate,
      openingCash: opening,
      cashReceived: summary.cashReceived,
      cashPaidOut: paidOut,
      expectedCash,
      actualCash: counted,
      difference,
      totalSales: summary.totalSales,
      transactionCount: summary.transactionCount,
      paymentTotals: summary.paymentTotals,
      closedAt: new Date().toISOString(),
    };

    try {
      const updated = [...latestClosings, record];

      localStorage.setItem(CLOSINGS_KEY, JSON.stringify(updated));
      setClosings(updated);
      setNotice("Daily closing saved successfully.");
      setActualCash("");
    } catch {
      setNotice("Unable to save closing. Check available browser storage.");
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
            Reconcile daily sales, payment methods and physical cash.
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
              {new Date(existingClosing.closedAt).toLocaleString("en-UG")}.
              A second closing cannot be created for this date.
            </span>
          </div>
        </div>
      )}

      <div className="daily-closing-metrics">
        <article className="surface-card operations-stat">
          <div className="operations-report-icon">
            <Banknote size={19} />
          </div>
          <span>Total sales</span>
          <strong>{formatMoney(summary.totalSales)}</strong>
          <small>{summary.transactionCount} transactions</small>
        </article>

        <article className="surface-card operations-stat">
          <div className="operations-report-icon">
            <Wallet size={19} />
          </div>
          <span>Cash received</span>
          <strong>{formatMoney(summary.cashReceived)}</strong>
          <small>Physical cash payments only</small>
        </article>

        <article className="surface-card operations-stat">
          <div className="operations-report-icon">
            <Banknote size={19} />
          </div>
          <span>Non-cash payments</span>
          <strong>{formatMoney(summary.nonCashReceived)}</strong>
          <small>Mobile money and bank transfers</small>
        </article>
      </div>

      <div className="daily-closing-grid">
        <section className="surface-card daily-closing-card">
          <div className="inventory-card-heading">
            <div>
              <div className="card-kicker">PAYMENT BREAKDOWN</div>
              <h2>Today's collections</h2>
            </div>
            <Wallet size={19} />
          </div>

          {Object.keys(summary.paymentTotals).length === 0 ? (
            <div className="inventory-empty">
              <Banknote size={24} />
              <strong>No sales recorded</strong>
              <span>Sales for the selected date will appear here.</span>
            </div>
          ) : (
            <div className="operations-report-payments">
              {Object.entries(summary.paymentTotals).map(
                ([method, amount]) => (
                  <div className="operations-report-payment" key={method}>
                    <span>{method}</span>
                    <strong>{formatMoney(amount)}</strong>
                  </div>
                )
              )}
            </div>
          )}

          <div className="operations-report-divider" />

          <div className="daily-closing-total">
            <span>Total collected</span>
            <strong>{formatMoney(summary.totalSales)}</strong>
          </div>
        </section>

        <section className="surface-card daily-closing-card">
          <div className="inventory-card-heading">
            <div>
              <div className="card-kicker">CASH RECONCILIATION</div>
              <h2>Count your cash</h2>
            </div>
            <ClipboardCheck size={19} />
          </div>

          <div className="daily-closing-fields">
            <label className="inventory-field">
              <span>Opening cash (UGX)</span>
              <input
                type="number"
                min="0"
                value={openingCash}
                disabled={Boolean(existingClosing)}
                onChange={(event) => setOpeningCash(event.target.value)}
                placeholder="e.g. 100000"
              />
            </label>

            <label className="inventory-field">
              <span>Cash paid out (UGX)</span>
              <input
                type="number"
                min="0"
                value={cashPaidOut}
                disabled={Boolean(existingClosing)}
                onChange={(event) => setCashPaidOut(event.target.value)}
                placeholder="e.g. 20000"
              />
            </label>

            <div className="daily-closing-calculation">
              <span>Expected cash in drawer</span>
              <strong>{formatMoney(expectedCash)}</strong>
              <small>
                Opening cash + cash received − cash paid out
              </small>
            </div>

            <label className="inventory-field">
              <span>Actual cash counted (UGX)</span>
              <input
                type="number"
                min="0"
                value={actualCash}
                disabled={Boolean(existingClosing)}
                onChange={(event) => setActualCash(event.target.value)}
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
                  {formatMoney(difference)}
                </strong>
              </div>
            )}

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
              {existingClosing ? "Already closed" : "Save daily closing"}
            </button>
          </div>
        </section>
      </div>

      {existingClosing && (
        <section className="surface-card daily-closing-card">
          <div className="card-kicker">SAVED RECONCILIATION</div>
          <h2>Closing summary</h2>

          <div className="operations-report-payments">
            <div className="operations-report-payment">
              <span>Opening cash</span>
              <strong>{formatMoney(existingClosing.openingCash)}</strong>
            </div>
            <div className="operations-report-payment">
              <span>Cash received</span>
              <strong>{formatMoney(existingClosing.cashReceived)}</strong>
            </div>
            <div className="operations-report-payment">
              <span>Cash paid out</span>
              <strong>{formatMoney(existingClosing.cashPaidOut)}</strong>
            </div>
            <div className="operations-report-payment">
              <span>Expected cash</span>
              <strong>{formatMoney(existingClosing.expectedCash)}</strong>
            </div>
            <div className="operations-report-payment">
              <span>Actual cash counted</span>
              <strong>{formatMoney(existingClosing.actualCash)}</strong>
            </div>
            <div className="operations-report-payment">
              <span>Difference</span>
              <strong>{formatMoney(existingClosing.difference)}</strong>
            </div>
          </div>
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
            <span>Your saved daily reconciliations will appear here.</span>
          </div>
        ) : (
          <div className="operations-record-list">
            {sortedClosings.map((closing) => (
              <article className="operations-record" key={closing.id}>
                <div className="operations-record-icon">
                  <ClipboardCheck size={17} />
                </div>

                <div className="operations-record-copy">
                  <strong>{formatDate(closing.date)}</strong>
                  <span>
                    {closing.transactionCount} transactions · Expected{" "}
                    {formatMoney(closing.expectedCash)}
                  </span>
                  <span>
                    Actual counted: {formatMoney(closing.actualCash)}
                  </span>
                </div>

                <strong
                  className={`operations-amount ${
                    closing.difference < 0 ? "report-negative" : ""
                  }`}
                >
                  {closing.difference > 0 ? "+" : ""}
                  {formatMoney(closing.difference)}
                </strong>
              </article>
            ))}
          </div>
        )}
      </section>

      <div className="operations-note">
        <CheckCircle2 size={16} />
        <span>
          Daily closings are saved in this browser's local storage. Cash
          paid out is entered manually. Mobile money and bank transfers are
          excluded from physical cash reconciliation. These records are not
          yet cloud-synchronised.
        </span>
      </div>
    </section>
  );
}
