
import { useRef } from "react";
import {
  formatMoneyInput,
  type CurrencyCode,
} from "../utils/currency";

type CurrencyInputProps = {
  value: string;
  onChange: (value: string) => void;
  currencyCode: CurrencyCode;
  placeholder?: string;
  className?: string;
  disabled?: boolean;
  required?: boolean;
  ariaLabel?: string;
};

export default function CurrencyInput({
  value,
  onChange,
  currencyCode,
  placeholder = "Enter amount",
  className,
  disabled = false,
  required = false,
  ariaLabel = "Amount",
}: CurrencyInputProps) {
  const inputRef = useRef<HTMLInputElement>(null);

  const displayValue = formatMoneyInput(value, currencyCode);

  const handleChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const input = event.currentTarget;
    const originalValue = input.value;
    const cursorPosition = input.selectionStart ?? originalValue.length;

    const charactersBeforeCursor = originalValue
      .slice(0, cursorPosition)
      .replace(/,/g, "").replace(/[^\d.]/g, "").length;

    const decimalPlaces =
      currencyCode === "USD" ? 2 : currencyCode === "KWD" ? 3 : 0;

    const cleaned = originalValue
      .replace(/,/g, "")
      .replace(/[^\d.]/g, "");

    const parts = cleaned.split(".");
    const integerPart = parts[0] ?? "";
    const decimalPart = parts.slice(1).join("").slice(0, decimalPlaces);

    const rawValue =
      decimalPlaces > 0 && parts.length > 1
        ? `${integerPart}.${decimalPart}`
        : integerPart;

    const formattedValue = formatMoneyInput(rawValue, currencyCode);

    onChange(rawValue);

    let nextCursorPosition = 0;
    let countedCharacters = 0;

    while (
      nextCursorPosition < formattedValue.length &&
      countedCharacters < charactersBeforeCursor
    ) {
      if (formattedValue[nextCursorPosition] !== ",") {
        countedCharacters++;
      }

      nextCursorPosition++;
    }

    requestAnimationFrame(() => {
      inputRef.current?.setSelectionRange(
        nextCursorPosition,
        nextCursorPosition,
      );
    });
  };

  return (
    <input
      ref={inputRef}
      type="text"
      inputMode={currencyCode === "UGX" ? "numeric" : "decimal"}
      value={displayValue}
      onChange={handleChange}
      placeholder={placeholder}
      className={className}
      disabled={disabled}
      required={required}
      aria-label={ariaLabel}
      autoComplete="off"
    />
  );
}
