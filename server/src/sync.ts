import { currentSeq, nextSeq } from "./db";

interface CardState {
  phase: string;
  due: number;
  stability: number;
  difficulty: number;
  elapsedDays: number;
  scheduledDays: number;
  reps: number;
  lapses: number;
  lastReview: number | null;
}

interface ReviewUpload {
  id: string;
  cardId: string;
  grade: string;
  reviewedAt: number;
  typedAnswer?: string | null;
  state: CardState;
}

export interface SyncInput {
  cursor: number;
  reviews: ReviewUpload[];
  deckSettings: { deckId: string; reverseMode: string }[];
}

const GRADES = new Set(["again", "hard", "good", "easy"]);
const PHASES = new Set(["new", "learning", "review", "relearning"]);

export function syncInputError(input: SyncInput): string | null {
  if (!Number.isInteger(input?.cursor) || input.cursor < 0) return "cursor must be a non-negative integer";
  if (!Array.isArray(input.reviews) || !Array.isArray(input.deckSettings)) return "reviews and deckSettings must be arrays";
  for (const review of input.reviews) {
    if (typeof review?.id !== "string" || typeof review.cardId !== "string") return "review id and cardId are required";
    if (!GRADES.has(review.grade)) return `invalid grade: ${review.grade}`;
    if (!Number.isFinite(review.reviewedAt)) return "reviewedAt must be a number";
    if (!PHASES.has(review.state?.phase)) return `invalid phase: ${review.state?.phase}`;
    if (!Number.isFinite(review.state.due)) return "state.due must be a number";
  }
  for (const setting of input.deckSettings) {
    if (setting?.reverseMode !== "type" && setting?.reverseMode !== "recall") return "reverseMode must be type or recall";
  }
  return null;
}

export async function sync(db: D1Database, input: SyncInput) {
  if (input.reviews.length || input.deckSettings.length) {
    const seq = await nextSeq(db);
    const statements: D1PreparedStatement[] = [];
    // Re-uploading a review is harmless: the log insert is ignored, and the card only
    // takes state from a review at least as new as the one it already has.
    for (const review of input.reviews) {
      const reviewedAt = Math.round(review.reviewedAt);
      const state = review.state;
      statements.push(
        db
          .prepare("INSERT OR IGNORE INTO review_logs (id, card_id, grade, reviewed_at, typed_answer) VALUES (?, ?, ?, ?, ?)")
          .bind(review.id, review.cardId, review.grade, reviewedAt, review.typedAnswer ?? null),
        db
          .prepare(
            `UPDATE cards SET phase = ?, due = ?, stability = ?, difficulty = ?, elapsed_days = ?, scheduled_days = ?,
               reps = ?, lapses = ?, last_review = ?, held_by = NULL, updated_seq = ?
             WHERE id = ? AND COALESCE(last_review, 0) <= ?`,
          )
          .bind(
            state.phase,
            Math.round(state.due),
            state.stability,
            state.difficulty,
            state.elapsedDays,
            state.scheduledDays,
            state.reps,
            state.lapses,
            reviewedAt,
            seq,
            review.cardId,
            reviewedAt,
          ),
        db.prepare("UPDATE cards SET held_by = NULL, updated_seq = ? WHERE held_by = ?").bind(seq, review.cardId),
      );
    }
    for (const setting of input.deckSettings) {
      statements.push(
        db.prepare("UPDATE decks SET reverse_mode = ?, updated_seq = ? WHERE id = ?").bind(setting.reverseMode, seq, setting.deckId),
      );
    }
    await db.batch(statements);
  }

  const cursor = await currentSeq(db);
  const since = (sql: string) => db.prepare(sql).bind(input.cursor, cursor);
  const [decks, notes, cards, lessons] = await db.batch([
    since(
      `SELECT id, name, kind, reverse_mode AS reverseMode, created_at AS createdAt
       FROM decks WHERE updated_seq > ? AND updated_seq <= ?`,
    ),
    since(
      `SELECT id, deck_id AS deckId, kind, hanzi, pinyin, english, lesson_date AS lessonDate
       FROM notes WHERE updated_seq > ? AND updated_seq <= ?`,
    ),
    since(
      `SELECT id, note_id AS noteId, deck_id AS deckId, direction, phase, due, stability, difficulty,
         elapsed_days AS elapsedDays, scheduled_days AS scheduledDays, reps, lapses,
         last_review AS lastReview, held_by AS heldBy
       FROM cards WHERE updated_seq > ? AND updated_seq <= ?`,
    ),
    since("SELECT date, title, body FROM lessons WHERE updated_seq > ? AND updated_seq <= ?"),
  ]);
  return { cursor, decks: decks.results, notes: notes.results, cards: cards.results, lessons: lessons.results };
}
