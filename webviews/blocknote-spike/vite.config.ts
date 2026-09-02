import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// Static, relocatable output — this bundle is loaded from a `file://`
// URL inside a WKWebView (see BlockNoteSpikeView.swift), not served from
// a dev server, so asset URLs must be relative rather than root-absolute.
export default defineConfig({
  plugins: [react()],
  base: "./",
  build: {
    outDir: "dist"
  }
});
