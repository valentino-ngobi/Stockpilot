
import { useEffect, useMemo, useState } from "react";
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
  getShopSettingsSnapshot,
  SETTINGS_STORAGE_KEY,
  saveShopSettings,
  type CurrencyCode,
} from "../utils/currency";

function getRecoverableShopName(
  snapshot: ReturnType<typeof getShopSettingsSnapshot>,
): string {
  if (snapshot.status === "valid" || snapshot.status === "missing") {
    return snapshot.settings.shopName;
  }

  const savedShopName =
    snapshot.status === "invalid"
      ? snapshot.storedFields?.shopName
      : undefined;

  return typeof savedShopName === "string" && savedShopName.trim()
    ? savedShopName
    : "";
}

export default function Settings() {
  const [savedSnapshot, setSavedSnapshot] = useState(
    () => getShopSettingsSnapshot()
  );

  const [shopName, setShopName] = useState(
    () => getRecoverableShopName(savedSnapshot)
  );

  const [currencyCode, setCurrencyCode] = useState<CurrencyCode>(
    () =>
      savedSnapshot.status === "valid" || savedSnapshot.status === "missing"
        ? savedSnapshot.settings.currencyCode
        : ""
  );

  const [currencySearch, setCurrencySearch] = useState("");
  const [notice, setNotice] = useState(() =>
    savedSnapshot.status === "invalid" || savedSnapshot.status === "unavailable"
      ? savedSnapshot.message
      : ""
  );
  const [hasUnsavedChanges, setHasUnsavedChanges] = useState(false);
  const [currencyExplicitlySelected, setCurrencyExplicitlySelected] =
    useState(
      () =>
        savedSnapshot.status === "valid" ||
        savedSnapshot.status === "missing"
    );

  useEffect(() => {
    const refreshSettings = (event?: StorageEvent) => {
      if (
        event &&
        event.key !== SETTINGS_STORAGE_KEY &&
        event.key !== null
      ) {
        return;
      }

      const latest = getShopSettingsSnapshot();

      if (hasUnsavedChanges) {
        if (
          latest.raw !== savedSnapshot.raw ||
          latest.status !== savedSnapshot.status
        ) {
          setNotice(
            "Settings changed in another tab. Your unsaved values are kept until you save or review the latest settings."
          );
        }
        return;
      }

      setSavedSnapshot((current) =>
        JSON.stringify(current) === JSON.stringify(latest)
          ? current
          : latest
      );

      if (latest.status === "valid" || latest.status === "missing") {
        setShopName(latest.settings.shopName);
        setCurrencyCode(latest.settings.currencyCode);
        setCurrencyExplicitlySelected(false);
        setNotice("");
      } else {
        setShopName(getRecoverableShopName(latest));
        setCurrencyCode("");
        setCurrencyExplicitlySelected(false);
        setNotice(latest.message);
      }
    };
    const refreshOnFocus = () => refreshSettings();

    window.addEventListener("storage", refreshSettings);
    window.addEventListener("focus", refreshOnFocus);
    return () => {
      window.removeEventListener("storage", refreshSettings);
      window.removeEventListener("focus", refreshOnFocus);
    };
  }, [hasUnsavedChanges, savedSnapshot]);

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

  const getSettingsEditNotice = (
    currencySelected = currencyExplicitlySelected
  ) => {
    if (savedSnapshot.status === "invalid") {
      return currencySelected
        ? `${savedSnapshot.message} The saved value is unchanged; click Save to replace it with these valid settings.`
        : `${savedSnapshot.message} The saved value is unchanged; choose a currency explicitly before saving.`;
    }

    if (savedSnapshot.status === "unavailable") {
      return savedSnapshot.message;
    }

    return "";
  };

  const handleSave = () => {
    const cleanedName = shopName.trim();

    if (!cleanedName) {
      setNotice(
        savedSnapshot.status === "invalid" &&
          !getRecoverableShopName(savedSnapshot)
          ? "The saved shop name could not be recovered safely. Enter the shop name manually before saving."
          : "Enter a shop name before saving."
      );
      return;
    }

    if (savedSnapshot.status === "invalid") {
      if (!currencyExplicitlySelected) {
        setNotice(
          `${savedSnapshot.message} Choose a currency explicitly to repair it; saved settings have not been changed.`
        );
        return;
      }
    }

    if (savedSnapshot.status === "unavailable") {
      setNotice(
        `${savedSnapshot.message} No changes were made; check browser storage before trying again.`
      );
      return;
    }

    const settingsToSave = {
      shopName: cleanedName,
      currencyCode,
    };
    const saveResult = saveShopSettings(
      settingsToSave,
      savedSnapshot.raw,
      savedSnapshot.status === "invalid" && currencyExplicitlySelected
    );

    if (saveResult === "conflict") {
      const latest = getShopSettingsSnapshot();

      setSavedSnapshot(latest);
      setHasUnsavedChanges(false);

      if (latest.status === "valid" || latest.status === "missing") {
        setShopName(latest.settings.shopName);
        setCurrencyCode(latest.settings.currencyCode);
        setCurrencyExplicitlySelected(false);
        setNotice(
          "Settings changed in another tab. The latest saved values were loaded; review them and save again if needed."
        );
      } else {
        setShopName(getRecoverableShopName(latest));
        setCurrencyCode("");
        setCurrencyExplicitlySelected(false);
        setNotice(
          `${latest.message} The latest settings could not be loaded, and no settings were overwritten. Repair the saved value before trying again.`
        );
      }
      return;
    }

    if (saveResult === "invalid") {
      const latest = getShopSettingsSnapshot();
      setSavedSnapshot(latest);
      setHasUnsavedChanges(false);
      if (latest.status === "invalid") {
        setShopName(getRecoverableShopName(latest));
        setCurrencyCode("");
      }
      setCurrencyExplicitlySelected(false);
      setNotice(
        latest.status === "invalid"
          ? `${latest.message} No changes were made.`
          : "Saved settings are invalid. No changes were made; reload and review Workspace settings."
      );
      return;
    }

    if (saveResult === "error") {
      setNotice("Could not save shop settings. Check available browser storage.");
      return;
    }

    const storedFields = {
      ...(savedSnapshot.status === "valid" || savedSnapshot.status === "invalid"
        ? savedSnapshot.storedFields ?? {}
        : {}),
      ...settingsToSave,
    };

    setSavedSnapshot({
      status: "valid",
      raw: JSON.stringify(storedFields),
      settings: settingsToSave,
      storedFields,
    });
    setHasUnsavedChanges(false);
    setCurrencyExplicitlySelected(false);
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
                    setHasUnsavedChanges(true);
                    setNotice(getSettingsEditNotice());
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
                    setNotice(getSettingsEditNotice());
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
                  setCurrencyExplicitlySelected(true);
                  setHasUnsavedChanges(true);
                  setNotice(getSettingsEditNotice(true));
                }}
              >
                {filteredCurrencies.length > 0 && currencyCode === "" && (
                  <option value="" disabled>
                    Select a currency to repair settings
                  </option>
                )}
                {filteredCurrencies.length === 0 ? (
                  <option value={currencyCode} disabled>
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
