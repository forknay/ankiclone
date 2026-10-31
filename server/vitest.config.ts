import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig(async () => ({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.toml" },
      miniflare: {
        bindings: {
          APP_TOKEN: "app-test-token",
          AGENT_TOKEN: "agent-test-token",
          TEST_MIGRATIONS: await readD1Migrations("./migrations"),
        },
      },
    }),
  ],
  test: { setupFiles: ["./test/setup.ts"] },
}));
