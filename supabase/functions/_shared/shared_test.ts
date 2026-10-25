import { assert, assertAlmostEquals, assertEquals, assertThrows } from "@std/assert";
import { bucket, decide, Device, inQuietHours, kpNeededForGeomagneticLatitude, ovationAt, sunAltitudeDeg } from "./aurora.ts";
import { buildBundle } from "./bundle.ts";
import { toRow } from "./devices.ts";
import { fcmMessage } from "./fcm.ts";
import { geohash } from "./geohash.ts";
import { b64urlDecode, decodeJwsPayload, signJwt } from "./jwt.ts";
import { appleEntitlement, playProductEntitlement, playSubscriptionEntitlement } from "./receipts.ts";
import { sanitize } from "./track.ts";
import { Omm, trimStarlink } from "./train.ts";

Deno.test("kp table matches the app (lib/domain/aurora/aurora_rules.dart)", () => {
  assertEquals(kpNeededForGeomagneticLatitude(70), 0);
  assertAlmostEquals(kpNeededForGeomagneticLatitude(61), 3, 1e-9);
  assertAlmostEquals(kpNeededForGeomagneticLatitude(56.5), 4.5, 1e-9);
  assertAlmostEquals(kpNeededForGeomagneticLatitude(-55), 5, 1e-9);
  assert(kpNeededForGeomagneticLatitude(30) > 9);
});

Deno.test("sun altitude: Nashville afternoon up, night down", () => {
  assert(sunAltitudeDeg(new Date("2026-10-21T18:00:00Z"), 36.17, -86.78) > 35);
  assert(sunAltitudeDeg(new Date("2026-10-21T06:00:00Z"), 36.17, -86.78) < -40);
});

Deno.test("ovation lookup is lon-major with fallback", () => {
  const grid: number[][] = [];
  for (let lon = 0; lon < 360; lon++) for (let lat = -90; lat <= 90; lat++) grid.push([lon, lat, lon === 273 && lat === 45 ? 37 : 0]);
  assertEquals(ovationAt(grid, 44.98, -86.78), 37);
  assertEquals(ovationAt([...grid].reverse(), 44.98, -86.78), 37);
});

const dev = (o: Partial<Device> = {}): Device => ({
  id: "d1",
  token: "t".repeat(30),
  platform: "ios",
  lat: 44.98,
  lon: -93.27,
  kp_needed: 6.2,
  plus: true,
  wake_me: false,
  quiet_start: 23 * 60,
  quiet_end: 330,
  utc_offset_min: -300,
  ...o,
});

Deno.test("aurora decide: same gate as the app", () => {
  const night = new Date("2026-10-22T03:00:00Z"); // 10pm CDT, dark, not quiet
  const base = { now: night, kpNow: 6, ovation: () => 40 };
  assertEquals(decide([dev()], base).send.length, 1);
  assertEquals(decide([dev({ plus: false })], base).skip[0].reason, "not plus");
  assertEquals(decide([dev()], { ...base, kpNow: 4 }).skip[0].reason.startsWith("kp"), true);
  assertEquals(decide([dev()], { ...base, ovation: () => 5 }).skip[0].reason, "ovation 5");
  assertEquals(decide([dev()], { ...base, clouds: () => 90 }).skip[0].reason, "cloudy 90");
  assertEquals(decide([dev()], { ...base, now: new Date("2026-10-21T18:00:00Z") }).skip[0].reason, "not dark");
  const late = new Date("2026-10-22T08:00:00Z"); // 3am CDT
  assertEquals(decide([dev()], { ...base, now: late }).skip[0].reason, "quiet hours");
  assertEquals(decide([dev({ wake_me: true })], { ...base, now: late }).send.length, 1);
});

Deno.test("quiet hours wrap midnight; bucket is 3-hourly", () => {
  assert(inQuietHours(dev({ utc_offset_min: 0 }), new Date("2026-10-22T23:30:00Z")));
  assert(!inQuietHours(dev({ utc_offset_min: 0 }), new Date("2026-10-22T12:00:00Z")));
  assertEquals(bucket(new Date("2026-10-22T05:59:00Z")), "2026-10-22T03:00:00.000Z");
});

Deno.test("geohash: known values", () => {
  assertEquals(geohash(57.64911, 10.40744, 11), "u4pruydqqvj");
  assertEquals(geohash(36.17, -86.78, 4), "dn6m");
});

Deno.test("register-device row: rounds location, computes kp, validates", () => {
  const r = toRow({ token: "x".repeat(40), platform: "android", lat: 36.1627, lon: -86.7816, plus: true, utcOffsetMin: -300 });
  assertEquals(r.lat, 36.2);
  assertEquals(r.lon, -86.8);
  assertEquals(r.cell, "dn6m");
  assert(r.kp_needed > 7 && r.kp_needed < 9);
  assertEquals(r.quiet_start, 1380);
  assertThrows(() => toRow({ token: "short", platform: "ios", lat: 0, lon: 0 }));
  assertThrows(() => toRow({ token: "x".repeat(40), platform: "web", lat: 0, lon: 0 }));
  assertThrows(() => toRow({ token: "x".repeat(40), platform: "ios", lat: 95, lon: 0 }));
});

Deno.test("track: allow-list, prop types, caps", () => {
  const rows = sanitize({
    installId: "0123456789abcdef0123",
    events: [
      { name: "seen_yes", at: "2026-10-25T01:00:00Z", props: { type: "iss", el: 62, ok: true, nested: { no: 1 } } },
      { name: "drop_tables", props: {} },
    ],
  });
  assertEquals(rows.length, 1);
  assertEquals(rows[0].props, { type: "iss", el: 62, ok: true });
  assertThrows(() => sanitize({ installId: "bad id", events: [] }));
});

