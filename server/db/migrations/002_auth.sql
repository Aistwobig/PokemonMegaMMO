-- Login sessions. Only a SHA-256 of the token is stored, so a database leak doesn't hand out logins.
CREATE TABLE sessions (
  token_hash BYTEA PRIMARY KEY,
  account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX sessions_account ON sessions (account_id);

-- "Ash" and "ash" are the same username, and the same trainer name.
CREATE UNIQUE INDEX accounts_username_lower ON accounts (lower(username));
CREATE UNIQUE INDEX trainers_name_lower ON trainers (lower(name));
