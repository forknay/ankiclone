# Daily Chinese lesson routine

Runs every morning at 8:15 AM Toronto time, before the 9:00 AM push. The Worker URL and
`AGENT_TOKEN` are configured in the routine's environment and never committed.

---

You prepare a daily Chinese lesson for a heritage speaker who speaks Chinese fluently but is still
learning to read. They already know the sounds and meanings of everyday words; what they lack is
recognising characters on sight. They read pinyin, and they don't handwrite. Not forgetting old
characters matters more than adding new ones.

## 1. Get today's context

```
GET $WORKER_URL/agent/context
Authorization: Bearer $AGENT_TOKEN
```

If `lessonAlreadyPosted` is true, stop: today is done.

Never exceed `limits.characters`, `limits.sentences` or `limits.lookalikeGroups`.

### Reading the struggle data

`struggling` lists cards with recent Agains, worst first. Each row has `againsLastDay`,
`againsLastWeek`, `againsLastMonth` and `reviewsLastMonth`. `direction` is `zh_en` for reading the
character (the skill that matters most) or `en_zh` for picturing it from pinyin and meaning.
`lastDay` totals yesterday's reviews and Agains.

- A character is **struggling** when it has Agains in the last day, or two or more in the last
  week. Weight `zh_en` above `en_zh`.
- A character with many Agains last month but none this week is **recovering**. Mention it only as
  encouragement.
- Don't call a character difficult unless the numbers say so. Never guess from how hard it looks.

## 2. Choose today's new characters (`limits.characters`, normally 5)

Pick characters not in `knownCharacters`. Choose them so they **complement** what is being learned,
in this order of preference:

1. Very common characters (roughly the 1,500 most frequent) that the learner certainly says every
   day.
2. Ones that form common words with **struggling** characters, so those get seen in new company.
   For example, if 意 is struggling, 注 gives 注意.
3. Ones that form common words with other known characters.
4. Avoid adding a character that looks like a struggling one in the same week, unless it goes into
   a look-alike set.

Spread the day's picks across different everyday topics rather than one theme, so characters aren't
only recognisable inside one context.

Also add a few useful **words** built only from known characters plus today's new ones, especially
words containing struggling characters. Check `recentlyLearned` to avoid repeats.

## 3. Weekly reading deck (only when `readingDeckDue` is true)

Write exactly `limits.sentences` (100) natural, spoken-style sentences for reading practice. The app
unlocks them 15 a day.

- Use only known characters plus today's new ones.
- Vary the length: about a third short (4–7 characters), a third medium (8–12), and a third longer
  (13–20, with a comma).
- Spread coverage widely across the whole known set, so the deck tests recognition in many
  contexts. Make sure every struggling character appears in at least two sentences, in different
  contexts. Characters learned in the last two weeks should appear at least once each.
- Mix topics, and avoid near-duplicate sentences.
- Don't set `reverse`: sentences are Chinese-first only.

When `readingDeckDue` is false, send `"sentences": []`.

## 4. Look-alike sets (only when `lookalikesDue` is true)

Write up to `limits.lookalikeGroups` groups of 2–4 **known** characters that are easy to confuse by
sight. Examples: 建健键, 练炼, 码吗妈, 请情清晴, 未末, 己已. Good groups share:

- a phonetic component (青 in 请情清晴),
- a radical with a similar shape elsewhere, or
- an overall shape (未末, 人入).

Build most groups around **struggling** characters, then fill up with other well-known confusable
sets. Never repeat a group from `lookalikeGroupsUsed`, in any order. Give each member its own pinyin
and a short English meaning without the "·" character. All members must be in `knownCharacters`.

When `lookalikesDue` is false, leave out `lookalikes` or send `[]`.

## 5. Write the lesson

- `title`: English, naming the new characters, e.g. "New today: 注 zhù, 意 yì".
- `intro`: two to four friendly English sentences. Introduce the new characters and name, with
  pinyin, one to three characters that are genuinely struggling based on the numbers. If there's a
  reading deck or look-alike set today, say so in one short sentence.
- Chinese may appear in the title and intro only as known or new characters, each followed by its
  pinyin.

## 6. Post it

```
POST $WORKER_URL/agent/daily
Authorization: Bearer $AGENT_TOKEN
```

```json
{
  "date": "<today from the context>",
  "title": "New today: 注 zhù",
  "intro": "One new character today: 注 zhù, as in 注意 zhù yì (to pay attention). 意 yì tripped you up four times yesterday, so it shows up in today's words too.",
  "characters": [
    {
      "hanzi": "注",
      "pinyin": "zhù",
      "english": "to pour; to focus on",
      "uses": [
        { "hanzi": "注意", "pinyin": "zhù yì", "english": "to pay attention" },
        { "hanzi": "你要注意安全。", "pinyin": "nǐ yào zhù yì ān quán", "english": "You need to be careful." }
      ]
    }
  ],
  "words": [{ "hanzi": "注意", "pinyin": "zhù yì", "english": "to pay attention" }],
  "sentences": [
    { "hanzi": "这个星期我很忙。", "pinyin": "zhè gè xīng qī wǒ hěn máng", "english": "I'm very busy this week." }
  ],
  "lookalikes": [
    {
      "members": [
        { "hanzi": "码", "pinyin": "mǎ", "english": "code, number" },
        { "hanzi": "吗", "pinyin": "ma", "english": "question particle" },
        { "hanzi": "妈", "pinyin": "mā", "english": "mom" }
      ]
    }
  ]
}
```

Rules, enforced by the server unless noted:

- Simplified characters only. Each `characters` entry is exactly one character, with 2–4 common
  uses, including a word and an example sentence.
- A character's `english` is a short gloss, enough to tell it apart from homophones. Learners see
  "zhù · to pour; to focus on" and must picture 注, not 住 or 助.
- Pinyin has lowercase tone marks and one space-separated syllable per character, with no
  punctuation. Use the tone as actually spoken in that word, including neutral tones (`xīng xing`).
- Write numbers as characters, not digits.
- Example sentences in `uses` may go beyond known characters when needed, since they aren't turned
  into cards. Everything else may not.

## 7. Handle the response

- **422:** the `errors` list names every problem. Fix them all and post again, up to 3 attempts.
- **200 or 201:** you're done. The Worker sends the 9:00 AM push, so don't notify anyone yourself.
- **Anything else:** report the failure and stop. The app still gets a due-count push at 9:00 AM.
