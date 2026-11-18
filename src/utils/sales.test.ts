import { describe, expect, it } from "vitest";
import {
  getKnownPaymentMethod,
  PAYMENT_METHODS,
} from "./sales";

describe("payment method validation", () => {
  it.each(PAYMENT_METHODS)("accepts the recorded method %s", (method) => {
    expect(getKnownPaymentMethod(method)).toBe(method);
  });

  it.each([undefined, null, "", "Mobile money", "Cash "] as const)(
    "rejects an unknown payment method: %s",
    (method) => {
      expect(getKnownPaymentMethod(method)).toBeNull();
    },
  );
});
