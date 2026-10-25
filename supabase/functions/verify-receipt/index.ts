// POST /functions/v1/verify-receipt
// iOS:     { installId, platform: "ios", transactionId }
// Android: { installId, platform: "android", productId, purchaseToken }
import { admin } from "../_shared/db.ts";
import { bad, env, json } from "../_shared/http.ts";
import { verifyApple, verifyPlay } from "../_shared/receipts.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return bad("POST only", 405);
  const b = await req.json().catch(() => ({}));
  if (!/^[a-f0-9-]{16,64}$/i.test(String(b.installId ?? ""))) return bad("installId");
  try {
    let ent;
    if (b.platform === "ios") {
      const k = env("APPLE_IAP_KEY");
      if (!k) return bad("APPLE_IAP_KEY not configured", 501);
      ent = await verifyApple(JSON.parse(k), String(b.transactionId));
    } else if (b.platform === "android") {
      const sa = env("PLAY_SERVICE_ACCOUNT");
      if (!sa) return bad("PLAY_SERVICE_ACCOUNT not configured", 501);
      ent = await verifyPlay(
        JSON.parse(sa),
        env("ANDROID_PACKAGE") ?? "com.brilliantdisruptions.lookup",
        String(b.productId),
        String(b.purchaseToken),
      );
    } else {
      return bad("platform");
    }
    await admin().from("entitlements").upsert({
      install_id: b.installId,
      platform: b.platform,
      product_id: ent.productId,
      original_id: ent.originalId,
      active: ent.active,
      expires_at: ent.expiresAt,
      verified_at: new Date().toISOString(),
    });
    // Keep the device's push eligibility in sync with the entitlement.
    if (typeof b.pushToken === "string") await admin().from("devices").update({ plus: ent.active }).eq("token", b.pushToken);
    return json(ent);
  } catch (e) {
    return bad(String((e as Error).message), 422);
  }
});
