---
type: readme
scope: VoiceTranscriberAPI
purpose: Setup and deployment guide for the Verbalize sync API
last_updated: 2026-03-18
---

# Verbalize Sync API

Cloudflare Workers + D1 backend for cross-device settings sync, dictionary, corrections, and transcript history.

## Prerequisites

- [Node.js](https://nodejs.org/) 18+
- A free [Cloudflare account](https://dash.cloudflare.com/sign-up)

## Setup (One-Time)

### 1. Install Wrangler CLI and dependencies

```bash
cd VoiceTranscriberAPI
npm install
```

### 2. Authenticate with Cloudflare

```bash
npx wrangler login
```

This opens a browser to authenticate. Follow the prompts.

### 3. Create the D1 Database

```bash
npx wrangler d1 create verbalize-db
```

This outputs something like:

```
✅ Successfully created DB 'verbalize-db' in region WNAM
Created your new D1 database.

[[d1_databases]]
binding = "DB"
database_name = "verbalize-db"
database_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

**Copy the `database_id` value** and paste it into `wrangler.toml`, replacing `REPLACE_WITH_YOUR_DATABASE_ID`.

### 4. Initialize the Database Schema

For local development:
```bash
npm run db:init:local
```

For production (remote D1):
```bash
npm run db:init:remote
```

This runs `schema.sql` which creates all tables and indexes.

### 5. Set the JWT Secret

Generate a random secret:
```bash
openssl rand -base64 32
```

Store it as a Cloudflare secret (never committed to code):
```bash
npx wrangler secret put JWT_SECRET
```

Paste the generated secret when prompted.

## Development

Start a local dev server:
```bash
npm run dev
```

The API runs at `http://localhost:8787`. All D1 data is stored locally in `.wrangler/state/`.

### Test with curl

**Register:**
```bash
curl -X POST http://localhost:8787/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email": "you@example.com", "password": "your-password-here"}'
```

**Login:**
```bash
curl -X POST http://localhost:8787/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "you@example.com", "password": "your-password-here"}'
```

**Use the access_token from login for authenticated requests:**
```bash
curl http://localhost:8787/api/sync/settings \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

**Update settings:**
```bash
curl -X PUT http://localhost:8787/api/sync/settings \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"settings": {"defaultStyleTone": "casual", "smartFormatting": true}}'
```

## Deployment

Deploy to Cloudflare's edge network:
```bash
npm run deploy
```

Your API will be available at `https://verbalize-api.<your-subdomain>.workers.dev`.

## API Endpoints

### Auth (Public)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/auth/register` | Create account (email + password) |
| POST | `/api/auth/login` | Login, get tokens |
| POST | `/api/auth/refresh` | Refresh access token |
| POST | `/api/auth/logout` | Invalidate refresh token |

### Sync (Requires `Authorization: Bearer <token>`)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/sync/settings` | Fetch user settings |
| PUT | `/api/sync/settings` | Update settings (full replace) |
| GET | `/api/sync/dictionary?since=` | Fetch dictionary entries |
| POST | `/api/sync/dictionary` | Batch upsert dictionary entries |
| DELETE | `/api/sync/dictionary/:id` | Soft-delete a dictionary entry |
| GET | `/api/sync/corrections?since=&limit=` | Fetch corrections |
| POST | `/api/sync/corrections` | Batch append corrections |
| GET | `/api/sync/transcripts?since=&limit=&offset=` | Fetch transcripts (paginated) |
| POST | `/api/sync/transcripts` | Batch upload transcripts |

## Cost

- **Free tier**: 100k Worker requests/day, 5GB D1 storage, 5M D1 reads/day
- **Paid ($5/mo)**: 10M requests/mo, unlimited D1 reads, 5GB D1

For a single user syncing across devices, the free tier is more than sufficient.
