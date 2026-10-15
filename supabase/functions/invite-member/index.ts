// invite-member: put a person on the Gaard CRM team list and email them an
// invitation. Called from Settings > Team when an admin presses Invite.
//
// Deploy: Supabase dashboard > Edge Functions > Deploy a new function > Via
// Editor, name it invite-member, paste this file, deploy. Then in the
// function's Details turn OFF "Verify JWT": the function checks the caller
// itself with is_admin(), which also requires the two-step code.
//
// The email is Supabase's "Invite user" email (Authentication > Emails). It
// only reaches people outside the Supabase organization once custom SMTP is
// set up (Authentication > Emails > SMTP Settings).

import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const apikey = req.headers.get('apikey') ?? Deno.env.get('SUPABASE_ANON_KEY')!;
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    // The caller, as themselves: row level security and is_admin() decide.
    const caller = createClient(url, apikey, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
      auth: { persistSession: false },
    });
    const { data: isAdmin, error: adminErr } = await caller.rpc('is_admin');
    if (adminErr || !isAdmin) return json({ error: 'Only an admin, signed in with the two-step code, can invite people.' }, 403);

    const { email, full_name, access_role = 'member', redirect_to } = await req.json();
    const e = String(email ?? '').trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e)) return json({ error: 'That email address does not look right.' }, 400);
    if (!['admin', 'member'].includes(access_role)) return json({ error: 'Unknown role.' }, 400);

    // 1. On the team list, written as the caller so the audit log names them.
    const { data: me } = await caller.rpc('my_access');
    const { data: rows } = await caller.from('team_members').select('id, email, auth_user_id');
    const existing = (rows ?? []).find((r) => String(r.email ?? '').toLowerCase() === e);
    const fields = { access_role, is_active: true, invited_at: new Date().toISOString(), invited_by: me?.id ?? null };
    const write = existing
      ? caller.from('team_members').update({ ...fields, ...(full_name ? { full_name } : {}) }).eq('id', existing.id)
      : caller.from('team_members').insert({ ...fields, email: e, full_name: full_name || e.split('@')[0] });
    const { error: writeErr } = await write;
    if (writeErr) return json({ error: writeErr.message }, 400);
    if (existing?.auth_user_id) return json({ status: 'joined' }); // already has an account: nothing to send

    // 2. The invitation email.
    const admin = createClient(url, service, { auth: { persistSession: false } });
    let { error: inviteErr } = await admin.auth.admin.inviteUserByEmail(e, { redirectTo: redirect_to });
    if (inviteErr && /already/i.test(inviteErr.message)) {
      // An account from an earlier invitation that was never used: start it again.
      const { data: list } = await admin.auth.admin.listUsers({ perPage: 1000 });
      const old = list?.users.find((u) => (u.email ?? '').toLowerCase() === e);
      if (old && !old.last_sign_in_at) {
        await admin.auth.admin.deleteUser(old.id);
        ({ error: inviteErr } = await admin.auth.admin.inviteUserByEmail(e, { redirectTo: redirect_to }));
      } else if (old) {
        return json({ status: 'joined' });
      }
    }
    if (inviteErr) return json({ error: 'Added to the team list, but the email could not be sent: ' + inviteErr.message }, 502);
    return json({ status: 'invited' });
  } catch (err) {
    return json({ error: String((err as Error)?.message ?? err) }, 500);
  }
});
