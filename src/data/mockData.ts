export type StockStatus = "In shop" | "With middle-man" | "At repairer";

export interface DeviceRecord {
  id: string;
  model: string;
  variant: string;
  identifier: string;
  status: StockStatus;
  approvedPrice: number;
  updated: string;
}

export const demoDevices: DeviceRecord[] = [
  { id: "SP-1008", model: "iPhone 13", variant: "128 GB · Midnight", identifier: "•••• 4821", status: "In shop", approvedPrice: 780000, updated: "4 min ago" },
  { id: "SP-1007", model: "Samsung Galaxy A55", variant: "256 GB · Awesome Navy", identifier: "•••• 1294", status: "With middle-man", approvedPrice: 920000, updated: "18 min ago" },
  { id: "SP-1006", model: "iPhone 12", variant: "64 GB · Black", identifier: "•••• 7732", status: "At repairer", approvedPrice: 560000, updated: "42 min ago" },
  { id: "SP-1005", model: "Redmi Note 13", variant: "128 GB · Graphite", identifier: "•••• 6602", status: "In shop", approvedPrice: 410000, updated: "1 hr ago" },
];

export const recentActivity = [
  { title: "Phone handover recorded", detail: "Samsung Galaxy A55 · Assigned to a middle-man", time: "18 min ago", type: "handover" },
  { title: "Accessory sale recorded", detail: "USB-C cable · 3 units", time: "32 min ago", type: "sale" },
  { title: "Repair status updated", detail: "iPhone 12 · Awaiting screen replacement", time: "42 min ago", type: "repair" },
  { title: "New stock added", detail: "iPhone 13 · 128 GB", time: "1 hr ago", type: "stock" },
];

export function formatUGX(amount: number): string {
  return new Intl.NumberFormat("en-UG", {
    style: "currency",
    currency: "UGX",
    maximumFractionDigits: 0,
  }).format(amount);
}