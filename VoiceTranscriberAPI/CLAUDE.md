---
type: config
scope: VoiceTranscriberAPI
purpose: Project-specific rules and build commands for the Verbalize sync API
last_updated: 2026-03-18
---

# CLAUDE.md — VoiceTranscriberAPI

## Stack
- **Runtime**: Cloudflare Workers (V8 isolates, no Node.js APIs)
- **Database**: Cloudflare D1 (SQLite)
- **Framework**: Hono (lightweight, Workers-native)
- **Language**: TypeScript (strict mode)
- **Auth**: Custom JWT (HMAC-SHA256 via Web Crypto API)
- **Password Hashing**: PBKDF2 (100k iterations, via Web Crypto API)

## Build Commands
```bash
npm install          # Install dependencies
npm run dev          # Local dev server (port 8787)
npm run deploy       # Deploy to Cloudflare
npm run db:init:local   # Init local D1 schema
npm run db:init:remote  # Init production D1 schema
```

## Key Constraints
- **No Node.js APIs**: Workers use Web Crypto, Fetch, etc. No `crypto`, `fs`, `path`.
- **No bcrypt/argon2 npm packages**: They use native bindings. Use PBKDF2 via Web Crypto instead.
- **D1 batch limit**: Max 100 statements per `DB.batch()` call.
- **Worker size limit**: 1MB compressed. Keep dependencies minimal.
- **JWT_SECRET**: Stored as a Cloudflare secret, never in code or wrangler.toml.

## Architecture
- `src/index.ts` — Entry point, router, CORS, JWT middleware
- `src/auth.ts` — Register, login, refresh, logout endpoints
- `src/sync.ts` — Settings, dictionary, corrections, transcripts endpoints
- `src/crypto.ts` — Password hashing (PBKDF2) and JWT (HMAC-SHA256)
- `src/types.ts` — Shared TypeScript types
- `schema.sql` — D1 database schema (run once per environment)
