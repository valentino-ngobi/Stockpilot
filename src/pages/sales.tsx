
import { useEffect, useMemo, useState } from "react";
import {
  CalendarClock,
  CheckCircle2,
  Receipt,
  Search,
  ShoppingCart,
  Smartphone,
  XCircle,
} from "lucide-react";

type DeviceRecord = {
  id: string;
  brand: string;
  model: string;
  identifier: string;
  status: "In shop" | "With middle-man" | "At repairer" | "Sold";
   category?: "Device" | "Accessory / spare part";
  costPrice?: string;
  sellingPrice?: string;
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
};

const INVENTORY_KEY = "stockpilot-inventory";
const SALES_KEY = "stockpilot-sales";

function readInventory(): DeviceRecord[] {
  try {
    const saved = localStorage.getItem(INVENTORY_KEY);
    return saved ? JSON.parse(saved) as DeviceRecord[] : [];
  } catch {
    return [];
  }
}

function readSales(): SaleRecord[] {
  try {
    const saved = localStorage.getItem(SALES_KEY);
    return saved ? JSON.parse(saved) as SaleRecord[] : [];
  } catch {
    return [];
  }
}

export default function Sales() {
  const [devices, setDevices] = useState<DeviceRecord[]>(readInventory);
  const [sales, setSales] = useState<SaleRecord[]>(readSales);
  const [search, setSearch] = useState("");
  const [selectedId, setSelectedId] = useState("");
  const [salePrice, setSalePrice] = useState("");
  const [paymentMethod, setPaymentMethod] =
    useState<PaymentMethod>("Cash");
  const [transactionDate, setTransactionDate] = useState(
    new Date().toISOString().slice(0, 16)
  );
  const [notice, setNotice] = useState("");

  const availableDevices = useMemo(
    () => devices.filter(
      (device) =>
        device.status === "In shop" &&
        (device.category === undefined || device.category === "Device")
    ),
    [devices]
  );

  const filteredDevices = availableDevices.filter((device) =>
    `${device.brand} ${device.model} ${device.identifier}`
      .toLowerCase()
      .includes(search.toLowerCase())
  );

  const selectedDevice = availableDevices.find(
    (device) => device.id === selectedId
  );

  useEffect(() => {
    try {
      localStorage.setItem(SALES_KEY, JSON.stringify(sales));
    } catch (error) {
      console.error("Could not save sales:", error);
    }
  }, [sales]);

  const formatMoney = (amount: number) =>
    new Intl.NumberFormat("en-UG", {
      style: "currency",
      currency: "UGX",
      maximumFractionDigits: 0,
    }).format(amount);

  const handleSale = () => {
    setNotice("");

    if (!selectedDevice) {
      setNotice("Select an available device before recording a sale.");
      return;
    }

    const price = Number(salePrice);

    if (!Number.isFinite(price) || price <= 0) {
      setNotice("Enter a valid selling price greater than zero.");
      return;
    }

    if (!transactionDate || Number.isNaN(new Date(transactionDate).getTime())) {
      setNotice("Enter a valid transaction date and time.");
      return;
    }

    // Re-read inventory to avoid selling a device that has changed status.
    const latestDevices = readInventory();
    const latestDevice = latestDevices.find(
      (device) => device.id === selectedDevice.id
    );

    if (!latestDevice || latestDevice.status !== "In shop") {
      setDevices(latestDevices);
      setSelectedId("");
      setNotice("This device is no longer available. Refresh your selection.");
      return;
    }

    const sale: SaleRecord = {
      id: `SALE-${Date.now()}`,
      deviceId: latestDevice.id,
      deviceName: `${latestDevice.brand} ${latestDevice.model}`,
      identifier: latestDevice.identifier,
      salePrice: price,
      paymentMethod,
      transactionDate: new Date(transactionDate).toISOString(),
      costPrice: Number(latestDevice.costPrice) || 0,
    };

    const updatedDevices = latestDevices.map((device) =>
      device.id === latestDevice.id
        ? { ...device, status: "Sold" as const, updated: "Just now" }
        : device
    );

    try {
      localStorage.setItem(INVENTORY_KEY, JSON.stringify(updatedDevices));

      const updatedSales = [sale, ...readSales()];
      localStorage.setItem(SALES_KEY, JSON.stringify(updatedSales));

      setDevices(updatedDevices);
      setSales(updatedSales);
      setSelectedId("");
      setSalePrice("");
      setTransactionDate(new Date().toISOString().slice(0, 16));
      setPaymentMethod("Cash");
      setNotice("Sale recorded successfully. Inventory status updated to Sold.");
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
            Record device sales and keep your inventory up to date.
          </p>
        </div>
        <div className="operations-heading-icon">
          <ShoppingCart size={22} />
        </div>
      </div>

      <div className="operations-grid">
        <section className="surface-card operations-form-card">
          <div className="card-kicker">NEW TRANSACTION</div>
          <h2>Record a device sale</h2>

          <div className="operations-form">
            <label className="inventory-field">
              <span>Find available device</span>
              <div className="inventory-list-search">
                <Search size={16} />
                <input
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  placeholder="Search model or IMEI"
                />
              </div>
            </label>

            <label className="inventory-field">
              <span>Select device</span>
              <select
                value={selectedId}
                onChange={(event) => {
                  const id = event.target.value;
                  setSelectedId(id);
                  const device = availableDevices.find((item) => item.id === id);
                  setSalePrice(device?.sellingPrice ?? "");
                }}
              >
                <option value="">Choose a device</option>
                {filteredDevices.map((device) => (
                  <option key={device.id} value={device.id}>
                    {device.brand} {device.model} — {device.identifier}
                  </option>
                ))}
              </select>
              {availableDevices.length === 0 && (
                <small className="field-hint">
                  No available devices. Receive stock into Inventory first.
                </small>
              )}
            </label>

            {selectedDevice && (
              <div className="inventory-info-banner surface-card">
                <Smartphone size={19} />
                <div>
                  <strong>
                    {selectedDevice.brand} {selectedDevice.model}
                  </strong>
                  <p>{selectedDevice.identifier}</p>
                </div>
              </div>
            )}

            <label className="inventory-field">
              <span>Selling price (UGX)</span>
              <input
                type="number"
                min="1"
                step="1"
                value={salePrice}
                onChange={(event) => setSalePrice(event.target.value)}
                placeholder="Enter actual sale price"
              />
            </label>

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
              {notice.includes("successfully") ? (
                <CheckCircle2 size={15} />
              ) : (
                <XCircle size={15} />
              )}
              {notice}
            </p>
          )}

          <button className="button button-primary" onClick={handleSale}>
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
                    <Receipt size={17} />
                  </div>
                  <div className="operations-record-copy">
                    <strong>{sale.deviceName}</strong>
                    <span>{sale.identifier}</span>
                    <span>
                      {new Date(sale.transactionDate).toLocaleString()}
                    </span>
                    <span>{sale.paymentMethod} · {sale.id}</span>
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
              {devices.filter((device) => device.status === "In shop").length}
              {" "}devices currently available for sale.
            </span>
          </div>
        </section>
      </div>
    </section>
  );
}
