/* ======================================================================
   002  RFP LOG COLUMNS
   Run once in the Supabase SQL Editor. Safe to run again.

   Jon's RFP log ("Request for Proposals SENT LOG") tracks a few things
   the rfps table did not have. How each of his columns maps:

     RFP Name / Issuer            title, organization_id         (existing)
     RFP Reference Number         reference_number               (new)
     Final Submission Date        submitted_on                   (existing)
     Approved for Submission      approved_for_submission        (new)
     Reviewed By                  reviewed_by                    (new)
     Date Reviewed                reviewed_on                    (new)
     Size of AUM                  est_mandate_aum                (existing)
     Conditions or Limitations    terms                          (new)
     Notes                        notes                          (existing)
     Response (Y/N)               decision_on is not null        (derived)
     Date Responded               decision_on                    (existing)
     Correspondence               decision_result, decision_notes (new)
     WON                          status = 'won'                 (existing)

   decision_result keeps Jon's five endings apart, where status only says
   won or lost. Existing RLS policies and the audit trigger already cover
   the table, so new columns need nothing else.
   ====================================================================== */

begin;

alter table public.rfps
  add column if not exists reference_number        text,
  add column if not exists approved_for_submission boolean,
  add column if not exists reviewed_by             text,
  add column if not exists reviewed_on             date,
  add column if not exists terms                   text,
  add column if not exists decision_result         text,
  add column if not exists decision_notes          text;

do $$ begin
  alter table public.rfps add constraint rfps_decision_result_check check (decision_result in
    ('awarded', 'finalist_not_selected', 'not_shortlisted', 'disqualified', 'not_awarded'));
exception when duplicate_object then null; end $$;

comment on column public.rfps.reference_number        is 'The issuer''s RFP number, e.g. "RFP 2025-IA-03", or "Direct proposal".';
comment on column public.rfps.approved_for_submission is 'Compliance approved the response for submission.';
comment on column public.rfps.reviewed_by             is 'Who reviewed it before submission (a person or "Compliance").';
comment on column public.rfps.reviewed_on             is 'Date of that review.';
comment on column public.rfps.terms                   is 'Conditions or limitations proposed: advisory model, fee, registration needed.';
comment on column public.rfps.decision_result         is 'How it ended: awarded, finalist_not_selected, not_shortlisted, disqualified, not_awarded.';
comment on column public.rfps.decision_notes          is 'The decision correspondence: who wrote, what they said.';

commit;
