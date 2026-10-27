import { useState } from "react";
import {
  ArrowLeftRight, Banknote, Building2, CalendarClock, CheckCircle2, ClipboardCheck,
  FileText, Package, Plus, Receipt, ShieldCheck, ShoppingCart, Users, Wrench,
} from "lucide-react";
import type { PageKey } from "../components/Sidebar";

type OperationRecord = { id: number; primary: string; secondary: string; status: string; amount?: string };

const config: Partial<Record<PageKey, { title: string; description: string; eyebrow: string; icon: typeof Package; action: string; fields: { label: string; placeholder: string; type?: string }[]; records: OperationRecord[]; note: string }>> = {
  Sales: {
    title: "Express checkout", eyebrow: "POINT OF SALE", description: "Find a serialized device or accessory, record payment and prepare a digital receipt.", icon: ShoppingCart, action: "Record demo sale",
    fields: [{ label: "IMEI, serial or product", placeholder: "Scan or enter device identifier" }, { label: "Selling price (UGX)", placeholder: "e.g. 850000", type: "number" }, { label: "Payment method", placeholder: "Cash / MTN MoMo / Airtel Money / Bank transfer" }, { label: "Customer WhatsApp (optional)", placeholder: "+256…" }],
    records: [{ id: 1, primary: "Demo iPhone 15 · 128 GB", secondary: "DEMO-IMEI-001 · Today 09:12", status: "Paid", amount: "UGX 850,000" }, { id: 2, primary: "USB-C charger · 2 units", secondary: "Demo transaction · Yesterday", status: "Paid", amount: "UGX 60,000" }],
    note: "Demo only: no payment is processed and no WhatsApp/SMS is sent. PDF generation and real receipt delivery require implementation and testing."
  },
  Custody: {
    title: "Device custody ledger", eyebrow: "MIDDLE-MAN TRACKING", description: "Track which device was entrusted to whom, when it left, and whether it was sold or returned.", icon: ArrowLeftRight, action: "Add demo custody record",
    fields: [{ label: "IMEI or serial", placeholder: "Scan or enter identifier" }, { label: "Person / middle-man", placeholder: "Name" }, { label: "Contact", placeholder: "Phone number" }, { label: "Expected return date", placeholder: "YYYY-MM-DD", type: "date" }],
    records: [{ id: 1, primary: "DEMO-IMEI-002 · Galaxy A15", secondary: "Assigned to Demo Agent · Today", status: "With middle-man" }, { id: 2, primary: "DEMO-IMEI-004 · iPhone 13", secondary: "Assigned to Demo Agent B · Yesterday", status: "Follow-up due" }],
    note: "Ownership and location should remain separate: a phone with a middle-man is still owned stock until a sale or other disposal is confirmed."
  },
  Repairs: {
    title: "Repair tracking", eyebrow: "SERVICE WORKFLOW", description: "Record devices sent to technicians and track diagnosis, repair cost and return to shop.", icon: Wrench, action: "Add demo repair job",
    fields: [{ label: "IMEI or serial", placeholder: "Scan or enter identifier" }, { label: "Technician / repair shop", placeholder: "Technician name" }, { label: "Reported issue", placeholder: "e.g. damaged screen" }, { label: "Estimated repair cost (UGX)", placeholder: "Optional estimate", type: "number" }],
    records: [{ id: 1, primary: "DEMO-IMEI-003 · Tecno Spark 20", secondary: "Charging port diagnosis · Yesterday", status: "At repairer" }, { id: 2, primary: "DEMO-SERIAL-005 · Samsung A-series", secondary: "Screen replacement · Today", status: "Awaiting quote" }],
    note: "Repair costs should be logged separately from device wholesale cost and sale revenue. This demo does not contact technicians."
  },
  "Daily closing": {
    title: "Daily cash reconciliation", eyebrow: "END-OF-DAY CONTROL", description: "Compare expected cash with the physical count and record discrepancies for owner review.", icon: ClipboardCheck, action: "Save demo closing",
    fields: [{ label: "Opening cash (UGX)", placeholder: "0", type: "number" }, { label: "Cash received (UGX)", placeholder: "0", type: "number" }, { label: "Cash paid out (UGX)", placeholder: "0", type: "number" }, { label: "Actual cash counted (UGX)", placeholder: "0", type: "number" }],
    records: [{ id: 1, primary: "Demo closing · 26 Oct", secondary: "Cash and non-cash payments reviewed", status: "Sample" }],
    note: "Expected cash = opening cash + cash received − cash paid out. Mobile money and bank transfers are not physical cash."
  },
  Reports: {
    title: "Know your stock", eyebrow: "INSIGHTS & REPORTING", description: "Monitor stock aging, low accessory levels, sales, stock valuation and estimated gross profit.", icon: FileText, action: "Add demo low-stock rule",
    fields: [{ label: "Product / SKU", placeholder: "e.g. iPhone 13 screen protector" }, { label: "Alert when quantity reaches", placeholder: "e.g. 5", type: "number" }],
    records: [{ id: 1, primary: "Aging stock · Demo iPhone 12", secondary: "Example device has been in stock over 60 days", status: "Review price" }, { id: 2, primary: "Low stock · Tempered glass", secondary: "Example quantity is below threshold", status: "Reorder" }],
    note: "Gross profit requires recorded net sales and cost of goods sold. These example alerts and figures are not connected to live transactions."
  },
  "Suppliers & credit": {
    title: "Supplier credit & customer layaway", eyebrow: "CREDIT LEDGERS", description: "Track what the shop owes suppliers and what customers still owe on reserved devices.", icon: Banknote, action: "Add demo credit entry",
    fields: [{ label: "Entry type", placeholder: "Supplier payable / Customer layaway" }, { label: "Supplier or customer", placeholder: "Name" }, { label: "Device IMEI / reference", placeholder: "Identifier or invoice reference" }, { label: "Amount due (UGX)", placeholder: "e.g. 300000", type: "number" }, { label: "Due date", placeholder: "YYYY-MM-DD", type: "date" }],
    records: [{ id: 1, primary: "Demo supplier payable", secondary: "Supplier A · Example balance UGX 450,000 · Due 30 Oct", status: "Part-paid" }, { id: 2, primary: "Demo customer layaway", secondary: "Reserved DEMO-IMEI-007 · Deposit UGX 200,000", status: "Balance due" }],
    note: "The real workflow must record every payment, calculate remaining balance, and prevent a reserved device from being released before the shop's rules are satisfied. These sample entries are not financial records."
  },
  "Team & shops": {
    title: "Team & shop access", eyebrow: "PEOPLE & LOCATIONS", description: "Plan shop membership, branch workspaces and least-privilege staff access.", icon: Users, action: "Add demo team member",
    fields: [{ label: "Staff display name", placeholder: "Name" }, { label: "Role", placeholder: "Owner / Admin / Attendant / Clerk" }, { label: "Shop or branch", placeholder: "Shop A / Shop B / Warehouse" }],
    records: [{ id: 1, primary: "Demo Owner", secondary: "Val Gadgets Demo · All owner controls", status: "Owner" }, { id: 2, primary: "Demo Attendant", secondary: "Shop A · POS and stock lookup only", status: "Clerk" }, { id: 3, primary: "Branch transfer · Shop A → Shop B", secondary: "Example transfer awaiting destination confirmation", status: "In-transit" }, { id: 4, primary: "Audit event · Demo Clerk", secondary: "Sample action log · no real staff data", status: "Logged" }],
    note: "This screen is a design prototype only. Real role enforcement must be implemented in the backend/database; hiding fields in the interface is not security. Transfers need Request → In-transit → Received states and audit events must be append-only."
  },
  Settings: {
    title: "Workspace settings", eyebrow: "PREFERENCES & CONTROLS", description: "Configure shop identity, currency, alerts and planned offline operation.", icon: Building2, action: "Save demo preference",
    fields: [{ label: "Shop name", placeholder: "Val Gadgets Demo" }, { label: "Default currency", placeholder: "UGX / KWD / USD" }, { label: "Aging stock threshold (days)", placeholder: "30", type: "number" }],
    records: [{ id: 1, primary: "Manual model entry", secondary: "Always available if lookup fails or internet is slow", status: "Required" }, { id: 2, primary: "Offline queue and sync", secondary: "Local persistence, conflict handling and retry policy", status: "Planned" }],
    note: "Offline support requires durable local storage and carefully tested synchronisation; it is not enabled by this settings mockup."
  },
};

