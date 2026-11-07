-- Weekly reading decks, look-alike character sets, per-card Again counts, and the 30-day interval cap.
-- The three linked tables are rebuilt to widen their CHECKs. Old tables are renamed away first and
-- dropped child-first, so no foreign key is ever broken, even mid-migration.

ALTER TABLE decks RENAME TO decks_old;
ALTER TABLE notes RENAME TO notes_old;
ALTER TABLE cards RENAME TO cards_old;

CREATE TABLE decks (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('master', 'sentences', 'reading', 'lookalikes')),
  reverse_mode TEXT NOT NULL CHECK (reverse_mode IN ('type', 'recall')),
  created_at INTEGER NOT NULL,
  updated_seq INTEGER NOT NULL
);

CREATE TABLE notes (
  id TEXT PRIMARY KEY,
  deck_id TEXT NOT NULL REFERENCES decks(id),
  kind TEXT NOT NULL CHECK (kind IN ('character', 'word', 'sentence', 'lookalike')),
  hanzi TEXT NOT NULL,
  pinyin TEXT NOT NULL,
  english TEXT NOT NULL,
  lesson_date TEXT,
  updated_seq INTEGER NOT NULL
);

-- agains: every time Again was pressed, including during learning steps (unlike lapses).
CREATE TABLE cards (
  id TEXT PRIMARY KEY,
  note_id TEXT NOT NULL REFERENCES notes(id),
  deck_id TEXT NOT NULL REFERENCES decks(id),
  direction TEXT NOT NULL CHECK (direction IN ('zh_en', 'en_zh')),
  phase TEXT NOT NULL CHECK (phase IN ('new', 'learning', 'review', 'relearning')),
  due INTEGER NOT NULL,
  stability REAL NOT NULL DEFAULT 0,
  difficulty REAL NOT NULL DEFAULT 0,
  elapsed_days REAL NOT NULL DEFAULT 0,
  scheduled_days REAL NOT NULL DEFAULT 0,
  reps INTEGER NOT NULL DEFAULT 0,
  lapses INTEGER NOT NULL DEFAULT 0,
  agains INTEGER NOT NULL DEFAULT 0,
  last_review INTEGER,
  held_by TEXT,
  updated_seq INTEGER NOT NULL
);

INSERT INTO decks SELECT id, name, kind, reverse_mode, created_at, updated_seq FROM decks_old;
INSERT INTO notes SELECT id, deck_id, kind, hanzi, pinyin, english, lesson_date, updated_seq FROM notes_old;
INSERT INTO cards (id, note_id, deck_id, direction, phase, due, stability, difficulty, elapsed_days, scheduled_days,
                   reps, lapses, last_review, held_by, updated_seq)
SELECT id, note_id, deck_id, direction, phase, due, stability, difficulty, elapsed_days, scheduled_days,
       reps, lapses, last_review, held_by, updated_seq FROM cards_old;

DROP TABLE cards_old;
DROP TABLE notes_old;
DROP TABLE decks_old;

CREATE UNIQUE INDEX notes_deck_hanzi ON notes (deck_id, hanzi);
CREATE INDEX cards_due ON cards (due);
CREATE INDEX cards_held_by ON cards (held_by);
CREATE INDEX cards_seq ON cards (updated_seq);
CREATE INDEX review_logs_time ON review_logs (reviewed_at);

UPDATE meta SET value = CAST(value AS INTEGER) + 1 WHERE key = 'seq';

UPDATE cards
SET agains = (SELECT COUNT(*) FROM review_logs r WHERE r.card_id = cards.id AND r.grade = 'again'),
    updated_seq = (SELECT CAST(value AS INTEGER) FROM meta WHERE key = 'seq');

-- English-first sentence cards mostly tested English, so they are retired: held by a card that never exists.
UPDATE cards SET held_by = 'retired'
WHERE direction = 'en_zh' AND deck_id IN (SELECT id FROM decks WHERE kind = 'sentences');

UPDATE cards
SET scheduled_days = 30, due = MIN(due, COALESCE(last_review, due) + 30 * 86400000)
WHERE scheduled_days > 30;
