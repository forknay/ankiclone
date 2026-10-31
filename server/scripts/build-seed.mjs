// Turns seed/master.tsv into seed/master.sql, checking it against the list of learned characters.
// Usage: node scripts/build-seed.mjs <learned_characters.txt>
import { readFileSync, writeFileSync } from "node:fs";

const expected = [...readFileSync(process.argv[2], "utf8").matchAll(/\p{Script=Han}/gu)].map((match) => match[0]);
const rows = readFileSync("seed/master.tsv", "utf8").trim().split("\n").map((line) => line.split("\t"));

const errors = [];
const seen = new Set();
for (const [hanzi, pinyin, english] of rows) {
  if (seen.has(hanzi)) errors.push(`duplicate: ${hanzi}`);
  seen.add(hanzi);
  if (!/^[a-züāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ]+$/.test(pinyin ?? "")) errors.push(`bad pinyin for ${hanzi}: ${pinyin}`);
  if (!english?.trim()) errors.push(`missing english: ${hanzi}`);
  if (!expected.includes(hanzi)) errors.push(`not in learned list: ${hanzi}`);
}
for (const hanzi of expected) if (!seen.has(hanzi)) errors.push(`missing from seed: ${hanzi}`);
if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(1);
}

const sql = (text) => `'${text.replaceAll("'", "''")}'`;
// Already known, so Chinese-first cards start as reviews due now, with the state FSRS gives a
// first "Good" and three days elapsed. English-first cards stay hidden until the first review.
const NOW = "CAST(strftime('%s', 'now') AS INTEGER) * 1000";
const lines = rows.flatMap(([hanzi, pinyin, english]) => {
  const key = hanzi.codePointAt(0).toString(16);
  return [
    `INSERT OR IGNORE INTO notes (id, deck_id, kind, hanzi, pinyin, english, updated_seq) VALUES ('note-${key}', 'master', 'character', ${sql(hanzi)}, ${sql(pinyin)}, ${sql(english)}, 1);`,
    `INSERT OR IGNORE INTO cards (id, note_id, deck_id, direction, phase, due, stability, difficulty, elapsed_days, scheduled_days, reps, last_review, updated_seq) VALUES ('card-${key}-zh', 'note-${key}', 'master', 'zh_en', 'review', ${NOW}, 3.1262, 5.3145, 3, 3, 1, ${NOW} - 259200000, 1);`,
    `INSERT OR IGNORE INTO cards (id, note_id, deck_id, direction, phase, due, held_by, updated_seq) VALUES ('card-${key}-en', 'note-${key}', 'master', 'en_zh', 'new', ${NOW}, 'card-${key}-zh', 1);`,
  ];
});
writeFileSync("seed/master.sql", lines.join("\n") + "\n");
console.log(`seed/master.sql: ${rows.length} characters`);
