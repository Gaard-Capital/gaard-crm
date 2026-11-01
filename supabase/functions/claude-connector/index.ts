// claude-connector: lets a team member's own Claude (claude.ai) put email
// replies into the CRM. It is an MCP server (Model Context Protocol, the way
// Claude talks to outside tools) with seven narrow tools and nothing else:
//
//   outreach_waiting_for_reply  who we wrote to and have not heard back from
//   find_contact                look one person up by email or name
//   record_reply                store a reply with its closest outcome
//   list_events                 the events on the CRM's Events page
//   record_event                add, update or take back an event (from Jon's Gaard
//                               Event Finder: Going, Maybe, Attended, Not going)
//   list_rfps                   the RFP log, in its 13 columns
//   record_rfp                  add or update an RFP, column for column as the log
//
// A reply recorded here sets the outcome on the letter's activity, exactly as
// the CRM's own Gmail check does; the database's outcome rules then schedule
// the follow-up. It appears under the bell for three days and a person can
// Change it on the contact's activity. Claude cannot delete, merge, send, or
// read anything else.
//
// Who is calling: each person makes their own long random key in Settings >
// Connect your Claude, and their connector address ends with it:
//   https://<project>.supabase.co/functions/v1/claude-connector/<key>
// The database keeps only the key's SHA-256 (connector_keys, db/015); the
// person must be an active team member. Disconnect in Settings, or
// deactivating the person, cuts their Claude off.
//
// Deploy: Supabase dashboard > Edge Functions > Deploy a new function > Via
// Editor, name it claude-connector, paste this file, deploy. In its Details
// turn OFF "Verify JWT" (claude.ai sends no Supabase sign-in; the key in the
// address is the check). No secret to add: SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY are already there. The function writes with the
// service role, so the audit log shows no user on these rows; ai_reason names
// the person whose Claude wrote it.

const PROTOCOLS = ['2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05'];
const OUTCOMES: Record<string, string> = {
  INTERESTED: 'Interested, call scheduled',
  NOT_NOW: 'Not now, check back later',
  NOT_INTERESTED: 'Not interested / no thank you',
  BOUNCED: 'Bounced / wrong email',
  OUT_OF_OFFICE: 'Out of office (auto-reply)',
  UNSUBSCRIBE: 'Asked not to be contacted',
  WRONG_PERSON: 'No longer there / wrong person',
  REFERRED_INTERNALLY: 'Pointed us to a colleague',
  HAS_ADVISOR: 'Already has an advisor',
};

