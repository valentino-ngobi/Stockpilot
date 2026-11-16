
import {
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
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
import {
  CURRENCY_OPTIONS,
  formatCurrency,
  getRecordCurrency,
  getShopCurrency,
  type CurrencyCode,
} from "../utils/currency";

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
  currencyCode?: CurrencyCode;
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
  currencyCode?: CurrencyCode;
  costCurrencyCode?: CurrencyCode;
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

function isAccessory(item: DeviceRecord) {
  return item.category === "Accessory / spare part";
}

function formatPriceInput(value: string): string {
  const cleaned = value.replace(/,/g, "").replace(/[^\d.]/g, "");
  const decimalPosition = cleaned.indexOf(".");

  const integerPart =
    decimalPosition === -1
      ? cleaned
      : cleaned.slice(0, decimalPosition);

  const decimalPart =
    decimalPosition === -1
      ? ""
      : cleaned.slice(decimalPosition + 1).replace(/\./g, "");

  const groupedInteger = integerPart.replace(
    /\B(?=(\d{3})+(?!\d))/g,
    ","
  );

  return decimalPosition === -1
    ? groupedInteger
    : `${groupedInteger}.${decimalPart}`;
}

function parsePriceInput(value: string): number {
  return Number(value.replace(/,/g, ""));
}

function getCaretPosition(
  formattedValue: string,
  digitCount: number
): number {
  if (digitCount <= 0) {
    return 0;
  }

  let counted = 0;

  for (let index = 0; index < formattedValue.length; index++) {
    if (formattedValue[index] !== ",") {
      counted++;
    }

    if (counted === digitCount) {
      return index + 1;
    }
  }

  return formattedValue.length;
}

export default function Sales() {
  const [devices, setDevices] = useState<DeviceRecord[]>(readInventory);
  const [sales, setSales] = useState<SaleRecord[]>(readSales);
  const [search, setSearch] = useState("");
  const [selectedId, setSelectedId] = useState("");
  const [salePrice, setSalePrice] = useState("");
  const [saleCurrencyCode, setSaleCurrencyCode] =
    useState<CurrencyCode>(getShopCurrency);
  const [quantity, setQuantity] = useState("1");
  const [paymentMethod, setPaymentMethod] =
    useState<PaymentMethod>("Cash");
  const [transactionDate, setTransactionDate] = useState(
    new Date().toISOString().slice(0, 16)
  );
  const [notice, setNotice] = useState("");

  const priceInputRef = useRef<HTMLInputElement>(null);
  const pendingPriceCaret = useRef<number | null>(null);

  useLayoutEffect(() => {
    if (
      pendingPriceCaret.current !== null &&
      priceInputRef.current
    ) {
      const position = getCaretPosition(
        salePrice,
        pendingPriceCaret.current
      );

      priceInputRef.current.setSelectionRange(position, position);
      pendingPriceCaret.current = null;
    }
  }, [salePrice]);

  const availableItems = useMemo(
    () => devices.filter((item) => item.status === "In shop"),
    [devices]
  );

  const normalizedSearch = search.trim().toLowerCase();

  const filteredItems = useMemo(
    () =>
      availableItems.filter((item) => {
        const searchableValues = [
          item.brand,
          item.model,
          item.identifier,
          ...(item.secondaryIdentifiers ?? []),
        ];

        return searchableValues.some((value) =>
          String(value ?? "")
            .toLowerCase()
            .includes(normalizedSearch)
        );
      }),
    [availableItems, normalizedSearch]
  );

  const selectedItem = availableItems.find(
    (item) => item.id === selectedId
  );

  const selectedIsAccessory = selectedItem
    ? isAccessory(selectedItem)
    : false;

  const purchaseCurrency = selectedItem
    ? getRecordCurrency(selectedItem.currencyCode)
    : null;

  const availableQuantity =
    selectedItem && selectedIsAccessory
      ? Math.max(0, Number(selectedItem.quantity) || 0)
      : 1;

  const requestedQuantity = selectedIsAccessory
    ? Math.max(0, Number(quantity) || 0)
    : 1;

  const totalPrice =
    parsePriceInput(salePrice) * requestedQuantity;

  useEffect(() => {
    try {
      localStorage.setItem(SALES_KEY, JSON.stringify(sales));
    } catch (error) {
      console.error("Could not save sales:", error);
    }
  }, [sales]);

  const handleCurrencyChange = (newCurrency: string) => {
    setSaleCurrencyCode(newCurrency);
    setSalePrice("");
    setNotice("");
  };

  const handlePriceChange = (
    event: React.ChangeEvent<HTMLInputElement>
  ) => {
    const inputValue = event.target.value;
    const cursorPosition =
      event.target.selectionStart ?? inputValue.length;

    const charactersBeforeCursor = inputValue
      .slice(0, cursorPosition)
      .replace(/,/g, "")
      .replace(/[^\d.]/g, "").length;

    const formattedValue = formatPriceInput(inputValue);

    pendingPriceCaret.current = charactersBeforeCursor;
    setSalePrice(formattedValue);
  };

  const handleItemSelection = (item: DeviceRecord) => {
    setSelectedId(item.id);

    const itemCurrency = getRecordCurrency(item.currencyCode);

    setSalePrice(
      itemCurrency === saleCurrencyCode
        ? formatPriceInput(item.sellingPrice ?? "")
        : ""
    );

    setQuantity("1");
    setSearch("");
    setNotice("");
  };

  const handleSale = () => {
    setNotice("");

    if (!selectedId) {
      setNotice("Please select an item to sell.");
      return;
    }

    const price = parsePriceInput(salePrice);
    const quantityToSell = Number(quantity);

    if (!Number.isFinite(price) || price <= 0) {
      setNotice("Enter a valid selling price.");
      return;
    }

    if (
      !Number.isInteger(quantityToSell) ||
      quantityToSell <= 0
    ) {
      setNotice("Enter a valid whole-number quantity.");
      return;
    }

    if (!transactionDate) {
      setNotice("Please select a transaction date.");
      return;
    }

    if (!saleCurrencyCode) {
      setNotice("Please select a sale currency.");
      return;
    }

    const latestDevices = readInventory();

    const latestItem = latestDevices.find(
      (item) => item.id === selectedId
    );

    if (!latestItem || latestItem.status !== "In shop") {
      setNotice(
        "This item is no longer available in the shop. Refresh and try again."
      );
      return;
    }

    const accessory = isAccessory(latestItem);
    const latestAvailableQuantity = accessory
      ? Math.max(0, Number(latestItem.quantity) || 0)
      : 1;

    if (accessory && quantityToSell > latestAvailableQuantity) {
      setNotice(
        `Only ${latestAvailableQuantity} units are currently available.`
      );
      return;
    }

    if (!accessory && quantityToSell !== 1) {
      setNotice("Devices can only be sold one at a time.");
      return;
    }

    const unitCost = Number(latestItem.costPrice) || 0;
    const saleTotal = price * quantityToSell;
    const costTotal = unitCost * quantityToSell;

    const sale: SaleRecord = {
      id: crypto.randomUUID(),
      deviceId: latestItem.id,
      deviceName: `${latestItem.brand} ${latestItem.model}`,
      identifier: latestItem.identifier,
      salePrice: saleTotal,
      paymentMethod,
      transactionDate,
      costPrice: costTotal,
      category: latestItem.category,
      quantitySold: accessory ? quantityToSell : 1,
      unitPrice: price,
      currencyCode: saleCurrencyCode,
      costCurrencyCode: getRecordCurrency(latestItem.currencyCode),
    };

    const updatedDevices = latestDevices.map((item) => {
      if (item.id !== selectedId) {
        return item;
      }

      if (accessory) {
        const remainingQuantity =
          Math.max(0, Number(item.quantity) || 0) - quantityToSell;

        return {
          ...item,
          quantity: remainingQuantity,
          status:
            remainingQuantity === 0
              ? "Sold" as const
              : "In shop" as const,
          updated: new Date().toISOString(),
        };
      }

      return {
        ...item,
        status: "Sold" as const,
        updated: new Date().toISOString(),
      };
    });

    const previousInventoryRaw =
      localStorage.getItem(INVENTORY_KEY);
    const previousSalesRaw =
      localStorage.getItem(SALES_KEY);

    const updatedSales = [sale, ...readSales()];

    try {
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
      setNotice("Sale recorded successfully.");
    } catch (error) {
      console.error("Could not save sale:", error);

      let rollbackSucceeded = true;

      try {
        if (previousInventoryRaw === null) {
          localStorage.removeItem(INVENTORY_KEY);
        } else {
          localStorage.setItem(
            INVENTORY_KEY,
            previousInventoryRaw
          );
        }

        if (previousSalesRaw === null) {
          localStorage.removeItem(SALES_KEY);
        } else {
          localStorage.setItem(
            SALES_KEY,
            previousSalesRaw
          );
        }
      } catch (rollbackError) {
        rollbackSucceeded = false;
        console.error(
          "Could not roll back failed sale:",
          rollbackError
        );
      }

      setNotice(
        rollbackSucceeded
          ? "Could not save the sale. No changes were kept. Check browser storage and try again."
          : "The sale could not be saved and automatic rollback also failed. Check inventory and sales records before trying again."
      );
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
            <div className="inventory-field">
              <label htmlFor="sales-stock-search">
                <span>Find available item</span>
              </label>

              <div style={{ position: "relative" }}>
                <div className="inventory-list-search">
                  <Search size={16} />
                  <input
                    id="sales-stock-search"
                    value={search}
                    onChange={(event) => {
                      setSearch(event.target.value);
                      setSelectedId("");
                      setSalePrice("");
                      setQuantity("1");
                      setNotice("");
                    }}
                    placeholder="Start typing a name, model or identifier..."
                    autoComplete="off"
                  />
                </div>

                {normalizedSearch.length > 0 && (
                  <div
                    role="listbox"
                    aria-label="Matching available stock"
                    style={{
                      position: "absolute",
                      top: "calc(100% + 6px)",
                      left: 0,
                      right: 0,
                      zIndex: 50,
                      maxHeight: "280px",
                      overflowY: "auto",
                      background: "var(--card-bg, #ffffff)",
                      color: "var(--text-primary, #171717)",
                      border: "1px solid var(--border-color, #d8dce3)",
                      borderRadius: "12px",
                      boxShadow: "0 12px 30px rgba(0, 0, 0, 0.16)",
                      padding: "6px",
                    }}
                  >
                    {filteredItems.length > 0 ? (
                      filteredItems.map((item) => (
                        <button
                          key={item.id}
                          type="button"
                          role="option"
                          aria-selected={selectedId === item.id}
                          onClick={() => handleItemSelection(item)}
                          style={{
                            display: "flex",
                            alignItems: "center",
                            gap: "12px",
                            width: "100%",
                            padding: "11px 10px",
                            border: "none",
                            borderRadius: "8px",
                            background:
                              selectedId === item.id
                                ? "var(--hover-bg, #edf2f8)"
                                : "transparent",
                            color: "inherit",
                            textAlign: "left",
                            cursor: "pointer",
                          }}
                        >
                          <span
                            style={{
                              display: "flex",
                              alignItems: "center",
                              justifyContent: "center",
                              width: "34px",
                              height: "34px",
                              flexShrink: 0,
                              borderRadius: "9px",
                              background: "var(--hover-bg, #edf2f8)",
                            }}
                          >
                            {isAccessory(item) ? (
                              <Package size={17} />
                            ) : (
                              <Smartphone size={17} />
                            )}
                          </span>

                          <span
                            style={{
                              display: "flex",
                              flexDirection: "column",
                              gap: "3px",
                              minWidth: 0,
                              flex: 1,
                            }}
                          >
                            <strong style={{ fontSize: "13px" }}>
                              {item.brand} {item.model}
                            </strong>
                            <span
                              style={{
                                fontSize: "12px",
                                opacity: 0.7,
                                overflow: "hidden",
                                textOverflow: "ellipsis",
                              }}
                            >
                              {item.identifier}
                            </span>
                          </span>

                          <span
                            style={{
                              fontSize: "11px",
                              opacity: 0.75,
                              whiteSpace: "nowrap",
                            }}
                          >
                            {isAccessory(item)
                              ? `${item.quantity ?? 0} available`
                              : "Device"}
                          </span>
                        </button>
                      ))
                    ) : (
                      <div
                        style={{
                          padding: "16px 12px",
                          fontSize: "13px",
                          opacity: 0.7,
                          textAlign: "center",
                        }}
                      >
                        No matching available stock found.
                      </div>
                    )}
                  </div>
                )}
              </div>

              <small className="field-hint">
                Type any part of the brand, model, SKU or identifier to see matching stock.
              </small>

              {availableItems.length === 0 && (
                <small className="field-hint">
                  No available items. Receive stock into Inventory first.
                </small>
              )}
            </div>

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
                  <p>
                    Original purchase currency: {purchaseCurrency}
                  </p>
                  <p>
                    Customer sale currency: {saleCurrencyCode}
                  </p>
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
              <span>Sale currency</span>
              <select
                value={saleCurrencyCode}
                onChange={(event) =>
                  handleCurrencyChange(event.target.value)
                }
              >
                {CURRENCY_OPTIONS.map((currency) => (
                  <option key={currency.code} value={currency.code}>
                    {currency.code}
                  </option>
                ))}
              </select>
              <small className="field-hint">
                Choose the currency the customer will actually pay in.
                This can differ from the purchase currency.
              </small>
            </label>

            <label className="inventory-field">
              <span>
                {selectedIsAccessory
                  ? `Selling price per unit (${saleCurrencyCode})`
                  : `Selling price (${saleCurrencyCode})`}
              </span>
              <input
                ref={priceInputRef}
                type="text"
                inputMode="decimal"
                value={salePrice}
                onChange={handlePriceChange}
                placeholder="Enter actual sale price"
                autoComplete="off"
              />
            </label>

            {selectedIsAccessory && (
              <div className="inventory-info-banner surface-card">
                <Receipt size={18} />
                <div>
                  <strong>Transaction total</strong>
                  <p>{formatCurrency(totalPrice, saleCurrencyCode)}</p>
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
              {sales.map((sale) => {
                const currencyCode = getRecordCurrency(sale.currencyCode);

                return (
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
                      {sale.costCurrencyCode && (
                        <span>
                          Original cost currency: {sale.costCurrencyCode}
                        </span>
                      )}
                    </div>
                    <strong className="operations-amount">
                      {formatCurrency(sale.salePrice, currencyCode)}
                    </strong>
                  </article>
                );
              })}
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
