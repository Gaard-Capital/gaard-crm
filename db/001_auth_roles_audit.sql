/* ======================================================================
   001  ACCOUNTS, ROLES, TWO-FACTOR AND THE AUDIT LOG
   Run once in the Supabase SQL Editor. Safe to run again.

   What it does
     1. team_members becomes the list of who may sign in, with a role:
        admin (manages who is on the team, reads the audit log) or member.
     2. is_team_member() now also requires the second factor (aal2), so a
        stolen password alone reads nothing. Every existing policy calls it,
        so they all tighten at once.
     3. Policies split: the team reads, adds, edits and deletes; only admins
        change who is on the team.
     4. audit_log records every insert, update and delete: who, when, which
        row, the old values and the new. A deleted row is kept there in
        full, so a wrong delete or merge can be undone. Nobody can edit or
        delete the log through the app.
     5. hook_before_user_created refuses an account for any email that is
        not on the team list. Enable it in the dashboard afterwards:
        Authentication > Auth Hooks > Before User Created > this function.
     6. A confirmed sign-in is tied to its team_members row by email.
     7. While the product is being built, everyone on the list is admin.

   The dashboard (Table Editor, SQL Editor) runs as postgres and is not
   affected by any of this.
   ====================================================================== */

begin;

/* ---------- 1. The team list ---------- */
alter table public.team_members
  add column if not exists access_role text not null default 'member',
  add column if not exists invited_at timestamptz,
  add column if not exists invited_by bigint references public.team_members(id),
  add column if not exists joined_at timestamptz;

do $$ begin
  alter table public.team_members
    add constraint team_members_access_role_check check (access_role in ('admin','member'));
exception when duplicate_object then null; end $$;

create unique index if not exists team_members_email_key
  on public.team_members (lower(email)) where email is not null;

/* ---------- 2. Access checks ---------- */
-- Signed in, on the active team list, and past the second factor.
create or replace function public.is_team_member()
 returns boolean language sql stable security definer set search_path to ''
as $$
  select coalesce(auth.jwt()->>'aal', '') = 'aal2'
     and exists (select 1 from public.team_members
                  where auth_user_id = auth.uid() and is_active)
$$;

create or replace function public.is_admin()
 returns boolean language sql stable security definer set search_path to ''
as $$
  select public.is_team_member()
     and exists (select 1 from public.team_members
                  where auth_user_id = auth.uid() and is_active and access_role = 'admin')
$$;

-- What the app asks right after sign-in, before the second factor:
-- am I on the list, and have I passed 2FA yet?
create or replace function public.my_access()
 returns json language sql stable security definer set search_path to ''
as $$
  select json_build_object('member', t.id is not null, 'id', t.id, 'name', t.full_name,
                           'role', t.access_role, 'aal', coalesce(auth.jwt()->>'aal', 'aal1'))
    from (select 1) one
    left join public.team_members t on t.auth_user_id = auth.uid() and t.is_active
$$;

revoke execute on function public.is_team_member(), public.is_admin(), public.my_access() from public, anon;
grant  execute on function public.is_team_member(), public.is_admin(), public.my_access() to authenticated;

