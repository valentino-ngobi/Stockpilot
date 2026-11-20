export function resetPasswordEntry(
  setPassword: (value: string) => void,
  setPasswordVisible: (value: boolean) => void,
): void {
  setPassword("");
  setPasswordVisible(false);
}
