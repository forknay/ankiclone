# ankiclone

Anki-style Chinese flashcards for iPhone, with a new lesson from Claude each morning.

- `ios/`: SwiftUI app. Works offline. `Packages/SchedulerCore` holds the scheduling (FSRS-5 with a
  6-month interval cap), study queue and pinyin checking.
- `server/`: Cloudflare Worker and D1 database: sync, Claude's lesson endpoints, and the 9 AM push.
- `agent/daily-routine.md`: prompt for the scheduled Claude routine.

## Tests

```bash
cd ios/Packages/SchedulerCore && swift test
```

```bash
cd server && npm install && npm test && npm run typecheck
```

## Deploy the backend

From `server/`:

```bash
npx wrangler login
```

```bash
npx wrangler d1 create ankiclone
```

Put the returned `database_id` in `wrangler.toml`, then:

```bash
npx wrangler d1 migrations apply ankiclone --remote
```

```bash
npx wrangler d1 execute ankiclone --remote --file seed/master.sql
```

```bash
npx wrangler secret put APP_TOKEN
```

```bash
npx wrangler secret put AGENT_TOKEN
```

```bash
npx wrangler deploy
```

For push, also set `APNS_KEY` (the contents of the `.p8` file), `APNS_KEY_ID`, `APNS_TEAM_ID` and
`APNS_TOPIC` (`com.julienyang.ankiclone`) with `wrangler secret put`.

## Local development

Put test tokens in `server/.dev.vars` (ignored by git), then:

```bash
cd server && npx wrangler d1 migrations apply ankiclone --local && npx wrangler d1 execute ankiclone --local --file seed/master.sql && npx wrangler dev --ip 127.0.0.1
```

Run the app from `ios/Ankiclone.xcodeproj` and set the server to `http://127.0.0.1:8787` in Settings.
