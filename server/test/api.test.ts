import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import worker, { Env } from "../src/index";
import { limitsFor, torontoParts } from "../src/config";
import { runMorningPush, SendPush } from "../src/push";

const call = (path: string, token: string, body?: unknown) =>
  worker.fetch(
    new Request(`https://test${path}`, {
      method: body === undefined ? "GET" : "POST",
      headers: { authorization: `Bearer ${token}` },
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
    env as unknown as Env,
  );
const agent = (path: string, body?: unknown) => call(path, "agent-test-token", body);
const app = (path: string, body?: unknown) => call(path, "app-test-token", body);
const syncFrom = async (cursor = 0, extra = {}) =>
  (await (await app("/sync", { cursor, reviews: [], deckSettings: [], ...extra })).json()) as any;

async function seedKnown(characters: string, due = Date.now() - 1000) {
  let index = 0;
  for (const hanzi of characters) {
    index++;
    await env.DB.batch([
      env.DB.prepare(
        "INSERT INTO notes (id, deck_id, kind, hanzi, pinyin, english, updated_seq) VALUES (?, 'master', 'character', ?, 'x', 'x', 1)",
      ).bind(`n${index}`, hanzi),
      env.DB.prepare(
        "INSERT INTO cards (id, note_id, deck_id, direction, phase, due, reps, updated_seq) VALUES (?, ?, 'master', 'zh_en', 'review', ?, 1, 1)",
      ).bind(`c${index}`, `n${index}`, due),
      env.DB.prepare(
        "INSERT INTO cards (id, note_id, deck_id, direction, phase, due, held_by, updated_seq) VALUES (?, ?, 'master', 'en_zh', 'new', ?, ?, 1)",
      ).bind(`r${index}`, `n${index}`, due, `c${index}`),
    ]);
  }
}

const today = () => torontoParts(new Date()).date;
const goodDaily = () => ({
  date: today(),
  title: "新字：学",
  intro: "今天学一个字",
  characters: [
    {
      hanzi: "学",
      pinyin: "xué",
      english: "to study",
      uses: [{ hanzi: "学生", pinyin: "xué shēng", english: "student" }],
    },
  ],
  words: [{ hanzi: "你好", pinyin: "nǐ hǎo", english: "hello" }],
  sentences: [
    { hanzi: "我学。", pinyin: "wǒ xué", english: "I study.", reverse: true },
    { hanzi: "你好吗？", pinyin: "nǐ hǎo ma", english: "How are you?" },
  ],
});
const reviewOf = (id: string, cardId: string, reviewedAt: number, due: number) => ({
  id,
  cardId,
  grade: "good",
  reviewedAt,
  state: { phase: "review", due, stability: 3, difficulty: 5, elapsedDays: 1, scheduledDays: 3, reps: 2, lapses: 0, lastReview: reviewedAt },
});
const postDailyErrors = async (body: unknown) => {
  const response = await agent("/agent/daily", body);
  expect(response.status).toBe(422);
  return ((await response.json()) as any).errors.join("\n") as string;
};

describe("auth", () => {
  it("rejects missing or crossed tokens", async () => {
    expect((await call("/agent/context", "nope")).status).toBe(401);
    expect((await app("/agent/context")).status).toBe(401);
    expect((await app("/agent/test-push", {})).status).toBe(401);
    expect((await agent("/sync", { cursor: 0, reviews: [], deckSettings: [] })).status).toBe(401);
  });
});

describe("backlog limits", () => {
  it("keeps five new characters a day unless reviews pile up", () => {
    const due = { reading: true, lookalikes: true };
    expect(limitsFor(250, due)).toEqual({ characters: 5, sentences: 100, lookalikeGroups: 8 });
    expect(limitsFor(251, due)).toEqual({ characters: 2, sentences: 0, lookalikeGroups: 8 });
    expect(limitsFor(0, { reading: false, lookalikes: false })).toEqual({ characters: 5, sentences: 0, lookalikeGroups: 0 });
  });

  it("context hides held cards from the backlog", async () => {
    await seedKnown("我你好吗");
    const context = (await (await agent("/agent/context")).json()) as any;
    expect(context.backlog).toBe(4);
    expect(context.knownCharacters).toBe("我你好吗");
    expect(context.limits.characters).toBe(5);
  });
});

describe("POST /agent/daily", () => {
  it("adds notes, cards, a reading deck and a lesson", async () => {
    await seedKnown("我你好吗");
    const response = await agent("/agent/daily", goodDaily());
    expect(response.status).toBe(201);
    const pulled = await syncFrom();
    expect(pulled.lessons).toHaveLength(1);
    expect(pulled.decks.map((deck: any) => deck.id)).toContain(`reading-${today()}`);
    const study = pulled.notes.find((note: any) => note.hanzi === "学");
    const studyCards = pulled.cards.filter((card: any) => card.noteId === study.id);
    expect(studyCards).toHaveLength(2);
    const dueOf = (direction: string) => studyCards.find((card: any) => card.direction === direction).due;
    expect(dueOf("zh_en")).toBeLessThan(dueOf("en_zh"));
    const sentence = pulled.notes.find((note: any) => note.hanzi === "你好吗？");
    expect(pulled.cards.filter((card: any) => card.noteId === sentence.id)).toHaveLength(1);
    // Sentences are Chinese-first only now, even if asked for reverse.
    const reversed = pulled.notes.find((note: any) => note.hanzi === "我学。");
    expect(pulled.cards.filter((card: any) => card.noteId === reversed.id)).toHaveLength(1);
  });

  it("unlocks the reading deck fifteen sentences a day, once a week", async () => {
    await seedKnown("我你好吗是不");
    const words = "我你好吗是不";
    const sentences = Array.from({ length: 16 }, (_, index) => {
      const pair = [words[index % 6], words[(index + 1 + Math.floor(index / 6)) % 6]];
      return { hanzi: `${pair.join("")}${"。".repeat(1 + Math.floor(index / 6))}${index}`.replace(/\d+$/, ""), pinyin: "x x", english: `s${index}` };
    });
    // Make each sentence distinct with punctuation variety the validator accepts.
    sentences.forEach((sentence, index) => (sentence.hanzi = `${sentence.hanzi.slice(0, 2)}${"！".repeat(index + 1)}`));
    const response = await agent("/agent/daily", { ...goodDaily(), sentences });
    expect(response.status).toBe(201);
    const { results } = await env.DB.prepare(
      "SELECT c.due FROM cards c JOIN notes n ON n.id = c.note_id WHERE n.kind = 'sentence' ORDER BY c.due",
    ).all<{ due: number }>();
    expect(results[15].due - results[0].due).toBe(86_400_000);
    expect(results[14].due).toBe(results[0].due);
    const context = (await (await agent("/agent/context")).json()) as any;
    expect(context.readingDeckDue).toBe(false);
    expect(context.limits.sentences).toBe(0);
  });

  it("adds look-alike groups of known characters, never repeating one", async () => {
    await seedKnown("码吗妈我你好");
    const group = {
      members: [
        { hanzi: "码", pinyin: "mǎ", english: "code" },
        { hanzi: "吗", pinyin: "ma", english: "question particle" },
        { hanzi: "妈", pinyin: "mā", english: "mom" },
      ],
    };
    const response = await agent("/agent/daily", { ...goodDaily(), sentences: [], lookalikes: [group] });
    expect(response.status).toBe(201);
    const note = (await env.DB.prepare("SELECT * FROM notes WHERE kind = 'lookalike'").first()) as any;
    expect(note).toMatchObject({ deck_id: "lookalikes", hanzi: "码吗妈", pinyin: "mǎ ma mā", english: "code · question particle · mom" });
    const context = (await (await agent("/agent/context")).json()) as any;
    expect(context.lookalikeGroupsUsed).toEqual(["码吗妈"]);
    expect(context.lookalikesDue).toBe(false);
  });

  it("rejects look-alike groups with unknown, repeated or too few characters", async () => {
    await seedKnown("码吗妈我你好");
    await env.DB.prepare(
      "INSERT INTO decks (id, name, kind, reverse_mode, created_at, updated_seq) VALUES ('lookalikes', 'Look-alikes', 'lookalikes', 'recall', 1, 1)",
    ).run();
    await env.DB.prepare(
      "INSERT INTO notes (id, deck_id, kind, hanzi, pinyin, english, lesson_date, updated_seq) VALUES ('g', 'lookalikes', 'lookalike', '妈吗', 'mā ma', 'mom · particle', '2020-01-01', 1)",
    ).run();
    const member = (hanzi: string) => ({ hanzi, pinyin: "mā", english: "x" });
    const errors = await postDailyErrors({
      ...goodDaily(),
      lookalikes: [
        { members: [member("码"), member("骂")] },
        { members: [member("吗"), member("妈")] },
        { members: [member("码")] },
      ],
    });
    expect(errors).toContain('"骂" is not a known character');
    expect(errors).toContain("already used as a look-alike group");
    expect(errors).toContain("members must list 2 to 4 characters");
  });

  it("is idempotent per date", async () => {
    await seedKnown("我你好吗");
    await agent("/agent/daily", goodDaily());
    const again = await agent("/agent/daily", goodDaily());
    expect(again.status).toBe(200);
    expect(((await again.json()) as any).alreadyPosted).toBe(true);
    const { count } = (await env.DB.prepare("SELECT COUNT(*) AS count FROM notes WHERE hanzi = '学'").first()) as any;
    expect(count).toBe(1);
  });

  it("rejects a sentence with unknown characters and saves nothing", async () => {
    await seedKnown("我你好吗");
    const body = goodDaily();
    body.sentences.push({ hanzi: "我吃。", pinyin: "wǒ chī", english: "I eat." });
    expect(await postDailyErrors(body)).toContain("unknown characters: 吃");
    expect((await syncFrom()).lessons).toHaveLength(0);
  });

  it("rejects pinyin that doesn't line up with the characters", async () => {
    await seedKnown("我你好吗");
    const body = goodDaily();
    body.sentences[0].pinyin = "wǒxué";
    expect(await postDailyErrors(body)).toContain("2 characters but pinyin has 1");
    body.sentences[0].pinyin = "wǒ xué.";
    expect(await postDailyErrors(body)).toContain("invalid pinyin");
  });

  it("rejects duplicates and multi-character 'characters'", async () => {
    await seedKnown("我你好吗学");
    expect(await postDailyErrors(goodDaily())).toContain("already in the master deck");
    const body = goodDaily();
    body.characters[0].hanzi = "学习";
    body.characters[0].pinyin = "xué xí";
    expect(await postDailyErrors(body)).toContain("must be a single character");
  });

  it("enforces the backlog limit", async () => {
    await seedKnown("我你好吗");
    const many = Array.from({ length: 6 }, (_, index) => ({
      hanzi: "天地人山水火"[index],
      pinyin: "x",
      english: "x",
      uses: [{ hanzi: "天", pinyin: "tiān", english: "sky" }],
    }));
    expect(await postDailyErrors({ ...goodDaily(), characters: many })).toContain("exceeds today's limit of 5");
  });

  it("rejects the wrong date", async () => {
    await seedKnown("我你好吗");
    expect(await postDailyErrors({ ...goodDaily(), date: "2020-01-01" })).toContain("date must be today");
  });
});

describe("POST /sync", () => {
  it("applies a review, unlocks the held card and logs it once", async () => {
    await seedKnown("我");
    const now = Date.now();
    const review = reviewOf("rev-1", "c1", now, now + 86_400_000);
    await syncFrom(0, { reviews: [review] });
    await syncFrom(0, { reviews: [review] });
    const card = (await env.DB.prepare("SELECT * FROM cards WHERE id = 'c1'").first()) as any;
    expect(card.due).toBe(now + 86_400_000);
    expect(card.last_review).toBe(now);
    const held = (await env.DB.prepare("SELECT held_by FROM cards WHERE id = 'r1'").first()) as any;
    expect(held.held_by).toBeNull();
    const { count } = (await env.DB.prepare("SELECT COUNT(*) AS count FROM review_logs").first()) as any;
    expect(count).toBe(1);
  });

  it("counts every Again on a card, once per review", async () => {
    await seedKnown("我");
    const now = Date.now();
    const again = (id: string, at: number) => ({ ...reviewOf(id, "c1", at, at + 60_000), grade: "again" });
    await syncFrom(0, { reviews: [again("a1", now - 2000), again("a2", now - 1000)] });
    await syncFrom(0, { reviews: [again("a2", now - 1000)] });
    const pulled = await syncFrom();
    expect(pulled.cards.find((card: any) => card.id === "c1").agains).toBe(2);

    const context = (await (await agent("/agent/context")).json()) as any;
    expect(context.lastDay).toEqual({ reviews: 2, agains: 2 });
    expect(context.struggling[0]).toMatchObject({ hanzi: "我", direction: "zh_en", againsLastDay: 2, againsLastWeek: 2 });
  });

  it("ignores an older review uploaded after a newer one", async () => {
    await seedKnown("我");
    const now = Date.now();
    await syncFrom(0, { reviews: [reviewOf("new", "c1", now, now + 5000)] });
    await syncFrom(0, { reviews: [reviewOf("old", "c1", now - 1000, now + 1)] });
    const card = (await env.DB.prepare("SELECT due FROM cards WHERE id = 'c1'").first()) as any;
    expect(card.due).toBe(now + 5000);
    const { count } = (await env.DB.prepare("SELECT COUNT(*) AS count FROM review_logs").first()) as any;
    expect(count).toBe(2);
  });

  it("only returns what changed since the cursor", async () => {
    await seedKnown("我你");
    const first = await syncFrom();
    expect(first.cards).toHaveLength(4);
    expect((await syncFrom(first.cursor)).cards).toHaveLength(0);
    const now = Date.now();
    const second = await syncFrom(first.cursor, { reviews: [reviewOf("a", "c1", now, now + 1000)] });
    expect(second.cards.map((card: any) => card.id).sort()).toEqual(["c1", "r1"]);
  });

  it("saves a deck's reverse mode", async () => {
    const pulled = await syncFrom(0, { deckSettings: [{ deckId: "master", reverseMode: "recall" }] });
    expect(pulled.decks.find((deck: any) => deck.id === "master").reverseMode).toBe("recall");
  });

  it("rejects malformed input", async () => {
    expect((await app("/sync", { cursor: -1, reviews: [], deckSettings: [] })).status).toBe(400);
    const now = Date.now();
    const bad = { ...reviewOf("a", "c1", now, now), grade: "great" };
    expect((await app("/sync", { cursor: 0, reviews: [bad], deckSettings: [] })).status).toBe(400);
  });
});

describe("morning push", () => {
  const nineAM = new Date("2026-11-03T14:00:00Z"); // EST
  const sends = () => {
    const sent: any[] = [];
    const send: SendPush = async (device, message) => {
      sent.push({ device, message });
      return "sent";
    };
    return { sent, send };
  };
  const addDevice = () => app("/devices", { token: "abc123", environment: "production" });

  it("fires at 9 local on both sides of the daylight saving change", () => {
    expect(torontoParts(new Date("2026-10-30T13:00:00Z")).hour).toBe(9); // EDT
    expect(torontoParts(new Date("2026-11-03T14:00:00Z")).hour).toBe(9); // EST
    expect(torontoParts(new Date("2026-11-03T13:00:00Z")).hour).toBe(8);
  });

  it("does nothing outside the hour, and sends only once a day", async () => {
    await seedKnown("我", nineAM.getTime() - 1000);
    await addDevice();
    const { sent, send } = sends();
    expect(await runMorningPush(env.DB, new Date("2026-11-03T13:45:00Z"), send)).toBe("not-time");
    expect(await runMorningPush(env.DB, nineAM, send)).toBe("sent");
    expect(await runMorningPush(env.DB, new Date("2026-11-03T14:15:00Z"), send)).toBe("already-sent");
    expect(sent).toHaveLength(1);
  });

  it("falls back to the due count when no lesson was posted", async () => {
    await seedKnown("我你", nineAM.getTime() - 1000);
    await addDevice();
    const { sent, send } = sends();
    await runMorningPush(env.DB, nineAM, send);
    expect(sent[0].message.title).toBe("2 cards due");
    expect(sent[0].message.lessonDate).toBeNull();
  });

  it("uses the lesson title when there is one", async () => {
    await seedKnown("我", nineAM.getTime() - 1000);
    await addDevice();
    await env.DB.prepare("INSERT INTO lessons (date, title, body, created_at, updated_seq) VALUES ('2026-11-03', '新字', '{}', 0, 1)").run();
    const { sent, send } = sends();
    await runMorningPush(env.DB, nineAM, send);
    expect(sent[0].message.title).toBe("新字");
    expect(sent[0].message.lessonDate).toBe("2026-11-03");
  });

  it("puts the intro, new characters and common uses in the notification", async () => {
    await seedKnown("我", nineAM.getTime() - 1000);
    await addDevice();
    const body = JSON.stringify({
      intro: "Today's character is 星 xīng.",
      characters: [
        {
          hanzi: "星",
          pinyin: "xīng",
          english: "star",
          uses: [
            { hanzi: "星期", pinyin: "xīng qī", english: "week" },
            { hanzi: "星星", pinyin: "xīng xing", english: "stars" },
            { hanzi: "明星", pinyin: "míng xīng", english: "celebrity" },
          ],
        },
      ],
    });
    await env.DB.prepare("INSERT INTO lessons (date, title, body, created_at, updated_seq) VALUES ('2026-11-03', 'New: 星', ?, 0, 1)").bind(body).run();
    const { sent, send } = sends();
    await runMorningPush(env.DB, nineAM, send);
    expect(sent[0].message.body).toBe(
      "Today's character is 星 xīng.\n\n星 xīng: star\n星期 xīng qī: week\n星星 xīng xing: stars\n\n1 card due.",
    );
  });

  it("keeps a very long lesson within the push size limit", async () => {
    await seedKnown("我", nineAM.getTime() - 1000);
    await addDevice();
    const body = JSON.stringify({ intro: "星".repeat(2000) });
    await env.DB.prepare("INSERT INTO lessons (date, title, body, created_at, updated_seq) VALUES ('2026-11-03', 'Long', ?, 0, 1)").bind(body).run();
    const { sent, send } = sends();
    await runMorningPush(env.DB, nineAM, send);
    expect(new TextEncoder().encode(sent[0].message.body).length).toBeLessThan(3100);
    expect(sent[0].message.body.endsWith("1 card due.")).toBe(true);
  });

  it("retries after a failure and removes dead tokens", async () => {
    await seedKnown("我", nineAM.getTime() - 1000);
    await addDevice();
    expect(await runMorningPush(env.DB, nineAM, async () => "failed")).toBe("failed");
    const { sent, send } = sends();
    expect(await runMorningPush(env.DB, new Date("2026-11-03T14:15:00Z"), send)).toBe("sent");
    expect(sent).toHaveLength(1);
    await env.DB.prepare("DELETE FROM meta WHERE key = 'last_push_date'").run();
    await runMorningPush(env.DB, nineAM, async () => "gone");
    const { count } = (await env.DB.prepare("SELECT COUNT(*) AS count FROM devices").first()) as any;
    expect(count).toBe(0);
  });
});
