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
import Inventory from "./pages/Inventory";
import Operations from "./pages/Operations";

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
        ) : activePage === "Inventory" ? (
          <Inventory />
        ) : (
          <Operations key={activePage} page={activePage} />
        )}
      </main>
    </div>
  );
}