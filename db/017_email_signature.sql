-- 017: each person's email signature (and, if they want, a logo beside it)
--
-- Letters end with the sender's name and the firm by default. A person who sets a
-- signature in Settings has it at the foot of their letters instead (mass email,
-- replies, RFP letters); a logo link puts the picture beside it in the email, the
-- way Jon's own signature looks. Kept on the person's own team_members row, so it
-- never sits in the repository. Only admins may write team_members (db/001), so
-- everyone sets their own through set_my_signature(), which changes the caller's
-- row and nothing else.
--
-- Safe to run twice.

begin;

alter table public.team_members add column if not exists email_signature text;
alter table public.team_members add column if not exists email_logo_url  text;

create or replace function public.set_my_signature(p_signature text, p_logo_url text)
  returns void
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_sig  text := nullif(trim(coalesce(p_signature, '')), '');
  v_logo text := nullif(trim(coalesce(p_logo_url, '')), '');
begin
  if not public.is_team_member() then
    raise exception 'Only a signed-in team member can set a signature';
  end if;
  if length(coalesce(v_sig, '')) > 1000 then
    raise exception 'A signature can be at most 1,000 characters';
  end if;
  if v_logo is not null and v_logo !~* '^https://[^[:space:]]+$' then
    raise exception 'A logo link starts with https://';
  end if;
  update public.team_members set email_signature = v_sig, email_logo_url = v_logo where auth_user_id = auth.uid();
end;
$$;

revoke execute on function public.set_my_signature(text, text) from public, anon;
grant  execute on function public.set_my_signature(text, text) to authenticated;

commit;

notify pgrst, 'reload schema';
