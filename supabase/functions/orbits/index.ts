// GET /functions/v1/orbits
// One small, cached bundle for every phone: ISS, Tiangong, train-phase
// Starlinks, upcoming launches. Spares Celestrak (and phones on cellular) the
// 4.7 MB daily Starlink download, and keeps us inside Celestrak's etiquette
// with one fetch per hour for everyone.
import { admin } from "../_shared/db.ts";
import { buildBundle } from "../_shared/bundle.ts";
import { json } from "../_shared/http.ts";

// Celestrak asks clients not to re-download the same data more often than every 2 hours.
const MAX_AGE_MS = 2 * 60 * 60 * 1000;

Deno.serve(async () => {
  const db = admin();
  const { data } = await db.from("orbit_cache").select("body, fetched_at").eq("key", "bundle").maybeSingle();
  if (data && Date.now() - new Date(data.fetched_at).getTime() < MAX_AGE_MS) {
    return json(data.body, 200, { "cache-control": "public, max-age=600" });
  }
  try {
    const body = await buildBundle();
    if (body.iss.length > 0) {
      await db.from("orbit_cache").upsert({ key: "bundle", body, fetched_at: body.fetchedAt });
    }
    return json(body, 200, { "cache-control": "public, max-age=600" });
  } catch (e) {
    // Serve stale rather than nothing.
    if (data) return json(data.body, 200, { "x-stale": "1" });
    return json({ error: String(e) }, 502);
  }
});
