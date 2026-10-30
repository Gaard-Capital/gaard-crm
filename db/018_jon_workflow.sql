-- 018: what Jon's own Claude skills do, inside the CRM
--
-- 1. opportunities.onboarding_checklist: the firm's 21-step onboarding checklist
--    (gaard-onboarding-checklist), one status note per step, kept as JSON
--    ({"0": "Delivered via email and documented, June 9, 2026", ...}) keyed by the
--    step's place in the fixed list the app holds.
-- 2. team_members.zoom_link and invite_also: the Zoom link a person's call
--    invitations carry, and who is always invited with them (Jon invites
--    Dr. Brogaard to every call: gaard-call-scheduler). Set by each person in
--    Settings through set_my_meeting_defaults(), for the caller's row only.
-- 3. The short "Nonprofit investing" letter (jb-mail-merge) as a shared template,
--    added once.
--
-- Safe to run twice.

begin;

alter table public.opportunities add column if not exists onboarding_checklist jsonb;
alter table public.team_members  add column if not exists zoom_link   text;
alter table public.team_members  add column if not exists invite_also text;

create or replace function public.set_my_meeting_defaults(p_zoom_link text, p_invite_also text)
  returns void
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_zoom   text := nullif(trim(coalesce(p_zoom_link, '')), '');
  v_invite text := nullif(trim(coalesce(p_invite_also, '')), '');
begin
  if not public.is_team_member() then
    raise exception 'Only a signed-in team member can set these';
  end if;
  if v_zoom is not null and v_zoom !~* '^https://[^[:space:]]+$' then
    raise exception 'A Zoom link starts with https://';
  end if;
  if v_invite is not null and v_invite !~* '^\s*[^@\s,]+@[^@\s,]+\.[^@\s,]+(\s*,\s*[^@\s,]+@[^@\s,]+\.[^@\s,]+)*\s*$' then
    raise exception 'Write the addresses to invite separated by commas';
  end if;
  update public.team_members set zoom_link = v_zoom, invite_also = v_invite where auth_user_id = auth.uid();
end;
$$;

revoke execute on function public.set_my_meeting_defaults(text, text) from public, anon;
grant  execute on function public.set_my_meeting_defaults(text, text) to authenticated;

insert into public.email_templates (name, segment_code, subject, body, is_first)
select 'Nonprofit investing (short)', 'ORG_NONPROFIT', 'Nonprofit investing',
       E'Hi {{first_name}},\n\nI am curious how {{Organization Name}} manages its investments. Would you be open to a brief chat?\n\nIf it is easier, pick a time here: {{booking_link}}\n\n{{sender_name}}\n{{firm_name}}',
       false
 where not exists (select 1 from public.email_templates where name = 'Nonprofit investing (short)');

commit;

notify pgrst, 'reload schema';
