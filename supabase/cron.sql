-- Run once in the SQL editor AFTER deploying functions. Replace <PROJECT_REF>
-- and store the service-role key in Vault first:
--   select vault.create_secret('<service-role-key>', 'lookup_service_key');
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'lookup-aurora-watch', '*/10 * * * *',
  $$
  select net.http_post(
    url := 'https://<PROJECT_REF>.supabase.co/functions/v1/aurora-watch',
    headers := jsonb_build_object(
      'authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'lookup_service_key'),
      'content-type', 'application/json'),
    body := '{}'::jsonb
  );
  $$
);

select cron.schedule('lookup-prune', '17 4 * * *', $$ select public.prune_lookup(); $$);