const TOOLS = [
  {
    name: 'outreach_waiting_for_reply',
    description: 'People Gaard Capital emailed who have not replied yet (their latest email still says No response). Use it to know whose replies to look for in Gmail.',
    inputSchema: { type: 'object', properties: {
      days: { type: 'integer', description: 'How far back to look, in days (default 60, at most 365).' },
    } },
    annotations: { readOnlyHint: true },
  },
  {
    name: 'find_contact',
    description: 'Look up a person in the Gaard CRM by email address or by name. Returns at most 10 people with their organization, latest outcome and next follow-up.',
    inputSchema: { type: 'object', properties: {
      query: { type: 'string', description: 'An email address, or part of a name.' },
    }, required: ['query'] },
    annotations: { readOnlyHint: true },
  },
  {
    name: 'record_reply',
    description: 'Store a reply someone sent to one of our emails, with the closest outcome. The CRM sets that outcome and schedules the follow-up from it; a person can change it in the CRM. ' +
      'Outcomes: ' + Object.entries(OUTCOMES).map(([k, v]) => `${k} = ${v}`).join('; ') + '. Use UNSUBSCRIBE only when they ask us to stop writing.',
    inputSchema: { type: 'object', properties: {
      email: { type: 'string', description: "The sender's email address." },
      reply_text: { type: 'string', description: 'Their reply, without the earlier emails quoted under it.' },
      received_at: { type: 'string', description: 'When the reply arrived, ISO 8601 (e.g. 2026-10-23T14:05:00Z).' },
      suggested_outcome: { type: 'string', enum: Object.keys(OUTCOMES) },
      confidence: { type: 'number', description: 'How sure you are, 0 to 1.' },
      reason: { type: 'string', description: 'One short sentence: why this outcome.' },
      gmail_message_id: { type: 'string', description: "Gmail's message id, if known; stops the same reply being stored twice." },
    }, required: ['email', 'reply_text', 'received_at', 'suggested_outcome'] },
  },
  {
    name: 'list_events',
    description: "Events on the Gaard CRM's Events page between two dates, with how many people were met at each. Use it to see what the CRM already has before record_event, or to write CRM notes back to the Gaard Event Finder.",
    inputSchema: { type: 'object', properties: {
      from: { type: 'string', description: 'First day, YYYY-MM-DD (default: 120 days ago).' },
      to: { type: 'string', description: 'Last day, YYYY-MM-DD (default: 180 days ahead).' },
    } },
    annotations: { readOnlyHint: true },
  },
  {
    name: 'list_rfps',
    description: "The Gaard CRM's RFP log, in the 13 columns of Jon's RFP Log sheet, plus the status and who won. Everyone on the team sees the same log.",
    inputSchema: { type: 'object', properties: {} },
    annotations: { readOnlyHint: true },
  },
  {
    name: 'record_rfp',
    description: "Add an RFP to the Gaard CRM's RFP log, or update it (matched on the reference number, then on issuer and name). The fields are the columns of Jon's RFP Log. Send what is known; anything left out stays as it is. Dates YYYY-MM-DD, AUM a plain number. A new RFP that has only been found and screened: status identified. Do not put staff names in notes.",
    inputSchema: { type: 'object', properties: {
      rfp_name: { type: 'string' }, issuer: { type: 'string', description: 'The organization issuing it.' },
      reference_number: { type: 'string' }, final_submission_date: { type: 'string' },
      approved_for_submission: { type: 'string', enum: ['Y', 'N'] }, reviewed_by: { type: 'string' }, date_reviewed: { type: 'string' },
      size_of_aum: { type: 'number' }, conditions_or_limitations: { type: 'string' }, notes: { type: 'string', description: 'Submission mechanics and the deal summary, or the screening notes.' },
      response: { type: 'string', description: 'N until they answer, then their answer.' }, date_responded: { type: 'string' }, correspondence: { type: 'string' },
      won: { type: 'string', enum: ['Y', 'N'] }, status: { type: 'string', enum: ['identified', 'intent_to_bid', 'submitted', 'finalist', 'won', 'lost', 'declined', 'cancelled'] },
      arrangement: { type: 'string', description: 'Type of arrangement, for example OPEB trust; direct institutional portfolio.' },
      winner: { type: 'string', description: 'Who won, when we did not.' }, how_we_scored: { type: 'string' }, url: { type: 'string', description: 'The RFP page or document.' },
    }, required: ['rfp_name', 'issuer'] },
  },
  {
    name: 'record_event',
    description: "Keep the Gaard CRM's Events page in step with the Gaard Event Finder. Call it whenever an event is marked Going, Maybe or Attended, and with status not_going whenever that mark is taken off. An event already there (same finder_id, or the same or a close name within three days) is updated, not added twice. not_going deletes the event from the CRM, or, if people were met at it, keeps it marked Not going.",
    inputSchema: { type: 'object', properties: {
      name: { type: 'string' },
      date: { type: 'string', description: 'The day it starts, YYYY-MM-DD.' },
      end_date: { type: 'string', description: 'The last day, YYYY-MM-DD, for an event of several days.' },
      status: { type: 'string', enum: ['going', 'maybe', 'attended', 'not_going'] },
      finder_id: { type: 'string', description: "The Event Finder's own id for this event." },
      format: { type: 'string', enum: ['in_person', 'virtual', 'hybrid'] },
      kind: { type: 'string', enum: ['conference', 'networking', 'webinar', 'workshop', 'other'] },
      host: { type: 'string', description: 'The organization or association running it.' },
      city: { type: 'string' },
      state: { type: 'string', description: 'Two-letter state, e.g. UT.' },
      cost_usd: { type: 'number' },
      people_met: { type: 'integer', description: 'How many contacts were made there, once attended.' },
      url: { type: 'string', description: 'The event page.' },
      notes: { type: 'string' },
    }, required: ['name', 'date'] },
  },
];

