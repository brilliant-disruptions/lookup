import { googleAccessToken, ServiceAccount } from "./jwt.ts";

export type Push = { token: string; title: string; body: string; data?: Record<string, string> };

/** Firebase Cloud Messaging HTTP v1 message; works for Android and iOS (APNs
 * via Firebase). Time-sensitive on iOS so Focus modes let it through. */
export function fcmMessage(p: Push) {
  return {
    message: {
      token: p.token,
      notification: { title: p.title, body: p.body },
      data: p.data ?? {},
      android: { priority: "HIGH", notification: { channel_id: "lookup_alerts" } },
      apns: {
        headers: { "apns-priority": "10", "apns-push-type": "alert" },
        payload: { aps: { sound: "default", "interruption-level": "time-sensitive" } },
      },
    },
  };
}

export async function sendFcm(
  sa: ServiceAccount,
  p: Push,
  fetchFn = fetch,
): Promise<{ ok: boolean; status: number; unregistered: boolean }> {
  const token = await googleAccessToken(sa, "https://www.googleapis.com/auth/firebase.messaging", fetchFn);
  const res = await fetchFn(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify(fcmMessage(p)),
  });
  const text = res.ok ? "" : await res.text();
  return { ok: res.ok, status: res.status, unregistered: res.status === 404 || text.includes("UNREGISTERED") };
}
