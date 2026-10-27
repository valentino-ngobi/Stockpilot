import { useCallback, useMemo, useState } from "react";
import {
  ArrowDownToLine,
  ArrowUpFromLine,
  Barcode,
  CheckCircle2,
  ClipboardList,
  PackagePlus,
  Search,
  ScanLine,
  ShieldCheck,
  Smartphone,
  XCircle,
} from "lucide-react";
import CameraScanner from "../components/CameraScanner";

type Movement = "Receive stock" | "Record stock movement";
type IdentifierField = "imei1" | "imei2" | "serial";
type DeviceRecord = {
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
  category?: "Device" | "Accessory / spare part";
  quantity?: number;
  secondaryIdentifiers?: string[];
  updated: string;
};

const initialDevices: DeviceRecord[] = [
  { id: "1", brand: "Apple", model: "iPhone 15 · 128 GB", identifier: "DEMO-IMEI-001", status: "In shop", updated: "Today, 09:12" },
  { id: "2", brand: "Samsung", model: "Galaxy A15 · 128 GB", identifier: "DEMO-IMEI-002", status: "With middle-man", updated: "Today, 08:44" },
  { id: "3", brand: "Tecno", model: "Spark 20 · 256 GB", identifier: "DEMO-IMEI-003", status: "At repairer", updated: "Yesterday" },
];

