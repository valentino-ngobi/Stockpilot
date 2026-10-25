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
} from "lucide-react";
import { demoDevices, formatUGX } from "../data/mockData";
import type { PageKey } from "../components/Sidebar";
import MetricCard from "../components/MetricCard";
import ActivityList from "../components/ActivityList";

interface OverviewProps {
  onNavigate: (page: PageKey) => void;
}

export default function Overview({ onNavigate }: OverviewProps) {
  const availableCount = demoDevices.filter((device) => device.status === "In shop").length;

  return (
    <div className="page-content">
      <section className="welcome-row">
        <div>
          <div className="eyebrow"><span className="eyebrow-line" /> SUNDAY, OCTOBER 25</div>
          <h1>Good morning, <span>Val.</span></h1>
          <p className="page-subtitle">Here's what's happening across your shop today.</p>
        </div>
        <div className="welcome-actions">
          <button className="button button-secondary" onClick={() => onNavigate("Reports")}>
            <Download size={16} /> Export report
          </button>
          <button className="button button-primary" onClick={() => onNavigate("Inventory")}>
            <Plus size={17} /> Add stock
          </button>
        </div>
      </section>

      <section className="status-strip" aria-label="System status">
        <div className="status-left">
          <span className="status-pulse" />
          <span className="status-title">All systems operational</span>
          <span className="status-divider" />
          <span className="status-detail">Demo data only</span>
        </div>
        <div className="status-right"><Clock3 size={14} /> Last updated just now</div>
      </section>

      <section className="metrics-grid" aria-label="Shop metrics">
        <MetricCard label="Inventory at cost" value="UGX 18.42M" note="Owned stock value" icon={BoxesIcon} tone="blue" trend="↗ 8.2%" />
        <MetricCard label="Sales today" value="UGX 2.84M" note="12 recorded transactions" icon={ReceiptText} tone="violet" trend="↗ 12.6%" />
        <MetricCard label="Expected cash" value="UGX 1.96M" note="Awaiting closing count" icon={Wallet} tone="cyan" />
        <MetricCard label="Needs follow-up" value="06 items" note="Custody and repairs" icon={CircleAlert} tone="amber" />
      </section>

      <section className="main-grid">
        <article className="surface-card sales-card">
          <div className="card-heading">
            <div>
              <div className="card-kicker">PERFORMANCE</div>
              <h2>Sales overview</h2>
            </div>
            <button className="select-button"><CalendarDays size={15} /> Last 7 days <span>⌄</span></button>
          </div>
          <div className="sales-summary">
            <div>
              <div className="sales-total">UGX 14.28M</div>
              <div className="sales-comparison"><span className="positive"><ArrowUpRight size={14} /> 9.4%</span> <span>vs previous 7 days</span></div>
            </div>
            <div className="sales-legend"><span className="legend-dot legend-current" /> This week <span className="legend-dot legend-previous" /> Previous</div>
          </div>
          <div className="chart-area" role="img" aria-label="Illustrative seven-day sales chart">
            <div className="chart-y-labels"><span>4M</span><span>3M</span><span>2M</span><span>1M</span><span>0</span></div>
            <div className="chart-plot">
              <div className="chart-grid-lines"><i /><i /><i /><i /><i /></div>
              <svg className="chart-svg" viewBox="0 0 600 190" preserveAspectRatio="none" aria-hidden="true">
                <defs>
                  <linearGradient id="salesFill" x1="0" x2="0" y1="0" y2="1">
                    <stop offset="0%" stopColor="#6D7CFF" stopOpacity=".28" />
                    <stop offset="100%" stopColor="#6D7CFF" stopOpacity="0" />
                  </linearGradient>
                </defs>
                <path d="M0,140 C35,125 45,135 82,108 S135,122 170,88 S220,100 255,75 S300,96 340,57 S395,74 425,44 S485,78 515,34 S570,53 600,20 L600,190 L0,190 Z" fill="url(#salesFill)" />
                <path d="M0,140 C35,125 45,135 82,108 S135,122 170,88 S220,100 255,75 S300,96 340,57 S395,74 425,44 S485,78 515,34 S570,53 600,20" fill="none" stroke="#7B87FF" strokeWidth="3" vectorEffect="non-scaling-stroke" strokeLinecap="round" />
                <path d="M0,162 C45,154 65,166 105,146 S160,157 205,135 S265,150 300,126 S360,139 405,119 S470,134 510,107 S560,124 600,96" fill="none" stroke="#3D4862" strokeWidth="2" strokeDasharray="5 6" vectorEffect="non-scaling-stroke" />
                <circle cx="515" cy="34" r="5" fill="#0D111B" stroke="#A5ACFF" strokeWidth="3" vectorEffect="non-scaling-stroke" />
              </svg>
              <div className="chart-x-labels"><span>Mon</span><span>Tue</span><span>Wed</span><span>Thu</span><span>Fri</span><span>Sat</span><span>Sun</span></div>
            </div>
          </div>
          <div className="chart-footer">
            <span><span className="footer-dot" /> Sales are sample figures for layout testing</span>
            <button className="text-button" onClick={() => onNavigate("Reports")}>View reports <ArrowRight size={15} /></button>
          </div>
        </article>

        <article className="surface-card stock-card">
          <div className="card-heading">
            <div>
              <div className="card-kicker">INVENTORY HEALTH</div>
              <h2>Stock at a glance</h2>
            </div>
            <button className="icon-button" aria-label="Open inventory" onClick={() => onNavigate("Inventory")}><ArrowUpRight size={17} /></button>
          </div>
          <div className="stock-hero">
            <div className="stock-ring"><div><strong>248</strong><span>total items</span></div></div>
            <div className="stock-legend">
              <div><span className="stock-key key-blue" /><span>In shop</span><strong>218</strong></div>
              <div><span className="stock-key key-violet" /><span>With middle-men</span><strong>18</strong></div>
              <div><span className="stock-key key-amber" /><span>At repairers</span><strong>12</strong></div>
            </div>
          </div>
          <div className="stock-note">
            <div className="stock-note-icon"><Smartphone size={16} /></div>
            <div><strong>{availableCount} demo phones shown in the table</strong><span>Detailed counts are illustrative.</span></div>
          </div>
          <button className="button button-secondary button-full" onClick={() => onNavigate("Inventory")}>Open inventory <ArrowRight size={16} /></button>
        </article>
      </section>

      <section className="bottom-grid">
        <article className="surface-card activity-card">
          <div className="card-heading">
            <div>
              <div className="card-kicker">LIVE FEED</div>
              <h2>Recent activity</h2>
            </div>
            <button className="text-button" onClick={() => onNavigate("Custody")}>View all <ArrowRight size={15} /></button>
          </div>
          <ActivityList />
        </article>

        <article className="surface-card attention-card">
          <div className="card-heading">
            <div>
              <div className="card-kicker">ACTION REQUIRED</div>
              <h2>Needs your attention</h2>
            </div>
            <span className="attention-count">3</span>
          </div>
          <button className="attention-item" onClick={() => onNavigate("Custody")}>
            <span className="attention-symbol symbol-violet"><ArrowUpRight size={17} /></span>
            <span className="attention-copy"><strong>Middle-man follow-up</strong><small>2 phones awaiting an update</small></span>
            <ArrowRight size={16} className="attention-arrow" />
          </button>
          <button className="attention-item" onClick={() => onNavigate("Repairs")}>
            <span className="attention-symbol symbol-amber"><WrenchIcon /></span>
            <span className="attention-copy"><strong>Repair status overdue</strong><small>1 phone has been away 3 days</small></span>
            <ArrowRight size={16} className="attention-arrow" />
          </button>
          <button className="attention-item" onClick={() => onNavigate("Daily closing")}>
            <span className="attention-symbol symbol-cyan"><Wallet size={17} /></span>
            <span className="attention-copy"><strong>Closing not completed</strong><small>Yesterday's cash count is missing</small></span>
            <ArrowRight size={16} className="attention-arrow" />
          </button>
        </article>
      </section>

      <section className="devices-section surface-card">
        <div className="card-heading">
          <div>
            <div className="card-kicker">RECENTLY UPDATED</div>
            <h2>Phone inventory</h2>
          </div>
          <button className="text-button" onClick={() => onNavigate("Inventory")}>View inventory <ArrowRight size={15} /></button>
        </div>
        <div className="table-wrap">
          <table className="inventory-table">
            <thead><tr><th>DEVICE</th><th>IDENTIFIER</th><th>STATUS</th><th>APPROVED PRICE</th><th>UPDATED</th><th /></tr></thead>
            <tbody>
              {demoDevices.map((device) => (
                <tr key={device.id}>
                  <td><div className="device-cell"><div className="device-thumbnail"><Smartphone size={18} /></div><div><strong>{device.model}</strong><span>{device.variant}</span></div></div></td>
                  <td className="identifier-cell">{device.identifier}</td>
                  <td><span className={`status-pill status-${device.status === "In shop" ? "available" : device.status === "With middle-man" ? "custody" : "repair"}`}><i />{device.status}</span></td>
                  <td className="price-cell">{formatUGX(device.approvedPrice)}</td>
                  <td className="updated-cell">{device.updated}</td>
                  <td><button className="row-more" aria-label={`Open ${device.model}`} onClick={() => onNavigate("Inventory")}>···</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="table-footnote"><span><CircleAlert size={14} /> Identifiers are masked fictional demo values.</span><button className="text-button" onClick={() => onNavigate("Inventory")}>Open full inventory <ArrowRight size={15} /></button></div>
      </section>

      <div className="prototype-disclaimer">StockPilot prototype · All names, values and activity are fictional demonstration data.</div>
    </div>
  );
}

