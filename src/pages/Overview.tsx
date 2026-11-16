
import { useMemo, useState, useEffect } from "react";
import MetricCard from "../components/MetricCard";
import {
  convertToSnapshotCurrency,
  formatCurrency,
  getRecordCurrency,
  getSavedExchangeRateSnapshot,
  getShopCurrency,
  refreshExchangeRateSnapshot,
} from "../utils/currency";

import type {
  CurrencyCode,
  ExchangeRateSnapshot,
} from "../utils/currency";
import {
  ArrowRight,
  ArrowUpRight,
  CalendarDays,
  CircleAlert,
  Clock3,
  Download,
  Plus,
  ReceiptText,
  Smartphone,
  Wallet,
  Boxes as BoxesIcon,
  Wrench as WrenchIcon,
  Package,
  ShoppingCart,
} from "lucide-react";
import type { PageKey } from "../components/Sidebar";
interface OverviewProps {
  onNavigate: (page: PageKey) => void;
}

type InventoryRecord = {
  id: string;
  brand: string;
  model: string;
  identifier: string;
  status: "In shop" | "With middle-man" | "At repairer" | "Sold";
  colour?: string;
  storage?: string;
  costPrice?: string;
  sellingPrice?: string;
  currencyCode?: CurrencyCode;
  category?: "Device" | "Accessory / spare part";
  quantity?: number;
  updated: string;
};

type SaleRecord = {
  id: string;
  deviceId: string;
  deviceName: string;
  identifier: string;
  salePrice: number;
  paymentMethod: string;
  transactionDate: string;
  costPrice: number;
  currencyCode?: CurrencyCode;
  costCurrencyCode?: CurrencyCode;
};

const INVENTORY_KEY = "stockpilot-inventory";
const SALES_KEY = "stockpilot-sales";

function readInventory(): InventoryRecord[] {
  try {
    const saved = localStorage.getItem(INVENTORY_KEY);
    return saved ? JSON.parse(saved) as InventoryRecord[] : [];
  } catch (error) {
    console.error("Could not read inventory:", error);
    return [];
  }
}

function readSales(): SaleRecord[] {
  try {
    const saved = localStorage.getItem(SALES_KEY);
    return saved ? JSON.parse(saved) as SaleRecord[] : [];
  } catch (error) {
    console.error("Could not read sales:", error);
    return [];
  }
}

function formatMoney(
  amount: number,
  currencyCode: CurrencyCode = getShopCurrency()
): string {
  return formatCurrency(amount, currencyCode);
}
function convertOverviewAmount(
  amount: number,
  sourceCurrency: CurrencyCode,
  snapshot: ExchangeRateSnapshot | null,
  targetCurrency: CurrencyCode
): number | null {
  if (sourceCurrency === targetCurrency) {
    return amount;
  }

  if (!snapshot) {
    return null;
  }

  return convertToSnapshotCurrency(
    amount,
    sourceCurrency,
    snapshot
  );
}

