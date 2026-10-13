-- Required F-08 runtime setup after the feature migration and worker deployment.
-- Create Vault secrets in the approved Supabase project:
-- keyword_push_url = https://<project-ref>.supabase.co/functions/v1/dispatch-keyword-push
-- keyword_push_secret = same value as Edge Function PUSH_DISPATCH_SECRET
-- Never put their values in a committed SQL file.
begin;
do $$ begin
  if to_regprocedure('public.companion_module_version()') is null then
    raise exception 'Apply the F-07/F-08/F-10 migration first';
  end if;
  if (select count(*) from vault.decrypted_secrets where name='keyword_push_url' and decrypted_secret<>'')<>1
    or (select count(*) from vault.decrypted_secrets where name='keyword_push_secret' and decrypted_secret<>'')<>1 then
    raise exception 'Configure exactly one keyword_push_url and keyword_push_secret in Vault first';
  end if;
end $$;
create extension if not exists pg_net with schema extensions;
select cron.schedule('gachita-keyword-push','* * * * *', $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name='keyword_push_url'),
    headers := jsonb_build_object('Content-Type','application/json','x-dispatch-secret',
      (select decrypted_secret from vault.decrypted_secrets where name='keyword_push_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
$job$);
commit;
