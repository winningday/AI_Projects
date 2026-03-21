// Module: Sync endpoints — settings, dictionary, corrections, transcripts

import { Hono } from 'hono';
import type { Env, DictionaryEntryPayload, CorrectionPayload, TranscriptPayload, SettingsPayload } from './types';

// This router expects userId to be set by the JWT middleware (via c.get('userId'))
const sync = new Hono<{ Bindings: Env; Variables: { userId: string } }>();

// ─── Settings (full replace) ───

// GET /api/sync/settings
sync.get('/settings', async (c) => {
  const userId = c.get('userId');

  const row = await c.env.DB.prepare(
    'SELECT settings_json, updated_at FROM user_settings WHERE user_id = ?'
  ).bind(userId).first<{ settings_json: string; updated_at: string }>();

  if (!row) {
    return c.json({ settings: {}, updated_at: null });
  }

  return c.json({
    settings: JSON.parse(row.settings_json) as SettingsPayload,
    updated_at: row.updated_at,
  });
});

// PUT /api/sync/settings
sync.put('/settings', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json<{ settings: SettingsPayload }>();

  if (!body.settings) {
    return c.json({ error: 'Settings object is required.' }, 400);
  }

  const json = JSON.stringify(body.settings);
  const now = new Date().toISOString();

  await c.env.DB.prepare(
    `INSERT INTO user_settings (user_id, settings_json, updated_at) VALUES (?, ?, ?)
     ON CONFLICT(user_id) DO UPDATE SET settings_json = excluded.settings_json, updated_at = excluded.updated_at`
  ).bind(userId, json, now).run();

  return c.json({ ok: true, updated_at: now });
});

// ─── Dictionary (merge by ID) ───

// GET /api/sync/dictionary?since=ISO_TIMESTAMP
sync.get('/dictionary', async (c) => {
  const userId = c.get('userId');
  const since = c.req.query('since');

  let query: string;
  let params: unknown[];

  if (since) {
    query = 'SELECT id, word, auto_added, date_added, deleted FROM dictionary_entries WHERE user_id = ? AND date_added > ? ORDER BY date_added ASC';
    params = [userId, since];
  } else {
    query = 'SELECT id, word, auto_added, date_added, deleted FROM dictionary_entries WHERE user_id = ? ORDER BY date_added ASC';
    params = [userId];
  }

  const { results } = await c.env.DB.prepare(query).bind(...params).all();

  return c.json({ entries: results ?? [] });
});

// POST /api/sync/dictionary (batch upsert)
sync.post('/dictionary', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json<{ entries: DictionaryEntryPayload[] }>();

  if (!body.entries || !Array.isArray(body.entries)) {
    return c.json({ error: 'Entries array is required.' }, 400);
  }

  const stmts = body.entries.map((entry) =>
    c.env.DB.prepare(
      `INSERT INTO dictionary_entries (id, user_id, word, auto_added, date_added) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET word = excluded.word, auto_added = excluded.auto_added`
    ).bind(entry.id, userId, entry.word, entry.auto_added ? 1 : 0, entry.date_added)
  );

  if (stmts.length > 0) {
    await c.env.DB.batch(stmts);
  }

  return c.json({ ok: true, count: stmts.length });
});

// DELETE /api/sync/dictionary/:id (soft delete for sync)
sync.delete('/dictionary/:id', async (c) => {
  const userId = c.get('userId');
  const id = c.req.param('id');

  await c.env.DB.prepare(
    'UPDATE dictionary_entries SET deleted = 1 WHERE id = ? AND user_id = ?'
  ).bind(id, userId).run();

  return c.json({ ok: true });
});

// ─── Corrections (append-only, deduplicate) ───

