import { renderToStaticMarkup } from "react-dom/server";
import { Children, isValidElement } from "react";
import { describe, expect, it, vi } from "vitest";
import PasswordVisibilityControl from "./PasswordVisibilityControl";
import { togglePasswordVisibility } from "../lib/passwordVisibility";

describe("password visibility control", () => {
  it("starts hidden with an accessible non-submit toggle button", () => {
    const markup = renderToStaticMarkup(
      <PasswordVisibilityControl
        id="auth-password"
        labelledBy="auth-password-label"
        value="fictional-passphrase"
        visible={false}
        autoComplete="current-password"
        onChange={() => undefined}
        onToggle={() => undefined}
      />,
    );

    expect(markup).toContain('type="password"');
    expect(markup).toContain('value="fictional-passphrase"');
    expect(markup).toContain('type="button"');
    expect(markup).toContain('aria-label="Show password"');
    expect(markup).toContain('aria-pressed="false"');
  });

  it("shows and hides the same controlled password value", () => {
    const password = "fictional-passphrase";
    const shownMarkup = renderToStaticMarkup(
      <PasswordVisibilityControl
        id="auth-password"
        labelledBy="auth-password-label"
        value={password}
        visible={true}
        autoComplete="new-password"
        onChange={() => undefined}
        onToggle={() => undefined}
      />,
    );
    const hiddenMarkup = renderToStaticMarkup(
      <PasswordVisibilityControl
        id="auth-password"
        labelledBy="auth-password-label"
        value={password}
        visible={togglePasswordVisibility(true)}
        autoComplete="new-password"
        onChange={() => undefined}
        onToggle={() => undefined}
      />,
    );

    expect(togglePasswordVisibility(false)).toBe(true);
    expect(shownMarkup).toContain('type="text"');
    expect(shownMarkup).toContain('aria-label="Hide password"');
    expect(hiddenMarkup).toContain('type="password"');
    expect(hiddenMarkup).toContain('value="fictional-passphrase"');
  });

  it("activates through the semantic button and preserves input focus on mouse down", () => {
    const onToggle = vi.fn();
    const control = PasswordVisibilityControl({
      id: "auth-password",
      labelledBy: "auth-password-label",
      value: "fictional-passphrase",
      visible: false,
      autoComplete: "current-password",
      onChange: () => undefined,
      onToggle,
    });
    const button = Children.toArray(control.props.children).find(
      (child) => isValidElement(child) && child.type === "button",
    );

    type ToggleButtonProps = {
      type: "button";
      "aria-label": string;
      onClick: () => void;
      onMouseDown: (event: { preventDefault: () => void }) => void;
    };
    expect(isValidElement<ToggleButtonProps>(button)).toBe(true);
    if (!isValidElement<ToggleButtonProps>(button)) return;
    expect(button.props.type).toBe("button");
    expect(button.props["aria-label"]).toBe("Show password");
    (button.props.onClick as () => void)();
    expect(onToggle).toHaveBeenCalledOnce();

    const preventDefault = vi.fn();
    (button.props.onMouseDown as (event: { preventDefault: () => void }) => void)(
      { preventDefault },
    );
    expect(preventDefault).toHaveBeenCalledOnce();
  });
});
