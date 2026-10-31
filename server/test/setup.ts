import { applyD1Migrations } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { beforeEach } from "vitest";

await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM cards"),
    env.DB.prepare("DELETE FROM notes"),
    env.DB.prepare("DELETE FROM review_logs"),
    env.DB.prepare("DELETE FROM lessons"),
    env.DB.prepare("DELETE FROM devices"),
    env.DB.prepare("DELETE FROM decks WHERE id != 'master'"),
    env.DB.prepare("DELETE FROM meta WHERE key != 'seq'"),
  ]);
});