// deno-lint-ignore no-explicit-any
type Db = any;
const normEmail = (s: unknown) => {
  const e = String(s ?? '').trim().toLowerCase().replace(/^mailto:|[<>\s]/g, '');
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e) ? e : null;
};
const day = (d: unknown) => (d ? String(d).slice(0, 10) : '');

/** Who a key belongs to: the active team member whose key has this SHA-256 (db/015). */
async function personForKey(db: Db, key: string): Promise<string | null> {
  if (!/^[0-9a-f]{48,128}$/.test(key)) return null;
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(key));
  const hash = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
  const { data } = await db.from('connector_keys').select('team_member_id, last_used_at, team_members(email, is_active)').eq('key_hash', hash).limit(1);
  const k = data?.[0];
  if (!k?.team_members?.is_active || !k.team_members.email) return null;
  // last used, at most once an hour (each write is also an audit row)
  if (!k.last_used_at || Date.now() - new Date(k.last_used_at).getTime() > 3600e3)
    await db.from('connector_keys').update({ last_used_at: new Date().toISOString() }).eq('team_member_id', k.team_member_id);
  return String(k.team_members.email).toLowerCase();
}

async function waiting(db: Db, args: { days?: number }) {
  const days = Math.min(365, Math.max(1, Number(args.days) || 60));
  const since = new Date(Date.now() - days * 864e5).toISOString();
  const { data, error } = await db.from('touchpoints')
    .select('id, contact_id, subject, touched_at, outcome_code, outcome_status, contacts(full_name, email, do_not_contact, organizations(name))')
    .in('touch_type', ['email', 'check_in']).eq('direction', 'outbound').gte('touched_at', since)
    .order('touched_at', { ascending: false }).limit(2000);
  if (error) throw new Error(error.message);
  const latest = new Map<number, Db>();
  for (const t of data ?? []) if (!latest.has(t.contact_id)) latest.set(t.contact_id, t);
  const rows = [...latest.values()].filter((t) => t.outcome_code === 'NO_RESPONSE' && t.outcome_status === 'confirmed'
    && t.contacts?.email && !t.contacts.do_not_contact);
  if (!rows.length) return `Nobody is waiting for a reply from the last ${days} days.`;
  return `No reply yet from ${rows.length} ${rows.length === 1 ? 'person' : 'people'} emailed in the last ${days} days:\n` + rows.map((t) =>
    `- ${t.contacts.full_name} <${t.contacts.email}>${t.contacts.organizations?.name ? ', ' + t.contacts.organizations.name : ''}: "${t.subject ?? ''}" sent ${day(t.touched_at)}`).join('\n');
}

