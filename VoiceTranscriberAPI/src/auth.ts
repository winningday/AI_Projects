// Module: Auth endpoints — register, login, refresh, logout

import { Hono } from 'hono';
import type { Env, RegisterRequest, LoginRequest, RefreshRequest } from './types';
import { hashPassword, verifyPassword, signJWT, generateRefreshToken, hashToken } from './crypto';

const auth = new Hono<{ Bindings: Env }>();

const ACCESS_TOKEN_TTL = 60 * 60;          // 1 hour
const REFRESH_TOKEN_TTL = 30 * 24 * 60 * 60; // 30 days
const MAX_REFRESH_TOKENS_PER_USER = 10;      // Max active sessions

// POST /api/auth/register
auth.post('/register', async (c) => {
  const body = await c.req.json<RegisterRequest>();

  if (!body.email || !body.password) {
    return c.json({ error: 'Email and password are required.' }, 400);
  }

  const email = body.email.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return c.json({ error: 'Invalid email format.' }, 400);
  }

  if (body.password.length < 8) {
    return c.json({ error: 'Password must be at least 8 characters.' }, 400);
  }

  // Check if email already exists
  const existing = await c.env.DB.prepare('SELECT id FROM users WHERE email = ?').bind(email).first();
  if (existing) {
    return c.json({ error: 'An account with this email already exists.' }, 409);
  }

  const userId = crypto.randomUUID();
  const passwordHash = await hashPassword(body.password);

  await c.env.DB.prepare(
    'INSERT INTO users (id, email, password_hash) VALUES (?, ?, ?)'
  ).bind(userId, email, passwordHash).run();

  // Create initial empty settings
  await c.env.DB.prepare(
    'INSERT INTO user_settings (user_id, settings_json) VALUES (?, ?)'
  ).bind(userId, '{}').run();

  // Issue tokens
  const tokens = await issueTokens(c.env, userId, email);

  return c.json({
    user: { id: userId, email, tier: 'free' },
    ...tokens,
  }, 201);
});

// POST /api/auth/login
auth.post('/login', async (c) => {
  const body = await c.req.json<LoginRequest>();

  if (!body.email || !body.password) {
    return c.json({ error: 'Email and password are required.' }, 400);
  }

  const email = body.email.trim().toLowerCase();

  const user = await c.env.DB.prepare(
    'SELECT id, email, password_hash, tier FROM users WHERE email = ?'
  ).bind(email).first<{ id: string; email: string; password_hash: string; tier: string }>();

  if (!user) {
    return c.json({ error: 'Invalid email or password.' }, 401);
  }

  const valid = await verifyPassword(body.password, user.password_hash);
  if (!valid) {
    return c.json({ error: 'Invalid email or password.' }, 401);
  }

  const tokens = await issueTokens(c.env, user.id, user.email);

  return c.json({
    user: { id: user.id, email: user.email, tier: user.tier },
    ...tokens,
  });
});

// POST /api/auth/refresh
auth.post('/refresh', async (c) => {
  const body = await c.req.json<RefreshRequest>();

  if (!body.refresh_token) {
    return c.json({ error: 'Refresh token is required.' }, 400);
  }

  const tokenHash = await hashToken(body.refresh_token);

  const stored = await c.env.DB.prepare(
    'SELECT rt.id, rt.user_id, rt.expires_at, u.email, u.tier FROM refresh_tokens rt JOIN users u ON u.id = rt.user_id WHERE rt.token_hash = ?'
  ).bind(tokenHash).first<{ id: string; user_id: string; expires_at: string; email: string; tier: string }>();

  if (!stored) {
    return c.json({ error: 'Invalid refresh token.' }, 401);
  }

  if (new Date(stored.expires_at) < new Date()) {
    await c.env.DB.prepare('DELETE FROM refresh_tokens WHERE id = ?').bind(stored.id).run();
    return c.json({ error: 'Refresh token expired.' }, 401);
  }

  // Rotate: delete old, issue new
  await c.env.DB.prepare('DELETE FROM refresh_tokens WHERE id = ?').bind(stored.id).run();

  const tokens = await issueTokens(c.env, stored.user_id, stored.email);

  return c.json({
    user: { id: stored.user_id, email: stored.email, tier: stored.tier },
    ...tokens,
  });
});

// POST /api/auth/logout
auth.post('/logout', async (c) => {
  const body = await c.req.json<RefreshRequest>();

  if (body.refresh_token) {
    const tokenHash = await hashToken(body.refresh_token);
    await c.env.DB.prepare('DELETE FROM refresh_tokens WHERE token_hash = ?').bind(tokenHash).run();
  }

  return c.json({ ok: true });
});

// --- Helpers ---

async function issueTokens(env: Env, userId: string, email: string) {
  const now = Math.floor(Date.now() / 1000);

  // Access token (JWT)
  const accessToken = await signJWT(
    { sub: userId, email, iat: now, exp: now + ACCESS_TOKEN_TTL },
    env.JWT_SECRET
  );

  // Refresh token (opaque, stored hashed)
  const refreshToken = generateRefreshToken();
  const refreshHash = await hashToken(refreshToken);
  const refreshId = crypto.randomUUID();
  const expiresAt = new Date((now + REFRESH_TOKEN_TTL) * 1000).toISOString();

  await env.DB.prepare(
    'INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)'
  ).bind(refreshId, userId, refreshHash, expiresAt).run();

  // Prune old refresh tokens (keep only most recent N per user)
  await env.DB.prepare(
    `DELETE FROM refresh_tokens WHERE user_id = ? AND id NOT IN (
      SELECT id FROM refresh_tokens WHERE user_id = ? ORDER BY created_at DESC LIMIT ?
    )`
  ).bind(userId, userId, MAX_REFRESH_TOKENS_PER_USER).run();

  return {
    access_token: accessToken,
    refresh_token: refreshToken,
    expires_in: ACCESS_TOKEN_TTL,
  };
}

export default auth;
