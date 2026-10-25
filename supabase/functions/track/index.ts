// POST /functions/v1/track  { installId, events: [{ name, at, props }] }
// First-party, anonymous product metrics for the spec's success metrics
// (alert precision, opt-in, trial conversion). No PII; allow-listed names.
import { admin } from "../_shared/db.ts";
import { bad, json } from "../_shared/http.ts";
import { sanitize } from "../_shared/track.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return bad("POST only", 405);
  let rows;
  try {
    rows = sanitize(await req.json());
  } catch (e) {
    return bad(`invalid ${(e as Error).message}`);
  }
  if (rows.length) {
    const { error } = await admin().from("analytics_events").insert(rows);
    if (error) return bad(error.message, 500);
  }
  return json({ ok: true, stored: rows.length });
});
