// POST /functions/v1/register-device
// { token, platform, lat, lon, plus, wakeMe, quietStart, quietEnd, utcOffsetMin }
// Stores the push token with a coarse location (rounded to 0.1°, ~10 km) so
// the server can send "aurora now". No account, no name, no exact location.
import { admin } from "../_shared/db.ts";
import { toRow } from "../_shared/devices.ts";
import { bad, json } from "../_shared/http.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return bad("POST only", 405);
  let row;
  try {
    row = toRow(await req.json());
  } catch (e) {
    return bad(`invalid ${String((e as Error).message)}`);
  }
  const { error } = await admin().from("devices").upsert(row, { onConflict: "token" });
  if (error) return bad(error.message, 500);
  return json({ ok: true, cell: row.cell, kpNeeded: row.kp_needed });
});