/* ---------- 3. Policies ---------- */
do $$
declare t text;
begin
  for t in select tablename from pg_policies
            where schemaname = 'public' and policyname = 'team_access' loop
    execute format('drop policy team_access on public.%I', t);
    execute format('create policy team_read on public.%I for select to authenticated using (public.is_team_member())', t);
    if t = 'team_members' then
      execute format('create policy admin_write on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
    else
      execute format('create policy team_insert on public.%I for insert to authenticated with check (public.is_team_member())', t);
      execute format('create policy team_update on public.%I for update to authenticated using (public.is_team_member()) with check (public.is_team_member())', t);
      execute format('create policy team_delete on public.%I for delete to authenticated using (public.is_team_member())', t);
    end if;
  end loop;
end $$;

/* ---------- 4. Audit log ---------- */
create table if not exists public.audit_log (
  id              bigint generated always as identity primary key,
  at              timestamptz not null default now(),
  actor_auth_id   uuid,
  actor_member_id bigint,
  actor_email     text,
  table_name      text not null,
  row_key         text,
  action          text not null,
  old_data        jsonb,
  new_data        jsonb
);
create index if not exists audit_log_row on public.audit_log (table_name, row_key);
create index if not exists audit_log_at  on public.audit_log (at desc);

alter table public.audit_log enable row level security;
drop policy if exists admin_read on public.audit_log;
create policy admin_read on public.audit_log for select to authenticated using (public.is_admin());
revoke insert, update, delete, truncate on public.audit_log from public, anon, authenticated;

-- Updates keep only the columns that changed; an update that changes
-- nothing but updated_at is not logged.
create or replace function public.audit_row()
 returns trigger language plpgsql security definer set search_path to ''
as $$
declare
  rec   jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  old_j jsonb;
  new_j jsonb;
begin
  if tg_op = 'UPDATE' then
    select jsonb_object_agg(k, to_jsonb(old)->k), jsonb_object_agg(k, to_jsonb(new)->k)
      into old_j, new_j
      from jsonb_object_keys(to_jsonb(new)) as k
     where k <> 'updated_at' and to_jsonb(new)->k is distinct from to_jsonb(old)->k;
    if old_j is null then return null; end if;
  elsif tg_op = 'INSERT' then
    new_j := to_jsonb(new);
  else
    old_j := to_jsonb(old);
  end if;

  insert into public.audit_log (actor_auth_id, actor_member_id, actor_email, table_name, row_key, action, old_data, new_data)
  select auth.uid(), m.id, coalesce(m.email, auth.jwt()->>'email'), tg_table_name,
         coalesce(rec->>'id', rec->>'code', rec->>'domain', rec->>'phrase', rec->>'header_key', rec->>'tab'),
         lower(tg_op), old_j, new_j
    from (select 1) one
    left join public.team_members m on m.auth_user_id = auth.uid();
  return null;
end $$;
revoke execute on function public.audit_row() from public, anon, authenticated;

-- Every table except the log itself and import_rows (a staging table that
-- an import fills by the thousand; the rows it produces are logged anyway).
do $$
declare t text;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r'
              and c.relname not in ('audit_log', 'import_rows') loop
    execute format('drop trigger if exists zz_audit on public.%I', t);
    execute format('create trigger zz_audit after insert or update or delete on public.%I for each row execute function public.audit_row()', t);
  end loop;
end $$;

/* ---------- 5. Only listed emails can create an account ---------- */
create or replace function public.hook_before_user_created(event jsonb)
 returns jsonb language sql stable security definer set search_path to ''
as $$
  select case
    when exists (select 1 from public.team_members
                  where lower(email) = lower(event->'user'->>'email') and is_active)
    then '{}'::jsonb
    else jsonb_build_object('error', jsonb_build_object(
           'http_code', 403,
           'message', 'This email is not on the Gaard Capital team list. Ask an administrator for an invitation.'))
  end
$$;
revoke execute on function public.hook_before_user_created(jsonb) from public, anon, authenticated;
grant  execute on function public.hook_before_user_created(jsonb) to supabase_auth_admin;

/* ---------- 6. Tie a confirmed sign-in to its team row ---------- */
create or replace function public.link_team_member()
 returns trigger language plpgsql security definer set search_path to ''
as $$
begin
  if new.email_confirmed_at is not null then
    update public.team_members
       set auth_user_id = new.id, joined_at = coalesce(joined_at, now())
     where lower(email) = lower(new.email) and auth_user_id is null;
  end if;
  return new;
end $$;
revoke execute on function public.link_team_member() from public, anon, authenticated;

drop trigger if exists link_team_member on auth.users;
create trigger link_team_member
  after insert or update of email_confirmed_at on auth.users
  for each row execute function public.link_team_member();

-- Accounts that already exist
update public.team_members t
   set auth_user_id = u.id, joined_at = coalesce(t.joined_at, now())
  from auth.users u
 where lower(u.email) = lower(t.email) and u.email_confirmed_at is not null
   and t.auth_user_id is null;

/* ---------- 7. Build phase: everyone on the list is admin ----------
   Jon Clifford (1) and the four builders (2-5). Before handover, set the
   builders back to member or inactive from the app's team screen. */
update public.team_members set access_role = 'admin' where id in (1, 2, 3, 4, 5);

commit;
