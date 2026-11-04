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
