-- 015: connecting a team member's own Claude (claude.ai) to the CRM
--
-- The Edge Function supabase/functions/claude-connector is an MCP server: a
-- person adds its address to Claude as a custom connector, and their Claude can
-- then list who has not replied, look people up, and store a reply with a
-- suggested outcome (it waits under the bell for a person to confirm).
--
-- The address ends with a long random key that belongs to one person. The key
-- is made in the browser (Settings > Connect your Claude) and shown once; the
-- database keeps only its SHA-256 hash, so a copy of this table cannot be used
-- to connect. One key per person; making a new one replaces the old, and
-- "Disconnect" removes it. Deactivating a team member also cuts their Claude off
-- (the function checks is_active).
--
-- Nobody reads or writes connector_keys through the API: the three functions
-- below act on the caller's own row only, and the Edge Function reads it with
-- the service role.
--
-- Safe to run twice.

begin;

create table if not exists public.connector_keys (
  team_member_id bigint primary key references public.team_members(id) on delete cascade,
  key_hash       text not null unique,            -- hex SHA-256 of the key
  created_at     timestamptz not null default now(),
  last_used_at   timestamptz
);

alter table public.connector_keys enable row level security;   -- no policies: closed to the API
revoke all on public.connector_keys from anon, authenticated;
grant select, insert, update, delete on public.connector_keys to service_role;

drop trigger if exists zz_audit on public.connector_keys;
create trigger zz_audit after insert or update or delete on public.connector_keys
  for each row execute function public.audit_row();

-- Is my Claude connected, and when was it last used?
create or replace function public.my_connector_key()
  returns table (created_at timestamptz, last_used_at timestamptz)
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
begin
  if not public.is_team_member() then
    raise exception 'Only a signed-in team member can see this';
  end if;
  return query
    select k.created_at, k.last_used_at
      from public.connector_keys k
      join public.team_members t on t.id = k.team_member_id
     where t.auth_user_id = auth.uid();
end;
$$;

-- A new key for me (the hash of it), replacing any earlier one.
create or replace function public.set_my_connector_key(p_hash text)
  returns void
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_me bigint;
begin
  if not public.is_team_member() then
    raise exception 'Only a signed-in team member can connect Claude';
  end if;
  if p_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Expected the SHA-256 of the key';
  end if;
  select id into v_me from public.team_members where auth_user_id = auth.uid();
  insert into public.connector_keys (team_member_id, key_hash) values (v_me, p_hash)
    on conflict (team_member_id) do update set key_hash = excluded.key_hash, created_at = now(), last_used_at = null;
end;
$$;

-- Disconnect my Claude.
create or replace function public.drop_my_connector_key()
  returns void
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  if not public.is_team_member() then
    raise exception 'Only a signed-in team member can disconnect Claude';
  end if;
  delete from public.connector_keys
   where team_member_id = (select id from public.team_members where auth_user_id = auth.uid());
end;
$$;

revoke execute on function public.my_connector_key()          from public, anon;
revoke execute on function public.set_my_connector_key(text)  from public, anon;
revoke execute on function public.drop_my_connector_key()     from public, anon;
grant  execute on function public.my_connector_key()          to authenticated;
grant  execute on function public.set_my_connector_key(text)  to authenticated;
grant  execute on function public.drop_my_connector_key()     to authenticated;

commit;

notify pgrst, 'reload schema';
