import { torontoParts } from "./config";
import { knownCharacters, nextSeq, todaysLimits } from "./db";
import { READING_NEW_PER_DAY } from "./config";
import { DailyInput, Entry, LOOKALIKE_SEPARATOR, lookalikeKey, validateDaily } from "./validate";

const DAY_MS = 86_400_000;

export async function agentContext(db: D1Database, nowMs: number) {
  const { counts, backlog, due, limits } = await todaysLimits(db, nowMs);
  const today = torontoParts(new Date(nowMs)).date;

  // Every Again counts, including during learning steps, and recent ones count most.
  const struggling = await db
    .prepare(
      `SELECT n.hanzi, n.pinyin, n.english, n.kind, c.direction,
         SUM(r.grade = 'again' AND r.reviewed_at >= ?1) AS againsLastDay,
         SUM(r.grade = 'again' AND r.reviewed_at >= ?2) AS againsLastWeek,
         SUM(r.grade = 'again') AS againsLastMonth,
         COUNT(*) AS reviewsLastMonth
       FROM review_logs r JOIN cards c ON c.id = r.card_id JOIN notes n ON n.id = c.note_id
       WHERE r.reviewed_at >= ?3 AND n.kind != 'sentence'
       GROUP BY n.id, c.direction
       HAVING againsLastMonth > 0
       ORDER BY 3 * againsLastDay + againsLastWeek + 0.25 * againsLastMonth DESC
       LIMIT 40`,
    )
    .bind(nowMs - DAY_MS, nowMs - 7 * DAY_MS, nowMs - 30 * DAY_MS)
    .all();
  const lastDay = await db
    .prepare("SELECT COUNT(*) AS reviews, COALESCE(SUM(grade = 'again'), 0) AS agains FROM review_logs WHERE reviewed_at >= ?")
    .bind(nowMs - DAY_MS)
    .first();
  const recent = await db
    .prepare(
      `SELECT hanzi, pinyin, english, lesson_date AS lessonDate FROM notes
       WHERE deck_id = 'master' AND lesson_date IS NOT NULL ORDER BY lesson_date DESC, rowid DESC LIMIT 50`,
    )
    .all();
  const lookalikes = await db.prepare("SELECT hanzi FROM notes WHERE kind = 'lookalike'").all<{ hanzi: string }>();
  const lessons = await db.prepare("SELECT date, title FROM lessons ORDER BY date DESC LIMIT 7").all();
  const existing = await db.prepare("SELECT 1 FROM lessons WHERE date = ?").bind(today).first();
  const known = await knownCharacters(db);

  return {
    today,
    lessonAlreadyPosted: existing !== null,
    backlog,
    limits,
    readingDeckDue: limits.sentences > 0,
    lookalikesDue: due.lookalikes,
    decks: counts,
    knownCharacters: known.join(""),
    knownCharacterCount: known.length,
    lastDay,
    struggling: struggling.results,
    lookalikeGroupsUsed: lookalikes.results.map((row) => row.hanzi),
    recentlyLearned: recent.results,
    recentLessons: lessons.results,
  };
}

type DailyResult = { status: 200 | 201 | 422; body: unknown };

export async function postDaily(db: D1Database, input: DailyInput, nowMs: number): Promise<DailyResult> {
  const today = torontoParts(new Date(nowMs)).date;
  const existing = await db.prepare("SELECT 1 FROM lessons WHERE date = ?").bind(input?.date ?? "").first();
  if (existing) return { status: 200, body: { ok: true, alreadyPosted: true } };

  const { limits } = await todaysLimits(db, nowMs);
  const master = await db.prepare("SELECT hanzi FROM notes WHERE deck_id = 'master'").all<{ hanzi: string }>();
  const groups = await db.prepare("SELECT hanzi FROM notes WHERE kind = 'lookalike'").all<{ hanzi: string }>();
  const errors = validateDaily(input, {
    today,
    known: new Set(await knownCharacters(db)),
    masterHanzi: new Set(master.results.map((row) => row.hanzi)),
    limits,
    lookalikeKeys: new Set(groups.results.map((row) => lookalikeKey(row.hanzi))),
  });
  if (errors.length) return { status: 422, body: { ok: false, errors } };

  const seq = await nextSeq(db);
  const statements: D1PreparedStatement[] = [];

  const addNote = (deckId: string, kind: string, entry: Entry, reverse: boolean, due = nowMs) => {
    const noteId = crypto.randomUUID();
    statements.push(
      db
        .prepare(
          `INSERT INTO notes (id, deck_id, kind, hanzi, pinyin, english, lesson_date, updated_seq)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        )
        .bind(noteId, deckId, kind, entry.hanzi, entry.pinyin.trim(), entry.english.trim(), input.date, seq),
    );
    const directions = reverse ? ["zh_en", "en_zh"] : ["zh_en"];
    for (const direction of directions) {
      statements.push(
        db
          .prepare(
            `INSERT INTO cards (id, note_id, deck_id, direction, phase, due, updated_seq)
             VALUES (?, ?, ?, ?, 'new', ?, ?)`,
          )
          // Due a moment later, so a new note's Chinese-first card always comes up first.
          .bind(crypto.randomUUID(), noteId, deckId, direction, direction === "en_zh" ? due + 1 : due, seq),
      );
    }
  };

  for (const character of input.characters) addNote("master", "character", character, true);
  for (const word of input.words) addNote("master", "word", word, true);

  // The week's reading deck unlocks a few new sentences per day, so learning steps don't pile up.
  if (input.sentences.length) {
    const deckId = `reading-${input.date}`;
    statements.push(
      db
        .prepare(
          `INSERT INTO decks (id, name, kind, reverse_mode, created_at, updated_seq)
           VALUES (?, ?, 'reading', 'recall', ?, ?)`,
        )
        .bind(deckId, `Reading ${input.date}`, nowMs, seq),
    );
    input.sentences.forEach((sentence, index) =>
      addNote(deckId, "sentence", sentence, false, nowMs + Math.floor(index / READING_NEW_PER_DAY) * DAY_MS),
    );
  }

  const lookalikes = input.lookalikes ?? [];
  if (lookalikes.length) {
    statements.push(
      db
        .prepare(
          `INSERT OR IGNORE INTO decks (id, name, kind, reverse_mode, created_at, updated_seq)
           VALUES ('lookalikes', 'Look-alikes', 'lookalikes', 'recall', 1, ?)`,
        )
        .bind(seq),
    );
  }
  for (const { members } of lookalikes) {
    addNote("lookalikes", "lookalike", {
      hanzi: members.map((member) => member.hanzi).join(""),
      pinyin: members.map((member) => member.pinyin.trim()).join(" "),
      english: members.map((member) => member.english.trim()).join(LOOKALIKE_SEPARATOR),
    }, false);
  }

  const body = JSON.stringify({
    intro: input.intro,
    characters: input.characters,
    words: input.words,
    sentenceCount: input.sentences.length,
    lookalikes: lookalikes.map(({ members }) => members.map((member) => member.hanzi).join("")),
  });
  statements.push(
    db
      .prepare("INSERT INTO lessons (date, title, body, created_at, updated_seq) VALUES (?, ?, ?, ?, ?)")
      .bind(input.date, input.title, body, nowMs, seq),
  );

  // D1 batches are a single transaction, so a failed run leaves nothing half-added.
  await db.batch(statements);
  return {
    status: 201,
    body: {
      ok: true,
      added: {
        characters: input.characters.length,
        words: input.words.length,
        sentences: input.sentences.length,
        lookalikes: lookalikes.length,
      },
    },
  };
}
