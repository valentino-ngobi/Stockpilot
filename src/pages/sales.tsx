
import { useEffect, useMemo, useState } from "react";
import {
  CalendarClock,
  CheckCircle2,
  Package,
  Receipt,
  Search,
  ShoppingCart,
  Smartphone,
  XCircle,
} from "lucide-react";

type ItemCategory = "Device" | "Accessory / spare part";

type DeviceRecord = {
  id: string;
  brand: string;
  model: string;
  identifier: string;
  status: "In shop" | "With middle-man" | "At repairer" | "Sold";
  category?: ItemCategory;
  costPrice?: string;
  sellingPrice?: string;
  quantity?: number;
  secondaryIdentifiers?: string[];
  updated: string;
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
  category?: ItemCategory;
  quantitySold?: number;
  unitPrice?: number;
};

const INVENTORY_KEY = "stockpilot-inventory";
const SALES_KEY = "stockpilot-sales";

function readInventory(): DeviceRecord[] {
  try {
    const saved = localStorage.getItem(INVENTORY_KEY);
    return saved ? (JSON.parse(saved) as DeviceRecord[]) : [];
  } catch {
    return [];
  }
}

function readSales(): SaleRecord[] {
  try {
    const saved = localStorage.getItem(SALES_KEY);
    return saved ? (JSON.parse(saved) as SaleRecord[]) : [];
  } catch {
    return [];
  }
}

function formatMoney(amount: number) {
  return new Intl.NumberFormat("en-UG", {
    style: "currency",
    currency: "UGX",
    maximumFractionDigits: 0,
  }).format(amount);
}

function isAccessory(item: DeviceRecord) {
  return item.category === "Accessory / spare part";
}

