-- =====================================================================
-- GAARD Capital CRM · Migration 6 of 6 · Access control (Supabase)
--
-- Jon: "everyone on the team right now has access to this ... it's not
-- really a concern about limiting access". So the rule is simple:
-- a signed-in person who is an active row in team_members can read and
-- edit everything; nobody else can see anything.
--
-- After running this:
--   1. Supabase dashboard > Authentication > turn OFF public sign-ups,
--      invite each team member by email.
--   2. Put each person's auth user id in team_members.auth_user_id.
--
-- On a plain Postgres without Supabase's auth schema this migration
-- only enables row-level security and skips the policies.
-- =====================================================================

do $migration$
declare
  t record;
  has_auth boolean := to_regprocedure('auth.uid()') is not null
                      and exists (select 1 from pg_roles where rolname = 'authenticated');
begin
  if has_auth then
    execute $f$
      create or replace function public.is_team_member() returns boolean
      language sql stable security definer set search_path = '' as $body$
        select exists (select 1 from public.team_members
                        where auth_user_id = auth.uid() and is_active)
      $body$
    $f$;
    execute 'revoke execute on function public.is_team_member() from public, anon';
    execute 'grant execute on function public.is_team_member() to authenticated';
  else
    raise notice 'Supabase auth not found: enabling row-level security without policies';
  end if;

  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
    if has_auth then
      execute format('drop policy if exists team_access on public.%I', t.tablename);
      execute format('create policy team_access on public.%I for all to authenticated '
                     'using (public.is_team_member()) with check (public.is_team_member())', t.tablename);
    end if;
  end loop;
end
$migration$;