async function find(db: Db, args: { query?: string }) {
  const q = String(args.query ?? '').trim();
  if (q.length < 2) return 'Give an email address or at least two letters of a name.';
  const e = normEmail(q);
  let req = db.from('contacts').select('id, full_name, email, title, do_not_contact, organizations(name)').limit(10);
  req = e ? req.eq('email_key', e) : req.ilike('full_name', '%' + q.replace(/[%_,()]/g, ' ') + '%');
  const { data, error } = await req;
  if (error) throw new Error(error.message);
  if (!data?.length) return `No one in the CRM matches "${q}".`;
  const ids = data.map((c: Db) => c.id);
  const [{ data: tps }, { data: rem }] = await Promise.all([
    db.from('touchpoints').select('contact_id, touched_at, responded_at, outcome_code, outcome_status, ai_suggested_outcome').in('contact_id', ids).order('touched_at', { ascending: false }).limit(500),
    db.from('reminders').select('contact_id, due_on').in('contact_id', ids).eq('status', 'open').order('due_on').limit(500),
  ]);
  return data.map((c: Db) => {
    const t = (tps ?? []).find((x: Db) => x.contact_id === c.id), r = (rem ?? []).find((x: Db) => x.contact_id === c.id);
    const last = !t ? 'no activity yet' : t.outcome_status === 'needs_review'
      ? `replied ${day(t.responded_at)}, waiting to be confirmed (suggested ${OUTCOMES[t.ai_suggested_outcome] ?? 'nothing'})`
      : `${t.outcome_code === 'NO_RESPONSE' ? 'emailed, no response yet' : OUTCOMES[t.outcome_code] ?? t.outcome_code ?? 'no outcome'} (${day(t.touched_at)})`;
    return `- ${c.full_name} <${c.email ?? 'no email'}>${c.title ? ', ' + c.title : ''}${c.organizations?.name ? ', ' + c.organizations.name : ''}. Latest: ${last}. Next follow-up: ${r ? r.due_on : 'none'}${c.do_not_contact ? '. DO NOT CONTACT' : ''}`;
  }).join('\n');
}

async function record(db: Db, me: string, a: Record<string, unknown>) {
  const email = normEmail(a.email);
  if (!email) return { text: 'That email address does not look right.', error: true };
  const code = String(a.suggested_outcome ?? '');
  if (!OUTCOMES[code]) return { text: 'Unknown outcome ' + code + '. Use one of ' + Object.keys(OUTCOMES).join(', ') + '.', error: true };
  const body = String(a.reply_text ?? '').trim().slice(0, 20000);
  if (!body) return { text: 'The reply text is empty.', error: true };
  const at = new Date(String(a.received_at ?? ''));
  if (isNaN(at.getTime())) return { text: 'received_at is not a date.', error: true };
  const gid = a.gmail_message_id ? String(a.gmail_message_id) : null;

  const { data: people, error: e1 } = await db.from('contacts').select('id, full_name').eq('email_key', email).limit(1);
  if (e1) throw new Error(e1.message);
  const c = people?.[0];
  if (!c) return { text: `${email} is not in the CRM, so nothing was stored. Only replies from people already in the CRM are recorded.` };
  if (gid) {
    const { data: seen } = await db.from('email_messages').select('id').eq('external_id', gid).limit(1);
    if (seen?.length) return { text: `Already stored: this reply from ${c.full_name} is in the CRM.` };
  }
  const { data: sent, error: e2 } = await db.from('touchpoints').select('id, touched_at, responded_at, response_excerpt, outcome_status')
    .eq('contact_id', c.id).in('touch_type', ['email', 'check_in']).eq('direction', 'outbound').lte('touched_at', at.toISOString())
    .order('touched_at', { ascending: false }).limit(1);
  if (e2) throw new Error(e2.message);
  const tp = sent?.[0];
  if (!tp) return { text: `The CRM has no email we sent to ${c.full_name} before this reply, so there is nothing to attach it to. Nothing was stored.` };
  const excerpt = body.slice(0, 400);
  if (tp.response_excerpt === excerpt) return { text: `Already stored: this reply from ${c.full_name} is in the CRM.` };

  // The outcome is set at once, as the CRM's own Gmail check does: the database's
  // outcome rules then schedule the follow-up. A person changes it in the CRM if it is wrong.
  const conf = a.confidence == null ? null : Math.min(1, Math.max(0, Number(a.confidence)));
  const { error: e3 } = await db.from('touchpoints').update({
    response_excerpt: excerpt, responded_at: at.toISOString(), ai_suggested_outcome: code, outcome_code: code,
    ai_confidence: Number.isFinite(conf) ? conf : null, outcome_status: 'confirmed', confirmed_at: new Date().toISOString(), updated_at: new Date().toISOString(),
    ai_reason: (`Claude, for ${me}: ` + String(a.reason ?? 'read from the reply')).slice(0, 500),
  }).eq('id', tp.id);
  if (e3) throw new Error(e3.message);
  const { error: e4 } = await db.from('email_messages').insert({
    contact_id: c.id, touchpoint_id: tp.id, mailbox: me, external_id: gid, direction: 'inbound', from_email: email,
    to_emails: [me], subject: null, body_text: body, sent_at: at.toISOString(), is_auto_reply: code === 'OUT_OF_OFFICE',
  });
  if (e4) throw new Error(e4.message);
  return { text: `Stored the reply from ${c.full_name} with the outcome ${OUTCOMES[code]}; the follow-up is scheduled from it. It shows under the bell in the CRM, where it can be changed.` };
}

