// Server-side purchase verification. Both paths ask the store directly over
// TLS, so the client can't forge a result.
import { decodeJwsPayload, googleAccessToken, importPkcs8, ServiceAccount, signJwt } from "./jwt.ts";

export const PRODUCTS = new Set(["lookup_plus_monthly", "lookup_plus_yearly", "lookup_plus_lifetime"]);

export type Entitlement = { active: boolean; productId: string; expiresAt: string | null; originalId: string; environment?: string };

// ---- Apple: App Store Server API -----------------------------------------
export type AppleKey = { issuerId: string; keyId: string; privateKey: string; bundleId: string };

export async function appleToken(k: AppleKey, nowSec = Math.floor(Date.now() / 1000)): Promise<string> {
  const key = await importPkcs8(k.privateKey, "ES256");
  return await signJwt(
    { alg: "ES256", kid: k.keyId, typ: "JWT" },
    { iss: k.issuerId, iat: nowSec, exp: nowSec + 20 * 60, aud: "appstoreconnect-v1", bid: k.bundleId },
    key,
  );
}

export function appleEntitlement(signedTransactionInfo: string, bundleId: string, now = new Date()): Entitlement {
  const t = decodeJwsPayload<any>(signedTransactionInfo);
  if (t.bundleId !== bundleId) throw new Error("bundle mismatch");
  if (!PRODUCTS.has(t.productId)) throw new Error("unknown product");
  const expires = t.expiresDate ? new Date(Number(t.expiresDate)) : null;
  const revoked = t.revocationDate != null;
  return {
    active: !revoked && (expires === null || expires > now),
    productId: t.productId,
    expiresAt: expires?.toISOString() ?? null,
    originalId: String(t.originalTransactionId ?? t.transactionId),
    environment: t.environment,
  };
}

export async function verifyApple(k: AppleKey, transactionId: string, fetchFn = fetch): Promise<Entitlement> {
  const token = await appleToken(k);
  for (const host of ["api.storekit.itunes.apple.com", "api.storekit-sandbox.itunes.apple.com"]) {
    const r = await fetchFn(`https://${host}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`, {
      headers: { authorization: `Bearer ${token}` },
    });
    if (r.status === 404) continue; // try sandbox (TestFlight)
    if (!r.ok) throw new Error(`apple ${r.status}`);
    return appleEntitlement((await r.json()).signedTransactionInfo, k.bundleId);
  }
  throw new Error("transaction not found");
}

// ---- Google: Play Developer API ------------------------------------------
export function playSubscriptionEntitlement(productId: string, purchaseToken: string, body: any, now = new Date()): Entitlement {
  const line = (body.lineItems ?? []).find((l: any) => l.productId === productId) ?? body.lineItems?.[0];
  const expires = line?.expiryTime ? new Date(line.expiryTime) : null;
  const state = body.subscriptionState as string | undefined;
  const okState = state === "SUBSCRIPTION_STATE_ACTIVE" || state === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD";
  return {
    active: okState && (!expires || expires > now),
    productId,
    expiresAt: expires?.toISOString() ?? null,
    originalId: purchaseToken,
  };
}

export function playProductEntitlement(productId: string, purchaseToken: string, body: any): Entitlement {
  // purchaseState 0 = purchased.
  return { active: body.purchaseState === 0, productId, expiresAt: null, originalId: purchaseToken };
}

export async function verifyPlay(
  sa: ServiceAccount,
  packageName: string,
  productId: string,
  purchaseToken: string,
  fetchFn = fetch,
): Promise<Entitlement> {
  if (!PRODUCTS.has(productId)) throw new Error("unknown product");
  const token = await googleAccessToken(sa, "https://www.googleapis.com/auth/androidpublisher", fetchFn);
  const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}/purchases`;
  const lifetime = productId === "lookup_plus_lifetime";
  const url = lifetime
    ? `${base}/products/${productId}/tokens/${encodeURIComponent(purchaseToken)}`
    : `${base}/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
  const r = await fetchFn(url, { headers: { authorization: `Bearer ${token}` } });
  if (!r.ok) throw new Error(`play ${r.status}`);
  const body = await r.json();
  return lifetime ? playProductEntitlement(productId, purchaseToken, body) : playSubscriptionEntitlement(productId, purchaseToken, body);
}
