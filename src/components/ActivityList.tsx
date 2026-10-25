import { ArrowDownLeft, ArrowUpRight, Boxes, Wrench } from "lucide-react";
import { recentActivity } from "../data/mockData";

const iconByType = {
  handover: ArrowUpRight,
  sale: ArrowDownLeft,
  repair: Wrench,
  stock: Boxes,
};

export default function ActivityList() {
  return (
    <div className="activity-list">
      {recentActivity.map((item) => {
        const Icon = iconByType[item.type as keyof typeof iconByType];
        return (
          <div className="activity-item" key={`${item.title}-${item.time}`}>
            <div className={`activity-icon activity-${item.type}`}>
              <Icon size={16} strokeWidth={1.8} />
            </div>
            <div className="activity-copy">
              <p>{item.title}</p>
              <span>{item.detail}</span>
            </div>
            <time>{item.time}</time>
          </div>
        );
      })}
    </div>
  );
}