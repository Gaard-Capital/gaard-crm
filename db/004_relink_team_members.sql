/* ======================================================================
   004  RELINK TEAM MEMBERS TO THEIR CURRENT ACCOUNTS
   Run once in the Supabase SQL Editor. Safe to run again.

   Two rows in team_members pointed at sign-in accounts that no longer
   exist (the accounts had been deleted and created again), so those people
   signed in fine but the database did not see them as team members.

   1. Every team member is tied to the confirmed account that has their
      email today, replacing a link to an account that is gone.
   2. link_team_member now does the same whenever an account is created or
      confirmed, instead of only filling an empty link.
   ====================================================================== */

begin;

update public.team_members t
   set auth_user_id = u.id, joined_at = coalesce(t.joined_at, now())
  from auth.users u
 where lower(u.email) = lower(t.email) and u.email_confirmed_at is not null
   and t.auth_user_id is distinct from u.id;

create or replace function public.link_team_member()
 returns trigger language plpgsql security definer set search_path to ''
as $$
begin
  if new.email_confirmed_at is not null then
    update public.team_members t
       set auth_user_id = new.id, joined_at = coalesce(t.joined_at, now())
     where lower(t.email) = lower(new.email)
       and (t.auth_user_id is null
            or not exists (select 1 from auth.users x where x.id = t.auth_user_id));
  end if;
  return new;
end $$;
revoke execute on function public.link_team_member() from public, anon, authenticated;

commit;

-- Check: every row should show the account's email next to the team email
select t.id, t.full_name, t.email, t.access_role, u.email as account_email
  from public.team_members t
  left join auth.users u on u.id = t.auth_user_id
 order by t.id;
