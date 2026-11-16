
import { useEffect, useMemo, useState } from "react";
import type { ChangeEvent } from "react";
import {
  ArrowDownLeft,
  ArrowUpRight,
  Banknote,
  CalendarClock,
  CheckCircle2,
  Plus,
  Receipt,
  Wallet,
} from "lucide-react";

import {
  CURRENCY_OPTIONS,
  convertToSnapshotCurrency,
  formatCurrency,
  getRecordCurrency,
  getSavedExchangeRateSnapshot,
  getShopCurrency,
  refreshExchangeRateSnapshot,
  type CurrencyCode,
  type ExchangeRateSnapshot,
} from "../utils/currency";

type CreditType = "Payable" | "Receivable";

type CreditPayment = {
  id: string;
  amount: number;
  date: string;
};

type CreditRecord = {
  id: string;
  type: CreditType;
  party: string;
  contact: string;
  reference: string;
  description: string;
  originalAmount: number;
  currencyCode?: CurrencyCode;
  dueDate: string;
  createdAt: string;
  payments: CreditPayment[];
  purchaseId?: string;
};

type ConvertedTotal = {
  amount: number;
  missingCurrencies: CurrencyCode[];
};

const STORAGE_KEY = "stockpilot-credit-records";

// Format numbers with thousands separators while preserving decimals.
function formatAmountInput(value: string): string {
  const cleaned = value.replace(/,/g, "").replace(/[^\d.]/g, "");
  const decimalIndex = cleaned.indexOf(".");

  const integerPart =
    decimalIndex === -1 ? cleaned : cleaned.slice(0, decimalIndex);

  const decimalPart =
    decimalIndex === -1 ? "" : cleaned.slice(decimalIndex + 1).replace(/\./g, "");

  const formattedInteger = integerPart.replace(
    /\B(?=(\d{3})+(?!\d))/g,
    ","
  );

  return decimalIndex === -1
    ? formattedInteger
    : `${formattedInteger}.${decimalPart}`;
}

// Remove display commas before converting the value into a number.
function parseAmountInput(value: string): number {
  return Number(value.replace(/,/g, ""));
}

// Update the displayed value while keeping the cursor in the correct position.
function handleFormattedAmountChange(
  event: ChangeEvent<HTMLInputElement>,
  setter: (value: string) => void
) {
  const input = event.currentTarget;
  const rawValue = input.value;
  const originalCaret = input.selectionStart ?? rawValue.length;

  const charactersBeforeCaret = rawValue
    .slice(0, originalCaret)
    .replace(/[^\d]/g, "").length;

  const formattedValue = formatAmountInput(rawValue);

  setter(formattedValue);

  requestAnimationFrame(() => {
    let position = 0;
    let charactersFound = 0;

    while (
      position < formattedValue.length &&
      charactersFound < charactersBeforeCaret
    ) {
      if (/\d/.test(formattedValue[position])) {
        charactersFound++;
      }

      position++;
    }

    // Keep the cursor after a comma when the separator is at this position.
    while (formattedValue[position] === ",") {
      position++;
    }

    input.setSelectionRange(position, position);
  });
}

function readRecords(): CreditRecord[] {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (!saved) return [];

    const parsed: unknown = JSON.parse(saved);

    if (!Array.isArray(parsed)) return [];

    return parsed.map((record) => ({
      ...record,
      payments: Array.isArray(record.payments) ? record.payments : [],
    })) as CreditRecord[];
  } catch {
    return [];
  }
}

function getCurrency(record: CreditRecord): CurrencyCode {
  return getRecordCurrency(record.currencyCode);
}

function getPaidAmount(record: CreditRecord) {
  return record.payments.reduce(
    (total, payment) => total + (Number(payment.amount) || 0),
    0
  );
}

function getBalance(record: CreditRecord) {
  return Math.max(0, record.originalAmount - getPaidAmount(record));
}

function getStatus(record: CreditRecord) {
  const balance = getBalance(record);

  if (balance <= 0) return "Paid";

  if (record.dueDate && record.dueDate < getToday()) return "Overdue";

  if (getPaidAmount(record) > 0) return "Part-paid";

  return "Outstanding";
}

