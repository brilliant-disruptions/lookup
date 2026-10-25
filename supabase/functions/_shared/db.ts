import { createClient, SupabaseClient } from "@supabase/supabase-js";
import { env } from "./http.ts";

/** Service-role client (bypasses RLS). Only ever used server-side. */
export function admin(): SupabaseClient {
  const url = env("SUPABASE_URL"), key = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set");
  return createClient(url, key, { auth: { persistSession: false } });
}
