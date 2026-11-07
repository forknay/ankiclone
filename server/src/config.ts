export const TIME_ZONE = "America/Toronto";
export const PUSH_HOUR = 9;

/** New characters per day, cut back only when reviews are piling up. */
export const NEW_CHARACTERS = 5;
export const NEW_CHARACTERS_UNDER_BACKLOG = 2;
export const BACKLOG_BRAKE = 250;

/** A reading deck of Chinese-first sentences each week, unlocked a few at a time. */
export const READING_DECK_SIZE = 100;
export const READING_EVERY_DAYS = 7;
export const READING_NEW_PER_DAY = 15;

/** Sets of look-alike characters, about twice a week. */
export const LOOKALIKE_GROUPS = 8;
export const LOOKALIKE_EVERY_DAYS = 3;

export interface Limits {
  characters: number;
  /** Reading-deck sentences: either a full week's deck or none. */
  sentences: number;
  lookalikeGroups: number;
}

export function limitsFor(backlog: number, due: { reading: boolean; lookalikes: boolean }): Limits {
  const braking = backlog > BACKLOG_BRAKE;
  return {
    characters: braking ? NEW_CHARACTERS_UNDER_BACKLOG : NEW_CHARACTERS,
    sentences: due.reading && !braking ? READING_DECK_SIZE : 0,
    lookalikeGroups: due.lookalikes ? LOOKALIKE_GROUPS : 0,
  };
}

export function torontoParts(now: Date): { date: string; hour: number } {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hourCycle: "h23",
  }).formatToParts(now);
  const get = (type: string) => parts.find((part) => part.type === type)!.value;
  return { date: `${get("year")}-${get("month")}-${get("day")}`, hour: Number(get("hour")) };
}
