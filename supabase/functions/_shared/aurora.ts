// Mirrors lib/domain/aurora/aurora_rules.dart and lib/domain/sky/sun.dart so
// the server and the app agree on when an aurora alert is warranted.

const D2R = Math.PI / 180;

const KP_TABLE: [number, number][] = [
  [0, 67],
  [1, 65],
  [2, 63],
  [3, 61],
  [4, 58],
  [5, 55],
  [6, 52],
  [7, 48],
  [8, 45],
  [9, 40],
];

export function geomagneticLatitudeDeg(lat: number, lon: number): number {
  const pLat = 80.9 * D2R, pLon = -72.6 * D2R;
  const s = Math.sin(lat * D2R) * Math.sin(pLat) +
    Math.cos(lat * D2R) * Math.cos(pLat) * Math.cos(lon * D2R - pLon);
  return Math.asin(Math.max(-1, Math.min(1, s))) / D2R;
}

export function kpNeededForGeomagneticLatitude(gm: number): number {
  const lat = Math.abs(gm);
  if (lat >= KP_TABLE[0][1]) return 0;
  for (let i = 1; i < KP_TABLE.length; i++) {
    const [kpHi, latLo] = KP_TABLE[i];
    const [kpLo, latHi] = KP_TABLE[i - 1];
    if (lat >= latLo) return kpLo + ((latHi - lat) / (latHi - latLo)) * (kpHi - kpLo);
  }
  return 9 + (40 - lat) / 5;
}

export const kpNeededAt = (lat: number, lon: number) => kpNeededForGeomagneticLatitude(geomagneticLatitudeDeg(lat, lon));

export function sunAltitudeDeg(utc: Date, lat: number, lon: number): number {
  const norm = (x: number) => ((x % 360) + 360) % 360;
  const jd = utc.getTime() / 86400000 + 2440587.5;
  const n = jd - 2451545.0;
  const l = norm(280.46 + 0.9856474 * n);
  const g = norm(357.528 + 0.9856003 * n) * D2R;
  const lambda = (l + 1.915 * Math.sin(g) + 0.02 * Math.sin(2 * g)) * D2R;
  const eps = (23.439 - 0.0000004 * n) * D2R;
  const ra = Math.atan2(Math.cos(eps) * Math.sin(lambda), Math.cos(lambda));
  const dec = Math.asin(Math.sin(eps) * Math.sin(lambda));
  const gmstH = (((18.697374558 + 24.06570982441908 * n) % 24) + 24) % 24;
  const ha = (norm(gmstH * 15 + lon) - ra / D2R) * D2R;
  const s = Math.sin(lat * D2R) * Math.sin(dec) + Math.cos(lat * D2R) * Math.cos(dec) * Math.cos(ha);
  return Math.asin(Math.max(-1, Math.min(1, s))) / D2R;
}

/** Ovation grid: [lon 0..359, lat -90..90, prob], lon-major. */
export function ovationAt(coords: number[][], lat: number, lon: number): number {
  const lo = ((Math.round(lon) % 360) + 360) % 360;
  const la = Math.max(-90, Math.min(90, Math.round(lat)));
  const idx = lo * 181 + (la + 90);
  const c = coords[idx];
  if (c && c[0] === lo && c[1] === la) return Math.round(c[2]);
  const hit = coords.find((x) => x[0] === lo && x[1] === la);
  return hit ? Math.round(hit[2]) : 0;
}

export type Device = {
  id: string;
  token: string;
  platform: "ios" | "android";
  lat: number;
  lon: number;
  kp_needed: number;
  plus: boolean;
  wake_me: boolean;
  quiet_start: number; // minutes after local midnight
  quiet_end: number;
  utc_offset_min: number;
};

export function inQuietHours(d: Device, now: Date): boolean {
  if (d.quiet_start === d.quiet_end) return false;
  const local = new Date(now.getTime() + d.utc_offset_min * 60000);
  const m = local.getUTCHours() * 60 + local.getUTCMinutes();
  return d.quiet_start < d.quiet_end ? m >= d.quiet_start && m < d.quiet_end : m >= d.quiet_start || m < d.quiet_end;
}

/** 3-hour bucket so each device gets at most one "aurora now" per bucket. */
export function bucket(now: Date): string {
  const b = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), Math.floor(now.getUTCHours() / 3) * 3));
  return b.toISOString();
}

export type Decision = { device: Device; reason: string };

/**
 * Same gate as the app's auroraNow(): dark, Kp within 1 of what's needed,
 * Ovation ≥ 20% at the cell, not cloudy, respecting quiet hours.
 */
export function decide(
  devices: Device[],
  opts: {
    now: Date;
    kpNow: number;
    ovation: (lat: number, lon: number) => number;
    clouds?: (lat: number, lon: number) => number | undefined;
  },
): { send: Decision[]; skip: Decision[] } {
  const send: Decision[] = [], skip: Decision[] = [];
  for (const d of devices) {
    const why = (() => {
      if (!d.plus) return "not plus";
      if (opts.kpNow < d.kp_needed - 1) return `kp ${opts.kpNow} < ${d.kp_needed - 1}`;
      if (sunAltitudeDeg(opts.now, d.lat, d.lon) > -6) return "not dark";
      const p = opts.ovation(d.lat, d.lon);
      if (p < 20) return `ovation ${p}`;
      const c = opts.clouds?.(d.lat, d.lon);
      if (c !== undefined && c > 60) return `cloudy ${c}`;
      if (inQuietHours(d, opts.now) && !d.wake_me) return "quiet hours";
      return null;
    })();
    (why ? skip : send).push({ device: d, reason: why ?? "go" });
  }
  return { send, skip };
}
