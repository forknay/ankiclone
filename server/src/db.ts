import { limitsFor, LOOKALIKE_EVERY_DAYS, READING_EVERY_DAYS } from "./config";

export async function nextSeq(db: D1Database): Promise<number> {
  const row = await db
    .prepare("UPDATE meta SET value = CAST(value AS INTEGER) + 1 WHERE key = 'seq' RETURNING value")
    .first<{ value: string }>();
  return Number(row!.value);
}

export async function currentSeq(db: D1Database): Promise<number> {
  const row = await db.prepare("SELECT value FROM meta WHERE key = 'seq'").first<{ value: string }>();
  return Number(row!.value);
}

export interface DeckCounts {
  deckId: string;
  name: string;
  overdue: number;
  learning: number;
  fresh: number;
}

/** Hidden (held) cards never count. Everything else that is due counts towards the backlog. */
export async function deckCounts(db: D1Database, now: number): Promise<DeckCounts[]> {
  const { results } = await db
    .prepare(
      `SELECT d.id AS deckId, d.name AS name,
         COALESCE(SUM(c.phase = 'review' AND c.due <= ?1), 0) AS overdue,
         COALESCE(SUM(c.phase IN ('learning', 'relearning') AND c.due <= ?1), 0) AS learning,
         COALESCE(SUM(c.phase = 'new' AND c.due <= ?1), 0) AS fresh
       FROM decks d LEFT JOIN cards c ON c.deck_id = d.id AND c.held_by IS NULL
       GROUP BY d.id ORDER BY d.kind, d.created_at DESC`,
    )
    .bind(now)
    .all<DeckCounts>();
  return results;
}

export function backlogOf(counts: DeckCounts[]): number {
  return counts.reduce((sum, deck) => sum + deck.overdue + deck.learning + deck.fresh, 0);
}

const DAY_MS = 86_400_000;

/** Whether this week's reading deck and the next look-alike set are due. */
export async function materialDue(db: D1Database, now: number) {
  const reading = await db
    .prepare("SELECT MAX(created_at) AS last FROM decks WHERE kind = 'reading'")
    .first<{ last: number | null }>();
  const lookalikes = await db
    .prepare("SELECT MAX(lesson_date) AS last FROM notes WHERE kind = 'lookalike'")
    .first<{ last: string | null }>();
  // A little slack, so a routine that runs a few minutes earlier than last week still counts.
  const olderThan = (ms: number | null, days: number) => ms === null || now - ms >= days * DAY_MS - 6 * 3_600_000;
  return {
    reading: olderThan(reading?.last ?? null, READING_EVERY_DAYS),
    lookalikes: olderThan(lookalikes?.last ? Date.parse(`${lookalikes.last}T12:00:00Z`) : null, LOOKALIKE_EVERY_DAYS),
  };
}

export async function todaysLimits(db: D1Database, now: number) {
  const counts = await deckCounts(db, now);
  const backlog = backlogOf(counts);
  const due = await materialDue(db, now);
  return { counts, backlog, due, limits: limitsFor(backlog, due) };
}

export async function knownCharacters(db: D1Database): Promise<string[]> {
  const { results } = await db
    .prepare("SELECT hanzi FROM notes WHERE deck_id = 'master' AND kind = 'character' ORDER BY rowid")
    .all<{ hanzi: string }>();
  return results.map((row) => row.hanzi);
}
