import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig(({ command }) => ({
  plugins: [react()],
  base: command === "build" ? "/dashboard-assets/" : "/",
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
  server: {
    proxy: {
      "/api": "http://127.0.0.1:8080",
      "/health": "http://127.0.0.1:8080",
      "/auth": "http://127.0.0.1:8080",
      "/logout": "http://127.0.0.1:8080",
      "/download": "http://127.0.0.1:8080",
    },
  },
}));
