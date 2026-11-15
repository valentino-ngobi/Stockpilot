
import { useEffect, useMemo, useState } from "react";
import {
  ClipboardList,
  PackageCheck,
  Plus,
  ShoppingCart,
  Truck,
} from "lucide-react";

type ProductCategory = "Device" | "Accessory / spare part";
type PurchaseStatus = "Draft" | "Received";

type PurchaseItem = {
  id: string;
  category: ProductCategory;
  brand: string;
  model: string;
  colour: string;
  storage: string;
  networkStatus: string;
  condition: string;
  quantity: number;
  unitCost: number;
  sellingPrice: number;
  identifiers: string[];
};

type PurchaseRecord = {
  id: string;
  supplier: string;
  supplierContact: string;
  invoiceReference: string;
  purchaseDate: string;
  dueDate: string;
  status: PurchaseStatus;
  items: PurchaseItem[];
  total: number;
  initialPayment: number;
  createdAt: string;
  receivedAt?: string;
};

type InventoryRecord = {
  id: string;
  brand: string;
  model: string;
  identifier: string;
  status: "In shop" | "With middle-man" | "At repairer" | "Sold";
  colour?: string;
  storage?: string;
  networkStatus?: string;
  condition?: string;
  costPrice?: string;
  sellingPrice?: string;
  category?: ProductCategory;
  quantity?: number;
  secondaryIdentifiers?: string[];
  updated: string;
};

type CreditPayment = {
  id: string;
  amount: number;
  date: string;
};

type CreditRecord = {
  id: string;
  type: "Payable" | "Receivable";
  party: string;
  contact: string;
  reference: string;
  description: string;
  originalAmount: number;
  dueDate: string;
  createdAt: string;
  payments: CreditPayment[];
  purchaseId?: string;
};

const PURCHASES_KEY = "stockpilot-purchases";
const INVENTORY_KEY = "stockpilot-inventory";
const CREDIT_KEY = "stockpilot-credit-records";

const emptyItem = {
  category: "Device" as ProductCategory,
  brand: "",
  model: "",
  colour: "",
  storage: "",
  networkStatus: "Unlocked",
  condition: "Brand New",
  quantity: "1",
  unitCost: "",
  sellingPrice: "",
  identifiers: "",
};

const money = (amount: number) =>
  new Intl.NumberFormat("en-UG").format(amount);

function readStorage<T>(key: string, fallback: T): T {
  try {
    const saved = localStorage.getItem(key);
    return saved ? (JSON.parse(saved) as T) : fallback;
  } catch {
    return fallback;
  }
}

function saveStorage<T>(key: string, value: T) {
  localStorage.setItem(key, JSON.stringify(value));
}