export default function Inventory() {
  const [movement, setMovement] = useState<Movement>("Receive stock");
  const [brand, setBrand] = useState("Apple");
  const [model, setModel] = useState("");
  const [colour, setColour] = useState("");
  const [storage, setStorage] = useState("128 GB");
  const [networkStatus, setNetworkStatus] = useState("Unlocked");
  const [condition, setCondition] = useState("Brand New");
  const [costPrice, setCostPrice] = useState("");
  const [sellingPrice, setSellingPrice] = useState("");
  const [category, setCategory] = useState<"Device" | "Accessory / spare part">("Device");
  const [quantity, setQuantity] = useState("1");
  const [imei1, setImei1] = useState("");
  const [imei2, setImei2] = useState("");
  const [serial, setSerial] = useState("");
  const [targetField, setTargetField] = useState<IdentifierField>("imei1");
  const [scannerOpen, setScannerOpen] = useState(false);
  const [status, setStatus] = useState("In shop");
  const [search, setSearch] = useState("");
  const [notice, setNotice] = useState("");
  const [devices, setDevices] = useState(initialDevices);

  const setIdentifier = useCallback((value: string) => {
    if (targetField === "imei1") setImei1(value);
    if (targetField === "imei2") setImei2(value);
    if (targetField === "serial") setSerial(value);
  }, [targetField]);

  const filteredDevices = useMemo(() => devices.filter((device) =>
    `${device.brand} ${device.model} ${device.identifier} ${device.status}`.toLowerCase().includes(search.toLowerCase())
  ), [devices, search]);

  const handleSave = () => {
    const identifier = imei1.trim() || serial.trim() || imei2.trim() || (category === "Accessory / spare part" ? model.trim() : "");
    if (!identifier) {
      setNotice(category === "Device" ? "Enter an IMEI or serial number, or scan a barcode first." : "Enter an accessory name/model or SKU/barcode.");
      return;
    }
    if (category === "Device" && imei1.trim() && !/^\d{15}$/.test(imei1.trim())) {
      setNotice("IMEI 1 should contain 15 digits. Check the number or use the serial-number field if this is not an IMEI.");
      return;
    }
    if (category === "Device" && imei2.trim() && !/^\d{15}$/.test(imei2.trim())) {
      setNotice("IMEI 2 should contain 15 digits. Leave it blank if this device has only one IMEI.");
      return;
    }

    const suppliedIdentifiers = [imei1.trim(), imei2.trim(), serial.trim(), identifier].filter(Boolean);
    const matchedDevice = devices.find((device) => [device.identifier, ...(device.secondaryIdentifiers ?? [])].some((existing) => suppliedIdentifiers.some((value) => existing.toLowerCase() === value.toLowerCase())));

    if (movement === "Record stock movement") {
      if (!matchedDevice) {
        setNotice("No matching device was found in the demo inventory. Receive the device into stock first, or check the identifier.");
        return;
      }
      setDevices((current) =>
  current.map((device) =>
    device.id === matchedDevice.id
      ? {
          ...device,
          status: status as DeviceRecord["status"],
          updated: "Just now",
        }
      : device
  )
);
      setNotice(`Demo movement recorded for ${matchedDevice.brand} ${matchedDevice.model}: ${status}.`);
      setImei1("");
      setImei2("");
      setSerial("");
      return;
    }

    const duplicate = devices.some((device) => [device.identifier, ...(device.secondaryIdentifiers ?? [])].some((existing) => suppliedIdentifiers.some((value) => existing.toLowerCase() === value.toLowerCase())));
    if (duplicate) {
      setNotice("This identifier already exists in the demo list. Review the existing device before adding another record.");
      return;
    }
    const record: DeviceRecord = {
      id: `${Date.now()}`,
      brand: brand.trim() || "Unknown brand",
      model: model.trim() || "Model not specified",
      identifier,
      status: "In shop",
      colour: colour.trim() || undefined,
      storage: category === "Device" ? storage : undefined,
      networkStatus: category === "Device" ? networkStatus : undefined,
      condition,
      costPrice: costPrice.trim() || undefined,
      sellingPrice: sellingPrice.trim() || undefined,
      category,
      quantity: category === "Accessory / spare part" ? Math.max(1, Number.parseInt(quantity, 10) || 1) : 1,
      secondaryIdentifiers: [imei1.trim(), imei2.trim(), serial.trim()].filter((value) => value && value !== identifier),
      updated: "Just now",
    };
    setDevices((current) => [record, ...current]);
    setNotice("Demo device added to the inventory list.");
    setBrand("Apple");
    setModel("");
    setColour("");
    setStorage("128 GB");
    setNetworkStatus("Unlocked");
    setCondition("Brand New");
    setCostPrice("");
    setSellingPrice("");
    setCategory("Device");
    setQuantity("1");
    setImei1("");
    setImei2("");
    setSerial("");
  };

  return (
    <section className="inventory-page page-content">
      <div className="welcome-row inventory-welcome">
        <div>
          <div className="eyebrow"><span className="eyebrow-line" /> INVENTORY CONTROL</div>
          <h1>Device inventory</h1>
          <p className="page-subtitle">Receive, identify and track individual devices from one place.</p>
        </div>
        <div className="inventory-status-chip"><span /> Demo workspace · sample data only</div>
      </div>

      <div className="inventory-info-banner surface-card">
        <div className="inventory-info-icon"><ShieldCheck size={19} /></div>
        <div><strong>Scan or type — your choice</strong><p>Camera scanning is optional. You can enter identifiers manually whenever a barcode is unavailable or the camera cannot be used.</p></div>
      </div>

      <div className="inventory-layout">
        <section className="surface-card inventory-entry-card">
          <div className="inventory-card-heading">
            <div><div className="card-kicker">DEVICE WORKFLOW</div><h2>Add a device or record movement</h2></div>
            <div className="inventory-heading-icon"><PackagePlus size={19} /></div>
          </div>

          <div className="inventory-mode-switch" role="tablist" aria-label="Stock operation">
            <button className={movement === "Receive stock" ? "is-active" : ""} onClick={() => { setMovement("Receive stock"); setNotice(""); }} role="tab" aria-selected={movement === "Receive stock"}><ArrowDownToLine size={16} /> Receive stock</button>
            <button className={movement === "Record stock movement" ? "is-active" : ""} onClick={() => { setMovement("Record stock movement"); setNotice(""); }} role="tab" aria-selected={movement === "Record stock movement"}><ArrowUpFromLine size={16} /> Record movement</button>
          </div>

          <div className="inventory-form-grid">
            {movement === "Receive stock" && <>
              <label className="inventory-field inventory-field-wide"><span>Stock type</span><select value={category} onChange={(event) => setCategory(event.target.value as "Device" | "Accessory / spare part")}><option value="Device">Serialized phone / device</option><option value="Accessory / spare part">Accessory / spare part</option></select></label>
              <label className="inventory-field"><span>Brand</span><select value={brand} onChange={(event) => setBrand(event.target.value)}><option>Apple</option><option>Samsung</option><option>Tecno</option><option>Infinix</option><option>Xiaomi</option><option>Other / unknown</option></select></label>
              <label className="inventory-field"><span>Model / part number <em>Optional lookup</em></span><input value={model} onChange={(event) => setModel(event.target.value)} placeholder="e.g. iPhone 17 or MG6C4AH/A" /><small className="field-hint">Lookup is optional. If unavailable or offline, enter details manually. Live catalogue lookup is not connected yet.</small></label>
              <label className="inventory-field"><span>Colour <em>Optional</em></span><input value={colour} onChange={(event) => setColour(event.target.value)} placeholder="e.g. Black" /></label>
              {category === "Accessory / spare part" && <label className="inventory-field"><span>Quantity received</span><input value={quantity} onChange={(event) => setQuantity(event.target.value)} placeholder="e.g. 10" inputMode="numeric" /></label>}
              {category === "Device" && <>
                <label className="inventory-field"><span>Storage capacity</span><select value={storage} onChange={(event) => setStorage(event.target.value)}><option>64 GB</option><option>128 GB</option><option>256 GB</option><option>512 GB</option><option>1 TB</option><option>Other / unknown</option></select></label>
                <label className="inventory-field"><span>Network status</span><select value={networkStatus} onChange={(event) => setNetworkStatus(event.target.value)}><option>Unlocked</option><option>Network locked</option><option>Unknown</option><option>Not applicable</option></select></label>
              </>}
              <label className="inventory-field"><span>Condition / grade</span><select value={condition} onChange={(event) => setCondition(event.target.value)}><option>Brand New</option><option>Refurbished</option><option>Used - Grade A</option><option>Used - Grade B</option><option>Used - Grade C</option><option>Needs inspection</option></select></label>
              <label className="inventory-field"><span>Cost price (owner-only later)</span><input value={costPrice} onChange={(event) => setCostPrice(event.target.value)} placeholder="Optional amount" inputMode="decimal" /></label>
              <label className="inventory-field"><span>Approved selling price</span><input value={sellingPrice} onChange={(event) => setSellingPrice(event.target.value)} placeholder="Optional amount" inputMode="decimal" /></label>
            </>}

            {movement === "Record stock movement" && <label className="inventory-field inventory-field-wide"><span>Movement type</span><select value={status} onChange={(event) => setStatus(event.target.value)}><option value="Sold">Sold to customer</option><option value="With middle-man">Handed to middle-man</option><option value="At repairer">Sent to repairer</option><option value="In shop">Returned to shop</option></select></label>}

            <div className="inventory-field inventory-field-wide">
              <span>{category === "Device" ? "Unique device identifier" : "Item identifier"} <em>{category === "Device" ? "IMEI or serial" : "SKU or barcode optional"}</em></span>
              <div className="scan-target-row">
                <button className={targetField === "imei1" ? "scan-target is-selected" : "scan-target"} onClick={() => setTargetField("imei1")}>IMEI 1</button>
                <button className={targetField === "imei2" ? "scan-target is-selected" : "scan-target"} onClick={() => setTargetField("imei2")}>IMEI 2</button>
                <button className={targetField === "serial" ? "scan-target is-selected" : "scan-target"} onClick={() => setTargetField("serial")}>Serial number</button>
              </div>
              <div className="identifier-input-row">
                <div className="identifier-input-wrap"><Barcode size={17} /><input value={targetField === "imei1" ? imei1 : targetField === "imei2" ? imei2 : serial} onChange={(event) => setIdentifier(event.target.value)} placeholder={targetField === "serial" ? "Type serial number" : "Type 15-digit IMEI"} inputMode={targetField === "serial" ? "text" : "numeric"} /></div>
                <button className="button button-secondary scan-open-button" onClick={() => setScannerOpen(true)}><ScanLine size={16} /> Scan</button>
              </div>
              <p className="field-hint">{category === "Device" ? "For IMEI, check the number after scanning. Most IMEIs contain 15 digits; serial numbers vary by manufacturer." : "Accessories do not need an IMEI. Enter a SKU/barcode if available, or use the product name/model above."}</p>
            </div>

            {movement === "Receive stock" && category === "Device" && <label className="inventory-field inventory-field-wide"><span>Second IMEI <em>Optional</em></span><input value={imei2} onChange={(event) => setImei2(event.target.value)} onFocus={() => setTargetField("imei2")} placeholder="For dual-IMEI devices, enter or scan IMEI 2" inputMode="numeric" /></label>}
          </div>

          {notice && <div className={`inventory-notice ${notice.includes("added") || notice.includes("recorded") ? "notice-success" : "notice-warning"}`} role="status">{notice.includes("added") || notice.includes("recorded") ? <CheckCircle2 size={16} /> : <XCircle size={16} />}{notice}</div>}

          <div className="inventory-form-actions">
            <span><ShieldCheck size={14} /> Duplicate identifier check in this demo</span>
            <button className="button button-primary" onClick={handleSave}>{movement === "Receive stock" ? <><PackagePlus size={16} /> Add device</> : <><ClipboardList size={16} /> Record movement</>}</button>
          </div>
          <p className="inventory-disclaimer">Prototype only: entries live in temporary page state and disappear on refresh. Secure storage, shop-wide duplicate checks and offline sync are not connected yet.</p>
        </section>

        <section className="surface-card inventory-list-card">
          <div className="inventory-card-heading">
            <div><div className="card-kicker">STOCK REGISTER</div><h2>Recently updated devices</h2></div>
            <span className="inventory-count">{devices.length} demo records</span>
          </div>
          <label className="inventory-list-search"><Search size={16} /><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search model, identifier or status" /></label>
          <div className="inventory-device-list">
            {filteredDevices.length === 0 ? <div className="inventory-empty"><Smartphone size={24} /><strong>No matching devices</strong><span>Try another search or add a demo record.</span></div> : filteredDevices.map((device) => (
              <article className="inventory-device-row" key={device.id}>
                <div className="inventory-device-icon"><Smartphone size={18} /></div>
                <div className="inventory-device-copy"><strong>{device.brand} {device.model}</strong><span className="inventory-identifier">{device.identifier}</span><span className="inventory-device-updated">{[device.category === "Accessory / spare part" ? `Qty ${device.quantity ?? 1}` : device.storage, device.colour, device.condition, device.networkStatus].filter(Boolean).join(" · ")}</span><span className="inventory-device-updated">{device.updated}</span></div>
                <span className={`inventory-device-status status-${device.status === "In shop" ? "available" : device.status === "Sold" ? "sold" : device.status === "At repairer" ? "repair" : "custody"}`}>{device.status}</span>
              </article>
            ))}
          </div>
          <div className="inventory-list-footer"><span><span className="inventory-footer-dot" /> Sample records only</span><span>Private identifiers should never be shown in a public demo.</span></div>
        </section>
      </div>
      {scannerOpen && <CameraScanner onClose={() => setScannerOpen(false)} onDetected={setIdentifier} title={`Scan ${targetField === "serial" ? "serial number" : targetField === "imei2" ? "IMEI 2" : "IMEI 1"}`} />}
    </section>
  );
}
