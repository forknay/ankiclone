export const TIME_ZONE = "America/Toronto";
export const PUSH_HOUR = 9;

/**
 * New characters per day, scaled down gradually by the backlog: every card due when the routine runs
 * at 8:15 AM, before the day's reviews. Full amount up to FULL_PACE_BACKLOG, then one fewer for each
 * further BACKLOG_STEP cards, reaching none above 600.
 */
export const NEW_CHARACTERS = 5;
export const FULL_PACE_BACKLOG = 300;
export const BACKLOG_STEP = 75;
/** The weekly reading deck adds 15 cards a day, so it waits while the backlog is above this. */
export const READING_MAX_BACKLOG = 450;

export function newCharactersFor(backlog: number): number {
  const over = Math.max(0, backlog - FULL_PACE_BACKLOG);
  return Math.max(0, NEW_CHARACTERS - Math.ceil(over / BACKLOG_STEP));
}

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
  return {
    characters: newCharactersFor(backlog),
    sentences: due.reading && backlog <= READING_MAX_BACKLOG ? READING_DECK_SIZE : 0,
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
