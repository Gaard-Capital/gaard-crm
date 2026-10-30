-- 011: an admin resets someone's second sign-in step (they lost or replaced their phone)
--
-- Settings > Team > "Reset 2-step" calls admin_reset_two_step(member id). It removes
-- that person's authenticator registrations; at their next sign-in the app asks them
-- to scan a new code. Their password, Google sign-in and data are untouched.
-- Only an admin who has passed the two-step check (is_admin()) can call it.
-- Moving to a new app with the old phone still at hand needs no admin: Settings >
-- "Use a new authenticator app".
--
-- Safe to run twice.

begin;

create or replace function public.admin_reset_two_step(p_member_id bigint)
  returns void
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_user uuid;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can reset the two-step sign-in';
  end if;
  select auth_user_id into v_user from public.team_members where id = p_member_id;
  if v_user is null then
    raise exception 'That person has not signed in yet, so there is nothing to reset';
  end if;
  delete from auth.mfa_factors where user_id = v_user;
end;
$$;

revoke execute on function public.admin_reset_two_step(bigint) from public, anon;
grant  execute on function public.admin_reset_two_step(bigint) to authenticated;

commit;

notify pgrst, 'reload schema';