function localDateKey(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function formatCompact(amount: number): string {
  if (amount >= 1_000_000) {
    return `${(amount / 1_000_000).toFixed(1)}M`;
  }

  if (amount >= 1_000) {
    return `${(amount / 1_000).toFixed(0)}K`;
  }

  return String(Math.round(amount));
}

function getStatusClass(status: InventoryRecord["status"]): string {
  if (status === "In shop") return "available";
  if (status === "With middle-man") return "custody";
  if (status === "At repairer") return "repair";
  return "sold";
}

export default function Overview({ onNavigate }: OverviewProps) {
  const [inventory, setInventory] = useState<InventoryRecord[]>(readInventory);
  const [sales, setSales] = useState<SaleRecord[]>(readSales);
  const [now, setNow] = useState(new Date());

  const [shopCurrency] = useState<CurrencyCode>(() =>
    getShopCurrency()
  );

  const [rateSnapshot, setRateSnapshot] =
    useState<ExchangeRateSnapshot | null>(() =>
      getSavedExchangeRateSnapshot(getShopCurrency())
    );

  useEffect(() => {
    const refreshData = () => {
      setInventory(readInventory());
      setSales(readSales());
      setNow(new Date());
    };

    window.addEventListener("focus", refreshData);
    window.addEventListener("storage", refreshData);

    return () => {
      window.removeEventListener("focus", refreshData);
      window.removeEventListener("storage", refreshData);
    };
  }, []);

  useEffect(() => {
    let active = true;

    const savedSnapshot =
      getSavedExchangeRateSnapshot(shopCurrency);

    if (savedSnapshot) {
      setRateSnapshot(savedSnapshot);
    }

    refreshExchangeRateSnapshot(shopCurrency)
      .then((snapshot) => {
        if (active) {
          setRateSnapshot(snapshot);
        }
      })
      .catch(() => {
        if (active) {
          setRateSnapshot(
            getSavedExchangeRateSnapshot(shopCurrency)
          );
        }
      });

    return () => {
      active = false;
    };
  }, [shopCurrency]);

  const todayKey = localDateKey(now);

   const stock = useMemo(() => {
    const active = inventory.filter((item) => item.status !== "Sold");

    const units = (item: InventoryRecord) =>
      item.category === "Accessory / spare part"
        ? Math.max(0, Number(item.quantity) || 0)
        : 1;

    let stockValue = 0;
    let unconvertedValuation = 0;

    active.forEach((item) => {
      const cost = (Number(item.costPrice) || 0) * units(item);
      const sourceCurrency = getRecordCurrency(item.currencyCode);

            const converted = convertOverviewAmount(
        cost,
        sourceCurrency,
        rateSnapshot,
        shopCurrency
      );

      if (converted === null) {
        if (cost !== 0 && sourceCurrency !== shopCurrency) {
          unconvertedValuation += 1;
        }
      } else {
        stockValue += converted;
      }
    });

    return {
      totalUnits: active.reduce((total, item) => total + units(item), 0),

      totalDevices: active.filter(
        (item) => item.category !== "Accessory / spare part"
      ).length,

      accessoryUnits: active
        .filter((item) => item.category === "Accessory / spare part")
        .reduce((total, item) => total + units(item), 0),

      inShop: active
        .filter((item) => item.status === "In shop")
        .reduce((total, item) => total + units(item), 0),

      withMiddleman: active
        .filter((item) => item.status === "With middle-man")
        .reduce((total, item) => total + units(item), 0),

      atRepairer: active
        .filter((item) => item.status === "At repairer")
        .reduce((total, item) => total + units(item), 0),

      stockValue,
      unconvertedValuation,
    };
  }, [inventory, rateSnapshot, shopCurrency]);

    const todaySales = useMemo(
    () =>
      sales.filter((sale) => {
        const date = new Date(sale.transactionDate);

        return (
          !Number.isNaN(date.getTime()) &&
          localDateKey(date) === todayKey
        );
      }),
    [sales, todayKey]
  );

  const todayRevenue = useMemo(
    () =>
      todaySales.reduce((total, sale) => {
                const converted = convertOverviewAmount(
          Number(sale.salePrice) || 0,
          getRecordCurrency(sale.currencyCode),
          rateSnapshot,
          shopCurrency
        );

        return total + (converted ?? 0);
      }, 0),
    [todaySales, rateSnapshot]
  );

  const cashReceived = useMemo(
    () =>
      todaySales
        .filter((sale) => sale.paymentMethod === "Cash")
        .reduce((total, sale) => {
                    const converted = convertOverviewAmount(
            Number(sale.salePrice) || 0,
            getRecordCurrency(sale.currencyCode),
            rateSnapshot,
            shopCurrency
          );

          return total + (converted ?? 0);
        }, 0),
    [todaySales, rateSnapshot]
  );

  const followUpCount = stock.withMiddleman + stock.atRepairer;

  const lastSevenDays = useMemo(() => {
    return Array.from({ length: 7 }, (_, index) => {
      const date = new Date(now);
      date.setDate(now.getDate() - (6 - index));

      const key = localDateKey(date);

      const total = sales
        .filter((sale) => {
          const saleDate = new Date(sale.transactionDate);

          return (
            !Number.isNaN(saleDate.getTime()) &&
            localDateKey(saleDate) === key
          );
        })
        .reduce((sum, sale) => {
                    const converted = convertOverviewAmount(
            Number(sale.salePrice) || 0,
            getRecordCurrency(sale.currencyCode),
            rateSnapshot,
            shopCurrency
          );

          return sum + (converted ?? 0);
        }, 0);

      return {
        label: date.toLocaleDateString("en-UG", {
          weekday: "short",
        }),
        total,
      };
    });
  }, [sales, now, rateSnapshot]);

  const weeklyRevenue = lastSevenDays.reduce(
    (total, day) => total + day.total,
    0
  );

  const previousSevenDaysRevenue = useMemo(() => {
    const start = new Date(now);
    start.setDate(now.getDate() - 13);
    start.setHours(0, 0, 0, 0);

    const end = new Date(now);
    end.setDate(now.getDate() - 7);
    end.setHours(0, 0, 0, 0);

    return sales
      .filter((sale) => {
        const date = new Date(sale.transactionDate);

        return (
          !Number.isNaN(date.getTime()) &&
          date >= start &&
          date < new Date(end.getTime() + 86400000)
        );
      })
      .reduce((total, sale) => {
                const converted = convertOverviewAmount(
          Number(sale.salePrice) || 0,
          getRecordCurrency(sale.currencyCode),
          rateSnapshot,
          shopCurrency
        );

        return total + (converted ?? 0);
      }, 0);
  }, [sales, now, rateSnapshot]);

  const weeklyChange =
    previousSevenDaysRevenue > 0
      ? ((weeklyRevenue - previousSevenDaysRevenue) /
          previousSevenDaysRevenue) * 100
      : null;

  const maxChartValue = Math.max(
    ...lastSevenDays.map((day) => day.total),
    1
    );
  const recentSales = sales.slice(0, 5);

  const recentInventory = [...inventory]
    .filter((item) => item.status !== "Sold")
    .slice(-5)
    .reverse();

  const greeting =
    now.getHours() < 12
      ? "Good morning"
      : now.getHours() < 17
        ? "Good afternoon"
        : "Good evening";

  return (
    <div className="page-content">
      <section className="welcome-row">
        <div>
          <div className="eyebrow">
            <span className="eyebrow-line" />
            {now.toLocaleDateString("en-UG", {
              weekday: "long",
              day: "numeric",
              month: "long",
              year: "numeric",
            }).toUpperCase()}
          </div>
          <h1>{greeting}, <span>Val.</span></h1>
          <p className="page-subtitle">
            Here's what's happening across your shop today.
          </p>
        </div>

        <div className="welcome-actions">
          <button
            className="button button-secondary"
            onClick={() => onNavigate("Reports")}
          >
            <Download size={16} /> Reports
          </button>
          <button
            className="button button-primary"
            onClick={() => onNavigate("Inventory")}
          >
            <Plus size={17} /> Add stock
          </button>
        </div>
      </section>

      <section className="status-strip" aria-label="System status">
        <div className="status-left">
          <span className="status-pulse" />
          <span className="status-title">Local data connected</span>
          <span className="status-divider" />
          <span className="status-detail">Browser storage</span>
        </div>
        <div className="status-right">
          <Clock3 size={14} /> Updated just now
        </div>
      </section>

            <section className="metrics-grid" aria-label="Shop metrics">
        <MetricCard
          label="Inventory at cost"
          value={formatMoney(stock.stockValue, shopCurrency)}
          note={
            stock.unconvertedValuation > 0
              ? `${stock.unconvertedValuation} records excluded: exchange rate unavailable`
              : "Unsold stock at recorded cost"
          }
          icon={BoxesIcon}
          tone="blue"
        />

        <MetricCard
          label="Sales today"
          value={formatMoney(todayRevenue, shopCurrency)}
          note={`${todaySales.length} recorded transactions`}
          icon={ReceiptText}
          tone="violet"
        />

        <MetricCard
          label="Cash received today"
          value={formatMoney(cashReceived, shopCurrency)}
          note="Cash payments only"
          icon={Wallet}
          tone="cyan"
        />

        <MetricCard
          label="Needs follow-up"
          value={`${followUpCount} items`}
          note={`${stock.withMiddleman} with middle-men · ${stock.atRepairer} at repairers`}
          icon={CircleAlert}
          tone="amber"
        />
      </section>

      <section className="main-grid">
        <article className="surface-card sales-card">
          <div className="card-heading">
            <div>
              <div className="card-kicker">PERFORMANCE</div>
              <h2>Sales overview</h2>
            </div>
            <div className="select-button">
              <CalendarDays size={15} /> Last 7 days
            </div>
          </div>

          <div className="sales-summary">
            <div>
              <div className="sales-total">
                {formatMoney(weeklyRevenue, shopCurrency)}
              </div>
              <div className="sales-comparison">
                {weeklyChange === null ? (
                  <span>No previous-week comparison yet</span>
                ) : (
                  <>
                    <span className={weeklyChange >= 0 ? "positive" : ""}>
                      <ArrowUpRight size={14} />
                      {Math.abs(weeklyChange).toFixed(1)}%
                    </span>
                    <span>vs previous 7 days</span>
                  </>
                )}
              </div>
            </div>
            <div className="sales-legend">
              <span className="legend-dot legend-current" /> This week
            </div>
          </div>

          <div className="chart-area" role="img" aria-label="Actual sales for the last seven days">
            <div className="chart-y-labels">
              <span>{formatCompact(maxChartValue)}</span>
              <span>{formatCompact(maxChartValue * 0.75)}</span>
              <span>{formatCompact(maxChartValue * 0.5)}</span>
              <span>{formatCompact(maxChartValue * 0.25)}</span>
              <span>0</span>
            </div>

            <div className="chart-plot">
              <div className="chart-grid-lines">
                <i /><i /><i /><i /><i />
              </div>

              <div
                style={{
                  position: "absolute",
                  inset: "8px 0 25px",
                  display: "flex",
                  alignItems: "flex-end",
                  justifyContent: "space-around",
                  gap: "10px",
                  padding: "0 8px",
                }}
              >
                {lastSevenDays.map((day) => (
                  <div
                    key={day.label}
                    title={`${day.label}: ${formatMoney(day.total, shopCurrency)}`}
                    style={{
                      flex: 1,
                      maxWidth: "48px",
                      height: `${Math.max((day.total / maxChartValue) * 100, 2)}%`,
                      minHeight: "2px",
                      borderRadius: "5px 5px 0 0",
                      background: "linear-gradient(180deg, #8b91ff, #5968d9)",
                    }}
                  />
                ))}
              </div>

              <div className="chart-x-labels">
                {lastSevenDays.map((day, index) => (
                  <span key={`${day.label}-${index}`}>{day.label}</span>
                ))}
              </div>
            </div>
          </div>

          <div className="chart-footer">
            <span>
              <span className="footer-dot" /> Based on recorded transactions
            </span>
            <button
              className="text-button"
              onClick={() => onNavigate("Reports")}
            >
              View reports <ArrowRight size={15} />
            </button>
          </div>
        </article>

        <article className="surface-card stock-card">
          <div className="card-heading">
            <div>
              <div className="card-kicker">INVENTORY HEALTH</div>
              <h2>Stock at a glance</h2>
            </div>
            <button
              className="icon-button"
              aria-label="Open inventory"
              onClick={() => onNavigate("Inventory")}
            >
              <ArrowUpRight size={17} />
            </button>
          </div>

          <div className="stock-hero">
            <div className="stock-ring">
              <div>
                <strong>{stock.totalUnits}</strong>
                <span>stock units</span>
              </div>
            </div>

            <div className="stock-legend">
              <div>
                <span className="stock-key key-blue" />
                <span>In shop</span>
                <strong>{stock.inShop}</strong>
              </div>
              <div>
                <span className="stock-key key-violet" />
                <span>With middle-men</span>
                <strong>{stock.withMiddleman}</strong>
              </div>
              <div>
                <span className="stock-key key-amber" />
                <span>At repairers</span>
                <strong>{stock.atRepairer}</strong>
              </div>
            </div>
          </div>

          <div className="stock-note">
            <div className="stock-note-icon">
              <Smartphone size={16} />
            </div>
            <div>
              <strong>{stock.totalDevices} devices · {stock.accessoryUnits} accessory units</strong>
              <span>Sold stock is excluded from current stock totals.</span>
            </div>
          </div>

          <button
            className="button button-secondary button-full"
            onClick={() => onNavigate("Inventory")}
          >
            Open inventory <ArrowRight size={16} />
          </button>
        </article>
      </section>

      <section className="bottom-grid">
                <article className="surface-card activity-card">
          <div className="card-heading">
            <div>
              <div className="card-kicker">TRANSACTION FEED</div>
              <h2>Recent sales</h2>
            </div>
            <button
              className="text-button"
              onClick={() => onNavigate("Sales")}
            >
              View all <ArrowRight size={15} />
            </button>
          </div>

          {recentSales.length === 0 ? (
            <div className="inventory-empty">
              <ReceiptText size={24} />
              <strong>No sales recorded yet</strong>
              <span>Completed sales will appear here.</span>
            </div>
          ) : (
            <div className="operations-record-list">
              {recentSales.map((sale) => (
                <article className="operations-record" key={sale.id}>
                  <div className="operations-record-icon">
                    <ShoppingCart size={17} />
                  </div>

                  <div className="operations-record-copy">
                    <strong>{sale.deviceName}</strong>
                    <span>{sale.identifier}</span>
                    <span>
                      {new Date(sale.transactionDate).toLocaleString()}
                    </span>
                  </div>

                  <strong className="operations-amount">
                    {formatMoney(
                      Number(sale.salePrice) || 0,
                      getRecordCurrency(sale.currencyCode)
                    )}
                  </strong>
                </article>
              ))}
            </div>
          )}
        </article>

        <article className="surface-card attention-card">
          <div className="card-heading">
            <div>
              <div className="card-kicker">ACTION REQUIRED</div>
              <h2>Needs your attention</h2>
            </div>
            <span className="attention-count">{followUpCount}</span>
          </div>

          {stock.withMiddleman > 0 && (
            <button
              className="attention-item"
              onClick={() => onNavigate("Custody")}
            >
              <span className="attention-symbol symbol-violet">
                <ArrowUpRight size={17} />
              </span>
              <span className="attention-copy">
                <strong>Middle-man follow-up</strong>
                <small>{stock.withMiddleman} stock units away</small>
              </span>
              <ArrowRight size={16} className="attention-arrow" />
            </button>
          )}

          {stock.atRepairer > 0 && (
            <button
              className="attention-item"
              onClick={() => onNavigate("Repairs")}
            >
              <span className="attention-symbol symbol-amber">
                <WrenchIcon size={17} />
              </span>
              <span className="attention-copy">
                <strong>Repair tracking</strong>
                <small>{stock.atRepairer} stock units at repairers</small>
              </span>
              <ArrowRight size={16} className="attention-arrow" />
            </button>
          )}

          {followUpCount === 0 && (
            <div className="inventory-empty">
              <CircleAlert size={22} />
              <strong>No stock follow-ups</strong>
              <span>No devices are currently marked away.</span>
            </div>
          )}

          <div className="stock-note">
            <div className="stock-note-icon">
              <Wallet size={16} />
            </div>
            <div>
              <strong>Cash closing</strong>
              <span>Daily closing records are not connected yet.</span>
            </div>
          </div>
        </article>
      </section>

            <section className="devices-section surface-card">
        <div className="card-heading">
          <div>
            <div className="card-kicker">INVENTORY RECORDS</div>
            <h2>Recently added stock</h2>
          </div>
          <button
            className="text-button"
            onClick={() => onNavigate("Inventory")}
          >
            View inventory <ArrowRight size={15} />
          </button>
        </div>

        {recentInventory.length === 0 ? (
          <div className="inventory-empty">
            <Package size={24} />
            <strong>No inventory records yet</strong>
            <span>Add stock to see your inventory here.</span>
          </div>
        ) : (
          <div className="table-wrap">
            <table className="inventory-table">
              <thead>
                <tr>
                  <th>ITEM</th>
                  <th>IDENTIFIER</th>
                  <th>STATUS</th>
                  <th>SELLING PRICE</th>
                  <th>UPDATED</th>
                  <th />
                </tr>
              </thead>

              <tbody>
                {recentInventory.map((item) => (
                  <tr key={item.id}>
                    <td>
                      <div className="device-cell">
                        <div className="device-thumbnail">
                          {item.category === "Accessory / spare part" ? (
                            <Package size={18} />
                          ) : (
                            <Smartphone size={18} />
                          )}
                        </div>

                        <div>
                          <strong>{item.brand} {item.model}</strong>
                          <span>
                            {item.category === "Accessory / spare part"
                              ? `Accessory · Qty ${item.quantity ?? 1}`
                              : item.storage ?? "Device"}
                          </span>
                        </div>
                      </div>
                    </td>

                    <td className="identifier-cell">{item.identifier}</td>

                    <td>
                      <span className={`status-pill status-${getStatusClass(item.status)}`}>
                        <i />{item.status}
                      </span>
                    </td>

                    <td className="price-cell">
                      {formatMoney(
                        Number(item.sellingPrice) || 0,
                        getRecordCurrency(item.currencyCode)
                      )}
                    </td>

                    <td className="updated-cell">{item.updated}</td>

                    <td>
                      <button
                        className="row-more"
                        aria-label={`Open ${item.model}`}
                        onClick={() => onNavigate("Inventory")}
                      >
                        ···
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <div className="table-footnote">
          <span>
            <CircleAlert size={14} /> Data shown comes from this browser's inventory records.
          </span>
          <button
            className="text-button"
            onClick={() => onNavigate("Inventory")}
          >
            Open full inventory <ArrowRight size={15} />
          </button>
        </div>
      </section>

      <div className="prototype-disclaimer">
        StockPilot prototype · Dashboard figures are calculated from locally stored inventory and sales records.
      </div>
    </div>
  );
}
