export function isSecretSupabaseKey(key: string): boolean {
  if (key.startsWith("sb_secret_")) return true;

  const payload = key.split(".")[1];
  if (!payload) return false;

  try {
    const decodeBase64 = (
      globalThis as unknown as { atob?: (value: string) => string }
    ).atob;
    if (!decodeBase64) return false;

    const base64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    const decoded = decodeBase64(base64.padEnd(Math.ceil(base64.length / 4) * 4, "="));
    return JSON.parse(decoded).role === "service_role";
  } catch {
    return false;
  }
}

export function productionBuildConfigurationError(
  urlValue: string | undefined,
  publishableKeyValue: string | undefined,
): string | null {
  const url = urlValue?.trim() ?? "";
  const publishableKey = publishableKeyValue?.trim() ?? "";

  if (!url || !publishableKey) {
    return "Production builds require VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY.";
  }

  if (isSecretSupabaseKey(publishableKey)) {
    return "A Supabase secret or service-role key cannot be used in a browser build. Use a publishable key.";
  }

  return null;
}
