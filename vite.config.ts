import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import { productionBuildConfigurationError } from "./src/lib/supabaseKey";

export default defineConfig(({ mode, command }) => {
  const env = loadEnv(mode, ".", "VITE_");
  if (command === "build") {
    const configurationError = productionBuildConfigurationError(
      env.VITE_SUPABASE_URL,
      env.VITE_SUPABASE_PUBLISHABLE_KEY,
    );

    if (configurationError) throw new Error(configurationError);
  }

  return {
    plugins: [react()],
  };
});