export default function Sales() {
  const [devices, setDevices] = useState<DeviceRecord[]>(readInventory);
  const [sales, setSales] = useState<SaleRecord[]>(readSales);
  const [search, setSearch] = useState("");
  const [selectedId, setSelectedId] = useState("");
  const [salePrice, setSalePrice] = useState("");
  const [quantity, setQuantity] = useState("1");
  const [paymentMethod, setPaymentMethod] =
    useState<PaymentMethod>("Cash");
  const [transactionDate, setTransactionDate] = useState(
    new Date().toISOString().slice(0, 16)
  );
  const [notice, setNotice] = useState("");

  const availableItems = useMemo(
    () =>
      devices.filter(
        (item) => item.status === "In shop"
      ),
    [devices]
  );

  const filteredItems = availableItems.filter((item) =>
    `${item.brand} ${item.model} ${item.identifier}`
      .toLowerCase()
      .includes(search.toLowerCase())
  );

  const selectedItem = availableItems.find(
    (item) => item.id === selectedId
  );

  const selectedIsAccessory = selectedItem
    ? isAccessory(selectedItem)
    : false;

  const availableQuantity = selectedItem && selectedIsAccessory
    ? Math.max(0, Number(selectedItem.quantity) || 0)
    : 1;

  const requestedQuantity = selectedIsAccessory
    ? Math.max(0, Number(quantity) || 0)
    : 1;

  const totalPrice =
    (Number(salePrice) || 0) * requestedQuantity;

  useEffect(() => {
    try {
      localStorage.setItem(SALES_KEY, JSON.stringify(sales));
    } catch (error) {
      console.error("Could not save sales:", error);
    }
  }, [sales]);

  const handleSale = () => {
    setNotice("");

    if (!selectedItem) {
      setNotice("Select an available item before recording a sale.");
      return;
    }

    const unitPrice = Number(salePrice);

    if (!Number.isFinite(unitPrice) || unitPrice <= 0) {
      setNotice("Enter a valid selling price greater than zero.");
      return;
    }

    const saleQuantity = isAccessory(selectedItem)
      ? Number(quantity)
      : 1;

    if (
      !Number.isInteger(saleQuantity) ||
      saleQuantity <= 0
    ) {
      setNotice("Enter a valid whole-number quantity.");
      return;
    }

    if (
      !transactionDate ||
      Number.isNaN(new Date(transactionDate).getTime())
    ) {
      setNotice("Enter a valid transaction date and time.");
      return;
    }

    // Re-read the latest inventory before completing the sale.
    const latestDevices = readInventory();
    const latestItem = latestDevices.find(
      (item) => item.id === selectedItem.id
    );

    if (!latestItem || latestItem.status !== "In shop") {
      setDevices(latestDevices);
      setSelectedId("");
      setNotice("This item is no longer available. Refresh your selection.");
      return;
    }

    const accessory = isAccessory(latestItem);
    const currentQuantity = accessory
      ? Math.max(0, Number(latestItem.quantity) || 0)
      : 1;

    if (saleQuantity > currentQuantity) {
      setDevices(latestDevices);
      setNotice(
        `Insufficient stock. Only ${currentQuantity} unit(s) are available.`
      );
      return;
    }

    const unitCost = Number(latestItem.costPrice) || 0;
    const saleTotal = unitPrice * saleQuantity;
    const costTotal = unitCost * saleQuantity;

    const sale: SaleRecord = {
      id: `SALE-${Date.now()}`,
      deviceId: latestItem.id,
      deviceName: `${latestItem.brand} ${latestItem.model}`,
      identifier: latestItem.identifier,
      salePrice: saleTotal,
      paymentMethod,
      transactionDate: new Date(transactionDate).toISOString(),
      costPrice: costTotal,
      category: accessory ? "Accessory / spare part" : "Device",
      quantitySold: saleQuantity,
      unitPrice,
    };

    const updatedDevices = latestDevices.map((item) => {
      if (item.id !== latestItem.id) return item;

      if (accessory) {
        const remainingQuantity = currentQuantity - saleQuantity;

        return {
          ...item,
          quantity: remainingQuantity,
          status: remainingQuantity === 0
            ? "Sold" as const
            : "In shop" as const,
          updated: "Just now",
        };
      }

      return {
        ...item,
        status: "Sold" as const,
        updated: "Just now",
      };
    });

    const updatedSales = [sale, ...readSales()];

    try {
      // Save both records together as far as browser storage allows.
      localStorage.setItem(
        INVENTORY_KEY,
        JSON.stringify(updatedDevices)
      );
      localStorage.setItem(
        SALES_KEY,
        JSON.stringify(updatedSales)
      );

      setDevices(updatedDevices);
      setSales(updatedSales);
      setSelectedId("");
      setSalePrice("");
      setQuantity("1");
      setPaymentMethod("Cash");
      setTransactionDate(new Date().toISOString().slice(0, 16));

      setNotice(
        accessory
          ? `Sale recorded. ${saleQuantity} unit(s) sold successfully.`
          : "Sale recorded successfully. Inventory status updated to Sold."
      );
    } catch (error) {
      console.error("Could not complete sale:", error);
      setNotice("Could not save the sale. Check browser storage and try again.");
    }
  };

  return (
    <section className="operations-page page-content">
      <div className="eyebrow">
        <span className="eyebrow-line" /> POINT OF SALE
      </div>

      <div className="operations-heading">
        <div>
          <h1>Sales & checkout</h1>
          <p className="page-subtitle">
            Sell phones, accessories and spare parts while keeping stock updated.
          </p>
        </div>
        <div className="operations-heading-icon">
          <ShoppingCart size={22} />
        </div>
      </div>

      <div className="operations-grid">
        <section className="surface-card operations-form-card">
          <div className="card-kicker">NEW TRANSACTION</div>
          <h2>Record a sale</h2>

          <div className="operations-form">
            <label className="inventory-field">
              <span>Find available item</span>
              <div className="inventory-list-search">
                <Search size={16} />
                <input
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  placeholder="Search phone, accessory or identifier"
                />
              </div>
            </label>

            <label className="inventory-field">
              <span>Select item</span>
              <select
                value={selectedId}
                onChange={(event) => {
                  const id = event.target.value;
                  setSelectedId(id);
                  const item = availableItems.find(
                    (record) => record.id === id
                  );
                  setSalePrice(item?.sellingPrice ?? "");
                  setQuantity("1");
                }}
              >
                <option value="">Choose an item</option>
                {filteredItems.map((item) => (
                  <option key={item.id} value={item.id}>
                    {isAccessory(item) ? "[Accessory]" : "[Device]"}{" "}
                    {item.brand} {item.model} — {item.identifier}
                    {isAccessory(item)
                      ? ` (${item.quantity ?? 0} available)`
                      : ""}
                  </option>
                ))}
              </select>

              {availableItems.length === 0 && (
                <small className="field-hint">
                  No available items. Receive stock into Inventory first.
                </small>
              )}
            </label>

            {selectedItem && (
              <div className="inventory-info-banner surface-card">
                {selectedIsAccessory ? (
                  <Package size={19} />
                ) : (
                  <Smartphone size={19} />
                )}
                <div>
                  <strong>
                    {selectedItem.brand} {selectedItem.model}
                  </strong>
                  <p>{selectedItem.identifier}</p>
                  {selectedIsAccessory && (
                    <p>{availableQuantity} unit(s) currently available</p>
                  )}
                </div>
              </div>
            )}

            {selectedIsAccessory && (
              <label className="inventory-field">
                <span>Quantity to sell</span>
                <input
                  type="number"
                  min="1"
                  max={availableQuantity}
                  step="1"
                  value={quantity}
                  onChange={(event) => setQuantity(event.target.value)}
                  placeholder="Enter quantity"
                />
                <small className="field-hint">
                  Available stock: {availableQuantity} unit(s)
                </small>
              </label>
            )}

            <label className="inventory-field">
              <span>
                {selectedIsAccessory
                  ? "Selling price per unit (UGX)"
                  : "Selling price (UGX)"}
              </span>
              <input
                type="number"
                min="1"
                step="1"
                value={salePrice}
                onChange={(event) => setSalePrice(event.target.value)}
                placeholder="Enter actual sale price"
              />
            </label>

            {selectedIsAccessory && (
              <div className="inventory-info-banner surface-card">
                <Receipt size={18} />
                <div>
                  <strong>Transaction total</strong>
                  <p>{formatMoney(totalPrice)}</p>
                </div>
              </div>
            )}

            <label className="inventory-field">
              <span>Payment method</span>
              <select
                value={paymentMethod}
                onChange={(event) =>
                  setPaymentMethod(event.target.value as PaymentMethod)
                }
              >
                <option>Cash</option>
                <option>MTN Mobile Money</option>
                <option>Airtel Money</option>
                <option>Bank Transfer</option>
              </select>
            </label>

            <label className="inventory-field">
              <span>Transaction date and time</span>
              <input
                type="datetime-local"
                value={transactionDate}
                onChange={(event) => setTransactionDate(event.target.value)}
              />
            </label>
          </div>

          {notice && (
            <p className="operations-notice" role="status">
              {notice.includes("recorded") || notice.includes("successfully") ? (
                <CheckCircle2 size={15} />
              ) : (
                <XCircle size={15} />
              )}
              {notice}
            </p>
          )}

          <button
            className="button button-primary"
            onClick={handleSale}
            disabled={
              selectedIsAccessory &&
              requestedQuantity > availableQuantity
            }
          >
            <ShoppingCart size={16} />
            Complete sale
          </button>

          <p className="inventory-disclaimer">
            Demo mode · No payment is processed. Records are stored in this
            browser only.
          </p>
        </section>

        <section className="surface-card operations-list-card">
          <div className="inventory-card-heading">
            <div>
              <div className="card-kicker">SALES REGISTER</div>
              <h2>Recent transactions</h2>
            </div>
            <span className="inventory-count">{sales.length} sales</span>
          </div>

          {sales.length === 0 ? (
            <div className="inventory-empty">
              <Receipt size={24} />
              <strong>No sales recorded yet</strong>
              <span>Your completed transactions will appear here.</span>
            </div>
          ) : (
            <div className="operations-record-list">
              {sales.map((sale) => (
                <article className="operations-record" key={sale.id}>
                  <div className="operations-record-icon">
                    {sale.category === "Accessory / spare part" ? (
                      <Package size={17} />
                    ) : (
                      <Receipt size={17} />
                    )}
                  </div>
                  <div className="operations-record-copy">
                    <strong>{sale.deviceName}</strong>
                    <span>{sale.identifier}</span>
                    {sale.category === "Accessory / spare part" && (
                      <span>
                        Accessory · Qty {sale.quantitySold ?? 1}
                      </span>
                    )}
                    <span>
                      {new Date(sale.transactionDate).toLocaleString()}
                    </span>
                    <span>
                      {sale.paymentMethod} · {sale.id}
                    </span>
                  </div>
                  <strong className="operations-amount">
                    {formatMoney(sale.salePrice)}
                  </strong>
                </article>
              ))}
            </div>
          )}

          <div className="operations-note">
            <CalendarClock size={16} />
            <span>
              {devices.filter((item) => item.status === "In shop").length}
              {" "}items currently available for sale.
            </span>
          </div>
        </section>
      </div>
    </section>
  );
}
