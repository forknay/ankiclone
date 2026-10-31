import { PUSH_HOUR, torontoParts } from "./config";
import { backlogOf, deckCounts } from "./db";

export interface PushMessage {
  title: string;
  body: string;
  lessonDate: string | null;
}

export interface PushDevice {
  token: string;
  environment: string;
}

/** Returns "sent", "gone" (token no longer valid) or "failed" (worth retrying). */
export type SendPush = (device: PushDevice, message: PushMessage) => Promise<"sent" | "gone" | "failed">;

interface LessonEntry {
  hanzi: string;
  pinyin: string;
  english: string;
}

/** Keeps the push well inside APNs' 4 KB limit, since Chinese text is 3 bytes per character. */
const MAX_LESSON_TEXT = 1000;

/** The lesson itself, so it can be read from the notification without opening the app. */
function lessonText(body: string): string {
  const lesson = JSON.parse(body) as { intro?: string; characters?: (LessonEntry & { uses?: LessonEntry[] })[] };
  const entry = ({ hanzi, pinyin, english }: LessonEntry) => `${hanzi} ${pinyin}: ${english}`;
  const characters = (lesson.characters ?? []).map((character) =>
    [character, ...(character.uses ?? []).slice(0, 2)].map(entry).join("\n"),
  );
  const text = [lesson.intro, ...characters].filter(Boolean).join("\n\n");
  const glyphs = Array.from(text);
  return glyphs.length > MAX_LESSON_TEXT ? `${glyphs.slice(0, MAX_LESSON_TEXT).join("")}…` : text;
}

export async function morningMessage(db: D1Database, now: Date): Promise<PushMessage | null> {
  const { date } = torontoParts(now);
  const backlog = backlogOf(await deckCounts(db, now.getTime()));
  const lesson = await db.prepare("SELECT title, body FROM lessons WHERE date = ?").bind(date).first<{ title: string; body: string }>();
  const due = `${backlog} card${backlog === 1 ? "" : "s"} due`;
  if (lesson) return { title: lesson.title, body: `${lessonText(lesson.body)}\n\n${due}.`.trim(), lessonDate: date };
  if (backlog > 0) return { title: due, body: "No new lesson today, just reviews.", lessonDate: null };
  return null;
}

/** Called every 15 minutes around 9 AM. Sends once a day, retrying within the hour if every device failed. */
export async function runMorningPush(db: D1Database, now: Date, send: SendPush): Promise<"not-time" | "already-sent" | "nothing" | "sent" | "failed"> {
  const { date, hour } = torontoParts(now);
  if (hour !== PUSH_HOUR) return "not-time";

  const sent = await db.prepare("SELECT value FROM meta WHERE key = 'last_push_date'").first<{ value: string }>();
  if (sent?.value === date) return "already-sent";

  const message = await morningMessage(db, now);
  const { results: devices } = await db.prepare("SELECT token, environment FROM devices").all<PushDevice>();
  if (!message || devices.length === 0) return "nothing";

  let delivered = 0;
  for (const device of devices) {
    const outcome = await send(device, message);
    if (outcome === "sent") delivered++;
    if (outcome === "gone") await db.prepare("DELETE FROM devices WHERE token = ?").bind(device.token).run();
  }
  if (delivered === 0) return "failed";

  await db
    .prepare("INSERT INTO meta (key, value) VALUES ('last_push_date', ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value")
    .bind(date)
    .run();
  return "sent";
}
