
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
  EXCHANGE_RATES_STORAGE_KEY,
  formatCurrency,
  getKnownNonNegativeAmount,
  getKnownOutstandingBalance,
  getKnownRecordCurrency,
  getSavedExchangeRateSnapshot,
  getShopCurrency,
  isExchangeRateSnapshotExpired,
  SETTINGS_STORAGE_KEY,
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
  unresolvedCurrencyRecords: number;
  invalidAmountRecords: number;
};

const STORAGE_KEY = "stockpilot-credit-records";

type CreditStorageSnapshot = {
  raw: string | null;
  records: CreditRecord[];
};

type CreditStorageReadState = {
  records: CreditRecord[];
  hasValidSnapshot: boolean;
  readError: boolean;
};

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

function isCreditPayment(value: unknown): value is CreditPayment {
  if (
    value === null ||
    typeof value !== "object" ||
    Array.isArray(value)
  ) {
    return false;
  }

  const payment = value as Record<string, unknown>;
  return (
    typeof payment.id === "string" &&
    typeof payment.amount === "number" &&
    Number.isFinite(payment.amount) &&
    payment.amount >= 0 &&
    typeof payment.date === "string"
  );
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

function readRecordSnapshot(): CreditStorageSnapshot | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw === null) return { raw, records: [] };

    const parsed: unknown = JSON.parse(raw);

    if (!Array.isArray(parsed)) return null;

    const records: CreditRecord[] = [];
    for (const value of parsed) {
      if (
        value === null ||
        typeof value !== "object" ||
        Array.isArray(value)
      ) {
        return null;
      }

      const record = value as Record<string, unknown>;
      const hasPayments = Object.prototype.hasOwnProperty.call(
        record,
        "payments"
      );

      if (
        hasPayments &&
        (!Array.isArray(record.payments) ||
          !record.payments.every(isCreditPayment))
      ) {
        return null;
      }

      records.push({
        ...record,
        // Older records predate the payments field; only a missing field is
        // normalized. A present but invalid value makes the ledger unreadable.
        payments: hasPayments ? (record.payments as CreditPayment[]) : [],
      } as CreditRecord);
    }

    return {
      raw,
      records,
    };
  } catch {
    return null;
  }
}

function toCreditStorageReadState(
  snapshot: CreditStorageSnapshot | null
): CreditStorageReadState {
  return {
    records: snapshot?.records ?? [],
    hasValidSnapshot: snapshot !== null,
    readError: snapshot === null,
  };
}

function getCurrency(record: CreditRecord): CurrencyCode | null {
  return getKnownRecordCurrency(record.currencyCode);
}

function getPaidAmount(record: CreditRecord) {
  return record.payments.reduce<number | null>((total, payment) => {
    if (total === null) return null;
    const updated = total + payment.amount;
    return Number.isFinite(updated) ? updated : null;
  }, 0);
}

function getBalance(record: CreditRecord): number | null {
  const paidAmount = getPaidAmount(record);
  return getKnownOutstandingBalance(record.originalAmount, paidAmount);
}

