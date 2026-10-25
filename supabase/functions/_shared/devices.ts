import { kpNeededAt } from "./aurora.ts";
import { geohash } from "./geohash.ts";

export function toRow(b: any) {
  if (typeof b?.token !== "string" || b.token.length < 20) throw new Error("token");
  if (b.platform !== "ios" && b.platform !== "android") throw new Error("platform");
  const lat = Number(b.lat), lon = Number(b.lon);
  if (!(Math.abs(lat) <= 90 && Math.abs(lon) <= 180)) throw new Error("location");
  const r1 = (x: number) => Math.round(x * 10) / 10;
  const int = (x: unknown, d: number) => (Number.isFinite(Number(x)) ? Math.trunc(Number(x)) : d);
  return {
    token: b.token,
    platform: b.platform,
    lat: r1(lat),
    lon: r1(lon),
    cell: geohash(lat, lon, 4),
    kp_needed: Math.round(kpNeededAt(lat, lon) * 10) / 10,
    plus: b.plus === true,
    wake_me: b.wakeMe === true,
    quiet_start: int(b.quietStart, 23 * 60),
    quiet_end: int(b.quietEnd, 5 * 60 + 30),
    utc_offset_min: int(b.utcOffsetMin, 0),
    updated_at: new Date().toISOString(),
  };
}