const isDay = (s: unknown) => /^\d{4}-\d{2}-\d{2}$/.test(String(s ?? '')) && !isNaN(new Date(String(s)).getTime());
const evKey = (s: unknown) => String(s ?? '').toLowerCase().replace(/\b(the|annual|20\d\d)\b/g, ' ').replace(/[^a-z0-9]+/g, ' ').trim();

async function listEvents(db: Db, a: { from?: string; to?: string }) {
  const from = isDay(a.from) ? a.from : new Date(Date.now() - 120 * 864e5).toISOString().slice(0, 10);
  const to = isDay(a.to) ? a.to : new Date(Date.now() + 180 * 864e5).toISOString().slice(0, 10);
  const { data, error } = await db.from('events').select('id, name, start_on, format, city, state, attendance').gte('start_on', from).lte('start_on', to).order('start_on').limit(500);
  if (error) throw new Error(error.message);
  if (!data?.length) return `No events on the CRM's Events page between ${from} and ${to}.`;
  const { data: tps } = await db.from('touchpoints').select('event_id, contact_id').in('event_id', data.map((e: Db) => e.id)).limit(5000);
  const met = (id: number) => new Set((tps ?? []).filter((t: Db) => t.event_id === id).map((t: Db) => t.contact_id)).size;
  return data.map((e: Db) => `- ${e.start_on} ${e.name} (${e.format === 'virtual' ? 'online' : [e.city, e.state].filter(Boolean).join(', ') || 'in person'}): ${met(e.id)} people met, ${e.attendance || 'going'}`).join('\n');
}

