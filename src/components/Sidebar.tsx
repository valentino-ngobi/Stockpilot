import {
  Activity,
  BarChart3,
  Boxes,
  BriefcaseBusiness,
  ClipboardCheck,
  LayoutDashboard,
  Settings2,
  Smartphone,
  Users,
  Wrench,
  X,
} from "lucide-react";

export type PageKey =
  | "Overview"
  | "Inventory"
  | "Sales"
  | "Custody"
  | "Repairs"
  | "Daily closing"
  | "Reports"
  | "Team & shops"
  | "Settings";

interface SidebarProps {
  activePage: PageKey;
  onNavigate: (page: PageKey) => void;
  mobileOpen: boolean;
  onClose: () => void;
}

const primaryItems = [
  { label: "Overview", icon: LayoutDashboard },
  { label: "Inventory", icon: Smartphone },
  { label: "Sales", icon: Activity },
  { label: "Custody", icon: Boxes },
  { label: "Repairs", icon: Wrench },
  { label: "Daily closing", icon: ClipboardCheck },
  { label: "Reports", icon: BarChart3 },
] as const;

export default function Sidebar({
  activePage,
  onNavigate,
  mobileOpen,
  onClose,
}: SidebarProps) {
  const handleNavigate = (page: PageKey) => {
    onNavigate(page);
    onClose();
  };

  return (
    <>
      <button
        className={`mobile-backdrop ${mobileOpen ? "is-visible" : ""}`}
        aria-label="Close navigation"
        onClick={onClose}
        tabIndex={mobileOpen ? 0 : -1}
      />
      <aside className={`sidebar ${mobileOpen ? "sidebar-open" : ""}`}>
        <div className="brand-row">
          <div className="brand-mark" aria-hidden="true">
            <Boxes size={21} strokeWidth={2.2} />
          </div>
          <div className="brand-copy">
            <span className="brand-name">StockPilot</span>
            <span className="brand-caption">RETAIL OPERATIONS</span>
          </div>
          <button className="icon-button sidebar-close" onClick={onClose} aria-label="Close menu">
            <X size={18} />
          </button>
        </div>

        <div className="shop-switcher">
          <div className="shop-avatar">VG</div>
          <div className="shop-details">
            <span className="shop-name">Val Gadgets Demo</span>
            <span className="shop-plan">Starter workspace</span>
          </div>
          <span className="switcher-indicator" aria-hidden="true">⌄</span>
        </div>

        <div className="nav-label">WORKSPACE</div>
        <nav className="nav-list" aria-label="Main navigation">
          {primaryItems.map(({ label, icon: Icon }) => (
            <button
              key={label}
              className={`nav-item ${activePage === label ? "nav-item-active" : ""}`}
              onClick={() => handleNavigate(label)}
              aria-current={activePage === label ? "page" : undefined}
            >
              <Icon size={18} strokeWidth={1.8} />
              <span>{label}</span>
              {label === "Custody" && <span className="nav-count">6</span>}
            </button>
          ))}
        </nav>

        <div className="nav-label nav-label-spaced">MANAGEMENT</div>
        <nav className="nav-list" aria-label="Management navigation">
          <button
            className={`nav-item ${activePage === "Team & shops" ? "nav-item-active" : ""}`}
            onClick={() => handleNavigate("Team & shops")}
          >
            <Users size={18} strokeWidth={1.8} />
            <span>Team & shops</span>
          </button>
          <button
            className={`nav-item ${activePage === "Settings" ? "nav-item-active" : ""}`}
            onClick={() => handleNavigate("Settings")}
          >
            <Settings2 size={18} strokeWidth={1.8} />
            <span>Settings</span>
          </button>
        </nav>

        <div className="sidebar-spacer" />
        <div className="help-card">
          <div className="help-icon"><BriefcaseBusiness size={17} /></div>
          <div>
            <p>Built for gadget retail</p>
            <span>Keep every device accounted for.</span>
          </div>
        </div>
        <div className="sidebar-footer">
          <div className="connection-dot" />
          <span>Demo mode</span>
          <span className="footer-version">v0.1.0</span>
        </div>
      </aside>
    </>
  );
}