export default function Purchases() {
  const [purchases, setPurchases] = useState<PurchaseRecord[]>(() =>
    readStorage(PURCHASES_KEY, [])
  );

  const [itemForm, setItemForm] = useState(emptyItem);
  const [items, setItems] = useState<PurchaseItem[]>([]);
  const [supplier, setSupplier] = useState("");
  const [supplierContact, setSupplierContact] = useState("");
  const [invoiceReference, setInvoiceReference] = useState("");
  const [purchaseDate, setPurchaseDate] = useState(
    new Date().toISOString().slice(0, 10)
  );
  const [dueDate, setDueDate] = useState("");
  const [initialPayment, setInitialPayment] = useState("0");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    saveStorage(PURCHASES_KEY, purchases);
  }, [purchases]);

  useEffect(() => {
    const refresh = () => {
      setPurchases(readStorage(PURCHASES_KEY, []));
    };

    window.addEventListener("focus", refresh);
    window.addEventListener("storage", refresh);

    return () => {
      window.removeEventListener("focus", refresh);
      window.removeEventListener("storage", refresh);
    };
  }, []);

  const purchaseTotal = useMemo(
    () => items.reduce((sum, item) => sum + item.quantity * item.unitCost, 0),
    [items]
  );

  const receivedCount = purchases.filter(
    (purchase) => purchase.status === "Received"
  ).length;

  const draftCount = purchases.filter(
    (purchase) => purchase.status === "Draft"
  ).length;

  const addItem = () => {
    setError("");
    setMessage("");

    const quantity = Number(itemForm.quantity);
    const unitCost = Number(itemForm.unitCost);
    const sellingPrice = Number(itemForm.sellingPrice || 0);

    if (!itemForm.brand.trim() || !itemForm.model.trim()) {
      setError("Enter the product brand and model or product name.");
      return;
    }

    if (!Number.isInteger(quantity) || quantity < 1) {
      setError("Quantity must be a whole number greater than zero.");
      return;
    }

    if (!Number.isFinite(unitCost) || unitCost <= 0) {
      setError("Enter a valid unit purchase cost.");
      return;
    }

    if (!Number.isFinite(sellingPrice) || sellingPrice < 0) {
      setError("Enter a valid selling price.");
      return;
    }

    const identifiers = itemForm.identifiers
      .split(/[\n,;]+/)
      .map((value) => value.trim())
      .filter(Boolean);

    if (itemForm.category === "Device") {
      if (identifiers.length !== quantity) {
        setError(
          `This device line has a quantity of ${quantity}. Enter exactly ${quantity} individual IMEI or serial numbers.`
        );
        return;
      }

      if (new Set(identifiers).size !== identifiers.length) {
        setError("The device identifiers must be unique.");
        return;
      }

      const invalidImei = identifiers.some(
        (identifier) => /^\d+$/.test(identifier) && identifier.length !== 15
      );

      if (invalidImei) {
        setError("Any numeric IMEI entered must contain exactly 15 digits.");
        return;
      }
    }

    if (
      itemForm.category === "Accessory / spare part" &&
      identifiers.length > 1
    ) {
      setError("For accessories, enter at most one SKU or barcode.");
      return;
    }

    const newItem: PurchaseItem = {
      id: `ITEM-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
      category: itemForm.category,
      brand: itemForm.brand.trim(),
      model: itemForm.model.trim(),
      colour: itemForm.colour.trim(),
      storage: itemForm.storage.trim(),
      networkStatus: itemForm.networkStatus,
      condition: itemForm.condition,
      quantity,
      unitCost,
      sellingPrice,
      identifiers,
    };

    setItems((current) => [...current, newItem]);
    setItemForm(emptyItem);
    setMessage("Product added to this purchase.");
  };

  const removeItem = (itemId: string) => {
    setItems((current) => current.filter((item) => item.id !== itemId));
  };

  const createPurchase = () => {
    setError("");
    setMessage("");

    if (!supplier.trim()) {
      setError("Enter the supplier name.");
      return;
    }

    if (items.length === 0) {
      setError("Add at least one product to the purchase.");
      return;
    }

    const paid = Number(initialPayment || 0);

    if (!Number.isFinite(paid) || paid < 0 || paid > purchaseTotal) {
      setError("Initial payment must be between zero and the purchase total.");
      return;
    }

    const purchase: PurchaseRecord = {
      id: `PUR-${Date.now()}`,
      supplier: supplier.trim(),
      supplierContact: supplierContact.trim(),
      invoiceReference: invoiceReference.trim(),
      purchaseDate,
      dueDate,
      status: "Draft",
      items,
      total: purchaseTotal,
      initialPayment: paid,
      createdAt: new Date().toISOString(),
    };

    setPurchases((current) => [purchase, ...current]);

    setSupplier("");
    setSupplierContact("");
    setInvoiceReference("");
    setPurchaseDate(new Date().toISOString().slice(0, 10));
    setDueDate("");
    setInitialPayment("0");
    setItems([]);
    setMessage("Purchase draft saved. Inventory has not been changed.");
  };

  const receivePurchase = (purchase: PurchaseRecord) => {
    setError("");
    setMessage("");

    if (purchase.status === "Received") {
      setError("This purchase has already been received.");
      return;
    }

    const inventory = readStorage<InventoryRecord[]>(INVENTORY_KEY, []);
    const credits = readStorage<CreditRecord[]>(CREDIT_KEY, []);

    const updatedInventory = [...inventory];

    for (const item of purchase.items) {
      if (item.category === "Device") {
        for (const identifier of item.identifiers) {
          const duplicate = updatedInventory.some(
            (record) =>
              record.identifier === identifier ||
              record.secondaryIdentifiers?.includes(identifier)
          );

          if (duplicate) {
            setError(
              `Cannot receive this purchase: identifier ${identifier} already exists in inventory. No stock was added.`
            );
            return;
          }
        }
      }
    }

    for (const item of purchase.items) {
      if (item.category === "Device") {
        for (const identifier of item.identifiers) {
          updatedInventory.push({
            id: `STOCK-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
            brand: item.brand,
            model: item.model,
            identifier,
            status: "In shop",
            colour: item.colour,
            storage: item.storage,
            networkStatus: item.networkStatus,
            condition: item.condition,
            costPrice: String(item.unitCost),
            sellingPrice: String(item.sellingPrice),
            category: "Device",
            quantity: 1,
            secondaryIdentifiers: [],
            updated: "Just now",
          });
        }
      } else {
        const sku = item.identifiers[0] || item.model;

        const existingIndex = updatedInventory.findIndex(
          (record) =>
            record.category === "Accessory / spare part" &&
            record.brand.toLowerCase() === item.brand.toLowerCase() &&
            record.model.toLowerCase() === item.model.toLowerCase() &&
            (record.identifier || record.model).toLowerCase() ===
              sku.toLowerCase() &&
            record.status !== "Sold"
        );

        if (existingIndex >= 0) {
          const existing = updatedInventory[existingIndex];
          const oldQuantity = existing.quantity || 0;
          const newQuantity = oldQuantity + item.quantity;
          const oldCost = Number(existing.costPrice || 0);

          const weightedCost =
            (oldCost * oldQuantity + item.unitCost * item.quantity) /
            newQuantity;

          updatedInventory[existingIndex] = {
            ...existing,
            quantity: newQuantity,
            costPrice: String(weightedCost),
            sellingPrice: String(item.sellingPrice || existing.sellingPrice || 0),
            status: "In shop",
            updated: "Just now",
          };
        } else {
          updatedInventory.push({
            id: `STOCK-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
            brand: item.brand,
            model: item.model,
            identifier: sku,
            status: "In shop",
            colour: item.colour,
            condition: item.condition,
            costPrice: String(item.unitCost),
            sellingPrice: String(item.sellingPrice),
            category: "Accessory / spare part",
            quantity: item.quantity,
            secondaryIdentifiers: [],
            updated: "Just now",
          });
        }
      }
    }

    const alreadyLinked = credits.some(
      (credit) => credit.purchaseId === purchase.id
    );

    if (alreadyLinked) {
      setError(
        "A supplier credit record already exists for this purchase. Please check the credit ledger before trying again."
      );
      return;
    }

    const creditRecord: CreditRecord = {
      id: `CREDIT-${Date.now()}`,
      type: "Payable",
      party: purchase.supplier,
      contact: purchase.supplierContact,
      reference: purchase.invoiceReference || purchase.id,
      description: `Stock purchase ${purchase.id}`,
      originalAmount: purchase.total,
      dueDate: purchase.dueDate,
      createdAt: new Date().toISOString(),
      payments:
        purchase.initialPayment > 0
          ? [
              {
                id: `PAY-${Date.now()}`,
                amount: purchase.initialPayment,
                date: new Date().toISOString(),
              },
            ]
          : [],
      purchaseId: purchase.id,
    };

    saveStorage(INVENTORY_KEY, updatedInventory);
    saveStorage(CREDIT_KEY, [creditRecord, ...credits]);

    setPurchases((current) =>
      current.map((record) =>
        record.id === purchase.id
          ? {
              ...record,
              status: "Received",
              receivedAt: new Date().toISOString(),
            }
          : record
      )
    );

    setMessage(
      `Stock received successfully. Inventory updated and supplier credit linked for ${purchase.supplier}.`
    );
  };

  const getPurchasePayment = (purchase: PurchaseRecord) => {
    const credits = readStorage<CreditRecord[]>(CREDIT_KEY, []);
    const linked = credits.find((credit) => credit.purchaseId === purchase.id);

    if (!linked) {
      return {
        paid: purchase.initialPayment,
        outstanding: purchase.total - purchase.initialPayment,
      };
    }

    const paid = linked.payments.reduce(
      (sum, payment) => sum + payment.amount,
      0
    );

    return {
      paid,
      outstanding: Math.max(0, linked.originalAmount - paid),
    };
  };

  const inputStyle: React.CSSProperties = {
    width: "100%",
    padding: "10px 12px",
    borderRadius: 8,
    border: "1px solid var(--border, #343a46)",
    background: "var(--surface, #171b24)",
    color: "var(--text, #ffffff)",
    fontSize: 13,
    boxSizing: "border-box",
  };

  const labelStyle: React.CSSProperties = {
    display: "block",
    fontSize: 12,
    marginBottom: 6,
    color: "var(--muted, #a0a8b7)",
  };

  const fieldStyle: React.CSSProperties = {
    display: "flex",
    flexDirection: "column",
    gap: 4,
    minWidth: 0,
  };

  const panelStyle: React.CSSProperties = {
    background: "var(--card, #171b24)",
    border: "1px solid var(--border, #303744)",
    borderRadius: 12,
    padding: 18,
  };

  const buttonStyle: React.CSSProperties = {
    border: 0,
    borderRadius: 8,
    padding: "10px 14px",
    background: "#3478f6",
    color: "#fff",
    fontWeight: 600,
    fontSize: 13,
    cursor: "pointer",
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
      <div>
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <ShoppingCart size={22} />
          <h2 style={{ margin: 0 }}>Purchases & Stock Receiving</h2>
        </div>
        <p style={{ color: "var(--muted, #a0a8b7)", fontSize: 13 }}>
          Record supplier invoices, receive products into inventory and track
          supplier balances.
        </p>
      </div>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))",
          gap: 12,
        }}
      >
        <div style={panelStyle}>
          <div style={{ color: "var(--muted, #a0a8b7)", fontSize: 12 }}>
            Total purchase records
          </div>
          <h2 style={{ margin: "8px 0 0" }}>{purchases.length}</h2>
        </div>
        <div style={panelStyle}>
          <div style={{ color: "var(--muted, #a0a8b7)", fontSize: 12 }}>
            Draft purchases
          </div>
          <h2 style={{ margin: "8px 0 0" }}>{draftCount}</h2>
        </div>
        <div style={panelStyle}>
          <div style={{ color: "var(--muted, #a0a8b7)", fontSize: 12 }}>
            Received purchases
          </div>
          <h2 style={{ margin: "8px 0 0" }}>{receivedCount}</h2>
        </div>
      </div>

      {message && (
        <div
          style={{
            padding: 12,
            borderRadius: 8,
            background: "rgba(34, 197, 94, 0.12)",
            color: "#4ade80",
            fontSize: 13,
          }}
        >
          {message}
        </div>
      )}

      {error && (
        <div
          style={{
            padding: 12,
            borderRadius: 8,
            background: "rgba(239, 68, 68, 0.12)",
            color: "#f87171",
            fontSize: 13,
          }}
        >
          {error}
        </div>
      )}

      <section style={panelStyle}>
        <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
          <ClipboardList size={18} />
          <h3 style={{ margin: 0 }}>New supplier purchase</h3>
        </div>
        <p style={{ color: "var(--muted, #a0a8b7)", fontSize: 12 }}>
          Add the supplier invoice details, then add each product line.
        </p>

        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
            gap: 14,
            marginTop: 16,
          }}
        >
          <label style={fieldStyle}>
            <span style={labelStyle}>Supplier name *</span>
            <input
              style={inputStyle}
              value={supplier}
              onChange={(event) => setSupplier(event.target.value)}
              placeholder="e.g. Kampala Mobile Supplies"
            />
          </label>

          <label style={fieldStyle}>
            <span style={labelStyle}>Supplier contact</span>
            <input
              style={inputStyle}
              value={supplierContact}
              onChange={(event) => setSupplierContact(event.target.value)}
              placeholder="Phone number"
            />
          </label>

          <label style={fieldStyle}>
            <span style={labelStyle}>Invoice / reference</span>
            <input
              style={inputStyle}
              value={invoiceReference}
              onChange={(event) => setInvoiceReference(event.target.value)}
              placeholder="Invoice number"
            />
          </label>

          <label style={fieldStyle}>
            <span style={labelStyle}>Purchase date</span>
            <input
              style={inputStyle}
              type="date"
              value={purchaseDate}
              onChange={(event) => setPurchaseDate(event.target.value)}
            />
          </label>

          <label style={fieldStyle}>
            <span style={labelStyle}>Payment due date</span>
            <input
              style={inputStyle}
              type="date"
              value={dueDate}
              onChange={(event) => setDueDate(event.target.value)}
            />
          </label>
        </div>

        <div
          style={{
            borderTop: "1px solid var(--border, #303744)",
            margin: "22px 0 18px",
          }}
        />

        <h4 style={{ margin: "0 0 14px" }}>Add products to this invoice</h4>

        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))",
            gap: 12,
          }}
        >
          <label style={fieldStyle}>
            <span style={labelStyle}>Product category</span>
            <select
              style={inputStyle}
              value={itemForm.category}
              onChange={(event) =>
                setItemForm((current) => ({
                  ...current,
                  category: event.target.value as ProductCategory,
                  quantity: "1",
                  identifiers: "",
                }))
              }
            >
              <option value="Device">Phone / device</option>
              <option value="Accessory / spare part">
                Accessory / spare part
              </option>
            </select>
          </label>

          <label style={fieldStyle}>
            <span style={labelStyle}>Brand *</span>
            <input
              style={inputStyle}
              value={itemForm.brand}
              onChange={(event) =>
                setItemForm((current) => ({
                  ...current,
                  brand: event.target.value,
                }))
              }
              placeholder="Samsung"
            />
          </label>

          <label style={fieldStyle}>
            <span style={labelStyle}>Model / product name *</span>
            <input
              style={inputStyle}
              value={itemForm.model}
              onChange={(event) =>
                setItemForm((current) => ({
                  ...current,
                  model: event.target.value,
                }))
              }
              placeholder="Galaxy A15 / USB-C charger"
            />
          </label>

          <label style={fieldStyle}>
            <span style={labelStyle}>Quantity *</span>
            <input
              style={inputStyle}
              type="number"
              min="1"
              step="1"
              value={itemForm.quantity}
              onChange={(event) =>
                setItemForm((current) => ({
                  ...current,
                  quantity: event.target.value,
                }))
              }
            />
          </label>

          <label style={fieldStyle}>
            <span style={labelStyle}>Unit purchase cost (UGX) *</span>
            <input
              style={inputStyle}
              type="number"
              min="1"
              value={itemForm.unitCost}
              onChange={(event) =>
                setItemForm((current) => ({
                  ...current,
                  unitCost: event.target.value,
                }))
              }
              placeholder="450000"
            />
          </label>

          <label style={fieldStyle}>
            <span style={labelStyle}>Unit selling price (UGX)</span>
            <input
              style={inputStyle}
              type="number"
              min="0"
              value={itemForm.sellingPrice}
              onChange={(event) =>
                setItemForm((current) => ({
                  ...current,
                  sellingPrice: event.target.value,
                }))
              }
              placeholder="500000"
            />
          </label>

          <label style={fieldStyle}>
            <span style={labelStyle}>Colour</span>
            <input
              style={inputStyle}
              value={itemForm.colour}
              onChange={(event) =>
                setItemForm((current) => ({
                  ...current,
                  colour: event.target.value,
                }))
              }
              placeholder="Black"
            />
          </label>

          <label style={fieldStyle}>
            <span style={labelStyle}>Storage</span>
            <input
              style={inputStyle}
              value={itemForm.storage}
              onChange={(event) =>
                setItemForm((current) => ({
                  ...current,
                  storage: event.target.value,
                }))
              }
              placeholder="128 GB"
            />
          </label>

          <label style={fieldStyle}>
            <span style={labelStyle}>Condition</span>
            <select
              style={inputStyle}
              value={itemForm.condition}
              onChange={(event) =>
                setItemForm((current) => ({
                  ...current,
                  condition: event.target.value,
                }))
              }
            >
              <option>Brand New</option>
              <option>Used</option>
              <option>Refurbished</option>
            </select>
          </label>

          {itemForm.category === "Device" && (
            <label style={fieldStyle}>
              <span style={labelStyle}>Network status</span>
              <select
                style={inputStyle}
                value={itemForm.networkStatus}
                onChange={(event) =>
                  setItemForm((current) => ({
                    ...current,
                    networkStatus: event.target.value,
                  }))
                }
              >
                <option>Unlocked</option>
                <option>Locked</option>
                <option>Unknown</option>
              </select>
            </label>
          )}
        </div>

        <label style={{ ...fieldStyle, marginTop: 14 }}>
          <span style={labelStyle}>
            {itemForm.category === "Device"
              ? "IMEI / serial numbers (one per device) *"
              : "SKU / barcode (optional)"}
          </span>
          <textarea
            style={{ ...inputStyle, minHeight: 85, resize: "vertical" }}
            value={itemForm.identifiers}
            onChange={(event) =>
              setItemForm((current) => ({
                ...current,
                identifiers: event.target.value,
              }))
            }
            placeholder={
              itemForm.category === "Device"
                ? "Enter one IMEI or serial number per device"
                : "Enter the product SKU or barcode if available"
            }
          />
          {itemForm.category === "Device" && (
            <span style={{ color: "var(--muted, #a0a8b7)", fontSize: 11 }}>
              The number of identifiers must match the device quantity.
            </span>
          )}
        </label>

        <button
          type="button"
          style={{ ...buttonStyle, marginTop: 14 }}
          onClick={addItem}
        >
          <Plus size={15} style={{ verticalAlign: "middle", marginRight: 6 }} />
          Add product line
        </button>

        {items.length > 0 && (
          <div style={{ marginTop: 22 }}>
            <h4>Invoice items</h4>
            <div style={{ overflowX: "auto" }}>
              <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 12 }}>
                <thead>
                  <tr style={{ color: "var(--muted, #a0a8b7)", textAlign: "left" }}>
                    <th style={{ padding: 9 }}>Product</th>
                    <th style={{ padding: 9 }}>Type</th>
                    <th style={{ padding: 9 }}>Qty</th>
                    <th style={{ padding: 9 }}>Unit cost</th>
                    <th style={{ padding: 9 }}>Line total</th>
                    <th style={{ padding: 9 }}></th>
                  </tr>
                </thead>
                <tbody>
                  {items.map((item) => (
                    <tr key={item.id} style={{ borderTop: "1px solid var(--border, #303744)" }}>
                      <td style={{ padding: 9 }}>
                        <strong>{item.brand} {item.model}</strong>
                        {item.identifiers.length > 0 && (
                          <div style={{ color: "var(--muted, #a0a8b7)", marginTop: 3 }}>
                            {item.identifiers.length} identifier(s)
                          </div>
                        )}
                      </td>
                      <td style={{ padding: 9 }}>{item.category === "Device" ? "Device" : "Accessory"}</td>
                      <td style={{ padding: 9 }}>{item.quantity}</td>
                      <td style={{ padding: 9 }}>{money(item.unitCost)}</td>
                      <td style={{ padding: 9 }}>{money(item.quantity * item.unitCost)}</td>
                      <td style={{ padding: 9 }}>
                        <button
                          type="button"
                          onClick={() => removeItem(item.id)}
                          style={{ background: "transparent", color: "#f87171", border: 0, cursor: "pointer" }}
                        >
                          Remove
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div style={{ textAlign: "right", marginTop: 14 }}>
              <span style={{ color: "var(--muted, #a0a8b7)", fontSize: 12 }}>
                Purchase total
              </span>
              <h2 style={{ margin: "4px 0" }}>UGX {money(purchaseTotal)}</h2>
            </div>
          </div>
        )}

        <div
          style={{
            borderTop: "1px solid var(--border, #303744)",
            margin: "22px 0 18px",
          }}
        />

        <label style={{ ...fieldStyle, maxWidth: 300 }}>
          <span style={labelStyle}>Amount already paid (UGX)</span>
          <input
            style={inputStyle}
            type="number"
            min="0"
            value={initialPayment}
            onChange={(event) => setInitialPayment(event.target.value)}
          />
        </label>

        <p style={{ color: "var(--muted, #a0a8b7)", fontSize: 12 }}>
          Saving this purchase creates a draft only. Stock is not added to
          inventory until you confirm that the goods have arrived.
        </p>

        <button type="button" style={buttonStyle} onClick={createPurchase}>
          Save purchase draft
        </button>
      </section>

      <section style={panelStyle}>
        <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
          <Truck size={18} />
          <h3 style={{ margin: 0 }}>Purchase history</h3>
        </div>

        {purchases.length === 0 ? (
          <p style={{ color: "var(--muted, #a0a8b7)", fontSize: 13 }}>
            No purchases recorded yet.
          </p>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: 12, marginTop: 16 }}>
            {purchases.map((purchase) => {
              const payment = getPurchasePayment(purchase);

              return (
                <div
                  key={purchase.id}
                  style={{
                    border: "1px solid var(--border, #303744)",
                    borderRadius: 10,
                    padding: 14,
                  }}
                >
                  <div
                    style={{
                      display: "flex",
                      flexWrap: "wrap",
                      justifyContent: "space-between",
                      gap: 12,
                    }}
                  >
                    <div>
                      <strong>{purchase.supplier}</strong>
                      <div style={{ color: "var(--muted, #a0a8b7)", fontSize: 11, marginTop: 4 }}>
                        {purchase.invoiceReference || purchase.id} · {purchase.purchaseDate}
                      </div>
                    </div>
                    <div style={{ textAlign: "right" }}>
                      <strong>UGX {money(purchase.total)}</strong>
                      <div
                        style={{
                          fontSize: 11,
                          marginTop: 4,
                          color: purchase.status === "Received" ? "#4ade80" : "#fbbf24",
                        }}
                      >
                        {purchase.status}
                      </div>
                    </div>
                  </div>

                  <div style={{ marginTop: 12, fontSize: 12, color: "var(--muted, #a0a8b7)" }}>
                    {purchase.items.map((item) => (
                      <div key={item.id} style={{ padding: "3px 0" }}>
                        {item.brand} {item.model} — {item.quantity} × UGX {money(item.unitCost)}
                      </div>
                    ))}
                  </div>

                  <div
                    style={{
                      display: "flex",
                      flexWrap: "wrap",
                      gap: 18,
                      marginTop: 12,
                      paddingTop: 10,
                      borderTop: "1px solid var(--border, #303744)",
                      fontSize: 12,
                    }}
                  >
                    <span>Paid: UGX {money(payment.paid)}</span>
                    <span>Outstanding: UGX {money(payment.outstanding)}</span>
                  </div>

                  {purchase.status === "Draft" ? (
                    <button
                      type="button"
                      style={{ ...buttonStyle, marginTop: 14 }}
                      onClick={() => receivePurchase(purchase)}
                    >
                      <PackageCheck size={15} style={{ verticalAlign: "middle", marginRight: 6 }} />
                      Confirm stock received
                    </button>
                  ) : (
                    <div style={{ color: "#4ade80", fontSize: 11, marginTop: 12 }}>
                      Stock received and supplier payable linked.
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </section>
    </div>
  );
}
