import { describe, expect, it, vi } from "vitest";
import { resetPasswordEntry } from "./passwordState";

describe("authentication password state cleanup", () => {
  it("clears the entered password and hides it", () => {
    const setPassword = vi.fn();
    const setPasswordVisible = vi.fn();

    resetPasswordEntry(setPassword, setPasswordVisible);

    expect(setPassword).toHaveBeenCalledWith("");
    expect(setPasswordVisible).toHaveBeenCalledWith(false);
  });
});