export default function Operations({ page }: { page: PageKey }) {
  const details = config[page];
  const [records, setRecords] = useState<OperationRecord[]>(details?.records ?? []);
  const [values, setValues] = useState<string[]>(details?.fields.map(() => "") ?? []);
  const [notice, setNotice] = useState("");
  if (!details) return null;
  const Icon = details.icon;
  const submit = () => {
    const first = values.find((value) => value.trim());
    if (!first) { setNotice("Enter at least one field before adding a demo record."); return; }
    setRecords((current) => [{ id: Date.now(), primary: first, secondary: values.filter(Boolean).slice(1).join(" · ") || "Demo entry · Just now", status: "Demo" }, ...current]);
    setValues(details.fields.map(() => ""));
    setNotice("Demo record added in this page session. It is not saved to a database.");
  };
  return <section className="operations-page page-content">
    <div className="eyebrow"><span className="eyebrow-line" /> {details.eyebrow}</div>
    <div className="operations-heading"><div><h1>{details.title}</h1><p className="page-subtitle">{details.description}</p></div><div className="operations-heading-icon"><Icon size={22} /></div></div>
    <div className="operations-grid">
      <section className="surface-card operations-form-card"><div className="card-kicker">QUICK ACTION</div><h2>{details.action}</h2>
        <div className="operations-form">{details.fields.map((field, index) => <label className="inventory-field" key={field.label}><span>{field.label}</span><input type={field.type ?? "text"} placeholder={field.placeholder} value={values[index] ?? ""} onChange={(event) => setValues((current) => current.map((value, position) => position === index ? event.target.value : value))} /></label>)}</div>
        {notice && <p className="operations-notice" role="status"><CheckCircle2 size={15} /> {notice}</p>}
        <button className="button button-primary" onClick={submit}><Plus size={16} /> {details.action}</button>
        <p className="inventory-disclaimer">Prototype only · fictional data · no persistent storage or real message/payment integration.</p>
      </section>
      <section className="surface-card operations-list-card"><div className="inventory-card-heading"><div><div className="card-kicker">WORKSPACE REGISTER</div><h2>Recent demo records</h2></div><span className="inventory-count">{records.length} records</span></div>
        <div className="operations-record-list">{records.map((record) => <article className="operations-record" key={record.id}><div className="operations-record-icon"><Receipt size={17} /></div><div className="operations-record-copy"><strong>{record.primary}</strong><span>{record.secondary}</span></div><span className="inventory-device-status status-available">{record.status}</span>{record.amount && <strong className="operations-amount">{record.amount}</strong>}</article>)}</div>
        <div className="operations-note"><ShieldCheck size={16} /><span>{details.note}</span></div>
      </section>
    </div>
    {page === "Reports" && <div className="operations-stat-grid"><div className="surface-card operations-stat"><CalendarClock size={18} /><span>Stock aging</span><strong>30 / 60 days</strong></div><div className="surface-card operations-stat"><Package size={18} /><span>Stock valuation</span><strong>Owner-only data</strong></div><div className="surface-card operations-stat"><Banknote size={18} /><span>Profit reporting</span><strong>Sales − COGS</strong></div></div>}
  </section>;
}
