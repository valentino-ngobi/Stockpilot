import type { LucideIcon } from "lucide-react";

interface MetricCardProps {
  label: string;
  value: string;
  note: string;
  icon: LucideIcon;
  tone: "blue" | "violet" | "cyan" | "amber";
  trend?: string;
}

export default function MetricCard({
  label,
  value,
  note,
  icon: Icon,
  tone,
  trend,
}: MetricCardProps) {
  return (
    <article className="metric-card surface-card">
      <div className="metric-topline">
        <span className="metric-label">{label}</span>
        <span className={`metric-icon metric-icon-${tone}`}><Icon size={18} strokeWidth={1.9} /></span>
      </div>
      <div className="metric-value">{value}</div>
      <div className="metric-bottomline">
        {trend && <span className="metric-trend">{trend}</span>}
        <span className="metric-note">{note}</span>
      </div>
    </article>
  );
}