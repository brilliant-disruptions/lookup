export const ALLOWED = new Set([
  "app_open",
  "onboarded",
  "notif_permission",
  "location_permission",
  "alert_scheduled",
  "alert_opened",
  "seen_yes",
  "seen_no",
  "finder_opened",
  "finder_on_target",
  "share",
  "invite",
  "paywall_shown",
  "purchase_started",
  "purchase_completed",
  "restore",
  "demo_played",
]);

export function sanitize(body: any): { install_id: string; name: string; at: string; props: Record<string, unknown> }[] {
  const id = String(body?.installId ?? "");
  if (!/^[a-f0-9-]{16,64}$/i.test(id)) throw new Error("installId");
  const events = Array.isArray(body?.events) ? body.events.slice(0, 100) : [];
  return events
    .filter((e: any) => ALLOWED.has(e?.name))
    .map((e: any) => {
      const props: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(e.props ?? {}).slice(0, 12)) {
        if (["string", "number", "boolean"].includes(typeof v)) props[k] = typeof v === "string" ? (v as string).slice(0, 80) : v;
      }
      const at = new Date(e.at);
      return { install_id: id, name: e.name, at: isNaN(at.getTime()) ? new Date().toISOString() : at.toISOString(), props };
    });
}
