import { useState } from "react";
import {
  Bell,
  ChevronDown,
  Command,
  Menu,
  Moon,
  Search,
  Sun,
} from "lucide-react";
import Sidebar, { type PageKey } from "./components/Sidebar";
import Overview from "./pages/Overview";

const placeholderCopy: Record<Exclude<PageKey, "Overview">, { title: string; description: string }> = {
  Inventory: { title: "Inventory", description: "Search devices, check approved selling prices and track stock status." },
  Sales: { title: "Sales", description: "Record sales, returns, payment methods and outstanding customer balances." },
  Custody: { title: "Custody ledger", description: "Track phones entrusted to middle-men and follow up on outstanding items." },
  Repairs: { title: "Repair tracking", description: "Follow devices sent to mechanics, repair costs and return status." },
  "Daily closing": { title: "Daily closing", description: "Reconcile expected cash against the actual count and review discrepancies." },
  Reports: { title: "Reports", description: "Review stock valuation, sales, expenses and operational summaries." },
  "Team & shops": { title: "Team & shops", description: "Manage staff roles and, in a later release, multiple shop workspaces." },
  Settings: { title: "Settings", description: "Configure shop preferences, appearance and account settings." },
};

export default function App() {
  const [activePage, setActivePage] = useState<PageKey>("Overview");
  const [darkMode, setDarkMode] = useState(true);
  const [mobileOpen, setMobileOpen] = useState(false);
  const [searchValue, setSearchValue] = useState("");

  const navigate = (page: PageKey) => setActivePage(page);

  return (
    <div className={`app-shell ${darkMode ? "theme-dark" : "theme-light"}`}>
      <Sidebar
        activePage={activePage}
        onNavigate={navigate}
        mobileOpen={mobileOpen}
        onClose={() => setMobileOpen(false)}
      />

      <main className="main-panel">
        <header className="topbar">
          <div className="topbar-left">
            <button className="icon-button mobile-menu-button" onClick={() => setMobileOpen(true)} aria-label="Open navigation">
              <Menu size={20} />
            </button>
            <div className="breadcrumb"><span>Workspace</span><span className="breadcrumb-slash">/</span><strong>{activePage}</strong></div>
          </div>
          <div className="topbar-actions">
            <label className="global-search">
              <Search size={16} />
              <input
                type="search"
                value={searchValue}
                onChange={(event) => setSearchValue(event.target.value)}
                placeholder="Search anything..."
                aria-label="Search"
              />
              <kbd><Command size={11} /> K</kbd>
            </label>
            <span className="topbar-divider" />
            <button className="icon-button theme-toggle" onClick={() => setDarkMode((value) => !value)} aria-label={darkMode ? "Switch to light mode" : "Switch to dark mode"} title={darkMode ? "Switch to light mode" : "Switch to dark mode"}>
              {darkMode ? <Sun size={18} /> : <Moon size={18} />}
            </button>
            <button className="icon-button notification-button" aria-label="Notifications">
              <Bell size={18} /><span />
            </button>
            <button className="profile-button" aria-label="Profile menu">
              <span className="profile-avatar">VN</span>
              <span className="profile-copy"><strong>Valentino</strong><small>Owner account</small></span>
              <ChevronDown size={15} className="profile-chevron" />
            </button>
          </div>
        </header>

        {activePage === "Overview" ? (
          <Overview onNavigate={navigate} />
        ) : (
          <section className="placeholder-page page-content">
            <div className="eyebrow"><span className="eyebrow-line" /> STOCKPILOT WORKSPACE</div>
            <h1>{placeholderCopy[activePage].title}</h1>
            <p className="page-subtitle">{placeholderCopy[activePage].description}</p>
            <div className="placeholder-card surface-card">
              <div className="placeholder-icon"><Command size={22} /></div>
              <h2>This module is scheduled for the next build stage.</h2>
              <p>Navigation and layout are connected. We'll implement the real workflow here, using fictional data until authentication and backend security are in place.</p>
              <button className="button button-primary" onClick={() => setActivePage("Overview")}>Return to overview</button>
            </div>
          </section>
        )}
      </main>
    </div>
  );
}