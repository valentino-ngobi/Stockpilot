
import { useMemo, useState } from "react";
import {
  Building2,
  CheckCircle2,
  Save,
  Search,
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

  const [currencySearch, setCurrencySearch] = useState("");
  const [notice, setNotice] = useState("");

  const filteredCurrencies = useMemo(() => {
    const search = currencySearch.trim().toLowerCase();

    if (!search) {
      return CURRENCY_OPTIONS;
    }

    return CURRENCY_OPTIONS.filter((currency) =>
      currency.code.toLowerCase().includes(search)
    );
  }, [currencySearch]);

  const selectedCurrency = CURRENCY_OPTIONS.find(
    (currency) => currency.code === currencyCode
  );

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
        <span className="eyebrow-line" />
        PREFERENCES &amp; CONTROLS
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
              <span>Search currencies</span>

              <div className="identifier-input-wrap">
                <Search size={17} />

                <input
                  type="text"
                  value={currencySearch}
                  onChange={(event) => {
                    setCurrencySearch(event.target.value);
                    setNotice("");
                  }}
                  placeholder="Search by code, e.g. AED or CNY"
                />
              </div>
            </label>

            <label className="inventory-field">
              <span>Default operating currency</span>

              <select
                value={currencyCode}
                onChange={(event) => {
                  setCurrencyCode(event.target.value);
                  setNotice("");
                }}
              >
                {filteredCurrencies.length === 0 ? (
                  <option value={currencyCode}>
                    No matching currencies
                  </option>
                ) : (
                  filteredCurrencies.map((currency) => (
                    <option
                      key={currency.code}
                      value={currency.code}
                    >
                      {currency.code} — {currency.decimalPlaces} decimal places
                    </option>
                  ))
                )}
              </select>

              <small className="field-hint">
                Search using a three-letter currency code. Your selected
                currency becomes the default for new shop transactions.
              </small>

              {filteredCurrencies.length === 0 && (
                <small className="field-hint">
                  No matching currency found. Try another code.
                </small>
              )}
            </label>
          </div>

          <div className="operations-note">
            <ShieldCheck size={16} />
            <span>
              Current selection: {selectedCurrency?.code || currencyCode}.
              Existing transactions retain their original currency.
            </span>
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
              <h2>Currency information</h2>
            </div>
            <Building2 size={19} />
          </div>

          <div className="operations-record-list">
            <article className="operations-record">
              <div className="operations-record-icon">
                <Building2 size={17} />
              </div>

              <div className="operations-record-copy">
                <strong>{currencyCode}</strong>
                <span>Selected operating currency</span>
              </div>

              <span className="inventory-device-status status-available">
                {selectedCurrency?.decimalPlaces ?? 2} decimals
              </span>
            </article>

            <article className="operations-record">
              <div className="operations-record-icon">
                <ShieldCheck size={17} />
              </div>

              <div className="operations-record-copy">
                <strong>{CURRENCY_OPTIONS.length} currencies</strong>
                <span>Available in this browser</span>
              </div>
            </article>
          </div>

          <div className="operations-note">
            <ShieldCheck size={16} />
            <span>
              Currency precision is determined automatically. For example,
              UGX and JPY use zero decimal places, USD uses two, and KWD
              uses three. Live exchange-rate conversion will be added
              separately.
            </span>
          </div>
        </section>
      </div>
    </section>
  );
}
