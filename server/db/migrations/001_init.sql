-- Accounts and characters
CREATE TABLE accounts (
  id            BIGSERIAL PRIMARY KEY,
  username      TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One trainer per account for now
CREATE TABLE trainers (
  id          BIGSERIAL PRIMARY KEY,
  account_id  BIGINT NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  trainer_id  INTEGER NOT NULL,          -- the 5-digit ID shown on the trainer card
  money       INTEGER NOT NULL DEFAULT 0 CHECK (money >= 0),
  map_id      TEXT NOT NULL DEFAULT 'vaniville',
  x           INTEGER NOT NULL,
  y           INTEGER NOT NULL,
  facing      TEXT NOT NULL DEFAULT 'down',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Every Pokémon a trainer owns, in the party or the PC
CREATE TABLE pokemon (
  id               BIGSERIAL PRIMARY KEY,
  owner_id         BIGINT NOT NULL REFERENCES trainers(id),
  original_owner_id BIGINT NOT NULL REFERENCES trainers(id),
  species          TEXT NOT NULL,          -- Showdown species id, e.g. 'froakie'
  nickname         TEXT,
  level            SMALLINT NOT NULL CHECK (level BETWEEN 1 AND 100),
  exp              INTEGER NOT NULL DEFAULT 0,
  nature           TEXT NOT NULL,
  ability          TEXT NOT NULL,
  gender           CHAR(1) CHECK (gender IN ('M', 'F', 'N')),
  shiny            BOOLEAN NOT NULL DEFAULT false,
  held_item        TEXT,
  ivs              SMALLINT[6] NOT NULL,   -- hp, atk, def, spa, spd, spe
  evs              SMALLINT[6] NOT NULL DEFAULT '{0,0,0,0,0,0}',
  moves            TEXT[] NOT NULL,        -- up to 4 move ids
  current_hp       INTEGER,                -- NULL = full HP
  status           TEXT,                   -- 'brn', 'par', ... or NULL
  location         TEXT NOT NULL CHECK (location IN ('party', 'box')),
  box              SMALLINT,               -- NULL when in party
  slot             SMALLINT NOT NULL,
  caught_ball      TEXT NOT NULL DEFAULT 'pokeball',
  caught_map_id    TEXT,
  caught_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((location = 'party' AND box IS NULL AND slot BETWEEN 0 AND 5)
      OR (location = 'box' AND box IS NOT NULL AND slot BETWEEN 0 AND 29))
);
-- No two Pokémon in the same spot. NULLS NOT DISTINCT so party slots (box IS NULL) are unique too.
CREATE UNIQUE INDEX pokemon_position ON pokemon (owner_id, location, box, slot) NULLS NOT DISTINCT;

CREATE TABLE inventory (
  trainer_id BIGINT NOT NULL REFERENCES trainers(id) ON DELETE CASCADE,
  item       TEXT NOT NULL,                -- Showdown item id, e.g. 'pokeball'
  quantity   INTEGER NOT NULL CHECK (quantity > 0),
  PRIMARY KEY (trainer_id, item)
);

CREATE TABLE badges (
  trainer_id BIGINT NOT NULL REFERENCES trainers(id) ON DELETE CASCADE,
  badge      TEXT NOT NULL,
  earned_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (trainer_id, badge)
);

-- Story progress: "got_starter", "met_shauna", ...
CREATE TABLE story_flags (
  trainer_id BIGINT NOT NULL REFERENCES trainers(id) ON DELETE CASCADE,
  flag       TEXT NOT NULL,
  set_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (trainer_id, flag)
);
