
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
  getKnownCostAmount,
  getKnownRecordCurrency,
  getKnownSaleAmount,
  getKnownStockQuantity,
  getShopCurrency,
  isCurrencyCode,
  SETTINGS_STORAGE_KEY,
  type CurrencyCode,
} from "../utils/currency";
import {
  getKnownPaymentMethod,
  PAYMENT_METHODS,
  type PaymentMethod,
} from "../utils/sales";

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

type SaleRecord = {
  id: string;
  deviceId: string;
  deviceName: string;
  identifier: string;
  salePrice: number;
  paymentMethod: PaymentMethod;
  transactionDate: string;
  costPrice: number | null;
  category?: ItemCategory;
  quantitySold?: number;
  unitPrice?: number;
  currencyCode?: CurrencyCode;
  costCurrencyCode?: CurrencyCode;
};

const INVENTORY_KEY = "stockpilot-inventory";
const SALES_KEY = "stockpilot-sales";

type StoredArraySnapshot<T> = {
  raw: string | null;
  records: T[];
};

type StoredArrayReadState<T> = {
  records: T[];
  hasValidSnapshot: boolean;
  readError: boolean;
};

function readStoredArray<T>(key: string): StoredArraySnapshot<T> | null {
  try {
    const raw = localStorage.getItem(key);

    if (raw === null) return { raw, records: [] };

    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return null;

    return { raw, records: parsed as T[] };
  } catch {
    return null;
  }
}

function toStoredArrayReadState<T>(
  snapshot: StoredArraySnapshot<T> | null
): StoredArrayReadState<T> {
  return {
    records: snapshot?.records ?? [],
    hasValidSnapshot: snapshot !== null,
    readError: snapshot === null,
  };
}

