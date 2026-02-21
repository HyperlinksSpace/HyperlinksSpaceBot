-- Wallet storage schema (initial)
-- Keep minimal + append-only fields as we evolve.

CREATE TABLE IF NOT EXISTS wallets (
  wallet_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,

  state TEXT NOT NULL,

  address TEXT NULL,
  public_key TEXT NULL,

  allocation_amount TEXT NULL,
  allocation_asset TEXT NULL,
  allocation_tx_ref TEXT NULL,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS wallets_user_id_idx ON wallets(user_id);
