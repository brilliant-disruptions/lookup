// Builds the cached orbits bundle. Pure enough to test with a fake fetch.
import { Omm, trimStarlink } from "./train.ts";

const CELESTRAK = "https://celestrak.org/NORAD/elements";

export async function getJson(url: string): Promise<any> {
  for (let i = 0; i < 3; i++) {
    try {
      const r = await fetch(url, { headers: { "user-agent": "LookUp-relay/1.0" } });
      if (r.ok) return await r.json();
    } catch { /* retry */ }
    await new Promise((res) => setTimeout(res, 1000 * 2 ** i));
  }
  throw new Error(`fetch failed: ${url}`);
}

export async function buildBundle(fetchJson = getJson) {
  const [iss, tiangong, starlink, sup, launches] = await Promise.allSettled([
    fetchJson(`${CELESTRAK}/gp.php?CATNR=25544&FORMAT=json`),
    fetchJson(`${CELESTRAK}/gp.php?CATNR=48274&FORMAT=json`),
    fetchJson(`${CELESTRAK}/gp.php?GROUP=starlink&FORMAT=json`),
    fetchJson(`${CELESTRAK}/supplemental/sup-gp.php?FILE=starlink&FORMAT=json`),
    fetchJson("https://ll.thespacedevs.com/2.3.0/launches/upcoming/?limit=40&mode=normal"),
  ]);
  const val = <T>(r: PromiseSettledResult<T>, d: T) => (r.status === "fulfilled" ? r.value : d);
  return {
    fetchedAt: new Date().toISOString(),
    iss: val(iss, []) as Omm[],
    tiangong: val(tiangong, []) as Omm[],
    starlink: trimStarlink([...(val(starlink, []) as Omm[]), ...(val(sup, []) as Omm[])]),
    launches: (val(launches, { results: [] }) as any).results ?? [],
  };
}