function getStatus(record: CreditRecord) {
  const balance = getBalance(record);

  if (balance === null) return "Invalid amount";
  if (balance <= 0) return "Paid";

  if (record.dueDate && record.dueDate < getToday()) return "Overdue";

  const paidAmount = getPaidAmount(record);
  if (paidAmount !== null && paidAmount > 0) return "Part-paid";

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
  let unresolvedCurrencyRecords = 0;
  let invalidAmountRecords = 0;
  const missingCurrencies = new Set<CurrencyCode>();

  records
    .filter((record) => record.type === type)
    .forEach((record) => {
      const balance = getBalance(record);

      if (balance === null) {
        invalidAmountRecords += 1;
        return;
      }
      if (balance <= 0) return;

      const recordCurrency = getCurrency(record);
      if (!recordCurrency) {
        unresolvedCurrencyRecords += 1;
        return;
      }

      if (recordCurrency === baseCurrency) {
        const updated = total + balance;
        if (!Number.isFinite(updated)) {
          invalidAmountRecords += 1;
          return;
        }
        total = updated;
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

      const updated = total + converted;
      if (!Number.isFinite(updated)) {
        invalidAmountRecords += 1;
        return;
      }
      total = updated;
    });

  return {
    amount: total,
    missingCurrencies: Array.from(missingCurrencies).sort(),
    unresolvedCurrencyRecords,
    invalidAmountRecords,
  };
}

function countUnresolvedBalances(
  records: CreditRecord[],
  type: CreditType
): number {
  return records.filter(
    (record) => {
      const balance = getBalance(record);
      return (
        record.type === type &&
        balance !== null &&
        balance > 0 &&
        !getCurrency(record)
      );
    }
  ).length;
}

function countInvalidBalances(
  records: CreditRecord[],
  type: CreditType
): number {
  return records.filter(
    (record) => record.type === type && getBalance(record) === null
  ).length;
}

export default function SupplierCredit() {
  const [recordReadState, setRecordReadState] = useState(() =>
    toCreditStorageReadState(readRecordSnapshot())
  );
  const records = recordReadState.records;
  const [activeTab, setActiveTab] = useState<"All" | CreditType>("All");
  const [showForm, setShowForm] = useState(false);
  const [notice, setNotice] = useState("");

  const [shopCurrency, setShopCurrency] = useState<CurrencyCode | null>(
    () => getShopCurrency()
  );

  const [exchangeSnapshot, setExchangeSnapshot] =
    useState<ExchangeRateSnapshot | null>(() =>
      (() => {
        const initialShopCurrency = getShopCurrency();
        return initialShopCurrency
          ? getSavedExchangeRateSnapshot(initialShopCurrency)
          : null;
      })()
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
    () => getShopCurrency() ?? ""
  );
  const [creditCurrencyManuallySelected, setCreditCurrencyManuallySelected] =
    useState(false);
  const [creditCurrencyNeedsReview, setCreditCurrencyNeedsReview] =
    useState(false);
  const [currencySettingsNotice, setCurrencySettingsNotice] = useState(() =>
    getShopCurrency()
      ? ""
      : "Shop currency settings are invalid or unavailable. Select this record's currency explicitly and review Workspace settings."
  );
  const [dueDate, setDueDate] = useState("");

  const [paymentRecordId, setPaymentRecordId] = useState("");
  const [paymentAmount, setPaymentAmount] = useState("");
  const [paymentDate, setPaymentDate] = useState(getToday());

  useEffect(() => {
    const refreshSettings = () => {
      const latestShopCurrency = getShopCurrency();
      setShopCurrency(latestShopCurrency);
      setCurrencySettingsNotice(
        latestShopCurrency
          ? ""
          : "Shop currency settings are invalid or unavailable. Select this record's currency explicitly and review Workspace settings."
      );
      if (!creditCurrencyManuallySelected) {
        if (!latestShopCurrency) {
          setCurrencyCode("");
          setCreditCurrencyNeedsReview(true);
        } else if (latestShopCurrency !== currencyCode) {
          setCurrencyCode(latestShopCurrency);
          setCreditCurrencyNeedsReview(true);
        }
      }
    };

    const refresh = (event?: StorageEvent) => {
      if (
        event &&
        event.key !== STORAGE_KEY &&
        event.key !== SETTINGS_STORAGE_KEY &&
        event.key !== EXCHANGE_RATES_STORAGE_KEY &&
        event.key !== null
      ) {
        return;
      }

      if (!event || event.key === STORAGE_KEY || event.key === null) {
        const latest = readRecordSnapshot();
        setRecordReadState((current) =>
          latest
            ? {
                records:
                  JSON.stringify(current.records) ===
                  JSON.stringify(latest.records)
                    ? current.records
                    : latest.records,
                hasValidSnapshot: true,
                readError: false,
              }
            : current.readError
              ? current
              : { ...current, readError: true }
        );
      }

      if (!event || event.key === SETTINGS_STORAGE_KEY || event.key === null) {
        refreshSettings();
      }

      if (
        shopCurrency &&
        (!event ||
          event.key === EXCHANGE_RATES_STORAGE_KEY ||
          event.key === SETTINGS_STORAGE_KEY ||
          event.key === null)
      ) {
        const latestRates = getSavedExchangeRateSnapshot(
          getShopCurrency() ?? shopCurrency
        );
        setExchangeSnapshot(latestRates);
      }
    };
    const refreshOnFocus = () => refresh();

    window.addEventListener("focus", refreshOnFocus);
    window.addEventListener("storage", refresh);

    return () => {
      window.removeEventListener("focus", refreshOnFocus);
      window.removeEventListener("storage", refresh);
    };
  }, [creditCurrencyManuallySelected, currencyCode, shopCurrency]);

  useEffect(() => {
    let cancelled = false;

    if (!shopCurrency) {
      setExchangeSnapshot(null);
      setRateMessage(
        "Shop currency settings are invalid or unavailable. Exchange-rate totals cannot be calculated."
      );
      return () => {
        cancelled = true;
      };
    }

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
            `Could not refresh exchange rates. Using the saved snapshot last updated ${new Date(
              savedSnapshot.lastUpdatedAt
            ).toLocaleString()}${
              isExchangeRateSnapshotExpired(savedSnapshot)
                ? " (expired)."
                : "."
            }`
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

  const saveRecords = (
    updated: CreditRecord[],
    expectedRaw: string | null,
  ): boolean => {
    try {
      if (localStorage.getItem(STORAGE_KEY) !== expectedRaw) {
        const latest = readRecordSnapshot();
        if (latest) {
          setRecordReadState({
            records: latest.records,
            hasValidSnapshot: true,
            readError: false,
          });
        } else {
          setRecordReadState((current) =>
            current.readError ? current : { ...current, readError: true }
          );
        }
        setNotice(
          "Credit records changed in another tab. The latest records were loaded; review and try again."
        );
        return false;
      }

      localStorage.setItem(STORAGE_KEY, JSON.stringify(updated));
      setRecordReadState({
        records: updated,
        hasValidSnapshot: true,
        readError: false,
      });
      return true;
    } catch {
      setNotice(
        "Could not save credit records. Check available browser storage."
      );
      return false;
    }
  };

  const totals = useMemo(() => {
    if (!shopCurrency) {
      return {
        payables: {
          amount: 0,
          missingCurrencies: [] as CurrencyCode[],
          unresolvedCurrencyRecords: countUnresolvedBalances(records, "Payable"),
          invalidAmountRecords: countInvalidBalances(records, "Payable"),
        },
        receivables: {
          amount: 0,
          missingCurrencies: [] as CurrencyCode[],
          unresolvedCurrencyRecords: countUnresolvedBalances(records, "Receivable"),
          invalidAmountRecords: countInvalidBalances(records, "Receivable"),
        },
        overdue: records.filter(
          (record) => getStatus(record) === "Overdue"
        ).length,
        open: records.filter((record) => (getBalance(record) ?? 0) > 0).length,
      };
    }

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
      open: records.filter((record) => (getBalance(record) ?? 0) > 0).length,
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

    if (!creditCurrencyManuallySelected) {
      const currentShopCurrency = getShopCurrency();

      if (!currentShopCurrency) {
        setShopCurrency(null);
        setCurrencyCode("");
        setCreditCurrencyNeedsReview(true);
        setNotice(
          "Shop currency settings are invalid or unavailable. Select this record's currency explicitly before saving."
        );
        return;
      }

      if (currentShopCurrency !== currencyCode) {
        setShopCurrency(currentShopCurrency);
        setCurrencyCode(currentShopCurrency);
        setCreditCurrencyNeedsReview(true);
        setNotice(
          "Shop currency changed. Review the amount and confirm the record currency before saving."
        );
        return;
      }
    }

    if (creditCurrencyNeedsReview) {
      setNotice(
        "Review the credit amount and currency, then confirm before saving."
      );
      return;
    }

    if (!currencyCode) {
      setNotice(
        currencySettingsNotice || "Select a currency before saving the credit record."
      );
      return;
    }

    if (!party.trim()) {
      setNotice("Enter the supplier or customer name.");
      return;
    }

    if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
      setNotice("Enter a valid amount greater than zero.");
      return;
    }

    const latest = readRecordSnapshot();

    if (!latest) {
      setRecordReadState((current) =>
        current.readError ? current : { ...current, readError: true }
      );
      setNotice(
        "Could not safely read saved credit records. No changes were made; check browser storage before trying again."
      );
      return;
    }

    const record: CreditRecord = {
      id: `CREDIT-${crypto.randomUUID()}`,
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

    if (!saveRecords([record, ...latest.records], latest.raw)) return;

    setParty("");
    setContact("");
    setReference("");
    setDescription("");
    setAmount("");
    setDueDate("");
    const currentShopCurrency = getShopCurrency();
    setCurrencyCode(currentShopCurrency ?? "");
    setCreditCurrencyManuallySelected(false);
    setCreditCurrencyNeedsReview(false);
    setCurrencySettingsNotice(
      currentShopCurrency
        ? ""
        : "Shop currency settings are invalid or unavailable. Select this record's currency explicitly and review Workspace settings."
    );
    setShowForm(false);
    setNotice("Credit record saved successfully.");
  };

  const addPayment = (record: CreditRecord) => {
    const parsedAmount = parseAmountInput(paymentAmount);
    const latest = readRecordSnapshot();

    if (!latest) {
      setRecordReadState((current) =>
        current.readError ? current : { ...current, readError: true }
      );
      setNotice(
        "Could not safely read saved credit records. No payment was recorded; check browser storage before trying again."
      );
      return;
    }

    const currentRecord = latest.records.find((item) => item.id === record.id);

    if (!currentRecord) {
      setRecordReadState({
        records: latest.records,
        hasValidSnapshot: true,
        readError: false,
      });
      setNotice("This credit record is no longer available. Latest records were loaded.");
      return;
    }

    const recordCurrency = getCurrency(currentRecord);
    if (!recordCurrency) {
      setNotice(
        "Cannot record a payment because this credit record has no valid saved currency. The record was not changed; resolve its currency first."
      );
      return;
    }

    const balance = getBalance(currentRecord);
    if (balance === null) {
      setNotice(
        "Cannot record a payment because this credit record has an invalid principal or payment total. The record was not changed; review its saved amounts first."
      );
      return;
    }

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
      id: `PAY-${crypto.randomUUID()}`,
      amount: parsedAmount,
      date: paymentDate || getToday(),
    };

    const updated = latest.records.map((item) =>
      item.id === currentRecord.id
        ? { ...item, payments: [...item.payments, payment] }
        : item
    );

    if (!saveRecords(updated, latest.raw)) return;
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

      {recordReadState.readError && (
        <div className="operations-note" role="alert">
          <strong>Credit ledger unavailable.</strong>{" "}
          {recordReadState.hasValidSnapshot
            ? "The latest browser storage read failed. Showing the last successfully loaded records; totals may be out of date."
            : "Browser storage could not be read. Credit totals and records are unavailable."}
        </div>
      )}

      <div className="credit-summary-grid">
        <article className="surface-card credit-summary-card">
          <div className="credit-summary-icon payable">
            <ArrowUpRight size={19} />
          </div>
          <span>Supplier payables</span>
          <strong>
            {recordReadState.hasValidSnapshot && shopCurrency
              ? formatCurrency(totals.payables.amount, shopCurrency)
              : "Unavailable"}
          </strong>
          <small>
            {!recordReadState.hasValidSnapshot
              ? "Credit ledger data could not be read."
              : shopCurrency
              ? `Combined outstanding balance in ${shopCurrency}`
              : "Shop currency is unavailable; converted total is not shown."}
          </small>
          {recordReadState.hasValidSnapshot &&
            totals.payables.missingCurrencies.length > 0 && (
            <small>
              Not converted: {totals.payables.missingCurrencies.join(", ")}
            </small>
          )}
          {recordReadState.hasValidSnapshot &&
            totals.payables.unresolvedCurrencyRecords > 0 && (
            <small>
              Excluded: {totals.payables.unresolvedCurrencyRecords} open record(s)
              with unavailable currency
            </small>
          )}
          {recordReadState.hasValidSnapshot &&
            totals.payables.invalidAmountRecords > 0 && (
            <small>
              Excluded: {totals.payables.invalidAmountRecords} record(s) with
              invalid principal or payment totals
            </small>
          )}
        </article>

        <article className="surface-card credit-summary-card">
          <div className="credit-summary-icon receivable">
            <ArrowDownLeft size={19} />
          </div>
          <span>Customer receivables</span>
          <strong>
            {recordReadState.hasValidSnapshot && shopCurrency
              ? formatCurrency(totals.receivables.amount, shopCurrency)
              : "Unavailable"}
          </strong>
          <small>
            {!recordReadState.hasValidSnapshot
              ? "Credit ledger data could not be read."
              : shopCurrency
              ? `Combined outstanding balance in ${shopCurrency}`
              : "Shop currency is unavailable; converted total is not shown."}
          </small>
          {recordReadState.hasValidSnapshot &&
            totals.receivables.missingCurrencies.length > 0 && (
            <small>
              Not converted: {totals.receivables.missingCurrencies.join(", ")}
            </small>
          )}
          {recordReadState.hasValidSnapshot &&
            totals.receivables.unresolvedCurrencyRecords > 0 && (
            <small>
              Excluded: {totals.receivables.unresolvedCurrencyRecords} open record(s)
              with unavailable currency
            </small>
          )}
          {recordReadState.hasValidSnapshot &&
            totals.receivables.invalidAmountRecords > 0 && (
            <small>
              Excluded: {totals.receivables.invalidAmountRecords} record(s)
              with invalid principal or payment totals
            </small>
          )}
        </article>

        <article className="surface-card credit-summary-card">
          <div className="credit-summary-icon">
            <Receipt size={19} />
          </div>
          <span>Open credit records</span>
          <strong>
            {recordReadState.hasValidSnapshot ? totals.open : "Unavailable"}
          </strong>
          <small>Records with unpaid balances</small>
        </article>

        <article className="surface-card credit-summary-card">
          <div className="credit-summary-icon overdue">
            <CalendarClock size={19} />
          </div>
          <span>Overdue records</span>
          <strong>
            {recordReadState.hasValidSnapshot ? totals.overdue : "Unavailable"}
          </strong>
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
                  onChange={(event) => {
                    setCurrencyCode(event.target.value as CurrencyCode);
                    setCreditCurrencyManuallySelected(true);
                    setCreditCurrencyNeedsReview(false);
                  }}
                >
                  <option value="" disabled>
                    Select a currency
                  </option>
                  {CURRENCY_OPTIONS.map((currency) => (
                    <option key={currency.code} value={currency.code}>
                      {currency.code}
                    </option>
                  ))}
                </select>
                {currencySettingsNotice && (
                  <small className="field-hint" role="status">
                    {currencySettingsNotice}
                  </small>
                )}
                {creditCurrencyNeedsReview && (
                  <small className="field-hint" role="status">
                    Shop currency changed. Review the amount, then{" "}
                    <button
                      className="button button-secondary"
                      type="button"
                      onClick={() => setCreditCurrencyNeedsReview(false)}
                    >
                      confirm this currency
                    </button>
                  </small>
                )}
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

        {!recordReadState.hasValidSnapshot ? (
          <div className="inventory-empty">
            <Banknote size={26} />
            <strong>Credit records unavailable</strong>
            <span>Browser storage could not be read.</span>
          </div>
        ) : visibleRecords.length === 0 ? (
          <div className="inventory-empty">
            <Banknote size={26} />
            <strong>
              {recordReadState.readError
                ? "No records in the last successful read"
                : "No credit records yet"}
            </strong>
            <span>
              {recordReadState.readError
                ? "The current ledger could not be verified."
                : "Create a supplier payable or customer receivable to begin."}
            </span>
          </div>
        ) : (
          <div className="credit-record-list">
            {visibleRecords.map((record) => {
              const paid = getPaidAmount(record);
              const balance = getBalance(record);
              const originalAmount = getKnownNonNegativeAmount(
                record.originalAmount
              );
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
                    <span>
                      Currency: {recordCurrency ?? "Currency unavailable"}
                    </span>
                    {!recordCurrency && balance !== null && balance > 0 && (
                      <small className="field-hint" role="status">
                        Payments are blocked until this record's currency is
                        explicitly resolved. Its original amount and balance
                        are shown without a currency assumption.
                      </small>
                    )}
                    {(originalAmount === null || paid === null || balance === null) && (
                      <small className="field-hint" role="alert">
                        This record has an invalid principal or payment total,
                        including payments exceeding its principal. Its balance
                        is excluded from summaries and payments are blocked
                        until the saved amounts are reviewed.
                      </small>
                    )}
                    <span>Due: {formatDate(record.dueDate)}</span>
                  </div>

                  <div className="credit-amount-grid">
                    <div>
                      <span>Original amount</span>
                      <strong>
                        {formatCurrency(
                          originalAmount ?? Number.NaN,
                          recordCurrency
                        )}
                      </strong>
                    </div>
                    <div>
                      <span>Paid</span>
                      <strong>
                        {formatCurrency(paid ?? Number.NaN, recordCurrency)}
                      </strong>
                    </div>
                    <div>
                      <span>Remaining balance</span>
                      <strong className="credit-balance">
                        {formatCurrency(
                          balance ?? Number.NaN,
                          recordCurrency
                        )}
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

                  {balance !== null && balance > 0 && (
                    <div className="credit-payment-actions">
                      {paymentOpen ? (
                        <div className="credit-payment-form">
                          <label className="inventory-field">
                            <span>
                              Payment amount (
                              {recordCurrency ?? "currency unavailable"})
                            </span>
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
                            disabled={!recordCurrency || balance === null}
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
                          disabled={!recordCurrency || balance === null}
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