// GET /api/sync/corrections?since=ISO_TIMESTAMP&limit=200
sync.get('/corrections', async (c) => {
  const userId = c.get('userId');
  const since = c.req.query('since');
  const limit = Math.min(parseInt(c.req.query('limit') ?? '200', 10), 500);

  let query: string;
  let params: unknown[];

  if (since) {
    query = 'SELECT id, original, corrected, date FROM corrections WHERE user_id = ? AND date > ? ORDER BY date ASC LIMIT ?';
    params = [userId, since, limit];
  } else {
    query = 'SELECT id, original, corrected, date FROM corrections WHERE user_id = ? ORDER BY date ASC LIMIT ?';
    params = [userId, limit];
  }

  const { results } = await c.env.DB.prepare(query).bind(...params).all();

  return c.json({ corrections: results ?? [] });
});

// POST /api/sync/corrections (batch append)
sync.post('/corrections', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json<{ corrections: CorrectionPayload[] }>();

  if (!body.corrections || !Array.isArray(body.corrections)) {
    return c.json({ error: 'Corrections array is required.' }, 400);
  }

  // Use INSERT OR IGNORE to skip duplicates (unique on user_id + original + corrected)
  const stmts = body.corrections.map((corr) =>
    c.env.DB.prepare(
      'INSERT OR IGNORE INTO corrections (id, user_id, original, corrected, date) VALUES (?, ?, ?, ?, ?)'
    ).bind(corr.id, userId, corr.original, corr.corrected, corr.date)
  );

  if (stmts.length > 0) {
    await c.env.DB.batch(stmts);
  }

  return c.json({ ok: true, count: stmts.length });
});

// ─── Transcripts (append-only, paginated) ───

// GET /api/sync/transcripts?since=ISO_TIMESTAMP&limit=50&offset=0
sync.get('/transcripts', async (c) => {
  const userId = c.get('userId');
  const since = c.req.query('since');
  const limit = Math.min(parseInt(c.req.query('limit') ?? '50', 10), 200);
  const offset = parseInt(c.req.query('offset') ?? '0', 10);

  let query: string;
  let params: unknown[];

  if (since) {
    query = 'SELECT id, original_text, cleaned_text, corrected_text, duration_seconds, device_source, timestamp FROM transcripts WHERE user_id = ? AND timestamp > ? ORDER BY timestamp ASC LIMIT ? OFFSET ?';
    params = [userId, since, limit, offset];
  } else {
    query = 'SELECT id, original_text, cleaned_text, corrected_text, duration_seconds, device_source, timestamp FROM transcripts WHERE user_id = ? ORDER BY timestamp ASC LIMIT ? OFFSET ?';
    params = [userId, limit, offset];
  }

  const { results } = await c.env.DB.prepare(query).bind(...params).all();

  // Get total count for pagination
  const countQuery = since
    ? 'SELECT COUNT(*) as total FROM transcripts WHERE user_id = ? AND timestamp > ?'
    : 'SELECT COUNT(*) as total FROM transcripts WHERE user_id = ?';
  const countParams = since ? [userId, since] : [userId];
  const countRow = await c.env.DB.prepare(countQuery).bind(...countParams).first<{ total: number }>();

  return c.json({
    transcripts: results ?? [],
    total: countRow?.total ?? 0,
    limit,
    offset,
  });
});

// POST /api/sync/transcripts (batch upload)
sync.post('/transcripts', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json<{ transcripts: TranscriptPayload[] }>();

  if (!body.transcripts || !Array.isArray(body.transcripts)) {
    return c.json({ error: 'Transcripts array is required.' }, 400);
  }

  // INSERT OR IGNORE — if transcript ID already exists, skip
  const stmts = body.transcripts.map((t) =>
    c.env.DB.prepare(
      `INSERT OR IGNORE INTO transcripts (id, user_id, original_text, cleaned_text, corrected_text, duration_seconds, device_source, timestamp)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(t.id, userId, t.original_text, t.cleaned_text, t.corrected_text, t.duration_seconds, t.device_source, t.timestamp)
  );

  if (stmts.length > 0) {
    await c.env.DB.batch(stmts);
  }

  return c.json({ ok: true, count: stmts.length });
});

export default sync;