function getToday() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function formatDate(date: string) {
  if (!date) return "No due date";

  return new Date(`${date}T00:00:00`).toLocaleDateString("en-UG", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

function getConvertedTotal(
  records: CreditRecord[],
  type: CreditType,
  baseCurrency: CurrencyCode,
  snapshot: ExchangeRateSnapshot | null
): ConvertedTotal {
  let total = 0;
  const missingCurrencies = new Set<CurrencyCode>();

  records
    .filter((record) => record.type === type)
    .forEach((record) => {
      const balance = getBalance(record);

      if (balance <= 0) return;

      const recordCurrency = getCurrency(record);

      if (recordCurrency === baseCurrency) {
        total += balance;
        return;
      }

      if (!snapshot || snapshot.baseCode !== baseCurrency) {
        missingCurrencies.add(recordCurrency);
        return;
      }

      const converted = convertToSnapshotCurrency(
        balance,
        recordCurrency,
        snapshot
      );

      if (converted === null) {
        missingCurrencies.add(recordCurrency);
        return;
      }

      total += converted;
    });

  return {
    amount: total,
    missingCurrencies: Array.from(missingCurrencies).sort(),
  };
}

export default function SupplierCredit() {
  const [records, setRecords] = useState<CreditRecord[]>(readRecords);
  const [activeTab, setActiveTab] = useState<"All" | CreditType>("All");
  const [showForm, setShowForm] = useState(false);
  const [notice, setNotice] = useState("");

  const [shopCurrency] = useState<CurrencyCode>(() => getShopCurrency());

  const [exchangeSnapshot, setExchangeSnapshot] =
    useState<ExchangeRateSnapshot | null>(() =>
      getSavedExchangeRateSnapshot(getShopCurrency())
    );

  const [rateMessage, setRateMessage] = useState(
    "Loading the latest exchange rates..."
  );

  const [type, setType] = useState<CreditType>("Payable");
  const [party, setParty] = useState("");
  const [contact, setContact] = useState("");
  const [reference, setReference] = useState("");
  const [description, setDescription] = useState("");
  const [amount, setAmount] = useState("");
  const [currencyCode, setCurrencyCode] = useState<CurrencyCode>(
    getShopCurrency()
  );
  const [dueDate, setDueDate] = useState("");

  const [paymentRecordId, setPaymentRecordId] = useState("");
  const [paymentAmount, setPaymentAmount] = useState("");
  const [paymentDate, setPaymentDate] = useState(getToday());

  useEffect(() => {
    const refresh = () => setRecords(readRecords());

    window.addEventListener("focus", refresh);
    window.addEventListener("storage", refresh);

    return () => {
      window.removeEventListener("focus", refresh);
      window.removeEventListener("storage", refresh);
    };
  }, []);

  useEffect(() => {
    let cancelled = false;

    const savedSnapshot = getSavedExchangeRateSnapshot(shopCurrency);

    if (savedSnapshot) {
      setExchangeSnapshot(savedSnapshot);
      setRateMessage("Saved exchange rates available. Refreshing rates...");
    }

    const fetchRates = async () => {
      try {
        const freshSnapshot =
          await refreshExchangeRateSnapshot(shopCurrency);

        if (cancelled) return;

        setExchangeSnapshot(freshSnapshot);

        const updatedDate = new Date(
          freshSnapshot.lastUpdatedAt
        ).toLocaleString();

        setRateMessage(
          `Exchange rates refreshed. Provider's last update: ${updatedDate}.`
        );
      } catch (error) {
        if (cancelled) return;

        console.error("Could not refresh exchange rates:", error);

        if (savedSnapshot) {
          setExchangeSnapshot(savedSnapshot);
          setRateMessage(
            "Could not refresh exchange rates. Using the last successfully saved rates."
          );
        } else {
          setRateMessage(
            "Exchange rates are unavailable. Only balances already in the shop currency can be included in the summary."
          );
        }
      }
    };

    void fetchRates();

    return () => {
      cancelled = true;
    };
  }, [shopCurrency]);

  const saveRecords = (updated: CreditRecord[]) => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(updated));
      setRecords(updated);
    } catch {
      setNotice(
        "Could not save credit records. Check available browser storage."
      );
    }
  };

  const totals = useMemo(() => {
    return {
      payables: getConvertedTotal(
        records,
        "Payable",
        shopCurrency,
        exchangeSnapshot
      ),
      receivables: getConvertedTotal(
        records,
        "Receivable",
        shopCurrency,
        exchangeSnapshot
      ),
      overdue: records.filter(
        (record) => getStatus(record) === "Overdue"
      ).length,
      open: records.filter((record) => getBalance(record) > 0).length,
    };
  }, [records, shopCurrency, exchangeSnapshot]);

  const visibleRecords = useMemo(() => {
    return records
      .filter((record) => activeTab === "All" || record.type === activeTab)
      .sort(
        (a, b) =>
          new Date(b.createdAt).getTime() -
          new Date(a.createdAt).getTime()
      );
  }, [records, activeTab]);

  const addRecord = () => {
    const parsedAmount = parseAmountInput(amount);

    if (!party.trim()) {
      setNotice("Enter the supplier or customer name.");
      return;
    }

    if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
      setNotice("Enter a valid amount greater than zero.");
      return;
    }

    const record: CreditRecord = {
      id: `CREDIT-${Date.now()}`,
      type,
      party: party.trim(),
      contact: contact.trim(),
      reference: reference.trim(),
      description: description.trim(),
      originalAmount: parsedAmount,
      currencyCode,
      dueDate,
      createdAt: new Date().toISOString(),
      payments: [],
    };

    saveRecords([record, ...records]);

    setParty("");
    setContact("");
    setReference("");
    setDescription("");
    setAmount("");
    setDueDate("");
    setCurrencyCode(getShopCurrency());
    setShowForm(false);
    setNotice("Credit record saved successfully.");
  };

  const addPayment = (record: CreditRecord) => {
    const parsedAmount = parseAmountInput(paymentAmount);
    const balance = getBalance(record);
    const recordCurrency = getCurrency(record);

    if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
      setNotice("Enter a valid payment amount greater than zero.");
      return;
    }

    if (parsedAmount > balance) {
      setNotice(
        `Payment exceeds the outstanding balance of ${formatCurrency(
          balance,
          recordCurrency
        )}.`
      );
      return;
    }

    const payment: CreditPayment = {
      id: `PAY-${Date.now()}`,
      amount: parsedAmount,
      date: paymentDate || getToday(),
    };

    const updated = records.map((item) =>
      item.id === record.id
        ? { ...item, payments: [...item.payments, payment] }
        : item
    );

    saveRecords(updated);
    setPaymentRecordId("");
    setPaymentAmount("");
    setPaymentDate(getToday());
    setNotice("Payment recorded and balance updated.");
  };

  return (
    <section className="operations-page page-content credit-page">
      <div className="eyebrow">
        <span className="eyebrow-line" /> CREDIT MANAGEMENT
      </div>

      <div className="operations-heading">
        <div>
          <h1>Suppliers & credit</h1>
          <p className="page-subtitle">
            Track supplier balances, customer debts and every payment made or
            received.
          </p>
        </div>
        <div className="operations-heading-icon">
          <Wallet size={22} />
        </div>
      </div>

      <div className="credit-summary-grid">
        <article className="surface-card credit-summary-card">
          <div className="credit-summary-icon payable">
            <ArrowUpRight size={19} />
          </div>
          <span>Supplier payables</span>
          <strong>
            {formatCurrency(totals.payables.amount, shopCurrency)}
          </strong>
          <small>
            Combined outstanding balance in {shopCurrency}
          </small>
          {totals.payables.missingCurrencies.length > 0 && (
            <small>
              Not converted: {totals.payables.missingCurrencies.join(", ")}
            </small>
          )}
        </article>

        <article className="surface-card credit-summary-card">
          <div className="credit-summary-icon receivable">
            <ArrowDownLeft size={19} />
          </div>
          <span>Customer receivables</span>
          <strong>
            {formatCurrency(totals.receivables.amount, shopCurrency)}
          </strong>
          <small>
            Combined outstanding balance in {shopCurrency}
          </small>
          {totals.receivables.missingCurrencies.length > 0 && (
            <small>
              Not converted: {totals.receivables.missingCurrencies.join(", ")}
            </small>
          )}
        </article>

        <article className="surface-card credit-summary-card">
          <div className="credit-summary-icon">
            <Receipt size={19} />
          </div>
          <span>Open credit records</span>
          <strong>{totals.open}</strong>
          <small>Records with unpaid balances</small>
        </article>

        <article className="surface-card credit-summary-card">
          <div className="credit-summary-icon overdue">
            <CalendarClock size={19} />
          </div>
          <span>Overdue records</span>
          <strong>{totals.overdue}</strong>
          <small>Past due date with a balance</small>
        </article>
      </div>

      <div className="operations-note" role="status">
        <Banknote size={16} />
        <span>
          {rateMessage} Exchange rates provided by{" "}
          <a
            href="https://www.exchangerate-api.com"
            target="_blank"
            rel="noreferrer"
          >
            ExchangeRate-API
          </a>
          . These are reference rates, not guaranteed settlement rates.
        </span>
      </div>

      <section className="surface-card credit-workspace">
        <div className="inventory-card-heading">
          <div>
            <div className="card-kicker">CREDIT LEDGER</div>
            <h2>Outstanding accounts</h2>
          </div>

          <button
            className="button button-primary"
            onClick={() => {
              setShowForm((current) => !current);
              setNotice("");
            }}
          >
            <Plus size={16} />
            New credit record
          </button>
        </div>

        {showForm && (
          <div className="credit-entry-form">
            <div className="credit-form-type">
              <button
                className={type === "Payable" ? "is-active" : ""}
                onClick={() => setType("Payable")}
                type="button"
              >
                Supplier payable
              </button>
              <button
                className={type === "Receivable" ? "is-active" : ""}
                onClick={() => setType("Receivable")}
                type="button"
              >
                Customer receivable
              </button>
            </div>

            <div className="credit-form-grid">
              <label className="inventory-field">
                <span>
                  {type === "Payable" ? "Supplier name *" : "Customer name *"}
                </span>
                <input
                  value={party}
                  onChange={(event) => setParty(event.target.value)}
                  placeholder="Enter name"
                />
              </label>

              <label className="inventory-field">
                <span>Contact number</span>
                <input
                  value={contact}
                  onChange={(event) => setContact(event.target.value)}
                  placeholder="+256..."
                />
              </label>

              <label className="inventory-field">
                <span>Invoice / sale reference</span>
                <input
                  value={reference}
                  onChange={(event) => setReference(event.target.value)}
                  placeholder="Invoice or transaction ID"
                />
              </label>

              <label className="inventory-field">
                <span>Currency *</span>
                <select
                  value={currencyCode}
                  onChange={(event) =>
                    setCurrencyCode(event.target.value as CurrencyCode)
                  }
                >
                  {CURRENCY_OPTIONS.map((currency) => (
                    <option key={currency.code} value={currency.code}>
                      {currency.code}
                    </option>
                  ))}
                </select>
              </label>

              <label className="inventory-field">
                <span>Original amount ({currencyCode}) *</span>
                <input
                  type="text"
                  inputMode="decimal"
                  value={amount}
                  onChange={(event) =>
                    handleFormattedAmountChange(event, setAmount)
                  }
                  placeholder="Enter amount"
                />
              </label>

              <label className="inventory-field">
                <span>Due date</span>
                <input
                  type="date"
                  value={dueDate}
                  onChange={(event) => setDueDate(event.target.value)}
                />
              </label>

              <label className="inventory-field credit-description-field">
                <span>Description</span>
                <input
                  value={description}
                  onChange={(event) => setDescription(event.target.value)}
                  placeholder="e.g. Samsung stock invoice"
                />
              </label>
            </div>

            <div className="credit-form-actions">
              <button
                className="button button-secondary"
                onClick={() => setShowForm(false)}
                type="button"
              >
                Cancel
              </button>
              <button
                className="button button-primary"
                onClick={addRecord}
                type="button"
              >
                <Plus size={16} /> Save credit record
              </button>
            </div>
          </div>
        )}

        <div className="credit-tabs">
          {(["All", "Payable", "Receivable"] as const).map((tab) => (
            <button
              key={tab}
              className={activeTab === tab ? "is-active" : ""}
              onClick={() => setActiveTab(tab)}
            >
              {tab === "All"
                ? "All accounts"
                : tab === "Payable"
                  ? "Supplier payables"
                  : "Customer receivables"}
            </button>
          ))}
        </div>

        {visibleRecords.length === 0 ? (
          <div className="inventory-empty">
            <Banknote size={26} />
            <strong>No credit records yet</strong>
            <span>
              Create a supplier payable or customer receivable to begin.
            </span>
          </div>
        ) : (
          <div className="credit-record-list">
            {visibleRecords.map((record) => {
              const paid = getPaidAmount(record);
              const balance = getBalance(record);
              const status = getStatus(record);
              const paymentOpen = paymentRecordId === record.id;
              const recordCurrency = getCurrency(record);

              return (
                <article className="credit-record" key={record.id}>
                  <div className="credit-record-top">
                    <div className="credit-record-party">
                      <div
                        className={`credit-record-icon ${record.type.toLowerCase()}`}
                      >
                        {record.type === "Payable" ? (
                          <ArrowUpRight size={18} />
                        ) : (
                          <ArrowDownLeft size={18} />
                        )}
                      </div>
                      <div>
                        <strong>{record.party}</strong>
                        <span>
                          {record.type === "Payable"
                            ? "Supplier payable"
                            : "Customer receivable"}
                        </span>
                      </div>
                    </div>
                    <span
                      className={`credit-status ${status
                        .toLowerCase()
                        .replace("-", "")}`}
                    >
                      {status}
                    </span>
                  </div>

                  <div className="credit-record-details">
                    {record.reference && (
                      <span>Reference: {record.reference}</span>
                    )}
                    {record.description && <span>{record.description}</span>}
                    {record.contact && <span>{record.contact}</span>}
                    <span>Currency: {recordCurrency}</span>
                    <span>Due: {formatDate(record.dueDate)}</span>
                  </div>

                  <div className="credit-amount-grid">
                    <div>
                      <span>Original amount</span>
                      <strong>
                        {formatCurrency(record.originalAmount, recordCurrency)}
                      </strong>
                    </div>
                    <div>
                      <span>Paid</span>
                      <strong>
                        {formatCurrency(paid, recordCurrency)}
                      </strong>
                    </div>
                    <div>
                      <span>Remaining balance</span>
                      <strong className="credit-balance">
                        {formatCurrency(balance, recordCurrency)}
                      </strong>
                    </div>
                  </div>

                  {record.payments.length > 0 && (
                    <div className="credit-payment-history">
                      <strong>Payment history</strong>
                      {record.payments.map((payment) => (
                        <div key={payment.id}>
                          <span>{formatDate(payment.date)}</span>
                          <strong>
                            {formatCurrency(payment.amount, recordCurrency)}
                          </strong>
                        </div>
                      ))}
                    </div>
                  )}

                  {balance > 0 && (
                    <div className="credit-payment-actions">
                      {paymentOpen ? (
                        <div className="credit-payment-form">
                          <label className="inventory-field">
                            <span>Payment amount ({recordCurrency})</span>
                            <input
                              type="text"
                              inputMode="decimal"
                              value={paymentAmount}
                              onChange={(event) =>
                                handleFormattedAmountChange(
                                  event,
                                  setPaymentAmount
                                )
                              }
                              placeholder={`Up to ${balance}`}
                            />
                          </label>
                          <label className="inventory-field">
                            <span>Payment date</span>
                            <input
                              type="date"
                              value={paymentDate}
                              onChange={(event) =>
                                setPaymentDate(event.target.value)
                              }
                            />
                          </label>
                          <button
                            className="button button-primary"
                            onClick={() => addPayment(record)}
                          >
                            <CheckCircle2 size={15} /> Record payment
                          </button>
                          <button
                            className="button button-secondary"
                            onClick={() => setPaymentRecordId("")}
                          >
                            Cancel
                          </button>
                        </div>
                      ) : (
                        <button
                          className="button button-secondary"
                          onClick={() => {
                            setPaymentRecordId(record.id);
                            setPaymentAmount("");
                            setNotice("");
                          }}
                        >
                          <Plus size={15} /> Record payment
                        </button>
                      )}
                    </div>
                  )}
                </article>
              );
            })}
          </div>
        )}

        {notice && (
          <p className="operations-notice" role="status">
            <CheckCircle2 size={15} /> {notice}
          </p>
        )}
      </section>

      <div className="operations-note">
        <Banknote size={16} />
        <span>
          Credit records and payments are stored locally in this browser.
          Individual ledger balances remain in their original currencies.
          Summary totals use the latest successfully saved exchange-rate
          snapshot. They do not automatically create sales, change inventory,
          or update cash received in Reports and Daily Closing. Cloud sync,
          staff permissions and secure backups are not implemented yet.
        </span>
      </div>
    </section>
  );
}
