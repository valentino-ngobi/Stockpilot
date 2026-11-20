import { createClient } from "@supabase/supabase-js";
import { resolveSupabaseConfiguration } from "./supabaseConfig";

export const supabaseConfiguration = resolveSupabaseConfiguration(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
  {
    isDevelopment: import.meta.env.DEV,
    prototypeEnabled: import.meta.env.VITE_STOCKPILOT_PROTOTYPE?.trim() === "true",
  },
);

export const supabase =
  supabaseConfiguration.mode === "configured"
    ? createClient(
        supabaseConfiguration.url,
        supabaseConfiguration.publishableKey,
        {
          auth: {
            persistSession: true,
            autoRefreshToken: true,
            detectSessionInUrl: true,
            storageKey: "stockpilot-supabase-auth-v1",
          },
        },
      )
    : null;
