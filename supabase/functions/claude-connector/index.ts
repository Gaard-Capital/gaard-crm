// claude-connector: lets a team member's own Claude (claude.ai) put email
// replies into the CRM. It is an MCP server (Model Context Protocol, the way
// Claude talks to outside tools) with three narrow tools and nothing else:
//
//   outreach_waiting_for_reply  who we wrote to and have not heard back from
//   find_contact                look one person up by email or name
//   record_reply                store a reply and SUGGEST its outcome
//
// A reply recorded here does not change the follow-up schedule. It sets the
// letter's activity to "needs review" with the suggested outcome, exactly as
// the CRM's own Gmail check does, and appears under the bell; a person
// presses Confirm (or Change) in the CRM and only then the outcome rules run.
// Claude cannot delete, merge, confirm, send, or read anything else.
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
    description: 'Store a reply someone sent to one of our emails, with the outcome you suggest. It does not change anything else: the reply waits under the CRM bell until a person confirms or changes the outcome. ' +
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

  const conf = a.confidence == null ? null : Math.min(1, Math.max(0, Number(a.confidence)));
  const { error: e3 } = await db.from('touchpoints').update({
    response_excerpt: excerpt, responded_at: at.toISOString(), ai_suggested_outcome: code,
    ai_confidence: Number.isFinite(conf) ? conf : null, outcome_status: 'needs_review', updated_at: new Date().toISOString(),
    ai_reason: (`Claude, for ${me}: ` + String(a.reason ?? 'read from the reply')).slice(0, 500),
  }).eq('id', tp.id);
  if (e3) throw new Error(e3.message);
  const { error: e4 } = await db.from('email_messages').insert({
    contact_id: c.id, touchpoint_id: tp.id, mailbox: me, external_id: gid, direction: 'inbound', from_email: email,
    to_emails: [me], subject: null, body_text: body, sent_at: at.toISOString(), is_auto_reply: code === 'OUT_OF_OFFICE',
  });
  if (e4) throw new Error(e4.message);
  return { text: `Stored the reply from ${c.full_name}, suggested outcome: ${OUTCOMES[code]}. It waits under the bell in the CRM until someone confirms it; the follow-up is scheduled then.` };
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
        instructions: 'Gaard Capital CRM. Typical use: call outreach_waiting_for_reply, search Gmail for replies from those addresses, then call record_reply once per reply. Replies wait for a person to confirm them in the CRM.' });
    }
    case 'ping': return ok({});
    case 'tools/list': return ok({ tools: TOOLS });
    case 'tools/call': {
      const name = msg.params?.name, args = msg.params?.arguments ?? {};
      try {
        if (name === 'outreach_waiting_for_reply') return ok({ content: [{ type: 'text', text: await waiting(db, args) }] });
        if (name === 'find_contact') return ok({ content: [{ type: 'text', text: await find(db, args) }] });
        if (name === 'record_reply') { const r = await record(db, me, args); return ok({ content: [{ type: 'text', text: r.text }], isError: !!r.error }); }
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
