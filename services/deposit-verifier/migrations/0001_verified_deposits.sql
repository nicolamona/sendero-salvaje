-- Audit/index only. Never use this table as an independent spendable balance ledger.
CREATE TABLE IF NOT EXISTS verified_deposits (
  chain_id INTEGER NOT NULL CHECK (chain_id = 8453),
  tx_hash TEXT NOT NULL CHECK (length(tx_hash) = 66),
  log_index INTEGER NOT NULL CHECK (log_index >= 0),
  block_number TEXT NOT NULL,
  block_hash TEXT NOT NULL CHECK (length(block_hash) = 66),
  player TEXT NOT NULL CHECK (length(player) = 42),
  amount_wei TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('finalized', 'orphaned')),
  confirmations INTEGER NOT NULL CHECK (confirmations >= 1),
  first_seen_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (chain_id, tx_hash, log_index)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_verified_deposits_player
  ON verified_deposits(player, status);