function getLocalDateTimeInputValue(date = new Date()): string {
  const localDate = new Date(
    date.getTime() - date.getTimezoneOffset() * 60_000,
  );

  return localDate.toISOString().slice(0, 16);
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

function formatSaleAmount(sale: SaleRecord): string {
  const amount = getKnownSaleAmount(sale.salePrice);
  return amount === null
    ? "Amount unavailable"
    : formatCurrency(amount, getKnownRecordCurrency(sale.currencyCode));
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
  const [inventoryReadState, setInventoryReadState] = useState(() =>
    toStoredArrayReadState(readStoredArray<DeviceRecord>(INVENTORY_KEY))
  );
  const [salesReadState, setSalesReadState] = useState(() =>
    toStoredArrayReadState(readStoredArray<SaleRecord>(SALES_KEY))
  );
  const devices = inventoryReadState.records;
  const sales = salesReadState.records;
  const [search, setSearch] = useState("");
  const [selectedId, setSelectedId] = useState("");
  const [salePrice, setSalePrice] = useState("");
  const [saleCurrencyCode, setSaleCurrencyCode] =
    useState<CurrencyCode>(() => getShopCurrency() ?? "");
  const [saleCurrencyManuallySelected, setSaleCurrencyManuallySelected] =
    useState(false);
  const [currencyNeedsReview, setCurrencyNeedsReview] = useState(false);
  const [currencySettingsNotice, setCurrencySettingsNotice] = useState(() =>
    getShopCurrency()
      ? ""
      : "Shop currency settings are invalid or unavailable. Select the sale currency explicitly and review Workspace settings."
  );
  const [quantity, setQuantity] = useState("1");
  const [paymentMethod, setPaymentMethod] =
    useState<PaymentMethod>("Cash");
  const [transactionDate, setTransactionDate] = useState(
    () => getLocalDateTimeInputValue()
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

  const purchaseCurrency =
    selectedItem && isCurrencyCode(selectedItem.currencyCode)
      ? selectedItem.currencyCode
      : null;

  const availableQuantity =
    selectedItem && selectedIsAccessory
      ? getKnownStockQuantity(selectedItem.quantity) ?? 0
      : 1;

  const requestedQuantity = selectedIsAccessory
    ? getKnownStockQuantity(Number(quantity)) ?? 0
    : 1;

  const totalPrice =
    parsePriceInput(salePrice) * requestedQuantity;

  useEffect(() => {
    const refreshCurrency = () => {
      const currentShopCurrency = getShopCurrency();

      if (!currentShopCurrency) {
        setCurrencySettingsNotice(
          "Shop currency settings are invalid or unavailable. Select the sale currency explicitly and review Workspace settings."
        );
        if (!saleCurrencyManuallySelected) {
          setSaleCurrencyCode("");
          setCurrencyNeedsReview(true);
        }
        return;
      }

      setCurrencySettingsNotice("");
      if (
        !saleCurrencyManuallySelected &&
        currentShopCurrency !== saleCurrencyCode
      ) {
        setSaleCurrencyCode(currentShopCurrency);
        setCurrencyNeedsReview(true);
      }
    };

    const refreshRecords = (event?: StorageEvent) => {
      if (
        event &&
        event.key !== INVENTORY_KEY &&
        event.key !== SALES_KEY &&
        event.key !== SETTINGS_STORAGE_KEY &&
        event.key !== null
      ) {
        return;
      }

      if (!event || event.key === INVENTORY_KEY || event.key === null) {
        const latestInventory = readStoredArray<DeviceRecord>(INVENTORY_KEY);
        setInventoryReadState((current) =>
          latestInventory
            ? {
                records:
                  JSON.stringify(current.records) ===
                  JSON.stringify(latestInventory.records)
                    ? current.records
                    : latestInventory.records,
                hasValidSnapshot: true,
                readError: false,
              }
            : current.readError
              ? current
              : { ...current, readError: true }
        );
      }

      if (!event || event.key === SALES_KEY || event.key === null) {
        const latestSales = readStoredArray<SaleRecord>(SALES_KEY);
        setSalesReadState((current) =>
          latestSales
            ? {
                records:
                  JSON.stringify(current.records) ===
                  JSON.stringify(latestSales.records)
                    ? current.records
                    : latestSales.records,
                hasValidSnapshot: true,
                readError: false,
              }
            : current.readError
              ? current
              : { ...current, readError: true }
        );
      }

      if (!event || event.key === SETTINGS_STORAGE_KEY || event.key === null) {
        refreshCurrency();
      }
    };
    const refreshOnFocus = () => refreshRecords();

    window.addEventListener("storage", refreshRecords);
    window.addEventListener("focus", refreshOnFocus);

    return () => {
      window.removeEventListener("storage", refreshRecords);
      window.removeEventListener("focus", refreshOnFocus);
    };
  }, [saleCurrencyCode, saleCurrencyManuallySelected]);

  const handleCurrencyChange = (newCurrency: string) => {
    setSaleCurrencyCode(newCurrency);
    setSaleCurrencyManuallySelected(true);
    setCurrencyNeedsReview(false);
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

    const itemCurrency = isCurrencyCode(item.currencyCode)
      ? item.currencyCode
      : null;

    setSalePrice(
      itemCurrency === saleCurrencyCode &&
        getKnownCostAmount(item.sellingPrice) !== null
        ? formatPriceInput(item.sellingPrice ?? "")
        : ""
    );

    setQuantity("1");
    setSearch("");
    setNotice(
      !itemCurrency
        ? "This inventory item has no valid saved cost currency. Its sale will be blocked until the cost currency is resolved."
        : isAccessory(item) &&
            getKnownStockQuantity(item.quantity) === null
          ? "This accessory has an invalid saved quantity. Its sale is blocked until inventory is corrected."
          : ""
    );
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
      !Number.isSafeInteger(quantityToSell) ||
      quantityToSell <= 0
    ) {
      setNotice("Enter a valid whole-number quantity.");
      return;
    }

    if (
      !transactionDate ||
      !Number.isFinite(new Date(transactionDate).getTime())
    ) {
      setNotice("Enter a valid transaction date and time.");
      return;
    }

    if (!saleCurrencyCode) {
      setNotice(
        currencySettingsNotice || "Please select a sale currency."
      );
      return;
    }

    if (!saleCurrencyManuallySelected) {
      const currentShopCurrency = getShopCurrency();

      if (!currentShopCurrency) {
        setSaleCurrencyCode("");
        setCurrencyNeedsReview(true);
        setNotice(
          "Shop currency settings are invalid or unavailable. Select the sale currency explicitly before saving."
        );
        return;
      }

      if (currentShopCurrency !== saleCurrencyCode) {
        setSaleCurrencyCode(currentShopCurrency);
        setCurrencyNeedsReview(true);
        setNotice(
          "Shop currency changed. Review the price and confirm the sale currency before saving."
        );
        return;
      }
    }

    if (currencyNeedsReview) {
      setNotice(
        "Review the sale price and currency, then confirm before recording this sale."
      );
      return;
    }

    const inventorySnapshot = readStoredArray<DeviceRecord>(INVENTORY_KEY);
    const salesSnapshot = readStoredArray<SaleRecord>(SALES_KEY);

    if (!inventorySnapshot || !salesSnapshot) {
      if (!inventorySnapshot) {
        setInventoryReadState((current) =>
          current.readError ? current : { ...current, readError: true }
        );
      }
      if (!salesSnapshot) {
        setSalesReadState((current) =>
          current.readError ? current : { ...current, readError: true }
        );
      }
      setNotice(
        "Could not safely read saved inventory or sales. No changes were made. Check browser storage before trying again."
      );
      return;
    }

    const latestDevices = inventorySnapshot.records;

    const latestItem = latestDevices.find(
      (item) => item.id === selectedId
    );

    if (!latestItem || latestItem.status !== "In shop") {
      setNotice(
        "This item is no longer available in the shop. Refresh and try again."
      );
      return;
    }

    const itemCostCurrency = latestItem.currencyCode;
    if (!isCurrencyCode(itemCostCurrency)) {
      setNotice(
        "This inventory item has no valid saved cost currency. No sale was recorded; resolve the item's cost currency before selling it."
      );
      return;
    }

    const accessory = isAccessory(latestItem);
    const latestAvailableQuantity = accessory
      ? getKnownStockQuantity(latestItem.quantity)
      : 1;

    if (latestAvailableQuantity === null) {
      setNotice(
        "This accessory has an invalid saved quantity. No sale was recorded; correct the inventory quantity first."
      );
      return;
    }

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

    const unitCost = getKnownCostAmount(latestItem.costPrice);
    const saleTotal = price * quantityToSell;
    const costTotal =
      unitCost === null ? null : unitCost * quantityToSell;

    if (getKnownSaleAmount(saleTotal) === null) {
      setNotice(
        "The sale total is outside the supported numeric range. No sale was recorded."
      );
      return;
    }

    if (costTotal !== null && !Number.isFinite(costTotal)) {
      setNotice(
        "The inventory cost is outside the supported numeric range. No sale was recorded."
      );
      return;
    }

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
      costCurrencyCode: itemCostCurrency,
    };

    const updatedDevices = latestDevices.map((item) => {
      if (item.id !== selectedId) {
        return item;
      }

      if (accessory) {
        const remainingQuantity =
          (getKnownStockQuantity(item.quantity) ?? 0) - quantityToSell;

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

    const updatedSales = [sale, ...salesSnapshot.records];
    const updatedInventoryRaw = JSON.stringify(updatedDevices);
    const updatedSalesRaw = JSON.stringify(updatedSales);
    let inventoryWritten = false;
    let salesWritten = false;

    try {
      if (
        localStorage.getItem(INVENTORY_KEY) !== inventorySnapshot.raw ||
        localStorage.getItem(SALES_KEY) !== salesSnapshot.raw
      ) {
        const currentInventory = readStoredArray<DeviceRecord>(INVENTORY_KEY);
        const currentSales = readStoredArray<SaleRecord>(SALES_KEY);

        setInventoryReadState((current) =>
          currentInventory
            ? toStoredArrayReadState(currentInventory)
            : current.readError
              ? current
              : { ...current, readError: true }
        );
        setSalesReadState((current) =>
          currentSales
            ? toStoredArrayReadState(currentSales)
            : current.readError
              ? current
              : { ...current, readError: true }
        );

        setNotice(
          "Inventory or sales changed in another tab. The latest records were loaded; review and try again."
        );
        return;
      }

      localStorage.setItem(INVENTORY_KEY, updatedInventoryRaw);
      inventoryWritten = true;

      localStorage.setItem(SALES_KEY, updatedSalesRaw);
      salesWritten = true;

      setInventoryReadState(toStoredArrayReadState({
        raw: updatedInventoryRaw,
        records: updatedDevices,
      }));
      setSalesReadState(toStoredArrayReadState({
        raw: updatedSalesRaw,
        records: updatedSales,
      }));

      setSelectedId("");
      setSalePrice("");
      setQuantity("1");
      setNotice("Sale recorded successfully.");
    } catch (error) {
      console.error("Could not save sale:", error);

      const restoreValue = (
        key: string,
        previousRaw: string | null,
        writtenRaw: string,
        wasWritten: boolean,
      ) => {
        if (!wasWritten) return true;

        try {
          if (localStorage.getItem(key) !== writtenRaw) return false;

          if (previousRaw === null) {
            localStorage.removeItem(key);
          } else {
            localStorage.setItem(key, previousRaw);
          }

          return true;
        } catch (rollbackError) {
          console.error(`Could not restore ${key} after a failed sale:`, rollbackError);
          return false;
        }
      };

      const salesRestored = restoreValue(
        SALES_KEY,
        salesSnapshot.raw,
        updatedSalesRaw,
        salesWritten,
      );
      const inventoryRestored = restoreValue(
        INVENTORY_KEY,
        inventorySnapshot.raw,
        updatedInventoryRaw,
        inventoryWritten,
      );
      const rollbackSucceeded = salesRestored && inventoryRestored;

      const currentInventory = readStoredArray<DeviceRecord>(INVENTORY_KEY);
      const currentSales = readStoredArray<SaleRecord>(SALES_KEY);
      setInventoryReadState((current) =>
        currentInventory
          ? toStoredArrayReadState(currentInventory)
          : current.readError
            ? current
            : { ...current, readError: true }
      );
      setSalesReadState((current) =>
        currentSales
          ? toStoredArrayReadState(currentSales)
          : current.readError
            ? current
            : { ...current, readError: true }
      );

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

      {(inventoryReadState.readError || salesReadState.readError) && (
        <div
          className="operations-notice"
          style={{ color: "#f87171", fontSize: 13 }}
          role="alert"
        >
          <XCircle size={15} />
          <span>
            {inventoryReadState.readError &&
              (inventoryReadState.hasValidSnapshot
                ? "Could not refresh inventory. Showing the last successfully loaded stock; current availability may be out of date. "
                : "Inventory data is unavailable because browser storage could not be read. ")}
            {salesReadState.readError &&
              (salesReadState.hasValidSnapshot
                ? "Could not refresh sales history. Showing the last successfully loaded records; current history may be out of date."
                : "Sales history is unavailable because browser storage could not be read.")}
          </span>
        </div>
      )}

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

              {inventoryReadState.hasValidSnapshot &&
                availableItems.length === 0 && (
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
                    Original purchase currency: {purchaseCurrency || "Currency unavailable"}
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
              {currencyNeedsReview && (
                <small className="field-hint" role="status">
                  Shop currency changed. Review the entered sale price, then
                  <button
                    className="button button-secondary"
                    type="button"
                    onClick={() => setCurrencyNeedsReview(false)}
                  >
                    confirm this currency
                  </button>
                </small>
              )}
              <small className="field-hint">
                Choose the currency the customer will actually pay in.
                This can differ from the purchase currency.
              </small>
            </label>

            <label className="inventory-field">
              <span>
                {selectedIsAccessory
                  ? `Selling price per unit (${saleCurrencyCode || "select currency"})`
                  : `Selling price (${saleCurrencyCode || "select currency"})`}
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
                  <p>
                    {saleCurrencyCode
                      ? formatCurrency(totalPrice, saleCurrencyCode)
                      : "Select a sale currency"}
                  </p>
                </div>
              </div>
            )}

            <label className="inventory-field">
              <span>Payment method</span>
              <select
                value={paymentMethod}
                onChange={(event) =>
                  setPaymentMethod(
                    getKnownPaymentMethod(event.target.value) ?? "Cash"
                  )
                }
              >
                {PAYMENT_METHODS.map((method) => (
                  <option key={method}>{method}</option>
                ))}
              </select>
              <small className="field-hint">
                This method applies to the full sale amount. Partial customer
                payments are not supported.
              </small>
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
            <span className="inventory-count">
              {salesReadState.hasValidSnapshot ? `${sales.length} sales` : "Sales unavailable"}
            </span>
          </div>

          {!salesReadState.hasValidSnapshot ? (
            <div className="inventory-empty">
              <Receipt size={24} />
              <strong>Sales history unavailable</strong>
              <span>Browser storage could not be read, so sales records cannot be verified.</span>
            </div>
          ) : sales.length === 0 ? (
            <div className="inventory-empty">
              <Receipt size={24} />
              <strong>
                {salesReadState.readError
                  ? "No sales were present in the last successful read"
                  : "No sales recorded yet"}
              </strong>
              <span>
                {salesReadState.readError
                  ? "The latest sales history could not be verified."
                  : "Your completed transactions will appear here."}
              </span>
            </div>
          ) : (
            <div className="operations-record-list">
              {sales.map((sale) => {
                const costCurrencyCode = getKnownRecordCurrency(
                  sale.costCurrencyCode
                );

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
                      {sale.costPrice == null ? (
                        <span>Original cost: unavailable</span>
                      ) : (
                        <span>
                          Original cost currency:{" "}
                          {costCurrencyCode ?? "Currency unavailable"}
                        </span>
                      )}
                    </div>
                    <strong className="operations-amount">
                      {formatSaleAmount(sale)}
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
