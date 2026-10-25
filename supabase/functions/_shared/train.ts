// Port of lib/domain/starlink/train_detector.dart: keep only launch groups
// still flying as a "train" so phones download ~50 KB instead of 4.7 MB.

export type Omm = {
  OBJECT_NAME?: string;
  OBJECT_ID?: string;
  EPOCH?: string;
  MEAN_MOTION: number;
  REV_AT_EPOCH?: number;
  [k: string]: unknown;
};

export const MAX_REV_FOR_TRAIN = 500;
export const MIN_MEAN_MOTION_FOR_TRAIN = 15.6;

export function launchKey(o: Omm): string {
  const id = o.OBJECT_ID ?? "";
  return id.length >= 8 ? id.substring(0, 8) : id;
}

/** Train-phase Starlink groups (≥5 members), newest launch first. */
export function trainGroups(records: Omm[]): Map<string, Omm[]> {
  const byLaunch = new Map<string, Omm[]>();
  for (const r of records) {
    if (!(r.OBJECT_NAME ?? "").toUpperCase().startsWith("STARLINK")) continue;
    const k = launchKey(r);
    if (k.length < 8) continue;
    const list = byLaunch.get(k) ?? [];
    list.push(r);
    byLaunch.set(k, list);
  }
  const groups = [...byLaunch.entries()]
    .filter(([, v]) => v.length >= 5)
    .map(([k, v]) => ({
      k,
      v,
      minRev: Math.min(...v.map((x) => x.REV_AT_EPOCH ?? 0)),
      mm: v.reduce((a, x) => a + x.MEAN_MOTION, 0) / v.length,
    }))
    .filter((g) => g.minRev <= MAX_REV_FOR_TRAIN && g.mm >= MIN_MEAN_MOTION_FOR_TRAIN)
    .sort((a, b) => a.minRev - b.minRev);
  return new Map(groups.map((g) => [g.k, g.v]));
}

/** Dedupe catalog + supplemental by name (freshest epoch wins), keep trains. */
export function trimStarlink(all: Omm[]): Omm[] {
  const byName = new Map<string, Omm>();
  for (const r of all) {
    const name = r.OBJECT_NAME ?? "";
    const prev = byName.get(name);
    if (!prev || (r.EPOCH ?? "") > (prev.EPOCH ?? "")) byName.set(name, r);
  }
  return [...trainGroups([...byName.values()]).values()].flat();
}
