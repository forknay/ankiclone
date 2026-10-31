export interface Entry {
  hanzi: string;
  pinyin: string;
  english: string;
}

export interface Character extends Entry {
  uses: Entry[];
}

export interface Sentence extends Entry {
  reverse?: boolean;
}

export interface DailyInput {
  date: string;
  title: string;
  intro: string;
  characters: Character[];
  words: Entry[];
  sentences: Sentence[];
}

const HAN = /\p{Script=Han}/gu;
const SENTENCE_TEXT = /^[\p{Script=Han}，。？！、：；“”‘’（）…—\s]+$/u;
const SYLLABLE = /^[a-züāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜńňǹḿ]+$/;

export function hanOf(text: string): string[] {
  return text.match(HAN) ?? [];
}

function checkEntry(entry: Entry | undefined, label: string, errors: string[]): boolean {
  if (typeof entry?.hanzi !== "string" || typeof entry?.pinyin !== "string" || typeof entry?.english !== "string") {
    errors.push(`${label}: hanzi, pinyin and english must all be strings`);
    return false;
  }
  if (!entry.english.trim()) errors.push(`${label}: english is empty`);
  if (!SENTENCE_TEXT.test(entry.hanzi)) {
    errors.push(`${label}: "${entry.hanzi}" must contain only Chinese characters and Chinese punctuation (write numbers in characters)`);
  }
  const syllables = entry.pinyin.trim().split(/\s+/);
  const bad = syllables.filter((syllable) => !SYLLABLE.test(syllable));
  if (bad.length) errors.push(`${label}: invalid pinyin syllables: ${bad.join(" ")} (lowercase, tone marks, no punctuation)`);
  const count = hanOf(entry.hanzi).length;
  if (syllables.length !== count) {
    errors.push(`${label}: "${entry.hanzi}" has ${count} characters but pinyin has ${syllables.length} syllables`);
  }
  return true;
}

export interface DailyRules {
  today: string;
  known: Set<string>;
  masterHanzi: Set<string>;
  limits: { characters: number; sentences: number };
}

/** Returns every problem at once, so the routine can fix them all in one retry. */
export function validateDaily(input: DailyInput, rules: DailyRules): string[] {
  const errors: string[] = [];
  if (input.date !== rules.today) errors.push(`date must be today, ${rules.today}`);
  if (typeof input.title !== "string" || !input.title.trim()) errors.push("title is required");
  if (typeof input.intro !== "string" || !input.intro.trim()) errors.push("intro is required");
  for (const field of ["characters", "words", "sentences"] as const) {
    if (!Array.isArray(input[field])) errors.push(`${field} must be an array`);
  }
  if (errors.length) return errors;

  if (input.characters.length > rules.limits.characters) {
    errors.push(`${input.characters.length} new characters exceeds today's limit of ${rules.limits.characters}`);
  }
  if (input.sentences.length > rules.limits.sentences) {
    errors.push(`${input.sentences.length} sentences exceeds today's limit of ${rules.limits.sentences}`);
  }

  const allowed = new Set(rules.known);
  const seen = new Set(rules.masterHanzi);
  input.characters.forEach((character, index) => {
    const label = `characters[${index}]`;
    if (!checkEntry(character, label, errors)) return;
    if (hanOf(character.hanzi).length !== 1 || character.hanzi.length !== 1) {
      errors.push(`${label}: "${character.hanzi}" must be a single character (put words in "words")`);
    }
    if (seen.has(character.hanzi)) errors.push(`${label}: "${character.hanzi}" is already in the master deck`);
    seen.add(character.hanzi);
    allowed.add(character.hanzi);
    if (!Array.isArray(character.uses) || character.uses.length === 0) {
      errors.push(`${label}: at least one common use is required`);
    } else {
      character.uses.forEach((use, useIndex) => checkEntry(use, `${label}.uses[${useIndex}]`, errors));
    }
  });

  const unknownIn = (text: string) => [...new Set(hanOf(text).filter((han) => !allowed.has(han)))];

  input.words.forEach((word, index) => {
    const label = `words[${index}]`;
    if (!checkEntry(word, label, errors)) return;
    if (seen.has(word.hanzi)) errors.push(`${label}: "${word.hanzi}" is already in the master deck`);
    seen.add(word.hanzi);
    const unknown = unknownIn(word.hanzi);
    if (unknown.length) errors.push(`${label}: "${word.hanzi}" uses unknown characters: ${unknown.join("")}`);
  });

  const sentences = new Set<string>();
  input.sentences.forEach((sentence, index) => {
    const label = `sentences[${index}]`;
    if (!checkEntry(sentence, label, errors)) return;
    if (sentences.has(sentence.hanzi)) errors.push(`${label}: duplicate of an earlier sentence`);
    sentences.add(sentence.hanzi);
    const unknown = unknownIn(sentence.hanzi);
    if (unknown.length) errors.push(`${label}: "${sentence.hanzi}" uses unknown characters: ${unknown.join("")}`);
  });

  return errors;
}
