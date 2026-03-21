// Module: Worker entry point — routes, CORS, JWT middleware, rate limiting

import { Hono } from 'hono';
import { cors } from 'hono/cors';
import type { Env } from './types';
import { verifyJWT } from './crypto';
import auth from './auth';
import sync from './sync';

const app = new Hono<{ Bindings: Env }>();

// ─── CORS ───

app.use('*', cors({
  origin: '*', // Lock this down in production if serving a web client
  allowHeaders: ['Content-Type', 'Authorization'],
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  maxAge: 86400,
}));

// ─── Health Check ───

app.get('/', (c) => c.json({ status: 'ok', service: 'verbalize-api' }));
app.get('/api/health', (c) => c.json({ status: 'ok' }));

// ─── Auth Routes (public) ───

app.route('/api/auth', auth);

// ─── JWT Middleware (protects all /api/sync/* routes) ───

app.use('/api/sync/*', async (c, next) => {
  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return c.json({ error: 'Missing or invalid Authorization header.' }, 401);
  }

  const token = authHeader.slice(7);
  const payload = await verifyJWT(token, c.env.JWT_SECRET);

  if (!payload) {
    return c.json({ error: 'Invalid or expired access token.' }, 401);
  }

  c.set('userId', payload.sub);
  c.set('userEmail', payload.email);

  await next();
});

// ─── Sync Routes (authenticated) ───

app.route('/api/sync', sync);

// ─── 404 Fallback ───

app.notFound((c) => c.json({ error: 'Not found.' }, 404));

// ─── Error Handler ───

app.onError((err, c) => {
  console.error('Unhandled error:', err);
  return c.json({ error: 'Internal server error.' }, 500);
});

export default app;
