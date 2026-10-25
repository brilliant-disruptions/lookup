// Minimal JWT signing with WebCrypto: RS256 for Google service accounts
// (FCM, Play Developer API) and ES256 for the App Store Server API.

const enc = new TextEncoder();

export function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? enc.encode(data) : data;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export function b64urlDecode(s: string): Uint8Array<ArrayBuffer> {
  const pad = s.replaceAll("-", "+").replaceAll("_", "/") + "===".slice((s.length + 3) % 4);
  const bin = atob(pad);
  return new Uint8Array(Array.from(bin, (c) => c.charCodeAt(0)));
}

function pemToDer(pem: string): ArrayBuffer {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0)).buffer;
}

export async function importPkcs8(pem: string, alg: "RS256" | "ES256"): Promise<CryptoKey> {
  const params = alg === "RS256" ? { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" } : { name: "ECDSA", namedCurve: "P-256" };
  return await crypto.subtle.importKey("pkcs8", pemToDer(pem), params, false, ["sign"]);
}

export async function signJwt(
  header: Record<string, unknown>,
  payload: Record<string, unknown>,
  key: CryptoKey,
): Promise<string> {
  const input = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const algo = header.alg === "RS256" ? { name: "RSASSA-PKCS1-v1_5" } : { name: "ECDSA", hash: "SHA-256" };
  // WebCrypto ECDSA returns raw r||s, which is exactly the JWS ES256 format.
  const sig = new Uint8Array(await crypto.subtle.sign(algo, key, enc.encode(input)));
  return `${input}.${b64url(sig)}`;
}

/** Decode a JWS payload without verifying (only for data fetched over TLS
 * straight from Apple/Google, never for client-supplied tokens). */
export function decodeJwsPayload<T = Record<string, unknown>>(jws: string): T {
  const [, payload] = jws.split(".");
  return JSON.parse(new TextDecoder().decode(b64urlDecode(payload))) as T;
}

export type ServiceAccount = { client_email: string; private_key: string; project_id?: string };

/** OAuth access token for a Google service account (cached per scope). */
const tokenCache = new Map<string, { token: string; exp: number }>();
export async function googleAccessToken(sa: ServiceAccount, scope: string, fetchFn = fetch): Promise<string> {
  const cached = tokenCache.get(scope);
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp - 60 > now) return cached.token;
  const key = await importPkcs8(sa.private_key, "RS256");
  const assertion = await signJwt({ alg: "RS256", typ: "JWT" }, {
    iss: sa.client_email,
    scope,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }, key);
  const res = await fetchFn("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new Error(`google token ${res.status}: ${await res.text()}`);
  const j = await res.json();
  tokenCache.set(scope, { token: j.access_token, exp: now + (j.expires_in ?? 3600) });
  return j.access_token;
}
