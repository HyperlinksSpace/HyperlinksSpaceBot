async function main() {
  const databaseUrl = (process.env.DATABASE_URL || '').trim();
  if (!databaseUrl) {
    console.log('[db] Skip migrations: DATABASE_URL is not set in build/runtime env.');
    return;
  }

  try {
    const { ensureSchema } = await import('../api/db.js');
    console.log('[db] Running schema migrations against DATABASE_URL...');
    await ensureSchema();
    console.log('[db] Schema is up to date.');
  } catch (err) {
    console.error('[db] Migration failed', err);
    console.error('[db] Non-fatal: continuing without migration step.');
  }
}

// eslint-disable-next-line @typescript-eslint/no-floating-promises
main().catch((err) => {
  console.error('[db] Migration script crashed', err);
  console.error('[db] Non-fatal: continuing without migration step.');
});
