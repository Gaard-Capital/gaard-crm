-- 009: each person's booking link (their Google Calendar appointment page)
--
-- Mail merge letters can say {{booking_link}}; it is filled with the link of
-- whoever sends the letter. The link lives on the person's own team_members row.
-- Only admins may write team_members (db/001), so everyone sets their own link
-- through set_my_booking_url(), which changes the caller's row and nothing else.
--
-- Safe to run twice.

begin;

alter table public.team_members add column if not exists booking_url text;

create or replace function public.set_my_booking_url(p_url text)
  returns void
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v text := nullif(trim(coalesce(p_url, '')), '');
begin
  if not public.is_team_member() then
    raise exception 'Only a signed-in team member can set a booking link';
  end if;
  if v is not null and v !~* '^https://[^[:space:]]+$' then
    raise exception 'A booking link starts with https://';
  end if;
  update public.team_members set booking_url = v where auth_user_id = auth.uid();
end;
$$;

revoke execute on function public.set_my_booking_url(text) from public, anon;
grant  execute on function public.set_my_booking_url(text) to authenticated;

commit;

-- The API picks up the new column and function
notify pgrst, 'reload schema';
