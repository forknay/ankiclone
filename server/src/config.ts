export const TIME_ZONE = "America/Toronto";
export const PUSH_HOUR = 9;

/** How much new material is allowed per day, given how many cards are waiting. */
const BACKLOG_TIERS = [
  { upTo: 50, characters: 5, sentences: 15 },
  { upTo: 150, characters: 3, sentences: 10 },
  { upTo: 300, characters: 1, sentences: 5 },
  { upTo: Infinity, characters: 0, sentences: 0 },
];

export function limitsFor(backlog: number): { characters: number; sentences: number } {
  const { characters, sentences } = BACKLOG_TIERS.find((tier) => backlog <= tier.upTo)!;
  return { characters, sentences };
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
