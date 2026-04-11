import { ensureSchema } from '../database/start.js';

async function main() {
  if (process.env.SKIP_DB_MIGRATE === '1') {
    console.log(
      '[db] SKIP_DB_MIGRATE=1 — skipping migrations (e.g. local vercel dev without DB).',
    );
    return;
  }
  try {
    console.log('[db] Running schema migrations against DATABASE_URL...');
    await ensureSchema();
    console.log('[db] Schema is up to date.');
  } catch (err) {
    console.error('[db] Migration failed', err);
    process.exitCode = 1;
  }
}

void main().catch((err) => {
  console.error('[db] Fatal', err);
  process.exit(1);
});