async function recordEvent(db: Db, me: string, a: Record<string, unknown>) {
  const name = String(a.name ?? '').trim().slice(0, 300), status = String(a.status || 'going'), finder = a.finder_id ? String(a.finder_id) : null;
  if (!name || !isDay(a.date)) return { text: 'An event needs a name and a date (YYYY-MM-DD).', error: true };
  if (!['going', 'maybe', 'attended', 'not_going'].includes(status)) return { text: 'Unknown status ' + status + '.', error: true };
  const start = String(a.date), end = isDay(a.end_date) && String(a.end_date) > start ? String(a.end_date) : null;
  const state = /^[A-Za-z]{2}$/.test(String(a.state ?? '')) ? String(a.state).toUpperCase() : null;
  const kind = ['conference', 'networking', 'webinar', 'workshop', 'other'].includes(String(a.kind)) ? String(a.kind) : 'other';
  const format = a.format === 'virtual' ? 'virtual' : 'in_person', url = a.url ? String(a.url).slice(0, 1000) : null;
  // the same event already on the page: its Finder id, or the same or a close name within three days
  let same: Db = null;
  if (finder) { const { data, error } = await db.from('events').select('id, name, cost_usd, state, city').eq('finder_id', finder).limit(1); if (error) throw new Error(error.message); same = data?.[0] ?? null; }
  if (!same) {
    const lo = new Date(new Date(start).getTime() - 3 * 864e5).toISOString().slice(0, 10), hi = new Date(new Date(start).getTime() + 3 * 864e5).toISOString().slice(0, 10);
    const { data: near, error: e1 } = await db.from('events').select('id, name, cost_usd, state, city').gte('start_on', lo).lte('start_on', hi).limit(200);
    if (e1) throw new Error(e1.message);
    const k = evKey(name), words = new Set(k.split(' '));
    same = (near ?? []).find((e: Db) => evKey(e.name) === k)
      || (near ?? []).find((e: Db) => { const w = evKey(e.name).split(' '); return w.filter((x) => words.has(x)).length >= Math.max(2, Math.ceil(Math.min(w.length, words.size) * 0.7)); }) || null;
  }
  if (status === 'not_going') {
    if (!same) return { text: `"${name}" is not on the Events page, so there is nothing to take off.` };
    // deleted, unless people were met there: then the foreign keys refuse and it stays, marked Not going
    const { error } = await db.from('events').delete().eq('id', same.id);
    if (!error) return { text: `Took "${same.name}" off the Events page.` };
    const { error: e2 } = await db.from('events').update({ attendance: 'not_going' }).eq('id', same.id);
    if (e2) throw new Error(e2.message);
    return { text: `People were met at "${same.name}", so it stays with their history, marked Not going.` };
  }
  const counts = Number.isFinite(Number(a.people_met)) && a.people_met != null ? { people_met_reported: Math.round(Number(a.people_met)) } : {};
  const cost = a.cost_usd != null && Number.isFinite(Number(a.cost_usd)) ? Number(a.cost_usd) : null;
  if (same) {
    const { error } = await db.from('events').update({ attendance: status, start_on: start, end_on: end, ...counts, ...(finder ? { finder_id: finder } : {}), ...(url ? { source_url: url } : {}),
      ...(cost != null && (same.cost_usd == null || Number(same.cost_usd) === 0) ? { cost_usd: cost } : {}),
      ...(!same.state && state ? { state } : {}), ...(!same.city && a.city ? { city: String(a.city) } : {}) }).eq('id', same.id);
    if (error) throw new Error(error.message);
    return { text: `Already on the Events page as "${same.name}"; now ${status}.` };
  }
  const { error } = await db.from('events').insert({ name, event_type: kind, format, hosted_by_us: false, host_org: a.host ? String(a.host) : null, start_on: start, end_on: end,
    city: a.city ? String(a.city) : null, state, cost_usd: cost ?? 0, attendance: status, finder_id: finder, source_url: url, ...counts,
    notes: [a.notes ? String(a.notes).slice(0, 1000) : '', 'Added by Claude, for ' + me].filter(Boolean).join('\n') });
  if (error) throw new Error(error.message);
  return { text: `Added "${name}" (${start}) to the Events page, ${status}.` };
}

const yn = (v: unknown) => (v == null ? '' : v ? 'Y' : 'N');
async function listRfps(db: Db) {
  const { data, error } = await db.from('rfps').select('*, organizations(name)').order('due_on', { ascending: false }).limit(500);
  if (error) throw new Error(error.message);
  if (!data?.length) return 'The RFP log is empty.';
  return ['RFP Name / Issuer\tRFP Reference Number\tFinal Submission Date\tApproved for Submission\tReviewed By\tDate Reviewed\tSize of AUM\tConditions or Limitations\tNotes\tResponse\tDate Responded\tCorrespondence\tWON\tStatus\tWho won',
    ...data.map((r: Db) => [`${r.title} / ${r.organizations?.name ?? ''}`, r.reference_number, r.submitted_on || r.due_on, yn(r.approved_for_submission), r.reviewed_by, r.reviewed_on, r.est_mandate_aum, r.terms, r.notes,
      r.response || 'N', r.decision_on, r.correspondence, r.status === 'won' ? 'Y' : r.status === 'lost' ? 'N' : '', r.status, r.winner].map((v) => String(v ?? '').replace(/\s+/g, ' ')).join('\t'))].join('\n');
}

