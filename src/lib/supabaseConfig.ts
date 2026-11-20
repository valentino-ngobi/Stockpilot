import { isSecretSupabaseKey } from "./supabaseKey";

export { productionBuildConfigurationError } from "./supabaseKey";

export type SupabaseConfiguration =
  | { mode: "prototype" }
  | { mode: "invalid"; message: string }
  | { mode: "configured"; url: string; publishableKey: string };

export type SupabaseConfigurationEnvironment = {
  isDevelopment: boolean;
  prototypeEnabled: boolean;
};

export function resolveSupabaseConfiguration(
  urlValue: string | undefined,
  publishableKeyValue: string | undefined,
  environment: SupabaseConfigurationEnvironment = {
    isDevelopment: false,
    prototypeEnabled: false,
  },
): SupabaseConfiguration {
  const url = urlValue?.trim() ?? "";
  const publishableKey = publishableKeyValue?.trim() ?? "";

  if (!url && !publishableKey) {
    if (environment.isDevelopment && environment.prototypeEnabled) {
      return { mode: "prototype" };
    }

    return {
      mode: "invalid",
      message:
        "Supabase configuration is required. Local prototype mode must be explicitly enabled during development.",
    };
  }

  if (!url || !publishableKey) {
    return {
      mode: "invalid",
      message:
        "Both VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY are required. Check the local environment file; no data was changed.",
    };
  }

  if (isSecretSupabaseKey(publishableKey)) {
    return {
      mode: "invalid",
      message:
        "A Supabase secret or service-role key cannot be used in browser configuration. Use a publishable key; no local data was opened.",
    };
  }

  try {
    const parsedUrl = new URL(url);
    const isLocalHttp =
      parsedUrl.protocol === "http:" &&
      ["localhost", "127.0.0.1", "[::1]"].includes(parsedUrl.hostname);

    if (parsedUrl.protocol !== "https:" && !isLocalHttp) {
      throw new Error("Use HTTPS, except for a local development URL.");
    }
  } catch {
    return {
      mode: "invalid",
      message:
        "VITE_SUPABASE_URL must be a valid HTTPS URL (or a local HTTP URL for development). No LocalStorage workflow was opened.",
    };
  }

  return { mode: "configured", url, publishableKey };
}
