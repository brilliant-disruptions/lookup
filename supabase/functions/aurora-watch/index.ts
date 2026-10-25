// Invoked every 10 minutes by pg_cron (see ../../cron.sql). Reads NOAA SWPC,
// decides per device with the same rules as the app, and pushes "aurora now"
// via FCM at most once per device per 3-hour bucket.
import { admin } from "../_shared/db.ts";
import { bucket, decide, Device, ovationAt } from "../_shared/aurora.ts";
import { sendFcm } from "../_shared/fcm.ts";
import { env, json } from "../_shared/http.ts";
import { ServiceAccount } from "../_shared/jwt.ts";

const SWPC = "https://services.swpc.noaa.gov";

async function cloudsFor(cells: { lat: number; lon: number }[]): Promise<Map<string, number>> {
  // One Open-Meteo call per ~1° cell; bounded so a busy night stays cheap.
  const out = new Map<string, number>();
  for (const c of cells.slice(0, 60)) {
    const key = `${Math.round(c.lat)},${Math.round(c.lon)}`;
    if (out.has(key)) continue;
    try {
      const r = await fetch(
        `https://api.open-meteo.com/v1/forecast?latitude=${Math.round(c.lat)}&longitude=${Math.round(c.lon)}&current=cloud_cover`,
      );
      if (r.ok) out.set(key, (await r.json()).current?.cloud_cover);
    } catch { /* unknown clouds: don't block */ }
  }
  return out;
}

Deno.serve(async () => {
  const now = new Date();
  const [kp1m, ovation] = await Promise.all([
    fetch(`${SWPC}/json/planetary_k_index_1m.json`).then((r) => r.json()),
    fetch(`${SWPC}/json/ovation_aurora_latest.json`).then((r) => r.json()),
  ]);
  const last = kp1m[kp1m.length - 1] ?? {};
  const kpNow = Number(last.estimated_kp ?? last.kp_index ?? 0);
  const db = admin();
  // Only devices that could possibly qualify at this Kp.
  const { data: devices, error } = await db.from("devices").select("*").eq("plus", true).lte("kp_needed", kpNow + 1);
  if (error) return json({ error: error.message }, 500);
  if (!devices?.length) return json({ kpNow, candidates: 0, sent: 0 });

  const clouds = await cloudsFor(devices as Device[]);
  const { send, skip } = decide(devices as Device[], {
    now,
    kpNow,
    ovation: (lat, lon) => ovationAt(ovation.coordinates, lat, lon),
    clouds: (lat, lon) => clouds.get(`${Math.round(lat)},${Math.round(lon)}`),
  });

  const saJson = env("FCM_SERVICE_ACCOUNT");
  if (!saJson) return json({ kpNow, candidates: devices.length, wouldSend: send.length, sent: 0, note: "FCM_SERVICE_ACCOUNT not set" });
  const sa = JSON.parse(saJson) as ServiceAccount;
  const b = bucket(now);
  let sent = 0;
  for (const { device } of send) {
    // Dedupe: insert first; if the row exists, this bucket already alerted.
    const { error: dup } = await db.from("aurora_sent").insert({ device_id: device.id, bucket: b });
    if (dup) continue;
    const r = await sendFcm(sa, {
      token: device.token,
      title: "Aurora now",
      body: "It's happening. Find a dark spot and look north.",
      data: { type: "auroraNow", kp: String(kpNow) },
    });
    if (r.ok) sent++;
    if (r.unregistered) await db.from("devices").delete().eq("id", device.id);
  }
  return json({ kpNow, candidates: devices.length, sent, skipped: skip.length });
});
