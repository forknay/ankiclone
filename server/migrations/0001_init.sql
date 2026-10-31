CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO meta (key, value) VALUES ('seq', '1');

CREATE TABLE decks (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('master', 'sentences')),
  reverse_mode TEXT NOT NULL CHECK (reverse_mode IN ('type', 'recall')),
  created_at INTEGER NOT NULL,
  updated_seq INTEGER NOT NULL
);
INSERT INTO decks (id, name, kind, reverse_mode, created_at, updated_seq)
VALUES ('master', 'Master', 'master', 'type', 0, 1);

CREATE TABLE notes (
  id TEXT PRIMARY KEY,
  deck_id TEXT NOT NULL REFERENCES decks(id),
  kind TEXT NOT NULL CHECK (kind IN ('character', 'word', 'sentence')),
  hanzi TEXT NOT NULL,
  pinyin TEXT NOT NULL,
  english TEXT NOT NULL,
  lesson_date TEXT,
  updated_seq INTEGER NOT NULL
);
CREATE UNIQUE INDEX notes_deck_hanzi ON notes (deck_id, hanzi);

-- Times are epoch milliseconds. held_by: this card stays hidden until that card is first reviewed.
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
  last_review INTEGER,
  held_by TEXT,
  updated_seq INTEGER NOT NULL
);
CREATE INDEX cards_due ON cards (due);
CREATE INDEX cards_held_by ON cards (held_by);
CREATE INDEX cards_seq ON cards (updated_seq);

-- Every grade ever given, so the scheduler can be swapped or re-run later.
CREATE TABLE review_logs (
  id TEXT PRIMARY KEY,
  card_id TEXT NOT NULL,
  grade TEXT NOT NULL CHECK (grade IN ('again', 'hard', 'good', 'easy')),
  reviewed_at INTEGER NOT NULL,
  typed_answer TEXT
);
CREATE INDEX review_logs_card ON review_logs (card_id);

CREATE TABLE lessons (
  date TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_seq INTEGER NOT NULL
);

CREATE TABLE devices (
  token TEXT PRIMARY KEY,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  updated_at INTEGER NOT NULL
);