async function recordRfp(db: Db, me: string, a: Record<string, unknown>) {
  const title = String(a.rfp_name ?? '').trim().slice(0, 300), issuer = String(a.issuer ?? '').trim().slice(0, 300);
  if (!title || !issuer) return { text: 'An RFP needs its name and its issuer.', error: true };
  for (const k of ['final_submission_date', 'date_reviewed', 'date_responded']) if (a[k] != null && a[k] !== '' && !isDay(a[k])) return { text: k + ' must be YYYY-MM-DD.', error: true };
  const { data: orgs, error: e1 } = await db.from('organizations').select('id, name').ilike('name', issuer.replace(/[%_]/g, ' ')).limit(1);
  if (e1) throw new Error(e1.message);
  let org = orgs?.[0];
  if (!org) {
    const { data, error } = await db.from('organizations').insert({ name: issuer, segment_code: /foundation|nonprofit|charit|trust|endowment|society|association/i.test(issuer) ? 'ORG_NONPROFIT' : 'ORG_OTHER', legacy_ref: 'RFP tracker' }).select('id, name').single();
    if (error) throw new Error(error.message);
    org = data;
  }
  const ref = a.reference_number ? String(a.reference_number).trim() : null;
  let same: Db = null;
  if (ref) { const { data } = await db.from('rfps').select('id, status, submitted_on').eq('reference_number', ref).limit(1); same = data?.[0] ?? null; }
  if (!same) { const { data } = await db.from('rfps').select('id, status, submitted_on').eq('organization_id', org.id).ilike('title', title.replace(/[%_]/g, ' ')).limit(1); same = data?.[0] ?? null; }
  const given = (k: string) => a[k] !== undefined && a[k] !== null && a[k] !== '';
  const final = given('final_submission_date') ? String(a.final_submission_date) : null, today = new Date().toISOString().slice(0, 10);
  const status = a.won === 'Y' ? 'won' : a.won === 'N' ? 'lost' : given('status') ? String(a.status) : same ? same.status : final && final <= today && a.approved_for_submission === 'Y' ? 'submitted' : a.approved_for_submission === 'Y' ? 'intent_to_bid' : 'identified';
  const row: Db = { status, title, organization_id: org.id };
  if (ref) row.reference_number = ref;
  if (final) { if (['submitted', 'finalist', 'won', 'lost'].includes(status)) row.submitted_on = final; row.due_on = final; }
  if (given('approved_for_submission')) row.approved_for_submission = a.approved_for_submission === 'Y';
  if (given('date_responded')) row.decision_on = a.date_responded;
  if (given('date_reviewed')) row.reviewed_on = a.date_reviewed;
  if (given('size_of_aum') && Number.isFinite(Number(a.size_of_aum))) row.est_mandate_aum = Number(a.size_of_aum);
  for (const [k, col] of [['reviewed_by', 'reviewed_by'], ['conditions_or_limitations', 'terms'], ['notes', 'notes'], ['response', 'response'], ['correspondence', 'correspondence'],
    ['arrangement', 'mandate_type'], ['winner', 'winner'], ['how_we_scored', 'decision_notes'], ['url', 'source_url']]) if (given(k)) row[col] = String(a[k]).slice(0, 5000);
  const { error } = same ? await db.from('rfps').update(row).eq('id', same.id) : await db.from('rfps').insert(row);
  if (error) throw new Error(error.message);
  return { text: `${same ? 'Updated' : 'Added'} "${title}" (${org.name}) in the RFP log, ${status}. Everyone on the team sees it.` };
}

