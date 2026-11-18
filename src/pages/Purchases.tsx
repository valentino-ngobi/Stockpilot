
import { useEffect, useMemo, useState } from "react";
import {
  ClipboardList,
  PackageCheck,
  Plus,
  ShoppingCart,
  Truck,
} from "lucide-react";
import CurrencyInput from "../components/CurrencyInput";
import {
  CURRENCY_OPTIONS,
  formatCurrency,
  getKnownCostAmount,
  getKnownNonNegativeAmount,
  getKnownOutstandingBalance,
  getKnownRecordCurrency,
  getKnownStockQuantity,
  getShopCurrency,
  isCurrencyCode,
  SETTINGS_STORAGE_KEY,
  type CurrencyCode,
} from "../utils/currency";

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
  currencyCode?: CurrencyCode;
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
  currencyCode?: CurrencyCode;
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
  payments?: CreditPayment[];
  purchaseId?: string;
  currencyCode?: CurrencyCode;
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

function normalizeIdentifier(value: unknown): string {
  return typeof value === "string"
    ? value.normalize("NFKC").trim().toUpperCase()
    : "";
}

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

function readCreditSnapshot(): StoredArraySnapshot<CreditRecord> | null {
  const snapshot = readStoredArray<unknown>(CREDIT_KEY);
  if (!snapshot) return null;

  const records: CreditRecord[] = [];
  for (const value of snapshot.records) {
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

    records.push(record as CreditRecord);
  }

  return { ...snapshot, records };
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

type StorageEntry = {
  key: string;
  value: unknown;
  expectedRaw: string | null;
};

function saveStorageBatch(entries: StorageEntry[]) {
  const previousValues = new Map<string, string | null>();
  const serializedValues = new Map<string, string>();

  // Refuse the write if any key changed after the caller read its snapshot.
  try {
    for (const entry of entries) {
      const currentValue = localStorage.getItem(entry.key);

      if (currentValue !== entry.expectedRaw) {
        return {
          success: false,
          rollbackSucceeded: true,
          conflict: true,
        };
      }

      previousValues.set(entry.key, currentValue);
      const serializedValue = JSON.stringify(entry.value);
      if (typeof serializedValue !== "string") {
        throw new Error(`Could not serialize ${entry.key}.`);
      }
      serializedValues.set(entry.key, serializedValue);
    }
  } catch {
    return {
      success: false,
      rollbackSucceeded: true,
      conflict: false,
    };
  }

  const writtenEntries: StorageEntry[] = [];

  // Attempt each write, keeping enough information for a cautious rollback.
  try {
    for (const entry of entries) {
      localStorage.setItem(entry.key, serializedValues.get(entry.key)!);
      writtenEntries.push(entry);
    }

    return {
      success: true,
      rollbackSucceeded: true,
      conflict: false,
    };
  } catch {
    // Restore only values written here, and do not replace a newer tab's value.
    let rollbackSucceeded = true;

    for (const entry of writtenEntries.reverse()) {
      try {
        const key = entry.key;
        const previousValue = previousValues.get(key) ?? null;

        if (localStorage.getItem(key) !== serializedValues.get(key)) {
          rollbackSucceeded = false;
          continue;
        }

        if (previousValue === null) {
          localStorage.removeItem(key);
        } else {
          localStorage.setItem(key, previousValue);
        }
      } catch {
        rollbackSucceeded = false;
      }
    }

    return {
      success: false,
      rollbackSucceeded,
      conflict: false,
    };
  }
}

export default function Purchases() {
  const [purchaseReadState, setPurchaseReadState] = useState(() =>
    toStoredArrayReadState(readStoredArray<PurchaseRecord>(PURCHASES_KEY))
  );
  const [creditReadState, setCreditReadState] = useState(() =>
    toStoredArrayReadState(readCreditSnapshot())
  );
  const purchases = purchaseReadState.records;

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
  const [invoiceCurrency, setInvoiceCurrency] = useState<CurrencyCode>(
    () => getShopCurrency() ?? ""
  );
  const [invoiceCurrencyManuallySelected, setInvoiceCurrencyManuallySelected] =
    useState(false);
  const [invoiceCurrencyNeedsReview, setInvoiceCurrencyNeedsReview] =
    useState(false);
  const [currencySettingsNotice, setCurrencySettingsNotice] = useState(() =>
    getShopCurrency()
      ? ""
      : "Shop currency settings are invalid or unavailable. Select the invoice currency explicitly and review Workspace settings."
  );
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    const refreshCurrency = () => {
      const currentShopCurrency = getShopCurrency();
      setCurrencySettingsNotice(
        currentShopCurrency
          ? ""
          : "Shop currency settings are invalid or unavailable. Select the invoice currency explicitly and review Workspace settings."
      );
      if (!invoiceCurrencyManuallySelected) {
        if (!currentShopCurrency) {
          setInvoiceCurrency("");
          setInvoiceCurrencyNeedsReview(true);
        } else if (currentShopCurrency !== invoiceCurrency) {
          setInvoiceCurrency(currentShopCurrency);
          setInvoiceCurrencyNeedsReview(true);
        }
      }
    };

    const refresh = (event?: StorageEvent) => {
      if (
        event &&
        event.key !== PURCHASES_KEY &&
        event.key !== CREDIT_KEY &&
        event.key !== SETTINGS_STORAGE_KEY &&
        event.key !== null
      ) {
        return;
      }

      if (
        !event ||
        event.key === PURCHASES_KEY ||
        event.key === CREDIT_KEY ||
        event.key === null
      ) {
        const latest = readStoredArray<PurchaseRecord>(PURCHASES_KEY);
        setPurchaseReadState((current) =>
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

      if (!event || event.key === CREDIT_KEY || event.key === null) {
        const latestCredits = readCreditSnapshot();
        setCreditReadState((current) =>
          latestCredits
            ? {
                records: latestCredits.records,
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
    const refreshOnFocus = () => refresh();

    window.addEventListener("focus", refreshOnFocus);
    window.addEventListener("storage", refresh);

    return () => {
      window.removeEventListener("focus", refreshOnFocus);
      window.removeEventListener("storage", refresh);
    };
  }, [invoiceCurrency, invoiceCurrencyManuallySelected]);

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

  const selectedCurrency = getKnownRecordCurrency(invoiceCurrency) ?? "";

  const addItem = () => {
    setError("");
    setMessage("");

    if (invoiceCurrencyNeedsReview) {
      setError(
        "Review the invoice currency and entered amounts, then confirm before adding products."
      );
      return;
    }

    if (!selectedCurrency) {
      setError(
        currencySettingsNotice || "Select an invoice currency before adding products."
      );
      return;
    }

    const quantity = Number(itemForm.quantity);
    const unitCost = Number(itemForm.unitCost);
    const sellingPrice = Number(itemForm.sellingPrice || 0);

    if (!itemForm.brand.trim() || !itemForm.model.trim()) {
      setError("Enter the product brand and model or product name.");
      return;
    }

    if (!Number.isSafeInteger(quantity) || quantity < 1) {
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

    const lineTotal = quantity * unitCost;
    const updatedTotal =
      items.reduce((sum, item) => sum + item.quantity * item.unitCost, 0) +
      lineTotal;
    if (!Number.isFinite(lineTotal) || !Number.isFinite(updatedTotal)) {
      setError(
        "The purchase total is outside the supported numeric range. Reduce the quantity or unit cost."
      );
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

    if (!invoiceCurrencyManuallySelected) {
      const currentShopCurrency = getShopCurrency();

      if (!currentShopCurrency) {
        setInvoiceCurrency("");
        setInvoiceCurrencyNeedsReview(true);
        setError(
          "Shop currency settings are invalid or unavailable. Select the invoice currency explicitly before saving."
        );
        return;
      }

      if (currentShopCurrency !== invoiceCurrency) {
        setInvoiceCurrency(currentShopCurrency);
        setInvoiceCurrencyNeedsReview(true);
        setError(
          "Shop currency changed. Review the invoice amounts and confirm the currency before saving."
        );
        return;
      }
    }

    if (invoiceCurrencyNeedsReview) {
      setError(
        "Review the invoice currency and entered amounts, then confirm before saving the draft."
      );
      return;
    }

    if (!selectedCurrency) {
      setError(
        currencySettingsNotice || "Select an invoice currency before saving the draft."
      );
      return;
    }

    if (!supplier.trim()) {
      setError("Enter the supplier name.");
      return;
    }

    if (items.length === 0) {
      setError("Add at least one product to the purchase.");
      return;
    }

    if (!Number.isFinite(purchaseTotal) || purchaseTotal <= 0) {
      setError(
        "The purchase total is invalid or outside the supported numeric range."
      );
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
      currencyCode: selectedCurrency,
    };

    const latestPurchases = readStoredArray<PurchaseRecord>(PURCHASES_KEY);

    if (!latestPurchases) {
      setPurchaseReadState((current) =>
        current.readError ? current : { ...current, readError: true }
      );
      setError(
        "Could not safely read purchase history. No draft was saved; check browser storage before trying again."
      );
      return;
    }

    const updatedPurchases = [purchase, ...latestPurchases.records];
    const saveResult = saveStorageBatch([
      {
        key: PURCHASES_KEY,
        value: updatedPurchases,
        expectedRaw: latestPurchases.raw,
      },
    ]);

    if (!saveResult.success) {
      if (saveResult.conflict) {
        const currentPurchases = readStoredArray<PurchaseRecord>(PURCHASES_KEY);
        if (currentPurchases) {
          setPurchaseReadState(toStoredArrayReadState(currentPurchases));
        } else {
          setPurchaseReadState((current) =>
            current.readError ? current : { ...current, readError: true }
          );
        }
        setError(
          "Purchase history changed in another tab. The latest records were loaded; review and try again."
        );
      } else {
        setError("Could not save the purchase draft. No changes were made.");
      }
      return;
    }

    setPurchaseReadState({
      records: updatedPurchases,
      hasValidSnapshot: true,
      readError: false,
    });

    setSupplier("");
    setSupplierContact("");
    setInvoiceReference("");
    setPurchaseDate(new Date().toISOString().slice(0, 10));
    setDueDate("");
    setInitialPayment("0");
    setItems([]);
    setInvoiceCurrency(getShopCurrency() ?? "");
    setInvoiceCurrencyManuallySelected(false);
    setInvoiceCurrencyNeedsReview(false);
    setCurrencySettingsNotice(
      getShopCurrency()
        ? ""
        : "Shop currency settings are invalid or unavailable. Select the invoice currency explicitly and review Workspace settings."
    );

    setMessage(
      `Purchase draft saved in ${selectedCurrency}. Inventory has not been changed.`
    );
  };

  
  const receivePurchase = (purchase: PurchaseRecord) => {
    setError("");
    setMessage("");

    const latestPurchases = readStoredArray<PurchaseRecord>(PURCHASES_KEY);
    const inventorySnapshot = readStoredArray<InventoryRecord>(INVENTORY_KEY);
    const creditSnapshot = readCreditSnapshot();

    if (!latestPurchases || !inventorySnapshot || !creditSnapshot) {
      if (!latestPurchases) {
        setPurchaseReadState((current) =>
          current.readError ? current : { ...current, readError: true }
        );
      }
      if (!creditSnapshot) {
        setCreditReadState((current) =>
          current.readError ? current : { ...current, readError: true }
        );
      }
      setError(
        "Could not safely read purchase, inventory, or credit records. No changes were made; check browser storage before trying again."
      );
      return;
    }

    const currentPurchase = latestPurchases.records.find(
      (record) => record.id === purchase.id
    );

    if (!currentPurchase) {
      setPurchaseReadState(toStoredArrayReadState(latestPurchases));
      setError("This purchase is no longer in the latest purchase history.");
      return;
    }

    if (currentPurchase.status === "Received") {
      setPurchaseReadState(toStoredArrayReadState(latestPurchases));
      setError("This purchase has already been received.");
      return;
    }

    if (currentPurchase.status !== "Draft") {
      setError(
        "Cannot receive this purchase because its saved status is invalid. No records were changed."
      );
      return;
    }

    if (typeof currentPurchase.supplier !== "string" ||
      !currentPurchase.supplier.trim()) {
      setError(
        "Cannot receive this purchase because its supplier name is missing or invalid. No records were changed."
      );
      return;
    }

    if (!isCurrencyCode(currentPurchase.currencyCode)) {
      setError(
        "Cannot receive this purchase because its saved invoice currency is missing or invalid. No inventory or supplier credit was changed; review the purchase currency before receiving it."
      );
      return;
    }

    if (
      !Array.isArray(currentPurchase.items) ||
      currentPurchase.items.length === 0
    ) {
      setError(
        "Cannot receive this purchase because its saved item list is missing or invalid. No records were changed."
      );
      return;
    }

    const validPurchaseTotal = getKnownNonNegativeAmount(currentPurchase.total);
    const validInitialPayment = getKnownNonNegativeAmount(
      currentPurchase.initialPayment
    );
    let calculatedPurchaseTotal = 0;
    for (const item of currentPurchase.items) {
      if (!item || typeof item !== "object") {
        setError(
          "Cannot receive this purchase because one or more saved item records are invalid. No inventory or supplier credit was changed."
        );
        return;
      }
      const quantity = getKnownStockQuantity(item?.quantity);
      const unitCost = getKnownNonNegativeAmount(item.unitCost);
      const savedSellingPrice = getKnownNonNegativeAmount(item.sellingPrice);
      if (
        (item.category !== "Device" &&
          item.category !== "Accessory / spare part") ||
        typeof item.brand !== "string" ||
        !item.brand.trim() ||
        typeof item.model !== "string" ||
        !item.model.trim() ||
        !Array.isArray(item.identifiers) ||
        !item.identifiers.every(
          (identifier) =>
            typeof identifier === "string" && identifier.trim().length > 0
        ) ||
        quantity === null ||
        quantity <= 0 ||
        unitCost === null ||
        unitCost <= 0 ||
        savedSellingPrice === null ||
        !Number.isFinite(unitCost * quantity)
      ) {
        setError(
          "Cannot receive this purchase because one or more saved item quantities or amounts are invalid. No inventory or supplier credit was changed."
        );
        return;
      }

      if (
        item.category === "Accessory / spare part" &&
        item.identifiers.length > 1
      ) {
        setError(
          "Cannot receive this purchase because an accessory line has multiple identifiers. No records were changed."
        );
        return;
      }

      calculatedPurchaseTotal +=
        unitCost * quantity;
      if (!Number.isFinite(calculatedPurchaseTotal)) {
        setError(
          "Cannot receive this purchase because its total is outside the supported numeric range. No records were changed."
        );
        return;
      }
    }

    if (
      validPurchaseTotal === null ||
      validInitialPayment === null ||
      validPurchaseTotal !== calculatedPurchaseTotal ||
      validInitialPayment > validPurchaseTotal
    ) {
      setError(
        "Cannot receive this purchase because its saved total or initial payment does not match the validated item amounts. No records were changed."
      );
      return;
    }

    const purchaseCurrency = currentPurchase.currencyCode;

    const inventory = inventorySnapshot.records;
    const credits = creditSnapshot.records;
    const updatedInventory = [...inventory];
    let accessoryLinesSeparatedForUnknownStockData = 0;

    const existingIdentifiers = new Set<string>();
    for (const record of inventory) {
      const savedIdentifiers = [
        record.identifier,
        ...(Array.isArray(record.secondaryIdentifiers)
          ? record.secondaryIdentifiers
          : []),
      ];

      for (const identifier of savedIdentifiers) {
        const normalized = normalizeIdentifier(identifier);
        if (normalized) existingIdentifiers.add(normalized);
      }
    }

    const incomingIdentifiers = new Set<string>();

    // Validate all device identifiers before preparing any receipt changes.
    for (const item of currentPurchase.items) {
      if (item.category === "Device") {
        if (!Array.isArray(item.identifiers) || item.identifiers.length === 0) {
          setError(
            `Cannot receive this purchase because device line ${item.brand} ${item.model} has no identifiers. No stock was added.`
          );
          return;
        }

        if (
          !Number.isSafeInteger(item.quantity) ||
          item.quantity < 1 ||
          item.identifiers.length !== item.quantity
        ) {
          setError(
            `Cannot receive this purchase because device line ${item.brand} ${item.model} requires ${item.quantity} identifier(s), but has ${item.identifiers.length}. No stock was added.`
          );
          return;
        }

        for (const identifier of item.identifiers) {
          const normalized = normalizeIdentifier(identifier);

          if (!normalized) {
            setError(
              "Cannot receive this purchase because a device line has an empty identifier. No stock was added."
            );
            return;
          }

          if (existingIdentifiers.has(normalized)) {
            setError(
              `Cannot receive this purchase: identifier "${identifier}" already exists in inventory. No stock was added.`
            );
            return;
          }

          if (incomingIdentifiers.has(normalized)) {
            setError(
              `Cannot receive this purchase: identifier "${identifier}" appears more than once across its device lines. No stock was added.`
            );
            return;
          }

          incomingIdentifiers.add(normalized);
        }
      }
    }

    const alreadyLinked = credits.some(
      (credit) => credit.purchaseId === currentPurchase.id
    );

    if (alreadyLinked) {
      setError(
        "A supplier credit record already exists for this purchase. Please check the credit ledger before trying again."
      );
      return;
    }

    // Prepare inventory changes without saving them yet.
    for (const item of currentPurchase.items) {
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
            currencyCode: purchaseCurrency,
          });
        }
      } else {
        const sku = item.identifiers[0] || item.model;

        const matchesAccessory = (record: InventoryRecord) =>
          record.category === "Accessory / spare part" &&
          String(record.brand ?? "").toLowerCase() ===
            item.brand.toLowerCase() &&
          String(record.model ?? "").toLowerCase() ===
            item.model.toLowerCase() &&
          String(record.identifier || record.model || "").toLowerCase() ===
            sku.toLowerCase() &&
          record.status !== "Sold" &&
          isCurrencyCode(record.currencyCode) &&
          record.currencyCode === purchaseCurrency;

        const existingIndex = updatedInventory.findIndex((record) =>
          matchesAccessory(record) &&
          getKnownCostAmount(record.costPrice) !== null &&
          getKnownStockQuantity(record.quantity) !== null
        );

        if (
          existingIndex < 0 &&
          updatedInventory.some(
            (record) =>
              matchesAccessory(record) &&
              (getKnownCostAmount(record.costPrice) === null ||
                getKnownStockQuantity(record.quantity) === null)
          )
        ) {
          accessoryLinesSeparatedForUnknownStockData += 1;
        }

        if (existingIndex >= 0) {
          const existing = updatedInventory[existingIndex];
          const oldCost = getKnownCostAmount(existing.costPrice);
          const oldQuantity = getKnownStockQuantity(existing.quantity);

          if (oldCost !== null && oldQuantity !== null) {
            const newQuantity = oldQuantity + item.quantity;
            const oldTotalCost = oldCost * oldQuantity;
            const incomingTotalCost = item.unitCost * item.quantity;
            const combinedTotalCost = oldTotalCost + incomingTotalCost;
            if (
              !Number.isSafeInteger(newQuantity) ||
              !Number.isFinite(oldTotalCost) ||
              !Number.isFinite(incomingTotalCost) ||
              !Number.isFinite(combinedTotalCost) ||
              newQuantity <= 0
            ) {
              setError(
                "Cannot receive this purchase because the combined accessory stock quantity or cost is outside the supported numeric range. No records were changed."
              );
              return;
            }
            const weightedCost =
              combinedTotalCost / newQuantity;
            if (!Number.isFinite(weightedCost)) {
              setError(
                "Cannot receive this purchase because the weighted accessory cost is invalid. No records were changed."
              );
              return;
            }

            updatedInventory[existingIndex] = {
              ...existing,
              quantity: newQuantity,
              costPrice: String(weightedCost),
              sellingPrice: String(
                item.sellingPrice || existing.sellingPrice || 0
              ),
              status: "In shop",
              currencyCode: purchaseCurrency,
              updated: "Just now",
            };
            continue;
          }
        }

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
          currencyCode: purchaseCurrency,
        });
      }
    }

    // Prepare the supplier credit record.
    const creditRecord: CreditRecord = {
      id: `CREDIT-${Date.now()}`,
      type: "Payable",
      party: currentPurchase.supplier,
      contact: currentPurchase.supplierContact,
      reference: currentPurchase.invoiceReference || currentPurchase.id,
      description: `Stock purchase ${currentPurchase.id}`,
      originalAmount: currentPurchase.total,
      dueDate: currentPurchase.dueDate,
      createdAt: new Date().toISOString(),
      payments:
        currentPurchase.initialPayment > 0
          ? [
              {
                id: `PAY-${Date.now()}`,
                amount: currentPurchase.initialPayment,
                date: new Date().toISOString(),
              },
            ]
          : [],
      purchaseId: currentPurchase.id,
      currencyCode: purchaseCurrency,
    };

    const updatedCredits = [creditRecord, ...credits];

    // Prepare the updated purchase history.
    const updatedPurchases = latestPurchases.records.map((record) =>
      record.id === currentPurchase.id
        ? {
            ...record,
            status: "Received" as PurchaseStatus,
            receivedAt: new Date().toISOString(),
            currencyCode: purchaseCurrency,
          }
        : record
    );

    // localStorage has no multi-key transaction. Write each key in sequence
    // and attempt a cautious rollback if a later write fails.
    const result = saveStorageBatch([
      {
        key: INVENTORY_KEY,
        value: updatedInventory,
        expectedRaw: inventorySnapshot.raw,
      },
      {
        key: CREDIT_KEY,
        value: updatedCredits,
        expectedRaw: creditSnapshot.raw,
      },
      {
        key: PURCHASES_KEY,
        value: updatedPurchases,
        expectedRaw: latestPurchases.raw,
      },
    ]);

    if (!result.success) {
      if (result.conflict) {
        const currentPurchases = readStoredArray<PurchaseRecord>(PURCHASES_KEY);
        if (currentPurchases) {
          setPurchaseReadState(toStoredArrayReadState(currentPurchases));
        } else {
          setPurchaseReadState((current) =>
            current.readError ? current : { ...current, readError: true }
          );
        }
        setError(
          "Inventory, credit, or purchase records changed in another tab. The latest purchase history was loaded; review and try again."
        );
      } else if (result.rollbackSucceeded) {
        setError(
          "Stock receiving could not be completed because a storage save failed. Previous records were restored. Please try again."
        );
      } else {
        setError(
          "Stock receiving encountered a storage error, and restoring every previous record could not be confirmed. Please check Inventory, Supplier Credit, and Purchase History before trying again."
        );
      }

      return;
    }

    // Update the React interface only after all three saves succeed.
    setPurchaseReadState({
      records: updatedPurchases,
      hasValidSnapshot: true,
      readError: false,
    });
    setCreditReadState({
      records: updatedCredits,
      hasValidSnapshot: true,
      readError: false,
    });

    setMessage(
      `Stock received successfully. Inventory updated and supplier credit linked for ${currentPurchase.supplier} in ${purchaseCurrency}.${
        accessoryLinesSeparatedForUnknownStockData > 0
          ? ` ${accessoryLinesSeparatedForUnknownStockData} accessory line(s) were added as separate stock records because matching stock had invalid cost or quantity data; the existing records were preserved.`
          : ""
      }`
    );
  };

  const getPurchasePayment = (purchase: PurchaseRecord) => {
    if (creditReadState.readError || !creditReadState.hasValidSnapshot) {
      return null;
    }

    const linked = creditReadState.records.find(
      (credit) => credit.purchaseId === purchase.id
    );

    if (!linked) {
      const total = getKnownNonNegativeAmount(purchase.total);
      const paid = getKnownNonNegativeAmount(purchase.initialPayment);
      const outstanding = getKnownOutstandingBalance(total, paid);
      if (total === null || paid === null || outstanding === null) return null;
      return {
        paid,
        outstanding,
      };
    }

    const originalAmount = getKnownNonNegativeAmount(
      linked.originalAmount
    );
    const paid = (linked.payments ?? []).reduce<number | null>(
      (sum, payment) => {
        if (sum === null) return null;
        const updated = sum + payment.amount;
        return Number.isFinite(updated) ? updated : null;
      },
      0
    );
    const outstanding = getKnownOutstandingBalance(originalAmount, paid);
    if (originalAmount === null || paid === null || outstanding === null) {
      return null;
    }

    return {
      paid,
      outstanding,
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
          supplier balances in their original currencies.
        </p>
      </div>

      {purchaseReadState.readError && (
        <div
          role="alert"
          style={{
            padding: 12,
            borderRadius: 8,
            background: "rgba(239, 68, 68, 0.12)",
            color: "#f87171",
            fontSize: 13,
          }}
        >
          {purchaseReadState.hasValidSnapshot
            ? "Could not read the latest purchase history. Showing the last successfully loaded records; current counts and history may be out of date."
            : "Purchase history is unavailable because browser storage could not be read. Counts and purchase history cannot be verified."}
        </div>
      )}

      {creditReadState.readError && (
        <div
          role="alert"
          style={{
            padding: 12,
            borderRadius: 8,
            background: "rgba(239, 68, 68, 0.12)",
            color: "#f87171",
            fontSize: 13,
          }}
        >
          Supplier balances are unavailable because browser storage could not
          read the supplier-credit ledger.
        </div>
      )}

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
          <h2 style={{ margin: "8px 0 0" }}>
            {purchaseReadState.hasValidSnapshot ? purchases.length : "Unavailable"}
          </h2>
        </div>
        <div style={panelStyle}>
          <div style={{ color: "var(--muted, #a0a8b7)", fontSize: 12 }}>
            Draft purchases
          </div>
          <h2 style={{ margin: "8px 0 0" }}>
            {purchaseReadState.hasValidSnapshot ? draftCount : "Unavailable"}
          </h2>
        </div>
        <div style={panelStyle}>
          <div style={{ color: "var(--muted, #a0a8b7)", fontSize: 12 }}>
            Received purchases
          </div>
          <h2 style={{ margin: "8px 0 0" }}>
            {purchaseReadState.hasValidSnapshot ? receivedCount : "Unavailable"}
          </h2>
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
          Add the supplier invoice details, choose its currency, then add each
          product line.
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

          <label style={fieldStyle}>
            <span style={labelStyle}>Invoice currency *</span>
            <select
              style={inputStyle}
              value={invoiceCurrency}
              onChange={(event) => {
                setInvoiceCurrency(event.target.value);
                setInvoiceCurrencyManuallySelected(true);
                setInvoiceCurrencyNeedsReview(false);
                setError("");
                setMessage("");
              }}
            >
              <option value="" disabled>
                Select a currency
              </option>
              {CURRENCY_OPTIONS.map((currency) => (
                <option key={currency.code} value={currency.code}>
                  {currency.code} ({currency.decimalPlaces} decimal places)
                </option>
              ))}
            </select>
            <span
              style={{
                color: "var(--muted, #a0a8b7)",
                fontSize: 11,
              }}
            >
              {currencySettingsNotice ||
                "Defaults to your shop currency, but can be changed for each supplier invoice."}
            </span>
            {invoiceCurrencyNeedsReview && (
              <span
                style={{ color: "#fbbf24", fontSize: 11 }}
                role="status"
              >
                Shop currency changed. Review the entered amounts, then{" "}
                <button
                  type="button"
                  style={buttonStyle}
                  onClick={() => setInvoiceCurrencyNeedsReview(false)}
                >
                  confirm this currency
                </button>
              </span>
            )}
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
            <span style={labelStyle}>
              Unit purchase cost ({selectedCurrency || "select currency"}) *
            </span>
            <CurrencyInput
              style={inputStyle}
              value={itemForm.unitCost}
              onChange={(value) =>
                setItemForm((current) => ({
                  ...current,
                  unitCost: value,
                }))
              }
              currencyCode={selectedCurrency}
              placeholder="Enter purchase cost"
              required
              disabled={!selectedCurrency}
            />
          </label>

          <label style={fieldStyle}>
            <span style={labelStyle}>
              Unit selling price ({selectedCurrency || "select currency"})
            </span>
            <CurrencyInput
              style={inputStyle}
              value={itemForm.sellingPrice}
              onChange={(value) =>
                setItemForm((current) => ({
                  ...current,
                  sellingPrice: value,
                }))
              }
              currencyCode={selectedCurrency}
              placeholder="Enter selling price"
              disabled={!selectedCurrency}
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
              <table
                style={{
                  width: "100%",
                  borderCollapse: "collapse",
                  fontSize: 12,
                }}
              >
                <thead>
                  <tr
                    style={{
                      color: "var(--muted, #a0a8b7)",
                      textAlign: "left",
                    }}
                  >
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
                    <tr
                      key={item.id}
                      style={{
                        borderTop: "1px solid var(--border, #303744)",
                      }}
                    >
                      <td style={{ padding: 9 }}>
                        <strong>
                          {item.brand} {item.model}
                        </strong>
                        {item.identifiers.length > 0 && (
                          <div
                            style={{
                              color: "var(--muted, #a0a8b7)",
                              marginTop: 3,
                            }}
                          >
                            {item.identifiers.length} identifier(s)
                          </div>
                        )}
                      </td>
                      <td style={{ padding: 9 }}>
                        {item.category === "Device" ? "Device" : "Accessory"}
                      </td>
                      <td style={{ padding: 9 }}>{item.quantity}</td>
                      <td style={{ padding: 9 }}>
                        {selectedCurrency
                          ? formatCurrency(item.unitCost, selectedCurrency)
                          : "Currency unavailable"}
                      </td>
                      <td style={{ padding: 9 }}>
                        {selectedCurrency
                          ? formatCurrency(
                              item.quantity * item.unitCost,
                              selectedCurrency
                            )
                          : "Currency unavailable"}
                      </td>
                      <td style={{ padding: 9 }}>
                        <button
                          type="button"
                          onClick={() => removeItem(item.id)}
                          style={{
                            background: "transparent",
                            color: "#f87171",
                            border: 0,
                            cursor: "pointer",
                          }}
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
              <span
                style={{
                  color: "var(--muted, #a0a8b7)",
                  fontSize: 12,
                }}
              >
                Purchase total ({selectedCurrency || "currency unavailable"})
              </span>
              <h2 style={{ margin: "4px 0" }}>
                {selectedCurrency
                  ? formatCurrency(purchaseTotal, selectedCurrency)
                  : "Currency unavailable"}
              </h2>
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
          <span style={labelStyle}>
            Amount already paid ({selectedCurrency || "currency unavailable"})
          </span>
          <CurrencyInput
            style={inputStyle}
            value={initialPayment}
            onChange={setInitialPayment}
            currencyCode={selectedCurrency}
            placeholder="Enter amount paid"
            disabled={!selectedCurrency}
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

        {!purchaseReadState.hasValidSnapshot ? (
          <p style={{ color: "var(--muted, #a0a8b7)", fontSize: 13 }}>
            Purchase history is unavailable because browser storage could not be
            read.
          </p>
        ) : purchases.length === 0 ? (
          <p style={{ color: "var(--muted, #a0a8b7)", fontSize: 13 }}>
            {purchaseReadState.readError
              ? "No purchases were present in the last successful read; current history could not be verified."
              : "No purchases recorded yet."}
          </p>
        ) : (
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: 12,
              marginTop: 16,
            }}
          >
            {purchases.map((purchase) => {
              const payment = getPurchasePayment(purchase);
              const purchaseCurrency = isCurrencyCode(purchase.currencyCode)
                ? purchase.currencyCode
                : null;
              const formatPurchaseAmount = (value: unknown) => {
                const amount = getKnownNonNegativeAmount(value);
                if (amount === null) return "Amount unavailable";
                return formatCurrency(amount, purchaseCurrency);
              };

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
                      <div
                        style={{
                          color: "var(--muted, #a0a8b7)",
                          fontSize: 11,
                          marginTop: 4,
                        }}
                      >
                        {purchase.invoiceReference || purchase.id} ·{" "}
                        {purchase.purchaseDate}
                      </div>
                    </div>
                    <div style={{ textAlign: "right" }}>
                      <strong>
                        {formatPurchaseAmount(purchase.total)}
                      </strong>
                      <div
                        style={{
                          fontSize: 11,
                          marginTop: 4,
                          color:
                            purchase.status === "Received"
                              ? "#4ade80"
                              : "#fbbf24",
                        }}
                      >
                        {purchase.status} · {purchaseCurrency || "currency unavailable"}
                      </div>
                    </div>
                  </div>

                  <div
                    style={{
                      marginTop: 12,
                      fontSize: 12,
                      color: "var(--muted, #a0a8b7)",
                    }}
                  >
                    {purchase.items.map((item) => (
                      <div key={item.id} style={{ padding: "3px 0" }}>
                        {item.brand} {item.model} — {item.quantity} ×{" "}
                        {formatPurchaseAmount(item.unitCost)}
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
                    <span>
                      Paid: {payment ? formatPurchaseAmount(payment.paid) : "Unavailable"}
                    </span>
                    <span>
                      Outstanding:{" "}
                      {payment
                        ? formatPurchaseAmount(payment.outstanding)
                        : "Unavailable"}
                    </span>
                  </div>

                  {purchase.status === "Draft" ? (
                    <button
                      type="button"
                      style={{ ...buttonStyle, marginTop: 14 }}
                      onClick={() => receivePurchase(purchase)}
                    >
                      <PackageCheck
                        size={15}
                        style={{
                          verticalAlign: "middle",
                          marginRight: 6,
                        }}
                      />
                      Confirm stock received
                    </button>
                  ) : (
                    <div
                      style={{
                        color: "#4ade80",
                        fontSize: 11,
                        marginTop: 12,
                      }}
                    >
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
