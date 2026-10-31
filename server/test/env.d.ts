declare namespace Cloudflare {
  interface Env {
    DB: D1Database;
    APP_TOKEN: string;
    AGENT_TOKEN: string;
    TEST_MIGRATIONS: import("cloudflare:test").D1Migration[];
  }
}
