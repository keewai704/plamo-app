import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    dir: "tests/e2e",
    testTimeout: 180_000,
    hookTimeout: 120_000,
    // The two browsers share one llama-server.
    fileParallelism: false,
  },
});
