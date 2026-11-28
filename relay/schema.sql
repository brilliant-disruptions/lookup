-- Seen near you relay. Reports and rate limits live an hour; subscriptions
-- 30 days unless the app renews them. No positions, no device ids, no IPs:
-- `reporter` and limit keys are salted hashes that change every day.

CREATE TABLE IF NOT EXISTS reports (
  id INTEGER PRIMARY KEY,
  la REAL NOT NULL,
  lo REAL NOT NULL,
  at INTEGER NOT NULL,          -- ms since epoch, set by the relay
  how TEXT NOT NULL,            -- 'eye' | 'camera'
  reporter TEXT NOT NULL        -- daily salted hash of the install's token
);
CREATE INDEX IF NOT EXISTS reports_cell_at ON reports (la, lo, at);
CREATE INDEX IF NOT EXISTS reports_at ON reports (at);

CREATE TABLE IF NOT EXISTS limits (
  key TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS limits_key_at ON limits (key, at);

CREATE TABLE IF NOT EXISTS subs (
  token TEXT PRIMARY KEY,       -- APNs device token or FCM registration token
  platform TEXT NOT NULL,       -- 'apns' | 'fcm'
  sandbox INTEGER NOT NULL DEFAULT 0,
  updated INTEGER NOT NULL,
  woken INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS sub_cells (
  token TEXT NOT NULL,
  la REAL NOT NULL,
  lo REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS sub_cells_cell ON sub_cells (la, lo);
CREATE INDEX IF NOT EXISTS sub_cells_token ON sub_cells (token);

-- "Look up with me" links (src/invite.ts): what, when, where to look, the
-- town name the sender's app shows, the forecast and the card picture. Kept
-- until two days after the event, then swept.
CREATE TABLE IF NOT EXISTS invites (
  code TEXT PRIMARY KEY,
  data TEXT NOT NULL,           -- JSON: type, title, start, end, look, face, place, clouds, tz
  image BLOB,                   -- the "where to look" PNG, or NULL for the default card
  created INTEGER NOT NULL,
  expires INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS invites_expires ON invites (expires);

-- Invite page views and "Get reminders" taps, counted per UTC day. Nothing
-- about who: just how many, so get/view says whether the page persuades.
CREATE TABLE IF NOT EXISTS invite_tally (
  day TEXT NOT NULL,            -- 2026-11-07
  what TEXT NOT NULL,           -- view | get
  n INTEGER NOT NULL,
  PRIMARY KEY (day, what)
);

-- Clouds from MET Norway (src/met.ts), one row per rough place (two
-- decimals, "36.17,-86.78"): the trimmed forecast and what MET said about
-- when to ask again. Nothing about who asked. Swept two days after the
-- last fetch.
CREATE TABLE IF NOT EXISTS met_cache (
  cell TEXT PRIMARY KEY,
  body TEXT NOT NULL,           -- JSON: {issued, fetched, steps}
  expires INTEGER NOT NULL,     -- ms: don't ask MET again before this
  last_modified TEXT,           -- MET's Last-Modified, sent back as If-Modified-Since
  fetched_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS met_cache_fetched ON met_cache (fetched_at);

-- The proxy's own state: 'pause' (after a 429/403), 's:<second>' (calls to
-- MET this second) and 'lock:<cell>' (one call per place at a time).
CREATE TABLE IF NOT EXISTS met_state (
  key TEXT PRIMARY KEY,
  value INTEGER NOT NULL,
  until INTEGER NOT NULL        -- ms: swept after this
);
