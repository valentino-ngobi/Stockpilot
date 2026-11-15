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
};

type PaymentMethod =
  | "Cash"
  | "MTN Mobile Money"
  | "Airtel Money"
  | "Bank Transfer";

type SaleRecord = {
  id: string;
  deviceId: string;
  deviceName: string;
  identifier: string;
  salePrice: number;
  paymentMethod: PaymentMethod;
  transactionDate: string;
  costPrice: number;
  category?: "Device" | "Accessory / spare part";
  quantitySold?: number;
  unitPrice?: number;
};

const INVENTORY_KEY = "stockpilot-inventory";
const SALES_KEY = "stockpilot-sales";

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

function formatMoney(amount: number) {
  return new Intl.NumberFormat("en-UG", {
    style: "currency",
    currency: "UGX",
    maximumFractionDigits: 0,
  }).format(Number.isFinite(amount) ? amount : 0);
}

function getSaleCategory(sale: SaleRecord) {
  return sale.category === "Accessory / spare part"
    ? "Accessory / spare part"
    : "Device";
}

function getSaleQuantity(sale: SaleRecord) {
  return getSaleCategory(sale) === "Device"
    ? 1
    : Math.max(0, Number(sale.quantitySold) || 0);
}

function getLocalDateKey(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function ReportsView() {
  const [inventory, setInventory] = useState<InventoryRecord[]>(() =>
    readStorage<InventoryRecord>(INVENTORY_KEY)
  );

  const [sales, setSales] = useState<SaleRecord[]>(() =>
    readStorage<SaleRecord>(SALES_KEY)
  );

  const [period, setPeriod] = useState<"7" | "30" | "all">("7");

  useEffect(() => {
    const refreshData = () => {
      setInventory(readStorage<InventoryRecord>(INVENTORY_KEY));
      setSales(readStorage<SaleRecord>(SALES_KEY));
    };

    window.addEventListener("focus", refreshData);
    window.addEventListener("storage", refreshData);

    return () => {
      window.removeEventListener("focus", refreshData);
      window.removeEventListener("storage", refreshData);
    };
  }, []);

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
    const revenue = filteredSales.reduce(
      (total, sale) => total + (Number(sale.salePrice) || 0),
      0
    );

    const costOfGoods = filteredSales.reduce(
      (total, sale) => total + (Number(sale.costPrice) || 0),
      0
    );

    const grossProfit = revenue - costOfGoods;

    const deviceSales = filteredSales.filter(
      (sale) => getSaleCategory(sale) === "Device"
    );

    const accessorySales = filteredSales.filter(
      (sale) => getSaleCategory(sale) === "Accessory / spare part"
    );

    const accessoryUnits = accessorySales.reduce(
      (total, sale) => total + getSaleQuantity(sale),
      0
    );

    const paymentTotals = filteredSales.reduce<Record<string, number>>(
      (totals, sale) => {
        const method = sale.paymentMethod || "Other";
        totals[method] = (totals[method] || 0) + (Number(sale.salePrice) || 0);
        return totals;
      },
      {}
    );

    return {
      revenue,
      costOfGoods,
      grossProfit,
      transactionCount: filteredSales.length,
      deviceCount: deviceSales.length,
      accessoryCount: accessorySales.length,
      accessoryUnits,
      paymentTotals,
    };
  }, [filteredSales]);

  const stock = useMemo(() => {
    const available = inventory.filter((item) => item.status !== "Sold");

    const devices = available.filter(
      (item) => item.category !== "Accessory / spare part"
    );

    const accessories = available.filter(
      (item) => item.category === "Accessory / spare part"
    );

    const accessoryUnits = accessories.reduce(
      (total, item) => total + Math.max(0, Number(item.quantity) || 0),
      0
    );

    const deviceValue = devices.reduce(
      (total, item) => total + (Number(item.costPrice) || 0),
      0
    );

    const accessoryValue = accessories.reduce(
      (total, item) =>
        total +
        (Number(item.costPrice) || 0) *
          Math.max(0, Number(item.quantity) || 0),
      0
    );

    return {
      deviceCount: devices.length,
      accessoryTypes: accessories.length,
      accessoryUnits,
      totalUnits: devices.length + accessoryUnits,
      valuation: deviceValue + accessoryValue,
      withMiddleMan: available.filter(
        (item) => item.status === "With middle-man"
      ).length,
      atRepairer: available.filter(
        (item) => item.status === "At repairer"
      ).length,
    };
  }, [inventory]);

  const dailySales = useMemo(() => {
    const days = period === "30" ? 30 : 7;
    const now = new Date();

    return Array.from({ length: days }, (_, index) => {
      const date = new Date(now);
      date.setHours(0, 0, 0, 0);
      date.setDate(date.getDate() - (days - index - 1));

      const key = getLocalDateKey(date);

      const total = filteredSales
        .filter((sale) => {
          const saleDate = new Date(sale.transactionDate);
          return (
            !Number.isNaN(saleDate.getTime()) &&
            getLocalDateKey(saleDate) === key
          );
        })
        .reduce((sum, sale) => sum + (Number(sale.salePrice) || 0), 0);

      return {
        key,
        label: date.toLocaleDateString("en-UG", {
          day: "numeric",
          month: "short",
        }),
        total,
      };
    });
  }, [filteredSales, period]);

  const highestDailySale = Math.max(
    ...dailySales.map((day) => day.total),
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
          <strong>{formatMoney(report.revenue)}</strong>
          <small>{report.transactionCount} transactions</small>
        </article>

        <article className="surface-card operations-stat">
          <div className="operations-report-icon">
            <TrendingUp size={19} />
          </div>
          <span>Estimated gross profit</span>
          <strong className={report.grossProfit < 0 ? "report-negative" : ""}>
            {formatMoney(report.grossProfit)}
          </strong>
          <small>Revenue minus recorded cost</small>
        </article>

        <article className="surface-card operations-stat">
          <div className="operations-report-icon">
            <Wallet size={19} />
          </div>
          <span>Cost of goods sold</span>
          <strong>{formatMoney(report.costOfGoods)}</strong>
          <small>Cost attached to recorded sales</small>
        </article>

        <article className="surface-card operations-stat">
          <div className="operations-report-icon">
            <Package size={19} />
          </div>
          <span>Current stock value</span>
          <strong>{formatMoney(stock.valuation)}</strong>
          <small>{stock.totalUnits} units still in stock</small>
        </article>
      </div>

      <div className="operations-report-grid">
        <section className="surface-card operations-report-card">
          <div className="inventory-card-heading">
            <div>
              <div className="card-kicker">SALES PERFORMANCE</div>
              <h2>Daily sales</h2>
            </div>
            <CalendarClock size={19} />
          </div>

          {report.transactionCount === 0 ? (
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
                        width: `${(day.total / highestDailySale) * 100}%`,
                      }}
                    />
                  </div>
                  <strong>{formatMoney(day.total)}</strong>
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

          <div className="operations-report-breakdown">
            <div className="operations-report-breakdown-row">
              <div className="operations-report-breakdown-icon">
                <Smartphone size={18} />
              </div>
              <div>
                <strong>Phones & devices</strong>
                <span>{report.deviceCount} transactions</span>
              </div>
              <strong>{formatMoney(
                filteredSales
                  .filter((sale) => getSaleCategory(sale) === "Device")
                  .reduce((sum, sale) => sum + (Number(sale.salePrice) || 0), 0)
              )}</strong>
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
              <strong>{formatMoney(
                filteredSales
                  .filter(
                    (sale) =>
                      getSaleCategory(sale) === "Accessory / spare part"
                  )
                  .reduce((sum, sale) => sum + (Number(sale.salePrice) || 0), 0)
              )}</strong>
            </div>
          </div>

          <div className="operations-report-divider" />

          <div className="card-kicker">PAYMENT METHODS</div>

          {Object.keys(report.paymentTotals).length === 0 ? (
            <p className="operations-report-empty">
              No payment records for this period.
            </p>
          ) : (
            <div className="operations-report-payments">
              {Object.entries(report.paymentTotals).map(([method, total]) => (
                <div className="operations-report-payment" key={method}>
                  <span>{method}</span>
                  <strong>{formatMoney(total)}</strong>
                </div>
              ))}
            </div>
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
            <strong>{stock.deviceCount}</strong>
          </div>

          <div>
            <Package size={19} />
            <span>Accessory types</span>
            <strong>{stock.accessoryTypes}</strong>
          </div>

          <div>
            <ShoppingCart size={19} />
            <span>Accessory units</span>
            <strong>{stock.accessoryUnits}</strong>
          </div>

          <div>
            <ArrowLeftRight size={19} />
            <span>With middle-men</span>
            <strong>{stock.withMiddleMan}</strong>
          </div>

          <div>
            <Wrench size={19} />
            <span>At repairers</span>
            <strong>{stock.atRepairer}</strong>
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
            {filteredSales.length} transactions
          </span>
        </div>

        {recentSales.length === 0 ? (
          <div className="inventory-empty">
            <Receipt size={25} />
            <strong>No transactions to display</strong>
            <span>Record a sale to start building your reports.</span>
          </div>
        ) : (
          <div className="operations-record-list">
            {recentSales.map((sale) => {
              const accessory =
                getSaleCategory(sale) === "Accessory / spare part";

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
                        ? `${getSaleQuantity(sale)} units`
                        : sale.identifier || "Device sale"}
                      {" · "}
                      {new Date(sale.transactionDate).toLocaleString("en-UG")}
                    </span>
                    <span>{sale.paymentMethod}</span>
                  </div>

                  <strong className="operations-amount">
                    {formatMoney(Number(sale.salePrice) || 0)}
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
