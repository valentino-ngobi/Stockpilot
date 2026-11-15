
import { useState } from "react";
import {
  Building2,
  CheckCircle2,
  Save,
  Settings2,
  ShieldCheck,
} from "lucide-react";
import {
  CURRENCY_OPTIONS,
  getShopSettings,
  saveShopSettings,
  type CurrencyCode,
} from "../utils/currency";

export default function Settings() {
  const [shopName, setShopName] = useState(
    () => getShopSettings().shopName
  );

  const [currencyCode, setCurrencyCode] = useState<CurrencyCode>(
    () => getShopSettings().currencyCode
  );

  const [notice, setNotice] = useState("");

  const handleSave = () => {
    const cleanedName = shopName.trim();

    if (!cleanedName) {
      setNotice("Enter a shop name before saving.");
      return;
    }

    saveShopSettings({
      shopName: cleanedName,
      currencyCode,
    });

    setShopName(cleanedName);
    setNotice("Shop settings saved successfully.");
  };

  return (
    <section className="operations-page page-content">
      <div className="eyebrow">
        <span className="eyebrow-line" /> PREFERENCES & CONTROLS
      </div>

      <div className="operations-heading">
        <div>
          <h1>Workspace settings</h1>
          <p className="page-subtitle">
            Manage your shop identity and default financial currency.
          </p>
        </div>

        <div className="operations-heading-icon">
          <Settings2 size={22} />
        </div>
      </div>

      <div className="operations-grid">
        <section className="surface-card operations-form-card">
          <div className="card-kicker">SHOP CONFIGURATION</div>
          <h2>Business preferences</h2>

          <div className="operations-form">
            <label className="inventory-field">
              <span>Shop name</span>
              <div className="identifier-input-wrap">
                <Building2 size={17} />
                <input
                  type="text"
                  value={shopName}
                  onChange={(event) => {
                    setShopName(event.target.value);
                    setNotice("");
                  }}
                  placeholder="Enter your shop name"
                  maxLength={80}
                />
              </div>
            </label>

            <label className="inventory-field">
              <span>Default operating currency</span>
              <select
                value={currencyCode}
                onChange={(event) => {
                  setCurrencyCode(
                    event.target.value as CurrencyCode
                  );
                  setNotice("");
                }}
              >
                {CURRENCY_OPTIONS.map((currency) => (
                  <option key={currency.code} value={currency.code}>
                    {currency.label}
                  </option>
                ))}
              </select>
              <small className="field-hint">
                This currency will be used for new financial records.
                Existing records keep their original currency.
              </small>
            </label>
          </div>

          {notice && (
            <div
              className={`inventory-notice ${
                notice.includes("successfully")
                  ? "notice-success"
                  : "notice-warning"
              }`}
              role="status"
            >
              {notice.includes("successfully") ? (
                <CheckCircle2 size={16} />
              ) : (
                <ShieldCheck size={16} />
              )}
              {notice}
            </div>
          )}

          <button
            className="button button-primary"
            onClick={handleSave}
          >
            <Save size={16} />
            Save settings
          </button>

          <p className="inventory-disclaimer">
            Settings are currently stored in this browser. They are
            not yet synchronised between users or devices.
          </p>
        </section>

        <section className="surface-card operations-list-card">
          <div className="inventory-card-heading">
            <div>
              <div className="card-kicker">CURRENCY STANDARD</div>
              <h2>Supported currencies</h2>
            </div>
            <Building2 size={19} />
          </div>

          <div className="operations-record-list">
            {CURRENCY_OPTIONS.map((currency) => (
              <article
                className="operations-record"
                key={currency.code}
              >
                <div className="operations-record-icon">
                  <Building2 size={17} />
                </div>

                <div className="operations-record-copy">
                  <strong>{currency.code}</strong>
                  <span>{currency.label}</span>
                </div>

                <span className="inventory-device-status status-available">
                  {currency.decimalPlaces} decimals
                </span>
              </article>
            ))}
          </div>

          <div className="operations-note">
            <ShieldCheck size={16} />
            <span>
              UGX uses whole amounts, USD uses two decimal places,
              and KWD uses three. Financial reports must keep
              different currencies separate unless an explicit
              exchange-rate conversion is implemented.
            </span>
          </div>
        </section>
      </div>
    </section>
  );
}
