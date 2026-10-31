import { agentContext, postDaily } from "./agent";
import { apnsSender, ApnsConfig } from "./apns";
import { PushDevice, runMorningPush } from "./push";
import { sync, syncInputError, SyncInput } from "./sync";
import type { DailyInput } from "./validate";

export interface Env extends ApnsConfig {
  DB: D1Database;
  APP_TOKEN: string;
  AGENT_TOKEN: string;
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

/** Constant-time comparison. An unset secret never matches. */
async function tokenMatches(given: string, expected: string | undefined): Promise<boolean> {
  if (!expected) return false;
  const digest = async (text: string) => new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  const [a, b] = await Promise.all([digest(given), digest(expected)]);
  return a.reduce((difference, byte, index) => difference | (byte ^ b[index]), 0) === 0;
}

async function readJson<T>(request: Request): Promise<T | null> {
  try {
    return (await request.json()) as T;
  } catch {
    return null;
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const { pathname } = new URL(request.url);
    const route = `${request.method} ${pathname}`;
    const token = (request.headers.get("authorization") ?? "").replace(/^Bearer /, "");
    const now = Date.now();

    // The app and the morning routine have separate tokens, so neither can use the other's endpoints.
    if (route === "GET /agent/context" || route === "POST /agent/daily" || route === "POST /agent/test-push") {
      if (!(await tokenMatches(token, env.AGENT_TOKEN))) return json({ error: "unauthorized" }, 401);
      if (route === "POST /agent/test-push") {
        const { results: devices } = await env.DB.prepare("SELECT token, environment FROM devices").all<PushDevice>();
        const send = apnsSender(env, new Date(now));
        const message = { title: "Test notification", body: "Push is working.", lessonDate: null };
        return json({ outcomes: await Promise.all(devices.map((device) => send(device, message))) });
      }
      if (route === "GET /agent/context") return json(await agentContext(env.DB, now));
      const input = await readJson<DailyInput>(request);
      if (!input) return json({ ok: false, errors: ["body must be JSON"] }, 400);
      const result = await postDaily(env.DB, input, now);
      return json(result.body, result.status);
    }

    if (route === "POST /sync" || route === "POST /devices") {
      if (!(await tokenMatches(token, env.APP_TOKEN))) return json({ error: "unauthorized" }, 401);
      if (route === "POST /sync") {
        const input = await readJson<SyncInput>(request);
        const problem = input ? syncInputError(input) : "body must be JSON";
        if (problem) return json({ error: problem }, 400);
        return json(await sync(env.DB, input!));
      }
      const device = await readJson<{ token: string; environment: string }>(request);
      if (typeof device?.token !== "string" || !/^[0-9a-fA-F]+$/.test(device.token)) return json({ error: "invalid token" }, 400);
      if (device.environment !== "sandbox" && device.environment !== "production") return json({ error: "invalid environment" }, 400);
      await env.DB.prepare(
        `INSERT INTO devices (token, environment, updated_at) VALUES (?, ?, ?)
         ON CONFLICT (token) DO UPDATE SET environment = excluded.environment, updated_at = excluded.updated_at`,
      )
        .bind(device.token, device.environment, now)
        .run();
      return json({ ok: true });
    }

    return json({ error: "not found" }, 404);
  },

  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    const now = new Date();
    const outcome = await runMorningPush(env.DB, now, apnsSender(env, now));
    console.log(`morning push: ${outcome}`);
  },
};
