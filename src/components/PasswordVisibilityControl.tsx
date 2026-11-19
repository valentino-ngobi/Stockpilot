import type { ChangeEventHandler } from "react";
import { Eye, EyeOff } from "lucide-react";

type PasswordVisibilityControlProps = {
  id: string;
  labelledBy: string;
  value: string;
  visible: boolean;
  autoComplete: "current-password" | "new-password";
  onChange: ChangeEventHandler<HTMLInputElement>;
  onToggle: () => void;
};

export default function PasswordVisibilityControl({
  id,
  labelledBy,
  value,
  visible,
  autoComplete,
  onChange,
  onToggle,
}: PasswordVisibilityControlProps) {
  return (
    <div className="backend-password-control">
      <input
        id={id}
        aria-labelledby={labelledBy}
        className="backend-password-input"
        type={visible ? "text" : "password"}
        value={value}
        onChange={onChange}
        autoComplete={autoComplete}
        minLength={8}
        required
      />
      <button
        className="backend-password-toggle"
        type="button"
        aria-label={visible ? "Hide password" : "Show password"}
        aria-pressed={visible}
        onMouseDown={(event) => event.preventDefault()}
        onClick={onToggle}
      >
        {visible ? <EyeOff size={17} aria-hidden="true" /> : <Eye size={17} aria-hidden="true" />}
      </button>
    </div>
  );
}
