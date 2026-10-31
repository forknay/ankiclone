import { torontoParts } from "./config";
import { knownCharacters, nextSeq, todaysLimits } from "./db";
import { DailyInput, Entry, validateDaily } from "./validate";

export async function agentContext(db: D1Database, nowMs: number) {
  const { counts, backlog, limits } = await todaysLimits(db, nowMs);
  const today = torontoParts(new Date(nowMs)).date;

  const weak = await db
    .prepare(
      `SELECT n.hanzi, n.pinyin, n.english, MAX(c.lapses) AS lapses
       FROM cards c JOIN notes n ON n.id = c.note_id
       WHERE c.lapses > 0 GROUP BY n.id ORDER BY lapses DESC, MAX(c.difficulty) DESC LIMIT 30`,
    )
    .all();
  const recent = await db
    .prepare(
      `SELECT hanzi, pinyin, english, lesson_date AS lessonDate FROM notes
       WHERE deck_id = 'master' AND lesson_date IS NOT NULL ORDER BY lesson_date DESC, rowid DESC LIMIT 50`,
    )
    .all();
  const lessons = await db.prepare("SELECT date, title FROM lessons ORDER BY date DESC LIMIT 7").all();
  const existing = await db.prepare("SELECT 1 FROM lessons WHERE date = ?").bind(today).first();
  const known = await knownCharacters(db);

  return {
    today,
    lessonAlreadyPosted: existing !== null,
    backlog,
    limits,
    decks: counts,
    knownCharacters: known.join(""),
    knownCharacterCount: known.length,
    weakCards: weak.results,
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
  const errors = validateDaily(input, {
    today,
    known: new Set(await knownCharacters(db)),
    masterHanzi: new Set(master.results.map((row) => row.hanzi)),
    limits,
  });
  if (errors.length) return { status: 422, body: { ok: false, errors } };

  const seq = await nextSeq(db);
  const statements: D1PreparedStatement[] = [];

  const addNote = (deckId: string, kind: string, entry: Entry, reverse: boolean) => {
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
          .bind(crypto.randomUUID(), noteId, deckId, direction, direction === "en_zh" ? nowMs + 1 : nowMs, seq),
      );
    }
  };

  for (const character of input.characters) addNote("master", "character", character, true);
  for (const word of input.words) addNote("master", "word", word, true);

  if (input.sentences.length) {
    const deckId = `sentences-${input.date}`;
    statements.push(
      db
        .prepare(
          `INSERT INTO decks (id, name, kind, reverse_mode, created_at, updated_seq)
           VALUES (?, ?, 'sentences', 'recall', ?, ?)`,
        )
        .bind(deckId, `Sentences ${input.date}`, nowMs, seq),
    );
    for (const sentence of input.sentences) addNote(deckId, "sentence", sentence, sentence.reverse === true);
  }

  const body = JSON.stringify({
    intro: input.intro,
    characters: input.characters,
    words: input.words,
    sentenceCount: input.sentences.length,
  });
  statements.push(
    db
      .prepare("INSERT INTO lessons (date, title, body, created_at, updated_seq) VALUES (?, ?, ?, ?, ?)")
      .bind(input.date, input.title, body, nowMs, seq),
  );

  // D1 batches are a single transaction, so a failed run leaves nothing half-added.
  await db.batch(statements);
  return { status: 201, body: { ok: true, added: { characters: input.characters.length, words: input.words.length, sentences: input.sentences.length } } };
}
