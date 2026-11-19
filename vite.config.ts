import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import { isSecretSupabaseKey } from "./src/lib/supabaseKey";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, ".", "VITE_");
  const publishableKey = env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() ?? "";

  if (isSecretSupabaseKey(publishableKey)) {
    throw new Error(
      "A Supabase secret or service-role key cannot be bundled in a browser build. Use a publishable key.",
    );
  }

  return {
    plugins: [react()],
  };
});
