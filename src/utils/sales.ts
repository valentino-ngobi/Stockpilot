export const PAYMENT_METHODS = [
  "Cash",
  "MTN Mobile Money",
  "Airtel Money",
  "Bank Transfer",
] as const;

export type PaymentMethod = (typeof PAYMENT_METHODS)[number];

export function getKnownPaymentMethod(
  value: unknown,
): PaymentMethod | null {
  return typeof value === "string"
    ? PAYMENT_METHODS.find((method) => method === value) ?? null
    : null;
}