Deno.test("starlink trim keeps only train-phase groups, deduped", () => {
  const mk = (id: string, n: number, rev: number, mm: number, epoch = "2026-10-20T00:00:00") =>
    Array.from(
      { length: n },
      (
        _,
        i,
      ) => ({
        OBJECT_NAME: `STARLINK-${id}-${i}`,
        OBJECT_ID: `${id}${String.fromCharCode(65 + i)}`,
        EPOCH: epoch,
        MEAN_MOTION: mm,
        REV_AT_EPOCH: rev,
      } as Omm),
    );
  const fresh = mk("2026-232", 6, 120, 15.8), old = mk("2022-119", 6, 900, 15.1), tiny = mk("2026-240", 3, 10, 15.9);
  const dup = mk("2026-232", 6, 125, 15.8, "2026-10-21T00:00:00");
  const out = trimStarlink([...fresh, ...old, ...tiny, ...dup]);
  assertEquals(out.length, 6);
  assert(out.every((o) => o.EPOCH === "2026-10-21T00:00:00"));
});

Deno.test("orbits bundle with a fake fetch; failures degrade per source", async () => {
  const fake = (url: string) => {
    if (url.includes("CATNR=25544")) return Promise.resolve([{ OBJECT_NAME: "ISS (ZARYA)", MEAN_MOTION: 15.49 }]);
    if (url.includes("CATNR=48274")) return Promise.reject(new Error("down"));
    if (url.includes("GROUP=starlink") || url.includes("sup-gp")) return Promise.resolve([]);
    return Promise.resolve({ results: [{ id: "L1" }] });
  };
  const b = await buildBundle(fake);
  assertEquals(b.iss.length, 1);
  assertEquals(b.tiangong, []);
  assertEquals(b.launches.length, 1);
});

Deno.test("JWT ES256 + RS256 signatures verify with the matching public key", async () => {
  for (const alg of ["ES256", "RS256"] as const) {
    const params = alg === "ES256"
      ? { name: "ECDSA", namedCurve: "P-256" }
      : { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" };
    const kp = await crypto.subtle.generateKey(params, true, ["sign", "verify"]) as CryptoKeyPair;
    const jwt = await signJwt({ alg, typ: "JWT" }, { iss: "x", n: 1 }, kp.privateKey);
    const [h, p, s] = jwt.split(".");
    const verify = alg === "ES256" ? { name: "ECDSA", hash: "SHA-256" } : { name: "RSASSA-PKCS1-v1_5" };
    assert(await crypto.subtle.verify(verify, kp.publicKey, b64urlDecode(s), new TextEncoder().encode(`${h}.${p}`)));
    assertEquals(decodeJwsPayload(jwt), { iss: "x", n: 1 });
  }
});

Deno.test("apple entitlement from signedTransactionInfo", () => {
  const jws = (o: object) => `e30.${btoa(JSON.stringify(o)).replaceAll("=", "")}.sig`;
  const now = new Date("2026-10-25T00:00:00Z");
  const sub = appleEntitlement(
    jws({
      bundleId: "com.brilliantdisruptions.lookup",
      productId: "lookup_plus_yearly",
      expiresDate: Date.parse("2027-10-25T00:00:00Z"),
      originalTransactionId: "1000",
      environment: "Sandbox",
    }),
    "com.brilliantdisruptions.lookup",
    now,
  );
  assertEquals(sub.active, true);
  assertEquals(sub.originalId, "1000");
  const expired = appleEntitlement(
    jws({
      bundleId: "com.brilliantdisruptions.lookup",
      productId: "lookup_plus_monthly",
      expiresDate: Date.parse("2026-09-01T00:00:00Z"),
      transactionId: "9",
    }),
    "com.brilliantdisruptions.lookup",
    now,
  );
  assertEquals(expired.active, false);
  const lifetime = appleEntitlement(
    jws({ bundleId: "com.brilliantdisruptions.lookup", productId: "lookup_plus_lifetime", transactionId: "7" }),
    "com.brilliantdisruptions.lookup",
    now,
  );
  assertEquals(lifetime.active, true);
  const refunded = appleEntitlement(
    jws({ bundleId: "com.brilliantdisruptions.lookup", productId: "lookup_plus_lifetime", transactionId: "8", revocationDate: 1 }),
    "com.brilliantdisruptions.lookup",
    now,
  );
  assertEquals(refunded.active, false);
  assertThrows(() =>
    appleEntitlement(jws({ bundleId: "evil.app", productId: "lookup_plus_yearly" }), "com.brilliantdisruptions.lookup", now)
  );
});

Deno.test("play entitlements", () => {
  const now = new Date("2026-10-25T00:00:00Z");
  assertEquals(
    playSubscriptionEntitlement("lookup_plus_yearly", "tok", {
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      lineItems: [{ productId: "lookup_plus_yearly", expiryTime: "2027-01-01T00:00:00Z" }],
    }, now).active,
    true,
  );
  assertEquals(
    playSubscriptionEntitlement("lookup_plus_yearly", "tok", { subscriptionState: "SUBSCRIPTION_STATE_EXPIRED", lineItems: [] }, now)
      .active,
    false,
  );
  assertEquals(playProductEntitlement("lookup_plus_lifetime", "tok", { purchaseState: 0 }).active, true);
  assertEquals(playProductEntitlement("lookup_plus_lifetime", "tok", { purchaseState: 1 }).active, false);
});

Deno.test("fcm message is time-sensitive on iOS and high priority on Android", () => {
  const m = fcmMessage({ token: "t", title: "Aurora now", body: "b" });
  assertEquals(m.message.apns.payload.aps["interruption-level"], "time-sensitive");
  assertEquals(m.message.android.priority, "HIGH");
});
