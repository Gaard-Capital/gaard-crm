-- =====================================================================
-- GAARD Capital CRM · Migration 8 of 9 · Client loyalty and benefit groups
--
-- Two of Jon's tabs are lists of people he already won, not prospects:
--
--   v_client_loyalty   funded clients: next Thanksgiving card, next referral
--                      check-in, last loyalty touch, mailing address
--   v_benefit_groups   affiliate benefit groups: plans served, commissions,
--                      shared employers, primary contact, next outreach
--
-- The two reminder types the loyalty view reads (thanksgiving_card,
-- referral_check_in) are reference rows in migration 10.
--
-- First run in the Supabase SQL Editor on Oct 3, 2026; this file was
-- rebuilt from the live schema on Oct 14, 2026.
-- =====================================================================

create or replace view public.v_client_loyalty with (security_invoker = true) as
 SELECT c.id AS contact_id,
    c.full_name,
    COALESCE(o.name, c.employer) AS client,
    sg.name AS segment,
    c.email,
    c.phone,
    COALESCE(c.mailing_address, o.mailing_address) AS mailing_address,
    op.funded_on,
    op.funded_aum,
    tc.due_on AS next_thanksgiving_card,
    rc.due_on AS next_referral_check_in,
    lt.due_on AS last_loyalty_touch_on,
    ltt.label AS last_loyalty_touch,
    tm.full_name AS owner
   FROM ((((((((public.contacts c
     JOIN public.segments sg ON ((sg.code = c.segment_code)))
     LEFT JOIN public.organizations o ON ((o.id = c.organization_id)))
     LEFT JOIN public.team_members tm ON ((tm.id = c.owner_id)))
     LEFT JOIN LATERAL ( SELECT p.funded_on,
            p.funded_aum
           FROM public.opportunities p
          WHERE ((p.contact_id = c.id) OR ((c.organization_id IS NOT NULL) AND (p.organization_id = c.organization_id)))
          ORDER BY (p.stage = 'funded'::text) DESC, p.opened_on DESC
         LIMIT 1) op ON (true))
     LEFT JOIN LATERAL ( SELECT r.due_on
           FROM public.reminders r
          WHERE ((r.contact_id = c.id) AND (r.reminder_type = 'thanksgiving_card'::text) AND (r.status = ANY (ARRAY['open'::text, 'snoozed'::text])))
          ORDER BY r.due_on
         LIMIT 1) tc ON (true))
     LEFT JOIN LATERAL ( SELECT r.due_on
           FROM public.reminders r
          WHERE ((r.contact_id = c.id) AND (r.reminder_type = 'referral_check_in'::text) AND (r.status = ANY (ARRAY['open'::text, 'snoozed'::text])))
          ORDER BY r.due_on
         LIMIT 1) rc ON (true))
     LEFT JOIN LATERAL ( SELECT r.due_on,
            r.reminder_type
           FROM public.reminders r
          WHERE ((r.contact_id = c.id) AND (r.reminder_type = ANY (ARRAY['thanksgiving_card'::text, 'referral_check_in'::text])) AND (r.status = 'done'::text))
          ORDER BY r.due_on DESC
         LIMIT 1) lt ON (true))
     LEFT JOIN public.reminder_types ltt ON ((ltt.code = lt.reminder_type)))
  WHERE (('client'::text = ANY (c.tags)) OR (EXISTS ( SELECT 1
           FROM public.opportunities p
          WHERE ((p.stage = 'funded'::text) AND ((p.contact_id = c.id) OR ((c.organization_id IS NOT NULL) AND (p.organization_id = c.organization_id)))))) OR (EXISTS ( SELECT 1
           FROM public.reminders r
          WHERE ((r.contact_id = c.id) AND (r.reminder_type = ANY (ARRAY['thanksgiving_card'::text, 'referral_check_in'::text]))))));

create or replace view public.v_benefit_groups with (security_invoker = true) as
 SELECT o.id AS organization_id,
    o.name,
    o.org_type,
    o.city,
    o.state,
    o.plans_served,
    o.commissions,
    o.shared_employers,
    o.advertises_retirement,
    cc.people,
    cc.primary_contact,
    cc.primary_email,
    cc.primary_title,
    tt.last_touch_on,
    tt.last_outcome,
    nr.due_on AS next_outreach_on,
    o.do_not_contact,
    o.notes
   FROM (((public.organizations o
     LEFT JOIN LATERAL ( SELECT count(*) AS people,
            (array_agg(c.full_name ORDER BY c.id))[1] AS primary_contact,
            (array_agg(c.email ORDER BY c.id))[1] AS primary_email,
            (array_agg(c.title ORDER BY c.id))[1] AS primary_title
           FROM public.contacts c
          WHERE (c.organization_id = o.id)) cc ON (true))
     LEFT JOIN LATERAL ( SELECT max(public.local_date(t.touched_at)) AS last_touch_on,
            (array_agg(x.label ORDER BY t.touched_at DESC))[1] AS last_outcome
           FROM ((public.touchpoints t
             JOIN public.contacts c ON ((c.id = t.contact_id)))
             LEFT JOIN public.outcomes x ON ((x.code = t.outcome_code)))
          WHERE (c.organization_id = o.id)) tt ON (true))
     LEFT JOIN LATERAL ( SELECT min(r.due_on) AS due_on
           FROM public.reminders r
          WHERE ((r.organization_id = o.id) AND (r.status = ANY (ARRAY['open'::text, 'snoozed'::text])))) nr ON (true))
  WHERE ((o.segment_code = 'AFFILIATE'::text) AND ((o.org_type ~~* '%benefit%'::text) OR ('benefit_group'::text = ANY (o.tags)) OR (o.plans_served IS NOT NULL)));
