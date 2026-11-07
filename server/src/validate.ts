import type { Limits } from "./config";

export interface Entry {
  hanzi: string;
  pinyin: string;
  english: string;
}

export interface Character extends Entry {
  uses: Entry[];
}

export interface Sentence extends Entry {
  /** Ignored: sentences are Chinese-first only. Still accepted so older payloads don't fail. */
  reverse?: boolean;
}

/** Characters that are easy to confuse, studied side by side without any context. */
export interface LookalikeGroup {
  members: Entry[];
}

export interface DailyInput {
  date: string;
  title: string;
  intro: string;
  characters: Character[];
  words: Entry[];
  sentences: Sentence[];
  lookalikes?: LookalikeGroup[];
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
  limits: Limits;
  /** Existing look-alike groups, as their characters sorted, so a repeat is caught in any order. */
  lookalikeKeys: Set<string>;
}

export const lookalikeKey = (hanzi: string) => [...hanzi].sort().join("");

/** How a group is stored as one note. Members' English is joined with this. */
export const LOOKALIKE_SEPARATOR = " · ";

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
  if (input.lookalikes !== undefined && !Array.isArray(input.lookalikes)) errors.push("lookalikes must be an array");
  const lookalikes = Array.isArray(input.lookalikes) ? input.lookalikes : [];
  if (lookalikes.length > rules.limits.lookalikeGroups) {
    errors.push(`${lookalikes.length} look-alike groups exceeds today's limit of ${rules.limits.lookalikeGroups}`);
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

  const groups = new Set(rules.lookalikeKeys);
  lookalikes.forEach((group, index) => {
    const label = `lookalikes[${index}]`;
    if (!Array.isArray(group?.members) || group.members.length < 2 || group.members.length > 4) {
      errors.push(`${label}: members must list 2 to 4 characters`);
      return;
    }
    const characters: string[] = [];
    group.members.forEach((member, memberIndex) => {
      const memberLabel = `${label}.members[${memberIndex}]`;
      if (!checkEntry(member, memberLabel, errors)) return;
      if (hanOf(member.hanzi).length !== 1 || member.hanzi.length !== 1) {
        errors.push(`${memberLabel}: "${member.hanzi}" must be a single character`);
      } else if (!allowed.has(member.hanzi)) {
        errors.push(`${memberLabel}: "${member.hanzi}" is not a known character`);
      }
      if (member.english.includes(LOOKALIKE_SEPARATOR.trim())) errors.push(`${memberLabel}: english must not contain "·"`);
      characters.push(member.hanzi);
    });
    if (new Set(characters).size !== characters.length) errors.push(`${label}: a character appears twice`);
    const key = lookalikeKey(characters.join(""));
    if (groups.has(key)) errors.push(`${label}: "${characters.join("")}" was already used as a look-alike group`);
    groups.add(key);
  });

  return errors;
}