/** One MCP request (JSON-RPC 2.0) for the person `me`. Returns the response, or null for a notification. */
export async function rpc(db: Db, me: string, msg: Db) {
  const ok = (result: unknown) => ({ jsonrpc: '2.0', id: msg.id, result });
  const fail = (code: number, message: string) => ({ jsonrpc: '2.0', id: msg.id ?? null, error: { code, message } });
  if (!msg || msg.jsonrpc !== '2.0' || typeof msg.method !== 'string') return fail(-32600, 'Invalid request');
  if (msg.id === undefined) return null;   // notifications (e.g. notifications/initialized) need no answer
  switch (msg.method) {
    case 'initialize': {
      const asked = msg.params?.protocolVersion;
      return ok({ protocolVersion: PROTOCOLS.includes(asked) ? asked : PROTOCOLS[0], capabilities: { tools: {} },
        serverInfo: { name: 'gaard-crm', version: '1.0.0' },
        instructions: 'Gaard Capital CRM. Typical use: call outreach_waiting_for_reply, search Gmail for replies from those addresses, then call record_reply once per reply with the closest outcome. The team can change an outcome in the CRM.' });
    }
    case 'ping': return ok({});
    case 'tools/list': return ok({ tools: TOOLS });
    case 'tools/call': {
      const name = msg.params?.name, args = msg.params?.arguments ?? {};
      try {
        if (name === 'outreach_waiting_for_reply') return ok({ content: [{ type: 'text', text: await waiting(db, args) }] });
        if (name === 'find_contact') return ok({ content: [{ type: 'text', text: await find(db, args) }] });
        if (name === 'record_reply') { const r = await record(db, me, args); return ok({ content: [{ type: 'text', text: r.text }], isError: !!r.error }); }
        if (name === 'list_events') return ok({ content: [{ type: 'text', text: await listEvents(db, args) }] });
        if (name === 'record_event') { const r = await recordEvent(db, me, args); return ok({ content: [{ type: 'text', text: r.text }], isError: !!r.error }); }
        if (name === 'list_rfps') return ok({ content: [{ type: 'text', text: await listRfps(db) }] });
        if (name === 'record_rfp') { const r = await recordRfp(db, me, args); return ok({ content: [{ type: 'text', text: r.text }], isError: !!r.error }); }
        return fail(-32602, 'Unknown tool ' + name);
      } catch (err) {
        return ok({ content: [{ type: 'text', text: 'The CRM refused: ' + (err as Error).message }], isError: true });
      }
    }
    default: return fail(-32601, 'Method not found: ' + msg.method);
  }
}

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, mcp-protocol-version, mcp-session-id',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

/** The HTTP side (MCP "Streamable HTTP", answering each POST with plain JSON). */
export async function handle(req: Request, connect: () => Promise<Db>) {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: { ...cors, Allow: 'POST' } });
  const key = new URL(req.url).pathname.split('/').filter(Boolean).pop() ?? '';
  const db = await connect();
  const me = await personForKey(db, key);
  if (!me) return new Response('Unknown or disconnected connector key. Make a new one in the CRM: Settings > Connect your Claude.', { status: 401, headers: cors });
  let body: Db;
  try { body = await req.json(); } catch { return Response.json({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } }, { status: 400, headers: cors }); }
  const out = Array.isArray(body) ? (await Promise.all(body.map((m) => rpc(db, me, m)))).filter(Boolean) : await rpc(db, me, body);
  if (out === null || (Array.isArray(out) && !out.length)) return new Response(null, { status: 202, headers: cors });
  return Response.json(out, { headers: cors });
}

// deno-lint-ignore no-explicit-any
const D = (globalThis as any).Deno;
if (D?.serve) {
  D.serve((req: Request) => handle(req, async () => {
    const { createClient } = await import('npm:@supabase/supabase-js@2.45.4');
    return createClient(D.env.get('SUPABASE_URL'), D.env.get('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false } });
  }));
}
