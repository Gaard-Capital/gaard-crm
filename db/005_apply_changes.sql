/* ======================================================================
   005  SAVING FROM THE APP: apply_changes()
   Run once in the Supabase SQL Editor. Safe to run again.

   The app keeps the rows in memory, applies the outcome rules itself (the
   same rules as apply_outcome_rules), and after every change sends what
   changed: rows added, the columns that changed on existing rows, and rows
   removed. apply_changes() writes them in one transaction, so a change is
   saved whole or not at all.

   - It runs as the caller (security invoker), so row level security, the
     team list and the two-step requirement all still apply, and the audit
     log records the person who made the change.
   - It sets app.seeding for this transaction only, which tells the
     automation triggers (touchpoints_after_write and the rest) to stand
     down: the app has already done that work, and doing it twice would make
     duplicate reminders. The normalizing triggers still run: match keys,
     flag rules, the do-not-contact block, milestone dates.
   - Only columns that exist in the table are written; anything else the
     app keeps on a row is ignored.
   - Ids chosen by the app move each table's id counter past them, so rows
     the database creates later do not collide.
   ====================================================================== */

begin;

create or replace function public.apply_changes(p_changes jsonb)
 returns jsonb
 language plpgsql
 security invoker
 set search_path to 'public', 'pg_temp'
as $$
declare
  ch      jsonb;
  t       text;
  op      text;
  r       jsonb;
  cols    text;
  sets    text;
  n       int := 0;
  inserted text[] := '{}';
  allowed constant text[] := array['team_members', 'events', 'campaigns', 'organizations', 'contacts', 'rfps',
                                   'touchpoints', 'opportunities', 'reminders', 'email_messages', 'flag_rules'];
begin
  if auth.uid() is null or not public.is_team_member() then
    raise exception 'Sign in as a team member, with your two-step code, to save changes' using errcode = '42501';
  end if;

  perform set_config('app.seeding', 'on', true);

  for ch in select value from jsonb_array_elements(p_changes) loop
    t  := ch->>'table';
    op := ch->>'op';
    r  := coalesce(ch->'row', '{}'::jsonb);
    if not (t = any (allowed)) then
      raise exception 'The app cannot change the table %', t;
    end if;

    if op = 'delete' then
      execute format('delete from public.%I where id = $1', t) using (ch->>'id')::bigint;
    else
      select string_agg(quote_ident(c.column_name), ', ' order by c.ordinal_position),
             string_agg(format('%I = r.%I', c.column_name, c.column_name), ', ' order by c.ordinal_position)
               filter (where c.column_name <> 'id')
        into cols, sets
        from information_schema.columns c
       where c.table_schema = 'public' and c.table_name = t
         and c.is_generated = 'NEVER' and r ? c.column_name;
      if cols is null then continue; end if;

      if op = 'insert' then
        execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1)', t, cols, cols, t)
          using r;
        if not (t = any (inserted)) then inserted := inserted || t; end if;
      elsif op = 'update' then
        if sets is null then continue; end if;
        execute format('update public.%I set %s from jsonb_populate_record(null::public.%I, $1) r where %I.id = $2', t, sets, t, t)
          using r, (ch->>'id')::bigint;
      else
        raise exception 'Unknown change "%"', op;
      end if;
    end if;
    n := n + 1;
  end loop;

  foreach t in array inserted loop
    begin
      execute format('select setval(pg_get_serial_sequence(%L, %L), greatest((select max(id) from public.%I), 1))',
                     'public.' || t, 'id', t);
    exception when insufficient_privilege then null;   -- the counter catches up on the next database insert instead
    end;
  end loop;

  return jsonb_build_object('applied', n);
end $$;

revoke execute on function public.apply_changes(jsonb) from public, anon;
grant  execute on function public.apply_changes(jsonb) to authenticated;

commit;
